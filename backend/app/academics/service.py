"""Academic taxonomy administration. Every change is audited; taxonomy rows are retired, never deleted."""

from __future__ import annotations

import uuid
from collections.abc import Sequence
from typing import Any

from sqlalchemy import delete, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.academics.models import (
    AcademicGroup,
    Board,
    Chapter,
    Curriculum,
    EducationLevel,
    InstructionMedium,
    Subject,
    SubjectGroup,
    Topic,
)
from app.academics.schemas import SubjectGroupIn
from app.core.errors import Conflict, ErrorCode, NotFound, ValidationFailed
from app.core.pagination import MAX_LIST_ROWS
from app.core.request_info import ClientInfo
from app.identity.services.principal import Principal
from app.platform.audit import ActorType, record_audit

type Entity = (
    Board | Chapter | Curriculum | EducationLevel | InstructionMedium | Subject | Topic | AcademicGroup
)


def _conflict_message(exc: IntegrityError) -> str | None:
    text = str(exc.orig)
    if "uq_" in text or "unique" in text.lower():
        return "A record with the same key, slug or number already exists"
    return None


class AcademicsService:
    def __init__(self, session: AsyncSession, client: ClientInfo) -> None:
        self.session = session
        self.client = client

    # ------------------------------------------------------------------ reads

    async def list_rows[M: Entity](
        self, model: type[M], *conditions: Any, include_inactive: bool = True, order: Sequence[Any] = ()
    ) -> Sequence[M]:
        query = select(model).where(*conditions)
        if not include_inactive and hasattr(model, "is_active"):
            query = query.where(model.is_active)  # type: ignore[attr-defined]
        return (await self.session.execute(query.order_by(*order).limit(MAX_LIST_ROWS))).scalars().all()

    async def subjects(
        self,
        *,
        education_level_id: uuid.UUID | None = None,
        curriculum_id: uuid.UUID | None = None,
        family_key: str | None = None,
        include_inactive: bool = True,
    ) -> list[tuple[Subject, list[SubjectGroup]]]:
        conditions = []
        if education_level_id:
            conditions.append(Subject.education_level_id == education_level_id)
        if curriculum_id:
            conditions.append(Subject.curriculum_id == curriculum_id)
        if family_key:
            conditions.append(Subject.family_key == family_key)
        subjects = await self.list_rows(
            Subject,
            *conditions,
            include_inactive=include_inactive,
            order=(Subject.position, Subject.family_key, Subject.paper_number, Subject.id),
        )
        return await self._with_groups(subjects)

    async def subject(self, subject_id: uuid.UUID) -> tuple[Subject, list[SubjectGroup]]:
        subject = await self._get(Subject, subject_id, "Subject")
        return (await self._with_groups([subject]))[0]

    async def _with_groups(self, subjects: Sequence[Subject]) -> list[tuple[Subject, list[SubjectGroup]]]:
        ids = [s.id for s in subjects]
        links: dict[uuid.UUID, list[SubjectGroup]] = {i: [] for i in ids}
        if ids:
            rows = (
                (await self.session.execute(select(SubjectGroup).where(SubjectGroup.subject_id.in_(ids))))
                .scalars()
                .all()
            )
            for link in rows:
                links[link.subject_id].append(link)
        return [(s, links[s.id]) for s in subjects]

    async def chapters(
        self, subject_id: uuid.UUID, *, include_inactive: bool = True
    ) -> list[tuple[Chapter, list[Topic]]]:
        chapters = await self.list_rows(
            Chapter,
            Chapter.subject_id == subject_id,
            include_inactive=include_inactive,
            order=(Chapter.position, Chapter.number),
        )
        ids = [c.id for c in chapters]
        topics: dict[uuid.UUID, list[Topic]] = {i: [] for i in ids}
        if ids:
            query = (
                select(Topic)
                .where(Topic.chapter_id.in_(ids))
                .order_by(Topic.position, Topic.id)
                .limit(MAX_LIST_ROWS)
            )
            if not include_inactive:
                query = query.where(Topic.is_active)
            for topic in (await self.session.execute(query)).scalars():
                topics[topic.chapter_id].append(topic)
        return [(c, topics[c.id]) for c in chapters]

    # ------------------------------------------------------------------ writes

    async def create[M: Entity](self, actor: Principal, entity: M, kind: str) -> M:
        self.session.add(entity)
        await self._flush()
        self._audit(actor, f"{kind}.created", kind, entity.id, {"id": str(entity.id)})
        await self.session.commit()
        await self.session.refresh(entity)
        return entity

    async def patch[M: Entity](
        self, actor: Principal, model: type[M], entity_id: uuid.UUID, values: dict[str, Any], kind: str
    ) -> M:
        entity = await self._get(model, entity_id, kind.replace("_", " ").capitalize(), lock=True)
        for name, value in values.items():
            setattr(entity, name, value)
        await self._flush()
        self._audit(actor, f"{kind}.updated", kind, entity.id, {"fields": sorted(values)})
        await self.session.commit()
        await self.session.refresh(entity)
        return entity

    async def create_curriculum(self, actor: Principal, entity: Curriculum) -> Curriculum:
        if entity.is_current:
            await self._clear_current()
        return await self.create(actor, entity, "curriculum")

    async def patch_curriculum(
        self, actor: Principal, curriculum_id: uuid.UUID, values: dict[str, Any]
    ) -> Curriculum:
        if values.get("is_current"):
            await self._clear_current()
        return await self.patch(actor, Curriculum, curriculum_id, values, "curriculum")

    async def create_group(self, actor: Principal, entity: AcademicGroup) -> AcademicGroup:
        await self._require(EducationLevel, entity.education_level_id, "education_level_id")
        return await self.create(actor, entity, "academic_group")

    async def create_subject(
        self, actor: Principal, subject: Subject, groups: Sequence[SubjectGroupIn]
    ) -> tuple[Subject, list[SubjectGroup]]:
        await self._require(Curriculum, subject.curriculum_id, "curriculum_id")
        await self._require(EducationLevel, subject.education_level_id, "education_level_id")
        await self._check_groups(subject.education_level_id, groups)
        self.session.add(subject)
        await self._flush()
        links = self._link_groups(subject.id, groups)
        await self._flush()
        self._audit(actor, "subject.created", "subject", subject.id, {"slug": subject.slug})
        await self.session.commit()
        await self.session.refresh(subject)
        return subject, links

    async def patch_subject(
        self,
        actor: Principal,
        subject_id: uuid.UUID,
        values: dict[str, Any],
        groups: Sequence[SubjectGroupIn] | None,
    ) -> tuple[Subject, list[SubjectGroup]]:
        subject = await self._get(Subject, subject_id, "Subject", lock=True)
        for name, value in values.items():
            setattr(subject, name, value)
        if groups is not None:
            await self._check_groups(subject.education_level_id, groups)
            await self.session.execute(delete(SubjectGroup).where(SubjectGroup.subject_id == subject_id))
            await self._flush()
            self._link_groups(subject_id, groups)
        await self._flush()
        fields = sorted(values) + (["groups"] if groups is not None else [])
        self._audit(actor, "subject.updated", "subject", subject.id, {"fields": fields})
        await self.session.commit()
        await self.session.refresh(subject)
        return (await self._with_groups([subject]))[0]

    async def create_chapter(self, actor: Principal, chapter: Chapter) -> Chapter:
        await self._require(Subject, chapter.subject_id, "subject_id")
        return await self.create(actor, chapter, "chapter")

    async def create_topic(self, actor: Principal, topic: Topic) -> Topic:
        await self._require(Chapter, topic.chapter_id, "chapter_id")
        return await self.create(actor, topic, "topic")

    # ------------------------------------------------------------------ helpers

    async def _clear_current(self) -> None:
        await self.session.execute(update(Curriculum).where(Curriculum.is_current).values(is_current=False))
        await self.session.flush()

    async def _check_groups(self, level_id: uuid.UUID, groups: Sequence[SubjectGroupIn]) -> None:
        ids = {g.group_id for g in groups}
        if len(ids) != len(groups):
            raise ValidationFailed("A group can be listed once per subject", field="groups")
        if not ids:
            return
        found = (
            (
                await self.session.execute(
                    select(AcademicGroup.id).where(
                        AcademicGroup.id.in_(ids), AcademicGroup.education_level_id == level_id
                    )
                )
            )
            .scalars()
            .all()
        )
        if len(found) != len(ids):
            raise ValidationFailed("Every group must belong to the subject's education level", field="groups")

    def _link_groups(self, subject_id: uuid.UUID, groups: Sequence[SubjectGroupIn]) -> list[SubjectGroup]:
        links = [
            SubjectGroup(subject_id=subject_id, group_id=g.group_id, offering=g.offering.value)
            for g in groups
        ]
        self.session.add_all(links)
        return links

    async def _require(self, model: Any, entity_id: uuid.UUID, field: str) -> None:
        if await self.session.get(model, entity_id) is None:
            raise ValidationFailed("Unknown reference", field=field)

    async def _get[M](self, model: type[M], entity_id: uuid.UUID, label: str, *, lock: bool = False) -> M:
        entity = await self.session.get(model, entity_id, with_for_update=lock, populate_existing=lock)
        if entity is None:
            raise NotFound(f"{label} not found")
        return entity

    async def _flush(self) -> None:
        try:
            await self.session.flush()
        except IntegrityError as exc:
            await self.session.rollback()
            if message := _conflict_message(exc):
                raise Conflict(message, code=ErrorCode.CONFLICT) from exc
            raise ValidationFailed("The values violate a taxonomy rule") from exc

    def _audit(
        self, actor: Principal, action: str, entity_type: str, entity_id: uuid.UUID, after: dict[str, Any]
    ) -> None:
        record_audit(
            self.session,
            action=action,
            actor_type=ActorType.STAFF,
            actor_user_id=actor.user_id,
            entity_type=entity_type,
            entity_id=entity_id,
            after=after,
            ip=self.client.ip,
            user_agent=self.client.user_agent,
        )

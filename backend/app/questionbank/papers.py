"""Question papers (historical board and test papers) and question error reports."""

from __future__ import annotations

import uuid
from collections.abc import Sequence
from datetime import UTC, datetime
from typing import Any

from sqlalchemy import delete, func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.academics.models import AcademicGroup, Board, EducationLevel, InstructionMedium, Subject
from app.core.errors import Conflict, ErrorCode, NotFound, ValidationFailed
from app.core.request_info import ClientInfo
from app.core.resources import Resources
from app.entitlements.models import EntitlementDefinition
from app.identity.services.principal import Principal
from app.platform.audit import ActorType, record_audit
from app.platform.outbox import publish_event
from app.questionbank.enforcement import paper_publishability, withdraw_question_content_if_unpublishable
from app.questionbank.models import (
    PaperStatus,
    Question,
    QuestionPaper,
    QuestionPaperBoard,
    QuestionPaperItem,
    QuestionReport,
    QuestionStatus,
    ReportStatus,
)
from app.questionbank.schemas import PaperIn, PaperItemIn, PaperPatch
from app.questionbank.service import QuestionService

PAPER_PUBLISHED = "question_paper.published"
_EDITABLE_FIELDS = (
    "academic_group_id",
    "instruction_medium_id",
    "exam_year",
    "exam_kind",
    "section",
    "title",
    "total_marks",
    "duration_minutes",
    "access_level",
    "required_entitlement_key",
)


def board_set_key(board_keys: Sequence[str]) -> str:
    """Sorted board keys joined by ',' (or 'all'): makes the paper's uniqueness constraint possible."""
    return ",".join(sorted(set(board_keys))) or "all"


class PaperService:
    def __init__(self, session: AsyncSession, resources: Resources, client: ClientInfo) -> None:
        self.session = session
        self.resources = resources
        self.client = client

    # ------------------------------------------------------------------ reads

    async def get(self, paper_id: uuid.UUID, *, lock: bool = False) -> QuestionPaper:
        paper = await self.session.get(QuestionPaper, paper_id, with_for_update=lock, populate_existing=lock)
        if paper is None:
            raise NotFound("Question paper not found")
        return paper

    async def boards(self, paper_id: uuid.UUID) -> list[uuid.UUID]:
        rows = await self.session.execute(
            select(QuestionPaperBoard.board_id).where(QuestionPaperBoard.paper_id == paper_id)
        )
        return sorted(rows.scalars())

    async def items(self, paper_id: uuid.UUID) -> Sequence[QuestionPaperItem]:
        rows = await self.session.execute(
            select(QuestionPaperItem)
            .where(QuestionPaperItem.paper_id == paper_id)
            .order_by(QuestionPaperItem.position)
        )
        return rows.scalars().all()

    async def search(
        self,
        *,
        subject_id: uuid.UUID | None,
        exam_year: int | None,
        status: str | None,
        offset: int,
        limit: int,
    ) -> tuple[list[QuestionPaper], int]:
        query = select(QuestionPaper)
        for column, value in (
            (QuestionPaper.subject_id, subject_id),
            (QuestionPaper.exam_year, exam_year),
            (QuestionPaper.status, status),
        ):
            if value is not None:
                query = query.where(column == value)
        total = (await self.session.execute(select(func.count()).select_from(query.subquery()))).scalar_one()
        rows = (
            await self.session.execute(
                query.order_by(QuestionPaper.exam_year.desc(), QuestionPaper.id).offset(offset).limit(limit)
            )
        ).scalars()
        return list(rows), total

    # ------------------------------------------------------------------ writes

    async def create(self, actor: Principal, body: PaperIn) -> QuestionPaper:
        await self._check_references(body.model_dump())
        keys = await self._board_keys(body.board_ids)
        paper = QuestionPaper(
            created_by=actor.user_id,
            board_set_key=board_set_key(keys),
            **body.model_dump(exclude={"board_ids"}, mode="json"),
        )
        self.session.add(paper)
        await self._flush(
            "A paper for this level, subject, year, exam kind, section and boards already exists"
        )
        self.session.add_all(
            QuestionPaperBoard(paper_id=paper.id, board_id=b) for b in dict.fromkeys(body.board_ids)
        )
        self._audit(actor, "question_paper.created", paper.id, after={"year": paper.exam_year})
        await self.session.commit()
        await self.session.refresh(paper)
        return paper

    async def update(self, actor: Principal, paper_id: uuid.UUID, body: PaperPatch) -> QuestionPaper:
        paper = await self.get(paper_id, lock=True)
        self._ensure_draft(paper)
        values = body.model_dump(exclude_unset=True, mode="json")
        board_ids = values.pop("board_ids", None)
        await self._check_references(values)
        for name, value in values.items():
            if name in _EDITABLE_FIELDS:
                setattr(paper, name, value)
        if paper.access_level == "entitled" and not paper.required_entitlement_key:
            raise ValidationFailed(
                "Entitled papers need required_entitlement_key", field="required_entitlement_key"
            )
        if board_ids is not None:
            keys = await self._board_keys([uuid.UUID(b) for b in board_ids])
            await self.session.execute(
                delete(QuestionPaperBoard).where(QuestionPaperBoard.paper_id == paper.id)
            )
            await self.session.flush()
            self.session.add_all(
                QuestionPaperBoard(paper_id=paper.id, board_id=uuid.UUID(b)) for b in dict.fromkeys(board_ids)
            )
            paper.board_set_key = board_set_key(keys)
        await self._flush(
            "A paper for this level, subject, year, exam kind, section and boards already exists"
        )
        self._audit(
            actor, "question_paper.updated", paper.id, after={"fields": sorted(body.model_fields_set)}
        )
        await self.session.commit()
        await self.session.refresh(paper)
        return paper

    async def set_items(
        self, actor: Principal, paper_id: uuid.UUID, items: Sequence[PaperItemIn]
    ) -> Sequence[QuestionPaperItem]:
        paper = await self.get(paper_id, lock=True)
        self._ensure_draft(paper)
        question_ids = [i.question_id for i in items]
        if len(set(question_ids)) != len(question_ids):
            raise ValidationFailed("A question can appear once in a paper", field="items")
        if len({i.item_number for i in items}) != len(items):
            raise ValidationFailed("Item numbers must be unique within a paper", field="items")
        if question_ids:
            found = (
                await self.session.execute(
                    select(func.count()).where(Question.id.in_(question_ids), Question.deleted_at.is_(None))
                )
            ).scalar_one()
            if found != len(question_ids):
                raise ValidationFailed("Unknown question in items", field="items")
            other_subject = (
                await self.session.execute(
                    select(func.count()).where(
                        Question.id.in_(question_ids), Question.subject_id != paper.subject_id
                    )
                )
            ).scalar_one()
            if other_subject:
                raise ValidationFailed("Every question must belong to the paper's subject", field="items")
        await self.session.execute(delete(QuestionPaperItem).where(QuestionPaperItem.paper_id == paper.id))
        await self.session.flush()
        self.session.add_all(
            QuestionPaperItem(
                paper_id=paper.id,
                question_id=item.question_id,
                item_number=item.item_number,
                position=position,
                marks=item.marks,
            )
            for position, item in enumerate(items)
        )
        self._audit(actor, "question_paper.items_changed", paper.id, after={"count": len(items)})
        await self.session.commit()
        return await self.items(paper.id)

    async def publish(self, actor: Principal, paper_id: uuid.UUID) -> QuestionPaper:
        paper = await self.get(paper_id, lock=True)
        if paper.status not in (PaperStatus.DRAFT, PaperStatus.ARCHIVED):
            raise _transition(paper, "published")
        items = await self.items(paper.id)
        reasons: list[str] = []
        if not items:
            reasons.append("NO_ITEMS")
        unpublished = (
            await self.session.execute(
                select(func.count()).where(
                    Question.id.in_([i.question_id for i in items]),
                    Question.status != QuestionStatus.PUBLISHED,
                )
            )
        ).scalar_one()
        if unpublished:
            reasons.append("ITEMS_NOT_PUBLISHED")
        gate = await paper_publishability(
            self.session, paper.id, territory=self.resources.settings.content_launch_territory
        )
        reasons.extend(r.value for r in gate.reasons)
        if reasons:
            raise Conflict(
                "This paper cannot be published yet",
                code=ErrorCode.CONTENT_NOT_PUBLISHABLE,
                details={"reasons": reasons},
            )
        paper.status = PaperStatus.PUBLISHED
        paper.published_at = datetime.now(UTC)
        publish_event(
            self.session,
            event_type=PAPER_PUBLISHED,
            aggregate_type="question_paper",
            aggregate_id=paper.id,
            payload={"paper_id": str(paper.id)},
        )
        self._audit(actor, "question_paper.published", paper.id)
        await self.session.commit()
        await self.session.refresh(paper)
        return paper

    async def archive(self, actor: Principal, paper_id: uuid.UUID, reason: str) -> QuestionPaper:
        paper = await self.get(paper_id, lock=True)
        if paper.status == PaperStatus.ARCHIVED:
            raise _transition(paper, "archived")
        before = paper.status
        paper.status = PaperStatus.ARCHIVED
        self._audit(actor, "question_paper.archived", paper.id, before={"status": before}, reason=reason)
        await self.session.flush()
        # Questions that stayed published on this paper's rights may no longer pass without it.
        item_ids = (
            (
                await self.session.execute(
                    select(QuestionPaperItem.question_id).where(QuestionPaperItem.paper_id == paper.id)
                )
            )
            .scalars()
            .all()
        )
        for question_id in sorted(item_ids):
            await withdraw_question_content_if_unpublishable(
                self.session,
                "question",
                question_id,
                territory=self.resources.settings.content_launch_territory,
                actor_user_id=actor.user_id,
                reason=reason,
            )
        await self.session.commit()
        await self.session.refresh(paper)
        return paper

    # ------------------------------------------------------------------ helpers

    @staticmethod
    def _ensure_draft(paper: QuestionPaper) -> None:
        if paper.status != PaperStatus.DRAFT:
            raise Conflict(
                "Only draft papers can be edited",
                code=ErrorCode.RECORD_LOCKED,
                details={"status": paper.status},
            )

    async def _board_keys(self, board_ids: Sequence[uuid.UUID]) -> list[str]:
        ids = set(board_ids)
        if not ids:
            return []
        rows = (await self.session.execute(select(Board.key).where(Board.id.in_(ids)))).scalars().all()
        if len(rows) != len(ids):
            raise ValidationFailed("Unknown board", field="board_ids")
        return list(rows)

    async def _check_references(self, values: dict[str, Any]) -> None:
        checks = (
            ("education_level_id", EducationLevel),
            ("subject_id", Subject),
            ("academic_group_id", AcademicGroup),
            ("instruction_medium_id", InstructionMedium),
        )
        for field, model in checks:
            if values.get(field) is not None and await self.session.get(model, values[field]) is None:
                raise ValidationFailed("Unknown reference", field=field)
        key = values.get("required_entitlement_key")
        if key is not None and await self.session.get(EntitlementDefinition, key) is None:
            raise ValidationFailed("Unknown entitlement", field="required_entitlement_key")
        if "subject_id" in values and "education_level_id" in values:
            subject = await self.session.get(Subject, values["subject_id"])
            if subject is not None and subject.education_level_id != values["education_level_id"]:
                raise ValidationFailed(
                    "The subject does not belong to this education level", field="subject_id"
                )

    async def _flush(self, conflict_message: str) -> None:
        try:
            await self.session.flush()
        except IntegrityError as exc:
            await self.session.rollback()
            if "uq_question_papers" in str(exc.orig):
                raise Conflict(conflict_message, code=ErrorCode.CONFLICT) from exc
            raise ValidationFailed("The values violate a paper rule") from exc

    def _audit(
        self,
        actor: Principal,
        action: str,
        entity_id: uuid.UUID,
        *,
        before: dict[str, Any] | None = None,
        after: dict[str, Any] | None = None,
        reason: str | None = None,
    ) -> None:
        record_audit(
            self.session,
            action=action,
            actor_type=ActorType.STAFF,
            actor_user_id=actor.user_id,
            entity_type="question_paper",
            entity_id=entity_id,
            before=before,
            after=after,
            reason=reason,
            ip=self.client.ip,
            user_agent=self.client.user_agent,
        )


def _transition(paper: QuestionPaper, action: str) -> Conflict:
    return Conflict(
        f"A {paper.status} paper cannot be {action}",
        code=ErrorCode.INVALID_STATE_TRANSITION,
        details={"status": paper.status},
    )


# ------------------------------------------------------------------ reports


class ReportService:
    def __init__(self, session: AsyncSession, client: ClientInfo) -> None:
        self.session = session
        self.client = client

    async def create(
        self, user_id: uuid.UUID, question_id: uuid.UUID, reason: str, body: str | None
    ) -> QuestionReport:
        question = await self.session.get(Question, question_id)
        if question is None or question.status != QuestionStatus.PUBLISHED or question.deleted_at is not None:
            raise NotFound("Question not found")
        existing = (
            await self.session.execute(
                select(func.count()).where(
                    QuestionReport.question_id == question_id,
                    QuestionReport.user_id == user_id,
                    QuestionReport.status == ReportStatus.OPEN,
                )
            )
        ).scalar_one()
        if existing:
            raise Conflict(
                "You already reported this question; we're looking into it", code=ErrorCode.CONFLICT
            )
        report = QuestionReport(question_id=question_id, user_id=user_id, reason=reason, body=body or None)
        self.session.add(report)
        await self.session.commit()
        await self.session.refresh(report)
        return report

    async def queue(self, *, status: str, offset: int, limit: int) -> tuple[list[QuestionReport], int]:
        query = select(QuestionReport).where(QuestionReport.status == status)
        total = (await self.session.execute(select(func.count()).select_from(query.subquery()))).scalar_one()
        rows = (
            await self.session.execute(
                query.order_by(QuestionReport.created_at, QuestionReport.id).offset(offset).limit(limit)
            )
        ).scalars()
        return list(rows), total

    async def resolve(
        self,
        actor: Principal,
        report_id: uuid.UUID,
        *,
        decision: str,
        hide_until_fixed: bool,
        reason: str,
        questions: QuestionService,
    ) -> QuestionReport:
        report = await self.session.get(QuestionReport, report_id, with_for_update=True)
        if report is None:
            raise NotFound("Report not found")
        if report.status != ReportStatus.OPEN:
            raise Conflict(
                "This report has already been resolved",
                code=ErrorCode.INVALID_STATE_TRANSITION,
                details={"status": report.status},
            )
        report.status = ReportStatus.ACCEPTED if decision == "accepted" else ReportStatus.REJECTED
        report.resolved_by = actor.user_id
        report.resolved_at = datetime.now(UTC)
        if decision == "accepted":
            await questions.reopen_for_fix(actor, report.question_id, note=reason, hide=hide_until_fixed)
        record_audit(
            self.session,
            action=f"question_report.{decision}",
            actor_type=ActorType.STAFF,
            actor_user_id=actor.user_id,
            entity_type="question_report",
            entity_id=report.id,
            after={
                "question_id": str(report.question_id),
                "hidden": hide_until_fixed and decision == "accepted",
            },
            reason=reason,
            ip=self.client.ip,
            user_agent=self.client.user_agent,
        )
        await self.session.commit()
        await self.session.refresh(report)
        return report

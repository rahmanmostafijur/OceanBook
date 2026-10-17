"""Question authoring and the editorial workflow (docs/architecture/08 §4).

Editable content lives in `question_revisions.snapshot`. Publishing a revision materialises it into the
live tables, so students keep seeing the published version while an edit of it is in review.
"""

from __future__ import annotations

import uuid
from collections.abc import Iterator, Sequence
from datetime import UTC, datetime
from typing import Any

from sqlalchemy import delete, func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.academics.models import Chapter, EducationLevel, Subject, Topic
from app.core.errors import Conflict, ErrorCode, Forbidden, NotFound, ValidationFailed
from app.core.logging import get_logger
from app.core.request_info import ClientInfo
from app.core.resources import Resources
from app.entitlements.models import EntitlementDefinition
from app.identity.services.principal import Principal
from app.media.models import MediaAsset
from app.platform.audit import ActorType, record_audit
from app.platform.outbox import publish_event
from app.questionbank import contentdoc
from app.questionbank.contentdoc import ContentDoc
from app.questionbank.enforcement import question_publishability
from app.questionbank.models import (
    Question,
    QuestionOption,
    QuestionOptionTranslation,
    QuestionPart,
    QuestionPartTranslation,
    QuestionReview,
    QuestionRevision,
    QuestionStatus,
    QuestionTranslation,
    ReviewDecision,
    RevisionStatus,
    Stimulus,
    StimulusTranslation,
)
from app.questionbank.rules import QuestionContent, completeness_issues, content_hash

QUESTION_PUBLISHED = "question.published"
log = get_logger(__name__)
EDITABLE_REVISIONS = frozenset({RevisionStatus.DRAFT, RevisionStatus.CHANGES_REQUESTED})
_LIVE_OR_DONE = frozenset({RevisionStatus.PUBLISHED, RevisionStatus.SUPERSEDED})


def iter_docs(content: QuestionContent) -> Iterator[ContentDoc]:
    for translation in content.translations.values():
        yield from (
            d
            for d in (
                translation.stem,
                translation.explanation,
                translation.model_answer,
                translation.marking_guidance,
            )
            if d
        )
    for option in content.options:
        yield from option.content.values()
    for part in content.parts:
        yield from part.prompt.values()
        yield from (part.model_answer or {}).values()
        yield from (part.marking_guidance or {}).values()


def _invalid(message: str, field: str, **details: Any) -> ValidationFailed:
    return ValidationFailed(message, field=field, details=details)


class QuestionService:
    def __init__(self, session: AsyncSession, resources: Resources, client: ClientInfo) -> None:
        self.session = session
        self.resources = resources
        self.client = client

    # ------------------------------------------------------------------ reads

    async def get(self, question_id: uuid.UUID, *, lock: bool = False) -> Question:
        question = await self.session.get(Question, question_id, with_for_update=lock, populate_existing=lock)
        if question is None or question.deleted_at is not None:
            raise NotFound("Question not found")
        return question

    async def revision(self, question: Question, number: int | None = None) -> QuestionRevision:
        number = number or question.latest_revision
        revision = (
            await self.session.execute(
                select(QuestionRevision).where(
                    QuestionRevision.question_id == question.id, QuestionRevision.revision == number
                )
            )
        ).scalar_one_or_none()
        if revision is None:
            raise NotFound("Revision not found")
        return revision

    async def revisions(self, question: Question) -> Sequence[QuestionRevision]:
        rows = await self.session.execute(
            select(QuestionRevision)
            .where(QuestionRevision.question_id == question.id)
            .order_by(QuestionRevision.revision.desc())
        )
        return rows.scalars().all()

    async def reviews(self, question: Question) -> Sequence[QuestionReview]:
        rows = await self.session.execute(
            select(QuestionReview)
            .where(QuestionReview.question_id == question.id)
            .order_by(QuestionReview.created_at.desc())
        )
        return rows.scalars().all()

    async def search(
        self,
        *,
        status: str | None,
        subject_id: uuid.UUID | None,
        chapter_id: uuid.UUID | None,
        type_: str | None,
        created_by: uuid.UUID | None,
        needs_review: bool,
        offset: int,
        limit: int,
    ) -> tuple[list[tuple[Question, str]], int]:
        query = select(Question).where(Question.deleted_at.is_(None))
        if status:
            query = query.where((Question.status == status) | (Question.pending_status == status))
        if needs_review:
            query = query.where(
                (Question.status == QuestionStatus.IN_REVIEW)
                | (Question.pending_status == RevisionStatus.IN_REVIEW)
            )
        for column, value in (
            (Question.subject_id, subject_id),
            (Question.chapter_id, chapter_id),
            (Question.type, type_),
            (Question.created_by, created_by),
        ):
            if value is not None:
                query = query.where(column == value)
        total = (await self.session.execute(select(func.count()).select_from(query.subquery()))).scalar_one()
        rows = (
            (
                await self.session.execute(
                    query.order_by(Question.updated_at.desc(), Question.id).offset(offset).limit(limit)
                )
            )
            .scalars()
            .all()
        )
        stems: dict[uuid.UUID, str] = {}
        if rows:
            revisions = await self.session.execute(
                select(QuestionRevision)
                .join(
                    Question,
                    (Question.id == QuestionRevision.question_id)
                    & (Question.latest_revision == QuestionRevision.revision),
                )
                .where(Question.id.in_([q.id for q in rows]))
            )
            for rev in revisions.scalars():
                stems[rev.question_id] = self._stem_text(rev.snapshot)
        return [(q, stems.get(q.id, "")) for q in rows], total

    @staticmethod
    def _stem_text(snapshot: dict[str, Any]) -> str:
        translations = snapshot.get("translations", {})
        entry = translations.get(snapshot.get("source_locale", "")) or next(iter(translations.values()), None)
        return contentdoc.plain_text(contentdoc.parse(entry["stem"])) if entry else ""

    # ------------------------------------------------------------------ authoring

    async def create(self, actor: Principal, content: QuestionContent, change_note: str | None) -> Question:
        await self._check_references(content)
        question = Question(
            created_by=actor.user_id,
            content_hash=content_hash(content),
            **self._columns(content),
        )
        self.session.add(question)
        await self._flush()
        self.session.add(
            QuestionRevision(
                question_id=question.id,
                revision=1,
                snapshot=content.model_dump(mode="json"),
                status=RevisionStatus.DRAFT,
                change_note=change_note,
                changed_by=actor.user_id,
                editor_ids=[str(actor.user_id)],
            )
        )
        self._audit(actor, "question.created", question.id, after={"type": question.type})
        await self.session.commit()
        await self.session.refresh(question)
        return question

    async def update(
        self, actor: Principal, question_id: uuid.UUID, content: QuestionContent, change_note: str | None
    ) -> Question:
        question = await self.get(question_id, lock=True)
        if _shelved(question):
            raise _locked(question, "Restore the question before editing it")
        latest = await self.revision(question)
        if content.type.value != question.type:
            raise _invalid("A question's type cannot change; create a new question", "content.type")
        await self._check_references(content)
        if latest.status in EDITABLE_REVISIONS:
            latest.snapshot = content.model_dump(mode="json")
            latest.change_note = change_note or latest.change_note
            latest.changed_by = actor.user_id
            latest.editor_ids = sorted({*latest.editor_ids, str(actor.user_id)})
            if question.version == 0:
                self._apply_columns(question, content)
        elif latest.status in _LIVE_OR_DONE:
            # An edit of published content starts a new revision; the live version stays untouched.
            latest = await self._new_revision(question, actor, content.model_dump(mode="json"), change_note)
            question.pending_status = RevisionStatus.DRAFT
        else:
            raise _locked(
                question, "This revision is awaiting review; ask a reviewer to request changes first"
            )
        self._audit(actor, "question.updated", question.id, after={"revision": latest.revision})
        await self._flush()
        await self.session.commit()
        await self.session.refresh(question)
        return question

    async def _new_revision(
        self,
        question: Question,
        actor: Principal,
        snapshot: dict[str, Any],
        change_note: str | None,
        *,
        authored: bool = True,
    ) -> QuestionRevision:
        """Start the next revision. `authored=False` is for copies nobody wrote (restore, report triage):
        the acting user is not an editor of it, so separation of duties does not bar them from reviewing."""
        number = (
            await self.session.execute(
                select(func.max(QuestionRevision.revision)).where(QuestionRevision.question_id == question.id)
            )
        ).scalar_one() + 1
        revision = QuestionRevision(
            question_id=question.id,
            revision=number,
            snapshot=snapshot,
            status=RevisionStatus.DRAFT,
            change_note=change_note,
            changed_by=actor.user_id,
            editor_ids=[str(actor.user_id)] if authored else [],
        )
        self.session.add(revision)
        question.latest_revision = number
        return revision

    # ------------------------------------------------------------------ workflow

    async def submit(self, actor: Principal, question_id: uuid.UUID) -> Question:
        question = await self.get(question_id, lock=True)
        revision = await self.revision(question)
        if revision.status not in EDITABLE_REVISIONS or _shelved(question):
            raise _transition(question, revision, "submitted for review")
        content = QuestionContent.model_validate(revision.snapshot)
        issues = completeness_issues(content)
        if issues:
            raise ValidationFailed("The question is incomplete", field="content", details={"issues": issues})
        await self._check_references(content)
        self._set_status(question, revision, RevisionStatus.IN_REVIEW)
        self._audit(actor, "question.submitted", question.id, after={"revision": revision.revision})
        await self.session.commit()
        await self.session.refresh(question)
        return question

    async def review(
        self, actor: Principal, question_id: uuid.UUID, decision: ReviewDecision, comment: str | None
    ) -> Question:
        question = await self.get(question_id, lock=True)
        revision = await self.revision(question)
        if revision.status != RevisionStatus.IN_REVIEW or _shelved(question):
            raise _transition(question, revision, "reviewed")
        if str(actor.user_id) in revision.editor_ids:
            raise Forbidden(
                "A question must be reviewed by someone who did not write or edit it",
                code=ErrorCode.SELF_VERIFICATION_FORBIDDEN,
            )
        self.session.add(
            QuestionReview(
                question_id=question.id,
                revision=revision.revision,
                reviewer_id=actor.user_id,
                decision=decision.value,
                comment=comment,
            )
        )
        match decision:
            case ReviewDecision.APPROVE:
                self._set_status(question, revision, RevisionStatus.APPROVED)
                question.reviewed_by = actor.user_id
            case ReviewDecision.REQUEST_CHANGES:
                self._set_status(question, revision, RevisionStatus.CHANGES_REQUESTED)
            case ReviewDecision.REJECT:
                self._reject(question, revision)
        self._audit(
            actor,
            f"question.review_{decision.value}",
            question.id,
            after={"revision": revision.revision},
            reason=comment,
        )
        await self.session.commit()
        await self.session.refresh(question)
        return question

    def _reject(self, question: Question, revision: QuestionRevision) -> None:
        """Reject discards the revision. If the question is live, the live version carries on; if nothing is
        live (never published, or hidden), the question is archived so it cannot get stuck in review."""
        revision.status = RevisionStatus.SUPERSEDED
        if question.status != QuestionStatus.PUBLISHED:
            question.status = QuestionStatus.ARCHIVED
        question.pending_status = None

    async def publish(
        self, actor: Principal, question_id: uuid.UUID, *, acknowledge_duplicates: bool
    ) -> Question:
        question = await self.get(question_id, lock=True)
        revision = await self.revision(question)
        if revision.status != RevisionStatus.APPROVED or _shelved(question):
            raise _transition(question, revision, "published")
        approvals = (
            (
                await self.session.execute(
                    select(QuestionReview.reviewer_id).where(
                        QuestionReview.question_id == question.id,
                        QuestionReview.revision == revision.revision,
                        QuestionReview.decision == ReviewDecision.APPROVE,
                    )
                )
            )
            .scalars()
            .all()
        )
        if not any(r is not None and str(r) not in revision.editor_ids for r in approvals):
            raise _not_publishable("NO_INDEPENDENT_APPROVAL")
        content = QuestionContent.model_validate(revision.snapshot)
        if issues := completeness_issues(content):
            raise _not_publishable(*issues)
        await self._check_references(content)
        if content.stimulus_id is not None:
            # Serialise with StimulusService.replace: the passage cannot change under a publish.
            await self.session.get(
                Stimulus, content.stimulus_id, with_for_update=True, populate_existing=True
            )
        await self._materialise(question, content)
        await self.session.flush()
        gate = await question_publishability(
            self.session, question, territory=self.resources.settings.content_launch_territory
        )
        if not gate.publishable:
            raise _not_publishable(*(r.value for r in gate.reasons))
        duplicates = await self._duplicates(question, content)
        if duplicates and not acknowledge_duplicates:
            raise _not_publishable("DUPLICATE_QUESTION", duplicate_of=[str(d) for d in duplicates])

        previous = (
            await self.session.execute(
                select(QuestionRevision).where(
                    QuestionRevision.question_id == question.id,
                    QuestionRevision.status == RevisionStatus.PUBLISHED,
                )
            )
        ).scalars()
        for old in previous:
            old.status = RevisionStatus.SUPERSEDED
        revision.status = RevisionStatus.PUBLISHED
        question.version = revision.revision
        question.status = QuestionStatus.PUBLISHED
        question.pending_status = None
        question.published_by = actor.user_id
        question.published_at = datetime.now(UTC)
        publish_event(
            self.session,
            event_type=QUESTION_PUBLISHED,
            aggregate_type="question",
            aggregate_id=question.id,
            payload={"question_id": str(question.id), "version": question.version},
        )
        self._audit(actor, "question.published", question.id, after={"version": question.version})
        await self.session.commit()
        await self.session.refresh(question)
        return question

    async def archive(self, actor: Principal, question_id: uuid.UUID, reason: str) -> Question:
        question = await self.get(question_id, lock=True)
        if question.status == QuestionStatus.ARCHIVED:
            raise _transition(question, await self.revision(question), "archived")
        before = question.status
        question.status = QuestionStatus.ARCHIVED
        latest = await self.revision(question)
        if question.version > 0 and latest.status in (RevisionStatus.IN_REVIEW, RevisionStatus.APPROVED):
            # An edit that was approved before the takedown must not publish the question again by itself.
            latest.status = RevisionStatus.CHANGES_REQUESTED
            question.pending_status = RevisionStatus.CHANGES_REQUESTED.value
        self._audit(actor, "question.archived", question.id, before={"status": before}, reason=reason)
        await self.session.commit()
        await self.session.refresh(question)
        return question

    async def restore(self, actor: Principal, question_id: uuid.UUID) -> Question:
        question = await self.get(question_id, lock=True)
        if question.status != QuestionStatus.ARCHIVED:
            raise _transition(question, await self.revision(question), "restored")
        latest = await self.revision(question)
        if latest.status in (
            RevisionStatus.DRAFT,
            RevisionStatus.CHANGES_REQUESTED,
            RevisionStatus.IN_REVIEW,
            RevisionStatus.APPROVED,
        ) or (latest.status == RevisionStatus.SUPERSEDED and question.version == 0):
            # Work in progress (or a rejected draft) comes back as a draft: it needs a fresh review.
            latest.status = RevisionStatus.DRAFT
        else:
            # Published or rejected-edit: restart from the live version, never from rejected text.
            live = await self.revision(question, question.version)
            await self._new_revision(question, actor, live.snapshot, "Restored from archive", authored=False)
        question.status = QuestionStatus.DRAFT
        question.pending_status = None
        self._audit(actor, "question.restored", question.id)
        await self.session.commit()
        await self.session.refresh(question)
        return question

    async def reopen_for_fix(
        self, actor: Principal, question_id: uuid.UUID, *, note: str, hide: bool
    ) -> None:
        """An accepted error report puts the question back with the editors (optionally hiding it until
        fixed). The caller commits."""
        question = await self.get(question_id, lock=True)
        latest = await self.revision(question)
        if latest.status in _LIVE_OR_DONE and question.version > 0:
            live = await self.revision(question, question.version)
            revision = await self._new_revision(question, actor, live.snapshot, note, authored=False)
            self._set_status(question, revision, RevisionStatus.CHANGES_REQUESTED)
        elif latest.status in (RevisionStatus.IN_REVIEW, RevisionStatus.APPROVED):
            self._set_status(question, latest, RevisionStatus.CHANGES_REQUESTED)
        if hide and question.status == QuestionStatus.PUBLISHED:
            question.status = QuestionStatus.ARCHIVED
        self._audit(actor, "question.reopened_by_report", question.id, reason=note)

    # ------------------------------------------------------------------ internals

    def _set_status(self, question: Question, revision: QuestionRevision, status: RevisionStatus) -> None:
        revision.status = status
        if question.version == 0 or question.status != QuestionStatus.PUBLISHED:
            question.status = QuestionStatus(status.value)
            question.pending_status = None
        else:
            question.pending_status = status.value

    @staticmethod
    def _columns(content: QuestionContent) -> dict[str, Any]:
        return {
            "type": content.type.value,
            "source_locale": content.source_locale,
            "stimulus_id": content.stimulus_id,
            "education_level_id": content.education_level_id,
            "subject_id": content.subject_id,
            "chapter_id": content.chapter_id,
            "topic_id": content.topic_id,
            "difficulty": content.difficulty,
            "cognitive_level": content.cognitive_level.value if content.cognitive_level else None,
            "marks": content.marks,
            "answer_spec": content.answer_spec,
            "access_level": content.access_level.value,
            "required_entitlement_key": content.required_entitlement_key,
        }

    def _apply_columns(self, question: Question, content: QuestionContent) -> None:
        for name, value in self._columns(content).items():
            setattr(question, name, value)
        question.content_hash = content_hash(content)

    async def _materialise(self, question: Question, content: QuestionContent) -> None:
        self._apply_columns(question, content)
        for model in (QuestionTranslation, QuestionOption, QuestionPart):
            await self.session.execute(delete(model).where(model.question_id == question.id))
        await self.session.flush()
        for locale, translation in content.translations.items():
            self.session.add(
                QuestionTranslation(
                    question_id=question.id,
                    locale=locale,
                    stem=contentdoc.dump(translation.stem),
                    stem_text=contentdoc.plain_text(translation.stem),
                    explanation=_dump(translation.explanation),
                    model_answer=_dump(translation.model_answer),
                    marking_guidance=_dump(translation.marking_guidance),
                    origin=translation.origin.value,
                )
            )
        for position, option in enumerate(content.options):
            row = QuestionOption(
                question_id=question.id, position=position, label=option.label, is_correct=option.is_correct
            )
            self.session.add(row)
            await self.session.flush()
            self.session.add_all(
                QuestionOptionTranslation(
                    option_id=row.id,
                    locale=locale,
                    content=contentdoc.dump(doc),
                    content_text=contentdoc.plain_text(doc),
                )
                for locale, doc in option.content.items()
            )
        for position, part in enumerate(content.parts):
            row_part = QuestionPart(
                question_id=question.id,
                position=position,
                label=part.label,
                cognitive_level=part.cognitive_level.value,
                marks=part.marks,
            )
            self.session.add(row_part)
            await self.session.flush()
            self.session.add_all(
                QuestionPartTranslation(
                    part_id=row_part.id,
                    locale=locale,
                    prompt=contentdoc.dump(doc),
                    model_answer=_dump((part.model_answer or {}).get(locale)),
                    marking_guidance=_dump((part.marking_guidance or {}).get(locale)),
                )
                for locale, doc in part.prompt.items()
            )

    async def _duplicates(self, question: Question, content: QuestionContent) -> list[uuid.UUID]:
        rows = await self.session.execute(
            select(Question.id).where(
                Question.content_hash == question.content_hash,
                Question.id != question.id,
                Question.subject_id == content.subject_id,
                Question.deleted_at.is_(None),
                Question.status != QuestionStatus.ARCHIVED,
            )
        )
        return list(rows.scalars())

    async def _check_references(self, content: QuestionContent) -> None:
        session = self.session
        level = await session.get(EducationLevel, content.education_level_id)
        if level is None or not level.is_active:
            raise _invalid("Unknown or inactive education level", "content.education_level_id")
        subject = await session.get(Subject, content.subject_id)
        if subject is None or not subject.is_active:
            raise _invalid("Unknown or inactive subject", "content.subject_id")
        if subject.education_level_id != content.education_level_id:
            raise _invalid("The subject does not belong to this education level", "content.subject_id")
        if content.chapter_id is not None:
            chapter = await session.get(Chapter, content.chapter_id)
            if chapter is None or chapter.subject_id != content.subject_id or not chapter.is_active:
                raise _invalid("The chapter does not belong to this subject", "content.chapter_id")
        if content.topic_id is not None:
            topic = await session.get(Topic, content.topic_id)
            if topic is None or topic.chapter_id != content.chapter_id or not topic.is_active:
                raise _invalid("The topic does not belong to this chapter", "content.topic_id")
        if content.stimulus_id is not None and await session.get(Stimulus, content.stimulus_id) is None:
            raise _invalid("Unknown stimulus", "content.stimulus_id")
        key = content.required_entitlement_key
        if key is not None and await session.get(EntitlementDefinition, key) is None:
            raise _invalid("Unknown entitlement", "content.required_entitlement_key")
        asset_ids = {a for doc in iter_docs(content) for a in contentdoc.image_asset_ids(doc)}
        if asset_ids:
            found = (
                await session.execute(
                    select(func.count()).where(MediaAsset.id.in_([uuid.UUID(a) for a in asset_ids]))
                )
            ).scalar_one()
            if found != len(asset_ids):
                raise _invalid("A document refers to an unknown image", "content")

    async def _flush(self) -> None:
        try:
            await self.session.flush()
        except IntegrityError as exc:
            await self.session.rollback()
            log.warning("question_integrity_error", error=str(exc.orig)[:300])
            raise ValidationFailed("The values violate a question rule") from exc

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
            entity_type="question",
            entity_id=entity_id,
            before=before,
            after=after,
            reason=reason,
            ip=self.client.ip,
            user_agent=self.client.user_agent,
        )


def _shelved(question: Question) -> bool:
    """Archived and never published: nothing is live, so only `restore` may move it."""
    return question.status == QuestionStatus.ARCHIVED and question.version == 0


def _dump(doc: ContentDoc | None) -> dict[str, Any] | None:
    return None if doc is None else contentdoc.dump(doc)


def _locked(question: Question, message: str) -> Conflict:
    return Conflict(message, code=ErrorCode.RECORD_LOCKED, details={"status": question.status})


def _transition(question: Question, revision: QuestionRevision, action: str) -> Conflict:
    return Conflict(
        f"A question that is {question.status} (revision {revision.status}) cannot be {action}",
        code=ErrorCode.INVALID_STATE_TRANSITION,
        details={"status": question.status, "revision_status": revision.status},
    )


def _not_publishable(*reasons: str, **extra: Any) -> Conflict:
    return Conflict(
        "This question cannot be published yet",
        code=ErrorCode.CONTENT_NOT_PUBLISHABLE,
        details={"reasons": list(reasons), **extra},
    )


# ------------------------------------------------------------------ stimuli


class StimulusService:
    def __init__(self, session: AsyncSession, client: ClientInfo) -> None:
        self.session = session
        self.client = client

    async def get(self, stimulus_id: uuid.UUID, *, lock: bool = False) -> Stimulus:
        stimulus = await self.session.get(Stimulus, stimulus_id, with_for_update=lock, populate_existing=lock)
        if stimulus is None:
            raise NotFound("Stimulus not found")
        return stimulus

    async def view(self, stimulus: Stimulus) -> tuple[dict[str, dict[str, Any]], int]:
        rows = await self.session.execute(
            select(StimulusTranslation).where(StimulusTranslation.stimulus_id == stimulus.id)
        )
        translations = {t.locale: t.content for t in rows.scalars()}
        used = (
            await self.session.execute(select(func.count()).where(Question.stimulus_id == stimulus.id))
        ).scalar_one()
        return translations, used

    async def list_all(self, *, offset: int, limit: int) -> tuple[list[Stimulus], int]:
        total = (await self.session.execute(select(func.count()).select_from(Stimulus))).scalar_one()
        rows = (
            await self.session.execute(
                select(Stimulus).order_by(Stimulus.created_at.desc(), Stimulus.id).offset(offset).limit(limit)
            )
        ).scalars()
        return list(rows), total

    async def create(
        self, actor: Principal, source_locale: str, translations: dict[str, ContentDoc]
    ) -> Stimulus:
        stimulus = Stimulus(source_locale=source_locale, created_by=actor.user_id)
        self.session.add(stimulus)
        await self.session.flush()
        self._put(stimulus.id, translations)
        self._audit(actor, "stimulus.created", stimulus.id)
        await self.session.commit()
        await self.session.refresh(stimulus)
        return stimulus

    async def replace(
        self,
        actor: Principal,
        stimulus_id: uuid.UUID,
        source_locale: str,
        translations: dict[str, ContentDoc],
    ) -> Stimulus:
        stimulus = await self.get(stimulus_id, lock=True)
        live = (
            await self.session.execute(
                select(func.count()).where(
                    Question.stimulus_id == stimulus_id,
                    Question.deleted_at.is_(None),
                    (Question.version > 0)
                    | Question.status.in_((QuestionStatus.IN_REVIEW, QuestionStatus.APPROVED))
                    | Question.pending_status.in_((RevisionStatus.IN_REVIEW, RevisionStatus.APPROVED)),
                )
            )
        ).scalar_one()
        if live:
            raise Conflict(
                "A stimulus used by a published question, or one in review, cannot be edited; "
                "create a new one and revise the question",
                code=ErrorCode.IN_USE,
            )
        stimulus.source_locale = source_locale
        await self.session.execute(
            delete(StimulusTranslation).where(StimulusTranslation.stimulus_id == stimulus_id)
        )
        await self.session.flush()
        self._put(stimulus_id, translations)
        self._audit(actor, "stimulus.updated", stimulus_id)
        await self.session.commit()
        await self.session.refresh(stimulus)
        return stimulus

    def _put(self, stimulus_id: uuid.UUID, translations: dict[str, ContentDoc]) -> None:
        self.session.add_all(
            StimulusTranslation(
                stimulus_id=stimulus_id,
                locale=locale,
                content=contentdoc.dump(doc),
                plain_text=contentdoc.plain_text(doc),
            )
            for locale, doc in translations.items()
        )

    def _audit(self, actor: Principal, action: str, entity_id: uuid.UUID) -> None:
        record_audit(
            self.session,
            action=action,
            actor_type=ActorType.STAFF,
            actor_user_id=actor.user_id,
            entity_type="stimulus",
            entity_id=entity_id,
            ip=self.client.ip,
            user_agent=self.client.user_agent,
        )

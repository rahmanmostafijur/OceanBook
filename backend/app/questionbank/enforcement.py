"""Rights gate for question-bank content (docs/architecture/12 §5).

A question is publishable on its own provenance, its stimulus's, or that of a published paper it
appears in. Papers are publishable on their own provenance. Content that stops passing is withdrawn
(archived), audited as `system` or the acting reviewer, and announced with `content.rights_lapsed`.
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime

from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.logging import get_logger
from app.platform.audit import ActorType, record_audit
from app.platform.outbox import publish_event
from app.provenance.models import ProvenanceRecord
from app.provenance.rules import Publishability, content_today, evaluate
from app.questionbank.models import (
    PaperStatus,
    Question,
    QuestionPaper,
    QuestionPaperItem,
    QuestionStatus,
)

RIGHTS_LAPSED = "content.rights_lapsed"
log = get_logger(__name__)


async def question_records(session: AsyncSession, question: Question) -> list[ProvenanceRecord]:
    """Own records, the stimulus's, and those of every published paper the question appears in."""
    paper_ids = select(QuestionPaperItem.paper_id).where(QuestionPaperItem.question_id == question.id)
    published_papers = select(QuestionPaper.id).where(
        QuestionPaper.id.in_(paper_ids), QuestionPaper.status == PaperStatus.PUBLISHED
    )
    conditions = [
        ProvenanceRecord.question_id == question.id,
        ProvenanceRecord.question_paper_id.in_(published_papers),
    ]
    if question.stimulus_id is not None:
        conditions.append(ProvenanceRecord.stimulus_id == question.stimulus_id)
    rows = await session.execute(select(ProvenanceRecord).where(or_(*conditions)))
    return list(rows.scalars())


async def question_publishability(
    session: AsyncSession, question: Question, *, territory: str, now: datetime | None = None
) -> Publishability:
    today = content_today(now)
    pooled = evaluate(await question_records(session, question), today=today, territory=territory)
    if not pooled.publishable or question.stimulus_id is None:
        return pooled
    # A separately licensed passage must pass on its own too: its revocation cannot be masked by the
    # question's other records.
    stimulus_records = (
        (
            await session.execute(
                select(ProvenanceRecord).where(ProvenanceRecord.stimulus_id == question.stimulus_id)
            )
        )
        .scalars()
        .all()
    )
    if not stimulus_records:
        return pooled
    return evaluate(stimulus_records, today=today, territory=territory)


async def paper_publishability(
    session: AsyncSession, paper_id: uuid.UUID, *, territory: str, now: datetime | None = None
) -> Publishability:
    rows = await session.execute(
        select(ProvenanceRecord).where(ProvenanceRecord.question_paper_id == paper_id)
    )
    return evaluate(rows.scalars(), today=content_today(now), territory=territory)


def _announce(
    session: AsyncSession,
    *,
    entity_type: str,
    entity_id: uuid.UUID,
    before: str,
    actor_user_id: uuid.UUID | None,
    reasons: list[str],
    reason: str,
) -> None:
    record_audit(
        session,
        action=f"{entity_type}.withdrawn_rights",
        actor_type=ActorType.SYSTEM if actor_user_id is None else ActorType.STAFF,
        actor_user_id=actor_user_id,
        entity_type=entity_type,
        entity_id=entity_id,
        before={"status": before},
        after={"status": "archived", "reasons": reasons},
        reason=reason,
    )
    publish_event(
        session,
        event_type=RIGHTS_LAPSED,
        aggregate_type=entity_type,
        aggregate_id=entity_id,
        payload={f"{entity_type}_id": str(entity_id), "reasons": reasons},
    )


async def _withdraw_question(
    session: AsyncSession,
    question_id: uuid.UUID,
    *,
    territory: str,
    actor_user_id: uuid.UUID | None,
    reason: str,
    now: datetime | None,
) -> bool:
    question = await session.get(Question, question_id, with_for_update=True, populate_existing=True)
    if question is None or question.status != QuestionStatus.PUBLISHED or question.deleted_at is not None:
        return False
    result = await question_publishability(session, question, territory=territory, now=now)
    if result.publishable:
        return False
    question.status = QuestionStatus.ARCHIVED
    _announce(
        session,
        entity_type="question",
        entity_id=question.id,
        before=QuestionStatus.PUBLISHED.value,
        actor_user_id=actor_user_id,
        reasons=[r.value for r in result.reasons],
        reason=reason,
    )
    return True


async def _withdraw_paper(
    session: AsyncSession,
    paper_id: uuid.UUID,
    *,
    territory: str,
    actor_user_id: uuid.UUID | None,
    reason: str,
    now: datetime | None,
) -> bool:
    paper = await session.get(QuestionPaper, paper_id, with_for_update=True, populate_existing=True)
    if paper is None or paper.status != PaperStatus.PUBLISHED:
        return False
    result = await paper_publishability(session, paper.id, territory=territory, now=now)
    if result.publishable:
        return False
    paper.status = PaperStatus.ARCHIVED
    _announce(
        session,
        entity_type="question_paper",
        entity_id=paper.id,
        before=PaperStatus.PUBLISHED.value,
        actor_user_id=actor_user_id,
        reasons=[r.value for r in result.reasons],
        reason=reason,
    )
    await session.flush()
    # Questions that were published on the strength of this paper's records may no longer pass.
    item_ids = (
        (
            await session.execute(
                select(QuestionPaperItem.question_id).where(QuestionPaperItem.paper_id == paper.id)
            )
        )
        .scalars()
        .all()
    )
    for question_id in sorted(item_ids):  # a fixed lock order, so concurrent withdrawals cannot deadlock
        await _withdraw_question(
            session, question_id, territory=territory, actor_user_id=actor_user_id, reason=reason, now=now
        )
    return True


async def withdraw_question_content_if_unpublishable(
    session: AsyncSession,
    subject_type: str,
    subject_id: uuid.UUID,
    *,
    territory: str,
    actor_user_id: uuid.UUID | None,
    reason: str,
    now: datetime | None = None,
) -> int:
    """Stage withdrawals on the caller's transaction after a rights change on `subject_type`
    (`question`, `stimulus` or `question_paper`). Returns how many items were withdrawn."""

    async def question(question_id: uuid.UUID) -> bool:
        return await _withdraw_question(
            session, question_id, territory=territory, actor_user_id=actor_user_id, reason=reason, now=now
        )

    if subject_type == "question_paper":
        return int(
            await _withdraw_paper(
                session, subject_id, territory=territory, actor_user_id=actor_user_id, reason=reason, now=now
            )
        )
    if subject_type == "question":
        return int(await question(subject_id))
    if subject_type == "stimulus":
        ids = (
            (await session.execute(select(Question.id).where(Question.stimulus_id == subject_id)))
            .scalars()
            .all()
        )
        return sum([await question(question_id) for question_id in ids])
    return 0


async def enforce_published_question_rights(
    session: AsyncSession, *, territory: str, now: datetime | None = None
) -> int:
    """Scheduled job: re-evaluate every published paper and question, committing each withdrawal on its
    own so locks stay short and one failure does not undo the rest."""
    paper_ids = (
        (await session.execute(select(QuestionPaper.id).where(QuestionPaper.status == PaperStatus.PUBLISHED)))
        .scalars()
        .all()
    )
    question_ids = (
        (
            await session.execute(
                select(Question.id).where(
                    Question.status == QuestionStatus.PUBLISHED, Question.deleted_at.is_(None)
                )
            )
        )
        .scalars()
        .all()
    )
    await session.rollback()  # end the read transaction before taking row locks
    withdrawn = 0
    reason = "Scheduled rights re-evaluation"
    effective_now = now or datetime.now(UTC)
    for subject_type, ids in (("question_paper", paper_ids), ("question", question_ids)):
        for subject_id in ids:
            try:
                withdrawn += await withdraw_question_content_if_unpublishable(
                    session,
                    subject_type,
                    subject_id,
                    territory=territory,
                    actor_user_id=None,
                    reason=reason,
                    now=effective_now,
                )
                await session.commit()
            except Exception:
                await session.rollback()
                log.exception("question_rights_enforcement_failed", subject=subject_type, id=str(subject_id))
    return withdrawn

"""Content sources, provenance records and the two-person verification workflow (12 §5).

unverified --submit--> pending --verify(other person)--> verified
     ^                    |
     +----edit---- rejected <--reject(other person)--+

Pending records are locked so the verifier sees exactly what was submitted. Verified records are
immutable except for narrowing rights changes (restricted / expired / disputed), which take effect at
once and withdraw content that is no longer publishable. Anything else means recording a new record.
"""

from __future__ import annotations

import uuid
from collections.abc import Sequence
from datetime import UTC, datetime
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.catalog.models import BookEdition, Publisher
from app.core.errors import Conflict, ErrorCode, Forbidden, NotFound, ValidationFailed
from app.core.request_info import ClientInfo
from app.core.resources import Resources
from app.identity.services.principal import Principal
from app.media.models import MediaAsset
from app.platform.audit import ActorType, record_audit
from app.provenance.enforcement import withdraw_if_unpublishable
from app.provenance.models import ContentSource, ProvenanceRecord, VerificationStatus
from app.provenance.rules import Publishability, content_today, evaluate
from app.provenance.schemas import (
    ContentSourceIn,
    ContentSourcePatch,
    ProvenanceIn,
    ProvenancePatch,
    RightsChangeIn,
    VerificationIn,
)

EDITABLE = frozenset({VerificationStatus.UNVERIFIED, VerificationStatus.REJECTED})
_URL_FIELDS = ("source_url", "website_url")


def _values(body: Any, *, exclude: set[str] | None = None) -> dict[str, Any]:
    values: dict[str, Any] = body.model_dump(exclude_unset=True, exclude=exclude or set())
    for name in _URL_FIELDS:
        if values.get(name) is not None:
            values[name] = str(values[name])
    return values


def snapshot(record: ProvenanceRecord) -> dict[str, Any]:
    return {
        "verification_status": record.verification_status,
        "rights_status": record.rights_status,
        "license_type": record.license_type,
        "territories": list(record.territories),
        "valid_from": record.valid_from.isoformat() if record.valid_from else None,
        "valid_until": record.valid_until.isoformat() if record.valid_until else None,
    }


async def edition_publishability(
    session: AsyncSession, edition_id: uuid.UUID, *, territory: str, now: datetime | None = None
) -> Publishability:
    records = (
        await session.execute(select(ProvenanceRecord).where(ProvenanceRecord.edition_id == edition_id))
    ).scalars()
    return evaluate(records, today=content_today(now), territory=territory)


async def assert_publishable(session: AsyncSession, edition_id: uuid.UUID, *, territory: str) -> None:
    result = await edition_publishability(session, edition_id, territory=territory)
    if not result.publishable:
        raise Conflict(
            "This edition cannot be published until its provenance is verified and its rights are clear",
            code=ErrorCode.CONTENT_NOT_PUBLISHABLE,
            details={"edition_id": str(edition_id), "reasons": [r.value for r in result.reasons]},
        )


class ProvenanceService:
    def __init__(self, session: AsyncSession, resources: Resources, client: ClientInfo) -> None:
        self.session = session
        self.resources = resources
        self.client = client

    # ------------------------------------------------------------------ sources

    async def list_sources(self, *, include_inactive: bool) -> Sequence[ContentSource]:
        query = select(ContentSource).order_by(ContentSource.created_at)
        if not include_inactive:
            query = query.where(ContentSource.is_active)
        return (await self.session.execute(query)).scalars().all()

    async def create_source(self, actor: Principal, body: ContentSourceIn) -> ContentSource:
        values = _values(body)
        await self._check_publisher(values.get("publisher_id"))
        source = ContentSource(**values)
        self.session.add(source)
        await self.session.flush()
        self._audit(actor, "content_source.created", "content_source", source.id, after={"kind": source.kind})
        await self.session.commit()
        await self.session.refresh(source)
        return source

    async def update_source(
        self, actor: Principal, source_id: uuid.UUID, body: ContentSourcePatch
    ) -> ContentSource:
        source = await self.session.get(ContentSource, source_id, with_for_update=True)
        if source is None:
            raise NotFound("Content source not found")
        values = _values(body)
        if "publisher_id" in values:
            await self._check_publisher(values["publisher_id"])
        for name, value in values.items():
            setattr(source, name, value)
        self._audit(
            actor, "content_source.updated", "content_source", source.id, after={"fields": sorted(values)}
        )
        await self.session.commit()
        await self.session.refresh(source)
        return source

    # ------------------------------------------------------------------ records

    async def get(self, record_id: uuid.UUID, *, lock: bool = False) -> ProvenanceRecord:
        record = await self.session.get(ProvenanceRecord, record_id, with_for_update=lock)
        if record is None:
            raise NotFound("Provenance record not found")
        return record

    async def for_edition(self, edition_id: uuid.UUID) -> Sequence[ProvenanceRecord]:
        await self._edition(edition_id)
        query = (
            select(ProvenanceRecord)
            .where(ProvenanceRecord.edition_id == edition_id)
            .order_by(ProvenanceRecord.created_at)
        )
        return (await self.session.execute(query)).scalars().all()

    async def queue(self, *, offset: int, limit: int) -> Sequence[ProvenanceRecord]:
        """Oldest-first verification queue."""
        query = (
            select(ProvenanceRecord)
            .where(ProvenanceRecord.verification_status == VerificationStatus.PENDING)
            .order_by(ProvenanceRecord.submitted_at, ProvenanceRecord.id)
            .offset(offset)
            .limit(limit)
        )
        return (await self.session.execute(query)).scalars().all()

    async def create_for_edition(
        self, actor: Principal, edition_id: uuid.UUID, body: ProvenanceIn
    ) -> ProvenanceRecord:
        await self._edition(edition_id)
        values = _values(body)
        await self._check_refs(values)
        record = ProvenanceRecord(
            edition_id=edition_id, created_by=actor.user_id, updated_by=actor.user_id, **values
        )
        self.session.add(record)
        await self.session.flush()
        self._audit(actor, "provenance.created", "provenance_record", record.id, after=snapshot(record))
        await self.session.commit()
        await self.session.refresh(record)
        return record

    async def update(self, actor: Principal, record_id: uuid.UUID, body: ProvenancePatch) -> ProvenanceRecord:
        record = await self.get(record_id, lock=True)
        if record.verification_status not in EDITABLE:
            raise Conflict(
                "Submitted and verified provenance cannot be edited; record a new entry instead",
                code=ErrorCode.RECORD_LOCKED,
                details={"verification_status": record.verification_status},
            )
        values = _values(body)
        await self._check_refs(values)
        before = snapshot(record)
        for name, value in values.items():
            setattr(record, name, value)
        if record.valid_from and record.valid_until and record.valid_until < record.valid_from:
            raise ValidationFailed("valid_until must not be before valid_from", field="valid_until")
        record.verification_status = VerificationStatus.UNVERIFIED
        record.updated_by = actor.user_id
        self._audit(
            actor, "provenance.updated", "provenance_record", record.id, before=before, after=snapshot(record)
        )
        await self.session.commit()
        await self.session.refresh(record)
        return record

    async def submit(self, actor: Principal, record_id: uuid.UUID) -> ProvenanceRecord:
        record = await self.get(record_id, lock=True)
        if record.verification_status not in EDITABLE:
            raise Conflict(
                "Only unverified or rejected provenance can be submitted",
                code=ErrorCode.INVALID_STATE_TRANSITION,
                details={"verification_status": record.verification_status},
            )
        record.verification_status = VerificationStatus.PENDING
        record.submitted_at = datetime.now(UTC)
        record.verification_notes = None
        self._audit(actor, "provenance.submitted", "provenance_record", record.id, after=snapshot(record))
        await self.session.commit()
        await self.session.refresh(record)
        return record

    async def decide(self, actor: Principal, record_id: uuid.UUID, body: VerificationIn) -> ProvenanceRecord:
        record = await self.get(record_id, lock=True)
        if record.verification_status != VerificationStatus.PENDING:
            raise Conflict(
                "Only submitted provenance can be verified or rejected",
                code=ErrorCode.INVALID_STATE_TRANSITION,
                details={"verification_status": record.verification_status},
            )
        if actor.user_id in {record.created_by, record.updated_by}:
            raise Forbidden(
                "Provenance must be verified by someone other than the person who recorded it",
                code=ErrorCode.SELF_VERIFICATION_FORBIDDEN,
            )
        before = snapshot(record)
        record.verification_notes = body.notes
        if body.decision == "verified":
            record.verification_status = VerificationStatus.VERIFIED
            record.verified_by = actor.user_id
            record.verified_at = datetime.now(UTC)
        else:
            record.verification_status = VerificationStatus.REJECTED
            record.verified_by = None
            record.verified_at = None
        self._audit(
            actor,
            f"provenance.{body.decision}",
            "provenance_record",
            record.id,
            before=before,
            after=snapshot(record),
        )
        await self.session.commit()
        await self.session.refresh(record)
        return record

    async def change_rights(
        self, actor: Principal, record_id: uuid.UUID, body: RightsChangeIn
    ) -> ProvenanceRecord:
        record = await self.get(record_id, lock=True)
        if record.verification_status != VerificationStatus.VERIFIED:
            raise Conflict(
                "Use an ordinary edit for provenance that is not yet verified",
                code=ErrorCode.INVALID_STATE_TRANSITION,
                details={"verification_status": record.verification_status},
            )
        before = snapshot(record)
        # updated_by is left alone: the record is not re-verified, and the database's two-person CHECK
        # compares verified_by with the people who wrote the record. The audit entry names the actor.
        record.rights_status = body.rights_status
        self._audit(
            actor,
            "provenance.rights_changed",
            "provenance_record",
            record.id,
            before=before,
            after=snapshot(record),
            reason=body.reason,
        )
        await self.session.flush()
        if record.edition_id is not None:
            await withdraw_if_unpublishable(
                self.session,
                record.edition_id,
                territory=self.resources.settings.content_launch_territory,
                actor_user_id=actor.user_id,
                reason=body.reason,
            )
        await self.session.commit()
        await self.session.refresh(record)
        return record

    # ------------------------------------------------------------------ helpers

    async def _edition(self, edition_id: uuid.UUID) -> BookEdition:
        edition = await self.session.get(BookEdition, edition_id)
        if edition is None:
            raise NotFound("Edition not found")
        return edition

    async def _check_publisher(self, publisher_id: uuid.UUID | None) -> None:
        if publisher_id is not None and await self.session.get(Publisher, publisher_id) is None:
            raise ValidationFailed("Unknown publisher", field="publisher_id")

    async def _check_refs(self, values: dict[str, Any]) -> None:
        if "source_id" in values:
            source = await self.session.get(ContentSource, values["source_id"])
            if source is None or not source.is_active:
                raise ValidationFailed("Unknown or inactive content source", field="source_id")
        asset_id = values.get("evidence_asset_id")
        if asset_id is not None and await self.session.get(MediaAsset, asset_id) is None:
            raise ValidationFailed("Unknown evidence asset", field="evidence_asset_id")

    def _audit(
        self,
        actor: Principal,
        action: str,
        entity_type: str,
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
            entity_type=entity_type,
            entity_id=entity_id,
            before=before,
            after=after,
            reason=reason,
            ip=self.client.ip,
            user_agent=self.client.user_agent,
        )

"""Staff provenance API: content sources, records, and the two-person verification workflow."""

from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, Query, status

from app.core.db import WriteSession
from app.core.envelope import Envelope, ok
from app.core.pagination import OffsetParams, offset_params
from app.identity.api.dependencies import ClientDep, ResourcesDep, require_permission
from app.identity.permissions import Permission
from app.identity.services.principal import Principal
from app.provenance.models import ProvenanceRecord
from app.provenance.schemas import (
    ContentSourceIn,
    ContentSourceOut,
    ContentSourcePatch,
    ProvenanceIn,
    ProvenanceOut,
    ProvenancePatch,
    RightsChangeIn,
    VerificationIn,
)
from app.provenance.service import ProvenanceService

router = APIRouter(prefix="/admin", tags=["admin: provenance"])

CanView = Annotated[Principal, Depends(require_permission(Permission.CATALOG_VIEW))]
CanEdit = Annotated[Principal, Depends(require_permission(Permission.PROVENANCE_EDIT))]
CanVerify = Annotated[Principal, Depends(require_permission(Permission.PROVENANCE_VERIFY))]
Paging = Annotated[OffsetParams, Depends(offset_params)]


def _out(record: ProvenanceRecord) -> ProvenanceOut:
    assert record.edition_id is not None  # the only subject type until the question bank adds more
    return ProvenanceOut.model_validate(
        {
            **{c.key: getattr(record, c.key) for c in ProvenanceRecord.__table__.columns},
            "subject_type": "edition",
            "subject_id": record.edition_id,
        }
    )


@router.get("/content-sources", response_model=Envelope[list[ContentSourceOut]])
async def admin_list_sources(
    _: CanView,
    session: WriteSession,
    resources: ResourcesDep,
    client: ClientDep,
    include_inactive: Annotated[bool, Query()] = False,
) -> Envelope[list[ContentSourceOut]]:
    sources = await ProvenanceService(session, resources, client).list_sources(
        include_inactive=include_inactive
    )
    return ok([ContentSourceOut.model_validate(s) for s in sources])


@router.post(
    "/content-sources", status_code=status.HTTP_201_CREATED, response_model=Envelope[ContentSourceOut]
)
async def admin_create_source(
    body: ContentSourceIn, actor: CanEdit, session: WriteSession, resources: ResourcesDep, client: ClientDep
) -> Envelope[ContentSourceOut]:
    source = await ProvenanceService(session, resources, client).create_source(actor, body)
    return ok(ContentSourceOut.model_validate(source))


@router.patch("/content-sources/{source_id}", response_model=Envelope[ContentSourceOut])
async def admin_update_source(
    source_id: uuid.UUID,
    body: ContentSourcePatch,
    actor: CanEdit,
    session: WriteSession,
    resources: ResourcesDep,
    client: ClientDep,
) -> Envelope[ContentSourceOut]:
    source = await ProvenanceService(session, resources, client).update_source(actor, source_id, body)
    return ok(ContentSourceOut.model_validate(source))


@router.get("/editions/{edition_id}/provenance", response_model=Envelope[list[ProvenanceOut]])
async def admin_edition_provenance(
    edition_id: uuid.UUID, _: CanView, session: WriteSession, resources: ResourcesDep, client: ClientDep
) -> Envelope[list[ProvenanceOut]]:
    records = await ProvenanceService(session, resources, client).for_edition(edition_id)
    return ok([_out(r) for r in records])


@router.post(
    "/editions/{edition_id}/provenance",
    status_code=status.HTTP_201_CREATED,
    response_model=Envelope[ProvenanceOut],
)
async def admin_create_provenance(
    edition_id: uuid.UUID,
    body: ProvenanceIn,
    actor: CanEdit,
    session: WriteSession,
    resources: ResourcesDep,
    client: ClientDep,
) -> Envelope[ProvenanceOut]:
    record = await ProvenanceService(session, resources, client).create_for_edition(actor, edition_id, body)
    return ok(_out(record))


@router.get(
    "/provenance/queue",
    response_model=Envelope[list[ProvenanceOut]],
    description="Submitted provenance awaiting a second person's decision, oldest first.",
)
async def admin_verification_queue(
    _: CanVerify, session: WriteSession, resources: ResourcesDep, client: ClientDep, paging: Paging
) -> Envelope[list[ProvenanceOut]]:
    records = await ProvenanceService(session, resources, client).queue(
        offset=paging.offset, limit=paging.page_size
    )
    return ok([_out(r) for r in records])


@router.get("/provenance/{record_id}", response_model=Envelope[ProvenanceOut])
async def admin_get_provenance(
    record_id: uuid.UUID, _: CanView, session: WriteSession, resources: ResourcesDep, client: ClientDep
) -> Envelope[ProvenanceOut]:
    return ok(_out(await ProvenanceService(session, resources, client).get(record_id)))


@router.patch("/provenance/{record_id}", response_model=Envelope[ProvenanceOut])
async def admin_update_provenance(
    record_id: uuid.UUID,
    body: ProvenancePatch,
    actor: CanEdit,
    session: WriteSession,
    resources: ResourcesDep,
    client: ClientDep,
) -> Envelope[ProvenanceOut]:
    return ok(_out(await ProvenanceService(session, resources, client).update(actor, record_id, body)))


@router.post("/provenance/{record_id}/submit", response_model=Envelope[ProvenanceOut])
async def admin_submit_provenance(
    record_id: uuid.UUID, actor: CanEdit, session: WriteSession, resources: ResourcesDep, client: ClientDep
) -> Envelope[ProvenanceOut]:
    return ok(_out(await ProvenanceService(session, resources, client).submit(actor, record_id)))


@router.post(
    "/provenance/{record_id}/decision",
    response_model=Envelope[ProvenanceOut],
    description="Verify or reject submitted provenance. The decider must not be the person who recorded or "
    "last edited it (403 SELF_VERIFICATION_FORBIDDEN).",
)
async def admin_decide_provenance(
    record_id: uuid.UUID,
    body: VerificationIn,
    actor: CanVerify,
    session: WriteSession,
    resources: ResourcesDep,
    client: ClientDep,
) -> Envelope[ProvenanceOut]:
    return ok(_out(await ProvenanceService(session, resources, client).decide(actor, record_id, body)))


@router.post(
    "/provenance/{record_id}/rights-status",
    response_model=Envelope[ProvenanceOut],
    description="Narrows the rights on verified provenance (restricted, expired, disputed). Takes effect "
    "at once: content that is no longer publishable is withdrawn in the same transaction.",
)
async def admin_change_provenance_rights(
    record_id: uuid.UUID,
    body: RightsChangeIn,
    actor: CanVerify,
    session: WriteSession,
    resources: ResourcesDep,
    client: ClientDep,
) -> Envelope[ProvenanceOut]:
    return ok(_out(await ProvenanceService(session, resources, client).change_rights(actor, record_id, body)))

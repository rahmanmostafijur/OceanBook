"""Provenance API contract."""

from __future__ import annotations

import uuid
from datetime import date, datetime
from typing import Annotated, Literal

from pydantic import AfterValidator, BaseModel, ConfigDict, Field, HttpUrl, StringConstraints, model_validator

from app.core.i18n import LocalizedText, LooseLocalizedText, nfc
from app.identity.schemas import Reason, StrictModel
from app.provenance.models import LicenseType, RightsStatus, SourceKind

Territory = Annotated[str, StringConstraints(pattern=r"^([A-Z]{2}|\*)$")]
Note = Annotated[str, AfterValidator(nfc), StringConstraints(max_length=2000)]
Reference = Annotated[str, AfterValidator(nfc), StringConstraints(max_length=500)]
NARROWING_RIGHTS = (RightsStatus.RESTRICTED, RightsStatus.EXPIRED, RightsStatus.DISPUTED)


def _territories(values: list[str]) -> list[str]:
    unique = list(dict.fromkeys(values))
    if "*" in unique and len(unique) > 1:
        raise ValueError("'*' (worldwide) cannot be combined with specific territories")
    return unique


Territories = Annotated[list[Territory], Field(min_length=1, max_length=250), AfterValidator(_territories)]
Exclusions = Annotated[list[Territory], Field(max_length=250), AfterValidator(_territories)]


class ContentSourceIn(StrictModel):
    kind: SourceKind
    name: LocalizedText
    publisher_id: uuid.UUID | None = None
    website_url: HttpUrl | None = None
    contact: Reference | None = None
    notes: Note | None = None


class ContentSourcePatch(StrictModel):
    name: LocalizedText | None = None
    publisher_id: uuid.UUID | None = None
    website_url: HttpUrl | None = None
    contact: Reference | None = None
    notes: Note | None = None
    is_active: bool | None = None


class _ProvenanceFields(StrictModel):
    source_url: HttpUrl | None = None
    source_reference: Reference | None = None
    license_reference: Reference | None = None
    attribution_text: LooseLocalizedText | None = None
    valid_from: date | None = None
    valid_until: date | None = None
    evidence_asset_id: uuid.UUID | None = None
    notes: Note | None = None

    @model_validator(mode="after")
    def _window(self) -> _ProvenanceFields:
        if self.valid_from and self.valid_until and self.valid_until < self.valid_from:
            raise ValueError("valid_until must not be before valid_from")
        return self


class ProvenanceIn(_ProvenanceFields):
    source_id: uuid.UUID
    license_type: LicenseType
    rights_status: RightsStatus
    territories: Territories = Field(default_factory=lambda: ["BD"])
    excluded_territories: Exclusions = Field(default_factory=list)


class ProvenancePatch(_ProvenanceFields):
    source_id: uuid.UUID | None = None
    license_type: LicenseType | None = None
    rights_status: RightsStatus | None = None
    territories: Territories | None = None
    excluded_territories: Exclusions | None = None


class VerificationIn(StrictModel):
    decision: Literal["verified", "rejected"]
    notes: Note | None = None

    @model_validator(mode="after")
    def _notes(self) -> VerificationIn:
        if self.decision == "rejected" and not self.notes:
            raise ValueError("A rejection needs notes explaining what to fix")
        return self


class RightsChangeIn(StrictModel):
    """Narrowing change on a verified record. It takes effect immediately and can unpublish content."""

    rights_status: Literal["restricted", "expired", "disputed"]
    reason: Reason


class ContentSourceOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    kind: str
    name: dict[str, str]
    publisher_id: uuid.UUID | None
    website_url: str | None
    contact: str | None
    notes: str | None
    is_active: bool
    created_at: datetime


class ProvenanceOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    subject_type: Literal["edition"]
    subject_id: uuid.UUID
    source_id: uuid.UUID
    source_url: str | None
    source_reference: str | None
    license_type: str
    license_reference: str | None
    rights_status: str
    attribution_text: dict[str, str] | None
    territories: list[str]
    excluded_territories: list[str]
    valid_from: date | None
    valid_until: date | None
    verification_status: str
    verified_by: uuid.UUID | None
    verified_at: datetime | None
    verification_notes: str | None
    evidence_asset_id: uuid.UUID | None
    notes: str | None
    created_by: uuid.UUID | None
    updated_by: uuid.UUID | None
    submitted_at: datetime | None
    created_at: datetime
    updated_at: datetime

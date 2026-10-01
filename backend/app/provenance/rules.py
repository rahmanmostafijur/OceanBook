"""The publish gate as a pure function (12 §5), so the rule is unit-testable without a database.

Publishable iff no record is disputed and at least one record is verified, has cleared or
public-domain rights, a validity window covering `today`, and a territory covering the launch
territory. When nothing passes, the reasons say what is missing.
"""

from __future__ import annotations

from collections.abc import Iterable
from dataclasses import dataclass
from datetime import UTC, date, datetime
from enum import StrEnum
from typing import Protocol
from zoneinfo import ZoneInfo

from app.provenance.models import PUBLISHABLE_RIGHTS, RightsStatus, VerificationStatus

# Contract dates are Bangladesh calendar dates.
CONTENT_TIMEZONE = ZoneInfo("Asia/Dhaka")


def content_today(now: datetime | None = None) -> date:
    return (now or datetime.now(UTC)).astimezone(CONTENT_TIMEZONE).date()


class BlockReason(StrEnum):
    NO_PROVENANCE = "NO_PROVENANCE"
    NOT_VERIFIED = "NOT_VERIFIED"
    RIGHTS_NOT_CLEARED = "RIGHTS_NOT_CLEARED"
    OUTSIDE_VALIDITY_WINDOW = "OUTSIDE_VALIDITY_WINDOW"
    TERRITORY_NOT_COVERED = "TERRITORY_NOT_COVERED"
    DISPUTED = "DISPUTED"


class RecordLike(Protocol):
    verification_status: str
    rights_status: str
    valid_from: date | None
    valid_until: date | None
    territories: list[str]
    excluded_territories: list[str]


@dataclass(frozen=True, slots=True)
class Publishability:
    publishable: bool
    reasons: tuple[BlockReason, ...]


def _failures(record: RecordLike, today: date, territory: str) -> set[BlockReason]:
    failures = set()
    if record.verification_status != VerificationStatus.VERIFIED:
        failures.add(BlockReason.NOT_VERIFIED)
    if record.rights_status not in PUBLISHABLE_RIGHTS:
        failures.add(BlockReason.RIGHTS_NOT_CLEARED)
    if (record.valid_from and record.valid_from > today) or (
        record.valid_until and record.valid_until < today
    ):
        failures.add(BlockReason.OUTSIDE_VALIDITY_WINDOW)
    covered = "*" in record.territories or territory in record.territories
    if not covered or territory in record.excluded_territories:
        failures.add(BlockReason.TERRITORY_NOT_COVERED)
    return failures


def evaluate(records: Iterable[RecordLike], *, today: date, territory: str) -> Publishability:
    items = list(records)
    if not items:
        return Publishability(False, (BlockReason.NO_PROVENANCE,))
    # A dispute counts once it sits on verified provenance (narrowed by a verifier); a draft record
    # cannot take content down on its own.
    disputed = (
        r.rights_status == RightsStatus.DISPUTED and r.verification_status == VerificationStatus.VERIFIED
        for r in items
    )
    if any(disputed):
        return Publishability(False, (BlockReason.DISPUTED,))
    per_record = [_failures(r, today, territory) for r in items]
    if any(not failures for failures in per_record):
        return Publishability(True, ())
    # Report what the closest record lacks (fewest failures), in a stable order.
    closest = min(per_record, key=len)
    return Publishability(False, tuple(sorted(closest)))

"""Pure catalog rules: publish gate, ISBN validation, localisation fallbacks, access decisions."""

from __future__ import annotations

import uuid
from dataclasses import dataclass, field
from datetime import UTC, date, datetime

import pytest
from pydantic import TypeAdapter, ValidationError

from app.catalog.isbn import normalise_isbn10, normalise_isbn13
from app.catalog.models import AccessLevel, Book, EditionUsageRights
from app.catalog.services.access import NoEntitlements, decide_access
from app.core.i18n import LocalizedText, negotiate, nfc, pick_locale, resolve
from app.provenance.rules import BlockReason, content_today, evaluate

TODAY = date(2026, 10, 1)


@dataclass
class Rec:
    verification_status: str = "verified"
    rights_status: str = "cleared"
    valid_from: date | None = None
    valid_until: date | None = None
    territories: list[str] = field(default_factory=lambda: ["BD"])
    excluded_territories: list[str] = field(default_factory=list)


def gate(*records: Rec) -> tuple[bool, tuple[BlockReason, ...]]:
    result = evaluate(records, today=TODAY, territory="BD")
    return result.publishable, result.reasons


# ------------------------------------------------------------------ publish gate


def test_gate_requires_some_provenance() -> None:
    assert gate() == (False, (BlockReason.NO_PROVENANCE,))


def test_gate_passes_with_verified_cleared_in_window_and_territory() -> None:
    assert gate(Rec()) == (True, ())
    assert gate(Rec(rights_status="public_domain", territories=["*"])) == (True, ())
    assert gate(Rec(valid_from=TODAY, valid_until=TODAY)) == (True, ())


@pytest.mark.parametrize(
    ("record", "reason"),
    [
        (Rec(verification_status="pending"), BlockReason.NOT_VERIFIED),
        (Rec(verification_status="unverified"), BlockReason.NOT_VERIFIED),
        (Rec(verification_status="rejected"), BlockReason.NOT_VERIFIED),
        (Rec(rights_status="pending"), BlockReason.RIGHTS_NOT_CLEARED),
        (Rec(rights_status="restricted"), BlockReason.RIGHTS_NOT_CLEARED),
        (Rec(valid_until=date(2026, 9, 30)), BlockReason.OUTSIDE_VALIDITY_WINDOW),
        (Rec(valid_from=date(2026, 10, 2)), BlockReason.OUTSIDE_VALIDITY_WINDOW),
        (Rec(territories=["IN"]), BlockReason.TERRITORY_NOT_COVERED),
        (Rec(territories=["*"], excluded_territories=["BD"]), BlockReason.TERRITORY_NOT_COVERED),
    ],
)
def test_gate_blocks_each_failing_condition(record: Rec, reason: BlockReason) -> None:
    assert gate(record) == (False, (reason,))


def test_one_passing_record_is_enough_but_a_verified_dispute_blocks() -> None:
    assert gate(Rec(verification_status="pending"), Rec()) == (True, ())
    assert gate(Rec(), Rec(rights_status="disputed")) == (False, (BlockReason.DISPUTED,))
    # A draft record claiming a dispute cannot take content down on its own.
    assert gate(Rec(), Rec(rights_status="disputed", verification_status="unverified")) == (True, ())


def test_gate_reports_the_closest_record() -> None:
    publishable, reasons = gate(
        Rec(verification_status="pending", rights_status="pending"), Rec(territories=["IN"])
    )
    assert not publishable and reasons == (BlockReason.TERRITORY_NOT_COVERED,)


def test_contract_dates_use_dhaka_calendar() -> None:
    # 19:00 UTC on 30 Sep is already 1 Oct in Dhaka (UTC+6).
    assert content_today(datetime(2026, 9, 30, 19, 0, tzinfo=UTC)) == date(2026, 10, 1)


# ------------------------------------------------------------------ ISBN


def test_isbn_normalisation_and_check_digits() -> None:
    assert normalise_isbn13("978-0-306-40615-7") == "9780306406157"
    assert normalise_isbn10("0-8044-2957-X") == "080442957X"
    for bad in ("9780306406158", "1234567890123", "97803064061"):
        with pytest.raises(ValueError, match="ISBN"):
            normalise_isbn13(bad)
    with pytest.raises(ValueError, match="check digit"):
        normalise_isbn10("0804429571")


# ------------------------------------------------------------------ localisation


def test_localized_text_requires_bangla_and_normalises() -> None:
    adapter = TypeAdapter(LocalizedText)
    decomposed = "কো"  # ক + ে + া (decomposed spelling of কো)
    value = adapter.validate_python({"bn": f"  {decomposed}  ", "en": "Physics", "fr": ""})
    assert value == {"bn": nfc(decomposed), "en": "Physics"}
    assert value["bn"] == "কো"  # composed vowel sign O
    with pytest.raises(ValidationError):
        adapter.validate_python({"en": "Physics"})
    with pytest.raises(ValidationError):
        adapter.validate_python({"bn": "x", "EN": "bad code"})


def test_resolution_fallback_order() -> None:
    label = {"bn": "পদার্থবিজ্ঞান", "en": "Physics"}
    assert resolve(label, "en") == "Physics"
    assert resolve(label, "en-GB") == "Physics"
    assert resolve(label, "ar") == "পদার্থবিজ্ঞান"
    assert resolve({"en": "Only English"}, "bn") == "Only English"
    assert resolve(None, "bn") is None
    assert pick_locale(["en"], "bn") == "en"
    assert pick_locale([], "bn") is None


def test_accept_language_negotiation() -> None:
    supported = ["bn", "en"]
    assert negotiate("en-US,en;q=0.9,bn;q=0.8", supported, "bn") == "en"
    assert negotiate("fr, bn;q=0.5", supported, "en") == "bn"
    assert negotiate("de", supported, "bn") == "bn"
    assert negotiate(None, supported, "bn") == "bn"
    assert negotiate("en;q=bogus, bn", supported, "en") == "bn"


# ------------------------------------------------------------------ access policy


def _book(level: AccessLevel, key: str | None = None) -> Book:
    return Book(slug="b", source_locale="bn", access_level=level, required_entitlement_key=key)


RIGHTS = EditionUsageRights(allow_preview=True, allow_read_online=True, allow_download=True)
USER = uuid.uuid4()


async def _decide(
    book: Book, user: uuid.UUID | None, *, rights: EditionUsageRights | None = RIGHTS, preview: bool = True
):
    return await decide_access(
        book,
        rights=rights,
        has_preview_content=preview,
        user_id=user,
        entitlements=NoEntitlements(),
        reader_enabled=False,
    )


async def test_free_books_are_readable_by_guests_but_never_downloadable_anonymously() -> None:
    decision = await _decide(_book(AccessLevel.FREE), None)
    assert (decision.state, decision.can_read, decision.can_download) == ("full", True, False)
    assert decision.reader_available is False


async def test_registered_books_need_sign_in() -> None:
    guest = await _decide(_book(AccessLevel.REGISTERED), None)
    assert (guest.state, guest.reasons) == ("preview_only", ("SIGN_IN_REQUIRED",))
    member = await _decide(_book(AccessLevel.REGISTERED), USER)
    assert (member.state, member.can_download) == ("full", True)


async def test_entitled_books_are_preview_only_without_an_entitlement() -> None:
    decision = await _decide(_book(AccessLevel.ENTITLED, "books.premium"), USER)
    assert decision.state == "preview_only" and decision.reasons == ("ENTITLEMENT_REQUIRED",)
    assert decision.acquire == {"entitlement_key": "books.premium"}
    guest = await _decide(_book(AccessLevel.ENTITLED, "books.premium"), None, preview=False)
    assert guest.state == "unavailable" and guest.reasons == ("SIGN_IN_REQUIRED", "ENTITLEMENT_REQUIRED")


async def test_usage_rights_restrict_reading_and_preview() -> None:
    no_online = EditionUsageRights(allow_preview=False, allow_read_online=False, allow_download=False)
    decision = await _decide(_book(AccessLevel.FREE), USER, rights=no_online)
    assert (decision.state, decision.reasons) == ("unavailable", ("RIGHTS_RESTRICTED",))
    missing = await _decide(_book(AccessLevel.FREE), USER, rights=None)
    assert missing.state == "unavailable" and "NOT_AVAILABLE" in missing.reasons

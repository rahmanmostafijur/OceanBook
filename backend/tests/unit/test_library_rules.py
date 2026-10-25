"""Shelf-state timestamp rules (pure)."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

from app.library.models import ShelfStatus
from app.library.service import shelf_timestamps

NOW = datetime(2026, 10, 26, 12, tzinfo=UTC)
EARLIER = NOW - timedelta(days=3)


def test_new_want_to_read_has_no_dates() -> None:
    assert shelf_timestamps(None, ShelfStatus.WANT_TO_READ, started_at=None, finished_at=None, now=NOW) == (
        None,
        None,
    )


def test_reading_stamps_start_once() -> None:
    assert shelf_timestamps(
        ShelfStatus.WANT_TO_READ, ShelfStatus.READING, started_at=None, finished_at=None, now=NOW
    ) == (NOW, None)
    assert shelf_timestamps(
        ShelfStatus.WANT_TO_READ, ShelfStatus.READING, started_at=EARLIER, finished_at=None, now=NOW
    ) == (EARLIER, None)


def test_finishing_stamps_finish_and_a_missing_start() -> None:
    assert shelf_timestamps(
        ShelfStatus.READING, ShelfStatus.FINISHED, started_at=EARLIER, finished_at=None, now=NOW
    ) == (EARLIER, NOW)
    assert shelf_timestamps(None, ShelfStatus.FINISHED, started_at=None, finished_at=None, now=NOW) == (
        NOW,
        NOW,
    )


def test_staying_finished_keeps_the_original_finish() -> None:
    assert shelf_timestamps(
        ShelfStatus.FINISHED, ShelfStatus.FINISHED, started_at=EARLIER, finished_at=EARLIER, now=NOW
    ) == (EARLIER, EARLIER)


def test_leaving_finished_clears_the_finish_but_keeps_the_start() -> None:
    for target in (ShelfStatus.READING, ShelfStatus.WANT_TO_READ):
        started, finished = shelf_timestamps(
            ShelfStatus.FINISHED, target, started_at=EARLIER, finished_at=EARLIER, now=NOW
        )
        assert finished is None and started == EARLIER


def test_control_characters_are_rejected_in_shelf_names_but_descriptions_keep_line_breaks() -> None:
    import pytest
    from pydantic import ValidationError

    from app.library.schemas import CollectionIn

    with pytest.raises(ValidationError):
        CollectionIn(name="a\x00b")
    with pytest.raises(ValidationError):
        CollectionIn(name="Weekend", description="bad\x07bell")
    assert CollectionIn(name="Weekend", description="line one\nline two").description == "line one\nline two"

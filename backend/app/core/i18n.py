"""Localisation primitives (docs/architecture/12 §4).

Short labels are `LocalizedText` JSONB objects keyed by locale (`{"bn": "...", "en": "..."}`); long-form,
reviewable content lives in `<entity>_translations` tables. All user-visible text is NFC-normalised.
"""

from __future__ import annotations

import re
import unicodedata
from collections.abc import Iterable, Mapping
from typing import Annotated

from fastapi import Header
from pydantic import AfterValidator

REQUIRED_LABEL_LOCALE = "bn"
FALLBACK_ORDER = ("bn", "en")
_LOCALE = re.compile(r"^[a-z]{2,3}(-[A-Z][a-z]{3})?(-[A-Z]{2})?$")
MAX_LABEL_LENGTH = 300


def nfc(value: str) -> str:
    return unicodedata.normalize("NFC", value).strip()


def _localized(value: dict[str, str]) -> dict[str, str]:
    cleaned: dict[str, str] = {}
    for locale, text in value.items():
        if not _LOCALE.match(locale):
            raise ValueError(f"Invalid locale code: {locale!r}")
        normalised = nfc(text)
        if not normalised:
            continue  # an empty translation is the same as no translation
        if len(normalised) > MAX_LABEL_LENGTH:
            raise ValueError(f"Label for {locale!r} is longer than {MAX_LABEL_LENGTH} characters")
        cleaned[locale] = normalised
    if REQUIRED_LABEL_LOCALE not in cleaned:
        raise ValueError(f"A {REQUIRED_LABEL_LOCALE!r} label is required")
    return cleaned


def _optional_localized(value: dict[str, str]) -> dict[str, str]:
    """Like LocalizedText, but the required-locale rule does not apply (e.g. attribution lines)."""
    cleaned = {}
    for locale, text in value.items():
        if not _LOCALE.match(locale):
            raise ValueError(f"Invalid locale code: {locale!r}")
        if normalised := nfc(text):
            cleaned[locale] = normalised[:2000]
    return cleaned


LocalizedText = Annotated[dict[str, str], AfterValidator(_localized)]
LooseLocalizedText = Annotated[dict[str, str], AfterValidator(_optional_localized)]


def resolve(text: Mapping[str, str] | None, locale: str) -> str | None:
    """Requested locale -> bn -> en -> first available (12 §4.1)."""
    if not text:
        return None
    for candidate in (locale, locale.split("-")[0], *FALLBACK_ORDER):
        if candidate in text:
            return text[candidate]
    return next(iter(text.values()))


def pick_locale(available: Iterable[str], locale: str) -> str | None:
    """Same fallback order, over a set of locales (e.g. the published translations of a book)."""
    present = list(available)
    for candidate in (locale, locale.split("-")[0], *FALLBACK_ORDER):
        if candidate in present:
            return candidate
    return present[0] if present else None


def negotiate(accept_language: str | None, supported: Iterable[str], default: str) -> str:
    """Best supported locale from an Accept-Language header (q-values honoured, malformed parts ignored)."""
    options = set(supported)
    ranked: list[tuple[float, int, str]] = []
    for index, part in enumerate((accept_language or "").split(",")[:20]):
        tag, _, params = part.strip().partition(";")
        quality = 1.0
        if params.strip().startswith("q="):
            try:
                quality = float(params.strip()[2:])
            except ValueError:
                continue
        ranked.append((-quality, index, tag.strip()))
    for _, _, tag in sorted(ranked):
        for candidate in (tag, tag.split("-")[0].lower()):
            if candidate in options:
                return candidate
    return default


def accept_language(accept_language: Annotated[str | None, Header(max_length=200)] = None) -> str | None:
    return accept_language

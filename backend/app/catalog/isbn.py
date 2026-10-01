"""ISBN normalisation with check-digit validation (hyphens and spaces are accepted on input)."""

from __future__ import annotations

import re

_SEPARATORS = re.compile(r"[\s-]")


def normalise_isbn13(value: str) -> str:
    digits = _SEPARATORS.sub("", value)
    if not re.fullmatch(r"97[89]\d{10}", digits):
        raise ValueError("ISBN-13 must be 13 digits starting with 978 or 979")
    total = sum(int(d) * (1 if i % 2 == 0 else 3) for i, d in enumerate(digits[:12]))
    if (10 - total % 10) % 10 != int(digits[12]):
        raise ValueError("ISBN-13 check digit is wrong")
    return digits


def normalise_isbn10(value: str) -> str:
    digits = _SEPARATORS.sub("", value).upper()
    if not re.fullmatch(r"\d{9}[\dX]", digits):
        raise ValueError("ISBN-10 must be 9 digits followed by a digit or X")
    total = sum((10 - i) * int(d) for i, d in enumerate(digits[:9]))
    check = 10 if digits[9] == "X" else int(digits[9])
    if (total + check) % 11 != 0:
        raise ValueError("ISBN-10 check digit is wrong")
    return digits

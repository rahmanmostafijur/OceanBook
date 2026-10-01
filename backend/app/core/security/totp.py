"""RFC 6238 TOTP (via pyotp) with replay protection and recovery codes."""

from __future__ import annotations

import hashlib
import hmac
import secrets
import time

import pyotp

PERIOD_SECONDS = 30
DIGITS = 6
VALID_WINDOW = 1  # accept the previous and next step to tolerate clock drift
RECOVERY_CODE_COUNT = 10
_RECOVERY_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # no 0/O, 1/I ambiguity


def new_secret() -> str:
    return pyotp.random_base32(length=32)  # 160 bits


def provisioning_uri(secret: str, *, account_name: str, issuer: str) -> str:
    return pyotp.TOTP(secret, digits=DIGITS, interval=PERIOD_SECONDS).provisioning_uri(
        name=account_name, issuer_name=issuer
    )


def matching_step(secret: str, code: str, *, after_step: int | None, now: float | None = None) -> int | None:
    """Return the time step the code belongs to, or None.

    Steps at or before `after_step` (the last accepted step) are rejected, so a code that was already
    used, or an older one, cannot be replayed.
    """
    if len(code) != DIGITS or not code.isdigit():
        return None
    totp = pyotp.TOTP(secret, digits=DIGITS, interval=PERIOD_SECONDS)
    current = int((now if now is not None else time.time()) // PERIOD_SECONDS)
    for step in range(current - VALID_WINDOW, current + VALID_WINDOW + 1):
        if after_step is not None and step <= after_step:
            continue
        if hmac.compare_digest(totp.generate_otp(step), code):
            return step
    return None


def new_recovery_codes() -> list[str]:
    def one() -> str:
        raw = "".join(secrets.choice(_RECOVERY_ALPHABET) for _ in range(12))
        return f"{raw[:4]}-{raw[4:8]}-{raw[8:]}"

    return [one() for _ in range(RECOVERY_CODE_COUNT)]


def hash_recovery_code(code: str) -> bytes:
    """Codes carry ~60 bits of entropy and are single-use; SHA-256 of the normalised form is sufficient."""
    normalised = code.replace("-", "").replace(" ", "").upper()
    return hashlib.sha256(normalised.encode()).digest()

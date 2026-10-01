"""Argon2id password hashing (PHC strings, so parameters can be upgraded on next login)."""

from __future__ import annotations

from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError, VerifyMismatchError

_hasher = PasswordHasher()  # argon2-cffi defaults follow RFC 9106's recommended profile

MIN_LENGTH = 8
MAX_LENGTH = 128

# Smallest set of the most common breached passwords; a k-anonymity HIBP range check is a later addition.
_COMMON = frozenset(
    {
        "password",
        "password1",
        "password123",
        "12345678",
        "123456789",
        "1234567890",
        "qwerty123",
        "11111111",
        "00000000",
        "iloveyou",
        "abc12345",
        "admin123",
        "letmein1",
        "welcome1",
        "bangladesh",
    }
)

# Verified against when the user does not exist, so timing doesn't reveal account existence.
_DUMMY_HASH = _hasher.hash("timing-equaliser-not-a-real-password")


def password_problem(password: str) -> str | None:
    if len(password) < MIN_LENGTH:
        return f"Password must be at least {MIN_LENGTH} characters"
    if len(password) > MAX_LENGTH:
        return f"Password must be at most {MAX_LENGTH} characters"
    if password.lower() in _COMMON:
        return "This password is too common"
    return None


def hash_password(password: str) -> str:
    return _hasher.hash(password)


def verify_password(password_hash: str | None, password: str) -> bool:
    try:
        return _hasher.verify(password_hash or _DUMMY_HASH, password) and password_hash is not None
    except (VerifyMismatchError, VerificationError, InvalidHashError):
        return False


def needs_rehash(password_hash: str) -> bool:
    return _hasher.check_needs_rehash(password_hash)

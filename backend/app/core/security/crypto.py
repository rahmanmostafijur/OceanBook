"""Field-level encryption for secrets at rest (e.g. TOTP seeds). AES-256-GCM with key ids for rotation.

Ciphertext layout: b"v1:" + key_id + b":" + nonce(12) + ciphertext||tag. The key id travels with the
data, so old rows stay decryptable after a rotation and can be re-encrypted lazily.
"""

from __future__ import annotations

import base64
import json
import os

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

from app.core.config import Settings
from app.core.logging import get_logger

log = get_logger(__name__)
_VERSION = b"v1"
_NONCE_BYTES = 12


class DecryptionError(Exception):
    pass


def _decode_key(encoded: str) -> bytes:
    key = base64.urlsafe_b64decode(encoded + "=" * (-len(encoded) % 4))
    if len(key) != 32:
        raise ValueError("data encryption keys must be 32 bytes (base64url)")
    return key


class FieldCipher:
    def __init__(self, *, active_key_id: str, keys: dict[str, bytes]) -> None:
        if active_key_id not in keys:
            raise ValueError("active key id missing from key set")
        if any(":" in kid for kid in keys):
            raise ValueError("key ids must not contain ':'")
        self._active = active_key_id
        self._keys = {kid: AESGCM(key) for kid, key in keys.items()}

    @classmethod
    def from_settings(cls, settings: Settings) -> FieldCipher:
        keys: dict[str, bytes] = {}
        if settings.data_encryption_previous_keys_json is not None:
            previous = json.loads(settings.data_encryption_previous_keys_json.get_secret_value())
            keys.update({kid: _decode_key(value) for kid, value in previous.items()})
        if settings.data_encryption_key is None:
            # Only reachable outside staging/production (Settings validation requires the key there).
            log.warning("data_encryption_ephemeral_key", detail="Encrypted fields are lost on restart")
            keys[settings.data_encryption_key_id] = AESGCM.generate_key(bit_length=256)
        else:
            keys[settings.data_encryption_key_id] = _decode_key(
                settings.data_encryption_key.get_secret_value()
            )
        return cls(active_key_id=settings.data_encryption_key_id, keys=keys)

    def encrypt(self, plaintext: bytes, *, context: bytes) -> bytes:
        """`context` (e.g. b"totp:<user_id>") is bound as associated data, so ciphertext can't be
        moved to another row."""
        nonce = os.urandom(_NONCE_BYTES)
        sealed = self._keys[self._active].encrypt(nonce, plaintext, context)
        return b":".join((_VERSION, self._active.encode())) + b":" + nonce + sealed

    def decrypt(self, blob: bytes, *, context: bytes) -> bytes:
        try:
            version, kid, rest = blob.split(b":", 2)
            if version != _VERSION:
                raise DecryptionError("unknown ciphertext version")
            cipher = self._keys[kid.decode()]
            return cipher.decrypt(rest[:_NONCE_BYTES], rest[_NONCE_BYTES:], context)
        except DecryptionError:
            raise
        except Exception as exc:  # wrong key, tampering, truncation, wrong context
            raise DecryptionError("cannot decrypt field") from exc

    def needs_reencryption(self, blob: bytes) -> bool:
        return not blob.startswith(_VERSION + b":" + self._active.encode() + b":")

"""UUIDv7 generation (RFC 9562), matching PostgreSQL 18's uuidv7().

Python 3.13's stdlib has no uuid7; ids must be generatable in the application so rows can be
created before a flush and, later, by offline clients.
"""

import os
import threading
import time
import uuid

_lock = threading.Lock()
_last_ms = 0
_counter = 0
_COUNTER_BITS = 12  # rand_a field used as a monotonic counter within one millisecond


def new_id() -> uuid.UUID:
    global _last_ms, _counter
    with _lock:
        now_ms = time.time_ns() // 1_000_000
        if now_ms > _last_ms:
            _last_ms = now_ms
            _counter = int.from_bytes(os.urandom(2)) & 0x3FF  # random start leaves headroom
        else:
            _counter += 1
            if _counter >= 1 << _COUNTER_BITS:  # counter exhausted: advance the logical clock
                _last_ms += 1
                _counter = 0
        ms, counter = _last_ms, _counter

    rand_b = int.from_bytes(os.urandom(8)) & ((1 << 62) - 1)
    value = (ms & ((1 << 48) - 1)) << 80
    value |= 0x7 << 76  # version 7
    value |= counter << 64
    value |= 0b10 << 62  # RFC 4122 variant
    value |= rand_b
    return uuid.UUID(int=value)

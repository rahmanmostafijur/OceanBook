"""Event handler registry for the worker. Modules register handlers here as they gain consumers.

Phase 1 has no business consumers yet (USER_REGISTERED gains its welcome notification in Phase 3);
the registry, idempotency guard and delivery path are in place and covered by tests.
"""

from app.platform.outbox import HandlerRegistry

registry = HandlerRegistry()

"""Imports every ORM model so Alembic sees the complete metadata. Add new modules here."""

from app.core.db import Base
from app.identity import models as identity_models  # noqa: F401
from app.platform import app_settings, audit, outbox  # noqa: F401

metadata = Base.metadata

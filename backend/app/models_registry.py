"""Imports every ORM model so Alembic sees the complete metadata. Add new modules here."""

from app.academics import models as academics_models  # noqa: F401
from app.catalog import models as catalog_models  # noqa: F401
from app.core.db import Base
from app.entitlements import models as entitlement_models  # noqa: F401
from app.identity import models as identity_models  # noqa: F401
from app.library import models as library_models  # noqa: F401
from app.media import models as media_models  # noqa: F401
from app.platform import app_settings, audit, outbox  # noqa: F401
from app.provenance import models as provenance_models  # noqa: F401
from app.questionbank import models as questionbank_models  # noqa: F401

metadata = Base.metadata

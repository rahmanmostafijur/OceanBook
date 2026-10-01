"""Alembic environment (async engine). Migrations fail fast instead of queueing behind live traffic."""

from __future__ import annotations

import asyncio
from logging.config import fileConfig

from alembic import context
from sqlalchemy import pool, text
from sqlalchemy.engine import Connection
from sqlalchemy.ext.asyncio import create_async_engine

from app.core.config import get_settings
from app.models_registry import metadata

config = context.config
if config.config_file_name is not None and config.attributes.get("configure_logger", True):
    fileConfig(config.config_file_name, disable_existing_loggers=False)

target_metadata = metadata


def _url() -> str:
    override = config.attributes.get("database_url")
    return str(override) if override else get_settings().database_url.get_secret_value()


def _include_object(obj: object, name: str | None, type_: str, reflected: bool, compare_to: object) -> bool:
    # Monthly partitions are created by the maintenance job, not modelled in SQLAlchemy.
    return not (type_ == "table" and reflected and name is not None and name.startswith("audit_logs_"))


def _run(connection: Connection) -> None:
    connection.execute(text("SET timezone = 'UTC'"))  # partition bounds and defaults are UTC
    connection.execute(text("SET lock_timeout = '5s'"))
    connection.execute(text("SET statement_timeout = '5min'"))
    context.configure(
        connection=connection,
        target_metadata=target_metadata,
        include_object=_include_object,
        compare_type=True,
        transaction_per_migration=True,
    )
    with context.begin_transaction():
        context.run_migrations()


async def _run_async() -> None:
    engine = create_async_engine(_url(), poolclass=pool.NullPool)
    async with engine.connect() as connection:
        await connection.run_sync(_run)
        await connection.commit()
    await engine.dispose()


if context.is_offline_mode():
    context.configure(url=_url(), target_metadata=target_metadata, literal_binds=True)
    with context.begin_transaction():
        context.run_migrations()
else:
    asyncio.run(_run_async())

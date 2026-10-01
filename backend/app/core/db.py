"""SQLAlchemy 2.x async engines and sessions with an explicit read/write split.

Services own transactions: they call `commit()` at the end of a use case. The session dependency
always closes the session, rolling back anything left uncommitted after an error.
"""

from __future__ import annotations

import uuid
from collections.abc import AsyncIterator
from dataclasses import dataclass
from datetime import datetime
from enum import StrEnum
from typing import Annotated

from fastapi import Depends, Request
from sqlalchemy import MetaData, func, text
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column
from sqlalchemy.types import DateTime, Uuid

from app.core.config import Settings
from app.core.ids import new_id

NAMING_CONVENTION = {
    "ix": "ix_%(table_name)s_%(column_0_N_name)s",
    "uq": "uq_%(table_name)s_%(column_0_N_name)s",
    "ck": "ck_%(table_name)s_%(constraint_name)s",
    "fk": "fk_%(table_name)s_%(column_0_name)s_%(referred_table_name)s",
    "pk": "pk_%(table_name)s",
}


def check_in(column: str, values: type[StrEnum]) -> str:
    """SQL for `column IN (...)` over a StrEnum: enumerations are text + CHECK (03 §1)."""
    return f"{column} IN ({', '.join(repr(v.value) for v in values)})"


class Base(DeclarativeBase):
    metadata = MetaData(naming_convention=NAMING_CONVENTION)


class UUIDPrimaryKey:
    id: Mapped[uuid.UUID] = mapped_column(
        Uuid, primary_key=True, default=new_id, server_default=text("uuidv7()")
    )


class CreatedAt:
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )


class Timestamps(CreatedAt):
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now(), onupdate=func.now()
    )


def _engine(url: str, settings: Settings) -> AsyncEngine:
    return create_async_engine(
        url,
        pool_size=settings.db_pool_size,
        max_overflow=settings.db_max_overflow,
        pool_pre_ping=True,
        hide_parameters=True,  # DB errors must never carry emails or hashes into logs
        pool_recycle=1800,
        connect_args={
            "server_settings": {
                "application_name": settings.service_name,
                "statement_timeout": str(settings.db_statement_timeout_ms),
                "timezone": "UTC",
            }
        },
    )


@dataclass(slots=True)
class Database:
    write_engine: AsyncEngine
    read_engine: AsyncEngine
    write_sessionmaker: async_sessionmaker[AsyncSession]
    read_sessionmaker: async_sessionmaker[AsyncSession]

    @classmethod
    def from_settings(cls, settings: Settings) -> Database:
        write = _engine(settings.database_url.get_secret_value(), settings)
        read = (
            write
            if settings.database_read_url is None
            else _engine(settings.database_read_url.get_secret_value(), settings)
        )
        return cls(
            write_engine=write,
            read_engine=read,
            write_sessionmaker=async_sessionmaker(write, expire_on_commit=False),
            read_sessionmaker=async_sessionmaker(read, expire_on_commit=False),
        )

    async def dispose(self) -> None:
        await self.write_engine.dispose()
        if self.read_engine is not self.write_engine:
            await self.read_engine.dispose()


def _database(request: Request) -> Database:
    db: Database = request.app.state.resources.db
    return db


async def get_write_session(request: Request) -> AsyncIterator[AsyncSession]:
    async with _database(request).write_sessionmaker() as session:
        yield session


async def get_read_session(request: Request) -> AsyncIterator[AsyncSession]:
    """Replica-tolerant reads only: never for authorisation, entitlements, or read-then-write."""
    async with _database(request).read_sessionmaker() as session:
        yield session


WriteSession = Annotated[AsyncSession, Depends(get_write_session)]
ReadSession = Annotated[AsyncSession, Depends(get_read_session)]

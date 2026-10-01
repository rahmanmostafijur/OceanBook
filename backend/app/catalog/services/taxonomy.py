"""Authors, publishers, categories (an ltree hierarchy) and tags. Every change is audited."""

from __future__ import annotations

import uuid
from collections.abc import Sequence
from typing import Any

from sqlalchemy import func, or_, select, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.catalog.models import Author, Category, Publisher, Tag
from app.catalog.schemas import (
    AuthorIn,
    AuthorPatch,
    CategoryIn,
    CategoryPatch,
    PublisherIn,
    PublisherPatch,
    TagIn,
    url_or_none,
)
from app.core.errors import Conflict, ErrorCode, NotFound, ValidationFailed
from app.core.request_info import ClientInfo
from app.identity.services.principal import Principal
from app.platform.audit import ActorType, record_audit

MAX_DEPTH = 5
# Category paths depend on their ancestors: creates, moves and retirements serialise on one lock.
_CATEGORY_LOCK = text("SELECT pg_advisory_xact_lock(hashtext('oceanbook.categories'))")


def like_pattern(query: str) -> str:
    escaped = query.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
    return f"%{escaped}%"


def slug_conflict(exc: IntegrityError) -> bool:
    return "uq_" in str(exc.orig) and "slug" in str(exc.orig)


def _values(body: Any) -> dict[str, Any]:
    values: dict[str, Any] = body.model_dump(exclude_unset=True)
    if "website" in values:
        values["website"] = url_or_none(body.website)
    return values


class TaxonomyService:
    def __init__(self, session: AsyncSession, client: ClientInfo) -> None:
        self.session = session
        self.client = client

    # ------------------------------------------------------------------ authors and publishers

    async def search_authors(
        self, *, query: str | None, offset: int, limit: int
    ) -> tuple[Sequence[Author], int]:
        return await self._search(Author, query, offset, limit)

    async def search_publishers(
        self, *, query: str | None, offset: int, limit: int
    ) -> tuple[Sequence[Publisher], int]:
        return await self._search(Publisher, query, offset, limit)

    async def _search[M: (Author, Publisher)](
        self, model: type[M], query: str | None, offset: int, limit: int
    ) -> tuple[Sequence[M], int]:
        condition = None
        if query:
            pattern = like_pattern(query)
            condition = or_(
                model.name.ilike(pattern), model.name_alt.ilike(pattern), model.slug.ilike(pattern)
            )
        base = select(model) if condition is None else select(model).where(condition)
        total = (await self.session.execute(select(func.count()).select_from(base.subquery()))).scalar_one()
        rows = (
            await self.session.execute(base.order_by(model.name, model.id).offset(offset).limit(limit))
        ).scalars()
        return rows.all(), total

    async def create_author(self, actor: Principal, body: AuthorIn) -> Author:
        return await self._create(actor, Author(**_values(body)), "author")

    async def update_author(self, actor: Principal, author_id: uuid.UUID, body: AuthorPatch) -> Author:
        author = await self._get(Author, author_id, "Author")
        values = _values(body)
        for name, value in values.items():
            setattr(author, name, value)
        if author.born_on and author.died_on and author.died_on < author.born_on:
            raise ValidationFailed("died_on must not be before born_on", field="died_on")
        return await self._save(actor, author, "author.updated", sorted(values))

    async def create_publisher(self, actor: Principal, body: PublisherIn) -> Publisher:
        return await self._create(actor, Publisher(**_values(body)), "publisher")

    async def update_publisher(
        self, actor: Principal, publisher_id: uuid.UUID, body: PublisherPatch
    ) -> Publisher:
        publisher = await self._get(Publisher, publisher_id, "Publisher")
        values = _values(body)
        for name, value in values.items():
            setattr(publisher, name, value)
        return await self._save(actor, publisher, "publisher.updated", sorted(values))

    # ------------------------------------------------------------------ tags

    async def list_tags(self) -> Sequence[Tag]:
        return (await self.session.execute(select(Tag).order_by(Tag.slug))).scalars().all()

    async def create_tag(self, actor: Principal, body: TagIn) -> Tag:
        return await self._create(actor, Tag(slug=body.slug, name=body.name), "tag")

    # ------------------------------------------------------------------ categories

    async def list_categories(self, *, include_inactive: bool) -> Sequence[Category]:
        query = select(Category).order_by(Category.depth, Category.position, Category.slug)
        if not include_inactive:
            query = query.where(Category.is_active)
        return (await self.session.execute(query)).scalars().all()

    async def create_category(self, actor: Principal, body: CategoryIn) -> Category:
        await self.session.execute(_CATEGORY_LOCK)
        path, depth = body.slug.replace("-", "_"), 0
        if body.parent_id is not None:
            parent = await self._active_parent(body.parent_id)
            path, depth = f"{parent.path}.{path}", parent.depth + 1
            if depth > MAX_DEPTH:
                raise ValidationFailed(f"Categories nest at most {MAX_DEPTH + 1} levels", field="parent_id")
        category = Category(
            slug=body.slug,
            parent_id=body.parent_id,
            path=path,
            depth=depth,
            name=body.name,
            description=body.description,
            icon=body.icon,
            position=body.position,
        )
        return await self._create(actor, category, "category")

    async def update_category(
        self, actor: Principal, category_id: uuid.UUID, body: CategoryPatch
    ) -> Category:
        await self.session.execute(_CATEGORY_LOCK)
        category = await self._get(Category, category_id, "Category", lock=True)
        values = body.model_dump(exclude_unset=True)
        if "parent_id" in values and values["parent_id"] != category.parent_id:
            await self._move(category, values.pop("parent_id"))
        else:
            values.pop("parent_id", None)
        if values.get("is_active") is False:
            await self._ensure_retirable(category)
        for name, value in values.items():
            setattr(category, name, value)
        return await self._save(actor, category, "category.updated", sorted(body.model_fields_set))

    async def _move(self, category: Category, parent_id: uuid.UUID | None) -> None:
        label = category.path.rsplit(".", 1)[-1]
        new_path, new_depth = label, 0
        if parent_id is not None:
            parent = await self._active_parent(parent_id)
            if parent.path == category.path or parent.path.startswith(f"{category.path}."):
                raise ValidationFailed("A category cannot move under itself", field="parent_id")
            new_path, new_depth = f"{parent.path}.{label}", parent.depth + 1
        deepest: int = (
            await self.session.execute(
                text("SELECT max(depth) FROM categories WHERE path <@ CAST(:p AS ltree)"),
                {"p": category.path},
            )
        ).scalar_one()
        if deepest - category.depth + new_depth > MAX_DEPTH:
            raise ValidationFailed(f"Categories nest at most {MAX_DEPTH + 1} levels", field="parent_id")
        move = text(
            "UPDATE categories SET "
            "path = CASE WHEN path = CAST(:old AS ltree) THEN CAST(:new AS ltree) "
            "ELSE CAST(:new AS ltree) || subpath(path, nlevel(CAST(:old AS ltree))) END, "
            "depth = depth + :delta "
            "WHERE path <@ CAST(:old AS ltree)"
        )
        try:
            await self.session.execute(
                move, {"new": new_path, "old": category.path, "delta": new_depth - category.depth}
            )
        except IntegrityError as exc:
            await self.session.rollback()
            raise Conflict(
                "A category with this slug already exists under the new parent",
                code=ErrorCode.SLUG_TAKEN,
                field="parent_id",
            ) from exc
        await self.session.refresh(category)
        category.parent_id = parent_id

    async def _active_parent(self, parent_id: uuid.UUID) -> Category:
        parent = await self._get(Category, parent_id, "Parent category")
        if not parent.is_active:
            raise ValidationFailed("Retired categories cannot take subcategories", field="parent_id")
        return parent

    async def _ensure_retirable(self, category: Category) -> None:
        active_children = (
            await self.session.execute(
                select(func.count()).where(Category.parent_id == category.id, Category.is_active)
            )
        ).scalar_one()
        if active_children:
            raise Conflict("Retire the subcategories first", code=ErrorCode.IN_USE)

    # ------------------------------------------------------------------ shared

    async def _get[M](self, model: type[M], entity_id: uuid.UUID, label: str, *, lock: bool = False) -> M:
        entity = await self.session.get(model, entity_id, with_for_update=lock, populate_existing=lock)
        if entity is None:
            raise NotFound(f"{label} not found")
        return entity

    async def _create[M: (Author, Publisher, Tag, Category)](
        self, actor: Principal, entity: M, kind: str
    ) -> M:
        self.session.add(entity)
        try:
            await self.session.flush()
        except IntegrityError as exc:
            await self.session.rollback()
            if slug_conflict(exc) or "uq_categories_path" in str(exc.orig):
                raise Conflict("This slug is already used", code=ErrorCode.SLUG_TAKEN, field="slug") from exc
            raise
        self._audit(actor, f"{kind}.created", kind, entity.id, {"slug": entity.slug})
        await self.session.commit()
        await self.session.refresh(entity)
        return entity

    async def _save[M: (Author, Publisher, Category)](
        self, actor: Principal, entity: M, action: str, fields: list[str]
    ) -> M:
        self._audit(actor, action, action.split(".")[0], entity.id, {"fields": fields})
        await self.session.commit()
        await self.session.refresh(entity)
        return entity

    def _audit(
        self, actor: Principal, action: str, entity_type: str, entity_id: uuid.UUID, after: dict[str, Any]
    ) -> None:
        record_audit(
            self.session,
            action=action,
            actor_type=ActorType.STAFF,
            actor_user_id=actor.user_id,
            entity_type=entity_type,
            entity_id=entity_id,
            after=after,
            ip=self.client.ip,
            user_agent=self.client.user_agent,
        )


async def category_subtree_ids(session: AsyncSession, slug: str) -> list[uuid.UUID] | None:
    """Ids of an active category and its active descendants, or None if the slug is unknown."""
    path = (
        await session.execute(select(Category.path).where(Category.slug == slug, Category.is_active))
    ).scalar_one_or_none()
    if path is None:
        return None
    rows = await session.execute(
        text("SELECT id FROM categories WHERE is_active AND path <@ CAST(:p AS ltree)"), {"p": path}
    )
    return [row[0] for row in rows]

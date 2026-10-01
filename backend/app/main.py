"""FastAPI application factory."""

from __future__ import annotations

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import APIRouter, FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.catalog.api import admin as catalog_admin
from app.catalog.api import public as catalog_public
from app.core.config import Environment, Settings, get_settings
from app.core.errors import register_error_handlers
from app.core.health import router as health_router
from app.core.logging import configure_logging
from app.core.middleware import BodySizeLimitMiddleware, RequestContextMiddleware, SecurityHeadersMiddleware
from app.core.resources import Resources
from app.identity.api import admin, auth, me
from app.identity.providers.registry import IdentityProviders
from app.provenance import api as provenance_api

API_PREFIX = "/api/v1"


def create_app(
    settings: Settings | None = None,
    *,
    resources: Resources | None = None,
    identity_providers: IdentityProviders | None = None,
) -> FastAPI:
    """Build the app. Tests pass `resources`; otherwise they are created at startup and closed at shutdown."""
    settings = settings or get_settings()
    configure_logging(level=settings.log_level, json_output=settings.log_json, service=settings.service_name)
    owns_resources = resources is None

    @asynccontextmanager
    async def lifespan(app: FastAPI) -> AsyncIterator[None]:
        if owns_resources:
            app.state.resources = Resources.create(settings)
        if owns_resources and identity_providers is None:
            app.state.identity_providers = IdentityProviders.create(settings, app.state.resources.redis)
        try:
            yield
        finally:
            if owns_resources:
                await app.state.resources.close()

    docs_enabled = settings.environment != Environment.PRODUCTION
    app = FastAPI(
        title="OceanBook API",
        version="1.0.0",
        lifespan=lifespan,
        docs_url=f"{API_PREFIX}/docs" if docs_enabled else None,
        redoc_url=None,
        openapi_url=f"{API_PREFIX}/openapi.json" if docs_enabled else None,
    )
    if resources is not None:
        app.state.resources = resources
        if identity_providers is None:
            app.state.identity_providers = IdentityProviders.create(settings, resources.redis)
    if identity_providers is not None:
        app.state.identity_providers = identity_providers

    register_error_handlers(app)

    # Starlette runs the last-added middleware first: request context wraps everything.
    if settings.cors_allow_origins:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=settings.cors_allow_origins,
            allow_credentials=True,
            allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE"],
            allow_headers=[
                "Authorization",
                "Content-Type",
                "Idempotency-Key",
                "If-Match",
                "X-Request-ID",
                "X-Device-Id",
                "X-App-Version",
                "Accept-Language",
            ],
            expose_headers=["X-Request-ID", "ETag", "Retry-After"],
            max_age=600,
        )
    app.add_middleware(BodySizeLimitMiddleware, max_bytes=settings.max_request_body_bytes)
    app.add_middleware(SecurityHeadersMiddleware, hsts=settings.is_deployed)
    app.add_middleware(RequestContextMiddleware)

    app.include_router(health_router)
    api = APIRouter(prefix=API_PREFIX)
    api.include_router(auth.router)
    api.include_router(me.router)
    api.include_router(admin.router)
    api.include_router(catalog_public.router)
    api.include_router(catalog_admin.router)
    api.include_router(provenance_api.router)
    app.include_router(api)
    return app

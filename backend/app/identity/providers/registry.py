"""Identity providers for one process, built from settings once at startup (tests substitute fakes)."""

from __future__ import annotations

from dataclasses import dataclass

from fastapi import Request
from redis.asyncio import Redis

from app.core.config import Settings
from app.core.errors import NotFound
from app.identity.models import IdentityProvider
from app.identity.providers.phone_otp import PhoneOtpProvider, create_phone_otp_provider
from app.identity.providers.social import (
    AppleIdentityProvider,
    GoogleIdentityProvider,
    SocialIdentityProvider,
)


@dataclass(slots=True)
class IdentityProviders:
    phone_otp: PhoneOtpProvider
    google: SocialIdentityProvider
    apple: SocialIdentityProvider

    @classmethod
    def create(cls, settings: Settings, redis: Redis) -> IdentityProviders:
        return cls(
            phone_otp=create_phone_otp_provider(settings, redis),
            google=GoogleIdentityProvider(
                settings.google_audiences, require_nonce=settings.google_require_nonce
            ),
            apple=AppleIdentityProvider(settings.apple_audiences),
        )

    def social(self, provider: IdentityProvider) -> SocialIdentityProvider:
        if provider == IdentityProvider.GOOGLE:
            return self.google
        if provider == IdentityProvider.APPLE:
            return self.apple
        raise NotFound("Unknown sign-in provider")


def get_identity_providers(request: Request) -> IdentityProviders:
    providers: IdentityProviders = request.app.state.identity_providers
    return providers

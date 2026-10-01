"""Operator CLI. Bootstraps the first super administrator (the API cannot grant roles to nobody).

Usage:
  python -m app.cli create-super-admin --email ops@example.org --name "Ops"   (password read from stdin)
  python -m app.cli issue-mfa-enrolment --email ops@example.org

Both print a one-time MFA enrolment token (valid 72 h). Staff can only enrol TOTP with such a token, and
staff routes only accept MFA-verified sessions, so a stolen staff password alone is never enough.
"""

from __future__ import annotations

import argparse
import asyncio
import getpass
import sys
import uuid

from sqlalchemy import select

from app.core.config import get_settings
from app.core.db import Database
from app.core.ids import new_id
from app.core.redis import create_redis
from app.core.security.passwords import hash_password, password_problem
from app.identity import repositories as repo
from app.identity.models import IdentityProvider, Role, User, UserIdentity, UserRole
from app.identity.permissions import SystemRole
from app.identity.services.login import normalise_email
from app.identity.services.step_up import issue_enrolment_token
from app.platform.audit import ActorType, record_audit


async def create_super_admin(email: str, name: str, password: str) -> str:
    db = Database.from_settings(get_settings())
    try:
        async with db.write_sessionmaker() as session:
            subject = normalise_email(email)
            if await repo.get_identity(session, IdentityProvider.PASSWORD, subject) is not None:
                raise SystemExit(f"A user with email {email} already exists")
            roles = (
                (
                    await session.execute(
                        select(Role).where(Role.key.in_([SystemRole.SUPER_ADMIN, SystemRole.STUDENT]))
                    )
                )
                .scalars()
                .all()
            )
            if len(roles) != 2:
                raise SystemExit("Roles are not seeded; run `alembic upgrade head` first")
            user = User(id=new_id(), display_name=name)
            session.add(user)
            await session.flush()
            session.add(
                UserIdentity(
                    user_id=user.id,
                    provider=IdentityProvider.PASSWORD,
                    provider_subject=subject,
                    provider_email=subject,
                    secret_hash=hash_password(password),
                )
            )
            for role in roles:
                session.add(UserRole(user_id=user.id, role_id=role.id))
            record_audit(
                session,
                action="user.super_admin_bootstrapped",
                actor_type=ActorType.SYSTEM,
                actor_user_id=None,
                entity_type="user",
                entity_id=user.id,
                reason="CLI bootstrap",
            )
            await session.commit()
            return str(user.id)
    finally:
        await db.dispose()


async def issue_enrolment(email: str | None = None, user_id: str | None = None) -> tuple[str, str]:
    settings = get_settings()
    db = Database.from_settings(settings)
    redis = create_redis(settings)
    try:
        async with db.write_sessionmaker() as session:
            if user_id is None:
                subject = normalise_email(email or "")
                identity = await repo.get_identity(session, IdentityProvider.PASSWORD, subject)
                if identity is None:
                    raise SystemExit(f"No account signs in with {email}")
                user_id = str(identity.user_id)
            uid = uuid.UUID(user_id)
            record_audit(
                session,
                action="auth.mfa_enrolment_issued",
                actor_type=ActorType.SYSTEM,
                actor_user_id=None,
                entity_type="user",
                entity_id=uid,
                reason="CLI",
            )
            await session.commit()
        token, expires = await issue_enrolment_token(redis, uid)
        return token, expires.isoformat()
    finally:
        await db.dispose()
        await redis.aclose()


def main() -> None:
    parser = argparse.ArgumentParser(prog="python -m app.cli")
    commands = parser.add_subparsers(dest="command", required=True)
    create = commands.add_parser("create-super-admin")
    create.add_argument("--email", required=True)
    create.add_argument("--name", required=True)
    enrol = commands.add_parser("issue-mfa-enrolment")
    enrol.add_argument("--email", required=True)
    args = parser.parse_args()

    if args.command == "issue-mfa-enrolment":
        token, expires = asyncio.run(issue_enrolment(email=args.email))
        print(f"MFA enrolment token (one use, expires {expires}):")  # noqa: T201
        print(token)  # noqa: T201
        return

    password = getpass.getpass("Password: ") if sys.stdin.isatty() else sys.stdin.readline().rstrip("\n")
    if problem := password_problem(password):
        raise SystemExit(problem)
    user_id = asyncio.run(create_super_admin(args.email, args.name, password))
    token, expires = asyncio.run(issue_enrolment(user_id=user_id))
    print(f"Created super administrator {user_id}")  # noqa: T201
    print(f"MFA enrolment token (one use, expires {expires}):")  # noqa: T201
    print(token)  # noqa: T201


if __name__ == "__main__":
    main()

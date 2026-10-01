"""Permission catalogue and system-role bundles.

Code checks permissions, never role names. The seed migration writes these rows; new roles can be
created as data. A test asserts this catalogue and the database stay in sync.
"""

from __future__ import annotations

from enum import StrEnum


class Permission(StrEnum):
    USERS_VIEW = "users.view"
    USERS_MANAGE = "users.manage"
    ROLES_VIEW = "roles.view"
    ROLES_ASSIGN = "roles.assign"
    AUDIT_VIEW = "audit.view"
    SYSTEM_VIEW = "system.view"


PERMISSION_DESCRIPTIONS: dict[Permission, str] = {
    Permission.USERS_VIEW: "View user accounts and their devices",
    Permission.USERS_MANAGE: "Suspend and reactivate user accounts, revoke sessions",
    Permission.ROLES_VIEW: "View roles and their permissions",
    Permission.ROLES_ASSIGN: "Grant and revoke roles",
    Permission.AUDIT_VIEW: "View the audit log",
    Permission.SYSTEM_VIEW: "View system health and queues",
}


class SystemRole(StrEnum):
    STUDENT = "student"
    CONTENT_EDITOR = "content_editor"
    REVIEWER = "reviewer"
    ADMIN = "admin"
    SUPER_ADMIN = "super_admin"


ROLE_NAMES: dict[SystemRole, str] = {
    SystemRole.STUDENT: "Student",
    SystemRole.CONTENT_EDITOR: "Content editor",
    SystemRole.REVIEWER: "Reviewer",
    SystemRole.ADMIN: "Administrator",
    SystemRole.SUPER_ADMIN: "Super administrator",
}

# Content permissions for editors/reviewers arrive with Phase 2 (catalog, question bank).
ROLE_PERMISSIONS: dict[SystemRole, frozenset[Permission]] = {
    SystemRole.STUDENT: frozenset(),
    SystemRole.CONTENT_EDITOR: frozenset(),
    SystemRole.REVIEWER: frozenset(),
    SystemRole.ADMIN: frozenset(
        {
            Permission.USERS_VIEW,
            Permission.USERS_MANAGE,
            Permission.ROLES_VIEW,
            Permission.AUDIT_VIEW,
            Permission.SYSTEM_VIEW,
        }
    ),
    SystemRole.SUPER_ADMIN: frozenset(Permission),
}

DEFAULT_ROLE = SystemRole.STUDENT
STAFF_ROLES = frozenset(
    {SystemRole.CONTENT_EDITOR, SystemRole.REVIEWER, SystemRole.ADMIN, SystemRole.SUPER_ADMIN}
)

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
    # Phase 2: catalog and provenance (migration 0004)
    CATALOG_VIEW = "catalog.view"
    CATALOG_EDIT = "catalog.edit"
    BOOKS_EDIT = "books.edit"
    BOOKS_PUBLISH = "books.publish"
    BOOKS_CHANGE_ACCESS = "books.change_access"
    RIGHTS_MANAGE = "rights.manage"
    PROVENANCE_EDIT = "provenance.edit"
    PROVENANCE_VERIFY = "provenance.verify"


PERMISSION_DESCRIPTIONS: dict[Permission, str] = {
    Permission.USERS_VIEW: "View user accounts and their devices",
    Permission.USERS_MANAGE: "Suspend and reactivate user accounts, revoke sessions",
    Permission.ROLES_VIEW: "View roles and their permissions",
    Permission.ROLES_ASSIGN: "Grant and revoke roles",
    Permission.AUDIT_VIEW: "View the audit log",
    Permission.SYSTEM_VIEW: "View system health and queues",
    Permission.CATALOG_VIEW: "View catalog records, drafts and provenance in the admin console",
    Permission.CATALOG_EDIT: "Create and edit authors, publishers, categories and tags",
    Permission.BOOKS_EDIT: "Create and edit books, editions, translations and tables of contents",
    Permission.BOOKS_PUBLISH: "Publish, unpublish and archive books after review",
    Permission.BOOKS_CHANGE_ACCESS: "Change a book's access level or required entitlement",
    Permission.RIGHTS_MANAGE: "Edit edition usage rights (preview, online reading, download, AI processing)",
    Permission.PROVENANCE_EDIT: "Register content sources and record provenance",
    Permission.PROVENANCE_VERIFY: "Verify or reject provenance recorded by someone else",
}

_CATALOG = frozenset(
    {
        Permission.CATALOG_VIEW,
        Permission.CATALOG_EDIT,
        Permission.BOOKS_EDIT,
        Permission.BOOKS_PUBLISH,
        Permission.BOOKS_CHANGE_ACCESS,
        Permission.RIGHTS_MANAGE,
        Permission.PROVENANCE_EDIT,
        Permission.PROVENANCE_VERIFY,
    }
)


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

# Editors prepare content and record provenance; reviewers publish and verify. Separation of duties
# (a verifier never verifies their own record) is enforced per record in the service, not by role.
ROLE_PERMISSIONS: dict[SystemRole, frozenset[Permission]] = {
    SystemRole.STUDENT: frozenset(),
    SystemRole.CONTENT_EDITOR: frozenset(
        {Permission.CATALOG_VIEW, Permission.CATALOG_EDIT, Permission.BOOKS_EDIT, Permission.PROVENANCE_EDIT}
    ),
    SystemRole.REVIEWER: frozenset(
        {Permission.CATALOG_VIEW, Permission.BOOKS_PUBLISH, Permission.PROVENANCE_VERIFY}
    ),
    SystemRole.ADMIN: frozenset(
        {
            Permission.USERS_VIEW,
            Permission.USERS_MANAGE,
            Permission.ROLES_VIEW,
            Permission.AUDIT_VIEW,
            Permission.SYSTEM_VIEW,
        }
    )
    | _CATALOG,
    SystemRole.SUPER_ADMIN: frozenset(Permission),
}

DEFAULT_ROLE = SystemRole.STUDENT
STAFF_ROLES = frozenset(
    {SystemRole.CONTENT_EDITOR, SystemRole.REVIEWER, SystemRole.ADMIN, SystemRole.SUPER_ADMIN}
)

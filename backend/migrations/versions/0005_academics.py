"""Academics: curricula, levels, boards, groups, subjects, chapters, topics, instruction media.

Implements docs/architecture/03 §7 as revised by 12 §4.1 and §6 (LocalizedText labels, instruction
media), plus the links 14 C16 deferred to the question-bank milestone: `content_sources.board_id`
and `book_subjects`. Seeds levels, boards, instruction media and the question-bank permissions
(frozen here; tests/integration/test_platform.py asserts the catalogue matches app.identity.permissions).

Revision ID: 0005
Revises: 0004
Create Date: 2026-10-17
"""

import json
from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = '0005'
down_revision: str | None = '0004'
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

PERMISSIONS = {
    "academics.manage": "Manage curricula, levels, boards, groups, subjects, chapters and topics",
    "questions.view": "View questions, stimuli, papers and reports in the admin console",
    "questions.edit": "Create and edit questions, stimuli and question papers; submit for review",
    "questions.review": "Approve, reject or request changes on questions written by others",
    "questions.publish": "Publish and archive questions and question papers; resolve reports",
}
ROLE_PERMISSIONS = {
    "content_editor": ["questions.view", "questions.edit"],
    "reviewer": ["questions.view", "questions.review", "questions.publish"],
    "admin": list(PERMISSIONS),
    "super_admin": list(PERMISSIONS),
}
LEVELS = [
    ("ssc", {"bn": "এসএসসি", "en": "SSC"}, 1),
    ("hsc", {"bn": "এইচএসসি", "en": "HSC"}, 2),
]
BOARDS = [
    ("dhaka", {"bn": "ঢাকা", "en": "Dhaka"}, "general"),
    ("rajshahi", {"bn": "রাজশাহী", "en": "Rajshahi"}, "general"),
    ("cumilla", {"bn": "কুমিল্লা", "en": "Cumilla"}, "general"),
    ("jashore", {"bn": "যশোর", "en": "Jashore"}, "general"),
    ("chattogram", {"bn": "চট্টগ্রাম", "en": "Chattogram"}, "general"),
    ("barishal", {"bn": "বরিশাল", "en": "Barishal"}, "general"),
    ("sylhet", {"bn": "সিলেট", "en": "Sylhet"}, "general"),
    ("dinajpur", {"bn": "দিনাজপুর", "en": "Dinajpur"}, "general"),
    ("mymensingh", {"bn": "ময়মনসিংহ", "en": "Mymensingh"}, "general"),
    ("madrasah", {"bn": "মাদ্রাসা", "en": "Madrasah"}, "madrasah"),
    ("technical", {"bn": "কারিগরি", "en": "Technical"}, "technical"),
]
MEDIA = [
    ("bangla_medium", {"bn": "বাংলা মাধ্যম", "en": "Bangla medium"}, "bn"),
    ("english_version", {"bn": "ইংরেজি ভার্সন", "en": "English version"}, "en"),
]

UPSERT_PERMISSION = sa.text(
    "INSERT INTO permissions (key, description) VALUES (:key, :description) "
    "ON CONFLICT (key) DO UPDATE SET description = EXCLUDED.description"
)
LINK_PERMISSION = sa.text(
    "INSERT INTO role_permissions (role_id, permission_key) "
    "SELECT id, :permission FROM roles WHERE key = :role ON CONFLICT DO NOTHING"
)


def upgrade() -> None:
    op.create_table('boards',
    sa.Column('key', sa.Text(), nullable=False),
    sa.Column('name', postgresql.JSONB(astext_type=sa.Text()), nullable=False),
    sa.Column('board_type', sa.Text(), nullable=False),
    sa.Column('is_active', sa.Boolean(), server_default='true', nullable=False),
    sa.Column('id', sa.Uuid(), server_default=sa.text('uuidv7()'), nullable=False),
    sa.CheckConstraint("board_type IN ('general', 'madrasah', 'technical')", name=op.f('ck_boards_board_type')),
    sa.CheckConstraint("jsonb_typeof(name) = 'object' AND name ? 'bn'", name=op.f('ck_boards_name_localized')),
    sa.CheckConstraint("key ~ '^[a-z][a-z0-9_]*$' AND char_length(key) <= 60", name=op.f('ck_boards_key_format')),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_boards')),
    sa.UniqueConstraint('key', name=op.f('uq_boards_key'))
    )
    op.create_table('curricula',
    sa.Column('key', sa.Text(), nullable=False),
    sa.Column('name', postgresql.JSONB(astext_type=sa.Text()), nullable=False),
    sa.Column('effective_from_year', sa.SmallInteger(), nullable=True),
    sa.Column('effective_to_year', sa.SmallInteger(), nullable=True),
    sa.Column('is_current', sa.Boolean(), server_default='false', nullable=False),
    sa.Column('id', sa.Uuid(), server_default=sa.text('uuidv7()'), nullable=False),
    sa.CheckConstraint("jsonb_typeof(name) = 'object' AND name ? 'bn'", name=op.f('ck_curricula_name_localized')),
    sa.CheckConstraint("key ~ '^[a-z][a-z0-9_]*$' AND char_length(key) <= 60", name=op.f('ck_curricula_key_format')),
    sa.CheckConstraint('effective_to_year IS NULL OR effective_from_year IS NULL OR effective_to_year >= effective_from_year', name=op.f('ck_curricula_years')),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_curricula')),
    sa.UniqueConstraint('key', name=op.f('uq_curricula_key'))
    )
    op.create_index('uq_curricula_current', 'curricula', ['is_current'], unique=True, postgresql_where=sa.text('is_current'))
    op.create_table('education_levels',
    sa.Column('key', sa.Text(), nullable=False),
    sa.Column('name', postgresql.JSONB(astext_type=sa.Text()), nullable=False),
    sa.Column('position', sa.SmallInteger(), server_default='0', nullable=False),
    sa.Column('is_active', sa.Boolean(), server_default='true', nullable=False),
    sa.Column('id', sa.Uuid(), server_default=sa.text('uuidv7()'), nullable=False),
    sa.CheckConstraint("jsonb_typeof(name) = 'object' AND name ? 'bn'", name=op.f('ck_education_levels_name_localized')),
    sa.CheckConstraint("key ~ '^[a-z][a-z0-9_]*$' AND char_length(key) <= 60", name=op.f('ck_education_levels_key_format')),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_education_levels')),
    sa.UniqueConstraint('key', name=op.f('uq_education_levels_key'))
    )
    op.create_table('instruction_media',
    sa.Column('key', sa.Text(), nullable=False),
    sa.Column('name', postgresql.JSONB(astext_type=sa.Text()), nullable=False),
    sa.Column('content_locale', sa.Text(), nullable=False),
    sa.Column('is_active', sa.Boolean(), server_default='true', nullable=False),
    sa.Column('id', sa.Uuid(), server_default=sa.text('uuidv7()'), nullable=False),
    sa.CheckConstraint("content_locale ~ '^[a-z]{2,3}(-[A-Z][a-z]{3})?(-[A-Z]{2})?$'", name=op.f('ck_instruction_media_locale_format')),
    sa.CheckConstraint("jsonb_typeof(name) = 'object' AND name ? 'bn'", name=op.f('ck_instruction_media_name_localized')),
    sa.CheckConstraint("key ~ '^[a-z][a-z0-9_]*$' AND char_length(key) <= 60", name=op.f('ck_instruction_media_key_format')),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_instruction_media')),
    sa.UniqueConstraint('key', name=op.f('uq_instruction_media_key'))
    )
    op.create_table('academic_groups',
    sa.Column('education_level_id', sa.Uuid(), nullable=False),
    sa.Column('key', sa.Text(), nullable=False),
    sa.Column('name', postgresql.JSONB(astext_type=sa.Text()), nullable=False),
    sa.Column('id', sa.Uuid(), server_default=sa.text('uuidv7()'), nullable=False),
    sa.CheckConstraint("jsonb_typeof(name) = 'object' AND name ? 'bn'", name=op.f('ck_academic_groups_name_localized')),
    sa.CheckConstraint("key ~ '^[a-z][a-z0-9_]*$' AND char_length(key) <= 60", name=op.f('ck_academic_groups_key_format')),
    sa.ForeignKeyConstraint(['education_level_id'], ['education_levels.id'], name=op.f('fk_academic_groups_education_level_id_education_levels'), ondelete='RESTRICT'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_academic_groups')),
    sa.UniqueConstraint('education_level_id', 'key', name=op.f('uq_academic_groups_education_level_id_key'))
    )
    op.create_table('subjects',
    sa.Column('curriculum_id', sa.Uuid(), nullable=False),
    sa.Column('education_level_id', sa.Uuid(), nullable=False),
    sa.Column('slug', sa.Text(), nullable=False),
    sa.Column('family_key', sa.Text(), nullable=False),
    sa.Column('board_code', sa.Text(), nullable=True),
    sa.Column('paper_number', sa.SmallInteger(), nullable=True),
    sa.Column('name', postgresql.JSONB(astext_type=sa.Text()), nullable=False),
    sa.Column('icon', sa.Text(), nullable=True),
    sa.Column('position', sa.Integer(), server_default='0', nullable=False),
    sa.Column('is_active', sa.Boolean(), server_default='true', nullable=False),
    sa.Column('id', sa.Uuid(), server_default=sa.text('uuidv7()'), nullable=False),
    sa.CheckConstraint("family_key ~ '^[a-z][a-z0-9_]*$' AND char_length(family_key) <= 60", name=op.f('ck_subjects_family_format')),
    sa.CheckConstraint("jsonb_typeof(name) = 'object' AND name ? 'bn'", name=op.f('ck_subjects_name_localized')),
    sa.CheckConstraint("slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' AND char_length(slug) <= 120", name=op.f('ck_subjects_slug_format')),
    sa.CheckConstraint('paper_number IN (1, 2)', name=op.f('ck_subjects_paper_number')),
    sa.ForeignKeyConstraint(['curriculum_id'], ['curricula.id'], name=op.f('fk_subjects_curriculum_id_curricula'), ondelete='RESTRICT'),
    sa.ForeignKeyConstraint(['education_level_id'], ['education_levels.id'], name=op.f('fk_subjects_education_level_id_education_levels'), ondelete='RESTRICT'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_subjects')),
    sa.UniqueConstraint('curriculum_id', 'education_level_id', 'slug', name=op.f('uq_subjects_curriculum_id_education_level_id_slug'))
    )
    op.create_index('ix_subjects_education_level_id_curriculum_id_position', 'subjects', ['education_level_id', 'curriculum_id', 'position'], unique=False, postgresql_where=sa.text('is_active'))
    op.create_index('ix_subjects_family_key', 'subjects', ['family_key'], unique=False)
    op.create_table('chapters',
    sa.Column('subject_id', sa.Uuid(), nullable=False),
    sa.Column('number', sa.SmallInteger(), nullable=False),
    sa.Column('name', postgresql.JSONB(astext_type=sa.Text()), nullable=False),
    sa.Column('position', sa.Integer(), server_default='0', nullable=False),
    sa.Column('is_active', sa.Boolean(), server_default='true', nullable=False),
    sa.Column('id', sa.Uuid(), server_default=sa.text('uuidv7()'), nullable=False),
    sa.CheckConstraint("jsonb_typeof(name) = 'object' AND name ? 'bn'", name=op.f('ck_chapters_name_localized')),
    sa.CheckConstraint('number BETWEEN 1 AND 200', name=op.f('ck_chapters_number')),
    sa.ForeignKeyConstraint(['subject_id'], ['subjects.id'], name=op.f('fk_chapters_subject_id_subjects'), ondelete='RESTRICT'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_chapters')),
    sa.UniqueConstraint('id', 'subject_id', name=op.f('uq_chapters_id_subject_id')),
    sa.UniqueConstraint('subject_id', 'number', name=op.f('uq_chapters_subject_id_number'))
    )
    op.create_table('subject_groups',
    sa.Column('subject_id', sa.Uuid(), nullable=False),
    sa.Column('group_id', sa.Uuid(), nullable=False),
    sa.Column('offering', sa.Text(), nullable=False),
    sa.CheckConstraint("offering IN ('compulsory', 'elective', 'optional')", name=op.f('ck_subject_groups_offering')),
    sa.ForeignKeyConstraint(['group_id'], ['academic_groups.id'], name=op.f('fk_subject_groups_group_id_academic_groups'), ondelete='CASCADE'),
    sa.ForeignKeyConstraint(['subject_id'], ['subjects.id'], name=op.f('fk_subject_groups_subject_id_subjects'), ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('subject_id', 'group_id', name=op.f('pk_subject_groups'))
    )
    op.create_table('topics',
    sa.Column('chapter_id', sa.Uuid(), nullable=False),
    sa.Column('name', postgresql.JSONB(astext_type=sa.Text()), nullable=False),
    sa.Column('position', sa.Integer(), server_default='0', nullable=False),
    sa.Column('is_active', sa.Boolean(), server_default='true', nullable=False),
    sa.Column('id', sa.Uuid(), server_default=sa.text('uuidv7()'), nullable=False),
    sa.CheckConstraint("jsonb_typeof(name) = 'object' AND name ? 'bn'", name=op.f('ck_topics_name_localized')),
    sa.ForeignKeyConstraint(['chapter_id'], ['chapters.id'], name=op.f('fk_topics_chapter_id_chapters'), ondelete='RESTRICT'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_topics')),
    sa.UniqueConstraint('id', 'chapter_id', name=op.f('uq_topics_id_chapter_id'))
    )
    op.add_column("content_sources", sa.Column("board_id", sa.Uuid(), nullable=True))
    op.create_foreign_key(
        op.f("fk_content_sources_board_id_boards"), "content_sources", "boards", ["board_id"], ["id"], ondelete="SET NULL"
    )
    op.create_table(
        "book_subjects",
        sa.Column("book_id", sa.Uuid(), nullable=False),
        sa.Column("subject_id", sa.Uuid(), nullable=False),
        sa.ForeignKeyConstraint(["book_id"], ["books.id"], name=op.f("fk_book_subjects_book_id_books"), ondelete="CASCADE"),
        sa.ForeignKeyConstraint(
            ["subject_id"], ["subjects.id"], name=op.f("fk_book_subjects_subject_id_subjects"), ondelete="RESTRICT"
        ),
        sa.PrimaryKeyConstraint("book_id", "subject_id", name=op.f("pk_book_subjects")),
    )
    op.create_index("ix_book_subjects_subject_id", "book_subjects", ["subject_id"], unique=False)
    _seed()


def _seed() -> None:
    bind = op.get_bind()
    for key, description in PERMISSIONS.items():
        bind.execute(UPSERT_PERMISSION, {"key": key, "description": description})
    for role, permissions in ROLE_PERMISSIONS.items():
        for permission in permissions:
            bind.execute(LINK_PERMISSION, {"role": role, "permission": permission})
    for key, name, position in LEVELS:
        bind.execute(
            sa.text(
                "INSERT INTO education_levels (key, name, position) VALUES (:k, CAST(:n AS jsonb), :p) "
                "ON CONFLICT (key) DO NOTHING"
            ),
            {"k": key, "n": json.dumps(name, ensure_ascii=False), "p": position},
        )
    for key, name, board_type in BOARDS:
        bind.execute(
            sa.text(
                "INSERT INTO boards (key, name, board_type) VALUES (:k, CAST(:n AS jsonb), :t) "
                "ON CONFLICT (key) DO NOTHING"
            ),
            {"k": key, "n": json.dumps(name, ensure_ascii=False), "t": board_type},
        )
    for key, name, locale in MEDIA:
        bind.execute(
            sa.text(
                "INSERT INTO instruction_media (key, name, content_locale) VALUES (:k, CAST(:n AS jsonb), :l) "
                "ON CONFLICT (key) DO NOTHING"
            ),
            {"k": key, "n": json.dumps(name, ensure_ascii=False), "l": locale},
        )


def downgrade() -> None:
    bind = op.get_bind()
    for permission in PERMISSIONS:
        bind.execute(sa.text("DELETE FROM role_permissions WHERE permission_key = :p"), {"p": permission})
        bind.execute(sa.text("DELETE FROM permissions WHERE key = :p"), {"p": permission})
    op.drop_index("ix_book_subjects_subject_id", table_name="book_subjects")
    op.drop_table("book_subjects")
    op.drop_constraint(op.f("fk_content_sources_board_id_boards"), "content_sources", type_="foreignkey")
    op.drop_column("content_sources", "board_id")
    op.drop_table('topics')
    op.drop_table('subject_groups')
    op.drop_table('chapters')
    op.drop_index('ix_subjects_family_key', table_name='subjects')
    op.drop_index('ix_subjects_education_level_id_curriculum_id_position', table_name='subjects', postgresql_where=sa.text('is_active'))
    op.drop_table('subjects')
    op.drop_table('academic_groups')
    op.drop_table('instruction_media')
    op.drop_table('education_levels')
    op.drop_index('uq_curricula_current', table_name='curricula', postgresql_where=sa.text('is_current'))
    op.drop_table('curricula')
    op.drop_table('boards')

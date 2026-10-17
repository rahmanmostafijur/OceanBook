"""Question bank: stimuli, questions with translations, options, parts, revisions, reviews, papers, reports.

Implements docs/architecture/03 §8 as revised by 12 §4.2 and §5. Editable content lives in
`question_revisions.snapshot`; the live tables hold the published version. Provenance records may now
name a question paper, a question or a stimulus, so the one-subject CHECK is widened here (14 C16).

Revision ID: 0006
Revises: 0005
Create Date: 2026-10-17
"""
from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = '0006'
down_revision: str | None = '0005'
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table('question_stimuli',
    sa.Column('source_locale', sa.Text(), nullable=False),
    sa.Column('created_by', sa.Uuid(), nullable=True),
    sa.Column('id', sa.Uuid(), server_default=sa.text('uuidv7()'), nullable=False),
    sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.CheckConstraint("source_locale ~ '^[a-z]{2,3}(-[A-Z][a-z]{3})?(-[A-Z]{2})?$'", name=op.f('ck_question_stimuli_source_locale')),
    sa.ForeignKeyConstraint(['created_by'], ['users.id'], name=op.f('fk_question_stimuli_created_by_users'), ondelete='SET NULL'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_question_stimuli'))
    )
    op.create_table('question_papers',
    sa.Column('education_level_id', sa.Uuid(), nullable=False),
    sa.Column('subject_id', sa.Uuid(), nullable=False),
    sa.Column('academic_group_id', sa.Uuid(), nullable=True),
    sa.Column('instruction_medium_id', sa.Uuid(), nullable=True),
    sa.Column('exam_year', sa.SmallInteger(), nullable=False),
    sa.Column('exam_kind', sa.Text(), nullable=False),
    sa.Column('section', sa.Text(), server_default='full', nullable=False),
    sa.Column('title', sa.Text(), nullable=True),
    sa.Column('total_marks', sa.Numeric(precision=6, scale=2), nullable=True),
    sa.Column('duration_minutes', sa.SmallInteger(), nullable=True),
    sa.Column('board_set_key', sa.Text(), nullable=False),
    sa.Column('access_level', sa.Text(), server_default='free', nullable=False),
    sa.Column('required_entitlement_key', sa.Text(), nullable=True),
    sa.Column('status', sa.Text(), server_default='draft', nullable=False),
    sa.Column('created_by', sa.Uuid(), nullable=True),
    sa.Column('published_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('id', sa.Uuid(), server_default=sa.text('uuidv7()'), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.CheckConstraint("access_level <> 'entitled' OR required_entitlement_key IS NOT NULL", name=op.f('ck_question_papers_entitled')),
    sa.CheckConstraint("access_level IN ('free', 'registered', 'entitled')", name=op.f('ck_question_papers_access_level')),
    sa.CheckConstraint("exam_kind IN ('board_final', 'test', 'pre_test', 'model', 'admission')", name=op.f('ck_question_papers_exam_kind')),
    sa.CheckConstraint("section IN ('full', 'mcq', 'cq')", name=op.f('ck_question_papers_section')),
    sa.CheckConstraint("status IN ('draft', 'published', 'archived')", name=op.f('ck_question_papers_status')),
    sa.CheckConstraint('exam_year BETWEEN 1990 AND 2100', name=op.f('ck_question_papers_exam_year')),
    sa.ForeignKeyConstraint(['academic_group_id'], ['academic_groups.id'], name=op.f('fk_question_papers_academic_group_id_academic_groups'), ondelete='RESTRICT'),
    sa.ForeignKeyConstraint(['created_by'], ['users.id'], name=op.f('fk_question_papers_created_by_users'), ondelete='SET NULL'),
    sa.ForeignKeyConstraint(['education_level_id'], ['education_levels.id'], name=op.f('fk_question_papers_education_level_id_education_levels'), ondelete='RESTRICT'),
    sa.ForeignKeyConstraint(['instruction_medium_id'], ['instruction_media.id'], name=op.f('fk_question_papers_instruction_medium_id_instruction_media'), ondelete='RESTRICT'),
    sa.ForeignKeyConstraint(['required_entitlement_key'], ['entitlement_definitions.key'], name=op.f('fk_question_papers_required_entitlement_key_entitlement_definitions'), ondelete='RESTRICT'),
    sa.ForeignKeyConstraint(['subject_id'], ['subjects.id'], name=op.f('fk_question_papers_subject_id_subjects'), ondelete='RESTRICT'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_question_papers')),
    sa.UniqueConstraint('education_level_id', 'subject_id', 'exam_year', 'exam_kind', 'section', 'board_set_key', name=op.f('uq_question_papers_education_level_id_subject_id_exam_year_exam_kind_section_board_set_key'))
    )
    op.create_index('ix_question_papers_browse', 'question_papers', ['education_level_id', 'subject_id', sa.literal_column('exam_year DESC')], unique=False, postgresql_where=sa.text("status = 'published'"))
    op.create_table('stimulus_translations',
    sa.Column('stimulus_id', sa.Uuid(), nullable=False),
    sa.Column('locale', sa.Text(), nullable=False),
    sa.Column('content', postgresql.JSONB(astext_type=sa.Text()), nullable=False),
    sa.Column('plain_text', sa.Text(), nullable=False),
    sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.CheckConstraint("locale ~ '^[a-z]{2,3}(-[A-Z][a-z]{3})?(-[A-Z]{2})?$'", name=op.f('ck_stimulus_translations_locale')),
    sa.ForeignKeyConstraint(['stimulus_id'], ['question_stimuli.id'], name=op.f('fk_stimulus_translations_stimulus_id_question_stimuli'), ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('stimulus_id', 'locale', name=op.f('pk_stimulus_translations'))
    )
    op.create_table('question_paper_boards',
    sa.Column('paper_id', sa.Uuid(), nullable=False),
    sa.Column('board_id', sa.Uuid(), nullable=False),
    sa.ForeignKeyConstraint(['board_id'], ['boards.id'], name=op.f('fk_question_paper_boards_board_id_boards'), ondelete='RESTRICT'),
    sa.ForeignKeyConstraint(['paper_id'], ['question_papers.id'], name=op.f('fk_question_paper_boards_paper_id_question_papers'), ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('paper_id', 'board_id', name=op.f('pk_question_paper_boards'))
    )
    op.create_index('ix_question_paper_boards_board_id_paper_id', 'question_paper_boards', ['board_id', 'paper_id'], unique=False)
    op.create_table('questions',
    sa.Column('type', sa.Text(), nullable=False),
    sa.Column('source_locale', sa.Text(), nullable=False),
    sa.Column('stimulus_id', sa.Uuid(), nullable=True),
    sa.Column('education_level_id', sa.Uuid(), nullable=False),
    sa.Column('subject_id', sa.Uuid(), nullable=False),
    sa.Column('chapter_id', sa.Uuid(), nullable=True),
    sa.Column('topic_id', sa.Uuid(), nullable=True),
    sa.Column('difficulty', sa.SmallInteger(), nullable=True),
    sa.Column('cognitive_level', sa.Text(), nullable=True),
    sa.Column('marks', sa.Numeric(precision=5, scale=2), server_default='1', nullable=False),
    sa.Column('answer_spec', postgresql.JSONB(astext_type=sa.Text()), server_default='{}', nullable=False),
    sa.Column('status', sa.Text(), server_default='draft', nullable=False),
    sa.Column('access_level', sa.Text(), server_default='free', nullable=False),
    sa.Column('required_entitlement_key', sa.Text(), nullable=True),
    sa.Column('version', sa.Integer(), server_default='0', nullable=False),
    sa.Column('latest_revision', sa.Integer(), server_default='1', nullable=False),
    sa.Column('pending_status', sa.Text(), nullable=True),
    sa.Column('content_hash', sa.LargeBinary(), nullable=False),
    sa.Column('created_by', sa.Uuid(), nullable=True),
    sa.Column('reviewed_by', sa.Uuid(), nullable=True),
    sa.Column('published_by', sa.Uuid(), nullable=True),
    sa.Column('published_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('deleted_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('id', sa.Uuid(), server_default=sa.text('uuidv7()'), nullable=False),
    sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.CheckConstraint("access_level <> 'entitled' OR required_entitlement_key IS NOT NULL", name=op.f('ck_questions_entitled')),
    sa.CheckConstraint("access_level IN ('free', 'registered', 'entitled')", name=op.f('ck_questions_access_level')),
    sa.CheckConstraint("cognitive_level IS NULL OR cognitive_level IN ('knowledge', 'comprehension', 'application', 'higher_order')", name=op.f('ck_questions_cognitive_level')),
    sa.CheckConstraint("pending_status IS NULL OR pending_status IN ('draft', 'in_review', 'changes_requested', 'approved', 'published', 'superseded')", name=op.f('ck_questions_pending_status')),
    sa.CheckConstraint("source_locale ~ '^[a-z]{2,3}(-[A-Z][a-z]{3})?(-[A-Z]{2})?$'", name=op.f('ck_questions_source_locale')),
    sa.CheckConstraint("status IN ('draft', 'in_review', 'changes_requested', 'approved', 'published', 'archived')", name=op.f('ck_questions_status')),
    sa.CheckConstraint("type <> 'creative' OR stimulus_id IS NOT NULL", name=op.f('ck_questions_creative_stimulus')),
    sa.CheckConstraint("type IN ('mcq_single', 'mcq_multi', 'true_false', 'short_answer', 'creative', 'fill_blank', 'matching')", name=op.f('ck_questions_type')),
    sa.CheckConstraint('difficulty BETWEEN 1 AND 5', name=op.f('ck_questions_difficulty')),
    sa.CheckConstraint('marks > 0', name=op.f('ck_questions_marks')),
    sa.CheckConstraint('topic_id IS NULL OR chapter_id IS NOT NULL', name=op.f('ck_questions_topic_needs_chapter')),
    sa.CheckConstraint('version >= 0 AND latest_revision >= 1', name=op.f('ck_questions_versions')),
    sa.ForeignKeyConstraint(['chapter_id', 'subject_id'], ['chapters.id', 'chapters.subject_id'], name='fk_questions_chapter_subject'),
    sa.ForeignKeyConstraint(['created_by'], ['users.id'], name=op.f('fk_questions_created_by_users'), ondelete='SET NULL'),
    sa.ForeignKeyConstraint(['education_level_id'], ['education_levels.id'], name=op.f('fk_questions_education_level_id_education_levels'), ondelete='RESTRICT'),
    sa.ForeignKeyConstraint(['published_by'], ['users.id'], name=op.f('fk_questions_published_by_users'), ondelete='SET NULL'),
    sa.ForeignKeyConstraint(['required_entitlement_key'], ['entitlement_definitions.key'], name=op.f('fk_questions_required_entitlement_key_entitlement_definitions'), ondelete='RESTRICT'),
    sa.ForeignKeyConstraint(['reviewed_by'], ['users.id'], name=op.f('fk_questions_reviewed_by_users'), ondelete='SET NULL'),
    sa.ForeignKeyConstraint(['stimulus_id'], ['question_stimuli.id'], name=op.f('fk_questions_stimulus_id_question_stimuli'), ondelete='RESTRICT'),
    sa.ForeignKeyConstraint(['subject_id'], ['subjects.id'], name=op.f('fk_questions_subject_id_subjects'), ondelete='RESTRICT'),
    sa.ForeignKeyConstraint(['topic_id', 'chapter_id'], ['topics.id', 'topics.chapter_id'], name='fk_questions_topic_chapter'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_questions'))
    )
    op.create_index('ix_questions_browse', 'questions', ['subject_id', 'chapter_id', 'type', 'difficulty', 'id'], unique=False, postgresql_where=sa.text("status = 'published' AND deleted_at IS NULL"))
    op.create_index('ix_questions_content_hash', 'questions', ['content_hash'], unique=False)
    op.create_index('ix_questions_created_by_updated_at', 'questions', ['created_by', sa.literal_column('updated_at DESC')], unique=False)
    op.create_index('ix_questions_stimulus_id', 'questions', ['stimulus_id'], unique=False, postgresql_where=sa.text('stimulus_id IS NOT NULL'))
    op.create_index('ix_questions_topic_id_id', 'questions', ['topic_id', 'id'], unique=False, postgresql_where=sa.text("status = 'published' AND deleted_at IS NULL"))
    op.create_index('ix_questions_workflow', 'questions', ['status', 'subject_id', sa.literal_column('updated_at DESC')], unique=False, postgresql_where=sa.text('deleted_at IS NULL'))
    op.create_table('question_options',
    sa.Column('question_id', sa.Uuid(), nullable=False),
    sa.Column('position', sa.SmallInteger(), nullable=False),
    sa.Column('label', sa.Text(), nullable=False),
    sa.Column('is_correct', sa.Boolean(), server_default='false', nullable=False),
    sa.Column('id', sa.Uuid(), server_default=sa.text('uuidv7()'), nullable=False),
    sa.CheckConstraint('position BETWEEN 0 AND 7', name=op.f('ck_question_options_position')),
    sa.ForeignKeyConstraint(['question_id'], ['questions.id'], name=op.f('fk_question_options_question_id_questions'), ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_question_options')),
    sa.UniqueConstraint('question_id', 'position', name=op.f('uq_question_options_question_id_position'))
    )
    op.create_table('question_paper_items',
    sa.Column('paper_id', sa.Uuid(), nullable=False),
    sa.Column('question_id', sa.Uuid(), nullable=False),
    sa.Column('item_number', sa.Text(), nullable=False),
    sa.Column('position', sa.Integer(), nullable=False),
    sa.Column('marks', sa.Numeric(precision=5, scale=2), nullable=True),
    sa.ForeignKeyConstraint(['paper_id'], ['question_papers.id'], name=op.f('fk_question_paper_items_paper_id_question_papers'), ondelete='CASCADE'),
    sa.ForeignKeyConstraint(['question_id'], ['questions.id'], name=op.f('fk_question_paper_items_question_id_questions'), ondelete='RESTRICT'),
    sa.PrimaryKeyConstraint('paper_id', 'question_id', name=op.f('pk_question_paper_items')),
    sa.UniqueConstraint('paper_id', 'item_number', name=op.f('uq_question_paper_items_paper_id_item_number')),
    sa.UniqueConstraint('paper_id', 'position', name=op.f('uq_question_paper_items_paper_id_position'))
    )
    op.create_index('ix_question_paper_items_question_id', 'question_paper_items', ['question_id'], unique=False)
    op.create_table('question_parts',
    sa.Column('question_id', sa.Uuid(), nullable=False),
    sa.Column('position', sa.SmallInteger(), nullable=False),
    sa.Column('label', sa.Text(), nullable=False),
    sa.Column('cognitive_level', sa.Text(), nullable=False),
    sa.Column('marks', sa.Numeric(precision=5, scale=2), nullable=False),
    sa.Column('id', sa.Uuid(), server_default=sa.text('uuidv7()'), nullable=False),
    sa.CheckConstraint("cognitive_level IN ('knowledge', 'comprehension', 'application', 'higher_order')", name=op.f('ck_question_parts_cognitive_level')),
    sa.CheckConstraint('marks > 0', name=op.f('ck_question_parts_marks')),
    sa.ForeignKeyConstraint(['question_id'], ['questions.id'], name=op.f('fk_question_parts_question_id_questions'), ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_question_parts')),
    sa.UniqueConstraint('question_id', 'label', name=op.f('uq_question_parts_question_id_label')),
    sa.UniqueConstraint('question_id', 'position', name=op.f('uq_question_parts_question_id_position'))
    )
    op.create_table('question_reports',
    sa.Column('question_id', sa.Uuid(), nullable=False),
    sa.Column('user_id', sa.Uuid(), nullable=True),
    sa.Column('reason', sa.Text(), nullable=False),
    sa.Column('body', sa.Text(), nullable=True),
    sa.Column('status', sa.Text(), server_default='open', nullable=False),
    sa.Column('resolved_by', sa.Uuid(), nullable=True),
    sa.Column('resolved_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('id', sa.Uuid(), server_default=sa.text('uuidv7()'), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.CheckConstraint("reason IN ('wrong_answer', 'typo', 'unclear', 'wrong_classification', 'copyright', 'other')", name=op.f('ck_question_reports_reason')),
    sa.CheckConstraint("status IN ('open', 'accepted', 'rejected')", name=op.f('ck_question_reports_status')),
    sa.CheckConstraint('body IS NULL OR char_length(body) <= 2000', name=op.f('ck_question_reports_body_length')),
    sa.ForeignKeyConstraint(['question_id'], ['questions.id'], name=op.f('fk_question_reports_question_id_questions'), ondelete='CASCADE'),
    sa.ForeignKeyConstraint(['resolved_by'], ['users.id'], name=op.f('fk_question_reports_resolved_by_users'), ondelete='SET NULL'),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], name=op.f('fk_question_reports_user_id_users'), ondelete='SET NULL'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_question_reports'))
    )
    op.create_index('ix_question_reports_open', 'question_reports', ['created_at'], unique=False, postgresql_where=sa.text("status = 'open'"))
    op.create_index('ix_question_reports_question_id', 'question_reports', ['question_id'], unique=False)
    op.create_index('uq_question_reports_open', 'question_reports', ['question_id', 'user_id'], unique=True, postgresql_where=sa.text("status = 'open'"))
    op.create_table('question_reviews',
    sa.Column('question_id', sa.Uuid(), nullable=False),
    sa.Column('revision', sa.Integer(), nullable=False),
    sa.Column('reviewer_id', sa.Uuid(), nullable=True),
    sa.Column('decision', sa.Text(), nullable=False),
    sa.Column('comment', sa.Text(), nullable=True),
    sa.Column('id', sa.Uuid(), server_default=sa.text('uuidv7()'), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.CheckConstraint("decision IN ('approve', 'request_changes', 'reject')", name=op.f('ck_question_reviews_decision')),
    sa.ForeignKeyConstraint(['question_id'], ['questions.id'], name=op.f('fk_question_reviews_question_id_questions'), ondelete='CASCADE'),
    sa.ForeignKeyConstraint(['reviewer_id'], ['users.id'], name=op.f('fk_question_reviews_reviewer_id_users'), ondelete='SET NULL'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_question_reviews'))
    )
    op.create_index('ix_question_reviews_question_id_created_at', 'question_reviews', ['question_id', sa.literal_column('created_at DESC')], unique=False)
    op.create_table('question_revisions',
    sa.Column('question_id', sa.Uuid(), nullable=False),
    sa.Column('revision', sa.Integer(), nullable=False),
    sa.Column('snapshot', postgresql.JSONB(astext_type=sa.Text()), nullable=False),
    sa.Column('status', sa.Text(), server_default='draft', nullable=False),
    sa.Column('change_note', sa.Text(), nullable=True),
    sa.Column('changed_by', sa.Uuid(), nullable=True),
    sa.Column('editor_ids', postgresql.JSONB(astext_type=sa.Text()), server_default='[]', nullable=False),
    sa.Column('id', sa.Uuid(), server_default=sa.text('uuidv7()'), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.CheckConstraint("status IN ('draft', 'in_review', 'changes_requested', 'approved', 'published', 'superseded')", name=op.f('ck_question_revisions_status')),
    sa.ForeignKeyConstraint(['changed_by'], ['users.id'], name=op.f('fk_question_revisions_changed_by_users'), ondelete='SET NULL'),
    sa.ForeignKeyConstraint(['question_id'], ['questions.id'], name=op.f('fk_question_revisions_question_id_questions'), ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_question_revisions')),
    sa.UniqueConstraint('question_id', 'revision', name=op.f('uq_question_revisions_question_id_revision'))
    )
    op.create_table('question_translations',
    sa.Column('question_id', sa.Uuid(), nullable=False),
    sa.Column('locale', sa.Text(), nullable=False),
    sa.Column('stem', postgresql.JSONB(astext_type=sa.Text()), nullable=False),
    sa.Column('stem_text', sa.Text(), nullable=False),
    sa.Column('explanation', postgresql.JSONB(astext_type=sa.Text()), nullable=True),
    sa.Column('model_answer', postgresql.JSONB(astext_type=sa.Text()), nullable=True),
    sa.Column('marking_guidance', postgresql.JSONB(astext_type=sa.Text()), nullable=True),
    sa.Column('origin', sa.Text(), server_default='original', nullable=False),
    sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.CheckConstraint("locale ~ '^[a-z]{2,3}(-[A-Z][a-z]{3})?(-[A-Z]{2})?$'", name=op.f('ck_question_translations_locale')),
    sa.ForeignKeyConstraint(['question_id'], ['questions.id'], name=op.f('fk_question_translations_question_id_questions'), ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('question_id', 'locale', name=op.f('pk_question_translations'))
    )
    op.create_table('question_option_translations',
    sa.Column('option_id', sa.Uuid(), nullable=False),
    sa.Column('locale', sa.Text(), nullable=False),
    sa.Column('content', postgresql.JSONB(astext_type=sa.Text()), nullable=False),
    sa.Column('content_text', sa.Text(), nullable=False),
    sa.CheckConstraint("locale ~ '^[a-z]{2,3}(-[A-Z][a-z]{3})?(-[A-Z]{2})?$'", name=op.f('ck_question_option_translations_locale')),
    sa.ForeignKeyConstraint(['option_id'], ['question_options.id'], name=op.f('fk_question_option_translations_option_id_question_options'), ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('option_id', 'locale', name=op.f('pk_question_option_translations'))
    )
    op.create_table('question_part_translations',
    sa.Column('part_id', sa.Uuid(), nullable=False),
    sa.Column('locale', sa.Text(), nullable=False),
    sa.Column('prompt', postgresql.JSONB(astext_type=sa.Text()), nullable=False),
    sa.Column('model_answer', postgresql.JSONB(astext_type=sa.Text()), nullable=True),
    sa.Column('marking_guidance', postgresql.JSONB(astext_type=sa.Text()), nullable=True),
    sa.CheckConstraint("locale ~ '^[a-z]{2,3}(-[A-Z][a-z]{3})?(-[A-Z]{2})?$'", name=op.f('ck_question_part_translations_locale')),
    sa.ForeignKeyConstraint(['part_id'], ['question_parts.id'], name=op.f('fk_question_part_translations_part_id_question_parts'), ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('part_id', 'locale', name=op.f('pk_question_part_translations'))
    )
    op.add_column('provenance_records', sa.Column('question_paper_id', sa.Uuid(), nullable=True))
    op.add_column('provenance_records', sa.Column('question_id', sa.Uuid(), nullable=True))
    op.add_column('provenance_records', sa.Column('stimulus_id', sa.Uuid(), nullable=True))
    op.create_index('ix_provenance_records_question_id', 'provenance_records', ['question_id'], unique=False)
    op.create_index('ix_provenance_records_question_paper_id', 'provenance_records', ['question_paper_id'], unique=False)
    op.create_index('ix_provenance_records_stimulus_id', 'provenance_records', ['stimulus_id'], unique=False)
    op.create_foreign_key(op.f('fk_provenance_records_question_paper_id_question_papers'), 'provenance_records', 'question_papers', ['question_paper_id'], ['id'], ondelete='CASCADE')
    op.create_foreign_key(op.f('fk_provenance_records_question_id_questions'), 'provenance_records', 'questions', ['question_id'], ['id'], ondelete='CASCADE')
    op.create_foreign_key(op.f('fk_provenance_records_stimulus_id_question_stimuli'), 'provenance_records', 'question_stimuli', ['stimulus_id'], ['id'], ondelete='CASCADE')
    op.drop_constraint(op.f("ck_provenance_records_one_subject"), "provenance_records", type_="check")
    op.create_check_constraint(
        op.f("ck_provenance_records_one_subject"),
        "provenance_records",
        "num_nonnulls(edition_id, question_paper_id, question_id, stimulus_id) = 1",
    )
    op.create_index(
        "ix_question_translations_stem_text_trgm",
        "question_translations",
        ["stem_text"],
        postgresql_using="gin",
        postgresql_ops={"stem_text": "gin_trgm_ops"},
    )


def downgrade() -> None:
    op.drop_constraint(op.f('fk_provenance_records_stimulus_id_question_stimuli'), 'provenance_records', type_='foreignkey')
    op.drop_constraint(op.f('fk_provenance_records_question_id_questions'), 'provenance_records', type_='foreignkey')
    op.drop_constraint(op.f('fk_provenance_records_question_paper_id_question_papers'), 'provenance_records', type_='foreignkey')
    op.drop_index('ix_provenance_records_stimulus_id', table_name='provenance_records')
    op.drop_index('ix_provenance_records_question_paper_id', table_name='provenance_records')
    op.drop_index('ix_provenance_records_question_id', table_name='provenance_records')
    op.drop_index("ix_question_translations_stem_text_trgm", table_name="question_translations")
    # Provenance of questions, papers and stimuli goes with them; only edition records can remain.
    op.execute("DELETE FROM provenance_records WHERE edition_id IS NULL")
    op.drop_constraint(op.f("ck_provenance_records_one_subject"), "provenance_records", type_="check")
    op.create_check_constraint(
        op.f("ck_provenance_records_one_subject"), "provenance_records", "num_nonnulls(edition_id) = 1"
    )
    op.drop_column('provenance_records', 'stimulus_id')
    op.drop_column('provenance_records', 'question_id')
    op.drop_column('provenance_records', 'question_paper_id')
    op.drop_table('question_part_translations')
    op.drop_table('question_option_translations')
    op.drop_table('question_translations')
    op.drop_table('question_revisions')
    op.drop_index('ix_question_reviews_question_id_created_at', table_name='question_reviews')
    op.drop_table('question_reviews')
    op.drop_index('uq_question_reports_open', table_name='question_reports', postgresql_where=sa.text("status = 'open'"))
    op.drop_index('ix_question_reports_question_id', table_name='question_reports')
    op.drop_index('ix_question_reports_open', table_name='question_reports', postgresql_where=sa.text("status = 'open'"))
    op.drop_table('question_reports')
    op.drop_table('question_parts')
    op.drop_index('ix_question_paper_items_question_id', table_name='question_paper_items')
    op.drop_table('question_paper_items')
    op.drop_table('question_options')
    op.drop_index('ix_questions_workflow', table_name='questions', postgresql_where=sa.text('deleted_at IS NULL'))
    op.drop_index('ix_questions_topic_id_id', table_name='questions', postgresql_where=sa.text("status = 'published' AND deleted_at IS NULL"))
    op.drop_index('ix_questions_stimulus_id', table_name='questions', postgresql_where=sa.text('stimulus_id IS NOT NULL'))
    op.drop_index('ix_questions_created_by_updated_at', table_name='questions')
    op.drop_index('ix_questions_content_hash', table_name='questions')
    op.drop_index('ix_questions_browse', table_name='questions', postgresql_where=sa.text("status = 'published' AND deleted_at IS NULL"))
    op.drop_table('questions')
    op.drop_index('ix_question_paper_boards_board_id_paper_id', table_name='question_paper_boards')
    op.drop_table('question_paper_boards')
    op.drop_table('stimulus_translations')
    op.drop_index('ix_question_papers_browse', table_name='question_papers', postgresql_where=sa.text("status = 'published'"))
    op.drop_table('question_papers')
    op.drop_table('question_stimuli')

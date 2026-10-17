"""The editable question snapshot and its completeness rules (docs/architecture/02 §11), as pure code.

`QuestionContent` is what `question_revisions.snapshot` stores. Shape is validated when a draft is
saved (so drafts may be incomplete); completeness is checked on submit and again on publish.
"""

from __future__ import annotations

import hashlib
import json
import re
import uuid
from decimal import Decimal
from typing import Annotated, Any

from pydantic import BaseModel, ConfigDict, Field, StringConstraints, field_validator, model_validator

from app.catalog.models import AccessLevel
from app.core.i18n import nfc
from app.questionbank.contentdoc import ContentDoc, blank_indexes, plain_text
from app.questionbank.models import CognitiveLevel, QuestionType, TranslationOrigin

LocaleCode = Annotated[str, StringConstraints(pattern=r"^[a-z]{2,3}(-[A-Z][a-z]{3})?(-[A-Z]{2})?$")]
Label = Annotated[str, StringConstraints(min_length=1, max_length=8, strip_whitespace=True)]
Marks = Annotated[Decimal, Field(gt=0, le=999, max_digits=5, decimal_places=2)]
LocalizedDocs = Annotated[dict[LocaleCode, ContentDoc], Field(min_length=1, max_length=8)]

MAX_OPTIONS = 8
MAX_PARTS = 6
MAX_BLANKS = 20
MAX_MATCH_ITEMS = 12
MAX_ACCEPTED = 20
MAX_SPEC_DEPTH = 5
MAX_SPEC_BYTES = 20_000


def _depth(value: Any, level: int = 1) -> int:
    if level > MAX_SPEC_DEPTH + 1:
        return level
    if isinstance(value, dict):
        return max([_depth(v, level + 1) for v in value.values()], default=level)
    if isinstance(value, list):
        return max([_depth(v, level + 1) for v in value], default=level)
    return level


class _Strict(BaseModel):
    model_config = ConfigDict(extra="forbid")


class TranslationContent(_Strict):
    stem: ContentDoc
    explanation: ContentDoc | None = None
    model_answer: ContentDoc | None = None
    marking_guidance: ContentDoc | None = None
    origin: TranslationOrigin = TranslationOrigin.ORIGINAL


class OptionContent(_Strict):
    label: Label
    is_correct: bool = False
    content: LocalizedDocs

    @field_validator("label")
    @classmethod
    def _nfc(cls, value: str) -> str:
        return nfc(value)


class PartContent(_Strict):
    label: Label
    cognitive_level: CognitiveLevel
    marks: Marks
    prompt: LocalizedDocs
    model_answer: dict[LocaleCode, ContentDoc] | None = None
    marking_guidance: dict[LocaleCode, ContentDoc] | None = None

    @field_validator("label")
    @classmethod
    def _nfc(cls, value: str) -> str:
        return nfc(value)


class QuestionContent(_Strict):
    type: QuestionType
    source_locale: LocaleCode
    stimulus_id: uuid.UUID | None = None
    education_level_id: uuid.UUID
    subject_id: uuid.UUID
    chapter_id: uuid.UUID | None = None
    topic_id: uuid.UUID | None = None
    difficulty: Annotated[int, Field(ge=1, le=5)] | None = None
    cognitive_level: CognitiveLevel | None = None
    marks: Marks = Decimal(1)
    answer_spec: dict[str, Any] = Field(default_factory=dict)
    access_level: AccessLevel = AccessLevel.FREE
    required_entitlement_key: str | None = None
    translations: Annotated[dict[LocaleCode, TranslationContent], Field(min_length=1, max_length=8)]
    options: Annotated[list[OptionContent], Field(max_length=MAX_OPTIONS)] = Field(default_factory=list)
    parts: Annotated[list[PartContent], Field(max_length=MAX_PARTS)] = Field(default_factory=list)

    @field_validator("answer_spec")
    @classmethod
    def _bounded_spec(cls, value: dict[str, Any]) -> dict[str, Any]:
        """Free-form JSON is bounded before it is stored: shallow, small, and strings only at the leaves."""
        if _depth(value) > MAX_SPEC_DEPTH or len(json.dumps(value, ensure_ascii=False)) > MAX_SPEC_BYTES:
            raise ValueError("answer_spec is too large or too deeply nested")
        return value

    @model_validator(mode="after")
    def _classification(self) -> QuestionContent:
        if self.topic_id is not None and self.chapter_id is None:
            raise ValueError("a topic needs its chapter")
        if self.access_level == AccessLevel.ENTITLED and not self.required_entitlement_key:
            raise ValueError("entitled questions need required_entitlement_key")
        return self


# ------------------------------------------------------------------ completeness


def _question_issues(content: QuestionContent) -> list[str]:
    issues: list[str] = []
    source = content.source_locale
    if source not in content.translations:
        issues.append("SOURCE_TRANSLATION_MISSING")
    labels = [o.label for o in content.options]
    if len(set(labels)) != len(labels):
        issues.append("OPTION_LABELS_NOT_UNIQUE")
    if any(source not in o.content for o in content.options):
        issues.append("OPTION_SOURCE_TEXT_MISSING")
    correct = sum(o.is_correct for o in content.options)
    count = len(content.options)
    match content.type:
        case QuestionType.MCQ_SINGLE:
            if not 2 <= count <= 6:
                issues.append("OPTION_COUNT_INVALID")
            if correct != 1:
                issues.append("EXACTLY_ONE_CORRECT_OPTION_REQUIRED")
        case QuestionType.MCQ_MULTI:
            if not 2 <= count <= MAX_OPTIONS:
                issues.append("OPTION_COUNT_INVALID")
            if correct < 1:
                issues.append("CORRECT_OPTION_REQUIRED")
        case QuestionType.TRUE_FALSE:
            if count != 2:
                issues.append("OPTION_COUNT_INVALID")
            if correct != 1:
                issues.append("EXACTLY_ONE_CORRECT_OPTION_REQUIRED")
        case _:
            if count:
                issues.append("OPTIONS_NOT_ALLOWED")
    return issues


def _type_issues(content: QuestionContent) -> list[str]:
    issues: list[str] = []
    source_translation = content.translations.get(content.source_locale)
    spec = content.answer_spec
    if content.type not in (QuestionType.FILL_BLANK, QuestionType.MATCHING) and spec:
        issues.append("ANSWER_SPEC_NOT_ALLOWED")
    if content.type is not QuestionType.CREATIVE and content.parts:
        issues.append("PARTS_NOT_ALLOWED")
    if content.type is QuestionType.SHORT_ANSWER and (
        source_translation is None or source_translation.model_answer is None
    ):
        issues.append("MODEL_ANSWER_REQUIRED")
    if content.type is QuestionType.CREATIVE:
        issues.extend(_creative_issues(content))
    if content.type is QuestionType.FILL_BLANK:
        issues.extend(_fill_blank_issues(content, source_translation))
    if content.type is QuestionType.MATCHING:
        issues.extend(_matching_issues(spec))
    return issues


def _creative_issues(content: QuestionContent) -> list[str]:
    issues: list[str] = []
    if content.stimulus_id is None:
        issues.append("STIMULUS_REQUIRED")
    if not content.parts:
        issues.append("PART_REQUIRED")
        return issues
    part_labels = [p.label for p in content.parts]
    if len(set(part_labels)) != len(part_labels):
        issues.append("PART_LABELS_NOT_UNIQUE")
    if any(content.source_locale not in p.prompt for p in content.parts):
        issues.append("PART_SOURCE_TEXT_MISSING")
    if sum((p.marks for p in content.parts), Decimal(0)) != content.marks:
        issues.append("PART_MARKS_MUST_SUM_TO_QUESTION_MARKS")
    return issues


def _fill_blank_issues(content: QuestionContent, source: TranslationContent | None) -> list[str]:
    blanks = content.answer_spec.get("blanks")
    if not isinstance(blanks, list) or not blanks or len(blanks) > MAX_BLANKS:
        return ["BLANKS_REQUIRED"]
    for blank in blanks:
        accepted = blank.get("accepted") if isinstance(blank, dict) else None
        if not isinstance(accepted, list) or not 1 <= len(accepted) <= MAX_ACCEPTED:
            return ["BLANK_ANSWERS_REQUIRED"]
        if not all(isinstance(a, str) and a.strip() for a in accepted):
            return ["BLANK_ANSWERS_REQUIRED"]
    if source is None:
        return []
    if blank_indexes(source.stem) != set(range(len(blanks))):
        return ["BLANK_TOKENS_MUST_MATCH_ANSWERS"]
    return []


def _matching_issues(spec: dict[str, Any]) -> list[str]:
    left, right, pairs = spec.get("left"), spec.get("right"), spec.get("pairs")
    if not (isinstance(left, list) and isinstance(right, list) and isinstance(pairs, list)):
        return ["MATCHING_SPEC_REQUIRED"]
    if not (2 <= len(left) <= MAX_MATCH_ITEMS and 2 <= len(right) <= MAX_MATCH_ITEMS):
        return ["MATCHING_SPEC_REQUIRED"]
    if not all(isinstance(x, str) and x.strip() for x in [*left, *right]):
        return ["MATCHING_SPEC_REQUIRED"]
    try:
        mapping = {int(a): int(b) for a, b in pairs}
    except (TypeError, ValueError):
        return ["MATCHING_PAIRS_INVALID"]
    if set(mapping) != set(range(len(left))) or not all(0 <= b < len(right) for b in mapping.values()):
        return ["MATCHING_PAIRS_INVALID"]
    return []


def completeness_issues(content: QuestionContent) -> list[str]:
    """Machine-readable reasons the question cannot be submitted or published; empty when complete."""
    return [*_question_issues(content), *_type_issues(content)]


# ------------------------------------------------------------------ identity of the content


def content_hash(content: QuestionContent) -> bytes:
    """Hash of the normalised source-language stem and options: duplicate detection (08 §4)."""
    source = content.translations.get(content.source_locale)
    stem = plain_text(source.stem) if source else ""
    options = sorted(
        plain_text(o.content[content.source_locale])
        for o in content.options
        if content.source_locale in o.content
    )
    normalised = re.sub(r"\s+", " ", "\n".join([content.type.value, stem, *options]).casefold()).strip()
    return hashlib.sha256(normalised.encode()).digest()

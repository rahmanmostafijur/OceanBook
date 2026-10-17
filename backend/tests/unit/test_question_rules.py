"""ContentDoc validation and question completeness rules: pure functions, no services needed."""

from __future__ import annotations

import uuid
from decimal import Decimal
from typing import Any

import pytest
from pydantic import ValidationError

from app.questionbank import contentdoc
from app.questionbank.contentdoc import Blank, ContentDoc, Math, Paragraph, Text, parse, plain_text, simple
from app.questionbank.models import QuestionType
from app.questionbank.rules import (
    OptionContent,
    PartContent,
    QuestionContent,
    TranslationContent,
    completeness_issues,
    content_hash,
)

LEVEL, SUBJECT, STIMULUS = uuid.uuid4(), uuid.uuid4(), uuid.uuid4()


def doc(text: str) -> ContentDoc:
    return simple(text)


def option(label: str, text: str, *, correct: bool = False) -> OptionContent:
    return OptionContent(label=label, is_correct=correct, content={"bn": doc(text)})


def question(type_: QuestionType, **overrides: Any) -> QuestionContent:
    values: dict[str, Any] = {
        "type": type_,
        "source_locale": "bn",
        "education_level_id": LEVEL,
        "subject_id": SUBJECT,
        "translations": {"bn": TranslationContent(stem=doc("প্রশ্ন"))},
    }
    values.update(overrides)
    return QuestionContent(**values)


def mcq(
    count: int = 4, correct: tuple[int, ...] = (0,), type_: QuestionType = QuestionType.MCQ_SINGLE
) -> QuestionContent:
    options = [option("কখগঘঙচছজ"[i], f"উত্তর {i}", correct=i in correct) for i in range(count)]
    return question(type_, options=options)


# ------------------------------------------------------------------ ContentDoc


def test_plain_text_flattens_math_images_lists_tables_and_blanks() -> None:
    value = parse(
        {
            "type": "doc",
            "v": 1,
            "blocks": [
                {
                    "type": "paragraph",
                    "inlines": [
                        {"type": "text", "text": "যদি "},
                        {"type": "math", "tex": "x^2 - 5x + 6 = 0"},
                        {"type": "text", "text": " তবে "},
                        {"type": "blank", "index": 0},
                    ],
                },
                {"type": "image", "asset_id": "0192b6a0-0000-7000-8000-000000000000", "alt": "ত্রিভুজ ABC"},
                {"type": "list", "style": "roman", "items": [[{"type": "text", "text": "প্রথম"}]]},
                {
                    "type": "table",
                    "rows": [[[{"type": "text", "text": "ক"}], [{"type": "text", "text": "খ"}]]],
                },
            ],
        }
    )
    assert plain_text(value) == "যদি x^2 - 5x + 6 = 0 তবে ____\nত্রিভুজ ABC\nপ্রথম\nক খ".replace("\n", " ")
    assert contentdoc.blank_indexes(value) == {0}
    assert contentdoc.image_asset_ids(value) == {"0192b6a0-0000-7000-8000-000000000000"}


def test_text_is_nfc_normalised() -> None:
    decomposed = "e\u0301"
    assert Text(text=decomposed).text == "\u00e9"


@pytest.mark.parametrize(
    "raw",
    [
        {"type": "doc", "v": 1, "blocks": []},
        {"type": "doc", "v": 2, "blocks": [{"type": "paragraph", "inlines": []}]},
        {"type": "doc", "v": 1, "blocks": [{"type": "html", "html": "<script>alert(1)</script>"}]},
        {
            "type": "doc",
            "v": 1,
            "blocks": [{"type": "paragraph", "inlines": [{"type": "link", "href": "x"}]}],
        },
        {"type": "doc", "v": 1, "blocks": [{"type": "paragraph", "inlines": [], "onclick": "x"}]},
        {"type": "doc", "v": 1, "blocks": [{"type": "image", "asset_id": "not-an-id", "alt": "x"}]},
        {"type": "doc", "v": 1, "blocks": [{"type": "image", "asset_id": "0" * 32, "alt": ""}]},
        {
            "type": "doc",
            "v": 1,
            "blocks": [{"type": "table", "rows": [[[{"type": "text", "text": "a"}]], []]}],
        },
        {
            "type": "doc",
            "v": 1,
            "blocks": [
                {
                    "type": "table",
                    "rows": [
                        [[{"type": "text", "text": "a"}], [{"type": "text", "text": "b"}]],
                        [[{"type": "text", "text": "c"}]],
                    ],
                }
            ],
        },
    ],
)
def test_documents_outside_the_closed_model_are_rejected(raw: dict[str, Any]) -> None:
    with pytest.raises(ValidationError):
        parse(raw)


@pytest.mark.parametrize(
    "tex", ["\\frac{a}{b}", "\\sqrt{x^2+y^2}", "\\alpha + \\beta", "\\mathrm{H_2O}", "\\{a\\}"]
)
def test_allowed_math_passes(tex: str) -> None:
    assert Math(tex=tex).tex == tex


@pytest.mark.parametrize(
    "tex",
    [
        "\\input{/etc/passwd}",
        "\\write18{rm}",
        "\\def\\x{y}",
        "\\href{http://x}{y}",
        "\\url{x}",
        "\\frac{a}{b",
        "}",
        "  ",
        "\\\u0000",
    ],
)
def test_dangerous_or_malformed_math_is_rejected(tex: str) -> None:
    with pytest.raises(ValidationError):
        Math(tex=tex)


def test_math_length_is_capped() -> None:
    with pytest.raises(ValidationError):
        Math(tex="x" * 1001)


def test_dump_round_trips() -> None:
    value = ContentDoc(blocks=[Paragraph(inlines=[Text(text="a", bold=True), Blank(index=1)])])
    assert parse(contentdoc.dump(value)) == value


# ------------------------------------------------------------------ completeness


def test_a_complete_single_choice_question_has_no_issues() -> None:
    assert completeness_issues(mcq()) == []


@pytest.mark.parametrize(
    ("content", "expected"),
    [
        (mcq(count=1), "OPTION_COUNT_INVALID"),
        (mcq(count=7), "OPTION_COUNT_INVALID"),
        (mcq(correct=()), "EXACTLY_ONE_CORRECT_OPTION_REQUIRED"),
        (mcq(correct=(0, 1)), "EXACTLY_ONE_CORRECT_OPTION_REQUIRED"),
        (mcq(count=4, correct=(), type_=QuestionType.MCQ_MULTI), "CORRECT_OPTION_REQUIRED"),
        (mcq(count=3, correct=(0,), type_=QuestionType.TRUE_FALSE), "OPTION_COUNT_INVALID"),
        (question(QuestionType.SHORT_ANSWER, options=[option("A", "x")]), "OPTIONS_NOT_ALLOWED"),
    ],
)
def test_choice_rules(content: QuestionContent, expected: str) -> None:
    assert expected in completeness_issues(content)


def test_multiple_choice_allows_several_correct_options() -> None:
    assert completeness_issues(mcq(count=5, correct=(0, 2, 3), type_=QuestionType.MCQ_MULTI)) == []


def test_true_false_needs_exactly_two_options() -> None:
    content = question(
        QuestionType.TRUE_FALSE, options=[option("A", "সত্য", correct=True), option("B", "মিথ্যা")]
    )
    assert completeness_issues(content) == []


def test_duplicate_option_labels_and_missing_source_text_are_reported() -> None:
    content = question(
        QuestionType.MCQ_SINGLE,
        options=[
            option("A", "x", correct=True),
            OptionContent(label="A", content={"en": doc("only english")}),
        ],
    )
    issues = completeness_issues(content)
    assert "OPTION_LABELS_NOT_UNIQUE" in issues and "OPTION_SOURCE_TEXT_MISSING" in issues


def test_source_translation_is_required() -> None:
    content = question(QuestionType.SHORT_ANSWER, translations={"en": TranslationContent(stem=doc("q"))})
    assert "SOURCE_TRANSLATION_MISSING" in completeness_issues(content)


def test_short_answer_needs_a_model_answer() -> None:
    assert "MODEL_ANSWER_REQUIRED" in completeness_issues(question(QuestionType.SHORT_ANSWER))
    complete = question(
        QuestionType.SHORT_ANSWER,
        translations={"bn": TranslationContent(stem=doc("প্রশ্ন"), model_answer=doc("উত্তর"))},
    )
    assert completeness_issues(complete) == []


def part(label: str, marks: str, level: str = "knowledge") -> PartContent:
    return PartContent(
        label=label, cognitive_level=level, marks=Decimal(marks), prompt={"bn": doc(f"অংশ {label}")}
    )


def test_creative_question_rules() -> None:
    parts = [
        part("ক", "1"),
        part("খ", "2", "comprehension"),
        part("গ", "3", "application"),
        part("ঘ", "4", "higher_order"),
    ]
    complete = question(QuestionType.CREATIVE, stimulus_id=STIMULUS, marks=Decimal(10), parts=parts)
    assert completeness_issues(complete) == []

    no_stimulus = question(QuestionType.CREATIVE, marks=Decimal(10), parts=parts)
    assert "STIMULUS_REQUIRED" in completeness_issues(no_stimulus)
    assert "PART_REQUIRED" in completeness_issues(question(QuestionType.CREATIVE, stimulus_id=STIMULUS))
    wrong_sum = question(QuestionType.CREATIVE, stimulus_id=STIMULUS, marks=Decimal(9), parts=parts)
    assert "PART_MARKS_MUST_SUM_TO_QUESTION_MARKS" in completeness_issues(wrong_sum)
    duplicate = question(
        QuestionType.CREATIVE, stimulus_id=STIMULUS, marks=Decimal(2), parts=[part("ক", "1"), part("ক", "1")]
    )
    assert "PART_LABELS_NOT_UNIQUE" in completeness_issues(duplicate)


def test_parts_are_only_for_creative_questions() -> None:
    assert "PARTS_NOT_ALLOWED" in completeness_issues(
        question(QuestionType.SHORT_ANSWER, parts=[part("ক", "1")])
    )


def fill_blank(spec: dict[str, Any], stem: ContentDoc | None = None) -> QuestionContent:
    stem = stem or ContentDoc(
        blocks=[Paragraph(inlines=[Text(text="ঢাকা "), Blank(index=0), Text(text=" এর রাজধানী")])]
    )
    return question(
        QuestionType.FILL_BLANK, answer_spec=spec, translations={"bn": TranslationContent(stem=stem)}
    )


def test_fill_blank_rules() -> None:
    assert completeness_issues(fill_blank({"blanks": [{"accepted": ["বাংলাদেশ", "Bangladesh"]}]})) == []
    assert completeness_issues(fill_blank({})) == ["BLANKS_REQUIRED"]
    assert completeness_issues(fill_blank({"blanks": [{"accepted": []}]})) == ["BLANK_ANSWERS_REQUIRED"]
    assert completeness_issues(fill_blank({"blanks": [{"accepted": [" "]}]})) == ["BLANK_ANSWERS_REQUIRED"]
    two = {"blanks": [{"accepted": ["a"]}, {"accepted": ["b"]}]}
    assert completeness_issues(fill_blank(two)) == ["BLANK_TOKENS_MUST_MATCH_ANSWERS"]
    assert completeness_issues(fill_blank({"blanks": [{"accepted": ["a"]}]}, stem=doc("no blank"))) == [
        "BLANK_TOKENS_MUST_MATCH_ANSWERS"
    ]


def test_matching_rules() -> None:
    good = {"left": ["a", "b"], "right": ["1", "2", "3"], "pairs": [[0, 2], [1, 0]]}
    assert completeness_issues(question(QuestionType.MATCHING, answer_spec=good)) == []
    assert completeness_issues(question(QuestionType.MATCHING)) == ["MATCHING_SPEC_REQUIRED"]
    partial = {**good, "pairs": [[0, 2]]}
    assert completeness_issues(question(QuestionType.MATCHING, answer_spec=partial)) == [
        "MATCHING_PAIRS_INVALID"
    ]
    out_of_range = {**good, "pairs": [[0, 9], [1, 0]]}
    assert completeness_issues(question(QuestionType.MATCHING, answer_spec=out_of_range)) == [
        "MATCHING_PAIRS_INVALID"
    ]
    garbage = {**good, "pairs": [["x", "y"], [1, 0]]}
    assert completeness_issues(question(QuestionType.MATCHING, answer_spec=garbage)) == [
        "MATCHING_PAIRS_INVALID"
    ]


def test_answer_spec_is_refused_for_other_types() -> None:
    assert "ANSWER_SPEC_NOT_ALLOWED" in completeness_issues(
        question(QuestionType.SHORT_ANSWER, answer_spec={"x": 1})
    )


# ------------------------------------------------------------------ shape and hash


def test_shape_rules_apply_when_saving() -> None:
    with pytest.raises(ValidationError):
        question(QuestionType.MCQ_SINGLE, topic_id=uuid.uuid4())  # topic without chapter
    with pytest.raises(ValidationError):
        question(QuestionType.MCQ_SINGLE, access_level="entitled")  # no entitlement key
    with pytest.raises(ValidationError):
        question(QuestionType.MCQ_SINGLE, difficulty=6)
    with pytest.raises(ValidationError):
        question(QuestionType.MCQ_SINGLE, marks=Decimal(0))
    with pytest.raises(ValidationError):
        question(QuestionType.MCQ_SINGLE, bogus=1)


def test_content_hash_ignores_case_spacing_and_option_order() -> None:
    a = question(
        QuestionType.MCQ_SINGLE,
        translations={"bn": TranslationContent(stem=doc("What  is X?"))},
        options=[option("A", "one", correct=True), option("B", "two")],
    )
    b = question(
        QuestionType.MCQ_SINGLE,
        translations={"bn": TranslationContent(stem=doc("what is x?"))},
        options=[option("A", "TWO"), option("B", "One ", correct=True)],
    )
    c = question(
        QuestionType.MCQ_SINGLE,
        translations={"bn": TranslationContent(stem=doc("What is Y?"))},
        options=[option("A", "one", correct=True), option("B", "two")],
    )
    assert content_hash(a) == content_hash(b)
    assert content_hash(a) != content_hash(c)


# ------------------------------------------------------------------ hardening found in review


def test_image_asset_ids_are_canonical_uuids() -> None:
    upper = "0192B6A0-0000-7000-8000-000000000000"
    block = {"type": "image", "asset_id": upper, "alt": "ছবি"}
    value = parse({"type": "doc", "v": 1, "blocks": [block]})
    assert contentdoc.image_asset_ids(value) == {upper.lower()}
    compact = parse({"type": "doc", "v": 1, "blocks": [{**block, "asset_id": upper.replace("-", "")}]})
    assert contentdoc.image_asset_ids(compact) == {upper.lower()}
    for bad in ("-" * 32, "not-a-uuid", ""):
        with pytest.raises(ValidationError):
            parse({"type": "doc", "v": 1, "blocks": [{**block, "asset_id": bad}]})


@pytest.mark.parametrize(
    "tex",
    [
        "\\begin{evil}x\\end{evil}",
        "x % hidden }",
        "\\^^5cinput",
        "a‮b",
        "a\x00b",
    ],
)
def test_math_rejects_unknown_environments_comments_and_control_characters(tex: str) -> None:
    with pytest.raises(ValidationError):
        Math(tex=tex)


def test_math_allows_known_environments() -> None:
    tex = "\\begin{pmatrix} a & b \\\\ c & d \\end{pmatrix}"
    assert Math(tex=tex).tex == tex


@pytest.mark.parametrize("text", ["a‮b", "a\x00b", "a​b"])
def test_text_rejects_control_and_bidi_format_characters(text: str) -> None:
    with pytest.raises(ValidationError):
        Text(text=text)


def test_text_keeps_newlines_and_bangla_joiners() -> None:
    assert Text(text="ক্ষ‍ত\nline").text.endswith("line")


def test_answer_spec_is_bounded() -> None:
    nested: dict[str, Any] = {}
    cursor = nested
    for _ in range(12):
        cursor["x"] = {}
        cursor = cursor["x"]
    with pytest.raises(ValidationError):
        question(QuestionType.FILL_BLANK, answer_spec=nested)
    with pytest.raises(ValidationError):
        question(QuestionType.FILL_BLANK, answer_spec={"blanks": [{"accepted": ["x" * 30_000]}]})

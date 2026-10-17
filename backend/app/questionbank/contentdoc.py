"""ContentDoc: the closed, versioned document model for question text (docs/architecture/08 §3).

No HTML and no free-form markup: the renderer knows exactly these nodes, so there is no injection
surface. Plain text is derived for search and duplicate detection (math as TeX, images as alt text).
"""

from __future__ import annotations

import re
import unicodedata
import uuid
from typing import Annotated, Any, Literal

from pydantic import BaseModel, ConfigDict, Field, TypeAdapter, field_validator

MAX_BLOCKS = 60
MAX_INLINES = 400
MAX_TEXT = 5_000
MAX_TEX = 1_000
MAX_LIST_ITEMS = 40
MAX_TABLE_ROWS = 30
MAX_TABLE_COLS = 8

# Math is rendered by a LaTeX widget on every client: only a closed set of commands is accepted, so a
# document can never reach file, macro-definition or URL commands.
_TEX_COMMAND = re.compile(r"\\([A-Za-z]+|.)")
_ENVIRONMENT = re.compile(r"\\(?:begin|end)\s*\{([^}]*)\}")
_ALLOWED_ENVIRONMENTS = frozenset({"array", "matrix", "pmatrix", "bmatrix", "cases"})
_ALLOWED_TEX = frozenset(
    {
        # structure
        "frac", "dfrac", "tfrac", "sqrt", "left", "right", "big", "Big", "bigg", "Bigg", "over", "binom",
        "overline", "underline", "overrightarrow", "hat", "bar", "vec", "dot", "ddot", "tilde", "widehat",
        "text", "mathrm", "mathbf", "mathit", "mathbb", "mathcal", "boldsymbol", "operatorname",
        "begin", "end", "cdot", "cdots", "ldots", "dots", "quad", "qquad", "space", "limits", "nolimits",
        # operators and relations
        "sum", "prod", "int", "iint", "oint", "lim", "sup", "inf", "max", "min", "log", "ln", "exp", "sin",
        "cos", "tan", "cot", "sec", "csc", "arcsin", "arccos", "arctan", "sinh", "cosh", "tanh", "det",
        "times", "div", "pm", "mp", "ast", "circ", "bullet", "oplus", "otimes", "cup", "cap", "setminus",
        "leq", "geq", "le", "ge", "neq", "ne", "approx", "equiv", "sim", "simeq", "cong", "propto",
        "ll", "gg",
        "subset", "supset", "subseteq", "supseteq", "in", "notin", "ni", "forall", "exists", "nexists",
        "land", "lor", "neg", "implies", "iff", "to", "rightarrow", "leftarrow", "leftrightarrow",
        "Rightarrow", "Leftarrow", "Leftrightarrow", "mapsto", "uparrow", "downarrow", "infty", "partial",
        "nabla", "angle", "triangle", "perp", "parallel", "degree", "prime", "emptyset", "varnothing",
        "therefore", "because", "mid", "lbrace", "rbrace", "langle", "rangle", "lceil", "rceil", "lfloor",
        "rfloor", "vert", "Vert", "hbar", "ell", "Re", "Im", "aleph", "star", "checkmark", "colon",
        # greek
        "alpha", "beta", "gamma", "delta", "epsilon", "varepsilon", "zeta", "eta", "theta", "vartheta",
        "iota", "kappa", "lambda", "mu", "nu", "xi", "pi", "varpi", "rho", "varrho", "sigma", "varsigma",
        "tau", "upsilon", "phi", "varphi", "chi", "psi", "omega", "Gamma", "Delta", "Theta", "Lambda", "Xi",
        "Pi", "Sigma", "Upsilon", "Phi", "Psi", "Omega",
        # chemistry and units written with mathrm/text; arrays and alignment
        "rightleftharpoons", "xrightarrow", "overset", "underset", "stackrel", "array", "matrix", "pmatrix",
        "bmatrix", "cases", "hline", "hspace", "mathop", "displaystyle", "textstyle", "scriptstyle",
    }
)  # fmt: skip
_TEX_SYMBOL_ESCAPES = frozenset("{}[]()|,;:!> _%&#\\.'^$")


def nfc(value: str) -> str:
    return unicodedata.normalize("NFC", value)


def validate_tex(tex: str) -> str:
    """NFC-normalised TeX if every command is allowed and braces balance; ValueError otherwise."""
    tex = nfc(tex).strip()
    if not tex:
        raise ValueError("math must not be empty")
    if "%" in tex or "^^" in tex:
        raise ValueError("TeX comments and character codes are not allowed")
    if any(unicodedata.category(c) in ("Cc", "Cf") for c in tex):
        raise ValueError("math must not contain control characters")
    for environment in _ENVIRONMENT.findall(tex):
        if environment not in _ALLOWED_ENVIRONMENTS:
            raise ValueError(f"TeX environment {environment} is not allowed")
    if len(tex) > MAX_TEX:
        raise ValueError(f"math is longer than {MAX_TEX} characters")
    for match in _TEX_COMMAND.finditer(tex):
        command = match.group(1)
        if len(command) == 1 and not command.isalpha():
            if command not in _TEX_SYMBOL_ESCAPES:
                raise ValueError(f"TeX escape \\{command} is not allowed")
        elif command not in _ALLOWED_TEX:
            raise ValueError(f"TeX command \\{command} is not allowed")
    depth = 0
    index = 0
    while index < len(tex):
        char = tex[index]
        if char == "\\":
            index += 2
            continue
        depth += char == "{"
        depth -= char == "}"
        if depth < 0:
            break
        index += 1
    if depth != 0:
        raise ValueError("math has unbalanced braces")
    return tex


class _Node(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)


class Text(_Node):
    type: Literal["text"] = "text"
    text: Annotated[str, Field(max_length=MAX_TEXT)]
    bold: bool = False
    italic: bool = False
    sub: bool = False
    sup: bool = False
    underline: bool = False

    @field_validator("text")
    @classmethod
    def _nfc(cls, value: str) -> str:
        """NFC text without control or invisible bidi-format characters (newlines and tabs are fine)."""
        for char in value:
            if (
                char not in "\n\t"
                and unicodedata.category(char) in ("Cc", "Cf")
                and char not in "\u200c\u200d"
            ):
                raise ValueError("text must not contain control or bidi-format characters")
        return nfc(value)


class Math(_Node):
    type: Literal["math"] = "math"
    tex: str
    display: bool = False

    @field_validator("tex")
    @classmethod
    def _tex(cls, value: str) -> str:
        return validate_tex(value)


class Blank(_Node):
    """A gap to fill in (fill_blank questions). `index` links to `answer_spec.blanks[index]`."""

    type: Literal["blank"] = "blank"
    index: Annotated[int, Field(ge=0, le=20)]


Inline = Annotated[Text | Math | Blank, Field(discriminator="type")]
Inlines = Annotated[list[Inline], Field(max_length=MAX_INLINES)]


class Paragraph(_Node):
    type: Literal["paragraph"] = "paragraph"
    inlines: Inlines


class Image(_Node):
    type: Literal["image"] = "image"
    asset_id: str
    alt: Annotated[str, Field(min_length=1, max_length=300)]
    width: Annotated[int, Field(ge=1, le=4000)] | None = None
    height: Annotated[int, Field(ge=1, le=4000)] | None = None

    @field_validator("asset_id")
    @classmethod
    def _canonical_uuid(cls, value: str) -> str:
        """One spelling per asset: a parsed, lower-case, hyphenated UUID."""
        try:
            return str(uuid.UUID(value))
        except ValueError as exc:
            raise ValueError("asset_id must be a UUID") from exc

    @field_validator("alt")
    @classmethod
    def _nfc(cls, value: str) -> str:
        return nfc(value).strip()


class ListBlock(_Node):
    type: Literal["list"] = "list"
    style: Literal["bullet", "decimal", "roman", "bangla"] = "bullet"
    items: Annotated[list[Inlines], Field(min_length=1, max_length=MAX_LIST_ITEMS)]


class Table(_Node):
    type: Literal["table"] = "table"
    rows: Annotated[
        list[Annotated[list[Inlines], Field(min_length=1, max_length=MAX_TABLE_COLS)]],
        Field(max_length=MAX_TABLE_ROWS),
    ]

    @field_validator("rows")
    @classmethod
    def _rectangular(cls, rows: list[list[Any]]) -> list[list[Any]]:
        if rows and len({len(row) for row in rows}) != 1:
            raise ValueError("every table row needs the same number of cells")
        return rows


Block = Annotated[Paragraph | Image | ListBlock | Table, Field(discriminator="type")]


class ContentDoc(_Node):
    type: Literal["doc"] = "doc"
    v: Literal[1] = 1
    blocks: Annotated[list[Block], Field(min_length=1, max_length=MAX_BLOCKS)]


_ADAPTER: TypeAdapter[ContentDoc] = TypeAdapter(ContentDoc)


def parse(value: Any) -> ContentDoc:
    """Validate a raw JSON document (ValidationError on anything outside the closed model)."""
    return _ADAPTER.validate_python(value)


def dump(doc: ContentDoc) -> dict[str, Any]:
    dumped: dict[str, Any] = _ADAPTER.dump_python(doc, mode="json")
    return dumped


def _inline_text(inline: Text | Math | Blank) -> str:
    if isinstance(inline, Text):
        return inline.text
    if isinstance(inline, Math):
        return inline.tex
    return "____"


def plain_text(doc: ContentDoc) -> str:
    """Derived text for search and duplicate detection: math as TeX, images as alt text, blanks as ____."""
    parts: list[str] = []
    for block in doc.blocks:
        if isinstance(block, Paragraph):
            parts.append("".join(_inline_text(i) for i in block.inlines))
        elif isinstance(block, Image):
            parts.append(block.alt)
        elif isinstance(block, ListBlock):
            parts.extend("".join(_inline_text(i) for i in item) for item in block.items)
        else:
            parts.extend(
                " ".join("".join(_inline_text(i) for i in cell) for cell in row) for row in block.rows
            )
    return re.sub(r"\s+", " ", "\n".join(parts)).strip()


def blank_indexes(doc: ContentDoc) -> set[int]:
    """Blank tokens used by a document (fill_blank questions)."""
    found: set[int] = set()

    def scan(inlines: list[Text | Math | Blank]) -> None:
        found.update(i.index for i in inlines if isinstance(i, Blank))

    for block in doc.blocks:
        if isinstance(block, Paragraph):
            scan(block.inlines)
        elif isinstance(block, ListBlock):
            for item in block.items:
                scan(item)
        elif isinstance(block, Table):
            for row in block.rows:
                for cell in row:
                    scan(cell)
    return found


def image_asset_ids(doc: ContentDoc) -> set[str]:
    return {b.asset_id for b in doc.blocks if isinstance(b, Image)}


def simple(text: str) -> ContentDoc:
    """One-paragraph document (importer cells and tests)."""
    return ContentDoc(blocks=[Paragraph(inlines=[Text(text=text)])])

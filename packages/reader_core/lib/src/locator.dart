import 'package:meta/meta.dart';

/// Content formats a reader engine can render. `structured` is OceanBook's own
/// Book -> Edition -> Chapter -> Section model; EPUB and PDF come from publisher files.
enum ContentFormat {
  structured,
  epub,
  pdf;

  static ContentFormat? fromWire(String? value) => ContentFormat.values.where((f) => f.name == value).firstOrNull;
}

/// A position in an edition, independent of any rendering engine.
///
/// Bookmarks, highlights, notes, progress and sync store locators only, so they survive engine
/// changes (e.g. moving a book from PDF to structured content keeps its edition-level progress).
@immutable
sealed class Locator {
  const Locator({required this.editionId, required this.progression})
    : assert(progression >= 0 && progression <= 1, 'progression is a fraction of the edition');

  /// Decodes the wire form `{"format": ..., "edition_id": ..., "progression": ..., ...}`.
  /// Unknown formats return null so newer clients' data never crashes older ones.
  static Locator? fromJson(Map<String, Object?> json) {
    final editionId = json['edition_id'] as String?;
    final progression = (json['progression'] as num?)?.toDouble();
    if (editionId == null || progression == null || progression < 0 || progression > 1) return null;
    return switch (ContentFormat.fromWire(json['format'] as String?)) {
      ContentFormat.structured => StructuredLocator(
        editionId: editionId,
        progression: progression,
        chapterId: json['chapter_id']! as String,
        sectionId: json['section_id'] as String?,
        offset: (json['offset'] as int?) ?? 0,
      ),
      ContentFormat.epub => EpubLocator(
        editionId: editionId,
        progression: progression,
        href: json['href']! as String,
        cfi: json['cfi'] as String?,
      ),
      ContentFormat.pdf => PdfLocator(editionId: editionId, progression: progression, page: json['page']! as int),
      null => null,
    };
  }

  final String editionId;

  /// 0..1 through the whole edition: the engine-neutral progress value.
  final double progression;

  ContentFormat get format;

  Map<String, Object?> toJson() => {'format': format.name, 'edition_id': editionId, 'progression': progression};
}

/// Position in structured content: a section of a chapter and a character offset within it.
final class StructuredLocator extends Locator {
  const StructuredLocator({
    required super.editionId,
    required super.progression,
    required this.chapterId,
    this.sectionId,
    this.offset = 0,
  }) : assert(offset >= 0, 'offset counts characters from the start of the section');

  final String chapterId;
  final String? sectionId;
  final int offset;

  @override
  ContentFormat get format => ContentFormat.structured;

  @override
  Map<String, Object?> toJson() => {
    ...super.toJson(),
    'chapter_id': chapterId,
    'section_id': sectionId,
    'offset': offset,
  };

  @override
  bool operator ==(Object other) =>
      other is StructuredLocator &&
      other.editionId == editionId &&
      other.progression == progression &&
      other.chapterId == chapterId &&
      other.sectionId == sectionId &&
      other.offset == offset;

  @override
  int get hashCode => Object.hash(editionId, progression, chapterId, sectionId, offset);
}

final class EpubLocator extends Locator {
  const EpubLocator({required super.editionId, required super.progression, required this.href, this.cfi});

  final String href;

  /// EPUB Canonical Fragment Identifier, when the engine can produce one.
  final String? cfi;

  @override
  ContentFormat get format => ContentFormat.epub;

  @override
  Map<String, Object?> toJson() => {...super.toJson(), 'href': href, 'cfi': cfi};

  @override
  bool operator ==(Object other) =>
      other is EpubLocator &&
      other.editionId == editionId &&
      other.progression == progression &&
      other.href == href &&
      other.cfi == cfi;

  @override
  int get hashCode => Object.hash(editionId, progression, href, cfi);
}

final class PdfLocator extends Locator {
  const PdfLocator({required super.editionId, required super.progression, required this.page})
    : assert(page >= 1, 'pages are 1-based');

  final int page;

  @override
  ContentFormat get format => ContentFormat.pdf;

  @override
  Map<String, Object?> toJson() => {...super.toJson(), 'page': page};

  @override
  bool operator ==(Object other) =>
      other is PdfLocator && other.editionId == editionId && other.progression == progression && other.page == page;

  @override
  int get hashCode => Object.hash(editionId, progression, page);
}

/// A selected range (for highlights and notes): both ends in the same format and edition.
@immutable
class LocatorRange {
  LocatorRange({required this.start, required this.end, required this.text})
    : assert(start.format == end.format && start.editionId == end.editionId, 'a range stays in one edition');

  final Locator start;
  final Locator end;

  /// The selected text, kept so annotations remain readable if the content is re-rendered.
  final String text;
}

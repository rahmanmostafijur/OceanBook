import 'package:meta/meta.dart';

import 'locator.dart';

/// Content protection a source uses. `lcp` is the DRM seam (Readium LCP); engines declare support.
enum ProtectionScheme { none, lcp }

enum ReaderTheme { light, sepia, dark }

/// Reading preferences, owned by the domain layer and applied by whichever engine is active.
@immutable
class ReaderSettings {
  const ReaderSettings({
    this.fontScale = 1.0,
    this.lineHeight = 1.6,
    this.theme = ReaderTheme.light,
    this.justify = false,
  }) : assert(fontScale >= 0.5 && fontScale <= 3.0, 'fontScale out of range'),
       assert(lineHeight >= 1.0 && lineHeight <= 2.5, 'lineHeight out of range');

  final double fontScale;

  /// Bangla needs generous leading for conjuncts and vowel signs; 1.6 is the default.
  final double lineHeight;
  final ReaderTheme theme;
  final bool justify;

  ReaderSettings copyWith({double? fontScale, double? lineHeight, ReaderTheme? theme, bool? justify}) => ReaderSettings(
    fontScale: fontScale ?? this.fontScale,
    lineHeight: lineHeight ?? this.lineHeight,
    theme: theme ?? this.theme,
    justify: justify ?? this.justify,
  );

  @override
  bool operator ==(Object other) =>
      other is ReaderSettings &&
      other.fontScale == fontScale &&
      other.lineHeight == lineHeight &&
      other.theme == theme &&
      other.justify == justify;

  @override
  int get hashCode => Object.hash(fontScale, lineHeight, theme, justify);
}

/// What to open: issued by the server's access endpoint (Phase 4), never constructed from client
/// guesses. The URL is short-lived; `expiresAt` tells the engine when to ask for a new one.
@immutable
class ReaderSource {
  const ReaderSource({
    required this.editionId,
    required this.format,
    required this.uri,
    required this.expiresAt,
    this.protection = ProtectionScheme.none,
    this.isPreview = false,
  });

  final String editionId;
  final ContentFormat format;
  final Uri uri;
  final DateTime expiresAt;
  final ProtectionScheme protection;
  final bool isPreview;
}

class UnsupportedSourceException implements Exception {
  UnsupportedSourceException(this.source);

  final ReaderSource source;

  @override
  String toString() => 'No reader engine supports ${source.format.name} with ${source.protection.name} protection';
}

/// One rendering engine (structured, EPUB, PDF, later LCP-protected EPUB). Engines live in the app
/// (`features/reader/engines/*`) and depend on exactly one rendering package each; everything else —
/// library, annotations, progress, sync — depends only on this interface and on [Locator].
abstract interface class ReaderEngine {
  ContentFormat get format;

  /// Emits the current position as the reader moves; the domain layer persists progress from it.
  Stream<Locator> get positions;

  Future<void> open(ReaderSource source, {Locator? initial, ReaderSettings settings});

  Future<void> goTo(Locator locator);

  Future<void> applySettings(ReaderSettings settings);

  Future<void> close();
}

/// Creates engines for the sources it supports.
abstract interface class ReaderEngineFactory {
  bool supports(ReaderSource source);

  ReaderEngine create();
}

/// Picks the engine for a source. Registration order is preference order.
class ReaderEngineRegistry {
  ReaderEngineRegistry([Iterable<ReaderEngineFactory> factories = const []]) : _factories = [...factories];

  final List<ReaderEngineFactory> _factories;

  void register(ReaderEngineFactory factory) => _factories.add(factory);

  ReaderEngine engineFor(ReaderSource source) {
    for (final factory in _factories) {
      if (factory.supports(source)) return factory.create();
    }
    throw UnsupportedSourceException(source);
  }
}

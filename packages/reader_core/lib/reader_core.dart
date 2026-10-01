/// Reader boundary (12 §10): positions, settings and the engine interface. No rendering dependencies,
/// so library, annotation, progress and sync code can depend on it without pulling in an engine.
library;

export 'src/locator.dart';
export 'src/reader_engine.dart';

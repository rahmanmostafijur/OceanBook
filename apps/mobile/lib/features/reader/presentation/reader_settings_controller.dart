import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reader_core/reader_core.dart';

const double minFontScale = 0.8;
const double maxFontScale = 2.0;
const double fontScaleStep = 0.1;

/// Reading preferences for the open book. Held in memory only: persisting them with the user's
/// other settings belongs to the Phase 4 reader.
class ReaderSettingsNotifier extends Notifier<ReaderSettings> {
  @override
  ReaderSettings build() => const ReaderSettings();

  void increaseFont() => _setFont(state.fontScale + fontScaleStep);

  void decreaseFont() => _setFont(state.fontScale - fontScaleStep);

  void setTheme(ReaderTheme theme) => state = state.copyWith(theme: theme);

  void setJustify({required bool justify}) => state = state.copyWith(justify: justify);

  void _setFont(double value) {
    // Round to one decimal so repeated steps never drift (0.1 + 0.2 != 0.3 in floating point).
    final next = (value.clamp(minFontScale, maxFontScale) * 10).round() / 10;
    state = state.copyWith(fontScale: next);
  }
}

final readerSettingsProvider = NotifierProvider<ReaderSettingsNotifier, ReaderSettings>(ReaderSettingsNotifier.new);

ReaderPalette paletteFor(ReaderTheme theme) => switch (theme) {
  ReaderTheme.light => ReaderPalette.day,
  ReaderTheme.sepia => ReaderPalette.sepia,
  ReaderTheme.dark => ReaderPalette.night,
};

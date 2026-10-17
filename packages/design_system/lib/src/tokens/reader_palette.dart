import 'package:flutter/material.dart';

/// Reading surfaces. A book page has its own palette, independent of the app theme: readers pick
/// day, sepia or night by comfort, not by the system setting. Contrast against [text] is at least
/// 7:1 on every surface (WCAG AAA for body copy).
@immutable
class ReaderPalette {
  const ReaderPalette({required this.background, required this.text, required this.muted, required this.accent});

  final Color background;
  final Color text;

  /// Secondary copy: chapter labels, page counters.
  final Color muted;

  /// Controls and progress.
  final Color accent;

  static const ReaderPalette day = ReaderPalette(
    background: Color(0xFFFFFFFF),
    text: Color(0xFF1B1B1B),
    muted: Color(0xFF5C5C5C),
    accent: Color(0xFF1E6A7A),
  );

  static const ReaderPalette sepia = ReaderPalette(
    background: Color(0xFFF4ECD8),
    text: Color(0xFF3B2F20),
    muted: Color(0xFF6F5F48),
    accent: Color(0xFF8A5A00),
  );

  static const ReaderPalette night = ReaderPalette(
    background: Color(0xFF121212),
    text: Color(0xFFE6E1D9),
    muted: Color(0xFFA8A29A),
    accent: Color(0xFF7FD0E0),
  );

  Brightness get brightness => ThemeData.estimateBrightnessForColor(background);
}

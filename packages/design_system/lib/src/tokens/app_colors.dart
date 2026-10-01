import 'package:flutter/material.dart';

/// Colour system. Widgets use [ColorScheme] roles (and [AppSemanticColors]) only:
/// no `Color(0x...)` literals outside this file.
abstract final class AppColors {
  /// Brand seed: a deep ocean teal (calm, studious, distinct from success-green and error-red).
  /// Both light and dark schemes are generated from it with Material 3's tonal-spot variant.
  static const Color seed = Color(0xFF1E6A7A);

  static ColorScheme scheme(Brightness brightness) => ColorScheme.fromSeed(
    seedColor: seed,
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
  );
}

/// Roles Material 3 does not define, derived from the same seed so they harmonise.
@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.premium,
    required this.onPremium,
    required this.premiumContainer,
    required this.onPremiumContainer,
    required this.highlights,
  });

  factory AppSemanticColors.forBrightness(Brightness brightness) {
    final success = ColorScheme.fromSeed(
      seedColor: const Color(0xFF2E7D32),
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
    );
    final premium = ColorScheme.fromSeed(
      seedColor: const Color(0xFF8A5A00),
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
    );
    return AppSemanticColors(
      success: success.primary,
      onSuccess: success.onPrimary,
      successContainer: success.primaryContainer,
      onSuccessContainer: success.onPrimaryContainer,
      premium: premium.primary,
      onPremium: premium.onPrimary,
      premiumContainer: premium.primaryContainer,
      onPremiumContainer: premium.onPrimaryContainer,
      highlights: HighlightPalette.of(brightness),
    );
  }

  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;
  final Color premium;
  final Color onPremium;
  final Color premiumContainer;
  final Color onPremiumContainer;
  final HighlightPalette highlights;

  static AppSemanticColors of(BuildContext context) =>
      Theme.of(context).extension<AppSemanticColors>() ?? AppSemanticColors.forBrightness(Theme.of(context).brightness);

  @override
  AppSemanticColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? premium,
    Color? onPremium,
    Color? premiumContainer,
    Color? onPremiumContainer,
    HighlightPalette? highlights,
  }) => AppSemanticColors(
    success: success ?? this.success,
    onSuccess: onSuccess ?? this.onSuccess,
    successContainer: successContainer ?? this.successContainer,
    onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
    premium: premium ?? this.premium,
    onPremium: onPremium ?? this.onPremium,
    premiumContainer: premiumContainer ?? this.premiumContainer,
    onPremiumContainer: onPremiumContainer ?? this.onPremiumContainer,
    highlights: highlights ?? this.highlights,
  );

  @override
  AppSemanticColors lerp(covariant AppSemanticColors? other, double t) {
    if (other == null) return this;
    return AppSemanticColors(
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      successContainer: Color.lerp(successContainer, other.successContainer, t)!,
      onSuccessContainer: Color.lerp(onSuccessContainer, other.onSuccessContainer, t)!,
      premium: Color.lerp(premium, other.premium, t)!,
      onPremium: Color.lerp(onPremium, other.onPremium, t)!,
      premiumContainer: Color.lerp(premiumContainer, other.premiumContainer, t)!,
      onPremiumContainer: Color.lerp(onPremiumContainer, other.onPremiumContainer, t)!,
      highlights: t < 0.5 ? highlights : other.highlights,
    );
  }
}

/// The five reader highlight colours (Phase 4), defined now so annotations look the same everywhere.
/// Each has a name for screen readers: colour is never the only signal.
@immutable
class HighlightPalette {
  const HighlightPalette(this.colors);

  factory HighlightPalette.of(Brightness brightness) {
    Color tone(Color seed) => ColorScheme.fromSeed(seedColor: seed, brightness: brightness).primaryContainer;
    return HighlightPalette({
      HighlightColor.yellow: tone(const Color(0xFFF2C94C)),
      HighlightColor.green: tone(const Color(0xFF6FCF97)),
      HighlightColor.blue: tone(const Color(0xFF56CCF2)),
      HighlightColor.pink: tone(const Color(0xFFF28DB2)),
      HighlightColor.purple: tone(const Color(0xFFBB6BD9)),
    });
  }

  final Map<HighlightColor, Color> colors;

  Color operator [](HighlightColor key) => colors[key]!;
}

enum HighlightColor { yellow, green, blue, pink, purple }

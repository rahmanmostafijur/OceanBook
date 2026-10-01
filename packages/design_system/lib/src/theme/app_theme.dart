import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import '../tokens/app_colors.dart';
import '../tokens/app_motion.dart';
import '../tokens/app_shapes.dart';
import '../tokens/app_spacing.dart';
import '../tokens/app_typography.dart';

/// How dense the UI is. Mobile uses Material's standard density; the web admin is a desktop tool and
/// uses compact density with one-step-smaller body text. Same tokens, same colours, same shapes.
enum AppDensity { standard, compact }

/// Builds the Material 3 [ThemeData] for both apps from the central tokens.
abstract final class AppTheme {
  static ThemeData light({AppDensity density = AppDensity.standard}) => _build(Brightness.light, density);

  static ThemeData dark({AppDensity density = AppDensity.standard}) => _build(Brightness.dark, density);

  static ThemeData _build(Brightness brightness, AppDensity density) {
    final scheme = AppColors.scheme(brightness);
    var text = AppTypography.textTheme(scheme);
    if (density == AppDensity.compact) {
      text = text.copyWith(bodyLarge: text.bodyMedium, titleLarge: text.titleMedium?.copyWith(fontSize: 20));
    }
    final compact = density == AppDensity.compact;
    const minTarget = Size(AppSizes.minTouchTarget, AppSizes.minTouchTarget);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      textTheme: text,
      fontFamily: 'packages/design_system/${AppTypography.uiFamily}',
      fontFamilyFallback: AppTypography.fallback,
      scaffoldBackgroundColor: scheme.surface,
      visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
      materialTapTargetSize: compact ? MaterialTapTargetSize.shrinkWrap : MaterialTapTargetSize.padded,
      extensions: [AppSemanticColors.forBrightness(brightness)],
      splashFactory: InkSparkle.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: scheme.surfaceTint,
        elevation: AppElevation.level0,
        scrolledUnderElevation: AppElevation.level2,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
      ),
      cardTheme: CardThemeData(
        elevation: AppElevation.level0,
        color: scheme.surfaceContainerLow,
        shape: AppShapes.card,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: compact ? const Size(64, 40) : minTarget,
          textStyle: text.labelLarge,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: compact ? const Size(64, 40) : minTarget,
          textStyle: text.labelLarge,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: compact ? const Size(48, 40) : minTarget, textStyle: text.labelLarge),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: compact ? const Size(40, 40) : minTarget),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(AppShapes.extraSmall))),
        filled: false,
        isDense: compact,
        contentPadding: EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: compact ? AppSpacing.sm : AppSpacing.md,
        ),
        errorMaxLines: 3,
        helperMaxLines: 3,
      ),
      chipTheme: ChipThemeData(
        shape: AppShapes.chip,
        labelStyle: text.labelLarge,
        side: BorderSide(color: scheme.outlineVariant),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(minimumSize: compact ? const Size(48, 40) : minTarget),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.secondaryContainer,
        labelTextStyle: WidgetStatePropertyAll(text.labelMedium),
        height: 80,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.secondaryContainer,
        selectedLabelTextStyle: text.labelMedium?.copyWith(color: scheme.onSurface),
        unselectedLabelTextStyle: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
      ),
      navigationDrawerTheme: NavigationDrawerThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        indicatorColor: scheme.secondaryContainer,
        labelTextStyle: WidgetStatePropertyAll(text.labelLarge),
        indicatorShape: const StadiumBorder(),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: AppSpacing.listTilePadding,
        minVerticalPadding: compact ? AppSpacing.xxs : AppSpacing.xs,
        dense: compact,
        titleTextStyle: text.bodyLarge,
        subtitleTextStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      ),
      dialogTheme: DialogThemeData(shape: AppShapes.dialog, backgroundColor: scheme.surfaceContainerHigh),
      bottomSheetTheme: BottomSheetThemeData(
        shape: AppShapes.bottomSheet,
        backgroundColor: scheme.surfaceContainerLow,
        showDragHandle: true,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: AppShapes.chip,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: text.bodyMedium?.copyWith(color: scheme.onInverseSurface),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: AppMotion.long2,
        textStyle: text.bodySmall?.copyWith(color: scheme.onInverseSurface),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 1, space: 1),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
      ),
      badgeTheme: BadgeThemeData(backgroundColor: scheme.error, textColor: scheme.onError),
      dataTableTheme: DataTableThemeData(
        headingTextStyle: text.labelLarge,
        dataTextStyle: text.bodyMedium,
        headingRowColor: WidgetStatePropertyAll(scheme.surfaceContainer),
        dividerThickness: 1,
      ),
    );
  }
}

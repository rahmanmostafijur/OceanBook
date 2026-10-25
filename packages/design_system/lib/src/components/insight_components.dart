import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../tokens/app_colors.dart';
import '../tokens/app_shapes.dart';
import '../tokens/app_spacing.dart';

/// Colour family for a [StatTile]. Each maps to a container role, so tiles stay calm (60 % neutral) and
/// the hue only says what kind of number it is; the label always says it in words too.
enum StatTone { neutral, primary, success, premium }

/// A titled surface for one group of content: an insight, a settings group, a summary. Tonal fill and a
/// hairline outline instead of a shadow, matching the elevation rule in [AppElevation].
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({required this.child, this.title, this.subtitle, this.trailing, this.padding, super.key});

  final Widget child;
  final String? title;
  final String? subtitle;

  /// Shown on the title row, e.g. a period picker or an action.
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // A Material (not a DecoratedBox) so list tiles inside keep their ink and selection colours.
    return Material(
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppShapes.large),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: padding ?? const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(header: true, child: Text(title!, style: theme.textTheme.titleMedium)),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                      ],
                    ),
                  ),
                  if (trailing != null) ...[const SizedBox(width: AppSpacing.xs), trailing!],
                ],
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

/// One headline number: tonal icon, label and value, read out as a single "label, value" phrase.
class StatTile extends StatelessWidget {
  const StatTile({
    required this.icon,
    required this.label,
    required this.value,
    this.caption,
    this.tone = StatTone.neutral,
    super.key,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? caption;
  final StatTone tone;

  (Color, Color) _colors(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final semantic = AppSemanticColors.of(context);
    return switch (tone) {
      StatTone.neutral => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
      StatTone.primary => (scheme.primaryContainer, scheme.onPrimaryContainer),
      StatTone.success => (semantic.successContainer, semantic.onSuccessContainer),
      StatTone.premium => (semantic.premiumContainer, semantic.onPremiumContainer),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (container, onContainer) = _colors(context);
    return Semantics(
      container: true,
      label: [label, value, ?caption].join(', '),
      excludeSemantics: true,
      child: SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(color: container, shape: BoxShape.circle),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xs),
                    child: Icon(icon, size: AppSizes.iconSmall, color: onContainer),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(child: Text(label, style: theme.textTheme.labelLarge)),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            // Scales down rather than breaking a long number across lines at large text sizes.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                value,
                maxLines: 1,
                style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            if (caption != null)
              Text(caption!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

/// A labelled count for the charts below.
@immutable
class ChartDatum {
  const ChartDatum({required this.label, required this.value, this.semanticLabel});

  final String label;
  final int value;

  /// Full spoken form ("March 2026: 3"); defaults to "label: value".
  final String? semanticLabel;
}

/// Vertical bars over time (days, weeks, months). The newest bar is filled with the primary colour and
/// the rest with its container tone; counts sit above non-zero bars, so values never depend on colour.
/// Assistive tech reads every bar's [ChartDatum.semanticLabel] in order.
class ColumnChart extends StatelessWidget {
  const ColumnChart({required this.data, this.height = 160, this.format, super.key});

  final List<ChartDatum> data;
  final double height;

  /// Formats counts for the locale (e.g. Bangla digits); defaults to plain digits.
  final String Function(int)? format;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final maxValue = data.fold<int>(0, (m, d) => math.max(m, d.value));
    final labelStyle = theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant);
    final valueStyle = theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600);
    final valueHeight = MediaQuery.textScalerOf(context).scale(16);
    return Semantics(
      container: true,
      label: data.map((d) => d.semanticLabel ?? '${d.label}: ${d.value}').join('; '),
      excludeSemantics: true,
      child: Column(
        children: [
          SizedBox(
            height: height,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final (i, d) in data.indexed)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs / 2),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final barSpace = math.max(0.0, constraints.maxHeight - valueHeight);
                          final fraction = maxValue == 0 ? 0.0 : d.value / maxValue;
                          return Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              if (d.value > 0)
                                SizedBox(
                                  height: valueHeight,
                                  child: FittedBox(
                                    child: Text(format?.call(d.value) ?? '${d.value}', style: valueStyle),
                                  ),
                                ),
                              Container(
                                height: math.max(d.value > 0 ? 4.0 : 2.0, barSpace * fraction),
                                decoration: BoxDecoration(
                                  color: d.value == 0
                                      ? scheme.outlineVariant
                                      : i == data.length - 1
                                      ? scheme.primary
                                      : scheme.primary.withValues(alpha: 0.45),
                                  borderRadius: BorderRadius.circular(AppShapes.extraSmall),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          _AxisLabels(labels: [for (final d in data) d.label], style: labelStyle),
        ],
      ),
    );
  }
}

/// Axis labels under the bars. When columns are too narrow for a readable label (many bars, a narrow
/// screen or large text) only every n-th label is shown, counted back from the newest, each centred on
/// its bar with room to spare, instead of shrinking every label until it is unreadable.
class _AxisLabels extends StatelessWidget {
  const _AxisLabels({required this.labels, required this.style});

  final List<String> labels;
  final TextStyle? style;

  /// Room a short label (about three characters) needs, in multiples of the font size.
  static const double _labelEms = 3.2;

  @override
  Widget build(BuildContext context) {
    final fontSize = MediaQuery.textScalerOf(context).scale(style?.fontSize ?? 11);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final column = width / labels.length;
        final step = math.max(1, (fontSize * _labelEms / column).ceil());
        final span = math.min(width, column * step);
        return SizedBox(
          height: fontSize * 1.6,
          child: Stack(
            children: [
              for (final (i, label) in labels.indexed)
                if ((labels.length - 1 - i) % step == 0)
                  Positioned(
                    left: (column * (i + 0.5) - span / 2).clamp(0, width - span),
                    width: span,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(label, style: style, maxLines: 1),
                      ),
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }
}

/// Ranked rows: label, count and a bar scaled to the largest count. Each row is read as one phrase.
class RankedBars extends StatelessWidget {
  const RankedBars({required this.data, this.color, this.maxValue, this.format, super.key});

  /// Formats counts for the locale; defaults to plain digits.
  final String Function(int)? format;

  final List<ChartDatum> data;
  final Color? color;

  /// Full-scale value; defaults to the largest count, set it to show shares of a whole.
  final int? maxValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final maxValue = this.maxValue ?? data.fold<int>(0, (m, d) => math.max(m, d.value));
    return Column(
      children: [
        for (final d in data)
          Semantics(
            label: d.semanticLabel ?? '${d.label}: ${d.value}',
            excludeSemantics: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs + 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(d.label, style: theme.textTheme.bodyMedium, overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(format?.call(d.value) ?? '${d.value}', style: theme.textTheme.labelLarge),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppShapes.extraSmall),
                    child: LinearProgressIndicator(
                      value: maxValue == 0 ? 0 : d.value / maxValue,
                      minHeight: 6,
                      color: color ?? scheme.primary,
                      backgroundColor: scheme.surfaceContainerHighest,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Grouped settings: a section label above a card whose rows are separated by inset dividers.
class SettingsSection extends StatelessWidget {
  const SettingsSection({required this.title, required this.children, super.key});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: AppSpacing.xxs, bottom: AppSpacing.xs),
          child: Semantics(
            header: true,
            child: Text(title, style: theme.textTheme.titleSmall?.copyWith(color: scheme.primary)),
          ),
        ),
        Material(
          color: scheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppShapes.large),
            side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (final (i, child) in children.indexed) ...[
                if (i > 0) const Divider(height: 1, indent: AppSpacing.md, endIndent: AppSpacing.md),
                child,
              ],
            ],
          ),
        ),
      ],
    );
  }
}

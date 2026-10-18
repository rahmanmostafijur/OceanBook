import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ob_l10n/ob_l10n.dart';
import 'package:reader_core/reader_core.dart';

import 'reader_settings_controller.dart';

/// Opens the reading settings as a compact panel. The barrier is nearly transparent so the page
/// behind visibly changes as each control is used.
Future<void> showReaderSettings(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  barrierColor: Colors.black12,
  sheetAnimationStyle: AppMotion.reduced(context) ? AnimationStyle.noAnimation : null,
  showDragHandle: true,
  constraints: const BoxConstraints(maxWidth: AppSizes.maxFormWidth + 40),
  shape: AppShapes.bottomSheet,
  builder: (_) => const ReaderSettingsPanel(),
);

class ReaderSettingsPanel extends ConsumerWidget {
  const ReaderSettingsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ObLocalizations.of(context);
    final settings = ref.watch(readerSettingsProvider);
    final notifier = ref.read(readerSettingsProvider.notifier);
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(header: true, child: Text(l10n.readerSettings, style: theme.textTheme.titleLarge)),
            const SizedBox(height: AppSpacing.lg),
            _Label(l10n.readerTextSize),
            Row(
              children: [
                IconButton.filledTonal(
                  tooltip: l10n.readerSmallerText,
                  onPressed: settings.fontScale > minFontScale ? notifier.decreaseFont : null,
                  icon: const Icon(Icons.text_decrease),
                ),
                Expanded(
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      l10n.readerFontPercent((settings.fontScale * 100).round()),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: l10n.readerLargerText,
                  onPressed: settings.fontScale < maxFontScale ? notifier.increaseFont : null,
                  icon: const Icon(Icons.text_increase),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            _Label(l10n.readerTheme),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<ReaderTheme>(
                segments: [
                  ButtonSegment(
                    value: ReaderTheme.light,
                    icon: const Icon(Icons.light_mode_outlined),
                    label: Text(l10n.readerThemeDay),
                  ),
                  ButtonSegment(
                    value: ReaderTheme.dark,
                    icon: const Icon(Icons.dark_mode_outlined),
                    label: Text(l10n.readerThemeNight),
                  ),
                  ButtonSegment(
                    value: ReaderTheme.sepia,
                    icon: const Icon(Icons.coffee_outlined),
                    label: Text(l10n.readerThemeSepia),
                  ),
                ],
                selected: {settings.theme},
                onSelectionChanged: (selection) => notifier.setTheme(selection.first),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            _Label(l10n.readerAlignment),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<bool>(
                segments: [
                  ButtonSegment(
                    value: false,
                    icon: const Icon(Icons.format_align_left),
                    label: Text(l10n.readerAlignStart),
                  ),
                  ButtonSegment(
                    value: true,
                    icon: const Icon(Icons.format_align_justify),
                    label: Text(l10n.readerAlignJustify),
                  ),
                ],
                selected: {settings.justify},
                onSelectionChanged: (selection) => notifier.setJustify(justify: selection.first),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );
}

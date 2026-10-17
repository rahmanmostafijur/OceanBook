import 'package:flutter/material.dart';

import '../tokens/app_shapes.dart';
import '../tokens/app_spacing.dart';

/// Renders a ContentDoc (docs/architecture/08 §3): the closed JSON document model the question bank uses
/// for stems, options, passages, explanations and answers. Only the known nodes are drawn, so a document
/// can never inject anything; unknown nodes are skipped, which keeps old clients working with newer
/// servers.
///
/// Math is shown as its TeX source in a distinct, labelled style until a LaTeX renderer is added; images
/// show their alt text until the media URL contract for question images lands.
class ContentDocView extends StatelessWidget {
  const ContentDocView({required this.doc, this.style, super.key});

  final Map<String, Object?> doc;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final base = style ?? Theme.of(context).textTheme.bodyLarge ?? const TextStyle();
    final blocks = <Widget>[];
    for (final raw in (doc['blocks'] as List?) ?? const <Object?>[]) {
      if (raw is! Map) continue;
      final block = raw.cast<String, Object?>();
      final widget = switch (block['type']) {
        'paragraph' => _Rich(inlines: block['inlines'], style: base),
        'image' => _ImagePlaceholder(alt: (block['alt'] as String?) ?? ''),
        'list' => _ListBlock(block: block, style: base),
        'table' => _TableBlock(rows: block['rows'], style: base),
        _ => null,
      };
      if (widget != null) blocks.add(widget);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, block) in blocks.indexed) ...[if (i > 0) const SizedBox(height: AppSpacing.xs), block],
      ],
    );
  }
}

class _Rich extends StatelessWidget {
  const _Rich({required this.inlines, required this.style});

  final Object? inlines;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final spans = <InlineSpan>[];
    for (final raw in (inlines as List?) ?? const <Object?>[]) {
      if (raw is! Map) continue;
      final node = raw.cast<String, Object?>();
      switch (node['type']) {
        case 'text':
          spans.add(_text(node, style));
        case 'math':
          final tex = (node['tex'] as String?) ?? '';
          spans.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: Semantics(
                label: tex,
                child: ExcludeSemantics(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
                    decoration: BoxDecoration(
                      color: scheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(AppShapes.extraSmall),
                    ),
                    child: Text(
                      tex,
                      style: style.copyWith(
                        fontFamily: 'monospace',
                        fontStyle: FontStyle.italic,
                        color: scheme.onSecondaryContainer,
                        fontSize: (style.fontSize ?? 16) * 0.92,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        case 'blank':
          spans.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: Semantics(
                label: '____',
                child: Container(
                  width: 72,
                  height: (style.fontSize ?? 16) * 1.2,
                  margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: scheme.onSurface, width: 1.5)),
                  ),
                ),
              ),
            ),
          );
      }
    }
    return Text.rich(TextSpan(children: spans, style: style));
  }

  static InlineSpan _text(Map<String, Object?> node, TextStyle base) {
    final text = (node['text'] as String?) ?? '';
    final raised = node['sup'] == true;
    final lowered = node['sub'] == true;
    final decorated = base.copyWith(
      fontWeight: node['bold'] == true ? FontWeight.w700 : null,
      fontStyle: node['italic'] == true ? FontStyle.italic : null,
      decoration: node['underline'] == true ? TextDecoration.underline : null,
    );
    if (!raised && !lowered) return TextSpan(text: text, style: decorated);
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: Transform.translate(
        offset: Offset(0, raised ? -(base.fontSize ?? 16) * 0.35 : (base.fontSize ?? 16) * 0.2),
        child: Text(text, style: decorated.copyWith(fontSize: (base.fontSize ?? 16) * 0.72)),
      ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder({required this.alt});

  final String alt;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      image: true,
      label: alt,
      child: ExcludeSemantics(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(AppShapes.medium),
          ),
          child: Row(
            children: [
              Icon(Icons.image_outlined, color: scheme.onSurfaceVariant),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  alt,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const _banglaMarkers = ['ক', 'খ', 'গ', 'ঘ', 'ঙ', 'চ', 'ছ', 'জ', 'ঝ', 'ঞ'];
const _romans = ['i', 'ii', 'iii', 'iv', 'v', 'vi', 'vii', 'viii', 'ix', 'x'];

class _ListBlock extends StatelessWidget {
  const _ListBlock({required this.block, required this.style});

  final Map<String, Object?> block;
  final TextStyle style;

  String _marker(int index) {
    final n = index + 1;
    return switch (block['style']) {
      'decimal' => '$n.',
      'roman' => '${index < _romans.length ? _romans[index] : n}.',
      'bangla' => '${index < _banglaMarkers.length ? _banglaMarkers[index] : n}.',
      _ => '•',
    };
  }

  @override
  Widget build(BuildContext context) {
    final items = (block['items'] as List?) ?? const <Object?>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, item) in items.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 32, child: Text(_marker(i), style: style)),
                Expanded(
                  child: _Rich(inlines: item, style: style),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _TableBlock extends StatelessWidget {
  const _TableBlock({required this.rows, required this.style});

  final Object? rows;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tableRows = <TableRow>[
      for (final row in (rows as List?) ?? const <Object?>[])
        TableRow(
          children: [
            for (final cell in (row as List?) ?? const <Object?>[])
              Padding(
                padding: const EdgeInsets.all(AppSpacing.xs),
                child: _Rich(inlines: cell, style: style),
              ),
          ],
        ),
    ];
    if (tableRows.isEmpty) return const SizedBox.shrink();
    return Table(
      border: TableBorder.all(color: scheme.outlineVariant),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: tableRows,
    );
  }
}

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:ob_l10n/ob_l10n.dart';

import 'content_text.dart';

const maxBlanks = 20;
const maxAcceptedAnswers = 20;
const minMatchItems = 2;
const maxMatchItems = 12;

/// The accepted answers of a fill-in-the-blank question, one field per gap (`answer_spec.blanks`). Each field
/// holds one accepted answer per line. Any other keys the server stored on a blank are kept as they were.
class BlankAnswers {
  BlankAnswers._(this._raw, List<List<String>> accepted) {
    for (final lines in accepted) {
      answers.add(TextEditingController(text: lines.join('\n')));
    }
  }

  BlankAnswers.empty() : _raw = const [];

  final List<Map<String, Object?>> _raw;
  final List<TextEditingController> answers = [];

  /// Null when [spec] holds anything but a list of blanks with plain accepted answers.
  static BlankAnswers? fromSpec(Map<String, Object?> spec) {
    final blanks = spec['blanks'];
    if (blanks is! List || blanks.isEmpty || blanks.length > maxBlanks) return null;
    final raw = <Map<String, Object?>>[];
    final accepted = <List<String>>[];
    for (final blank in blanks) {
      final list = blank is Map ? blank['accepted'] : null;
      if (blank is! Map || list is! List || list.any((a) => a is! String || a.contains('\n'))) return null;
      raw.add(blank.cast<String, Object?>());
      accepted.add(list.cast<String>());
    }
    return BlankAnswers._(raw, accepted);
  }

  /// Gap numbers 1..n each used at least once, with no number skipped.
  static bool markersValid(String stem) {
    final numbers = blankNumbers(stem).toSet();
    return numbers.isNotEmpty && numbers.length <= maxBlanks && numbers.every((n) => n >= 1 && n <= numbers.length);
  }

  /// Grows or shrinks the fields to the number of gaps in [stem]; a stem with skipped numbers changes nothing.
  void syncWith(String stem) {
    if (!markersValid(stem)) return;
    final count = blankNumbers(stem).toSet().length;
    while (answers.length < count) {
      answers.add(TextEditingController());
    }
    while (answers.length > count) {
      answers.removeLast().dispose();
    }
  }

  List<String> _lines(TextEditingController c) => [
    for (final line in c.text.split('\n'))
      if (line.trim().isNotEmpty) line.trim(),
  ];

  bool get isComplete =>
      answers.isNotEmpty && answers.every((c) => _lines(c).isNotEmpty && _lines(c).length <= maxAcceptedAnswers);

  Map<String, Object?> toSpec(Map<String, Object?> rawSpec) => {
    ...rawSpec,
    'blanks': [
      for (final (i, c) in answers.indexed) {...?(i < _raw.length ? _raw[i] : null), 'accepted': _lines(c)},
    ],
  };

  void dispose() {
    for (final c in answers) {
      c.dispose();
    }
  }
}

/// The two columns of a matching question and which right item each left item pairs with
/// (`answer_spec.left`, `right`, `pairs`). Items are plain text.
class MatchingDraft {
  MatchingDraft._(List<String> left, List<String> right, this.targets, this._raw)
    : left = [for (final t in left) TextEditingController(text: t)],
      right = [for (final t in right) TextEditingController(text: t)];

  factory MatchingDraft.empty() => MatchingDraft._(
    List.filled(minMatchItems, ''),
    List.filled(minMatchItems, ''),
    List<int?>.filled(minMatchItems, null, growable: true),
    const {},
  );

  final List<TextEditingController> left;
  final List<TextEditingController> right;

  /// For each left item, the index of the right item it matches.
  final List<int?> targets;
  final Map<String, Object?> _raw;

  /// Null when [spec] is not plain strings with one valid pair per left item.
  static MatchingDraft? fromSpec(Map<String, Object?> spec) {
    final left = spec['left'];
    final right = spec['right'];
    final pairs = spec['pairs'];
    if (left is! List || right is! List || pairs is! List) return null;
    if (left.any((e) => e is! String) || right.any((e) => e is! String)) return null;
    if (left.length < minMatchItems || left.length > maxMatchItems) return null;
    if (right.length < minMatchItems || right.length > maxMatchItems) return null;
    final targets = List<int?>.filled(left.length, null, growable: true);
    for (final pair in pairs) {
      if (pair is! List || pair.length != 2 || pair[0] is! int || pair[1] is! int) return null;
      final (a, b) = (pair[0] as int, pair[1] as int);
      if (a < 0 || a >= left.length || b < 0 || b >= right.length || targets[a] != null) return null;
      targets[a] = b;
    }
    if (targets.contains(null)) return null;
    return MatchingDraft._(left.cast<String>(), right.cast<String>(), targets, spec);
  }

  bool get isComplete =>
      left.every((c) => c.text.trim().isNotEmpty) &&
      right.every((c) => c.text.trim().isNotEmpty) &&
      !targets.contains(null);

  void addLeft() {
    left.add(TextEditingController());
    targets.add(null);
  }

  void removeLeft(int index) {
    left.removeAt(index).dispose();
    targets.removeAt(index);
  }

  void addRight() => right.add(TextEditingController());

  /// Removing a right item clears the pairs that pointed at it and renumbers the ones after it.
  void removeRight(int index) {
    right.removeAt(index).dispose();
    for (var i = 0; i < targets.length; i++) {
      final t = targets[i];
      if (t == null) continue;
      targets[i] = t == index ? null : (t > index ? t - 1 : t);
    }
  }

  Map<String, Object?> toSpec() => {
    ..._raw,
    'left': [for (final c in left) c.text.trim()],
    'right': [for (final c in right) c.text.trim()],
    'pairs': [
      for (final (i, t) in targets.indexed) [i, t],
    ],
  };

  void dispose() {
    for (final c in [...left, ...right]) {
      c.dispose();
    }
  }
}

/// One field per gap for the accepted answers.
class BlankAnswersEditor extends StatelessWidget {
  const BlankAnswersEditor({required this.blanks, super.key});

  final BlankAnswers blanks;

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, c) in blanks.answers.indexed)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: TextFormField(
              key: Key('blank-answers-$i'),
              controller: c,
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: l10n.adminBlankAnswers(i + 1),
                helperText: l10n.adminBlankAnswersHint,
              ),
              validator: (v) {
                final lines = (v ?? '').split('\n').where((l) => l.trim().isNotEmpty).length;
                return lines == 0 || lines > maxAcceptedAnswers ? l10n.errorValidation : null;
              },
            ),
          ),
      ],
    );
  }
}

/// The left and right columns of a matching question, with a picker pairing each left item.
class MatchingEditor extends StatelessWidget {
  const MatchingEditor({required this.draft, required this.onChanged, super.key});

  final MatchingDraft draft;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    final theme = Theme.of(context);
    String? requiredText(String? v) => (v?.trim().isEmpty ?? true) ? l10n.errorValidation : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.lg),
        Semantics(header: true, child: Text(l10n.adminMatchingRight, style: theme.textTheme.titleMedium)),
        for (final (i, c) in draft.right.indexed)
          Padding(
            key: ObjectKey(c),
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    key: Key('match-right-$i'),
                    controller: c,
                    decoration: InputDecoration(labelText: '${l10n.adminMatchingItem} ${i + 1}'),
                    onChanged: (_) => onChanged(),
                    validator: requiredText,
                  ),
                ),
                IconButton(
                  key: Key('match-right-remove-$i'),
                  tooltip: l10n.adminRemoveItem,
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: draft.right.length <= minMatchItems
                      ? null
                      : () {
                          draft.removeRight(i);
                          onChanged();
                        },
                ),
              ],
            ),
          ),
        if (draft.right.length < maxMatchItems)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const Key('match-right-add'),
              icon: const Icon(Icons.add),
              label: Text(l10n.adminAddItem),
              onPressed: () {
                draft.addRight();
                onChanged();
              },
            ),
          ),
        const SizedBox(height: AppSpacing.lg),
        Semantics(header: true, child: Text(l10n.adminMatchingLeft, style: theme.textTheme.titleMedium)),
        for (final (i, c) in draft.left.indexed)
          Padding(
            key: ObjectKey(c),
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 320,
                  child: TextFormField(
                    key: Key('match-left-$i'),
                    controller: c,
                    decoration: InputDecoration(labelText: '${l10n.adminMatchingItem} ${i + 1}'),
                    validator: requiredText,
                  ),
                ),
                SizedBox(
                  width: 220,
                  key: Key('match-target-$i'),
                  child: DropdownButtonFormField<int>(
                    key: ValueKey('${draft.targets[i]}-${draft.right.length}'),
                    isExpanded: true,
                    initialValue: draft.targets[i],
                    decoration: InputDecoration(labelText: l10n.adminMatchesWith),
                    items: [
                      for (var r = 0; r < draft.right.length; r++)
                        DropdownMenuItem(
                          value: r,
                          child: Text('${r + 1}. ${draft.right[r].text}', overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) {
                      draft.targets[i] = v;
                      onChanged();
                    },
                    validator: (v) => v == null ? l10n.errorValidation : null,
                  ),
                ),
                IconButton(
                  key: Key('match-left-remove-$i'),
                  tooltip: l10n.adminRemoveItem,
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: draft.left.length <= minMatchItems
                      ? null
                      : () {
                          draft.removeLeft(i);
                          onChanged();
                        },
                ),
              ],
            ),
          ),
        if (draft.left.length < maxMatchItems)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const Key('match-left-add'),
              icon: const Icon(Icons.add),
              label: Text(l10n.adminAddItem),
              onPressed: () {
                draft.addLeft();
                onChanged();
              },
            ),
          ),
      ],
    );
  }
}

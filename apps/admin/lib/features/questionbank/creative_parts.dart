import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:ob_l10n/ob_l10n.dart';

import 'content_text.dart';

const maxCreativeParts = 6;
const _minCreativeParts = 1;
const _partLabelWidth = 72.0;
const _partMarksWidth = 96.0;
const _partLevelWidth = 200.0;

/// Cognitive levels of a creative part, in the order they are graded (wire names as the server expects).
const cognitiveLevels = ['knowledge', 'comprehension', 'application', 'higher_order'];

/// The usual ক/খ/গ/ঘ layout: 1, 2, 3 and 4 marks at the four levels.
const defaultPartMarks = ['1', '2', '3', '4'];

String cognitiveLevelLabel(ObLocalizations l10n, String level) => switch (level) {
  'knowledge' => l10n.adminCognitiveKnowledge,
  'comprehension' => l10n.adminCognitiveComprehension,
  'application' => l10n.adminCognitiveApplication,
  'higher_order' => l10n.adminCognitiveHigherOrder,
  _ => level,
};

/// One part (ক, খ, গ, ঘ) of a creative question while it is being edited.
class PartDraft {
  PartDraft({required String label, required String prompt, required String marks, required this.level})
    : label = TextEditingController(text: label),
      prompt = TextEditingController(text: prompt),
      marks = TextEditingController(text: marks);

  final TextEditingController label;
  final TextEditingController prompt;
  final TextEditingController marks;
  String level;

  void dispose() {
    label.dispose();
    prompt.dispose();
    marks.dispose();
  }
}

/// The sum of the parts' marks; parts with unreadable marks count as zero (validation reports them).
double totalPartMarks(Iterable<PartDraft> parts) =>
    parts.fold(0, (sum, p) => sum + (double.tryParse(p.marks.text.trim()) ?? 0));

/// The editable rows for the parts of a creative question. The server requires the part marks to add up
/// to the question's marks, so the question's marks are shown as that total instead of being typed.
class CreativePartsEditor extends StatelessWidget {
  const CreativePartsEditor({
    required this.parts,
    required this.onAdd,
    required this.onRemove,
    required this.onChanged,
    super.key,
  });

  final List<PartDraft> parts;
  final VoidCallback onAdd;
  final void Function(int index) onRemove;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    final total = totalPartMarks(parts);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.lg),
        Semantics(header: true, child: Text(l10n.adminPartsHeading, style: Theme.of(context).textTheme.titleMedium)),
        for (final (i, part) in parts.indexed)
          Padding(
            key: ObjectKey(part),
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.start,
              children: [
                SizedBox(
                  width: _partLabelWidth,
                  child: TextFormField(
                    key: Key('part-label-$i'),
                    controller: part.label,
                    decoration: InputDecoration(labelText: l10n.adminPartLabel),
                    validator: (v) => (v?.trim().isEmpty ?? true) || v!.trim().length > 8 ? l10n.errorValidation : null,
                  ),
                ),
                SizedBox(
                  width: _partMarksWidth,
                  child: TextFormField(
                    key: Key('part-marks-$i'),
                    controller: part.marks,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: l10n.adminPartMarks),
                    onChanged: (_) => onChanged(),
                    validator: (v) {
                      final marks = double.tryParse(v?.trim() ?? '');
                      return marks == null || marks <= 0 || marks > 999 ? l10n.errorValidation : null;
                    },
                  ),
                ),
                SizedBox(
                  width: _partLevelWidth,
                  child: DropdownButtonFormField<String>(
                    key: Key('part-level-$i'),
                    isExpanded: true,
                    initialValue: part.level,
                    decoration: InputDecoration(labelText: l10n.adminPartLevel),
                    items: [
                      for (final level in cognitiveLevels)
                        DropdownMenuItem(value: level, child: Text(cognitiveLevelLabel(l10n, level))),
                    ],
                    onChanged: (v) {
                      part.level = v!;
                      onChanged();
                    },
                  ),
                ),
                IconButton(
                  key: Key('part-remove-$i'),
                  tooltip: l10n.adminRemovePart,
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: parts.length <= _minCreativeParts ? null : () => onRemove(i),
                ),
                SizedBox(
                  width: double.infinity,
                  child: TextFormField(
                    key: Key('part-prompt-$i'),
                    controller: part.prompt,
                    minLines: 2,
                    maxLines: 5,
                    decoration: InputDecoration(labelText: l10n.adminPartPrompt),
                    validator: (v) => isValidContentText(v ?? '') ? null : l10n.errorValidation,
                  ),
                ),
              ],
            ),
          ),
        if (parts.length < maxCreativeParts)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const Key('part-add'),
              icon: const Icon(Icons.add),
              label: Text(l10n.adminAddPart),
              onPressed: onAdd,
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: Text(
            key: const Key('part-total'),
            l10n.adminTotalMarks(formatMarks(total)),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}

/// `3` for whole numbers, `2.5` otherwise.
String formatMarks(double marks) => marks == marks.roundToDouble() ? '${marks.round()}' : '$marks';

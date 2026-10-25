import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:ob_core/ob_core.dart';
import 'package:ob_l10n/ob_l10n.dart';

import 'content_text.dart';

const minOptions = 2;
const maxSingleOptions = 6;
const maxMultiOptions = 8;
const answerLabels = {
  'bn': ['ক', 'খ', 'গ', 'ঘ', 'ঙ', 'চ', 'ছ', 'জ'],
  'en': ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H'],
};
const trueFalseText = {
  'bn': ['সত্য', 'মিথ্যা'],
  'en': ['True', 'False'],
};

class OptionDraft {
  OptionDraft({required String label, required String text, this.correct = false})
    : label = TextEditingController(text: label),
      text = TextEditingController(text: text);

  final TextEditingController label;
  final TextEditingController text;
  bool correct;

  void dispose() {
    label.dispose();
    text.dispose();
  }
}

/// The options of a single choice, multiple choice or true/false question: label, text, a correct mark
/// and (except for true/false) add and remove.
class OptionsEditor extends StatelessWidget {
  const OptionsEditor({
    required this.options,
    required this.type,
    required this.locale,
    required this.invalid,
    required this.onCorrect,
    required this.onRemove,
    required this.onAdd,
    super.key,
  });

  final List<OptionDraft> options;
  final QuestionType type;
  final String locale;

  /// Shows the "mark the correct option" message.
  final bool invalid;
  final void Function(int index, bool value) onCorrect;
  final ValueChanged<int> onRemove;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    final isTrueFalse = type == QuestionType.trueFalse;
    final max = type == QuestionType.mcqMulti ? maxMultiOptions : maxSingleOptions;
    String? required(String? v) => isValidContentText(v ?? '') ? null : l10n.errorValidation;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.lg),
        Semantics(header: true, child: Text(l10n.adminOptionsHeading, style: Theme.of(context).textTheme.titleMedium)),
        for (final (i, o) in options.indexed)
          Padding(
            key: ObjectKey(o),
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 72,
                  child: TextFormField(
                    key: Key('option-label-$i'),
                    controller: o.label,
                    decoration: InputDecoration(labelText: l10n.adminOptionLabel),
                    validator: (v) => (v?.trim().isEmpty ?? true) || v!.trim().length > 8 ? l10n.errorValidation : null,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextFormField(
                    key: Key('option-text-$i'),
                    controller: o.text,
                    decoration: InputDecoration(labelText: l10n.adminOptionText),
                    validator: required,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Semantics(
                  label: l10n.adminOptionCorrect,
                  child: Checkbox(
                    key: Key('option-correct-$i'),
                    value: o.correct,
                    onChanged: (v) => onCorrect(i, v ?? false),
                  ),
                ),
                if (!isTrueFalse)
                  IconButton(
                    key: Key('option-remove-$i'),
                    tooltip: l10n.adminRemoveOption,
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: options.length <= minOptions ? null : () => onRemove(i),
                  ),
              ],
            ),
          ),
        if (invalid)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Semantics(
              liveRegion: true,
              child: Text(
                type == QuestionType.mcqMulti ? l10n.adminCorrectAtLeastOne : l10n.adminCorrectExactlyOne,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ),
        if (!isTrueFalse && options.length < max)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const Key('option-add'),
              icon: const Icon(Icons.add),
              label: Text(l10n.adminAddOption),
              onPressed: onAdd,
            ),
          ),
      ],
    );
  }
}

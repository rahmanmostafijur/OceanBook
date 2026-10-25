import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:ob_l10n/ob_l10n.dart';

import 'content_text.dart';
import 'creative_parts.dart';
import 'option_fields.dart';

const _humanOrigin = 'human_translation';

/// The text of a question in its second language (English for a Bangla question and the other way round),
/// kept beside the source-language fields. Everything is optional; leaving all of it empty means no
/// translation. A translation the editor cannot reproduce (images, unknown fields) is left untouched.
class TranslationDraft {
  TranslationDraft.empty(this.locale, {this.allowBlanks = false});

  TranslationDraft._(this.locale, {required this.allowBlanks});

  /// The translation in [locale] found in the question's saved content (`translations[locale]`).
  factory TranslationDraft.fromRaw(Map<String, Object?> content, String locale, {required bool allowBlanks}) {
    final raw = ((content['translations'] as Map?)?[locale] as Map?)?.cast<String, Object?>() ?? const {};
    final draft = TranslationDraft._(locale, allowBlanks: allowBlanks);
    String? read(String key) =>
        textFromDoc(raw[key] as Map<String, Object?>?, allowBlanks: key == 'stem' && allowBlanks);
    final stemText = read('stem');
    final explanationText = read('explanation');
    final modelText = read('model_answer');
    final guidanceText = read('marking_guidance');
    if ([stemText, explanationText, modelText, guidanceText].contains(null)) draft.supported = false;
    draft.stem.text = stemText ?? '';
    draft.explanation.text = explanationText ?? '';
    draft.modelAnswer.text = modelText ?? '';
    draft.guidance.text = guidanceText ?? '';
    return draft;
  }

  final String locale;
  final bool allowBlanks;
  bool supported = true;
  final stem = TextEditingController();
  final explanation = TextEditingController();
  final modelAnswer = TextEditingController();
  final guidance = TextEditingController();
  final stimulus = TextEditingController();
  final Map<Object, TextEditingController> _byDraft = {};

  /// The stimulus text when the question was loaded, to tell whether it changed.
  String stimulusAtLoad = '';

  /// The field for an option or part draft, created on first use.
  TextEditingController of(Object draft) => _byDraft.putIfAbsent(draft, TextEditingController.new);

  void seedStimulus(Object? doc) {
    final text = textFromDoc(doc as Map<String, Object?>?);
    if (text == null) {
      supported = false;
      return;
    }
    stimulus.text = text;
    stimulusAtLoad = text;
  }

  void seedOptions(List<OptionDraft> drafts, List<Map<String, Object?>> rawOptions) {
    for (final (i, draft) in drafts.indexed) {
      final doc = i < rawOptions.length ? ((rawOptions[i]['content'] as Map?)?[locale]) : null;
      final text = textFromDoc(doc as Map<String, Object?>?);
      if (text == null) supported = false;
      of(draft).text = text ?? '';
    }
  }

  void seedParts(List<PartDraft> drafts, List<Map<String, Object?>> rawParts) {
    for (final (i, draft) in drafts.indexed) {
      final doc = i < rawParts.length ? ((rawParts[i]['prompt'] as Map?)?[locale]) : null;
      final text = textFromDoc(doc as Map<String, Object?>?);
      if (text == null) supported = false;
      of(draft).text = text ?? '';
    }
  }

  bool get hasContent =>
      [stem, explanation, modelAnswer, guidance, stimulus, ..._byDraft.values].any((c) => c.text.trim().isNotEmpty);

  /// [translations] with this language's entry set from the fields, or removed when they are all empty.
  Map<String, Object?> applyTo(Map<String, Object?> translations, {required bool shortAnswer}) {
    if (!supported) return translations;
    final result = {...translations};
    if (!hasContent) return result..remove(locale);
    final current = {...?(result[locale] as Map?)?.cast<String, Object?>()};
    void set(String key, TextEditingController c, {bool allowBlanks = false}) {
      if (c.text.trim().isEmpty) {
        current.remove(key);
      } else {
        current[key] = docFromText(c.text, allowBlanks: allowBlanks);
      }
    }

    set('stem', stem, allowBlanks: allowBlanks);
    set('explanation', explanation);
    if (shortAnswer) {
      set('model_answer', modelAnswer);
      set('marking_guidance', guidance);
    }
    current['origin'] ??= _humanOrigin;
    return result..[locale] = current;
  }

  /// The passage's documents with this language's entry set from the field, or removed when it is empty.
  Map<String, Object?> applyToStimulus(Map<String, Object?> docs) {
    if (!supported) return docs;
    final result = {...docs};
    if (stimulus.text.trim().isEmpty) return result..remove(locale);
    return result..[locale] = docFromText(stimulus.text);
  }

  bool get stimulusChanged => stimulus.text != stimulusAtLoad;

  /// [built] (one map per option, in the order of [drafts]) with the text of this language set or removed.
  List<Map<String, Object?>> applyToOptions(List<OptionDraft> drafts, List<Map<String, Object?>> built) =>
      supported ? _localised(drafts, built, 'content') : built;

  List<Map<String, Object?>> applyToParts(List<PartDraft> drafts, List<Map<String, Object?>> built) =>
      supported ? _localised(drafts, built, 'prompt') : built;

  List<Map<String, Object?>> _localised(List<Object> drafts, List<Map<String, Object?>> built, String key) => [
    for (final (i, item) in built.indexed)
      {
        ...item,
        key: _with((item[key]! as Map).cast<String, Object?>(), of(drafts[i])),
      },
  ];

  Map<String, Object?> _with(Map<String, Object?> docs, TextEditingController c) {
    final result = {...docs};
    if (c.text.trim().isEmpty) {
      result.remove(locale);
    } else {
      result[locale] = docFromText(c.text);
    }
    return result;
  }

  void dispose() {
    for (final c in [stem, explanation, modelAnswer, guidance, stimulus, ..._byDraft.values]) {
      c.dispose();
    }
  }
}

/// The second-language fields of the question editor.
class TranslationSection extends StatelessWidget {
  const TranslationSection({
    required this.draft,
    required this.options,
    required this.parts,
    required this.isCreative,
    required this.isShortAnswer,
    super.key,
  });

  final TranslationDraft draft;
  final List<OptionDraft> options;
  final List<PartDraft> parts;
  final bool isCreative;
  final bool isShortAnswer;

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    final theme = Theme.of(context);
    final language = draft.locale == 'bn' ? l10n.adminLanguageBangla : l10n.adminLanguageEnglish;
    String? optional(String? v) => (v?.trim().isEmpty ?? true) || isValidContentText(v!) ? null : l10n.errorValidation;
    Widget field(String key, TextEditingController c, String label, {int minLines = 1, bool stem = false}) => Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: TextFormField(
        key: Key(key),
        controller: c,
        minLines: minLines,
        maxLines: 8,
        decoration: InputDecoration(labelText: label),
        validator: stem
            ? (v) => draft.hasContent && !isValidContentText(v ?? '', allowBlanks: draft.allowBlanks)
                  ? l10n.errorValidation
                  : null
            : optional,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.lg),
        Semantics(
          header: true,
          child: Text(l10n.adminTranslationHeading(language), style: theme.textTheme.titleMedium),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          draft.supported ? l10n.adminTranslationHint : l10n.adminTranslationUnsupported,
          style: theme.textTheme.bodySmall,
        ),
        if (draft.supported) ...[
          field('translation-stem', draft.stem, l10n.adminFieldStem, minLines: 2, stem: true),
          if (isCreative) field('translation-stimulus', draft.stimulus, l10n.adminFieldStimulus, minLines: 2),
          if (isShortAnswer) ...[
            field('translation-model-answer', draft.modelAnswer, l10n.adminModelAnswer),
            field('translation-guidance', draft.guidance, l10n.adminMarkingGuidance),
          ],
          field('translation-explanation', draft.explanation, l10n.adminFieldExplanation),
          for (final (i, o) in options.indexed)
            field('translation-option-$i', draft.of(o), '${l10n.adminOptionText} ${o.label.text}'),
          for (final (i, p) in parts.indexed)
            field('translation-part-$i', draft.of(p), '${l10n.adminPartPrompt} ${p.label.text}', minLines: 2),
        ],
      ],
    );
  }
}

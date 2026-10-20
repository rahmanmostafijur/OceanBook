import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ob_core/ob_core.dart';

import 'support/admin_harness.dart';

Future<void> _pick(WidgetTester tester, String key, String label) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String key, String text) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.enterText(find.byKey(Key(key)), text);
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

Future<void> _classify(WidgetTester tester) async {
  await _pick(tester, 'question-level', 'HSC');
  await _pick(tester, 'question-subject', 'Physics 1st Paper');
}

Map<String, Object?> _paragraph(Map<String, Object?> doc) =>
    ((doc['blocks']! as List).single as Map).cast<String, Object?>();

void main() {
  testWidgets('creates a single-choice question and opens it', (tester) async {
    final questions = FakeAdminQuestions();
    await pumpAdmin(tester, restored: staffUser, questions: questions, location: '/questions');
    await tester.tap(find.byKey(const Key('new-question')));
    await tester.pumpAndSettle();

    await _type(tester, 'question-stem', r'আলোর বেগ $c$ কত?');
    await _type(tester, 'option-text-0', 'প্রথম');
    await _type(tester, 'option-text-1', 'দ্বিতীয়');
    await _type(tester, 'option-text-2', 'তৃতীয়');
    await _type(tester, 'option-text-3', 'চতুর্থ');
    await _tap(tester, 'option-correct-2');
    await _classify(tester);
    await _tap(tester, 'question-save');

    expect(questions.calls, contains('create:'));
    final saved = questions.savedContent!;
    expect(saved['type'], 'mcq_single');
    expect(saved['source_locale'], 'bn');
    expect(saved['education_level_id'], 'l1');
    expect(saved['subject_id'], 's1');
    expect(saved['marks'], '1');
    final options = (saved['options']! as List).cast<Map<String, Object?>>();
    expect(options.map((o) => o['label']), ['ক', 'খ', 'গ', 'ঘ']);
    expect(options.map((o) => o['is_correct']), [false, false, true, false]);
    final stem = ((saved['translations']! as Map)['bn']! as Map)['stem']! as Map<String, Object?>;
    expect(_paragraph(stem)['inlines'], [
      {'type': 'text', 'text': 'আলোর বেগ '},
      {'type': 'math', 'tex': 'c', 'display': false},
      {'type': 'text', 'text': ' কত?'},
    ]);
    expect(find.byKey(const Key('edit-question')), findsNothing); // landed on the question page (in review)
    expect(find.text('Multiple choice'), findsOneWidget);
  });

  testWidgets('needs exactly one correct option for single choice and sends nothing otherwise', (tester) async {
    final questions = FakeAdminQuestions();
    await pumpAdmin(tester, restored: staffUser, questions: questions, location: '/questions/new');
    await _type(tester, 'question-stem', 'প্রশ্ন');
    for (var i = 0; i < 4; i++) {
      await _type(tester, 'option-text-$i', 'উত্তর $i');
    }
    await _classify(tester);
    await _tap(tester, 'question-save');
    expect(find.text('Mark exactly one option as correct.'), findsOneWidget);

    await _tap(tester, 'option-correct-0');
    await _tap(tester, 'option-correct-1'); // single choice: moves the mark
    final checked = tester.widgetList<Checkbox>(find.byType(Checkbox)).map((c) => c.value).toList();
    expect(checked, [false, true, false, false]);
    expect(questions.calls.where((c) => c.startsWith('create')), isEmpty);
  });

  testWidgets('multiple choice allows several correct options and can add and remove options', (tester) async {
    await pumpAdmin(tester, restored: staffUser, location: '/questions/new');
    await _pick(tester, 'question-type', 'Multiple answers');
    await _tap(tester, 'option-add');
    expect(find.byKey(const Key('option-text-4')), findsOneWidget);
    await _tap(tester, 'option-correct-0');
    await _tap(tester, 'option-correct-1');
    expect(tester.widgetList<Checkbox>(find.byType(Checkbox)).where((c) => c.value ?? false), hasLength(2));
    await _tap(tester, 'option-remove-4');
    expect(find.byKey(const Key('option-text-4')), findsNothing);
  });

  testWidgets('true/false starts with the two statements and a fixed option count', (tester) async {
    await pumpAdmin(tester, restored: staffUser, location: '/questions/new');
    await _pick(tester, 'question-type', 'True or false');
    expect(find.widgetWithText(TextFormField, 'সত্য'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'মিথ্যা'), findsOneWidget);
    expect(find.byKey(const Key('option-add')), findsNothing);
    expect(find.byKey(const Key('option-remove-0')), findsNothing);
  });

  testWidgets('rejects an unpaired dollar sign in the text', (tester) async {
    final questions = FakeAdminQuestions();
    await pumpAdmin(tester, restored: staffUser, questions: questions, location: '/questions/new');
    await _type(tester, 'question-stem', r'costs $5');
    await _tap(tester, 'question-save');
    expect(find.text('Please check the highlighted fields.'), findsWidgets);
    expect(questions.calls.where((c) => c.startsWith('create')), isEmpty);
  });

  testWidgets('editing changes the Bangla text but keeps other translations and option content', (tester) async {
    final questions = FakeAdminQuestions(question: fakeAdminQuestion(status: 'draft'));
    await pumpAdmin(tester, restored: staffUser, questions: questions, location: '/questions/q1');
    await tester.tap(find.byKey(const Key('edit-question')));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextFormField, 'আলোর বেগ কত?'), findsOneWidget);
    await _type(tester, 'question-stem', 'আলোর বেগ কত মিটার/সেকেন্ড?');
    await _type(tester, 'question-note', 'fix wording');
    await _tap(tester, 'question-save');

    expect(questions.calls, contains('update:q1:fix wording'));
    final saved = questions.savedContent!;
    final translations = saved['translations']! as Map;
    expect(translations.keys, containsAll(['bn', 'en']));
    expect(_paragraph((translations['bn']! as Map)['stem']! as Map<String, Object?>)['inlines'], [
      {'type': 'text', 'text': 'আলোর বেগ কত মিটার/সেকেন্ড?'},
    ]);
    expect((translations['bn']! as Map)['origin'], 'original');
    final first = (saved['options']! as List).first as Map;
    expect((first['content'] as Map).keys, containsAll(['bn', 'en']));
    expect(saved['chapter_id'], 'c1');
    expect(saved['topic_id'], 't1');
    expect(saved['difficulty'], 2);
  });

  testWidgets('content the editor cannot reproduce is not editable', (tester) async {
    final raw = fakeRawContent(
      stem: {
        'type': 'doc',
        'v': 1,
        'blocks': [
          {'type': 'image', 'asset_id': 'a1', 'alt': 'diagram'},
        ],
      },
    );
    final questions = FakeAdminQuestions(
      question: fakeAdminQuestion(status: 'draft', rawContent: raw),
    );
    await pumpAdmin(tester, restored: staffUser, questions: questions, location: '/questions/q1/edit');
    expect(find.textContaining('cannot edit yet'), findsOneWidget);
    expect(find.byKey(const Key('question-save')), findsNothing);
  });

  testWidgets('a server rejection is shown and the form stays', (tester) async {
    final questions = FakeAdminQuestions(question: fakeAdminQuestion(status: 'draft'))
      ..saveError = const ServerFailure(
        status: 403,
        errors: [ApiErrorItem(code: ApiErrorCode.forbidden, message: 'no')],
      );
    await pumpAdmin(tester, restored: staffUser, questions: questions, location: '/questions/q1/edit');
    await _tap(tester, 'question-save');
    expect(find.text("You don't have access to this."), findsOneWidget);
    expect(find.byKey(const Key('question-save')), findsOneWidget);
  });

  testWidgets('only editable states offer Edit', (tester) async {
    await pumpAdmin(
      tester,
      restored: staffUser,
      questions: FakeAdminQuestions(question: fakeAdminQuestion(status: 'in_review')),
      location: '/questions/q1',
    );
    expect(find.byKey(const Key('edit-question')), findsNothing);
  });

  testWidgets('the editor meets accessibility guidelines', (tester) async {
    await pumpAdmin(tester, restored: staffUser, location: '/questions/new');
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
  });
}

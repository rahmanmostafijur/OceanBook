import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
  await tester.pump();
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

String _text(Object? doc) => (((doc! as Map)['blocks']! as List).single as Map)['inlines']! is List
    ? ((((doc as Map)['blocks']! as List).single as Map)['inlines']! as List).map((i) => (i as Map)['text']).join()
    : '';

Future<FakeAdminQuestions> _openCreate(WidgetTester tester) async {
  final questions = FakeAdminQuestions();
  await pumpAdmin(
    tester,
    size: const Size(1440, 2600),
    restored: staffUser,
    questions: questions,
    location: '/questions/new',
  );
  await _pick(tester, 'question-type', 'Creative');
  return questions;
}

void main() {
  testWidgets('a new creative question starts with four parts at 1, 2, 3 and 4 marks', (tester) async {
    await _openCreate(tester);
    for (var i = 0; i < 4; i++) {
      expect(find.byKey(Key('part-prompt-$i')), findsOneWidget);
    }
    expect(find.byKey(const Key('part-prompt-4')), findsNothing);
    expect(find.byKey(const Key('option-add')), findsNothing);
    expect(find.byKey(const Key('question-marks')), findsNothing);
    expect(find.text('Total marks: 10'), findsOneWidget);
  });

  testWidgets('creates the stimulus first, then the question with parts that add up to its marks', (tester) async {
    final questions = await _openCreate(tester);
    await _type(tester, 'question-stem', 'উদ্দীপকটি পড়ো');
    await _type(tester, 'question-stimulus', r'একটি বস্তুর ভর $m$');
    for (var i = 0; i < 4; i++) {
      await _type(tester, 'part-prompt-$i', 'অংশ $i');
    }
    await _type(tester, 'part-marks-3', '5');
    expect(find.text('Total marks: 11'), findsOneWidget);
    await _pick(tester, 'part-level-3', 'Application');
    await _classify(tester);
    await _tap(tester, 'question-save');

    expect(questions.calls, ['stimulus:bn', 'create:']);
    expect(questions.createdStimulus!.keys, ['bn']);
    final saved = questions.savedContent!;
    expect(saved['type'], 'creative');
    expect(saved['stimulus_id'], 's-new');
    expect(saved['marks'], '11.00');
    expect(saved['options'], isEmpty);
    final parts = (saved['parts']! as List).cast<Map<String, Object?>>();
    expect(parts.map((p) => p['label']), ['ক', 'খ', 'গ', 'ঘ']);
    expect(parts.map((p) => p['marks']), ['1', '2', '3', '5']);
    expect(parts.map((p) => p['cognitive_level']), ['knowledge', 'comprehension', 'application', 'application']);
    expect(_text(((parts.first['prompt']! as Map)['bn'])), 'অংশ 0');
  });

  testWidgets('needs a stimulus and every part filled in before anything is sent', (tester) async {
    final questions = await _openCreate(tester);
    await _type(tester, 'question-stem', 'উদ্দীপকটি পড়ো');
    await _classify(tester);
    await _tap(tester, 'question-save');
    expect(find.text('Please check the highlighted fields.'), findsWidgets);
    expect(questions.calls, isEmpty);
  });

  testWidgets('parts can be added up to six and removed down to one', (tester) async {
    await _openCreate(tester);
    await _tap(tester, 'part-add');
    await _tap(tester, 'part-add');
    expect(find.byKey(const Key('part-prompt-5')), findsOneWidget);
    expect(find.byKey(const Key('part-add')), findsNothing);
    for (var i = 5; i >= 1; i--) {
      await _tap(tester, 'part-remove-$i');
    }
    expect(find.byKey(const Key('part-prompt-1')), findsNothing);
    expect(tester.widget<IconButton>(find.byKey(const Key('part-remove-0'))).onPressed, isNull);
    expect(find.text('Total marks: 1'), findsOneWidget);
  });

  testWidgets('editing an unchanged passage keeps it and keeps what the editor does not show', (tester) async {
    final questions = FakeAdminQuestions(question: fakeCreativeQuestion())..stimuli['s1'] = fakeStimulus();
    await pumpAdmin(
      tester,
      size: const Size(1440, 2600),
      restored: staffUser,
      questions: questions,
      location: '/questions/q1/edit',
    );
    expect(find.widgetWithText(TextFormField, 'একটি উদ্দীপক'), findsOneWidget);
    await _type(tester, 'part-prompt-1', 'দ্বিতীয় অংশ, সংশোধিত');
    await _tap(tester, 'question-save');

    expect(questions.calls, ['update:q1:']);
    final saved = questions.savedContent!;
    expect(saved['stimulus_id'], 's1');
    expect(saved['marks'], '3.00');
    final parts = (saved['parts']! as List).cast<Map<String, Object?>>();
    expect((parts.first['prompt']! as Map).keys, containsAll(['bn', 'en']));
    expect(parts.first['model_answer'], isNotNull);
    expect(_text((parts.last['prompt']! as Map)['bn']), 'দ্বিতীয় অংশ, সংশোধিত');
  });

  testWidgets('a changed passage becomes a new stimulus that keeps the other translations', (tester) async {
    final questions = FakeAdminQuestions(question: fakeCreativeQuestion())..stimuli['s1'] = fakeStimulus();
    await pumpAdmin(
      tester,
      size: const Size(1440, 2600),
      restored: staffUser,
      questions: questions,
      location: '/questions/q1/edit',
    );
    await _type(tester, 'question-stimulus', 'নতুন উদ্দীপক');
    await _tap(tester, 'question-save');

    expect(questions.calls, ['stimulus:bn', 'update:q1:']);
    expect(questions.createdStimulus!.keys, containsAll(['bn', 'en']));
    expect(_text(questions.createdStimulus!['bn']), 'নতুন উদ্দীপক');
    expect(questions.savedContent!['stimulus_id'], 's-new');
  });

  testWidgets('a passage with formatting the editor cannot reproduce keeps the question read-only', (tester) async {
    final questions = FakeAdminQuestions(question: fakeCreativeQuestion())..stimuli['s1'] = fakeStimulusWithImage();
    await pumpAdmin(
      tester,
      size: const Size(1440, 2600),
      restored: staffUser,
      questions: questions,
      location: '/questions/q1/edit',
    );
    expect(find.textContaining('cannot edit yet'), findsOneWidget);
    expect(find.byKey(const Key('question-save')), findsNothing);
  });

  testWidgets('the creative editor meets accessibility guidelines', (tester) async {
    await _openCreate(tester);
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
  });
}

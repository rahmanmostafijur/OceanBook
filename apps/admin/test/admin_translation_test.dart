import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/admin_harness.dart';

const _tall = Size(1440, 3000);

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

Future<FakeAdminQuestions> _fillNewQuestion(WidgetTester tester) async {
  final questions = FakeAdminQuestions();
  await pumpAdmin(tester, size: _tall, restored: staffUser, questions: questions, location: '/questions/new');
  await _type(tester, 'question-stem', 'বাংলা প্রশ্ন');
  for (var i = 0; i < 4; i++) {
    await _type(tester, 'option-text-$i', 'উত্তর $i');
  }
  await _tap(tester, 'option-correct-1');
  await _pick(tester, 'question-level', 'HSC');
  await _pick(tester, 'question-subject', 'Physics 1st Paper');
  return questions;
}

Map<String, Object?> _translations(FakeAdminQuestions q) =>
    (q.savedContent!['translations']! as Map).cast<String, Object?>();

String _text(Object? doc) =>
    ((((doc! as Map)['blocks']! as List).single as Map)['inlines']! as List).map((i) => (i as Map)['text']).join();

void main() {
  testWidgets('a new question can carry an English translation of its text, options and explanation', (tester) async {
    final questions = await _fillNewQuestion(tester);
    await _type(tester, 'translation-stem', 'English question');
    await _type(tester, 'translation-explanation', 'Because.');
    await _type(tester, 'translation-option-1', 'Second');
    await _tap(tester, 'question-save');

    final en = (_translations(questions)['en']! as Map).cast<String, Object?>();
    expect(_text(en['stem']), 'English question');
    expect(_text(en['explanation']), 'Because.');
    expect(en['origin'], 'human_translation');
    final options = (questions.savedContent!['options']! as List).cast<Map<String, Object?>>();
    expect((options[1]['content']! as Map).keys, containsAll(['bn', 'en']));
    expect(_text((options[1]['content']! as Map)['en']), 'Second');
    expect((options[0]['content']! as Map).keys, ['bn']); // an option left empty has no translation
  });

  testWidgets('leaving the translation empty saves no translation', (tester) async {
    final questions = await _fillNewQuestion(tester);
    await _tap(tester, 'question-save');
    expect(_translations(questions).keys, ['bn']);
  });

  testWidgets('a translation needs its question text', (tester) async {
    final questions = await _fillNewQuestion(tester);
    await _type(tester, 'translation-option-0', 'First');
    await _tap(tester, 'question-save');
    expect(questions.calls, isEmpty);
  });

  testWidgets('an English question is translated into Bangla', (tester) async {
    final questions = FakeAdminQuestions();
    await pumpAdmin(tester, size: _tall, restored: staffUser, questions: questions, location: '/questions/new');
    await _pick(tester, 'question-language', 'English');
    expect(find.text('Translation (Bangla)'), findsOneWidget);
  });

  testWidgets('editing shows the saved translation and emptying it removes it', (tester) async {
    final questions = FakeAdminQuestions(question: fakeAdminQuestion(status: 'draft'));
    await pumpAdmin(tester, size: _tall, restored: staffUser, questions: questions, location: '/questions/q1/edit');
    expect(find.widgetWithText(TextFormField, 'What is the speed of light?'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'First answer'), findsOneWidget);

    await _type(tester, 'translation-stem', '');
    await _type(tester, 'translation-option-0', '');
    await _tap(tester, 'question-save');

    expect(_translations(questions).keys, ['bn']);
    final first = (questions.savedContent!['options']! as List).first as Map;
    expect((first['content']! as Map).keys, ['bn']);
  });

  testWidgets('a translation with formatting the editor cannot edit is shown as such and kept', (tester) async {
    final raw = fakeRawContent();
    final translations = (raw['translations']! as Map).cast<String, Object?>();
    translations['en'] = {
      'stem': {
        'type': 'doc',
        'v': 1,
        'blocks': [
          {'type': 'image', 'asset_id': 'a1', 'alt': 'diagram'},
        ],
      },
      'origin': 'human_translation',
    };
    final questions = FakeAdminQuestions(
      question: fakeAdminQuestion(status: 'draft', rawContent: raw),
    );
    await pumpAdmin(tester, size: _tall, restored: staffUser, questions: questions, location: '/questions/q1/edit');
    expect(find.textContaining('formatting the editor cannot edit yet'), findsOneWidget);
    expect(find.byKey(const Key('translation-stem')), findsNothing);

    await _tap(tester, 'question-save');
    final en = (_translations(questions)['en']! as Map).cast<String, Object?>();
    expect(((en['stem']! as Map)['blocks']! as List).single, containsPair('type', 'image'));
  });

  testWidgets('a creative question can translate its passage and parts', (tester) async {
    final questions = FakeAdminQuestions(question: fakeCreativeQuestion())..stimuli['s1'] = fakeStimulus();
    await pumpAdmin(tester, size: _tall, restored: staffUser, questions: questions, location: '/questions/q1/edit');
    expect(find.widgetWithText(TextFormField, 'A passage'), findsOneWidget);
    await _type(tester, 'translation-stimulus', 'A new passage');
    await _type(tester, 'translation-part-1', 'Second part');
    await _tap(tester, 'question-save');

    expect(questions.calls, ['stimulus:bn', 'update:q1:']);
    expect(_text(questions.createdStimulus!['en']), 'A new passage');
    expect(questions.createdStimulus!.keys, containsAll(['bn', 'en']));
    final parts = (questions.savedContent!['parts']! as List).cast<Map<String, Object?>>();
    expect(_text((parts.last['prompt']! as Map)['en']), 'Second part');
    expect(_text((parts.first['prompt']! as Map)['en']), 'First part'); // kept
  });

  testWidgets('a creative question whose passage is unchanged keeps its stimulus', (tester) async {
    final questions = FakeAdminQuestions(question: fakeCreativeQuestion())..stimuli['s1'] = fakeStimulus();
    await pumpAdmin(tester, size: _tall, restored: staffUser, questions: questions, location: '/questions/q1/edit');
    await _tap(tester, 'question-save');
    expect(questions.calls, ['update:q1:']);
    expect(questions.savedContent!['stimulus_id'], 's1');
  });

  testWidgets('a short answer question translates its model answer', (tester) async {
    final questions = FakeAdminQuestions();
    await pumpAdmin(tester, size: _tall, restored: staffUser, questions: questions, location: '/questions/new');
    await _pick(tester, 'question-type', 'Short answer');
    await _type(tester, 'question-stem', 'বাংলা');
    await _type(tester, 'question-model-answer', 'উত্তর');
    await _type(tester, 'translation-stem', 'English');
    await _type(tester, 'translation-model-answer', 'Answer');
    await _pick(tester, 'question-level', 'HSC');
    await _pick(tester, 'question-subject', 'Physics 1st Paper');
    await _tap(tester, 'question-save');
    final en = (_translations(questions)['en']! as Map).cast<String, Object?>();
    expect(_text(en['model_answer']), 'Answer');
  });

  testWidgets('the translation fields meet accessibility guidelines', (tester) async {
    await pumpAdmin(tester, size: _tall, restored: staffUser, location: '/questions/new');
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
  });
}

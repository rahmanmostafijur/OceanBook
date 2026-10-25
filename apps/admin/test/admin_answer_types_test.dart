import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ob_core/ob_core.dart';

import 'support/admin_harness.dart';

const _tall = Size(1440, 2400);

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

Future<FakeAdminQuestions> _openCreate(WidgetTester tester, String typeLabel) async {
  final questions = FakeAdminQuestions();
  await pumpAdmin(tester, size: _tall, restored: staffUser, questions: questions, location: '/questions/new');
  await _pick(tester, 'question-type', typeLabel);
  return questions;
}

Future<void> _classify(WidgetTester tester) async {
  await _pick(tester, 'question-level', 'HSC');
  await _pick(tester, 'question-subject', 'Physics 1st Paper');
}

Map<String, Object?> _bnTranslation(Map<String, Object?> saved) =>
    ((saved['translations']! as Map)['bn']! as Map).cast<String, Object?>();

List<Object?> _inlines(Object? doc) =>
    ((((doc! as Map)['blocks']! as List).single as Map)['inlines']!) as List<Object?>;

void main() {
  group('short answer', () {
    testWidgets('needs a model answer and sends it with the optional marking guidance', (tester) async {
      final questions = await _openCreate(tester, 'Short answer');
      expect(find.byKey(const Key('option-add')), findsNothing);
      await _type(tester, 'question-stem', 'Define velocity.');
      await _classify(tester);
      await _tap(tester, 'question-save');
      expect(questions.calls, isEmpty); // model answer missing

      await _type(tester, 'question-model-answer', 'Rate of change of displacement.');
      await _type(tester, 'question-guidance', 'One mark for direction.');
      await _tap(tester, 'question-save');

      final saved = questions.savedContent!;
      expect(saved['type'], 'short_answer');
      expect(saved['options'], isEmpty);
      expect(saved.containsKey('answer_spec'), isFalse);
      final t = _bnTranslation(saved);
      expect(_inlines(t['model_answer']), [
        {'type': 'text', 'text': 'Rate of change of displacement.'},
      ]);
      expect(t.containsKey('marking_guidance'), isTrue);
    });

    testWidgets('an empty marking guidance is left out', (tester) async {
      final questions = await _openCreate(tester, 'Short answer');
      await _type(tester, 'question-stem', 'Define velocity.');
      await _type(tester, 'question-model-answer', 'Answer');
      await _classify(tester);
      await _tap(tester, 'question-save');
      expect(_bnTranslation(questions.savedContent!).containsKey('marking_guidance'), isFalse);
    });
  });

  group('fill in the blank', () {
    testWidgets('one answer field per gap marker, saved as blank inlines and an answer spec', (tester) async {
      final questions = await _openCreate(tester, 'Fill in the blank');
      await _type(tester, 'question-stem', 'Water boils at [[1]] degrees and freezes at [[2]].');
      expect(find.byKey(const Key('blank-answers-1')), findsOneWidget);
      expect(find.byKey(const Key('blank-answers-2')), findsNothing);
      await _type(tester, 'blank-answers-0', '100\none hundred');
      await _type(tester, 'blank-answers-1', '0');
      await _classify(tester);
      await _tap(tester, 'question-save');

      final saved = questions.savedContent!;
      expect(saved['type'], 'fill_blank');
      expect(saved['answer_spec'], {
        'blanks': [
          {
            'accepted': ['100', 'one hundred'],
          },
          {
            'accepted': ['0'],
          },
        ],
      });
      expect(_inlines(_bnTranslation(saved)['stem']), [
        {'type': 'text', 'text': 'Water boils at '},
        {'type': 'blank', 'index': 0},
        {'type': 'text', 'text': ' degrees and freezes at '},
        {'type': 'blank', 'index': 1},
        {'type': 'text', 'text': '.'},
      ]);
    });

    testWidgets('skipped gap numbers and a missing answer block saving', (tester) async {
      final questions = await _openCreate(tester, 'Fill in the blank');
      await _type(tester, 'question-stem', 'Only [[2]] is marked');
      await _classify(tester);
      await _tap(tester, 'question-save');
      expect(find.textContaining('without skipping a number'), findsOneWidget);
      expect(questions.calls, isEmpty);

      await _type(tester, 'question-stem', 'Now [[1]] is marked');
      await _tap(tester, 'question-save');
      expect(questions.calls, isEmpty); // the gap has no accepted answer yet
      await _type(tester, 'blank-answers-0', 'x');
      await _tap(tester, 'question-save');
      expect(questions.calls, contains('create:'));
    });

    testWidgets('editing keeps the other keys the server stored on a blank', (tester) async {
      final questions = FakeAdminQuestions(question: fakeFillBlankQuestion());
      await pumpAdmin(tester, size: _tall, restored: staffUser, questions: questions, location: '/questions/q1/edit');
      expect(find.widgetWithText(TextFormField, 'Water boils at [[1]] degrees.'), findsOneWidget);
      await _type(tester, 'blank-answers-0', '100\nboiling point');
      await _tap(tester, 'question-save');

      final blank = ((questions.savedContent!['answer_spec']! as Map)['blanks']! as List).single as Map;
      expect(blank['accepted'], ['100', 'boiling point']);
      expect(blank['case_sensitive'], false);
    });
  });

  group('matching', () {
    Future<void> fillItems(WidgetTester tester) async {
      await _type(tester, 'match-right-0', 'Newton');
      await _type(tester, 'match-right-1', 'Joule');
      await _type(tester, 'match-left-0', 'Unit of force');
      await _type(tester, 'match-left-1', 'Unit of energy');
    }

    testWidgets('pairs every left item with a right item and sends the spec', (tester) async {
      final questions = await _openCreate(tester, 'Matching');
      expect(find.byKey(const Key('option-add')), findsNothing);
      await _type(tester, 'question-stem', 'Match the units.');
      await fillItems(tester);
      await _pick(tester, 'match-target-0', '1. Newton');
      await _pick(tester, 'match-target-1', '2. Joule');
      await _classify(tester);
      await _tap(tester, 'question-save');

      final saved = questions.savedContent!;
      expect(saved['type'], 'matching');
      expect(saved['answer_spec'], {
        'left': ['Unit of force', 'Unit of energy'],
        'right': ['Newton', 'Joule'],
        'pairs': [
          [0, 0],
          [1, 1],
        ],
      });
    });

    testWidgets('a left item without a match blocks saving', (tester) async {
      final questions = await _openCreate(tester, 'Matching');
      await _type(tester, 'question-stem', 'Match the units.');
      await fillItems(tester);
      await _pick(tester, 'match-target-0', '1. Newton');
      await _classify(tester);
      await _tap(tester, 'question-save');
      expect(questions.calls, isEmpty);
    });

    testWidgets('removing a right item clears the pairs that pointed at it', (tester) async {
      await _openCreate(tester, 'Matching');
      await _tap(tester, 'match-right-add');
      await _type(tester, 'match-right-0', 'A');
      await _type(tester, 'match-right-1', 'B');
      await _type(tester, 'match-right-2', 'C');
      await _pick(tester, 'match-target-0', '2. B');
      await _pick(tester, 'match-target-1', '3. C');
      await _tap(tester, 'match-right-remove-1');
      expect(find.byKey(const Key('match-right-2')), findsNothing);
      // item 0 lost its match (B was removed); item 1 now points at the renumbered C
      expect(find.text('2. C'), findsOneWidget);
      expect(find.text('2. B'), findsNothing);
    });

    testWidgets('items can be added up to twelve per column', (tester) async {
      await _openCreate(tester, 'Matching');
      for (var i = 0; i < 10; i++) {
        await _tap(tester, 'match-left-add');
      }
      expect(find.byKey(const Key('match-left-add')), findsNothing);
      expect(find.byKey(const Key('match-left-11')), findsOneWidget);
    });
  });

  testWidgets('the new type forms meet accessibility guidelines', (tester) async {
    for (final type in ['Short answer', 'Fill in the blank', 'Matching']) {
      await _openCreate(tester, type);
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
    }
  });

  testWidgets('a question whose answer spec the editor cannot reproduce is read-only', (tester) async {
    final odd = fakeTypedQuestion(QuestionType.matching, {
      'answer_spec': {
        'left': ['a', 'b'],
        'right': ['x', 'y'],
        'pairs': [
          [0, 0],
        ],
      },
    });
    await pumpAdmin(
      tester,
      restored: staffUser,
      questions: FakeAdminQuestions(question: odd),
      location: '/questions/q1/edit',
    );
    expect(find.textContaining('cannot edit yet'), findsOneWidget);
  });

  group('rich text', () {
    testWidgets('formatting, lists, tables and display maths are sent as document blocks', (tester) async {
      final questions = await _openCreate(tester, 'Short answer');
      await _type(tester, 'question-stem', 'Name the **two** units:\n\n- joule\n- newton\n\n\$\$E=mc^2\$\$');
      await _type(tester, 'question-model-answer', '| a | b |\n| c | d |');
      await _classify(tester);
      await _tap(tester, 'question-save');

      final t = _bnTranslation(questions.savedContent!);
      final blocks = ((t['stem']! as Map)['blocks']! as List).cast<Map<String, Object?>>();
      expect(blocks.map((b) => b['type']), ['paragraph', 'list', 'paragraph']);
      expect((blocks.first['inlines'] as List)[1], {'type': 'text', 'text': 'two', 'bold': true});
      expect((blocks.last['inlines'] as List).single, {'type': 'math', 'tex': 'E=mc^2', 'display': true});
      expect((((t['model_answer']! as Map)['blocks']! as List).single as Map)['type'], 'table');
    });

    testWidgets('a question with a list in its text can be edited', (tester) async {
      final stem = {
        'type': 'doc',
        'v': 1,
        'blocks': [
          {
            'type': 'list',
            'style': 'bullet',
            'items': [
              [
                {'type': 'text', 'text': 'first', 'italic': true},
              ],
            ],
          },
        ],
      };
      final question = fakeTypedQuestion(QuestionType.mcqSingle, {
        'translations': {
          'bn': {'stem': stem, 'origin': 'original'},
        },
        'options': [
          {
            'label': 'A',
            'is_correct': true,
            'content': {'bn': stem},
          },
        ],
      });
      await pumpAdmin(
        tester,
        size: _tall,
        restored: staffUser,
        questions: FakeAdminQuestions(question: question),
        location: '/questions/q1/edit',
      );
      expect(find.widgetWithText(TextFormField, '- *first*'), findsWidgets);
    });
  });
}

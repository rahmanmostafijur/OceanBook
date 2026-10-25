import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ob_core/ob_core.dart';
import 'package:oceanbook_admin/features/questionbank/admin_question_api.dart';

import 'support/admin_harness.dart';

const _tall = Size(1440, 2200);

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

AdminQuestionRow _row(String id, String stem) => AdminQuestionRow(
  id: id,
  type: QuestionType.mcqSingle,
  status: 'published',
  version: 1,
  marks: 1,
  accessLevel: 'free',
  stem: stem,
  updatedAt: DateTime.utc(2026, 10),
);

void main() {
  testWidgets('creates a paper with boards and lands on its page', (tester) async {
    final questions = FakeAdminQuestions();
    await pumpAdmin(tester, size: _tall, restored: staffUser, questions: questions, location: '/question-papers');
    await tester.tap(find.byKey(const Key('new-paper')));
    await tester.pumpAndSettle();

    await _pick(tester, 'paper-level', 'HSC');
    await _pick(tester, 'paper-subject', 'Physics 1st Paper');
    await _type(tester, 'paper-year', '2022');
    await _pick(tester, 'paper-section', 'MCQ');
    await _type(tester, 'paper-marks', '30');
    await _tap(tester, 'paper-board-dhaka');
    await _tap(tester, 'paper-board-rajshahi');
    await _tap(tester, 'paper-board-rajshahi'); // toggled off again
    await _tap(tester, 'paper-save');

    expect(questions.calls, contains('paper-create'));
    final body = questions.savedPaper!;
    expect(body['education_level_id'], 'l1');
    expect(body['subject_id'], 's1');
    expect(body['exam_year'], 2022);
    expect(body['exam_kind'], 'board_final');
    expect(body['section'], 'mcq');
    expect(body['total_marks'], '30');
    expect(body['title'], isNull);
    expect(body['duration_minutes'], isNull);
    expect(body['board_ids'], ['b1']);
    expect(body['access_level'], 'free');
    expect(find.byKey(const Key('paper-publish')), findsOneWidget); // landed on the paper's page
  });

  testWidgets('needs a level, a subject and a valid year before anything is sent', (tester) async {
    final questions = FakeAdminQuestions();
    await pumpAdmin(tester, size: _tall, restored: staffUser, questions: questions, location: '/question-papers/new');
    await _type(tester, 'paper-year', '1800');
    await _tap(tester, 'paper-save');
    expect(find.text('Please check the highlighted fields.'), findsWidgets);
    expect(questions.calls, isEmpty);
  });

  testWidgets('a server rejection is shown and the form stays', (tester) async {
    final questions = FakeAdminQuestions()
      ..paperError = const ServerFailure(
        status: 409,
        errors: [ApiErrorItem(code: ApiErrorCode.conflict, message: 'exists')],
      );
    await pumpAdmin(tester, size: _tall, restored: staffUser, questions: questions, location: '/question-papers/new');
    await _pick(tester, 'paper-level', 'HSC');
    await _pick(tester, 'paper-subject', 'Physics 1st Paper');
    await _type(tester, 'paper-year', '2022');
    await _tap(tester, 'paper-save');
    expect(find.byKey(const Key('paper-save')), findsOneWidget);
    expect(find.byKey(const Key('paper-year')), findsOneWidget);
  });

  testWidgets('editing a draft sends the editable fields and never the level or subject', (tester) async {
    final questions = FakeAdminQuestions();
    await pumpAdmin(
      tester,
      size: _tall,
      restored: staffUser,
      questions: questions,
      location: '/question-papers/p1/edit',
    );
    expect(find.byKey(const Key('paper-level')), findsNothing);
    expect(find.widgetWithText(TextFormField, '2022'), findsOneWidget);
    await _type(tester, 'paper-year', '2023');
    await _tap(tester, 'paper-save');

    expect(questions.calls, contains('paper-update:p1'));
    final patch = questions.savedPaper!;
    expect(patch['exam_year'], 2023);
    expect(patch['board_ids'], ['b1']);
    expect(patch.containsKey('subject_id'), isFalse);
    expect(patch.containsKey('education_level_id'), isFalse);
  });

  testWidgets('a paper that is not a draft cannot be edited', (tester) async {
    final questions = FakeAdminQuestions()..currentPaper = fakePaper(status: 'published');
    await pumpAdmin(
      tester,
      size: _tall,
      restored: staffUser,
      questions: questions,
      location: '/question-papers/p1/edit',
    );
    expect(find.text('Only draft papers can be edited.'), findsOneWidget);
    expect(find.byKey(const Key('paper-save')), findsNothing);
  });

  testWidgets('the paper page lists its questions with their text and offers the draft actions', (tester) async {
    final questions = FakeAdminQuestions()..questionRows = [_row('q1', 'আলোর বেগ কত?')];
    await pumpAdmin(tester, restored: staffUser, questions: questions, location: '/question-papers/p1');
    expect(find.text('আলোর বেগ কত?'), findsOneWidget);
    for (final key in ['paper-publish', 'paper-edit', 'paper-choose', 'paper-archive']) {
      expect(find.byKey(Key(key)), findsOneWidget, reason: key);
    }
  });

  testWidgets('a published paper can only be archived', (tester) async {
    final questions = FakeAdminQuestions()..currentPaper = fakePaper(status: 'published');
    await pumpAdmin(tester, restored: staffUser, questions: questions, location: '/question-papers/p1');
    expect(find.byKey(const Key('paper-archive')), findsOneWidget);
    for (final key in ['paper-publish', 'paper-edit', 'paper-choose']) {
      expect(find.byKey(Key(key)), findsNothing, reason: key);
    }
  });

  testWidgets('publish failures list the gate reasons', (tester) async {
    final questions = FakeAdminQuestions()
      ..paperError = const ServerFailure(
        status: 409,
        errors: [
          ApiErrorItem(
            code: ApiErrorCode.contentNotPublishable,
            message: 'blocked',
            details: {
              'reasons': ['NO_ITEMS', 'NO_PROVENANCE'],
            },
          ),
        ],
      );
    await pumpAdmin(tester, restored: staffUser, questions: questions, location: '/question-papers/p1');
    await _tap(tester, 'paper-publish');
    expect(find.byKey(const Key('paper-error')), findsOneWidget);
    expect(find.textContaining('•'), findsNWidgets(2));
  });

  testWidgets('publishing and archiving (with a reason) call the server', (tester) async {
    final questions = FakeAdminQuestions();
    await pumpAdmin(tester, restored: staffUser, questions: questions, location: '/question-papers/p1');
    await _tap(tester, 'paper-publish');
    await _tap(tester, 'paper-archive');
    await tester.enterText(find.byKey(const Key('comment-field')), 'superseded');
    await _tap(tester, 'comment-confirm');
    expect(questions.calls, containsAll(['paper-publish:p1', 'paper-archive:p1:superseded']));
  });

  testWidgets('choosing questions keeps numbers of those kept and numbers new ones after them', (tester) async {
    final questions = FakeAdminQuestions()
      ..currentPaper = fakePaper(
        items: const [AdminPaperItem(questionId: 'q1', itemNumber: '5', marks: 2)],
      )
      ..questionRows = [_row('q1', 'প্রথম'), _row('q2', 'দ্বিতীয়'), _row('q3', 'তৃতীয়')];
    await pumpAdmin(tester, restored: staffUser, questions: questions, location: '/question-papers/p1');
    await _tap(tester, 'paper-choose');
    expect(tester.widget<CheckboxListTile>(find.byKey(const Key('pick-q1'))).value, isTrue);
    await tester.tap(find.byKey(const Key('pick-q3')));
    await tester.tap(find.byKey(const Key('pick-q2')));
    await _tap(tester, 'pick-confirm');

    expect(questions.calls, contains('paper-items:p1'));
    final items = questions.savedItems!;
    expect(items.map((i) => (i.questionId, i.itemNumber)), [('q1', '5'), ('q2', '6'), ('q3', '7')]);
    expect(items.first.marks, 2);
  });

  testWidgets('removing every question sends an empty list', (tester) async {
    final questions = FakeAdminQuestions()..questionRows = [_row('q1', 'প্রথম')];
    await pumpAdmin(tester, restored: staffUser, questions: questions, location: '/question-papers/p1');
    await _tap(tester, 'paper-choose');
    await tester.tap(find.byKey(const Key('pick-q1')));
    await _tap(tester, 'pick-confirm');
    expect(questions.savedItems, isEmpty);
  });

  testWidgets('the paper pages meet accessibility guidelines', (tester) async {
    await pumpAdmin(tester, size: _tall, restored: staffUser, location: '/question-papers/new');
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    await pumpAdmin(tester, restored: staffUser, location: '/question-papers/p1');
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
  });
}

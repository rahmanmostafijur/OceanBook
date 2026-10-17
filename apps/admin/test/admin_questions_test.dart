import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ob_core/ob_core.dart';
import 'package:oceanbook_admin/features/questionbank/admin_question_api.dart';
import 'package:oceanbook_admin/features/questionbank/question_detail_page.dart';

import 'support/admin_harness.dart';

ServerFailure _notPublishable(List<String> reasons) => ServerFailure(
  status: 409,
  errors: [
    ApiErrorItem(
      code: ApiErrorCode.contentNotPublishable,
      message: 'blocked',
      details: {'reasons': reasons},
    ),
  ],
);

void main() {
  group('workflow actions follow the question state (the server re-checks each one)', () {
    List<QuestionAction> actions(String status, {String? pending}) =>
        questionActionsFor(fakeAdminQuestion(status: status, pendingStatus: pending, version: pending == null ? 0 : 1));

    test('draft and changes requested can be submitted', () {
      expect(actions('draft'), [QuestionAction.submit, QuestionAction.archive]);
      expect(actions('changes_requested').first, QuestionAction.submit);
    });

    test('in review offers the three reviewer decisions', () {
      expect(actions('in_review'), [QuestionAction.approve, QuestionAction.requestChanges, QuestionAction.reject]);
    });

    test('approved offers publish', () => expect(actions('approved').first, QuestionAction.publish));

    test('an edit of a published question follows the edit, not the live status', () {
      expect(actions('published', pending: 'in_review').first, QuestionAction.approve);
      expect(actions('published', pending: 'draft'), [QuestionAction.submit]); // cannot archive from an edit
      expect(actions('published'), [QuestionAction.archive]);
    });

    test('archived can be restored', () => expect(actions('archived'), [QuestionAction.restore]));

    test('only comment-bearing actions ask for one', () {
      expect(
        [
          for (final a in QuestionAction.values)
            if (a.needsComment) a,
        ],
        [
          QuestionAction.requestChanges,
          QuestionAction.reject,
          QuestionAction.archive,
        ],
      );
    });
  });

  testWidgets('the questions table filters on the server and opens a question', (tester) async {
    final questions = FakeAdminQuestions();
    await pumpAdmin(tester, restored: staffUser, questions: questions, location: '/questions');
    expect(find.byType(DataTable), findsOneWidget);
    expect(find.text('আলোর বেগ কত?'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'In review'), findsOneWidget);

    await tester.tap(find.byKey(const Key('questions-needs-review')));
    await tester.pumpAndSettle();
    expect(questions.calls.last, 'questions:::true:1');

    await tester.tap(find.text('আলোর বেগ কত?'));
    await tester.pumpAndSettle();
    expect(find.byType(QuestionDetailPage), findsOneWidget);
    expect(find.text('প্রথম উত্তর'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget); // the correct option is marked
  });

  testWidgets('review decisions are sent; rejecting asks for a comment first', (tester) async {
    final questions = FakeAdminQuestions();
    await pumpAdmin(tester, restored: staffUser, questions: questions, location: '/questions/q1');
    await tester.tap(find.byKey(const Key('action-approve')));
    await tester.pumpAndSettle();
    expect(questions.calls.last, 'approve::false');

    await tester.tap(find.byKey(const Key('action-reject')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('comment-confirm'))); // too short: nothing is sent yet
    await tester.pumpAndSettle();
    expect(questions.calls.last, 'approve::false');
    await tester.enterText(find.byKey(const Key('comment-field')), 'বিষয়ের বাইরে');
    await tester.tap(find.byKey(const Key('comment-confirm')));
    await tester.pumpAndSettle();
    expect(questions.calls.last, 'reject:বিষয়ের বাইরে:false');
  });

  testWidgets('a blocked publish shows the reasons, and a duplicate can be acknowledged', (tester) async {
    final questions = FakeAdminQuestions(question: fakeAdminQuestion(status: 'approved'))
      ..actionError = _notPublishable(['NO_INDEPENDENT_APPROVAL', 'DUPLICATE_QUESTION']);
    await pumpAdmin(tester, restored: staffUser, questions: questions, location: '/questions/q1');
    await tester.tap(find.byKey(const Key('action-publish')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('action-error')), findsOneWidget);
    expect(find.text('• Needs approval from someone who did not edit it'), findsOneWidget);
    expect(find.text('• Looks like a duplicate of an existing question'), findsOneWidget);

    questions.actionError = null;
    await tester.tap(find.byKey(const Key('action-publish-duplicate')));
    await tester.pumpAndSettle();
    expect(questions.calls.last, 'publish::true');
  });

  testWidgets('completeness issues from the server are listed before submitting', (tester) async {
    final questions = FakeAdminQuestions(
      question: fakeAdminQuestion(status: 'draft', issues: const ['OPTION_COUNT_INVALID']),
    );
    await pumpAdmin(tester, restored: staffUser, questions: questions, location: '/questions/q1');
    expect(find.text('To fix before it can be submitted'), findsOneWidget);
    expect(find.text('OPTION_COUNT_INVALID'), findsOneWidget);
  });

  testWidgets('a pending edit of a live question says the published version stays live', (tester) async {
    final questions = FakeAdminQuestions(
      question: fakeAdminQuestion(status: 'published', pendingStatus: 'in_review', version: 1),
    );
    await pumpAdmin(tester, restored: staffUser, questions: questions, location: '/questions/q1');
    expect(find.text('An edit is in progress; the published version stays live.'), findsOneWidget);
    expect(find.text('Version 1'), findsNothing); // the line carries version, marks and level together
    expect(find.textContaining('Version 1'), findsOneWidget);
  });

  testWidgets('papers and subjects pages render the server data', (tester) async {
    final questions = FakeAdminQuestions();
    await pumpAdmin(tester, restored: staffUser, questions: questions, location: '/question-papers');
    expect(find.text('2022'), findsOneWidget);
    expect(find.text('Board exam'), findsOneWidget);
    expect(find.text('30'), findsOneWidget);

    await pumpAdmin(tester, restored: staffUser, questions: questions, location: '/subjects');
    expect(find.text('Physics 1st Paper'), findsOneWidget);
    await tester.tap(find.text('Physics 1st Paper'));
    await tester.pumpAndSettle();
    expect(find.text('1. Physical world'), findsOneWidget);
    expect(find.text('Measurement'), findsOneWidget);
  });

  testWidgets('question pages meet accessibility guidelines', (tester) async {
    await pumpAdmin(tester, restored: staffUser, location: '/questions');
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    await pumpAdmin(tester, restored: staffUser, location: '/questions/q1');
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
  });
}

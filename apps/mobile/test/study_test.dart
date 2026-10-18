import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ob_core/ob_core.dart';

import 'support/harness.dart';

/// Taps a filter chip, scrolling the horizontal chip row first (the chips outgrow a phone's width).
Future<void> _tapChip(WidgetTester tester, String label) async {
  final chip = find.widgetWithText(FilterChip, label);
  final row = find.descendant(
    of: find.byWidgetPredicate((w) => w is ListView && w.scrollDirection == Axis.horizontal),
    matching: find.byType(Scrollable),
  );
  await tester.scrollUntilVisible(chip, 120, scrollable: row);
  await tester.pumpAndSettle();
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

/// Taps an option in the open choice sheet, scrolling the sheet's list to it first (long lists build lazily).
Future<void> _tapText(WidgetTester tester, String text) async {
  final option = find.descendant(of: find.byType(ListTile), matching: find.text(text));
  final sheet = find.descendant(of: find.byType(DraggableScrollableSheet), matching: find.byType(Scrollable));
  await tester.scrollUntilVisible(option, 60, scrollable: sheet);
  await tester.pumpAndSettle();
  await tester.tap(option);
  await tester.pumpAndSettle();
}

Finder _searchField() => find.descendant(of: find.byKey(const Key('study-search')), matching: find.byType(TextField));

void main() {
  group('QuestionQuery', () {
    test('changing the subject drops the chapter and topic that belong to it', () {
      const query = QuestionQuery(levelId: 'l', subjectId: 's', chapterId: 'c', topicId: 't', year: 2022);
      final changed = query.copyWith(subjectId: 's2', clearSubject: false);
      expect(changed.chapterId, 'c'); // copyWith alone keeps them; clearing the subject is explicit
      final cleared = query.copyWith(clearSubject: true);
      expect((cleared.subjectId, cleared.chapterId, cleared.topicId, cleared.year), (null, null, null, 2022));
    });

    test('short search text is not sent, and the level alone is not a narrowing filter', () {
      const query = QuestionQuery(levelId: 'l', search: 'a');
      expect(query.toQuery()['q'], isNull);
      expect(query.hasNarrowingFilters, isTrue); // the text exists, even though it is not sent yet
      expect(const QuestionQuery(levelId: 'l').hasNarrowingFilters, isFalse);
      expect(const QuestionQuery(search: 'আলো').toQuery()['q'], 'আলো');
    });
  });

  group('study screen', () {
    testWidgets('a question tile announces its marks along with type and stem', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, questions: FakeQuestions(), location: '/study');
      expect(find.bySemanticsLabel(RegExp(r'^Multiple choice, .*mark.*প্রশ্ন নম্বর 0$')), findsOneWidget);
      handle.dispose();
    });

    testWidgets('starts at SSC and lists questions', (tester) async {
      final questions = FakeQuestions();
      await pumpApp(tester, questions: questions, location: '/study');
      expect(find.text('প্রশ্ন নম্বর 0'), findsOneWidget);
      expect(find.text('Multiple choice'), findsWidgets);
      expect(questions.queries.first.$1.levelId, sscLevel.id);
      expect(find.text('Clear filters'), findsNothing);
    });

    testWidgets('picking a level resets filters and reloads', (tester) async {
      final questions = FakeQuestions();
      await pumpApp(tester, questions: questions, location: '/study');
      await tester.tap(find.text('এইচএসসি'));
      await tester.pumpAndSettle();
      expect(questions.queries.last.$1, const QuestionQuery(levelId: 'lvl-hsc'));
    });

    testWidgets('filters go to the server and can be cleared', (tester) async {
      final questions = FakeQuestions();
      await pumpApp(tester, questions: questions, location: '/study');

      await _tapChip(tester, 'Subject');
      await tester.tap(find.text(physics.name));
      await tester.pumpAndSettle();
      expect(questions.queries.last.$1.subjectId, physics.id);
      expect(find.widgetWithText(FilterChip, 'Subject: ${physics.name}'), findsOneWidget);

      await _tapChip(tester, 'Chapter');
      expect(questions.chapterRequests, [physics.id]);
      await tester.tap(find.text('1. ভৌত জগৎ'));
      await tester.pumpAndSettle();
      expect(questions.queries.last.$1.chapterId, 'ch-1');

      await _tapChip(tester, 'Type');
      await _tapText(tester, 'Creative');
      expect(questions.queries.last.$1.type, QuestionType.creative);

      await _tapChip(tester, 'Difficulty');
      await _tapText(tester, 'Level 3');
      expect(questions.queries.last.$1.difficulty, 3);

      await tester.scrollUntilVisible(
        find.text('Clear filters'),
        120,
        scrollable: find.descendant(
          of: find.byWidgetPredicate((w) => w is ListView && w.scrollDirection == Axis.horizontal),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.ensureVisible(find.text('Clear filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();
      expect(questions.queries.last.$1, const QuestionQuery(levelId: 'lvl-ssc'));
    });

    testWidgets('the chapter filter needs a subject first', (tester) async {
      await pumpApp(tester, location: '/study');
      final chip = tester.widget<FilterChip>(find.widgetWithText(FilterChip, 'Chapter'));
      expect(chip.onSelected, isNull);
    });

    testWidgets('choosing Any in a sheet clears that filter', (tester) async {
      final questions = FakeQuestions();
      await pumpApp(tester, questions: questions, location: '/study');
      await _tapChip(tester, 'Type');
      await _tapText(tester, 'Matching');
      expect(questions.queries.last.$1.type, QuestionType.matching);
      await _tapChip(tester, 'Type: Matching');
      await _tapText(tester, 'Any');
      expect(questions.queries.last.$1.type, isNull);
    });

    testWidgets('search is debounced and sent to the server', (tester) async {
      final questions = FakeQuestions();
      await pumpApp(tester, questions: questions, location: '/study');
      final before = questions.queries.length;
      await tester.enterText(_searchField(), 'আলো');
      await tester.pump(const Duration(milliseconds: 100));
      expect(questions.queries.length, before);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(questions.queries.last.$1.search, 'আলো');
    });

    testWidgets('an empty result offers to clear the filters', (tester) async {
      final questions = FakeQuestions(total: 0);
      await pumpApp(tester, questions: questions, location: '/study');
      expect(find.text('No questions match these filters'), findsOneWidget);
      expect(find.text('Clear filters'), findsNothing); // nothing to clear yet
      await _tapChip(tester, 'Type');
      await _tapText(tester, 'Creative');
      expect(find.text('Clear filters'), findsWidgets);
    });

    testWidgets('scrolling loads the next page with the cursor', (tester) async {
      final questions = FakeQuestions(total: 45);
      await pumpApp(tester, questions: questions, location: '/study');
      expect(questions.queries.length, 1);
      await tester.dragUntilVisible(
        find.text('প্রশ্ন নম্বর 19'),
        find.byType(CustomScrollView),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      expect(questions.queries.any((q) => q.$2 == '20'), isTrue);
    });

    testWidgets('survives 200 % text and meets accessibility guidelines', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpApp(tester, location: '/study', locale: const Locale('bn'));
      expect(tester.takeException(), isNull);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
    });
  });

  group('question screen', () {
    testWidgets('shows stem and options, and reveals the server-provided answer', (tester) async {
      await pumpApp(tester, location: '/study');
      await tester.tap(find.text('প্রশ্ন নম্বর 0'));
      await tester.pumpAndSettle();
      expect(find.text('আলোর বেগ কত?'), findsOneWidget);
      expect(find.text('উত্তর খ'), findsOneWidget);
      expect(find.text('Appeared in 2022 · #12'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsNothing);
      expect(find.text('Explanation'), findsNothing);

      await tester.tap(find.text('উত্তর ক'));
      await tester.pump();
      await tester.ensureVisible(find.text('Show answer'));
      await tester.tap(find.text('Show answer'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_circle), findsOneWidget); // option খ
      expect(find.byIcon(Icons.cancel), findsOneWidget); // the wrong pick, ক
      expect(find.text('Explanation'), findsOneWidget);
      await tester.tap(find.text('Hide answer'));
      await tester.pumpAndSettle();
      expect(find.text('Explanation'), findsNothing);
    });

    testWidgets('multiple-answer questions toggle several picks', (tester) async {
      final detail = fakeQuestionDetail();
      final multi = QuestionDetail(
        card: const QuestionCard(
          id: 'q-1',
          type: QuestionType.mcqMulti,
          locale: 'bn',
          stemText: 's',
          marks: 1,
          accessLevel: AccessLevel.free,
        ),
        stem: detail.stem,
        options: detail.options,
        parts: const [],
        appearances: const [],
        access: detail.access,
      );
      await pumpApp(
        tester,
        questions: FakeQuestions(detail: multi),
        location: '/study/questions/q-1',
      );
      await tester.tap(find.text('উত্তর ক'));
      await tester.tap(find.text('উত্তর গ'));
      await tester.pump();
      await tester.tap(find.text('উত্তর ক'));
      await tester.pump();
      await tester.ensureVisible(find.text('Show answer'));
      await tester.tap(find.text('Show answer'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.cancel), findsOneWidget); // only গ is still picked, and it is wrong
    });

    testWidgets('locked answers: no answer data is shown and a guest is told to sign in', (tester) async {
      final locked = fakeQuestionDetail(canViewAnswers: false, reasons: const [AccessReason.signInRequired]);
      await pumpApp(
        tester,
        questions: FakeQuestions(detail: locked),
        location: '/study/questions/q-1',
      );
      expect(find.text('আলোর বেগ কত?'), findsOneWidget); // the question itself stays visible
      expect(find.text('Show answer'), findsNothing);
      expect(find.text('Sign in to see answers'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Sign in'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsNothing);
    });

    testWidgets('premium answers explain themselves without a sign-in button', (tester) async {
      final locked = fakeQuestionDetail(canViewAnswers: false, reasons: const [AccessReason.entitlementRequired]);
      await pumpApp(
        tester,
        restored: testUser,
        questions: FakeQuestions(detail: locked),
        location: '/study/questions/q-1',
      );
      expect(find.text('Answers are part of Premium'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Sign in'), findsNothing);
    });

    testWidgets('creative questions show the passage and parts with model answers', (tester) async {
      await pumpApp(
        tester,
        questions: FakeQuestions(detail: fakeQuestionDetail(creative: true)),
        location: '/study/questions/q-1',
      );
      expect(find.text('Read the passage'), findsOneWidget);
      expect(find.text('একটি বস্তু ১০ মি/সে বেগে চলছে।'), findsOneWidget);
      expect(find.text('বেগ কাকে বলে?'), findsOneWidget);
      expect(find.text('সরণের পরিবর্তনের হার'), findsNothing);
      await tester.ensureVisible(find.text('Show answer'));
      await tester.tap(find.text('Show answer'));
      await tester.pumpAndSettle();
      expect(find.text('সরণের পরিবর্তনের হার'), findsOneWidget);
    });

    testWidgets('meets accessibility guidelines in Bangla at 200 % text', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpApp(tester, location: '/study/questions/q-1', locale: const Locale('bn'));
      expect(tester.takeException(), isNull);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    });
  });
}

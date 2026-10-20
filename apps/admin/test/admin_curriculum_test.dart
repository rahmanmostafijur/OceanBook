import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ob_core/ob_core.dart';

import 'support/admin_harness.dart';

Future<FakeAdminCurriculum> _openPhysics(WidgetTester tester, {FakeAdminCurriculum? curriculum}) async {
  final fake = curriculum ?? FakeAdminCurriculum();
  await pumpAdmin(tester, restored: staffUser, curriculum: fake, location: '/subjects');
  await tester.tap(find.text('Physics 1st Paper'));
  await tester.pumpAndSettle();
  return fake;
}

void main() {
  testWidgets('shows chapters and topics with their controls', (tester) async {
    await _openPhysics(tester);
    expect(find.text('1. Physical world'), findsOneWidget);
    expect(find.text('Measurement'), findsOneWidget);
    expect(find.byTooltip('Archive'), findsNWidgets(3));
  });

  testWidgets('adds a chapter with the next number and both names', (tester) async {
    final fake = await _openPhysics(tester);
    await tester.tap(find.byKey(const Key('add-chapter-s1')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, '2'), findsOneWidget); // next chapter number suggested

    await tester.enterText(find.byKey(const Key('name-dialog-bn')), 'গতি');
    await tester.enterText(find.byKey(const Key('name-dialog-en')), 'Motion');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(fake.calls, ['createChapter:s1:2:{bn: গতি, en: Motion}']);
    expect(find.text('Save'), findsNothing); // dialog closed
  });

  testWidgets('the Bangla name is required before anything is sent', (tester) async {
    final fake = await _openPhysics(tester);
    await tester.tap(find.byKey(const Key('add-topic-c1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('name-dialog-en')), 'Only English');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Please check the highlighted fields.'), findsOneWidget);
    expect(fake.calls, isEmpty);
  });

  testWidgets('edits a topic name', (tester) async {
    final fake = await _openPhysics(tester);
    await tester.tap(find.byKey(const Key('edit-topic-t1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('name-dialog-bn')), 'পরিমাপ ও একক');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(fake.calls, ['updateTopic:t1:{bn: পরিমাপ ও একক, en: Measurement}:null']);
  });

  testWidgets('archives a chapter', (tester) async {
    final fake = await _openPhysics(tester);
    await tester.tap(find.byKey(const Key('toggle-chapter-c1')));
    await tester.pumpAndSettle();
    expect(fake.calls, ['updateChapter:c1:null:null:false']);
  });

  testWidgets('a server rejection is shown in the dialog and keeps it open', (tester) async {
    final fake = FakeAdminCurriculum()
      ..writeError = const ServerFailure(
        status: 403,
        errors: [ApiErrorItem(code: ApiErrorCode.forbidden, message: 'no')],
      );
    await _openPhysics(tester, curriculum: fake);
    await tester.tap(find.byKey(const Key('add-topic-c1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('name-dialog-bn')), 'নতুন');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Save'), findsOneWidget);
    expect(find.text("You don't have access to this."), findsOneWidget);
  });

  testWidgets('curriculum page and dialog meet accessibility guidelines', (tester) async {
    await _openPhysics(tester);
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await tester.tap(find.byKey(const Key('add-chapter-s1')));
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
  });

  group('subjects', () {
    Future<void> pickFromDropdown(WidgetTester tester, String key, String label) async {
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    testWidgets('creates a subject with level, group offering and paper', (tester) async {
      final fake = FakeAdminCurriculum();
      await pumpAdmin(tester, restored: staffUser, curriculum: fake, location: '/subjects');
      await tester.tap(find.byKey(const Key('add-subject')));
      await tester.pumpAndSettle();

      await pickFromDropdown(tester, 'subject-curriculum', 'NCTB 2012');
      await pickFromDropdown(tester, 'subject-level', 'HSC');
      await tester.enterText(find.byKey(const Key('subject-slug')), 'chemistry-1st');
      await tester.enterText(find.byKey(const Key('subject-bn')), 'রসায়ন ১ম পত্র');
      await tester.enterText(find.byKey(const Key('subject-family')), 'chemistry');
      await tester.enterText(find.byKey(const Key('subject-board')), '176');
      await pickFromDropdown(tester, 'subject-paper', '1st paper');
      await pickFromDropdown(tester, 'subject-group-science', 'Elective');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(fake.calls, [
        'createSubject:cur1:l1:chemistry-1st:chemistry:{bn: রসায়ন ১ম পত্র}:176:1:(g1=elective)',
      ]);
      expect(find.text('Save'), findsNothing);
    });

    testWidgets('rejects a bad slug and family key before sending', (tester) async {
      final fake = FakeAdminCurriculum();
      await pumpAdmin(tester, restored: staffUser, curriculum: fake, location: '/subjects');
      await tester.tap(find.byKey(const Key('add-subject')));
      await tester.pumpAndSettle();
      await pickFromDropdown(tester, 'subject-curriculum', 'NCTB 2012');
      await pickFromDropdown(tester, 'subject-level', 'HSC');
      await tester.enterText(find.byKey(const Key('subject-slug')), 'Bad Slug');
      await tester.enterText(find.byKey(const Key('subject-bn')), 'রসায়ন');
      await tester.enterText(find.byKey(const Key('subject-family')), 'Chem');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Please check the highlighted fields.'), findsNWidgets(2));
      expect(fake.calls, isEmpty);
    });

    testWidgets('edits a subject without changing its curriculum, level or slug', (tester) async {
      final fake = FakeAdminCurriculum();
      await pumpAdmin(tester, restored: staffUser, curriculum: fake, location: '/subjects');
      await tester.tap(find.text('Physics 1st Paper'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('edit-subject-s1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('subject-slug')), findsNothing);
      expect(find.byKey(const Key('subject-curriculum')), findsNothing);
      await pickFromDropdown(tester, 'subject-paper', '2nd paper');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(fake.calls, [
        'updateSubject:s1:physics:{bn: পদার্থবিজ্ঞান ১ম পত্র, en: Physics 1st Paper}:2:null',
      ]);
    });

    testWidgets('archives a subject', (tester) async {
      final fake = FakeAdminCurriculum();
      await pumpAdmin(tester, restored: staffUser, curriculum: fake, location: '/subjects');
      await tester.tap(find.text('Physics 1st Paper'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('toggle-subject-s1')));
      await tester.pumpAndSettle();
      expect(fake.calls, ['updateSubject:s1:null:null:null:false']);
    });

    testWidgets('subject dialog meets accessibility guidelines', (tester) async {
      await pumpAdmin(tester, restored: staffUser, location: '/subjects');
      await tester.tap(find.byKey(const Key('add-subject')));
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
    });
  });
}

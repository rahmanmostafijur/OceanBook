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
    expect(find.byTooltip('Archive'), findsNWidgets(2));
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
}

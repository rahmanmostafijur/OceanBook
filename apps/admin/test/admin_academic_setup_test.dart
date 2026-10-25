import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ob_core/ob_core.dart';
import 'package:oceanbook_admin/features/academics/academic_setup_api.dart';

import 'support/admin_harness.dart';

Future<FakeAcademicSetup> _open(WidgetTester tester, {FakeAcademicSetup? setup}) async {
  final fake = setup ?? FakeAcademicSetup();
  await pumpAdmin(tester, restored: staffUser, setup: fake, location: '/academic-setup');
  return fake;
}

Future<void> _kind(WidgetTester tester, SetupKind kind) async {
  await tester.tap(find.byKey(Key('setup-kind-${kind.name}')));
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String key, String text) async {
  await tester.enterText(find.byKey(Key(key)), text);
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists each kind with its details', (tester) async {
    await _open(tester);
    expect(find.text('HSC'), findsOneWidget);
    expect(find.text('SSC'), findsOneWidget);
    await _kind(tester, SetupKind.boards);
    expect(find.text('dhaka · General'), findsOneWidget);
    await _kind(tester, SetupKind.curricula);
    expect(find.text('nctb_2012 · 2012– · Current curriculum'), findsOneWidget);
    await _kind(tester, SetupKind.media);
    expect(find.text('bangla · bn'), findsOneWidget);
  });

  testWidgets('adds a level with a key, names and order', (tester) async {
    final setup = await _open(tester);
    await _tap(tester, 'setup-add');
    await _type(tester, 'setup-key', 'honours');
    await _type(tester, 'setup-bn', 'অনার্স');
    await _type(tester, 'setup-en', 'Honours');
    await _type(tester, 'setup-position', '3');
    await _tap(tester, 'setup-save');

    expect(setup.calls, contains('create:levels:honours:'));
    expect(setup.lastBody, {
      'key': 'honours',
      'name': {'bn': 'অনার্স', 'en': 'Honours'},
      'position': 3,
    });
    expect(find.text('Honours'), findsOneWidget); // the list reloaded
  });

  testWidgets('a key must be lower case letters, digits and underscores starting with a letter', (tester) async {
    final setup = await _open(tester);
    await _tap(tester, 'setup-add');
    await _type(tester, 'setup-bn', 'নাম');
    for (final bad in ['Honours', '1abc', 'a-b', '']) {
      await _type(tester, 'setup-key', bad);
      await _tap(tester, 'setup-save');
      expect(setup.calls.where((c) => c.startsWith('create')), isEmpty, reason: bad);
    }
    await _type(tester, 'setup-key', 'a_1');
    await _tap(tester, 'setup-save');
    expect(setup.calls, contains('create:levels:a_1:'));
  });

  testWidgets('the Bangla name is required', (tester) async {
    final setup = await _open(tester);
    await _tap(tester, 'setup-add');
    await _type(tester, 'setup-key', 'honours');
    await _type(tester, 'setup-en', 'Honours');
    await _tap(tester, 'setup-save');
    expect(setup.calls.where((c) => c.startsWith('create')), isEmpty);
  });

  testWidgets('editing does not offer the key and keeps it', (tester) async {
    final setup = await _open(tester);
    await _tap(tester, 'setup-edit-ssc');
    expect(find.byKey(const Key('setup-key')), findsNothing);
    await _type(tester, 'setup-en', 'Secondary');
    await _tap(tester, 'setup-save');
    expect(setup.calls, contains('update:levels:l0:'));
    expect(setup.lastBody!.containsKey('key'), isFalse);
    expect((setup.lastBody!['name']! as Map)['en'], 'Secondary');
  });

  testWidgets('a group is added under the chosen level', (tester) async {
    final setup = await _open(tester);
    await _kind(tester, SetupKind.groups);
    expect(find.text('Science'), findsOneWidget);
    await _tap(tester, 'setup-add');
    await _type(tester, 'setup-key', 'humanities');
    await _type(tester, 'setup-bn', 'মানবিক');
    await _tap(tester, 'setup-save');
    expect(setup.calls, contains('create:groups:humanities:l1'));
  });

  testWidgets('a curriculum keeps its years and cannot end before it starts', (tester) async {
    final setup = await _open(tester);
    await _kind(tester, SetupKind.curricula);
    await _tap(tester, 'setup-edit-nctb_2012');
    await _type(tester, 'setup-to', '2000');
    await _tap(tester, 'setup-save');
    expect(setup.calls.where((c) => c.startsWith('update')), isEmpty);

    await _type(tester, 'setup-to', '2030');
    await _type(tester, 'setup-from', '1800');
    await _tap(tester, 'setup-save');
    expect(setup.calls.where((c) => c.startsWith('update')), isEmpty); // 1800 is out of range

    await _type(tester, 'setup-from', '2013');
    await _tap(tester, 'setup-save');
    expect(setup.lastBody, containsPair('effective_from_year', 2013));
    expect(setup.lastBody, containsPair('effective_to_year', 2030));
    expect(setup.lastBody, containsPair('is_current', true));
  });

  testWidgets('a board has a type and can be archived and restored; groups and curricula cannot', (tester) async {
    final setup = await _open(tester);
    await _kind(tester, SetupKind.boards);
    await _tap(tester, 'setup-toggle-dhaka');
    expect(setup.calls, contains('update:boards:b1:false'));
    expect(find.textContaining('Archived'), findsWidgets);
    await _tap(tester, 'setup-toggle-dhaka');
    expect(setup.calls, contains('update:boards:b1:true'));

    await _tap(tester, 'setup-add');
    await _type(tester, 'setup-key', 'madrasah_board');
    await _type(tester, 'setup-bn', 'মাদ্রাসা');
    await tester.tap(find.byKey(const Key('setup-board-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Madrasah').last);
    await tester.pumpAndSettle();
    await _tap(tester, 'setup-save');
    expect(setup.lastBody, containsPair('board_type', 'madrasah'));

    await _kind(tester, SetupKind.groups);
    expect(find.byKey(const Key('setup-toggle-science')), findsNothing);
    await _kind(tester, SetupKind.curricula);
    expect(find.byKey(const Key('setup-toggle-nctb_2012')), findsNothing);
  });

  testWidgets('an instruction medium has a content language', (tester) async {
    final setup = await _open(tester);
    await _kind(tester, SetupKind.media);
    await _tap(tester, 'setup-add');
    await _type(tester, 'setup-key', 'english');
    await _type(tester, 'setup-bn', 'ইংরেজি');
    await tester.tap(find.byKey(const Key('setup-content-locale')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English').last);
    await tester.pumpAndSettle();
    await _tap(tester, 'setup-save');
    expect(setup.lastBody, containsPair('content_locale', 'en'));
  });

  testWidgets('a server rejection is shown in the dialog and the dialog stays', (tester) async {
    final setup = FakeAcademicSetup()
      ..writeError = const ServerFailure(
        status: 409,
        errors: [ApiErrorItem(code: ApiErrorCode.conflict, message: 'exists')],
      );
    await _open(tester, setup: setup);
    await _tap(tester, 'setup-add');
    await _type(tester, 'setup-key', 'ssc');
    await _type(tester, 'setup-bn', 'এসএসসি');
    await _tap(tester, 'setup-save');
    expect(find.byKey(const Key('setup-save')), findsOneWidget);
    expect(find.byKey(const Key('setup-key')), findsOneWidget);
  });

  testWidgets('the setup page and its dialog meet accessibility guidelines', (tester) async {
    await _open(tester);
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    await _tap(tester, 'setup-add');
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
  });
}

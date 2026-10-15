import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ob_core/ob_core.dart';
import 'package:oceanbook_admin/features/rights/rights_api.dart';

import 'support/admin_harness.dart';

void main() {
  editionRightsTests();

  test('a record is editable only while it is a draft, and remembers who touched it', () {
    final record = fakeRecord();
    expect(record.isPending, isTrue);
    expect(record.isEditable, isFalse);
    expect(record.touchedBy('author-1'), isTrue);
    expect(record.touchedBy('someone-else'), isFalse);
  });

  test('new provenance is sent with ISO dates and omits empty optionals', () {
    final json = NewProvenance(
      sourceId: 's',
      licenseType: 'cc_by',
      rightsStatus: 'cleared',
      territories: const ['BD'],
      validFrom: DateTime.utc(2026, 3, 5),
    ).toJson();
    expect(json['valid_from'], '2026-03-05');
    expect(json.containsKey('valid_until'), isFalse);
    expect(json.containsKey('source_url'), isFalse);
  });

  testWidgets('content sources list shows kind and status, and retiring one calls the server', (tester) async {
    final rights = FakeRights();
    await pumpAdmin(tester, restored: staffUser, rights: rights, location: '/content-sources');
    expect(find.text('Anyaprokash'), findsOneWidget);
    expect(find.text('Publisher'), findsOneWidget);
    await tester.tap(find.byKey(const Key('source-active-src1')));
    await tester.pumpAndSettle();
    expect(rights.calls, contains('active:src1:false'));
    expect(find.text('Retired'), findsOneWidget);
  });

  testWidgets('new source dialog needs a name and a valid website before it calls the server', (tester) async {
    final rights = FakeRights();
    await pumpAdmin(tester, restored: staffUser, rights: rights, location: '/content-sources');
    await tester.tap(find.byKey(const Key('new-source')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('new-source-create')));
    await tester.pumpAndSettle();
    expect(rights.calls.where((c) => c.startsWith('create')), isEmpty);
    await tester.enterText(find.byKey(const Key('new-source-name-en')), 'Dhaka Board');
    await tester.enterText(find.byKey(const Key('new-source-website')), 'not a url');
    await tester.tap(find.byKey(const Key('new-source-create')));
    await tester.pumpAndSettle();
    expect(rights.calls.where((c) => c.startsWith('create')), isEmpty);
    await tester.enterText(find.byKey(const Key('new-source-website')), 'https://dhakaboard.gov.bd');
    await tester.tap(find.byKey(const Key('new-source-create')));
    await tester.pumpAndSettle();
    expect(rights.calls, contains('create-source:publisher:en=Dhaka Board:https://dhakaboard.gov.bd'));
    expect(find.text('Dhaka Board'), findsOneWidget);
  });

  testWidgets('the queue lets a second person verify, and the entry leaves the queue', (tester) async {
    final rights = FakeRights();
    await pumpAdmin(tester, restored: staffUser, rights: rights, location: '/rights');
    expect(find.text('Anyaprokash'), findsOneWidget);
    await tester.tap(find.byKey(const Key('verify-r1')));
    await tester.pumpAndSettle();
    expect(rights.calls, contains('decide:r1:verified:'));
    expect(find.text('Nothing awaits verification.'), findsOneWidget);
  });

  testWidgets('you cannot verify what you recorded: buttons are off and say why', (tester) async {
    final rights = FakeRights(queued: [fakeRecord(createdBy: staffUser.id)]);
    await pumpAdmin(tester, restored: staffUser, rights: rights, location: '/rights');
    expect(tester.widget<FilledButton>(find.byKey(const Key('verify-r1'))).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(find.byKey(const Key('reject-r1'))).onPressed, isNull);
    expect(find.text('Someone else must verify what you recorded.'), findsOneWidget);
  });

  testWidgets('rejecting needs notes and sends them', (tester) async {
    final rights = FakeRights();
    await pumpAdmin(tester, restored: staffUser, rights: rights, location: '/rights');
    await tester.tap(find.byKey(const Key('reject-r1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reject-confirm')));
    await tester.pumpAndSettle();
    expect(rights.calls.where((c) => c.startsWith('decide')), isEmpty, reason: 'empty notes are not sent');
    await tester.enterText(find.byKey(const Key('reject-notes')), 'Licence number missing');
    await tester.tap(find.byKey(const Key('reject-confirm')));
    await tester.pumpAndSettle();
    expect(rights.calls, contains('decide:r1:rejected:Licence number missing'));
  });

  testWidgets('a server refusal is shown in localised copy', (tester) async {
    final rights = FakeRights()
      ..decideError = const ServerFailure(
        status: 403,
        errors: [ApiErrorItem(code: ApiErrorCode.selfVerificationForbidden, message: 'x')],
      );
    await pumpAdmin(tester, restored: staffUser, rights: rights, location: '/rights');
    await tester.tap(find.byKey(const Key('verify-r1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('queue-error')), findsOneWidget);
    expect(find.text('Someone else must verify what you recorded.'), findsOneWidget);
  });

  testWidgets('rights pages meet accessibility guidelines', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpAdmin(tester, restored: staffUser, location: '/content-sources');
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    await pumpAdmin(tester, restored: staffUser, location: '/rights');
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}

void editionRightsTests() {
  testWidgets('an edition lists its provenance and offers the action its state allows', (tester) async {
    final rights = FakeRights()
      ..edition = [
        fakeRecord(id: 'draft', verification: 'unverified'),
        fakeRecord(id: 'ok', verification: 'verified'),
        fakeRecord(id: 'wait'),
      ];
    await pumpAdmin(tester, restored: staffUser, rights: rights, location: '/books/b1');
    await tester.scrollUntilVisible(find.byKey(const Key('prov-wait')), 200, scrollable: find.byType(Scrollable).first);
    expect(find.byKey(const Key('submit-prov-draft')), findsOneWidget);
    expect(find.byKey(const Key('narrow-ok')), findsOneWidget);
    expect(find.byKey(const Key('submit-prov-wait')), findsNothing);
    expect(find.byKey(const Key('narrow-wait')), findsNothing);
    await tester.tap(find.byKey(const Key('submit-prov-draft')));
    await tester.pumpAndSettle();
    expect(rights.calls, contains('submit:draft'));
  });

  testWidgets('narrowing rights asks for status and an audited reason', (tester) async {
    final rights = FakeRights()..edition = [fakeRecord(id: 'ok', verification: 'verified')];
    await pumpAdmin(tester, restored: staffUser, rights: rights, location: '/books/b1');
    await tester.scrollUntilVisible(find.byKey(const Key('narrow-ok')), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const Key('narrow-ok')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('narrow-confirm')));
    await tester.pumpAndSettle();
    expect(rights.calls.where((c) => c.startsWith('narrow')), isEmpty, reason: 'a reason is required');
    await tester.enterText(find.byKey(const Key('narrow-reason')), 'Publisher withdrew licence');
    await tester.tap(find.byKey(const Key('narrow-confirm')));
    await tester.pumpAndSettle();
    expect(rights.calls, contains('narrow:ok:restricted:Publisher withdrew licence'));
  });

  testWidgets('recording provenance validates territories and sends the chosen source', (tester) async {
    final rights = FakeRights();
    await pumpAdmin(tester, restored: staffUser, rights: rights, location: '/books/b1');
    await tester.scrollUntilVisible(find.byKey(const Key('record-e1')), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const Key('record-e1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('record-confirm')));
    await tester.pumpAndSettle();
    expect(rights.calls.where((c) => c.startsWith('record')), isEmpty, reason: 'a source is required');
    await tester.tap(find.byKey(const Key('record-source')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Anyaprokash').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('record-territories')), 'bd, *');
    await tester.tap(find.byKey(const Key('record-confirm')));
    await tester.pumpAndSettle();
    expect(rights.calls.where((c) => c.startsWith('record')), isEmpty, reason: '* cannot combine with countries');
    await tester.enterText(find.byKey(const Key('record-territories')), 'bd, in');
    await tester.tap(find.byKey(const Key('record-confirm')));
    await tester.pumpAndSettle();
    expect(rights.calls, contains('record:e1:src1:licensed_commercial:BD+IN'));
  });
}

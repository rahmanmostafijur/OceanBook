import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ob_core/ob_core.dart';
import 'package:oceanbook_admin/features/catalog/admin_catalog_api.dart';
import 'package:oceanbook_admin/features/catalog/book_detail_page.dart';

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
  test('workflow actions follow the book status (the server re-checks each one)', () {
    expect(actionsFor('draft'), [BookAction.submit, BookAction.archive]);
    expect(actionsFor('in_review').first, BookAction.publish);
    expect(actionsFor('published'), [BookAction.unpublish, BookAction.archive]);
    expect(actionsFor('archived'), isEmpty);
  });

  testWidgets('books table lists drafts with status and filters on the server', (tester) async {
    final catalog = FakeAdminCatalog();
    await pumpAdmin(tester, restored: staffUser, catalog: catalog, location: '/books');
    expect(find.byType(DataTable), findsOneWidget);
    expect(find.text('নন্দিত নরকে'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'In review'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('books-search')), 'নন্দিত');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(catalog.calls.last, 'books:নন্দিত::1');
  });

  testWidgets('opening a book shows its editions and the server publish-gate verdict', (tester) async {
    await pumpAdmin(tester, restored: staffUser, location: '/books');
    await tester.tap(find.text('নন্দিত নরকে'));
    await tester.pumpAndSettle();
    expect(find.byType(BookDetailPage), findsOneWidget);
    expect(find.text('Publishing blocked'), findsOneWidget);
    expect(find.text("Provenance awaits a second person's verification"), findsOneWidget);
    expect(find.text('bn · 9780306406157 · 2 chapters'), findsOneWidget);
  });

  testWidgets('a blocked publish shows the reasons the server returned', (tester) async {
    final catalog = FakeAdminCatalog()..transitionError = _notPublishable(['NO_PROVENANCE', 'DISPUTED']);
    await pumpAdmin(tester, restored: staffUser, catalog: catalog, location: '/books/b1');
    await tester.tap(find.byKey(const Key('action-publish')));
    await tester.pumpAndSettle();
    expect(catalog.calls.last, 'publish:');
    expect(find.byKey(const Key('action-error')), findsOneWidget);
    expect(find.text('• No provenance recorded'), findsOneWidget);
    expect(find.text('• Rights are disputed'), findsOneWidget);
  });

  testWidgets('unpublishing asks for an audited reason and sends it', (tester) async {
    final catalog = FakeAdminCatalog(book: fakeAdminBook(status: 'published', publishable: true));
    await pumpAdmin(tester, restored: staffUser, catalog: catalog, location: '/books/b1');
    expect(find.text('Provenance verified: ready to publish'), findsOneWidget);
    await tester.tap(find.byKey(const Key('action-unpublish')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('reason-field')), 'Cover update');
    await tester.tap(find.byKey(const Key('reason-confirm')));
    await tester.pumpAndSettle();
    expect(catalog.calls.last, 'unpublish:Cover update');
  });

  testWidgets('new book dialog validates the slug locally and opens the created draft', (tester) async {
    final catalog = FakeAdminCatalog();
    await pumpAdmin(tester, restored: staffUser, catalog: catalog, location: '/books');
    await tester.tap(find.byKey(const Key('new-book')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('new-book-title')), 'নন্দিত নরকে');
    await tester.enterText(find.byKey(const Key('new-book-slug')), 'Not A Slug');
    await tester.tap(find.byKey(const Key('new-book-create')));
    await tester.pumpAndSettle();
    expect(catalog.calls.where((c) => c.startsWith('create')), isEmpty);
    await tester.enterText(find.byKey(const Key('new-book-slug')), 'nondito-noroke');
    await tester.tap(find.byKey(const Key('new-book-create')));
    await tester.pumpAndSettle();
    expect(catalog.calls, contains('create:nondito-noroke:bn:entitled:নন্দিত নরকে'));
    expect(find.byType(BookDetailPage), findsOneWidget);
  });

  testWidgets('authors, publishers and the category tree render', (tester) async {
    await pumpAdmin(tester, restored: staffUser, location: '/authors');
    expect(find.text('হুমায়ূন আহমেদ (Humayun Ahmed)'), findsOneWidget);
    await pumpAdmin(tester, restored: staffUser, location: '/publishers');
    expect(find.text('অন্যপ্রকাশ'), findsOneWidget);
    await pumpAdmin(tester, restored: staffUser, location: '/categories');
    final fiction = tester.getTopLeft(find.text('Fiction'));
    final novel = tester.getTopLeft(find.text('Novel'));
    expect(fiction.dy < novel.dy && fiction.dx < novel.dx, isTrue, reason: 'parent first, child indented');
  });

  testWidgets('catalog admin pages meet accessibility guidelines', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpAdmin(tester, restored: staffUser, location: '/books');
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    await pumpAdmin(tester, restored: staffUser, location: '/books/b1');
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}

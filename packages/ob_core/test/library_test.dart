import 'package:flutter_test/flutter_test.dart';
import 'package:ob_core/ob_core.dart';

import 'support/fake_http.dart';

Map<String, Object?> item({String status = 'reading', Object? rating = '4.50'}) => {
  'book_id': 'b1',
  'slug': 'nondito-noroke',
  'title': 'নন্দিত নরকে',
  'subtitle': null,
  'locale': 'bn',
  'cover_url': null,
  'access_level': 'free',
  'contributors': [
    {'id': 'a1', 'slug': 'humayun-ahmed', 'name': 'হুমায়ূন আহমেদ', 'role': 'author'},
    {'id': 'a2', 'slug': 'editor', 'name': 'Editor', 'role': 'editor'},
  ],
  'shelf_status': status,
  'is_favorite': true,
  'added_at': '2026-10-01T10:00:00Z',
  'started_at': '2026-10-02T10:00:00Z',
  'finished_at': null,
  'updated_at': '2026-10-02T10:00:00Z',
  'primary_category': {'id': 'c1', 'slug': 'novel', 'name': 'উপন্যাস'},
  'language': 'bn',
  'page_count': 120,
  'publisher': {'id': 'p1', 'slug': 'anyaprokash', 'name': 'অন্যপ্রকাশ'},
  'rating_avg': rating,
  'rating_count': 12,
};

Map<String, Object?> collection({List<String> ids = const ['b1']}) => {
  'id': 'c-1',
  'name': 'Weekend',
  'description': null,
  'position': 0,
  'book_ids': ids,
  'book_count': ids.length,
  'created_at': '2026-10-01T10:00:00Z',
  'updated_at': '2026-10-01T10:00:00Z',
};

void main() {
  late FakeAdapter adapter;
  late LibraryApi library;

  setUp(() {
    adapter = FakeAdapter((_) => json(200, envelope(null)));
    library = LibraryApi(
      ApiClient(
        baseUrl: 'https://api.test/api/v1',
        tokens: InMemoryTokenStore(),
        identity: const ClientIdentity(installationId: 'install-1234', appVersion: '0.1.0', platform: 'android'),
        locale: () => 'bn',
        adapter: adapter,
        retryBaseDelay: const Duration(milliseconds: 1),
      ),
    );
  });

  Map<String, Object?> sentBody() => Map<String, Object?>.from(adapter.requests.last.data as Map);

  test('library items decode shelf state and catalog facts', () async {
    adapter.handler = (_) => json(200, envelope([item()]));
    final items = await library.library();
    final book = items.single;
    expect(adapter.requests.single.path, endsWith('/me/library'));
    expect(book.status, ShelfStatus.reading);
    expect(book.isFavorite, isTrue);
    expect(book.authorNames, ['হুমায়ূন আহমেদ']);
    expect(book.category?.name, 'উপন্যাস');
    expect(book.publisher?.slug, 'anyaprokash');
    expect(book.pageCount, 120);
    expect(book.ratingAvg, 4.5);
    expect(book.finishedAt, isNull);
    expect(book.startedAt, DateTime.utc(2026, 10, 2, 10));
  });

  test('numeric ratings and unknown statuses decode safely', () {
    expect(LibraryItem.fromJson(item(rating: 3)).ratingAvg, 3.0);
    expect(LibraryItem.fromJson(item(status: 'something-new')).status, ShelfStatus.wantToRead);
  });

  test('search matches title and authors, not editors', () {
    final book = LibraryItem.fromJson(item());
    expect(book.matches('হুমায়ূন'), isTrue);
    expect(book.matches('নন্দিত'), isTrue);
    expect(book.matches('Editor'), isFalse);
    expect(book.matches('  '), isTrue);
  });

  test('saveBook sends only the fields that change', () async {
    adapter.handler = (_) => json(200, envelope(item(status: 'finished')));
    await library.saveBook('b1', status: ShelfStatus.finished);
    expect(adapter.requests.last.method, 'PUT');
    expect(adapter.requests.last.path, endsWith('/me/books/b1'));
    expect(sentBody(), {'shelf_status': 'finished'});

    await library.saveBook('b1', isFavorite: false);
    expect(sentBody(), {'is_favorite': false});
  });

  test('updateCollection distinguishes unchanged from cleared descriptions', () async {
    adapter.handler = (_) => json(200, envelope(collection()));
    await library.updateCollection('c-1', name: 'Later');
    expect(sentBody(), {'name': 'Later'});
    await library.updateCollection('c-1', clearDescription: true);
    expect(sentBody(), {'description': null});
  });

  test('collection items are added with PUT and removed with DELETE', () async {
    adapter.handler = (_) => json(200, envelope(collection(ids: const ['b1', 'b2'])));
    final added = await library.addToCollection('c-1', 'b2');
    expect(adapter.requests.last.method, 'PUT');
    expect(added.bookIds, ['b1', 'b2']);
    expect(added.contains('b2'), isTrue);

    adapter.handler = (_) => json(200, envelope(collection()));
    final removed = await library.removeFromCollection('c-1', 'b2');
    expect(adapter.requests.last.method, 'DELETE');
    expect(adapter.requests.last.path, endsWith('/me/collections/c-1/items/b2'));
    expect(removed.bookCount, 1);
  });

  test('library errors surface their codes', () async {
    adapter.handler = (_) => json(409, errorBody('COLLECTION_NAME_TAKEN'));
    await expectLater(
      library.createCollection(id: 'c-2', name: 'weekend'),
      throwsA(isA<ServerFailure>().having((f) => f.code, 'code', ApiErrorCode.collectionNameTaken)),
    );
  });
}

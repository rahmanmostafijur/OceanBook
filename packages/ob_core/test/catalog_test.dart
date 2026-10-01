import 'package:flutter_test/flutter_test.dart';
import 'package:ob_core/ob_core.dart';

import 'support/fake_http.dart';

Map<String, Object?> card({String slug = 'nondito-noroke', String locale = 'bn'}) => {
  'id': 'b1',
  'slug': slug,
  'locale': locale,
  'title': 'নন্দিত নরকে',
  'subtitle': null,
  'content_type': 'book',
  'access_level': 'entitled',
  'contributors': [
    {'id': 'a1', 'slug': 'humayun-ahmed', 'name': 'হুমায়ূন আহমেদ', 'role': 'author'},
    {'id': 'a2', 'slug': 'editor', 'name': 'Editor', 'role': 'editor'},
  ],
  'cover_url': null,
  'rating_avg': '0.00',
  'rating_count': 0,
  'published_at': '2026-10-01T10:00:00Z',
};

Map<String, Object?> access({bool canRead = false, bool reader = false, List<String>? reasons}) => {
  'level': 'entitled',
  'state': canRead ? 'full' : 'preview_only',
  'reasons': reasons ?? ['SIGN_IN_REQUIRED', 'ENTITLEMENT_REQUIRED'],
  'can_preview': true,
  'can_read': canRead,
  'can_download': false,
  'reader_available': reader,
  'acquire': {'entitlement_key': 'books.premium'},
};

void main() {
  late FakeAdapter adapter;
  late CatalogApi catalog;

  setUp(() {
    adapter = FakeAdapter((_) => json(200, envelope(null)));
    catalog = CatalogApi(
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

  test('book list sends only meaningful filters and follows the cursor', () async {
    adapter.handler = (_) => json(200, envelope([card()], page: {'next_cursor': 'c2', 'has_more': true, 'limit': 20}));
    final page = await catalog.books(
      const BookQuery(category: 'fiction', search: ' ন '),
      cursor: 'c1',
    );
    final params = adapter.requests.single.queryParameters;
    expect(params, {'category': 'fiction', 'sort': 'newest', 'cursor': 'c1', 'limit': 20});
    expect(page.nextCursor, 'c2');
    expect(page.items.single.authors.map((a) => a.name), ['হুমায়ূন আহমেদ']);
    expect(page.items.single.accessLevel, AccessLevel.entitled);
  });

  test('detail decodes structure and the server access block; Read stays off without the reader', () async {
    adapter.handler = (_) => json(
      200,
      envelope({
        ...card(),
        'description': 'প্রথম উপন্যাস',
        'available_locales': ['bn'],
        'categories': [
          {'id': 'c1', 'slug': 'novel', 'name': 'উপন্যাস', 'is_primary': true},
        ],
        'tags': <Object>[],
        'editions': [
          {
            'id': 'e1',
            'edition_label': 'প্রথম সংস্করণ',
            'edition_number': null,
            'isbn13': '9780306406157',
            'isbn10': null,
            'publication_date': '1972-01-01',
            'page_count': 120,
            'language': 'bn',
            'publishers': [
              {'id': 'p1', 'slug': 'anyaprokash', 'name': 'অন্যপ্রকাশ', 'role': 'publisher'},
            ],
          },
        ],
        'default_edition_id': 'e1',
        'toc': [
          {
            'id': 'ch1',
            'title': 'এক',
            'word_count': 900,
            'is_preview': false,
            'sections': [
              {'id': 's1', 'title': 'শুরু', 'word_count': 900, 'is_preview': true},
            ],
          },
        ],
        'attributions': ['অন্যপ্রকাশের অনুমতিক্রমে'],
        'access': access(canRead: true),
      }),
    );
    final detail = await catalog.book('nondito-noroke');
    expect(adapter.requests.single.path, '/books/nondito-noroke');
    expect(detail.defaultEdition!.publishers.single.name, 'অন্যপ্রকাশ');
    expect(detail.toc.single.hasPreview, isTrue);
    expect(detail.access.canRead, isTrue);
    expect(detail.access.readEnabled, isFalse, reason: 'the reader is not available until Phase 4');
    expect(detail.access.needsEntitlement, isTrue);
    expect(detail.access.entitlementKey, 'books.premium');
  });

  test('unknown access values fail closed', () {
    final parsed = BookAccess.fromJson({'level': 'gold', 'state': 'weird'});
    expect(parsed.level, AccessLevel.unknown);
    expect(parsed.state, AccessState.unavailable);
    expect((parsed.canRead, parsed.canPreview, parsed.readEnabled), (false, false, false));
  });

  test('categories and authors decode; not found maps to a typed failure', () async {
    adapter.handler = (request) => request.path == '/categories'
        ? json(
            200,
            envelope([
              {
                'id': 'c1',
                'parent_id': null,
                'slug': 'fiction',
                'path': 'fiction',
                'depth': 0,
                'name': 'কথাসাহিত্য',
                'description': null,
                'icon': null,
                'position': 0,
              },
            ]),
          )
        : json(404, errorBody('NOT_FOUND'));
    expect((await catalog.categories()).single.name, 'কথাসাহিত্য');
    await expectLater(
      catalog.author('nobody'),
      throwsA(isA<ServerFailure>().having((f) => f.code, 'code', ApiErrorCode.notFound)),
    );
  });
}

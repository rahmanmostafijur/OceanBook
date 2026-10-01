import 'package:ob_core/ob_core.dart';

const fakeAuthor = Contributor(id: 'a1', slug: 'humayun-ahmed', name: 'হুমায়ূন আহমেদ', role: 'author');

BookCard fakeCard(int i, {AccessLevel access = AccessLevel.entitled, String locale = 'bn'}) => BookCard(
  id: 'book-$i',
  slug: 'book-$i',
  locale: locale,
  title: i == 0 ? 'নন্দিত নরকে' : 'বই $i',
  accessLevel: access,
  contributors: const [fakeAuthor],
);

BookAccess fakeAccess({
  bool canRead = false,
  bool canPreview = true,
  bool readerAvailable = false,
  List<String> reasons = const [AccessReason.signInRequired, AccessReason.entitlementRequired],
}) => BookAccess(
  level: AccessLevel.entitled,
  state: canRead ? AccessState.full : (canPreview ? AccessState.previewOnly : AccessState.unavailable),
  reasons: reasons,
  canPreview: canPreview,
  canRead: canRead,
  canDownload: false,
  readerAvailable: readerAvailable,
  entitlementKey: 'books.premium',
);

BookDetail fakeDetail({BookAccess? access, String locale = 'bn'}) => BookDetail(
  card: fakeCard(0, locale: locale),
  description: 'হুমায়ূন আহমেদের প্রথম উপন্যাস।',
  availableLocales: [locale],
  categories: const [NamedRef(id: 'c1', slug: 'novel', name: 'উপন্যাস', isPrimary: true)],
  tags: const [],
  editions: [
    Edition(
      id: 'e1',
      label: 'প্রথম সংস্করণ',
      language: 'bn',
      isbn13: '9780306406157',
      pageCount: 120,
      publicationDate: DateTime.utc(1972),
      publishers: const [NamedRef(id: 'p1', slug: 'anyaprokash', name: 'অন্যপ্রকাশ', role: 'publisher')],
    ),
  ],
  defaultEditionId: 'e1',
  toc: const [
    TocChapter(
      id: 'ch1',
      title: 'এক',
      isPreview: false,
      sections: [TocSection(id: 's1', title: 'শুরু', isPreview: true)],
    ),
    TocChapter(id: 'ch2', title: 'দুই', isPreview: false, sections: []),
  ],
  attributions: const ['অন্যপ্রকাশের অনুমতিক্রমে'],
  access: access ?? fakeAccess(),
);

/// In-memory catalog that records the queries it receives (filtering is the server's job).
class FakeCatalog implements CatalogRepository {
  FakeCatalog({this.total = 3, BookDetail? detail}) : detail = detail ?? fakeDetail();

  final int total;
  BookDetail detail;
  final List<(BookQuery, String?)> queries = [];
  int detailCalls = 0;

  @override
  Future<CursorPage<BookCard>> books(BookQuery query, {String? cursor, int limit = 20}) async {
    queries.add((query, cursor));
    final start = cursor == null ? 0 : int.parse(cursor);
    final end = (start + limit).clamp(0, total);
    return CursorPage(items: [for (var i = start; i < end; i++) fakeCard(i)], nextCursor: end < total ? '$end' : null);
  }

  @override
  Future<BookDetail> book(String idOrSlug) async {
    detailCalls++;
    return detail;
  }

  @override
  Future<List<CategoryNode>> categories() async => const [
    CategoryNode(id: 'c0', slug: 'fiction', name: 'Fiction', depth: 0, position: 0),
    CategoryNode(id: 'c1', slug: 'novel', name: 'Novel', depth: 1, position: 0, parentId: 'c0'),
  ];

  @override
  Future<AuthorProfile> author(String slug) async =>
      const AuthorProfile(id: 'a1', slug: 'humayun-ahmed', name: 'হুমায়ূন আহমেদ', nameAlt: 'Humayun Ahmed');
}

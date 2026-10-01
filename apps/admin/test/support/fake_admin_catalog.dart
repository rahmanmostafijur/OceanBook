import 'package:ob_core/ob_core.dart';
import 'package:oceanbook_admin/features/catalog/admin_catalog_api.dart';

AdminBook fakeAdminBook({String status = 'in_review', bool publishable = false}) => AdminBook(
  id: 'b1',
  slug: 'nondito-noroke',
  status: status,
  accessLevel: 'entitled',
  sourceLocale: 'bn',
  defaultEditionId: 'e1',
  translations: const [AdminTranslation(locale: 'bn', title: 'নন্দিত নরকে', status: 'draft')],
  contributors: const ['হুমায়ূন আহমেদ'],
  editions: [
    AdminEdition(
      id: 'e1',
      label: 'প্রথম সংস্করণ',
      language: 'bn',
      status: 'draft',
      isbn13: '9780306406157',
      chapterCount: 2,
      publishable: publishable,
      blockReasons: publishable ? const [] : const ['NOT_VERIFIED'],
    ),
  ],
);

/// Scripted admin catalog: records calls, and can fail transitions the way the server does.
class FakeAdminCatalog implements AdminCatalogRepository {
  FakeAdminCatalog({AdminBook? book}) : current = book ?? fakeAdminBook();

  AdminBook current;
  Object? transitionError;
  final List<String> calls = [];

  @override
  Future<Paged<AdminBookRow>> books({String? query, String? status, int page = 1, int pageSize = 25}) async {
    calls.add('books:${query ?? ''}:${status ?? ''}:$page');
    return Paged(
      rows: [
        AdminBookRow(
          id: 'b1',
          slug: 'nondito-noroke',
          title: 'নন্দিত নরকে',
          status: current.status,
          accessLevel: 'entitled',
          editionCount: 1,
          updatedAt: DateTime.utc(2026, 10),
        ),
      ],
      total: 1,
    );
  }

  @override
  Future<AdminBook> book(String id) async => current;

  @override
  Future<AdminBook> createBook({
    required String slug,
    required String sourceLocale,
    required String title,
    required String accessLevel,
  }) async {
    calls.add('create:$slug:$sourceLocale:$accessLevel:$title');
    return current = fakeAdminBook(status: 'draft');
  }

  @override
  Future<AdminBook> transition(String id, BookAction action, {String? reason}) async {
    calls.add('${action.path}:${reason ?? ''}');
    final error = transitionError;
    if (error != null) throw error;
    return current;
  }

  @override
  Future<Paged<AdminPerson>> authors({String? query, int page = 1}) async => const Paged(
    rows: [AdminPerson(id: 'a1', slug: 'humayun-ahmed', name: 'হুমায়ূন আহমেদ', nameAlt: 'Humayun Ahmed')],
    total: 1,
  );

  @override
  Future<Paged<AdminPerson>> publishers({String? query, int page = 1}) async => const Paged(
    rows: [AdminPerson(id: 'p1', slug: 'anyaprokash', name: 'অন্যপ্রকাশ')],
    total: 1,
  );

  @override
  Future<List<AdminCategory>> categories() async => const [
    AdminCategory(
      id: 'c1',
      slug: 'novel',
      path: 'fiction.novel',
      depth: 1,
      name: LocalizedText({'bn': 'উপন্যাস', 'en': 'Novel'}),
      isActive: true,
    ),
    AdminCategory(
      id: 'c0',
      slug: 'fiction',
      path: 'fiction',
      depth: 0,
      name: LocalizedText({'bn': 'কথাসাহিত্য', 'en': 'Fiction'}),
      isActive: true,
    ),
  ];
}

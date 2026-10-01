import '../api/api_client.dart';
import '../api/api_models.dart';
import 'catalog_models.dart';

/// Read-only catalog access for apps. Implementations must not filter or decide access locally.
abstract interface class CatalogRepository {
  Future<CursorPage<BookCard>> books(BookQuery query, {String? cursor, int limit = 20});
  Future<BookDetail> book(String idOrSlug);
  Future<List<CategoryNode>> categories();
  Future<AuthorProfile> author(String slug);
}

class CatalogApi implements CatalogRepository {
  CatalogApi(this.api);

  final ApiClient api;

  @override
  Future<CursorPage<BookCard>> books(BookQuery query, {String? cursor, int limit = 20}) async {
    final response = await api.get(
      '/books',
      query: {...query.toQuery(), 'cursor': cursor, 'limit': limit},
      decode: (json) => [for (final item in json! as List) BookCard.fromJson(item as Map<String, Object?>)],
    );
    final page = response.page;
    return CursorPage(items: response.data, nextCursor: page is CursorPageMeta ? page.nextCursor : null);
  }

  @override
  Future<BookDetail> book(String idOrSlug) async {
    final response = await api.get(
      '/books/${Uri.encodeComponent(idOrSlug)}',
      decode: (json) => BookDetail.fromJson(json! as Map<String, Object?>),
    );
    return response.data;
  }

  @override
  Future<List<CategoryNode>> categories() async {
    final response = await api.get(
      '/categories',
      decode: (json) => [for (final item in json! as List) CategoryNode.fromJson(item as Map<String, Object?>)],
    );
    return response.data;
  }

  @override
  Future<AuthorProfile> author(String slug) async {
    final response = await api.get(
      '/authors/${Uri.encodeComponent(slug)}',
      decode: (json) => AuthorProfile.fromJson(json! as Map<String, Object?>),
    );
    return response.data;
  }
}

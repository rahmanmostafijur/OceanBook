import '../api/api_client.dart';
import 'library_models.dart';

/// The signed-in user's library: shelf state, favourites and their own collections (shelves).
/// Every call goes to the server; the server owns visibility, caps and ownership checks.
abstract interface class LibraryRepository {
  Future<List<LibraryItem>> library();

  /// Adds the book (as want to read unless [status] says otherwise) or updates its shelf state.
  Future<LibraryItem> saveBook(String bookId, {ShelfStatus? status, bool? isFavorite});
  Future<void> removeBook(String bookId);

  Future<List<BookCollection>> collections();
  Future<BookCollection> createCollection({required String id, required String name, String? description});

  /// Pass `clearDescription: true` to remove the description (a null [description] means "unchanged").
  Future<BookCollection> updateCollection(String id, {String? name, String? description, bool clearDescription});
  Future<void> deleteCollection(String id);
  Future<BookCollection> addToCollection(String collectionId, String bookId);
  Future<BookCollection> removeFromCollection(String collectionId, String bookId);
}

class LibraryApi implements LibraryRepository {
  LibraryApi(this.api);

  final ApiClient api;

  static String _enc(String id) => Uri.encodeComponent(id);
  static BookCollection _collection(Object? json) => BookCollection.fromJson(json! as Map<String, Object?>);

  @override
  Future<List<LibraryItem>> library() async {
    final response = await api.get(
      '/me/library',
      decode: (json) => [for (final item in json! as List) LibraryItem.fromJson(item as Map<String, Object?>)],
    );
    return response.data;
  }

  @override
  Future<LibraryItem> saveBook(String bookId, {ShelfStatus? status, bool? isFavorite}) async {
    final response = await api.put(
      '/me/books/${_enc(bookId)}',
      body: {'shelf_status': ?status?.wire, 'is_favorite': ?isFavorite},
      decode: (json) => LibraryItem.fromJson(json! as Map<String, Object?>),
    );
    return response.data;
  }

  @override
  Future<void> removeBook(String bookId) => api.delete('/me/books/${_enc(bookId)}');

  @override
  Future<List<BookCollection>> collections() async {
    final response = await api.get(
      '/me/collections',
      decode: (json) => [for (final c in json! as List) _collection(c)],
    );
    return response.data;
  }

  @override
  Future<BookCollection> createCollection({required String id, required String name, String? description}) async {
    final response = await api.post(
      '/me/collections',
      body: {'id': id, 'name': name, 'description': ?description},
      decode: _collection,
    );
    return response.data;
  }

  @override
  Future<BookCollection> updateCollection(
    String id, {
    String? name,
    String? description,
    bool clearDescription = false,
  }) async {
    final response = await api.patch(
      '/me/collections/${_enc(id)}',
      body: {'name': ?name, if (clearDescription) 'description': null else 'description': ?description},
      decode: _collection,
    );
    return response.data;
  }

  @override
  Future<void> deleteCollection(String id) => api.delete('/me/collections/${_enc(id)}');

  @override
  Future<BookCollection> addToCollection(String collectionId, String bookId) async {
    final response = await api.put('/me/collections/${_enc(collectionId)}/items/${_enc(bookId)}', decode: _collection);
    return response.data;
  }

  @override
  Future<BookCollection> removeFromCollection(String collectionId, String bookId) async {
    final response = await api.deleteWithBody(
      '/me/collections/${_enc(collectionId)}/items/${_enc(bookId)}',
      decode: _collection,
    );
    return response.data;
  }
}

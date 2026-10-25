import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ob_core/ob_core.dart';

import '../../../core/network/api_providers.dart';
import '../../../core/settings/app_settings.dart';
import '../../auth/presentation/auth_controller.dart';

final libraryRepositoryProvider = Provider<LibraryRepository>((ref) => LibraryApi(ref.watch(apiClientProvider)));

/// The signed-in user's id, or null for guests. Library state is rebuilt when it changes, so one
/// user's shelves never show up for the next person on a shared device.
final libraryUserIdProvider = Provider<String?>(
  (ref) => ref.watch(
    authControllerProvider.select((s) => s.value is AuthSignedIn ? (s.value! as AuthSignedIn).user.id : null),
  ),
);

/// The user's library from `/me/library`. Mutations call the server first and then update this list
/// with the server's answer; a failed call leaves the list as it was and rethrows for the UI to report.
class LibraryController extends AsyncNotifier<List<LibraryItem>> {
  LibraryRepository get _repo => ref.read(libraryRepositoryProvider);

  /// Applies a server answer to the list, unless the user changed while the call was in flight (the
  /// answer belongs to the previous account) or the list never loaded (then it is fetched afresh).
  void _apply(String? owner, List<LibraryItem> Function(List<LibraryItem>) update) {
    if (ref.read(libraryUserIdProvider) != owner) return;
    final current = state.value;
    if (current == null) {
      ref.invalidateSelf();
      return;
    }
    state = AsyncData(update(current));
  }

  @override
  Future<List<LibraryItem>> build() async {
    ref.watch(localeProvider); // titles and category names are resolved for the UI language
    if (ref.watch(libraryUserIdProvider) == null) return const [];
    return ref.watch(libraryRepositoryProvider).library();
  }

  /// Adds the book or changes its status / favourite flag.
  Future<LibraryItem> save(String bookId, {ShelfStatus? status, bool? isFavorite}) async {
    final owner = ref.read(libraryUserIdProvider);
    final saved = await _repo.saveBook(bookId, status: status, isFavorite: isFavorite);
    _apply(
      owner,
      (current) => current.any((b) => b.bookId == bookId)
          ? [for (final b in current) b.bookId == bookId ? saved : b]
          : [saved, ...current],
    );
    return saved;
  }

  /// Removes the book from the library; the server also takes it off every shelf.
  Future<void> remove(String bookId) async {
    final owner = ref.read(libraryUserIdProvider);
    await _repo.removeBook(bookId);
    if (ref.read(libraryUserIdProvider) != owner) return;
    _apply(
      owner,
      (current) => [
        for (final b in current)
          if (b.bookId != bookId) b,
      ],
    );
    ref.read(collectionsProvider.notifier).forgetBook(bookId);
  }
}

final libraryProvider = AsyncNotifierProvider<LibraryController, List<LibraryItem>>(LibraryController.new);

/// The library entry for one book, or null when it is not in the library (or not loaded yet).
final libraryItemProvider = Provider.family<LibraryItem?, String>((ref, bookId) {
  for (final b in ref.watch(libraryProvider).value ?? const <LibraryItem>[]) {
    if (b.bookId == bookId) return b;
  }
  return null;
});

/// The user's shelves (collections).
class CollectionsController extends AsyncNotifier<List<BookCollection>> {
  LibraryRepository get _repo => ref.read(libraryRepositoryProvider);

  /// See [LibraryController._apply]: never writes a partial list or another account's answer.
  void _apply(String? owner, List<BookCollection> Function(List<BookCollection>) update) {
    if (ref.read(libraryUserIdProvider) != owner) return;
    final current = state.value;
    if (current == null) {
      ref.invalidateSelf();
      return;
    }
    state = AsyncData(update(current));
  }

  Future<void> _replaceAfter(Future<BookCollection> call) async {
    final owner = ref.read(libraryUserIdProvider);
    final updated = await call;
    _apply(owner, (current) => [for (final c in current) c.id == updated.id ? updated : c]);
  }

  @override
  Future<List<BookCollection>> build() async {
    if (ref.watch(libraryUserIdProvider) == null) return const [];
    return ref.watch(libraryRepositoryProvider).collections();
  }

  List<BookCollection> get _current => state.value ?? const <BookCollection>[];

  /// [id] is generated once per form by the caller, so retrying after a lost response returns the
  /// shelf created the first time instead of a second one.
  Future<BookCollection> create({required String id, required String name, String? description}) async {
    final owner = ref.read(libraryUserIdProvider);
    final created = await _repo.createCollection(id: id, name: name, description: description);
    _apply(
      owner,
      (current) => [
        for (final c in current)
          if (c.id != created.id) c,
        created,
      ],
    );
    return created;
  }

  Future<void> edit(String id, {required String name, String? description}) async {
    final trimmed = description?.trim();
    await _replaceAfter(
      _repo.updateCollection(
        id,
        name: name,
        description: trimmed == null || trimmed.isEmpty ? null : trimmed,
        clearDescription: trimmed == null || trimmed.isEmpty,
      ),
    );
  }

  Future<void> delete(String id) async {
    final owner = ref.read(libraryUserIdProvider);
    await _repo.deleteCollection(id);
    _apply(
      owner,
      (current) => [
        for (final c in current)
          if (c.id != id) c,
      ],
    );
  }

  Future<void> addBook(String collectionId, String bookId) =>
      _replaceAfter(_repo.addToCollection(collectionId, bookId));

  Future<void> removeBook(String collectionId, String bookId) =>
      _replaceAfter(_repo.removeFromCollection(collectionId, bookId));

  /// Mirrors the server after a book left the library: it is on no shelf any more.
  void forgetBook(String bookId) {
    if (!_current.any((c) => c.contains(bookId))) return;
    state = AsyncData([
      for (final c in _current)
        c.contains(bookId)
            ? BookCollection(
                id: c.id,
                name: c.name,
                description: c.description,
                position: c.position,
                bookIds: [
                  for (final id in c.bookIds)
                    if (id != bookId) id,
                ],
                createdAt: c.createdAt,
                updatedAt: c.updatedAt,
              )
            : c,
    ]);
  }
}

final collectionsProvider = AsyncNotifierProvider<CollectionsController, List<BookCollection>>(
  CollectionsController.new,
);

/// Which books the Books tab shows.
enum LibraryShelfFilter { all, wantToRead, reading, finished, favorites }

enum LibrarySort { recentlyAdded, recentlyUpdated, title }

@immutable
class LibraryView {
  const LibraryView({this.query = '', this.filter = LibraryShelfFilter.all, this.sort = LibrarySort.recentlyAdded});

  final String query;
  final LibraryShelfFilter filter;
  final LibrarySort sort;

  LibraryView copyWith({String? query, LibraryShelfFilter? filter, LibrarySort? sort}) =>
      LibraryView(query: query ?? this.query, filter: filter ?? this.filter, sort: sort ?? this.sort);

  bool accepts(LibraryItem book) {
    final passes = switch (filter) {
      LibraryShelfFilter.all => true,
      LibraryShelfFilter.wantToRead => book.status == ShelfStatus.wantToRead,
      LibraryShelfFilter.reading => book.status == ShelfStatus.reading,
      LibraryShelfFilter.finished => book.status == ShelfStatus.finished,
      LibraryShelfFilter.favorites => book.isFavorite,
    };
    return passes && book.matches(query);
  }

  /// Filters and sorts without touching [books].
  List<LibraryItem> apply(List<LibraryItem> books) {
    final visible = [
      for (final b in books)
        if (accepts(b)) b,
    ];
    final compare = switch (sort) {
      LibrarySort.recentlyAdded => (LibraryItem a, LibraryItem b) => b.addedAt.compareTo(a.addedAt),
      LibrarySort.recentlyUpdated => (LibraryItem a, LibraryItem b) => b.updatedAt.compareTo(a.updatedAt),
      LibrarySort.title => (LibraryItem a, LibraryItem b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    };
    return visible..sort(compare);
  }
}

class LibraryViewNotifier extends Notifier<LibraryView> {
  /// Search, filter and sort start fresh for each account on a shared device.
  @override
  LibraryView build() {
    ref.watch(libraryUserIdProvider);
    return const LibraryView();
  }

  void search(String query) => state = state.copyWith(query: query);
  void filter(LibraryShelfFilter filter) => state = state.copyWith(filter: filter);
  void sortBy(LibrarySort sort) => state = state.copyWith(sort: sort);
}

final libraryViewProvider = NotifierProvider<LibraryViewNotifier, LibraryView>(LibraryViewNotifier.new);

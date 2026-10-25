import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ob_core/ob_core.dart';
import 'package:oceanbook_mobile/features/library/data/library_providers.dart';

import 'support/fake_library.dart';

class _User extends Notifier<String?> {
  @override
  String? build() => 'user-a';

  void set(String? id) => state = id;
}

final _user = NotifierProvider<_User, String?>(_User.new);

/// Holds `saveBook` and `collections` until released, to put calls in flight.
class _GatedLibrary extends FakeLibrary {
  _GatedLibrary({super.shelves});

  Completer<void>? saveGate;
  Completer<void>? listGate;

  @override
  Future<LibraryItem> saveBook(String bookId, {ShelfStatus? status, bool? isFavorite}) async {
    await saveGate?.future;
    return super.saveBook(bookId, status: status, isFavorite: isFavorite);
  }

  @override
  Future<List<BookCollection>> collections() async {
    await listGate?.future;
    return super.collections();
  }
}

ProviderContainer _container(FakeLibrary library) {
  final container = ProviderContainer(
    overrides: [
      libraryRepositoryProvider.overrideWithValue(library),
      libraryUserIdProvider.overrideWith((ref) => ref.watch(_user)),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

BookCollection _shelf(String id) =>
    BookCollection(id: id, name: id, position: 0, bookIds: const [], createdAt: testNow, updatedAt: testNow);

void main() {
  test('an answer that arrives after the account changed is not applied to the new account', () async {
    final library = _GatedLibrary()..saveGate = Completer<void>();
    final container = _container(library);
    await container.read(libraryProvider.future);

    final pending = container.read(libraryProvider.notifier).save('new-book');
    container.read(_user.notifier).set('user-b');
    final userB = await container.read(libraryProvider.future);
    library.saveGate!.complete();
    await pending;

    final after = container.read(libraryProvider).value!;
    expect(after.map((b) => b.bookId), userB.map((b) => b.bookId));
    expect(after.any((b) => b.bookId == 'new-book'), isFalse);
  });

  test('creating a shelf before the list has loaded reloads it instead of dropping existing shelves', () async {
    final library = _GatedLibrary(shelves: [_shelf('old')])..listGate = Completer<void>();
    final container = _container(library);
    container.listen(collectionsProvider, (_, _) {});

    await container.read(collectionsProvider.notifier).create(id: 'new', name: 'New');
    library.listGate!.complete();
    final shelves = await container.read(collectionsProvider.future);
    expect(shelves.map((s) => s.id), containsAll(['old', 'new']));
  });

  test('a repeated create with the same id does not add the shelf twice', () async {
    final container = _container(FakeLibrary());
    await container.read(collectionsProvider.future);
    final controller = container.read(collectionsProvider.notifier);
    await controller.create(id: 'same', name: 'Weekend');
    expect(container.read(collectionsProvider).value!.where((s) => s.id == 'same'), hasLength(1));
  });

  test('search and filter start fresh for the next account', () async {
    final container = _container(FakeLibrary());
    container.read(libraryViewProvider.notifier)
      ..search('কসমস')
      ..filter(LibraryShelfFilter.finished);
    container.read(_user.notifier).set('user-b');
    expect(container.read(libraryViewProvider).query, '');
    expect(container.read(libraryViewProvider).filter, LibraryShelfFilter.all);
  });
}

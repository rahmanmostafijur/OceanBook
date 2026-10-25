import 'package:ob_core/ob_core.dart';

/// "Now" for widget tests; the harness pins the insights clock to it.
final testNow = DateTime(2026, 10, 26, 12);

DateTime daysAgo(int days) => testNow.subtract(Duration(days: days));

const _author = Contributor(id: 'a1', slug: 'humayun-ahmed', name: 'হুমায়ূন আহমেদ', role: 'author');
const _novel = NamedRef(id: 'cat-novel', slug: 'novel', name: 'উপন্যাস');
const _science = NamedRef(id: 'cat-science', slug: 'science', name: 'বিজ্ঞান');
const _anyaprokash = NamedRef(id: 'pub-1', slug: 'anyaprokash', name: 'অন্যপ্রকাশ');

LibraryItem libraryItem(
  String id,
  String title, {
  ShelfStatus status = ShelfStatus.wantToRead,
  bool favorite = false,
  int addedDaysAgo = 30,
  int? finishedDaysAgo,
  NamedRef? category = _novel,
  String? language = 'bn',
  int? pages,
  NamedRef? publisher = _anyaprokash,
  double rating = 0,
  int ratingCount = 0,
  List<Contributor> contributors = const [_author],
}) => LibraryItem(
  bookId: id,
  slug: id,
  title: title,
  locale: 'bn',
  accessLevel: AccessLevel.free,
  contributors: contributors,
  status: status,
  isFavorite: favorite,
  addedAt: daysAgo(addedDaysAgo),
  startedAt: status == ShelfStatus.wantToRead ? null : daysAgo(addedDaysAgo),
  finishedAt: finishedDaysAgo == null ? null : daysAgo(finishedDaysAgo),
  updatedAt: daysAgo(finishedDaysAgo ?? addedDaysAgo),
  category: category,
  language: language,
  pageCount: pages,
  publisher: publisher,
  ratingAvg: rating,
  ratingCount: ratingCount,
);

List<LibraryItem> sampleLibrary() => [
  libraryItem(
    'lib-01',
    'নন্দিত নরকে',
    status: ShelfStatus.reading,
    favorite: true,
    addedDaysAgo: 3,
    pages: 96,
    rating: 4.5,
    ratingCount: 20,
  ),
  libraryItem(
    'lib-02',
    'কসমস',
    status: ShelfStatus.finished,
    finishedDaysAgo: 2,
    addedDaysAgo: 40,
    category: _science,
    pages: 396,
    rating: 4.8,
    ratingCount: 9,
  ),
  libraryItem('lib-03', 'পথের পাঁচালী', addedDaysAgo: 10, pages: 240),
  libraryItem(
    'lib-04',
    'A Brief History',
    status: ShelfStatus.finished,
    finishedDaysAgo: 100,
    addedDaysAgo: 200,
    category: _science,
    language: 'en',
    pages: 212,
    publisher: null,
  ),
  libraryItem('lib-05', 'লালসালু', addedDaysAgo: 60, category: null),
];

/// In-memory [LibraryRepository] that applies the server's rules (status timestamps, removal takes the
/// book off every shelf, case-insensitive shelf names) and records calls.
class FakeLibrary implements LibraryRepository {
  FakeLibrary({List<LibraryItem>? items, List<BookCollection>? shelves})
    : _items = [...(items ?? sampleLibrary())],
      _shelves = [...?shelves];

  final List<LibraryItem> _items;
  final List<BookCollection> _shelves;
  final List<String> calls = [];

  /// When set, the next mutating call throws it (and clears it).
  ApiFailure? failNext;

  void _maybeFail() {
    final failure = failNext;
    failNext = null;
    if (failure != null) throw failure;
  }

  static ServerFailure _error(int status, ApiErrorCode code) => ServerFailure(
    status: status,
    errors: [ApiErrorItem(code: code, message: code.wire)],
  );

  @override
  Future<List<LibraryItem>> library() async => List.of(_items);

  @override
  Future<LibraryItem> saveBook(String bookId, {ShelfStatus? status, bool? isFavorite}) async {
    calls.add('save:$bookId:${status?.wire}:$isFavorite');
    _maybeFail();
    final index = _items.indexWhere((b) => b.bookId == bookId);
    final now = testNow;
    final old = index < 0 ? libraryItem(bookId, 'নন্দিত নরকে', addedDaysAgo: 0) : _items[index];
    final next = status ?? old.status;
    final saved = LibraryItem(
      bookId: old.bookId,
      slug: old.slug,
      title: old.title,
      locale: old.locale,
      accessLevel: old.accessLevel,
      contributors: old.contributors,
      status: next,
      isFavorite: isFavorite ?? old.isFavorite,
      addedAt: index < 0 ? now : old.addedAt,
      startedAt: next == ShelfStatus.wantToRead ? old.startedAt : old.startedAt ?? now,
      finishedAt: next == ShelfStatus.finished ? (old.status == ShelfStatus.finished ? old.finishedAt : now) : null,
      updatedAt: now,
      category: old.category,
      language: old.language,
      pageCount: old.pageCount,
      publisher: old.publisher,
      ratingAvg: old.ratingAvg,
      ratingCount: old.ratingCount,
    );
    if (index < 0) {
      _items.insert(0, saved);
    } else {
      _items[index] = saved;
    }
    return saved;
  }

  @override
  Future<void> removeBook(String bookId) async {
    calls.add('remove:$bookId');
    _maybeFail();
    _items.removeWhere((b) => b.bookId == bookId);
    for (var i = 0; i < _shelves.length; i++) {
      if (_shelves[i].contains(bookId)) {
        _shelves[i] = _withIds(_shelves[i], _shelves[i].bookIds.where((id) => id != bookId).toList());
      }
    }
  }

  @override
  Future<List<BookCollection>> collections() async => List.of(_shelves);

  @override
  Future<BookCollection> createCollection({required String id, required String name, String? description}) async {
    calls.add('create:$name');
    _maybeFail();
    if (_shelves.any((s) => s.name.toLowerCase() == name.toLowerCase())) {
      throw _error(409, ApiErrorCode.collectionNameTaken);
    }
    final shelf = BookCollection(
      id: id,
      name: name,
      description: description,
      position: _shelves.length,
      bookIds: const [],
      createdAt: testNow,
      updatedAt: testNow,
    );
    _shelves.add(shelf);
    return shelf;
  }

  @override
  Future<BookCollection> updateCollection(
    String id, {
    String? name,
    String? description,
    bool clearDescription = false,
  }) async {
    calls.add('update:$id:$name');
    _maybeFail();
    final i = _index(id);
    final old = _shelves[i];
    return _shelves[i] = BookCollection(
      id: id,
      name: name ?? old.name,
      description: clearDescription ? null : description ?? old.description,
      position: old.position,
      bookIds: old.bookIds,
      createdAt: old.createdAt,
      updatedAt: testNow,
    );
  }

  @override
  Future<void> deleteCollection(String id) async {
    calls.add('delete:$id');
    _maybeFail();
    _shelves.removeAt(_index(id));
  }

  @override
  Future<BookCollection> addToCollection(String collectionId, String bookId) async {
    calls.add('add:$collectionId:$bookId');
    _maybeFail();
    if (!_items.any((b) => b.bookId == bookId)) throw _error(409, ApiErrorCode.notInLibrary);
    final i = _index(collectionId);
    final ids = _shelves[i].bookIds;
    return _shelves[i] = _withIds(_shelves[i], ids.contains(bookId) ? ids : [...ids, bookId]);
  }

  @override
  Future<BookCollection> removeFromCollection(String collectionId, String bookId) async {
    calls.add('take:$collectionId:$bookId');
    _maybeFail();
    final i = _index(collectionId);
    return _shelves[i] = _withIds(_shelves[i], _shelves[i].bookIds.where((id) => id != bookId).toList());
  }

  int _index(String id) {
    final i = _shelves.indexWhere((s) => s.id == id);
    if (i < 0) throw _error(404, ApiErrorCode.notFound);
    return i;
  }

  static BookCollection _withIds(BookCollection s, List<String> ids) => BookCollection(
    id: s.id,
    name: s.name,
    description: s.description,
    position: s.position,
    bookIds: ids,
    createdAt: s.createdAt,
    updatedAt: s.updatedAt,
  );
}

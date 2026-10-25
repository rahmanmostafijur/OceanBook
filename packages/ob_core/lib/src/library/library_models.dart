import 'package:meta/meta.dart';

import '../catalog/catalog_models.dart';

/// Personal-library value types mirroring `/me/library`, `/me/books/{id}` and `/me/collections`
/// (backend `app/library`). Text arrives already resolved for the request locale.

DateTime? _date(Object? raw) => raw == null ? null : DateTime.parse(raw as String);

/// The server sends decimals as strings; accept numbers too.
double _decimal(Object? raw) => switch (raw) {
  final num n => n.toDouble(),
  final String s => double.tryParse(s) ?? 0,
  _ => 0,
};

/// Where a book sits on the reader's shelf. Every book in the library has one.
enum ShelfStatus {
  wantToRead('want_to_read'),
  reading('reading'),
  finished('finished');

  const ShelfStatus(this.wire);
  final String wire;

  static ShelfStatus fromWire(String? value) =>
      ShelfStatus.values.firstWhere((s) => s.wire == value, orElse: () => ShelfStatus.wantToRead);
}

/// One book in the signed-in user's library: catalog facts plus the user's shelf state.
@immutable
class LibraryItem {
  const LibraryItem({
    required this.bookId,
    required this.slug,
    required this.title,
    required this.locale,
    required this.accessLevel,
    required this.contributors,
    required this.status,
    required this.isFavorite,
    required this.addedAt,
    required this.updatedAt,
    this.subtitle,
    this.coverUrl,
    this.startedAt,
    this.finishedAt,
    this.category,
    this.language,
    this.pageCount,
    this.publisher,
    this.ratingAvg = 0,
    this.ratingCount = 0,
  });

  factory LibraryItem.fromJson(Map<String, Object?> json) {
    final category = json['primary_category'] as Map<String, Object?>?;
    final publisher = json['publisher'] as Map<String, Object?>?;
    return LibraryItem(
      bookId: json['book_id']! as String,
      slug: json['slug']! as String,
      title: json['title']! as String,
      subtitle: json['subtitle'] as String?,
      locale: json['locale']! as String,
      coverUrl: json['cover_url'] as String?,
      accessLevel: AccessLevel.fromWire(json['access_level'] as String?),
      contributors: [
        for (final c in (json['contributors'] as List?) ?? const <Object?>[])
          Contributor.fromJson(c! as Map<String, Object?>),
      ],
      status: ShelfStatus.fromWire(json['shelf_status'] as String?),
      isFavorite: (json['is_favorite'] as bool?) ?? false,
      addedAt: _date(json['added_at'])!,
      startedAt: _date(json['started_at']),
      finishedAt: _date(json['finished_at']),
      updatedAt: _date(json['updated_at'])!,
      category: category == null ? null : NamedRef.fromJson(category),
      language: json['language'] as String?,
      pageCount: (json['page_count'] as num?)?.toInt(),
      publisher: publisher == null ? null : NamedRef.fromJson(publisher),
      ratingAvg: _decimal(json['rating_avg']),
      ratingCount: (json['rating_count'] as num?)?.toInt() ?? 0,
    );
  }

  final String bookId;
  final String slug;
  final String title;
  final String? subtitle;
  final String locale;
  final String? coverUrl;
  final AccessLevel accessLevel;
  final List<Contributor> contributors;
  final ShelfStatus status;
  final bool isFavorite;
  final DateTime addedAt;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final DateTime updatedAt;

  /// Primary catalog category, resolved to the request locale.
  final NamedRef? category;

  /// Language code of the default edition.
  final String? language;

  /// Page count of the default edition, when the publisher supplied one.
  final int? pageCount;
  final NamedRef? publisher;

  /// Average catalog rating from all readers (0–5); [ratingCount] is 0 when nobody has rated it.
  final double ratingAvg;
  final int ratingCount;

  /// Authors only, in credit order; empty when the catalog lists none.
  List<String> get authorNames => [
    for (final c in contributors)
      if (c.role == 'author') c.name,
  ];

  bool matches(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return true;
    return title.toLowerCase().contains(needle) || authorNames.any((a) => a.toLowerCase().contains(needle));
  }
}

/// A user-made shelf. [bookIds] are in shelf order.
@immutable
class BookCollection {
  const BookCollection({
    required this.id,
    required this.name,
    required this.position,
    required this.bookIds,
    required this.createdAt,
    required this.updatedAt,
    this.description,
  });

  factory BookCollection.fromJson(Map<String, Object?> json) => BookCollection(
    id: json['id']! as String,
    name: json['name']! as String,
    description: json['description'] as String?,
    position: (json['position'] as num?)?.toInt() ?? 0,
    bookIds: [for (final id in (json['book_ids'] as List?) ?? const <Object?>[]) id! as String],
    createdAt: _date(json['created_at'])!,
    updatedAt: _date(json['updated_at'])!,
  );

  final String id;
  final String name;
  final String? description;
  final int position;
  final List<String> bookIds;
  final DateTime createdAt;
  final DateTime updatedAt;

  int get bookCount => bookIds.length;
  bool contains(String bookId) => bookIds.contains(bookId);
}

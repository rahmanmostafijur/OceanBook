import 'package:meta/meta.dart';

/// Catalog value types mirroring the public `/books`, `/categories`, `/authors`, `/publishers`
/// contract (backend `app/catalog/schemas.py`). Text arrives already resolved for the request locale.

T _req<T>(Map<String, Object?> json, String key) => json[key] as T;

List<T> _list<T>(Object? raw, T Function(Map<String, Object?>) decode) => [
  for (final item in (raw as List?) ?? const <Object?>[]) decode(item! as Map<String, Object?>),
];

DateTime? _date(Object? raw) => raw == null ? null : DateTime.parse(raw as String);

enum AccessLevel {
  free,
  registered,
  entitled,
  unknown;

  static AccessLevel fromWire(String? value) =>
      AccessLevel.values.firstWhere((v) => v.name == value, orElse: () => AccessLevel.unknown);
}

/// What the server decided for this caller. The client renders it and never decides access itself.
enum AccessState {
  full,
  previewOnly,
  unavailable;

  static AccessState fromWire(String? value) => switch (value) {
    'full' => AccessState.full,
    'preview_only' => AccessState.previewOnly,
    _ => AccessState.unavailable,
  };
}

/// Reason codes the server attaches to an access decision.
abstract final class AccessReason {
  static const signInRequired = 'SIGN_IN_REQUIRED';
  static const entitlementRequired = 'ENTITLEMENT_REQUIRED';
  static const rightsRestricted = 'RIGHTS_RESTRICTED';
  static const notAvailable = 'NOT_AVAILABLE';
}

@immutable
class BookAccess {
  const BookAccess({
    required this.level,
    required this.state,
    required this.reasons,
    required this.canPreview,
    required this.canRead,
    required this.canDownload,
    required this.readerAvailable,
    this.entitlementKey,
  });

  factory BookAccess.fromJson(Map<String, Object?> json) => BookAccess(
    level: AccessLevel.fromWire(json['level'] as String?),
    state: AccessState.fromWire(json['state'] as String?),
    reasons: [for (final r in (json['reasons'] as List?) ?? const <Object?>[]) '$r'],
    canPreview: (json['can_preview'] as bool?) ?? false,
    canRead: (json['can_read'] as bool?) ?? false,
    canDownload: (json['can_download'] as bool?) ?? false,
    readerAvailable: (json['reader_available'] as bool?) ?? false,
    entitlementKey: (json['acquire'] as Map<String, Object?>?)?['entitlement_key'] as String?,
  );

  final AccessLevel level;
  final AccessState state;
  final List<String> reasons;
  final bool canPreview;
  final bool canRead;
  final bool canDownload;

  /// Server-side feature flag: the reader ships in Phase 4.
  final bool readerAvailable;
  final String? entitlementKey;

  /// The Read action is enabled only when the server allows reading *and* the reader exists.
  bool get readEnabled => canRead && readerAvailable;
  bool get previewEnabled => canPreview && readerAvailable;
  bool get needsSignIn => reasons.contains(AccessReason.signInRequired);
  bool get needsEntitlement => reasons.contains(AccessReason.entitlementRequired);
}

@immutable
class Contributor {
  const Contributor({required this.id, required this.slug, required this.name, required this.role});

  factory Contributor.fromJson(Map<String, Object?> json) => Contributor(
    id: _req(json, 'id'),
    slug: _req(json, 'slug'),
    name: _req(json, 'name'),
    role: _req(json, 'role'),
  );

  final String id;
  final String slug;
  final String name;
  final String role;
}

@immutable
class BookCard {
  const BookCard({
    required this.id,
    required this.slug,
    required this.locale,
    required this.title,
    required this.accessLevel,
    required this.contributors,
    this.subtitle,
    this.coverUrl,
    this.publishedAt,
  });

  factory BookCard.fromJson(Map<String, Object?> json) => BookCard(
    id: _req(json, 'id'),
    slug: _req(json, 'slug'),
    locale: _req(json, 'locale'),
    title: _req(json, 'title'),
    subtitle: json['subtitle'] as String?,
    accessLevel: AccessLevel.fromWire(json['access_level'] as String?),
    contributors: _list(json['contributors'], Contributor.fromJson),
    coverUrl: json['cover_url'] as String?,
    publishedAt: _date(json['published_at']),
  );

  final String id;
  final String slug;

  /// Locale the title was resolved in (may differ from the UI locale when a translation is missing).
  final String locale;
  final String title;
  final String? subtitle;
  final AccessLevel accessLevel;
  final List<Contributor> contributors;
  final String? coverUrl;
  final DateTime? publishedAt;

  Iterable<Contributor> get authors => contributors.where((c) => c.role == 'author');
}

@immutable
class NamedRef {
  const NamedRef({required this.id, required this.slug, required this.name, this.role, this.isPrimary = false});

  factory NamedRef.fromJson(Map<String, Object?> json) => NamedRef(
    id: _req(json, 'id'),
    slug: _req(json, 'slug'),
    name: _req(json, 'name'),
    role: json['role'] as String?,
    isPrimary: (json['is_primary'] as bool?) ?? false,
  );

  final String id;
  final String slug;
  final String name;
  final String? role;
  final bool isPrimary;
}

@immutable
class TocSection {
  const TocSection({required this.id, required this.title, required this.isPreview});

  factory TocSection.fromJson(Map<String, Object?> json) =>
      TocSection(id: _req(json, 'id'), title: _req(json, 'title'), isPreview: (json['is_preview'] as bool?) ?? false);

  final String id;
  final String title;
  final bool isPreview;
}

/// Book -> Edition -> Chapter -> Section: the structure the Phase 4 reader renders.
@immutable
class TocChapter {
  const TocChapter({required this.id, required this.title, required this.isPreview, required this.sections});

  factory TocChapter.fromJson(Map<String, Object?> json) => TocChapter(
    id: _req(json, 'id'),
    title: _req(json, 'title'),
    isPreview: (json['is_preview'] as bool?) ?? false,
    sections: _list(json['sections'], TocSection.fromJson),
  );

  final String id;
  final String title;
  final bool isPreview;
  final List<TocSection> sections;

  bool get hasPreview => isPreview || sections.any((s) => s.isPreview);
}

@immutable
class Edition {
  const Edition({
    required this.id,
    required this.label,
    required this.language,
    required this.publishers,
    this.isbn13,
    this.pageCount,
    this.publicationDate,
  });

  factory Edition.fromJson(Map<String, Object?> json) => Edition(
    id: _req(json, 'id'),
    label: _req(json, 'edition_label'),
    language: _req(json, 'language'),
    isbn13: json['isbn13'] as String?,
    pageCount: json['page_count'] as int?,
    publicationDate: _date(json['publication_date']),
    publishers: _list(json['publishers'], NamedRef.fromJson),
  );

  final String id;
  final String label;
  final String language;
  final String? isbn13;
  final int? pageCount;
  final DateTime? publicationDate;
  final List<NamedRef> publishers;
}

@immutable
class BookDetail {
  const BookDetail({
    required this.card,
    required this.availableLocales,
    required this.categories,
    required this.tags,
    required this.editions,
    required this.toc,
    required this.attributions,
    required this.access,
    this.description,
    this.defaultEditionId,
  });

  factory BookDetail.fromJson(Map<String, Object?> json) => BookDetail(
    card: BookCard.fromJson(json),
    description: json['description'] as String?,
    availableLocales: [for (final l in (json['available_locales'] as List?) ?? const <Object?>[]) '$l'],
    categories: _list(json['categories'], NamedRef.fromJson),
    tags: _list(json['tags'], NamedRef.fromJson),
    editions: _list(json['editions'], Edition.fromJson),
    defaultEditionId: json['default_edition_id'] as String?,
    toc: _list(json['toc'], TocChapter.fromJson),
    attributions: [for (final a in (json['attributions'] as List?) ?? const <Object?>[]) '$a'],
    access: BookAccess.fromJson(json['access']! as Map<String, Object?>),
  );

  final BookCard card;
  final String? description;
  final List<String> availableLocales;
  final List<NamedRef> categories;
  final List<NamedRef> tags;
  final List<Edition> editions;
  final String? defaultEditionId;
  final List<TocChapter> toc;
  final List<String> attributions;
  final BookAccess access;

  Edition? get defaultEdition => editions.where((e) => e.id == defaultEditionId).firstOrNull;
}

@immutable
class CategoryNode {
  const CategoryNode({
    required this.id,
    required this.slug,
    required this.name,
    required this.depth,
    required this.position,
    this.parentId,
    this.icon,
  });

  factory CategoryNode.fromJson(Map<String, Object?> json) => CategoryNode(
    id: _req(json, 'id'),
    slug: _req(json, 'slug'),
    name: _req(json, 'name'),
    depth: _req(json, 'depth'),
    position: _req(json, 'position'),
    parentId: json['parent_id'] as String?,
    icon: json['icon'] as String?,
  );

  final String id;
  final String slug;
  final String name;
  final int depth;
  final int position;
  final String? parentId;
  final String? icon;
}

@immutable
class AuthorProfile {
  const AuthorProfile({required this.id, required this.slug, required this.name, this.nameAlt, this.biography});

  factory AuthorProfile.fromJson(Map<String, Object?> json) => AuthorProfile(
    id: _req(json, 'id'),
    slug: _req(json, 'slug'),
    name: _req(json, 'name'),
    nameAlt: json['name_alt'] as String?,
    biography: json['biography'] as String?,
  );

  final String id;
  final String slug;
  final String name;
  final String? nameAlt;
  final String? biography;
}

/// One page of a keyset-paginated list.
@immutable
class CursorPage<T> {
  const CursorPage({required this.items, this.nextCursor});

  final List<T> items;
  final String? nextCursor;

  bool get hasMore => nextCursor != null;
}

enum BookSort { newest, popular, rating }

@immutable
class BookQuery {
  const BookQuery({
    this.category,
    this.author,
    this.publisher,
    this.language,
    this.access,
    this.search,
    this.sort = BookSort.newest,
  });

  final String? category;
  final String? author;
  final String? publisher;
  final String? language;
  final AccessLevel? access;
  final String? search;
  final BookSort sort;

  BookQuery copyWith({String? category, String? search, BookSort? sort, bool clearCategory = false}) => BookQuery(
    category: clearCategory ? null : (category ?? this.category),
    author: author,
    publisher: publisher,
    language: language,
    access: access,
    search: search ?? this.search,
    sort: sort ?? this.sort,
  );

  Map<String, Object?> toQuery() => {
    'category': category,
    'author': author,
    'publisher': publisher,
    'language': language,
    'access': access?.name,
    // The server requires at least two characters; shorter input means "no search".
    'q': (search?.trim().length ?? 0) >= 2 ? search!.trim() : null,
    'sort': sort.name,
  };

  @override
  bool operator ==(Object other) =>
      other is BookQuery &&
      other.category == category &&
      other.author == author &&
      other.publisher == publisher &&
      other.language == language &&
      other.access == access &&
      other.search == search &&
      other.sort == sort;

  @override
  int get hashCode => Object.hash(category, author, publisher, language, access, search, sort);
}

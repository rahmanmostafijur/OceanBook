import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ob_core/ob_core.dart';

import '../../core/providers.dart';

/// Admin catalog contract (`/admin/books`, `/admin/authors`, ...). The server enforces permissions,
/// the review workflow and the provenance publish gate; this layer only carries requests and results.

T _req<T>(Map<String, Object?> json, String key) => json[key] as T;

List<T> _list<T>(Object? raw, T Function(Map<String, Object?>) decode) => [
  for (final item in (raw as List?) ?? const <Object?>[]) decode(item! as Map<String, Object?>),
];

@immutable
class AdminBookRow {
  const AdminBookRow({
    required this.id,
    required this.slug,
    required this.title,
    required this.status,
    required this.accessLevel,
    required this.editionCount,
    required this.updatedAt,
  });

  factory AdminBookRow.fromJson(Map<String, Object?> json) => AdminBookRow(
    id: _req(json, 'id'),
    slug: _req(json, 'slug'),
    title: _req(json, 'title'),
    status: _req(json, 'status'),
    accessLevel: _req(json, 'access_level'),
    editionCount: _req(json, 'edition_count'),
    updatedAt: DateTime.parse(_req(json, 'updated_at')),
  );

  final String id;
  final String slug;
  final String title;
  final String status;
  final String accessLevel;
  final int editionCount;
  final DateTime updatedAt;
}

@immutable
class AdminTranslation {
  const AdminTranslation({required this.locale, required this.title, required this.status});

  factory AdminTranslation.fromJson(Map<String, Object?> json) =>
      AdminTranslation(locale: _req(json, 'locale'), title: _req(json, 'title'), status: _req(json, 'status'));

  final String locale;
  final String title;
  final String status;
}

@immutable
class AdminEdition {
  const AdminEdition({
    required this.id,
    required this.label,
    required this.language,
    required this.status,
    required this.chapterCount,
    required this.publishable,
    required this.blockReasons,
    this.isbn13,
  });

  factory AdminEdition.fromJson(Map<String, Object?> json) {
    final gate = json['provenance']! as Map<String, Object?>;
    return AdminEdition(
      id: _req(json, 'id'),
      label: _req(json, 'edition_label'),
      language: _req(json, 'language'),
      status: _req(json, 'status'),
      isbn13: json['isbn13'] as String?,
      chapterCount: _req(json, 'chapter_count'),
      publishable: _req(gate, 'publishable'),
      blockReasons: [for (final r in (gate['reasons'] as List?) ?? const <Object?>[]) '$r'],
    );
  }

  final String id;
  final String label;
  final String language;
  final String status;
  final String? isbn13;
  final int chapterCount;

  /// The server's publish-gate verdict for this edition (provenance, rights, window, territory).
  final bool publishable;
  final List<String> blockReasons;
}

@immutable
class AdminBook {
  const AdminBook({
    required this.id,
    required this.slug,
    required this.status,
    required this.accessLevel,
    required this.sourceLocale,
    required this.translations,
    required this.contributors,
    required this.editions,
    this.defaultEditionId,
  });

  factory AdminBook.fromJson(Map<String, Object?> json) => AdminBook(
    id: _req(json, 'id'),
    slug: _req(json, 'slug'),
    status: _req(json, 'status'),
    accessLevel: _req(json, 'access_level'),
    sourceLocale: _req(json, 'source_locale'),
    defaultEditionId: json['default_edition_id'] as String?,
    translations: _list(json['translations'], AdminTranslation.fromJson),
    contributors: [
      for (final c in (json['contributors'] as List?) ?? const <Object?>[]) '${(c! as Map<String, Object?>)['name']}',
    ],
    editions: _list(json['editions'], AdminEdition.fromJson),
  );

  final String id;
  final String slug;
  final String status;
  final String accessLevel;
  final String sourceLocale;
  final String? defaultEditionId;
  final List<AdminTranslation> translations;
  final List<String> contributors;
  final List<AdminEdition> editions;

  String get title =>
      translations.where((t) => t.locale == sourceLocale).firstOrNull?.title ??
      (translations.isEmpty ? slug : translations.first.title);

  AdminEdition? get defaultEdition => editions.where((e) => e.id == defaultEditionId).firstOrNull;
}

@immutable
class AdminPerson {
  const AdminPerson({required this.id, required this.slug, required this.name, this.nameAlt});

  factory AdminPerson.fromJson(Map<String, Object?> json) => AdminPerson(
    id: _req(json, 'id'),
    slug: _req(json, 'slug'),
    name: _req(json, 'name'),
    nameAlt: json['name_alt'] as String?,
  );

  final String id;
  final String slug;
  final String name;
  final String? nameAlt;
}

@immutable
class AdminCategory {
  const AdminCategory({
    required this.id,
    required this.slug,
    required this.path,
    required this.depth,
    required this.name,
    required this.isActive,
  });

  factory AdminCategory.fromJson(Map<String, Object?> json) => AdminCategory(
    id: _req(json, 'id'),
    slug: _req(json, 'slug'),
    path: _req(json, 'path'),
    depth: _req(json, 'depth'),
    name: LocalizedText.fromJson(json['name']),
    isActive: _req(json, 'is_active'),
  );

  final String id;
  final String slug;
  final String path;
  final int depth;
  final LocalizedText name;
  final bool isActive;
}

@immutable
class Paged<T> {
  const Paged({required this.rows, required this.total});

  final List<T> rows;
  final int total;
}

/// Workflow transitions; reason-bearing ones are audited server-side.
enum BookAction {
  submit('submit', needsReason: false),
  requestChanges('request-changes', needsReason: true),
  publish('publish', needsReason: false),
  unpublish('unpublish', needsReason: true),
  archive('archive', needsReason: true);

  const BookAction(this.path, {required this.needsReason});

  final String path;
  final bool needsReason;
}

/// Actions the current status allows. The server re-checks every transition and permission.
List<BookAction> actionsFor(String status) => switch (status) {
  'draft' => const [BookAction.submit, BookAction.archive],
  'in_review' => const [BookAction.publish, BookAction.requestChanges, BookAction.archive],
  'published' => const [BookAction.unpublish, BookAction.archive],
  'unpublished' => const [BookAction.publish, BookAction.archive],
  _ => const [],
};

abstract interface class AdminCatalogRepository {
  Future<Paged<AdminBookRow>> books({String? query, String? status, int page = 1, int pageSize = 25});
  Future<AdminBook> book(String id);
  Future<AdminBook> createBook({
    required String slug,
    required String sourceLocale,
    required String title,
    required String accessLevel,
  });
  Future<AdminBook> transition(String id, BookAction action, {String? reason});
  Future<Paged<AdminPerson>> authors({String? query, int page = 1});
  Future<Paged<AdminPerson>> publishers({String? query, int page = 1});
  Future<List<AdminCategory>> categories();
}

class AdminCatalogApi implements AdminCatalogRepository {
  AdminCatalogApi(this.api);

  final ApiClient api;

  static String? _q(String? query) => (query?.trim().length ?? 0) >= 2 ? query!.trim() : null;

  int _total(ApiResponse<Object?> response, int fallback) {
    final page = response.page;
    return page is OffsetPageMeta ? page.total : fallback;
  }

  AdminBook _book(Object? json) => AdminBook.fromJson(json! as Map<String, Object?>);

  @override
  Future<Paged<AdminBookRow>> books({String? query, String? status, int page = 1, int pageSize = 25}) async {
    final response = await api.get(
      '/admin/books',
      query: {'q': _q(query), 'status': status, 'page': page, 'page_size': pageSize},
      decode: (j) => _list(j, AdminBookRow.fromJson),
    );
    return Paged(rows: response.data, total: _total(response, response.data.length));
  }

  @override
  Future<AdminBook> book(String id) async => (await api.get('/admin/books/$id', decode: _book)).data;

  @override
  Future<AdminBook> createBook({
    required String slug,
    required String sourceLocale,
    required String title,
    required String accessLevel,
  }) async {
    final response = await api.post(
      '/admin/books',
      body: {
        'slug': slug,
        'source_locale': sourceLocale,
        'access_level': accessLevel,
        'required_entitlement_key': accessLevel == 'entitled' ? 'books.premium' : null,
        'translation': {'title': title},
      },
      decode: _book,
    );
    return response.data;
  }

  @override
  Future<AdminBook> transition(String id, BookAction action, {String? reason}) async {
    final response = await api.post(
      '/admin/books/$id/${action.path}',
      body: action.needsReason ? {'reason': reason} : null,
      decode: _book,
    );
    return response.data;
  }

  @override
  Future<Paged<AdminPerson>> authors({String? query, int page = 1}) => _people('/admin/authors', query, page);

  @override
  Future<Paged<AdminPerson>> publishers({String? query, int page = 1}) => _people('/admin/publishers', query, page);

  Future<Paged<AdminPerson>> _people(String path, String? query, int page) async {
    final response = await api.get(
      path,
      query: {'q': _q(query), 'page': page, 'page_size': 50},
      decode: (j) => _list(j, AdminPerson.fromJson),
    );
    return Paged(rows: response.data, total: _total(response, response.data.length));
  }

  @override
  Future<List<AdminCategory>> categories() async =>
      (await api.get('/admin/categories', decode: (j) => _list(j, AdminCategory.fromJson))).data;
}

final adminCatalogRepositoryProvider = Provider<AdminCatalogRepository>(
  (ref) => AdminCatalogApi(ref.watch(adminApiProvider)),
);

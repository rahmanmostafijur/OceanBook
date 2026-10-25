import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ob_core/ob_core.dart';

import '../../core/providers.dart';

/// The reference lists the curriculum is built on (`/admin/academics`). The server enforces
/// `academics.manage` and every rule about keys and years; this layer only carries requests and results.
enum SetupKind {
  levels('levels'),
  groups('groups'),
  curricula('curricula'),
  boards('boards'),
  media('instruction-media');

  const SetupKind(this.path);

  final String path;

  /// Levels, boards and media can be archived; groups and curricula cannot.
  bool get canArchive => this == levels || this == boards || this == media;
}

const boardTypes = ['general', 'madrasah', 'technical'];
const contentLocales = ['bn', 'en'];

/// One row of any of the lists; the fields that do not apply to its kind stay null.
@immutable
class SetupEntry {
  const SetupEntry({
    required this.id,
    required this.key,
    required this.name,
    this.isActive = true,
    this.position,
    this.boardType,
    this.contentLocale,
    this.effectiveFromYear,
    this.effectiveToYear,
    this.isCurrent = false,
    this.levelId,
  });

  factory SetupEntry.fromJson(Map<String, Object?> json) => SetupEntry(
    id: json['id']! as String,
    key: json['key']! as String,
    name: LocalizedText.fromJson(json['name']),
    isActive: json['is_active'] as bool? ?? true,
    position: json['position'] as int?,
    boardType: json['board_type'] as String?,
    contentLocale: json['content_locale'] as String?,
    effectiveFromYear: json['effective_from_year'] as int?,
    effectiveToYear: json['effective_to_year'] as int?,
    isCurrent: json['is_current'] as bool? ?? false,
    levelId: json['education_level_id'] as String?,
  );

  final String id;
  final String key;
  final LocalizedText name;
  final bool isActive;
  final int? position;
  final String? boardType;
  final String? contentLocale;
  final int? effectiveFromYear;
  final int? effectiveToYear;
  final bool isCurrent;
  final String? levelId;
}

/// What the form edits. The fields a kind does not use are ignored.
@immutable
class SetupFields {
  const SetupFields({
    required this.name,
    this.position = 0,
    this.boardType = 'general',
    this.contentLocale = 'bn',
    this.effectiveFromYear,
    this.effectiveToYear,
    this.isCurrent = false,
  });

  final LocalizedText name;
  final int position;
  final String boardType;
  final String contentLocale;
  final int? effectiveFromYear;
  final int? effectiveToYear;
  final bool isCurrent;

  Map<String, Object?> toJson(SetupKind kind) => {
    'name': name.values,
    ...switch (kind) {
      SetupKind.levels => {'position': position},
      SetupKind.groups => const <String, Object?>{},
      SetupKind.curricula => {
        'effective_from_year': effectiveFromYear,
        'effective_to_year': effectiveToYear,
        'is_current': isCurrent,
      },
      SetupKind.boards => {'board_type': boardType},
      SetupKind.media => {'content_locale': contentLocale},
    },
  };
}

abstract interface class AcademicSetupRepository {
  /// Groups belong to a level; the other kinds ignore [levelId].
  Future<List<SetupEntry>> list(SetupKind kind, {String? levelId});

  /// [key] cannot be changed afterwards; [levelId] is required for groups.
  Future<void> create(SetupKind kind, {required String key, required SetupFields fields, String? levelId});
  Future<void> update(SetupKind kind, String id, {SetupFields? fields, bool? isActive});
}

class AcademicSetupApi implements AcademicSetupRepository {
  AcademicSetupApi(this.api);

  final ApiClient api;

  static Object? _ignore(Object? json) => null;

  @override
  Future<List<SetupEntry>> list(SetupKind kind, {String? levelId}) async => (await api.get(
    '/admin/academics/${kind.path}',
    query: {if (kind == SetupKind.groups && levelId != null) 'education_level_id': levelId},
    decode: (j) => [for (final o in j! as List) SetupEntry.fromJson(o! as Map<String, Object?>)],
  )).data;

  @override
  Future<void> create(
    SetupKind kind, {
    required String key,
    required SetupFields fields,
    String? levelId,
  }) async {
    await api.post(
      '/admin/academics/${kind.path}',
      body: {'key': key, if (kind == SetupKind.groups) 'education_level_id': levelId, ...fields.toJson(kind)},
      decode: _ignore,
    );
  }

  @override
  Future<void> update(SetupKind kind, String id, {SetupFields? fields, bool? isActive}) async {
    await api.patch(
      '/admin/academics/${kind.path}/$id',
      body: {if (fields != null) ...fields.toJson(kind), 'is_active': ?isActive},
      decode: _ignore,
    );
  }
}

final academicSetupRepositoryProvider = Provider<AcademicSetupRepository>(
  (ref) => AcademicSetupApi(ref.watch(adminApiProvider)),
);

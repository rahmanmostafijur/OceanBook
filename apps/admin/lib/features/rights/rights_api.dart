import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ob_core/ob_core.dart';

import '../../core/providers.dart';

/// Content sources and provenance (`/admin/content-sources`, `/admin/provenance/*`). The server enforces
/// the two-person rule and the publish gate; this layer only carries requests and results.

T _req<T>(Map<String, Object?> json, String key) => json[key] as T;

List<T> _list<T>(Object? raw, T Function(Map<String, Object?>) decode) => [
  for (final item in (raw as List?) ?? const <Object?>[]) decode(item! as Map<String, Object?>),
];

const sourceKinds = [
  'education_board',
  'publisher',
  'author',
  'government',
  'website',
  'partner',
  'internal',
  'other',
];

const licenseTypes = [
  'licensed_commercial',
  'permission_granted',
  'public_domain',
  'government_open',
  'cc_by',
  'cc_by_sa',
  'cc_by_nc',
  'original_work',
  'unknown',
];

const rightsStatuses = ['pending', 'cleared', 'restricted', 'expired', 'disputed', 'public_domain'];

/// Narrowing changes a verifier may apply to verified records (server: `RightsChangeIn`).
const narrowingRights = ['restricted', 'expired', 'disputed'];

@immutable
class ContentSource {
  const ContentSource({
    required this.id,
    required this.kind,
    required this.name,
    required this.isActive,
    this.websiteUrl,
    this.contact,
  });

  factory ContentSource.fromJson(Map<String, Object?> json) => ContentSource(
    id: _req(json, 'id'),
    kind: _req(json, 'kind'),
    name: LocalizedText.fromJson(json['name']),
    isActive: _req(json, 'is_active'),
    websiteUrl: json['website_url'] as String?,
    contact: json['contact'] as String?,
  );

  final String id;
  final String kind;
  final LocalizedText name;
  final bool isActive;
  final String? websiteUrl;
  final String? contact;
}

@immutable
class ProvenanceRecord {
  const ProvenanceRecord({
    required this.id,
    required this.subjectId,
    required this.sourceId,
    required this.licenseType,
    required this.rightsStatus,
    required this.verificationStatus,
    required this.territories,
    required this.excludedTerritories,
    this.sourceUrl,
    this.licenseReference,
    this.validFrom,
    this.validUntil,
    this.verificationNotes,
    this.createdBy,
    this.updatedBy,
    this.submittedAt,
  });

  factory ProvenanceRecord.fromJson(Map<String, Object?> json) => ProvenanceRecord(
    id: _req(json, 'id'),
    subjectId: _req(json, 'subject_id'),
    sourceId: _req(json, 'source_id'),
    licenseType: _req(json, 'license_type'),
    rightsStatus: _req(json, 'rights_status'),
    verificationStatus: _req(json, 'verification_status'),
    territories: [for (final t in (json['territories'] as List?) ?? const <Object?>[]) '$t'],
    excludedTerritories: [for (final t in (json['excluded_territories'] as List?) ?? const <Object?>[]) '$t'],
    sourceUrl: json['source_url'] as String?,
    licenseReference: json['license_reference'] as String?,
    validFrom: _date(json['valid_from']),
    validUntil: _date(json['valid_until']),
    verificationNotes: json['verification_notes'] as String?,
    createdBy: json['created_by'] as String?,
    updatedBy: json['updated_by'] as String?,
    submittedAt: _date(json['submitted_at']),
  );

  static DateTime? _date(Object? raw) => raw == null ? null : DateTime.parse('$raw');

  final String id;
  final String subjectId;
  final String sourceId;
  final String licenseType;
  final String rightsStatus;
  final String verificationStatus;
  final List<String> territories;
  final List<String> excludedTerritories;
  final String? sourceUrl;
  final String? licenseReference;
  final DateTime? validFrom;
  final DateTime? validUntil;
  final String? verificationNotes;
  final String? createdBy;
  final String? updatedBy;
  final DateTime? submittedAt;

  bool get isVerified => verificationStatus == 'verified';
  bool get isPending => verificationStatus == 'pending';

  /// Records may be edited and submitted only while the server still treats them as drafts.
  bool get isEditable => verificationStatus == 'unverified' || verificationStatus == 'rejected';

  /// The two-person rule from the client's side: the decider must be neither author nor last editor.
  /// Only used to explain a disabled button; the server is the authority (403 SELF_VERIFICATION_FORBIDDEN).
  bool touchedBy(String userId) => createdBy == userId || updatedBy == userId;
}

/// New provenance for an edition. Dates are sent as ISO `yyyy-MM-dd`.
@immutable
class NewProvenance {
  const NewProvenance({
    required this.sourceId,
    required this.licenseType,
    required this.rightsStatus,
    required this.territories,
    this.sourceUrl,
    this.licenseReference,
    this.validFrom,
    this.validUntil,
  });

  final String sourceId;
  final String licenseType;
  final String rightsStatus;
  final List<String> territories;
  final String? sourceUrl;
  final String? licenseReference;
  final DateTime? validFrom;
  final DateTime? validUntil;

  static String _iso(DateTime d) => d.toIso8601String().substring(0, 10);

  Map<String, Object?> toJson() => {
    'source_id': sourceId,
    'license_type': licenseType,
    'rights_status': rightsStatus,
    'territories': territories,
    'source_url': ?sourceUrl,
    'license_reference': ?licenseReference,
    if (validFrom != null) 'valid_from': _iso(validFrom!),
    if (validUntil != null) 'valid_until': _iso(validUntil!),
  };
}

abstract interface class RightsRepository {
  Future<List<ContentSource>> sources({bool includeInactive = true});
  Future<ContentSource> createSource({required String kind, required Map<String, String> name, String? websiteUrl});
  Future<ContentSource> setSourceActive(String id, {required bool isActive});
  Future<List<ProvenanceRecord>> queue({int page = 1});
  Future<List<ProvenanceRecord>> forEdition(String editionId);
  Future<ProvenanceRecord> record(String editionId, NewProvenance provenance);
  Future<ProvenanceRecord> submit(String recordId);
  Future<ProvenanceRecord> decide(String recordId, {required bool verified, String? notes});
  Future<ProvenanceRecord> narrow(String recordId, {required String rightsStatus, required String reason});
}

class RightsApi implements RightsRepository {
  RightsApi(this.api);

  final ApiClient api;

  ContentSource _source(Object? json) => ContentSource.fromJson(json! as Map<String, Object?>);

  ProvenanceRecord _record(Object? json) => ProvenanceRecord.fromJson(json! as Map<String, Object?>);

  @override
  Future<List<ContentSource>> sources({bool includeInactive = true}) async => (await api.get(
    '/admin/content-sources',
    query: {'include_inactive': includeInactive},
    decode: (j) => _list(j, ContentSource.fromJson),
  )).data;

  @override
  Future<ContentSource> createSource({
    required String kind,
    required Map<String, String> name,
    String? websiteUrl,
  }) async => (await api.post(
    '/admin/content-sources',
    body: {'kind': kind, 'name': name, 'website_url': ?websiteUrl},
    decode: _source,
  )).data;

  @override
  Future<ContentSource> setSourceActive(String id, {required bool isActive}) async =>
      (await api.patch('/admin/content-sources/$id', body: {'is_active': isActive}, decode: _source)).data;

  @override
  Future<List<ProvenanceRecord>> queue({int page = 1}) async => (await api.get(
    '/admin/provenance/queue',
    query: {'page': page, 'page_size': 50},
    decode: (j) => _list(j, ProvenanceRecord.fromJson),
  )).data;

  @override
  Future<List<ProvenanceRecord>> forEdition(String editionId) async => (await api.get(
    '/admin/editions/$editionId/provenance',
    decode: (j) => _list(j, ProvenanceRecord.fromJson),
  )).data;

  @override
  Future<ProvenanceRecord> record(String editionId, NewProvenance provenance) async =>
      (await api.post('/admin/editions/$editionId/provenance', body: provenance.toJson(), decode: _record)).data;

  @override
  Future<ProvenanceRecord> submit(String recordId) async =>
      (await api.post('/admin/provenance/$recordId/submit', decode: _record)).data;

  @override
  Future<ProvenanceRecord> decide(String recordId, {required bool verified, String? notes}) async => (await api.post(
    '/admin/provenance/$recordId/decision',
    body: {'decision': verified ? 'verified' : 'rejected', 'notes': ?notes},
    decode: _record,
  )).data;

  @override
  Future<ProvenanceRecord> narrow(String recordId, {required String rightsStatus, required String reason}) async =>
      (await api.post(
        '/admin/provenance/$recordId/rights-status',
        body: {'rights_status': rightsStatus, 'reason': reason},
        decode: _record,
      )).data;
}

final rightsRepositoryProvider = Provider<RightsRepository>((ref) => RightsApi(ref.watch(adminApiProvider)));

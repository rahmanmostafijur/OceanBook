import 'package:ob_core/ob_core.dart';
import 'package:oceanbook_admin/features/rights/rights_api.dart';

ProvenanceRecord fakeRecord({
  String id = 'r1',
  String createdBy = 'author-1',
  String updatedBy = 'author-1',
  String verification = 'pending',
}) => ProvenanceRecord(
  id: id,
  subjectId: 'e1',
  sourceId: 'src1',
  licenseType: 'licensed_commercial',
  rightsStatus: 'cleared',
  verificationStatus: verification,
  territories: const ['BD'],
  excludedTerritories: const [],
  validFrom: DateTime.utc(2026),
  validUntil: DateTime.utc(2027),
  createdBy: createdBy,
  updatedBy: updatedBy,
);

/// Scripted rights repository: records calls and can fail decisions the way the server does.
class FakeRights implements RightsRepository {
  FakeRights({List<ProvenanceRecord>? queued}) : queued = queued ?? [fakeRecord()];

  List<ProvenanceRecord> queued;

  /// Records returned for any edition.
  List<ProvenanceRecord> edition = [];
  Object? decideError;
  final List<String> calls = [];

  final List<ContentSource> _sources = [
    const ContentSource(
      id: 'src1',
      kind: 'publisher',
      name: LocalizedText({'bn': 'অন্যপ্রকাশ', 'en': 'Anyaprokash'}),
      isActive: true,
    ),
  ];

  @override
  Future<List<ContentSource>> sources({bool includeInactive = true}) async => List.of(_sources);

  @override
  Future<ContentSource> createSource({
    required String kind,
    required Map<String, String> name,
    String? websiteUrl,
  }) async {
    calls.add('create-source:$kind:${name.entries.map((e) => '${e.key}=${e.value}').join(',')}:${websiteUrl ?? ''}');
    final source = ContentSource(
      id: 'src${_sources.length + 1}',
      kind: kind,
      name: LocalizedText(name),
      isActive: true,
    );
    _sources.add(source);
    return source;
  }

  @override
  Future<ContentSource> setSourceActive(String id, {required bool isActive}) async {
    calls.add('active:$id:$isActive');
    final index = _sources.indexWhere((s) => s.id == id);
    final old = _sources[index];
    return _sources[index] = ContentSource(id: id, kind: old.kind, name: old.name, isActive: isActive);
  }

  @override
  Future<List<ProvenanceRecord>> queue({int page = 1}) async => List.of(queued);

  @override
  Future<ProvenanceRecord> decide(String recordId, {required bool verified, String? notes}) async {
    calls.add('decide:$recordId:${verified ? 'verified' : 'rejected'}:${notes ?? ''}');
    final error = decideError;
    if (error != null) throw error;
    final decided = queued.firstWhere((r) => r.id == recordId);
    queued = [
      for (final r in queued)
        if (r.id != recordId) r,
    ];
    return decided;
  }

  @override
  Future<List<ProvenanceRecord>> forEdition(String editionId) async => List.of(edition);

  @override
  Future<ProvenanceRecord> record(String editionId, NewProvenance provenance) async {
    calls.add('record:$editionId:${provenance.sourceId}:${provenance.licenseType}:${provenance.territories.join('+')}');
    return fakeRecord(id: 'new');
  }

  @override
  Future<ProvenanceRecord> submit(String recordId) async {
    calls.add('submit:$recordId');
    return fakeRecord(id: recordId);
  }

  @override
  Future<ProvenanceRecord> narrow(String recordId, {required String rightsStatus, required String reason}) async {
    calls.add('narrow:$recordId:$rightsStatus:$reason');
    return fakeRecord(id: recordId);
  }
}

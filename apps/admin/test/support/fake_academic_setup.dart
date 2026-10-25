import 'package:ob_core/ob_core.dart';
import 'package:oceanbook_admin/features/academics/academic_setup_api.dart';

/// In-memory reference lists; records writes and can fail them the way the server does.
class FakeAcademicSetup implements AcademicSetupRepository {
  FakeAcademicSetup() {
    entries = {
      SetupKind.levels: [
        const SetupEntry(
          id: 'l1',
          key: 'hsc',
          name: LocalizedText({'bn': 'এইচএসসি', 'en': 'HSC'}),
          position: 2,
        ),
        const SetupEntry(
          id: 'l0',
          key: 'ssc',
          name: LocalizedText({'bn': 'এসএসসি', 'en': 'SSC'}),
          position: 1,
        ),
      ],
      SetupKind.groups: [
        const SetupEntry(
          id: 'g1',
          key: 'science',
          name: LocalizedText({'bn': 'বিজ্ঞান', 'en': 'Science'}),
          levelId: 'l1',
        ),
      ],
      SetupKind.curricula: [
        const SetupEntry(
          id: 'c1',
          key: 'nctb_2012',
          name: LocalizedText({'bn': 'এনসিটিবি ২০১২', 'en': 'NCTB 2012'}),
          effectiveFromYear: 2012,
          isCurrent: true,
        ),
      ],
      SetupKind.boards: [
        const SetupEntry(
          id: 'b1',
          key: 'dhaka',
          name: LocalizedText({'bn': 'ঢাকা', 'en': 'Dhaka'}),
          boardType: 'general',
        ),
      ],
      SetupKind.media: [
        const SetupEntry(
          id: 'm1',
          key: 'bangla',
          name: LocalizedText({'bn': 'বাংলা', 'en': 'Bangla medium'}),
          contentLocale: 'bn',
        ),
      ],
    };
  }

  late Map<SetupKind, List<SetupEntry>> entries;
  Object? writeError;
  final List<String> calls = [];

  /// What the last create or update sent.
  Map<String, Object?>? lastBody;

  @override
  Future<List<SetupEntry>> list(SetupKind kind, {String? levelId}) async {
    calls.add('list:${kind.name}:${levelId ?? ''}');
    return [
      for (final e in entries[kind]!)
        if (kind != SetupKind.groups || levelId == null || e.levelId == levelId) e,
    ];
  }

  @override
  Future<void> create(SetupKind kind, {required String key, required SetupFields fields, String? levelId}) async {
    if (writeError != null) throw writeError!;
    calls.add('create:${kind.name}:$key:${levelId ?? ''}');
    lastBody = {'key': key, ...fields.toJson(kind)};
    entries[kind] = [
      ...entries[kind]!,
      SetupEntry(id: 'new-$key', key: key, name: fields.name, levelId: levelId),
    ];
  }

  @override
  Future<void> update(SetupKind kind, String id, {SetupFields? fields, bool? isActive}) async {
    if (writeError != null) throw writeError!;
    calls.add('update:${kind.name}:$id:${isActive ?? ''}');
    lastBody = {if (fields != null) ...fields.toJson(kind), 'is_active': ?isActive};
    entries[kind] = [
      for (final e in entries[kind]!)
        if (e.id == id)
          SetupEntry(
            id: e.id,
            key: e.key,
            name: fields?.name ?? e.name,
            isActive: isActive ?? e.isActive,
            position: e.position,
            boardType: e.boardType,
            contentLocale: e.contentLocale,
            effectiveFromYear: fields?.effectiveFromYear ?? e.effectiveFromYear,
            effectiveToYear: e.effectiveToYear,
            isCurrent: e.isCurrent,
            levelId: e.levelId,
          )
        else
          e,
    ];
  }
}

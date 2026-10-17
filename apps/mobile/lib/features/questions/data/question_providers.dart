import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ob_core/ob_core.dart';

import '../../../core/network/api_providers.dart';
import '../../../core/settings/app_settings.dart';
import '../../auth/presentation/auth_controller.dart';

final questionRepositoryProvider = Provider<QuestionRepository>(
  (ref) => QuestionApi(ref.watch(apiClientProvider), locale: ref.watch(localeProvider).languageCode),
);

/// Taxonomy labels are localized and questions follow the caller's access: reload on language or
/// identity changes.
void _watchContext(Ref ref) {
  ref.watch(localeProvider);
  ref.watch(authControllerProvider.select((s) => s.value is AuthSignedIn ? (s.value! as AuthSignedIn).user.id : null));
}

final educationLevelsProvider = FutureProvider.autoDispose<List<EducationLevelRef>>((ref) {
  ref.watch(localeProvider);
  return ref.watch(questionRepositoryProvider).levels();
});

final boardsProvider = FutureProvider.autoDispose<List<BoardRef>>((ref) {
  ref.watch(localeProvider);
  return ref.watch(questionRepositoryProvider).boards();
});

final subjectsProvider = FutureProvider.autoDispose.family<List<SubjectRef>, String>((ref, levelId) {
  ref.watch(localeProvider);
  return ref.watch(questionRepositoryProvider).subjects(levelId: levelId);
});

final chaptersProvider = FutureProvider.autoDispose.family<List<ChapterRef>, String>((ref, subjectId) {
  ref.watch(localeProvider);
  return ref.watch(questionRepositoryProvider).chapters(subjectId);
});

final questionDetailProvider = FutureProvider.autoDispose.family<QuestionDetail, String>((ref, id) {
  _watchContext(ref);
  return ref.watch(questionRepositoryProvider).question(id);
});

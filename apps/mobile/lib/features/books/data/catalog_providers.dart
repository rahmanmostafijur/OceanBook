import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ob_core/ob_core.dart';

import '../../../core/network/api_providers.dart';
import '../../../core/settings/app_settings.dart';
import '../../auth/presentation/auth_controller.dart';

final catalogRepositoryProvider = Provider<CatalogRepository>((ref) => CatalogApi(ref.watch(apiClientProvider)));

/// Rebuild catalog reads when the language or the signed-in identity changes: titles are localized
/// and the `access` block is personalised by the server.
void _watchContext(Ref ref) {
  ref.watch(localeProvider);
  ref.watch(authControllerProvider.select((s) => s.value is AuthSignedIn ? (s.value! as AuthSignedIn).user.id : null));
}

final bookDetailProvider = FutureProvider.autoDispose.family<BookDetail, String>((ref, idOrSlug) {
  _watchContext(ref);
  return ref.watch(catalogRepositoryProvider).book(idOrSlug);
});

final categoriesProvider = FutureProvider.autoDispose<List<CategoryNode>>((ref) {
  ref.watch(localeProvider);
  return ref.watch(catalogRepositoryProvider).categories();
});

final authorProvider = FutureProvider.autoDispose.family<AuthorProfile, String>((ref, slug) {
  ref.watch(localeProvider);
  return ref.watch(catalogRepositoryProvider).author(slug);
});

/// A short, single-page rail (home "popular", an author's books).
final bookRailProvider = FutureProvider.autoDispose.family<List<BookCard>, BookQuery>((ref, query) async {
  _watchContext(ref);
  return (await ref.watch(catalogRepositoryProvider).books(query, limit: 12)).items;
});

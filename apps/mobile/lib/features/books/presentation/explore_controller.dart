import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ob_core/ob_core.dart';

import '../../../core/settings/app_settings.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/catalog_providers.dart';

@immutable
class ExploreState {
  const ExploreState({
    this.query = const BookQuery(),
    this.items = const [],
    this.nextCursor,
    this.loadingMore = false,
    this.loadMoreError,
  });

  final BookQuery query;
  final List<BookCard> items;
  final String? nextCursor;
  final bool loadingMore;
  final Object? loadMoreError;

  bool get hasMore => nextCursor != null;

  ExploreState copyWith({
    List<BookCard>? items,
    String? nextCursor,
    bool clearCursor = false,
    bool? loadingMore,
    Object? loadMoreError,
    bool clearError = false,
  }) => ExploreState(
    query: query,
    items: items ?? this.items,
    nextCursor: clearCursor ? null : (nextCursor ?? this.nextCursor),
    loadingMore: loadingMore ?? this.loadingMore,
    loadMoreError: clearError ? null : (loadMoreError ?? this.loadMoreError),
  );
}

/// Explore listing: the query (search, category, sort) and keyset pages. Filtering happens on the
/// server; this controller only asks for pages and appends them.
class ExploreController extends AsyncNotifier<ExploreState> {
  BookQuery _query = const BookQuery();

  @override
  Future<ExploreState> build() async {
    // Titles are localized and access is personalised: reload on language or identity changes.
    ref
      ..watch(catalogRepositoryProvider)
      ..watch(localeProvider)
      ..watch(authControllerProvider.select((s) => s.value is AuthSignedIn));
    return _firstPage(_query);
  }

  Future<ExploreState> _firstPage(BookQuery query) async {
    final page = await ref.read(catalogRepositoryProvider).books(query);
    return ExploreState(query: query, items: page.items, nextCursor: page.nextCursor);
  }

  Future<void> _reload(BookQuery query) async {
    if (query == _query && state.hasValue) return;
    _query = query;
    state = const AsyncLoading<ExploreState>();
    state = await AsyncValue.guard(() => _firstPage(query));
  }

  Future<void> search(String text) => _reload(_query.copyWith(search: text.trim()));

  Future<void> selectCategory(String? slug) =>
      _reload(slug == null ? _query.copyWith(clearCategory: true) : _query.copyWith(category: slug));

  Future<void> sortBy(BookSort sort) => _reload(_query.copyWith(sort: sort));

  Future<void> refresh() async {
    state = await AsyncValue.guard(() => _firstPage(_query));
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) return;
    state = AsyncData(current.copyWith(loadingMore: true, clearError: true));
    try {
      final page = await ref.read(catalogRepositoryProvider).books(current.query, cursor: current.nextCursor);
      if (current.query != _query) return; // the query changed while this page was loading
      state = AsyncData(
        current.copyWith(
          items: [...current.items, ...page.items],
          nextCursor: page.nextCursor,
          clearCursor: page.nextCursor == null,
          loadingMore: false,
        ),
      );
    } on Object catch (error) {
      state = AsyncData(current.copyWith(loadingMore: false, loadMoreError: error));
    }
  }
}

final exploreControllerProvider = AsyncNotifierProvider<ExploreController, ExploreState>(ExploreController.new);

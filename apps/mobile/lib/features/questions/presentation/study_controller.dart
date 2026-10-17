import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ob_core/ob_core.dart';

import '../../../core/settings/app_settings.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/question_providers.dart';

@immutable
class StudyState {
  const StudyState({
    required this.query,
    this.items = const [],
    this.nextCursor,
    this.loadingMore = false,
    this.loadMoreError,
    this.reloading = false,
  });

  final QuestionQuery query;
  final List<QuestionCard> items;
  final String? nextCursor;
  final bool loadingMore;
  final Object? loadMoreError;

  /// A new first page is loading; the previous items and the new filters stay on screen meanwhile.
  final bool reloading;

  bool get hasMore => nextCursor != null;

  StudyState copyWith({
    List<QuestionCard>? items,
    String? nextCursor,
    bool clearCursor = false,
    bool? loadingMore,
    Object? loadMoreError,
    bool clearError = false,
  }) => StudyState(
    query: query,
    items: items ?? this.items,
    nextCursor: clearCursor ? null : (nextCursor ?? this.nextCursor),
    loadingMore: loadingMore ?? this.loadingMore,
    loadMoreError: clearError ? null : (loadMoreError ?? this.loadMoreError),
  );
}

/// The study question list: the filters and keyset pages. Filtering happens on the server; this
/// controller only asks for pages and appends them.
class StudyController extends AsyncNotifier<StudyState> {
  QuestionQuery? _query;

  @override
  Future<StudyState> build() async {
    ref
      ..watch(questionRepositoryProvider)
      ..watch(localeProvider)
      ..watch(authControllerProvider.select((s) => s.value is AuthSignedIn));
    var query = _query;
    if (query == null) {
      // First visit: start at the first education level (SSC) so the list is never mixed across levels.
      final levels = await ref.watch(educationLevelsProvider.future);
      query = QuestionQuery(levelId: levels.isEmpty ? null : levels.first.id);
      _query = query;
    }
    return _firstPage(query);
  }

  Future<StudyState> _firstPage(QuestionQuery query) async {
    final page = await ref.read(questionRepositoryProvider).questions(query);
    return StudyState(query: query, items: page.items, nextCursor: page.nextCursor);
  }

  Future<void> _reload(QuestionQuery query) async {
    if (query == _query && state.hasValue) return;
    _query = query;
    // Keep what is on screen (the filter chips in particular) while the new list loads.
    final previous = state.value;
    if (previous != null) {
      state = AsyncData(
        StudyState(query: query, items: previous.items, nextCursor: previous.nextCursor, reloading: true),
      );
    } else {
      state = const AsyncLoading<StudyState>();
    }
    state = await AsyncValue.guard(() => _firstPage(query));
  }

  QuestionQuery get _current => _query ?? const QuestionQuery();

  /// A different level means different subjects: every other filter is dropped.
  Future<void> selectLevel(String levelId) => _reload(QuestionQuery(levelId: levelId));

  Future<void> search(String text) => _reload(_current.copyWith(search: text.trim()));

  Future<void> selectSubject(String? id) =>
      _reload(id == null ? _current.copyWith(clearSubject: true) : _current.copyWith(subjectId: id));

  Future<void> selectChapter(String? id) =>
      _reload(id == null ? _current.copyWith(clearChapter: true) : _current.copyWith(chapterId: id));

  Future<void> selectType(QuestionType? type) =>
      _reload(type == null ? _current.copyWith(clearType: true) : _current.copyWith(type: type));

  Future<void> selectDifficulty(int? level) =>
      _reload(level == null ? _current.copyWith(clearDifficulty: true) : _current.copyWith(difficulty: level));

  Future<void> selectBoard(String? id) =>
      _reload(id == null ? _current.copyWith(clearBoard: true) : _current.copyWith(boardId: id));

  Future<void> selectYear(int? year) =>
      _reload(year == null ? _current.copyWith(clearYear: true) : _current.copyWith(year: year));

  Future<void> clearFilters() => _reload(QuestionQuery(levelId: _current.levelId));

  Future<void> refresh() async {
    state = await AsyncValue.guard(() => _firstPage(_current));
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) return;
    state = AsyncData(current.copyWith(loadingMore: true, clearError: true));
    try {
      final page = await ref.read(questionRepositoryProvider).questions(current.query, cursor: current.nextCursor);
      if (current.query != _query) return; // the filters changed while this page was loading
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

final studyControllerProvider = AsyncNotifierProvider<StudyController, StudyState>(StudyController.new);

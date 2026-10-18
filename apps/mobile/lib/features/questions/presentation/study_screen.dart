import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ob_core/ob_core.dart';
import 'package:ob_l10n/ob_l10n.dart';

import '../../../core/errors/failure_messages.dart';
import '../data/question_providers.dart';
import 'question_labels.dart';
import 'study_controller.dart';

const _searchDebounce = Duration(milliseconds: 350);
const _loadMoreExtent = 600.0;
const _firstYear = 2010;
const _largeTextScale = 1.5;

/// Study: the SSC/HSC question bank. Pick a level, narrow by subject, chapter, type, difficulty, board
/// and year; every filter is applied by the server, and pages load as you scroll.
class StudyScreen extends ConsumerStatefulWidget {
  const StudyScreen({super.key});

  @override
  ConsumerState<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends ConsumerState<StudyScreen> {
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.extentAfter < _loadMoreExtent) {
      ref.read(studyControllerProvider.notifier).loadMore();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    final study = ref.watch(studyControllerProvider);
    final controller = ref.read(studyControllerProvider.notifier);
    final gutter = AppSpacing.gutter(MediaQuery.sizeOf(context).width);
    final query = study.value?.query;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.studyTitle)),
      body: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: RefreshIndicator(
          onRefresh: controller.refresh,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: ConstrainedContent(
                  maxWidth: AppSizes.maxReadableWidth,
                  child: Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: _LevelSwitch(selectedId: query?.levelId, onSelected: controller.selectLevel),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(gutter, AppSpacing.sm, gutter, AppSpacing.xs),
                  child: AppSearchBar(
                    fieldKey: const Key('study-search'),
                    hintText: l10n.searchHint,
                    onChanged: (text) {
                      _debounce?.cancel();
                      _debounce = Timer(_searchDebounce, () => controller.search(text));
                    },
                    onSubmitted: controller.search,
                  ),
                ),
              ),
              if (query != null) SliverToBoxAdapter(child: _FilterBar(query: query)),
              if (study.value?.reloading ?? false)
                SliverToBoxAdapter(child: PageLoading.linear(semanticLabel: l10n.commonLoading)),
              ..._results(context, l10n, study, controller),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _results(
    BuildContext context,
    ObLocalizations l10n,
    AsyncValue<StudyState> study,
    StudyController controller,
  ) {
    final gutter = AppSpacing.gutter(MediaQuery.sizeOf(context).width);
    return switch (study) {
      AsyncData(:final value) when value.items.isEmpty => [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            icon: Icons.quiz_outlined,
            title: l10n.emptyQuestions,
            message: l10n.emptyQuestionsHint,
            action: value.query.hasNarrowingFilters
                ? FilledButton.tonal(onPressed: controller.clearFilters, child: Text(l10n.filterClear))
                : null,
          ),
        ),
      ],
      AsyncValue(:final value?) => [
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: gutter),
          sliver: SliverList.separated(
            itemCount: value.items.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.xs),
            itemBuilder: (_, index) => Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: AppSizes.maxReadableWidth),
                child: _QuestionTile(question: value.items[index]),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: _Footer(state: value, onRetry: controller.loadMore),
        ),
      ],
      AsyncError(:final error) => [
        SliverFillRemaining(
          hasScrollBody: false,
          child: ErrorState(
            title: l10n.errorTitle,
            message: failureMessage(l10n, error),
            retryLabel: l10n.actionRetry,
            onRetry: controller.refresh,
          ),
        ),
      ],
      _ => [
        SliverFillRemaining(
          hasScrollBody: false,
          child: PageLoading(semanticLabel: l10n.commonLoading),
        ),
      ],
    };
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.state, required this.onRetry});

  final StudyState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    if (state.loadMoreError != null) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Center(
          child: TextButton(onPressed: onRetry, child: Text(l10n.actionRetry)),
        ),
      );
    }
    if (state.loadingMore) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: PageLoading(semanticLabel: l10n.commonLoading),
      );
    }
    return const SizedBox(height: AppSpacing.sectionGap);
  }
}

class _LevelSwitch extends ConsumerWidget {
  const _LevelSwitch({required this.selectedId, required this.onSelected});

  final String? selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final levels = ref.watch(educationLevelsProvider).value ?? const <EducationLevelRef>[];
    if (levels.isEmpty || selectedId == null) return const SizedBox(height: AppSizes.minTouchTarget);
    return SegmentedButton<String>(
      segments: [for (final level in levels) ButtonSegment(value: level.id, label: Text(level.name))],
      selected: {selectedId!},
      onSelectionChanged: (s) => onSelected(s.first),
    );
  }
}

/// Filter chips. Each opens a choice sheet; a filled chip shows the current choice.
class _FilterBar extends ConsumerWidget {
  const _FilterBar({required this.query});

  final QuestionQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ObLocalizations.of(context);
    final controller = ref.read(studyControllerProvider.notifier);
    final gutter = AppSpacing.gutter(MediaQuery.sizeOf(context).width);
    final subjects = ref.watch(subjectsProvider(query.levelId ?? '')).value ?? const <SubjectRef>[];
    final chapters = query.subjectId == null
        ? const <ChapterRef>[]
        : (ref.watch(chaptersProvider(query.subjectId!)).value ?? const <ChapterRef>[]);
    final boards = ref.watch(boardsProvider).value ?? const <BoardRef>[];
    final years = [for (var y = DateTime.now().year; y >= _firstYear; y--) y];

    String? nameOf<T>(Iterable<T> items, String? id, String Function(T) idOf, String Function(T) nameOf) {
      for (final item in items) {
        if (idOf(item) == id) return nameOf(item);
      }
      return null;
    }

    return SizedBox(
      height: AppSizes.chipRowHeight(context) + AppSpacing.xs,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: gutter),
        children: [
          _FilterChip(
            label: l10n.filterSubject,
            value: nameOf(subjects, query.subjectId, (s) => s.id, subjectLabel),
            onTap: () async {
              final picked = await showChoiceSheet<String>(
                context,
                title: l10n.studyChooseSubject,
                options: [for (final s in subjects) (s.id, subjectLabel(s))],
                selected: query.subjectId,
                anyLabel: l10n.filterAny,
              );
              if (picked != null) await controller.selectSubject(picked.value);
            },
          ),
          _FilterChip(
            label: l10n.filterChapter,
            enabled: query.subjectId != null,
            value: nameOf(chapters, query.chapterId, (c) => c.id, (c) => '${c.number}. ${c.name}'),
            onTap: () async {
              final picked = await showChoiceSheet<String>(
                context,
                title: l10n.filterChapter,
                options: [for (final c in chapters) (c.id, '${c.number}. ${c.name}')],
                selected: query.chapterId,
                anyLabel: l10n.filterAny,
              );
              if (picked != null) await controller.selectChapter(picked.value);
            },
          ),
          _FilterChip(
            label: l10n.filterType,
            value: query.type == null ? null : questionTypeLabel(l10n, query.type!),
            onTap: () async {
              final picked = await showChoiceSheet<QuestionType>(
                context,
                title: l10n.filterType,
                options: [
                  for (final t in QuestionType.values)
                    if (t != QuestionType.unknown) (t, questionTypeLabel(l10n, t)),
                ],
                selected: query.type,
                anyLabel: l10n.filterAny,
              );
              if (picked != null) await controller.selectType(picked.value);
            },
          ),
          _FilterChip(
            label: l10n.filterDifficulty,
            value: query.difficulty == null ? null : l10n.questionDifficultyLevel(query.difficulty!),
            onTap: () async {
              final picked = await showChoiceSheet<int>(
                context,
                title: l10n.filterDifficulty,
                options: [for (var d = 1; d <= 5; d++) (d, l10n.questionDifficultyLevel(d))],
                selected: query.difficulty,
                anyLabel: l10n.filterAny,
              );
              if (picked != null) await controller.selectDifficulty(picked.value);
            },
          ),
          _FilterChip(
            label: l10n.filterBoard,
            value: nameOf(boards, query.boardId, (b) => b.id, (b) => b.name),
            onTap: () async {
              final picked = await showChoiceSheet<String>(
                context,
                title: l10n.filterBoard,
                options: [for (final b in boards) (b.id, b.name)],
                selected: query.boardId,
                anyLabel: l10n.filterAny,
              );
              if (picked != null) await controller.selectBoard(picked.value);
            },
          ),
          _FilterChip(
            label: l10n.filterYear,
            value: query.year?.toString(),
            onTap: () async {
              final picked = await showChoiceSheet<int>(
                context,
                title: l10n.filterYear,
                options: [for (final y in years) (y, '$y')],
                selected: query.year,
                anyLabel: l10n.filterAny,
              );
              if (picked != null) await controller.selectYear(picked.value);
            },
          ),
          if (query.hasNarrowingFilters)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: AppSpacing.xs),
              child: Center(
                child: TextButton(onPressed: controller.clearFilters, child: Text(l10n.filterClear)),
              ),
            ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.value, required this.onTap, this.enabled = true});

  final String label;
  final String? value;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final selected = value != null;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: AppSpacing.xs),
      child: Center(
        child: FilterChip(
          label: Text(selected ? '$label: $value' : label),
          selected: selected,
          showCheckmark: false,
          onSelected: enabled ? (_) => onTap() : null,
          avatar: const Icon(Icons.arrow_drop_down, size: AppSizes.iconSmall + 4),
        ),
      ),
    );
  }
}

/// The result of a choice sheet: `value == null` means "Any" (clear the filter).
class Choice<T> {
  const Choice(this.value);

  final T? value;
}

Future<Choice<T>?> showChoiceSheet<T>(
  BuildContext context, {
  required String title,
  required List<(T, String)> options,
  required T? selected,
  required String anyLabel,
}) {
  return showModalBottomSheet<Choice<T>>(
    context: context,
    isScrollControlled: true,
    sheetAnimationStyle: AppMotion.reduced(context) ? AnimationStyle.noAnimation : null,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: AppSizes.maxFormWidth + 80),
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (context, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xs),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Semantics(header: true, child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
            ),
          ),
          Expanded(
            child: ListView(
              controller: scroll,
              children: [
                ListTile(
                  title: Text(anyLabel),
                  selected: selected == null,
                  trailing: selected == null ? const Icon(Icons.check) : null,
                  onTap: () => Navigator.of(context).pop(Choice<T>(null)),
                ),
                for (final (value, label) in options)
                  ListTile(
                    title: Text(label),
                    selected: value == selected,
                    trailing: value == selected ? const Icon(Icons.check) : null,
                    onTap: () => Navigator.of(context).pop(Choice<T>(value)),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _QuestionTile extends StatelessWidget {
  const _QuestionTile({required this.question});

  final QuestionCard question;

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final marks = question.marks == question.marks.roundToDouble() ? question.marks.round() : question.marks;
    final isLargeText = MediaQuery.textScalerOf(context).scale(1) >= _largeTextScale;
    final label = [
      questionTypeLabel(l10n, question.type),
      l10n.questionMarks(marks),
      if (question.difficulty != null) l10n.questionDifficultyLevel(question.difficulty!),
      if (question.accessLevel == AccessLevel.entitled) l10n.questionPremium,
      question.stemText,
    ].join(', ');
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Card(
        child: InkWell(
          onTap: () => context.go('/study/questions/${question.id}'),
          child: Padding(
            padding: AppSpacing.cardPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  question.stemText,
                  maxLines: isLargeText ? 6 : 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xxs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _Tag(label: questionTypeLabel(l10n, question.type)),
                    _Tag(label: l10n.questionMarks(marks)),
                    if (question.difficulty != null) _Tag(label: l10n.questionDifficultyLevel(question.difficulty!)),
                    if (question.accessLevel == AccessLevel.entitled)
                      Tooltip(
                        message: l10n.questionPremium,
                        child: Icon(
                          Icons.workspace_premium_outlined,
                          size: AppSizes.iconSmall,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xxs),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(AppShapes.extraSmall),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.onSecondaryContainer),
      ),
    );
  }
}

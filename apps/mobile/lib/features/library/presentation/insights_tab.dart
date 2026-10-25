import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:ob_core/ob_core.dart';
import 'package:ob_l10n/ob_l10n.dart';

import '../data/library_providers.dart';
import '../domain/library_insights.dart';
import 'library_labels.dart';
import 'widgets/book_details_sheet.dart';

/// Overridable "now" so tests can pin the calendar.
final clockProvider = Provider<DateTime Function()>((_) => DateTime.now);

final _periodProvider = NotifierProvider<_PeriodNotifier, InsightPeriod>(_PeriodNotifier.new);

class _PeriodNotifier extends Notifier<InsightPeriod> {
  @override
  InsightPeriod build() {
    ref.watch(libraryUserIdProvider);
    return InsightPeriod.year;
  }

  void set(InsightPeriod period) => state = period;
}

const double _twoColumnWidth = 840;

/// Counts in the UI language's digits, so tiles, bars and ranks agree.
String Function(int) _numbers(BuildContext context) =>
    NumberFormat.decimalPattern(Localizations.localeOf(context).toLanguageTag()).format;

/// Reading insights computed on the device from the library list. Each card states what it is based
/// on, and a card whose data is missing says so instead of guessing.
class InsightsTab extends ConsumerWidget {
  const InsightsTab({required this.books, super.key});

  final List<LibraryItem> books;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ObLocalizations.of(context);
    if (books.isEmpty) {
      return EmptyState(
        icon: Icons.insights_outlined,
        title: l10n.insightsEmptyTitle,
        message: l10n.insightsEmptyMessage,
      );
    }
    final now = ref.watch(clockProvider)();
    final insights = LibraryInsights.compute(books, now: now);
    final cards = <Widget>[
      _FinishedCard(insights: insights),
      _StatusCard(insights: insights),
      _RankingCard(
        title: l10n.insightsGenresTitle,
        subtitle: l10n.insightsGenresSubtitle,
        ranking: insights.categories,
        empty: l10n.insightsNoCategories,
      ),
      _GrowthCard(insights: insights),
      _RankingCard(
        title: l10n.insightsLanguagesTitle,
        ranking: insights.languages,
        empty: l10n.insightsNoLanguages,
        labelOf: (r) => languageName(l10n, r.key),
      ),
      _RankingCard(title: l10n.insightsPublishersTitle, ranking: insights.publishers, empty: l10n.insightsNoPublishers),
      _BookListCard(
        title: l10n.insightsLongestTitle,
        books: insights.longest,
        empty: l10n.insightsNoPageCounts,
        trailing: (b) => l10n.insightsPages(b.pageCount!),
      ),
      // With five or fewer page counts the shortest list would repeat the longest one.
      if (insights.booksWithPageCount > insightTopCount)
        _BookListCard(
          title: l10n.insightsShortestTitle,
          books: insights.shortest,
          empty: l10n.insightsNoPageCounts,
          trailing: (b) => l10n.insightsPages(b.pageCount!),
        ),
      _BookListCard(
        title: l10n.insightsTopRatedTitle,
        subtitle: l10n.insightsTopRatedSubtitle,
        books: insights.topRated,
        empty: l10n.insightsNoRatings,
        trailing: (b) => l10n.insightsRatingValue(b.ratingAvg.toStringAsFixed(1), b.ratingCount),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= _twoColumnWidth;
        final gutter = AppSpacing.gutter(constraints.maxWidth);
        return ListView(
          padding: EdgeInsets.fromLTRB(gutter, AppSpacing.md, gutter, AppSpacing.xxl),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _StatGrid(insights: insights, columns: twoColumns ? 4 : 2),
                    const SizedBox(height: AppSpacing.md),
                    if (twoColumns)
                      _TwoColumns(children: cards)
                    else
                      for (final card in cards) ...[card, const SizedBox(height: AppSpacing.md)],
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TwoColumns extends StatelessWidget {
  const _TwoColumns({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    Widget column(int parity) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, child) in children.indexed)
            if (i.isEven == (parity == 0)) ...[child, const SizedBox(height: AppSpacing.md)],
        ],
      ),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        column(0),
        const SizedBox(width: AppSpacing.md),
        column(1),
      ],
    );
  }
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.insights, required this.columns});

  final LibraryInsights insights;
  final int columns;

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    final number = NumberFormat.decimalPattern(Localizations.localeOf(context).toLanguageTag());
    final unknownPages = insights.finishedWithoutPageCount;
    final tiles = [
      StatTile(
        icon: Icons.local_library_outlined,
        label: l10n.insightsTotalBooks,
        value: number.format(insights.total),
        tone: StatTone.primary,
      ),
      StatTile(
        icon: Icons.check_circle_outline,
        label: l10n.insightsFinishedYear(
          DateFormat.y(Localizations.localeOf(context).toLanguageTag()).format(DateTime(insights.year)),
        ),
        value: number.format(insights.finishedThisYear),
        tone: StatTone.success,
      ),
      StatTile(
        icon: Icons.auto_stories_outlined,
        label: l10n.insightsReadingNow,
        value: number.format(insights.countOf(ShelfStatus.reading)),
      ),
      StatTile(
        icon: Icons.description_outlined,
        label: l10n.insightsPagesFinished,
        value: number.format(insights.pagesFinished),
        caption: unknownPages > 0 ? l10n.insightsPagesUnknown(unknownPages) : null,
        tone: StatTone.premium,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - AppSpacing.sm * (columns - 1)) / columns;
        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [for (final tile in tiles) SizedBox(width: width, child: tile)],
        );
      },
    );
  }
}

class _FinishedCard extends ConsumerWidget {
  const _FinishedCard({required this.insights});

  final LibraryInsights insights;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ObLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final period = ref.watch(_periodProvider);
    final series = insights.finishedSeries(period);
    final total = series.fold(0, (sum, b) => sum + b.count);
    String label(TimeBucket b) => switch (period) {
      InsightPeriod.week => DateFormat.E(locale).format(b.start),
      InsightPeriod.month => DateFormat.MMMd(locale).format(b.start),
      InsightPeriod.year => DateFormat.MMM(locale).format(b.start),
      InsightPeriod.lifetime => '${b.includesEarlier ? '≤' : ''}${DateFormat.y(locale).format(b.start)}',
    };
    String spoken(TimeBucket b) => switch (period) {
      InsightPeriod.week => DateFormat.MMMEd(locale).format(b.start),
      InsightPeriod.month => DateFormat.MMMd(locale).format(b.start),
      InsightPeriod.year => DateFormat.yMMMM(locale).format(b.start),
      InsightPeriod.lifetime => label(b),
    };
    return SurfaceCard(
      title: l10n.insightsFinishedTitle,
      subtitle: l10n.insightsFinishedInPeriod(total),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final (p, text) in [
                (InsightPeriod.week, l10n.insightsPeriodWeek),
                (InsightPeriod.month, l10n.insightsPeriodMonth),
                (InsightPeriod.year, l10n.insightsPeriodYear),
                (InsightPeriod.lifetime, l10n.insightsPeriodLifetime),
              ])
                ChoiceChip(
                  label: Text(text),
                  selected: p == period,
                  onSelected: (_) => ref.read(_periodProvider.notifier).set(p),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (total == 0)
            _InlineEmpty(
              icon: Icons.menu_book_outlined,
              title: l10n.insightsNothingFinished,
              message: l10n.insightsNothingFinishedHint,
            )
          else
            ColumnChart(
              format: _numbers(context),
              data: [
                for (final b in series)
                  ChartDatum(
                    label: label(b),
                    value: b.count,
                    semanticLabel: l10n.insightsChartItem(spoken(b), b.count),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.insights});

  final LibraryInsights insights;

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    final theme = Theme.of(context);
    return SurfaceCard(
      title: l10n.libraryStatusLabel,
      subtitle: l10n.insightsShareFinished(insights.finishedPercent),
      child: Column(
        children: [
          for (final status in [ShelfStatus.reading, ShelfStatus.wantToRead, ShelfStatus.finished])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
              child: Row(
                children: [
                  ExcludeSemantics(
                    child: Icon(
                      shelfStatusIcon(status),
                      size: AppSizes.iconSmall,
                      color: shelfStatusColors(context, status).$2,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: RankedBars(
                      format: _numbers(context),
                      color: theme.colorScheme.primary,
                      data: [
                        ChartDatum(
                          label: shelfStatusLabel(l10n, status),
                          value: insights.countOf(status),
                        ),
                      ],
                      maxValue: insights.total,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _RankingCard extends StatelessWidget {
  const _RankingCard({required this.title, required this.ranking, required this.empty, this.subtitle, this.labelOf});

  final String title;
  final String? subtitle;
  final Ranking ranking;
  final String empty;
  final String Function(RankedCount)? labelOf;

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    return SurfaceCard(
      title: title,
      subtitle: subtitle,
      child: ranking.isEmpty
          ? Text(empty, style: Theme.of(context).textTheme.bodyMedium)
          : RankedBars(
              format: _numbers(context),
              data: [
                for (final r in ranking.top) ChartDatum(label: labelOf?.call(r) ?? r.label, value: r.count),
                if (ranking.otherCount > 0) ChartDatum(label: l10n.insightsOthers, value: ranking.otherCount),
              ],
            ),
    );
  }
}

class _GrowthCard extends StatelessWidget {
  const _GrowthCard({required this.insights});

  final LibraryInsights insights;

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    return SurfaceCard(
      title: l10n.insightsGrowthTitle,
      subtitle: l10n.insightsGrowthSubtitle,
      child: ColumnChart(
        format: _numbers(context),
        height: 120,
        data: [
          for (final b in insights.addedPerMonth)
            ChartDatum(
              label: DateFormat.MMM(locale).format(b.start),
              value: b.count,
              semanticLabel: l10n.insightsChartItem(DateFormat.yMMMM(locale).format(b.start), b.count),
            ),
        ],
      ),
    );
  }
}

class _BookListCard extends StatelessWidget {
  const _BookListCard({
    required this.title,
    required this.books,
    required this.empty,
    required this.trailing,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final List<LibraryItem> books;
  final String empty;
  final String Function(LibraryItem) trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SurfaceCard(
      title: title,
      subtitle: subtitle,
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xs),
      child: books.isEmpty
          ? Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Text(empty, style: theme.textTheme.bodyMedium),
            )
          : Column(
              children: [
                for (final (i, book) in books.indexed)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    onTap: () => showBookDetailsSheet(context, book),
                    leading: SizedBox(
                      width: 24,
                      child: Text(
                        _numbers(context)(i + 1),
                        style: theme.textTheme.labelLarge,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    title: Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(trailing(book)),
                  ),
              ],
            ),
    );
  }
}

class _InlineEmpty extends StatelessWidget {
  const _InlineEmpty({required this.icon, required this.title, required this.message});

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Column(
        children: [
          ExcludeSemantics(
            child: CircleAvatar(
              radius: 24,
              backgroundColor: theme.colorScheme.secondaryContainer,
              child: Icon(icon, color: theme.colorScheme.onSecondaryContainer),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(title, style: theme.textTheme.titleSmall, textAlign: TextAlign.center),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

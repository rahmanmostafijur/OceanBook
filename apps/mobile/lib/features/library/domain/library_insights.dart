import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:ob_core/ob_core.dart';

/// Time windows for "books finished". Every window ends today (device time zone).
enum InsightPeriod { week, month, year, lifetime }

/// Number of entries shown in ranked lists before the rest is summed as "other".
const int insightTopCount = 5;

const int _monthDays = 30;
const int _monthBucketDays = 6;
const int _lifetimeMaxYears = 10;

/// One bar: a span of local calendar days starting at [start] (inclusive) and the count inside it.
@immutable
class TimeBucket {
  const TimeBucket({required this.start, required this.count, this.includesEarlier = false});

  final DateTime start;
  final int count;

  /// The oldest lifetime bucket also counts everything before its year.
  final bool includesEarlier;
}

/// A ranked category, language or publisher. [key] is a stable id (category id, language code).
@immutable
class RankedCount {
  const RankedCount({required this.key, required this.label, required this.count});

  final String key;
  final String label;
  final int count;
}

/// Top entries plus how many books fall outside them.
@immutable
class Ranking {
  const Ranking(this.top, this.otherCount);

  final List<RankedCount> top;
  final int otherCount;

  bool get isEmpty => top.isEmpty;
}

DateTime _day(DateTime t) {
  final local = t.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// Reading insights derived from the library items alone. Nothing is stored or estimated: a book
/// without a page count, category or rating is left out of that particular figure, and the screens
/// say so. Dates are bucketed in the device's time zone.
@immutable
class LibraryInsights {
  const LibraryInsights._(this._items, this._today);

  factory LibraryInsights.compute(List<LibraryItem> items, {required DateTime now}) =>
      LibraryInsights._(List.unmodifiable(items), _day(now));

  final List<LibraryItem> _items;
  final DateTime _today;

  /// The current year in the device's calendar.
  int get year => _today.year;

  int get total => _items.length;
  bool get isEmpty => _items.isEmpty;

  int countOf(ShelfStatus status) => _items.where((b) => b.status == status).length;
  int get favorites => _items.where((b) => b.isFavorite).length;

  List<LibraryItem> get _finished => [
    for (final b in _items)
      if (b.status == ShelfStatus.finished) b,
  ];

  /// Share of the library marked finished, 0–100.
  int get finishedPercent => total == 0 ? 0 : (countOf(ShelfStatus.finished) * 100 / total).round();

  int get finishedThisYear =>
      _finished.where((b) => b.finishedAt != null && _day(b.finishedAt!).year == _today.year).length;

  /// Pages of finished books whose edition lists a page count. Reading progress is not tracked yet,
  /// so this counts whole finished books only.
  int get pagesFinished => _finished.fold(0, (sum, b) => sum + (b.pageCount ?? 0));
  int get finishedWithoutPageCount => _finished.where((b) => b.pageCount == null).length;

  /// Books finished per bucket for [period], oldest first.
  List<TimeBucket> finishedSeries(InsightPeriod period) {
    final dates = [
      for (final b in _finished)
        if (b.finishedAt != null) _day(b.finishedAt!),
    ];
    switch (period) {
      case InsightPeriod.week:
        return [
          for (var i = 6; i >= 0; i--) _countDays(dates, DateTime(_today.year, _today.month, _today.day - i), days: 1),
        ];
      case InsightPeriod.month:
        const buckets = _monthDays ~/ _monthBucketDays;
        return [
          for (var i = buckets - 1; i >= 0; i--)
            _countDays(
              dates,
              DateTime(_today.year, _today.month, _today.day - (i + 1) * _monthBucketDays + 1),
              days: _monthBucketDays,
            ),
        ];
      case InsightPeriod.year:
        return [
          for (var i = 11; i >= 0; i--)
            () {
              final start = DateTime(_today.year, _today.month - i);
              return TimeBucket(
                start: start,
                count: dates.where((d) => d.year == start.year && d.month == start.month).length,
              );
            }(),
        ];
      case InsightPeriod.lifetime:
        final earliest = dates.isEmpty ? _today.year : dates.map((d) => d.year).reduce(math.min);
        final firstYear = math.max(earliest, _today.year - _lifetimeMaxYears + 1);
        return [
          for (var year = firstYear; year <= _today.year; year++)
            TimeBucket(
              start: DateTime(year),
              count: dates.where((d) => year == firstYear ? d.year <= year : d.year == year).length,
              includesEarlier: year == firstYear && earliest < firstYear,
            ),
        ];
    }
  }

  int finishedIn(InsightPeriod period) => finishedSeries(period).fold(0, (sum, b) => sum + b.count);

  TimeBucket _countDays(List<DateTime> dates, DateTime start, {required int days}) {
    final end = DateTime(start.year, start.month, start.day + days);
    return TimeBucket(start: start, count: dates.where((d) => !d.isBefore(start) && d.isBefore(end)).length);
  }

  /// Books added per calendar month over the last 12 months, oldest first.
  List<TimeBucket> get addedPerMonth {
    final added = [for (final b in _items) _day(b.addedAt)];
    return [
      for (var i = 11; i >= 0; i--)
        () {
          final start = DateTime(_today.year, _today.month - i);
          return TimeBucket(
            start: start,
            count: added.where((d) => d.year == start.year && d.month == start.month).length,
          );
        }(),
    ];
  }

  Ranking get categories => _rank([
    for (final b in _items)
      if (b.category != null) (b.category!.id, b.category!.name),
  ]);

  /// Language codes; the screen turns them into names.
  Ranking get languages => _rank([
    for (final b in _items)
      if (b.language != null) (b.language!, b.language!),
  ]);

  Ranking get publishers => _rank([
    for (final b in _items)
      if (b.publisher != null) (b.publisher!.id, b.publisher!.name),
  ]);

  List<LibraryItem> get _withPages => [
    for (final b in _items)
      if (b.pageCount != null && b.pageCount! > 0) b,
  ];

  int get booksWithPageCount => _withPages.length;

  List<LibraryItem> get longest =>
      (_withPages..sort((a, b) => b.pageCount!.compareTo(a.pageCount!))).take(insightTopCount).toList();

  List<LibraryItem> get shortest =>
      (_withPages..sort((a, b) => a.pageCount!.compareTo(b.pageCount!))).take(insightTopCount).toList();

  /// Highest catalog rating first; ties go to the book with more ratings.
  List<LibraryItem> get topRated {
    final rated =
        [
          for (final b in _items)
            if (b.ratingCount > 0) b,
        ]..sort((a, b) {
          final byRating = b.ratingAvg.compareTo(a.ratingAvg);
          return byRating != 0 ? byRating : b.ratingCount.compareTo(a.ratingCount);
        });
    return rated.take(insightTopCount).toList();
  }

  static Ranking _rank(List<(String, String)> keyed) {
    final counts = <String, int>{};
    final labels = <String, String>{};
    for (final (key, label) in keyed) {
      counts[key] = (counts[key] ?? 0) + 1;
      labels[key] = label;
    }
    final ranked = [
      for (final e in counts.entries) RankedCount(key: e.key, label: labels[e.key]!, count: e.value),
    ]..sort((a, b) => a.count != b.count ? b.count.compareTo(a.count) : a.label.compareTo(b.label));
    final top = ranked.take(insightTopCount).toList();
    final other = ranked.skip(insightTopCount).fold(0, (sum, r) => sum + r.count);
    return Ranking(top, other);
  }
}

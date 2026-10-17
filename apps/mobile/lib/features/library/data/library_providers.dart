import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/library_book.dart';

/// Sample shelf. The library backend (chapter content, progress, continue reading) is not part of
/// Phase 2, so the screen is built against this list; swap this provider for the real repository when
/// library sync lands. Nothing here is persisted.
final libraryBooksProvider = Provider<List<LibraryBook>>((ref) => _sampleBooks);

const _novelBlurb =
    'একটি মফস্বল শহরের তরুণের জীবন, স্বপ্ন আর বড় হয়ে ওঠার গল্প। সহজ ভাষায় লেখা এই উপন্যাস পাঠককে পরিচিত '
    'পথে নিয়ে গিয়ে অচেনা প্রশ্নের মুখোমুখি দাঁড় করায়। প্রতিটি অধ্যায়ে নতুন চরিত্র আর নতুন বাঁক, যা শেষ পর্যন্ত '
    'পাঠককে আটকে রাখে।';
const _scienceBlurb =
    'মহাবিশ্বের জটিল ধারণাগুলো গল্পের মতো করে ব্যাখ্যা করা হয়েছে। গণিত ছাড়াই পদার্থবিজ্ঞানের মূল ভাবনাগুলো '
    'বোঝার জন্য এই বই শিক্ষার্থী ও কৌতূহলী পাঠক দুজনের জন্যই উপযোগী।';
const _textbookBlurb =
    'জাতীয় শিক্ষাক্রম অনুযায়ী প্রতিটি অধ্যায়ের সারসংক্ষেপ, উদাহরণ ও অনুশীলনী। পরীক্ষার প্রস্তুতির জন্য '
    'গুরুত্বপূর্ণ বিষয়গুলো আলাদা করে চিহ্নিত করা আছে।';

const _sampleBooks = <LibraryBook>[
  LibraryBook(
    id: 'lib-01',
    title: 'নন্দিত নরকে',
    author: 'হুমায়ূন আহমেদ',
    category: 'উপন্যাস',
    synopsis: _novelBlurb,
    progressPercent: 64,
    rating: 4.5,
  ),
  LibraryBook(
    id: 'lib-02',
    title: 'পদার্থবিজ্ঞান ১ম পত্র',
    author: 'জাতীয় শিক্ষাক্রম ও পাঠ্যপুস্তক বোর্ড',
    category: 'পাঠ্যবই',
    synopsis: _textbookBlurb,
    progressPercent: 22,
    rating: 4,
  ),
  LibraryBook(
    id: 'lib-03',
    title: 'সময়ের সংক্ষিপ্ত ইতিহাস',
    author: 'স্টিফেন হকিং',
    category: 'বিজ্ঞান',
    synopsis: _scienceBlurb,
    progressPercent: 100,
    rating: 5,
  ),
  LibraryBook(
    id: 'lib-04',
    title: 'পথের পাঁচালী',
    author: 'বিভূতিভূষণ বন্দ্যোপাধ্যায়',
    category: 'উপন্যাস',
    synopsis: _novelBlurb,
    rating: 4.5,
  ),
  LibraryBook(
    id: 'lib-05',
    title: 'রসায়ন ২য় পত্র',
    author: 'জাতীয় শিক্ষাক্রম ও পাঠ্যপুস্তক বোর্ড',
    category: 'পাঠ্যবই',
    synopsis: _textbookBlurb,
    progressPercent: 8,
    rating: 3.5,
  ),
  LibraryBook(
    id: 'lib-06',
    title: 'কসমস',
    author: 'কার্ল সেগান',
    category: 'বিজ্ঞান',
    synopsis: _scienceBlurb,
    progressPercent: 41,
    rating: 4.5,
  ),
  LibraryBook(
    id: 'lib-07',
    title: 'লালসালু',
    author: 'সৈয়দ ওয়ালীউল্লাহ',
    category: 'উপন্যাস',
    synopsis: _novelBlurb,
    progressPercent: 90,
    rating: 4,
  ),
  LibraryBook(
    id: 'lib-08',
    title: 'উচ্চতর গণিত ১ম পত্র',
    author: 'জাতীয় শিক্ষাক্রম ও পাঠ্যপুস্তক বোর্ড',
    category: 'পাঠ্যবই',
    synopsis: _textbookBlurb,
    rating: 3.5,
  ),
  LibraryBook(
    id: 'lib-09',
    title: 'অবাক পৃথিবী',
    author: 'মুহম্মদ জাফর ইকবাল',
    category: 'বিজ্ঞান',
    synopsis: _scienceBlurb,
    progressPercent: 15,
    rating: 4,
  ),
  LibraryBook(
    id: 'lib-10',
    title: 'পদ্মা নদীর মাঝি',
    author: 'মানিক বন্দ্যোপাধ্যায়',
    category: 'উপন্যাস',
    synopsis: _novelBlurb,
    progressPercent: 55,
    rating: 4.5,
  ),
];

/// Categories shown as pills, in shelf order, after the leading "All".
final libraryCategoriesProvider = Provider<List<String>>((ref) {
  final seen = <String>{};
  return [
    for (final book in ref.watch(libraryBooksProvider))
      if (seen.add(book.category)) book.category,
  ];
});

@immutable
class LibraryFilter {
  const LibraryFilter({this.query = '', this.category});

  final String query;

  /// `null` means all categories.
  final String? category;

  LibraryFilter copyWith({String? query, String? category, bool clearCategory = false}) =>
      LibraryFilter(query: query ?? this.query, category: clearCategory ? null : (category ?? this.category));

  @override
  bool operator ==(Object other) => other is LibraryFilter && other.query == query && other.category == category;

  @override
  int get hashCode => Object.hash(query, category);
}

class LibraryFilterNotifier extends Notifier<LibraryFilter> {
  @override
  LibraryFilter build() => const LibraryFilter();

  void search(String query) => state = state.copyWith(query: query);

  void selectCategory(String? category) =>
      state = category == null ? state.copyWith(clearCategory: true) : state.copyWith(category: category);
}

final libraryFilterProvider = NotifierProvider<LibraryFilterNotifier, LibraryFilter>(LibraryFilterNotifier.new);

/// Books after the search text and category are applied.
final visibleLibraryBooksProvider = Provider<List<LibraryBook>>((ref) {
  final filter = ref.watch(libraryFilterProvider);
  return [
    for (final book in ref.watch(libraryBooksProvider))
      if ((filter.category == null || book.category == filter.category) && book.matches(filter.query)) book,
  ];
});

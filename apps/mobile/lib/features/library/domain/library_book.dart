import 'package:flutter/foundation.dart';

/// A book in the signed-in user's library. Mirrors the shape the Phase 4 library sync will return
/// (`id`, `title`, `author`, `coverUrl`, `progressPercent`); `category`, `synopsis` and `rating` come
/// from the catalog record.
@immutable
class LibraryBook {
  const LibraryBook({
    required this.id,
    required this.title,
    required this.author,
    required this.category,
    required this.synopsis,
    this.coverUrl,
    this.progressPercent = 0,
    this.rating = 0,
  }) : assert(progressPercent >= 0 && progressPercent <= 100, 'progressPercent is 0-100'),
       assert(rating >= 0 && rating <= 5, 'rating is 0-5');

  final String id;
  final String title;
  final String author;
  final String category;
  final String synopsis;
  final String? coverUrl;
  final int progressPercent;

  /// Average rating, 0-5 in half steps.
  final double rating;

  bool get isStarted => progressPercent > 0;

  bool matches(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return true;
    return title.toLowerCase().contains(needle) || author.toLowerCase().contains(needle);
  }
}

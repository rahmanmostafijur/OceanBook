import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ob_l10n/ob_l10n.dart';

import '../../../core/errors/failure_messages.dart';
import '../data/library_providers.dart';
import 'books_tab.dart';
import 'insights_tab.dart';
import 'shelves_tab.dart';

/// Library (signed-in only): the user's books, their shelves and reading insights, all from
/// `/me/library` and `/me/collections`.
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ObLocalizations.of(context);
    final library = ref.watch(libraryProvider);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.libraryTitle),
          bottom: TabBar(
            tabs: [
              Tab(text: l10n.libraryTabBooks),
              Tab(text: l10n.libraryTabShelves),
              Tab(text: l10n.libraryTabInsights),
            ],
          ),
        ),
        body: switch (library) {
          AsyncValue(:final value?) => TabBarView(
            children: [
              BooksTab(books: value),
              ShelvesTab(books: value),
              InsightsTab(books: value),
            ],
          ),
          AsyncError(:final error) => ErrorState(
            title: l10n.errorTitle,
            message: failureMessage(l10n, error),
            retryLabel: l10n.actionRetry,
            onRetry: () => ref.invalidate(libraryProvider),
          ),
          _ => PageLoading(semanticLabel: l10n.commonLoading),
        },
      ),
    );
  }
}

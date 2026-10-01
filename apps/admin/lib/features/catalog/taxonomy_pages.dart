import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ob_l10n/ob_l10n.dart';

import '../../core/messages.dart';
import 'admin_catalog_api.dart';

enum PeopleKind { authors, publishers }

final _peopleQueryProvider = NotifierProvider.family<_Query, String, PeopleKind>(_Query.new);

class _Query extends Notifier<String> {
  _Query(this.kind);

  final PeopleKind kind;

  @override
  String build() => '';

  void set(String value) => state = value;
}

final adminPeopleProvider = FutureProvider.autoDispose.family<Paged<AdminPerson>, PeopleKind>((ref, kind) {
  final repo = ref.watch(adminCatalogRepositoryProvider);
  final query = ref.watch(_peopleQueryProvider(kind));
  return kind == PeopleKind.authors ? repo.authors(query: query) : repo.publishers(query: query);
});

final adminCategoriesProvider = FutureProvider.autoDispose<List<AdminCategory>>(
  (ref) => ref.watch(adminCatalogRepositoryProvider).categories(),
);

/// Authors or publishers: searchable table (the admin view includes people not yet on a published book).
class PeoplePage extends ConsumerWidget {
  const PeoplePage({required this.kind, super.key});

  final PeopleKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ObLocalizations.of(context);
    final people = ref.watch(adminPeopleProvider(kind));
    final title = kind == PeopleKind.authors ? l10n.authorsTitle : l10n.publishersTitle;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: SizedBox(
              width: 360,
              child: AppSearchBar(
                hintText: title,
                onSubmitted: (q) => ref.read(_peopleQueryProvider(kind).notifier).set(q.trim()),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: switch (people) {
              AsyncData(:final value) when value.rows.isEmpty => EmptyState(
                icon: Icons.person_search,
                title: l10n.errorNotFound,
              ),
              AsyncData(:final value) => Card(
                clipBehavior: Clip.antiAlias,
                child: SingleChildScrollView(
                  child: SizedBox(
                    width: double.infinity,
                    child: DataTable(
                      columns: [
                        DataColumn(label: Text(l10n.adminColumnName)),
                        DataColumn(label: Text(l10n.adminColumnSlug)),
                      ],
                      rows: [
                        for (final p in value.rows)
                          DataRow(
                            cells: [
                              DataCell(Text(p.nameAlt == null ? p.name : '${p.name} (${p.nameAlt})')),
                              DataCell(Text(p.slug)),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              AsyncError(:final error) => ErrorState(
                title: l10n.errorTitle,
                message: adminFailureMessage(l10n, error),
                retryLabel: l10n.actionRetry,
                onRetry: () => ref.invalidate(adminPeopleProvider(kind)),
              ),
              _ => const Center(child: CircularProgressIndicator()),
            },
          ),
        ],
      ),
    );
  }
}

/// Category hierarchy (ltree paths), indented by depth; retired categories are marked, not hidden.
class CategoriesPage extends ConsumerWidget {
  const CategoriesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ObLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    return switch (ref.watch(adminCategoriesProvider)) {
      AsyncData(:final value) when value.isEmpty => EmptyState(
        icon: Icons.category_outlined,
        title: l10n.categoriesTitle,
      ),
      AsyncData(:final value) => ListView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        children: [
          for (final c in [...value]..sort((a, b) => a.path.compareTo(b.path)))
            ListTile(
              contentPadding: EdgeInsetsDirectional.only(start: AppSpacing.md + c.depth * AppSpacing.xl),
              leading: Icon(c.depth == 0 ? Icons.folder_outlined : Icons.subdirectory_arrow_right),
              title: Text(c.name.resolve(locale)),
              subtitle: Text(c.path),
              trailing: c.isActive ? null : StatusChipLite(label: l10n.adminStatusArchived),
            ),
        ],
      ),
      AsyncError(:final error) => ErrorState(
        title: l10n.errorTitle,
        message: adminFailureMessage(l10n, error),
        retryLabel: l10n.actionRetry,
        onRetry: () => ref.invalidate(adminCategoriesProvider),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

class StatusChipLite extends StatelessWidget {
  const StatusChipLite({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Chip(
    avatar: const Icon(Icons.inventory_2_outlined, size: AppSizes.iconSmall),
    label: Text(label),
    visualDensity: VisualDensity.compact,
  );
}

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ob_core/ob_core.dart';
import 'package:ob_l10n/ob_l10n.dart';

import '../../core/providers.dart';

@immutable
class AdminUserRow {
  const AdminUserRow({
    required this.id,
    required this.displayName,
    required this.status,
    required this.roles,
    this.email,
  });

  factory AdminUserRow.fromJson(Map<String, Object?> json) => AdminUserRow(
    id: json['id']! as String,
    displayName: json['display_name']! as String,
    email: json['email'] as String?,
    status: json['status']! as String,
    roles: [for (final r in (json['roles'] as List?) ?? const <Object?>[]) '$r'],
  );

  final String id;
  final String displayName;
  final String? email;
  final String status;
  final List<String> roles;
}

@immutable
class UserPage {
  const UserPage({required this.rows, required this.total, required this.page, required this.pageSize});
  final List<AdminUserRow> rows;
  final int total;
  final int page;
  final int pageSize;
}

abstract interface class AdminUsersRepository {
  Future<UserPage> search({String? query, int page = 1, int pageSize = 25});
}

class AdminUsersApi implements AdminUsersRepository {
  AdminUsersApi(this.api);
  final ApiClient api;

  @override
  Future<UserPage> search({String? query, int page = 1, int pageSize = 25}) async {
    final response = await api.get(
      '/admin/users',
      query: {'q': (query?.length ?? 0) >= 2 ? query : null, 'page': page, 'page_size': pageSize},
      decode: (j) => [for (final row in j! as List) AdminUserRow.fromJson(row as Map<String, Object?>)],
    );
    final meta = response.page;
    return UserPage(
      rows: response.data,
      total: meta is OffsetPageMeta ? meta.total : response.data.length,
      page: page,
      pageSize: pageSize,
    );
  }
}

final adminUsersRepositoryProvider = Provider<AdminUsersRepository>(
  (ref) => AdminUsersApi(ref.watch(adminApiProvider)),
);

final _userQueryProvider = NotifierProvider<_Query, String>(_Query.new);

class _Query extends Notifier<String> {
  @override
  String build() => '';
  void set(String value) => state = value;
}

final adminUsersProvider = FutureProvider.autoDispose<UserPage>((ref) {
  return ref.watch(adminUsersRepositoryProvider).search(query: ref.watch(_userQueryProvider));
});

/// Users: dense, desktop-oriented table backed by `GET /admin/users` (server-side search + paging).
class UsersPage extends ConsumerWidget {
  const UsersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ObLocalizations.of(context);
    final users = ref.watch(adminUsersProvider);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 420,
            child: AppSearchBar(
              hintText: l10n.adminNavUsers,
              onSubmitted: (q) => ref.read(_userQueryProvider.notifier).set(q.trim()),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: switch (users) {
              AsyncData(:final value) when value.rows.isEmpty => EmptyState(
                icon: Icons.group_outlined,
                title: l10n.errorNotFound,
              ),
              AsyncData(:final value) => Card(
                child: SingleChildScrollView(
                  child: DataTable(
                    columns: [
                      DataColumn(label: Text(l10n.authDisplayName)),
                      DataColumn(label: Text(l10n.authEmail)),
                      DataColumn(label: Text(l10n.adminNavRoles)),
                      const DataColumn(label: Text('Status')),
                    ],
                    rows: [
                      for (final u in value.rows)
                        DataRow(
                          cells: [
                            DataCell(Text(u.displayName)),
                            DataCell(Text(u.email ?? '—')),
                            DataCell(
                              Wrap(
                                spacing: AppSpacing.xxs,
                                children: [for (final r in u.roles) Chip(label: Text(r))],
                              ),
                            ),
                            DataCell(Text(u.status)),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              AsyncError() => ErrorState(
                title: l10n.errorTitle,
                message: l10n.errorServer,
                retryLabel: l10n.actionRetry,
                onRetry: () => ref.invalidate(adminUsersProvider),
              ),
              _ => const Center(child: CircularProgressIndicator()),
            },
          ),
        ],
      ),
    );
  }
}

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ob_l10n/ob_l10n.dart';

import '../../core/messages.dart';
import 'academic_setup_api.dart';
import 'setup_dialog.dart';

class _Selection {
  const _Selection(this.kind, this.levelId);

  final SetupKind kind;
  final String? levelId;

  @override
  bool operator ==(Object other) => other is _Selection && other.kind == kind && other.levelId == levelId;

  @override
  int get hashCode => Object.hash(kind, levelId);
}

final _entriesProvider = FutureProvider.autoDispose.family<List<SetupEntry>, _Selection>(
  (ref, selection) => ref.watch(academicSetupRepositoryProvider).list(selection.kind, levelId: selection.levelId),
);

final _levelsProvider = FutureProvider.autoDispose<List<SetupEntry>>(
  (ref) => ref.watch(academicSetupRepositoryProvider).list(SetupKind.levels),
);

String _kindLabel(ObLocalizations l10n, SetupKind kind) => switch (kind) {
  SetupKind.levels => l10n.adminSetupLevels,
  SetupKind.groups => l10n.adminSetupGroups,
  SetupKind.curricula => l10n.adminSetupCurricula,
  SetupKind.boards => l10n.adminSetupBoards,
  SetupKind.media => l10n.adminSetupMedia,
};

/// Levels, groups, curricula, boards and instruction media: the lists subjects, questions and papers are
/// classified by. Keys are fixed once created; levels, boards and media can be archived.
class AcademicSetupPage extends ConsumerStatefulWidget {
  const AcademicSetupPage({super.key});

  @override
  ConsumerState<AcademicSetupPage> createState() => _AcademicSetupPageState();
}

class _AcademicSetupPageState extends ConsumerState<AcademicSetupPage> {
  SetupKind _kind = SetupKind.levels;
  String? _levelId;

  void _refresh(_Selection selection) {
    ref.invalidate(_entriesProvider(selection));
    if (selection.kind == SetupKind.levels) ref.invalidate(_levelsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final levels = ref.watch(_levelsProvider).value ?? const <SetupEntry>[];
    final levelId = _kind == SetupKind.groups ? (_levelId ?? levels.firstOrNull?.id) : null;
    final selection = _Selection(_kind, levelId);
    final entries = _kind == SetupKind.groups && levelId == null
        ? const AsyncData<List<SetupEntry>>([])
        : ref.watch(_entriesProvider(selection));
    final repo = ref.read(academicSetupRepositoryProvider);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<SetupKind>(
              key: const Key('setup-kind'),
              showSelectedIcon: false,
              segments: [
                for (final k in SetupKind.values)
                  ButtonSegment(
                    value: k,
                    label: Text(_kindLabel(l10n, k), key: Key('setup-kind-${k.name}')),
                  ),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.single),
            ),
            if (_kind == SetupKind.groups && levels.isNotEmpty)
              DropdownMenu<String>(
                key: const Key('setup-level'),
                initialSelection: levelId,
                label: Text(l10n.adminSetupPickLevel),
                onSelected: (v) => setState(() => _levelId = v),
                dropdownMenuEntries: [
                  for (final l in levels) DropdownMenuEntry(value: l.id, label: l.name.resolve(locale)),
                ],
              ),
            FilledButton.icon(
              key: const Key('setup-add'),
              icon: const Icon(Icons.add),
              label: Text(l10n.adminSetupAdd),
              onPressed: _kind == SetupKind.groups && levelId == null
                  ? null
                  : () => showSetupDialog(
                      context,
                      kind: _kind,
                      title: '${l10n.adminSetupAdd}: ${_kindLabel(l10n, _kind)}',
                      onSave: (key, fields) async {
                        await repo.create(_kind, key: key, fields: fields, levelId: levelId);
                        _refresh(selection);
                      },
                    ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        switch (entries) {
          AsyncData(:final value) when value.isEmpty => EmptyState(
            icon: Icons.tune_outlined,
            title: l10n.adminSetupEmpty,
          ),
          AsyncData(:final value) => Card(
            child: Column(
              children: [
                for (final entry in value)
                  _EntryTile(
                    kind: _kind,
                    entry: entry,
                    onEdit: () => showSetupDialog(
                      context,
                      kind: _kind,
                      title: '${l10n.adminSetupEdit}: ${entry.name.resolve(locale)}',
                      entry: entry,
                      onSave: (_, fields) async {
                        await repo.update(_kind, entry.id, fields: fields);
                        _refresh(selection);
                      },
                    ),
                    onToggle: () async {
                      try {
                        await repo.update(_kind, entry.id, isActive: !entry.isActive);
                        _refresh(selection);
                      } on Object catch (error) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text(adminFailureMessage(l10n, error))));
                        }
                      }
                    },
                  ),
              ],
            ),
          ),
          AsyncError(:final error) => ErrorState(
            title: l10n.errorTitle,
            message: adminFailureMessage(l10n, error),
            retryLabel: l10n.actionRetry,
            onRetry: () => ref.invalidate(_entriesProvider(selection)),
          ),
          _ => PageLoading.linear(semanticLabel: l10n.commonLoading),
        },
      ],
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.kind, required this.entry, required this.onEdit, required this.onToggle});

  final SetupKind kind;
  final SetupEntry entry;
  final VoidCallback onEdit;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final details = [
      entry.key,
      if (kind == SetupKind.boards && entry.boardType != null) boardTypeLabel(l10n, entry.boardType!),
      if (kind == SetupKind.media && entry.contentLocale != null) entry.contentLocale!,
      if (kind == SetupKind.curricula && (entry.effectiveFromYear != null || entry.effectiveToYear != null))
        '${entry.effectiveFromYear ?? ''}–${entry.effectiveToYear ?? ''}',
      if (kind == SetupKind.curricula && entry.isCurrent) l10n.adminSetupIsCurrent,
      if (!entry.isActive) l10n.adminStatusArchived,
    ];
    return ListTile(
      key: Key('setup-entry-${entry.key}'),
      title: Text(entry.name.resolve(locale)),
      subtitle: Text(details.join(' · ')),
      trailing: Wrap(
        children: [
          IconButton(
            key: Key('setup-edit-${entry.key}'),
            tooltip: l10n.adminSetupEdit,
            icon: const Icon(Icons.edit_outlined),
            onPressed: onEdit,
          ),
          if (kind.canArchive)
            IconButton(
              key: Key('setup-toggle-${entry.key}'),
              tooltip: entry.isActive ? l10n.adminArchiveItem : l10n.adminRestoreItem,
              icon: Icon(entry.isActive ? Icons.archive_outlined : Icons.unarchive_outlined),
              onPressed: onToggle,
            ),
        ],
      ),
    );
  }
}

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ob_core/ob_core.dart';
import 'package:ob_l10n/ob_l10n.dart';

import '../../../core/config/app_config.dart';
import '../../../core/settings/app_settings.dart';
import '../../auth/presentation/auth_controller.dart';

/// Profile and settings in groups: account, appearance, premium status, about, sign-out. Only settings
/// the app can actually apply are shown.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ObLocalizations.of(context);
    final theme = Theme.of(context);
    final auth = ref.watch(authControllerProvider).value;
    final user = auth is AuthSignedIn ? auth.user : null;
    const gap = SizedBox(height: AppSpacing.xl);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.profileTitle)),
      body: ConstrainedContent(
        maxWidth: AppSizes.maxReadableWidth,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          children: [
            SettingsSection(
              title: l10n.settingsAccount,
              children: [
                if (user != null) ...[
                  _AccountTile(user: user),
                  ListTile(
                    leading: const Icon(Icons.logout),
                    title: Text(l10n.actionSignOut),
                    onTap: () => _confirmSignOut(context, ref),
                  ),
                ] else
                  const _GuestTile(),
              ],
            ),
            gap,
            SettingsSection(
              title: l10n.settingsAppearance,
              children: [
                _ChoiceTile(
                  icon: Icons.language,
                  title: l10n.settingsLanguage,
                  control: SegmentedButton<String>(
                    segments: [
                      ButtonSegment(value: 'bn', label: Text(l10n.languageBangla)),
                      ButtonSegment(value: 'en', label: Text(l10n.languageEnglish)),
                    ],
                    selected: {ref.watch(localeProvider).languageCode},
                    onSelectionChanged: (s) => ref.read(localeProvider.notifier).set(Locale(s.first)),
                  ),
                ),
                _ChoiceTile(
                  icon: Icons.dark_mode_outlined,
                  title: l10n.settingsTheme,
                  control: SegmentedButton<ThemeMode>(
                    segments: [
                      ButtonSegment(value: ThemeMode.system, label: Text(l10n.themeSystem)),
                      ButtonSegment(value: ThemeMode.light, label: Text(l10n.themeLight)),
                      ButtonSegment(value: ThemeMode.dark, label: Text(l10n.themeDark)),
                    ],
                    selected: {ref.watch(themeModeProvider)},
                    onSelectionChanged: (s) => ref.read(themeModeProvider.notifier).set(s.first),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: AppSpacing.xxs, top: AppSpacing.xs),
              child: Text(
                l10n.settingsSavedOnDevice,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            gap,
            SettingsSection(
              title: l10n.settingsPremium,
              children: [
                ListTile(
                  leading: Icon(Icons.workspace_premium_outlined, color: AppSemanticColors.of(context).premium),
                  title: Text(l10n.settingsPremium),
                  subtitle: Text(l10n.settingsPremiumUnavailable),
                ),
              ],
            ),
            gap,
            SettingsSection(
              title: l10n.settingsAbout,
              children: [
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text(l10n.settingsVersion),
                  trailing: Text(AppConfig.appVersion, style: theme.textTheme.bodyLarge),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final l10n = ObLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.settingsSignOutConfirmTitle),
        content: Text(l10n.settingsSignOutConfirmMessage),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l10n.actionCancel)),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(l10n.actionSignOut)),
        ],
      ),
    );
    if (confirmed ?? false) await ref.read(authControllerProvider.notifier).signOut();
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initial = user.displayName.trim().isEmpty ? '?' : user.displayName.trim().characters.first.toUpperCase();
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      leading: ExcludeSemantics(
        child: CircleAvatar(
          backgroundColor: scheme.primaryContainer,
          foregroundColor: scheme.onPrimaryContainer,
          child: Text(initial),
        ),
      ),
      title: Text(user.displayName),
      subtitle: Text(user.email ?? user.phone ?? ''),
    );
  }
}

class _GuestTile extends StatelessWidget {
  const _GuestTile();

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.settingsGuestTitle, style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            l10n.settingsGuestMessage,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            onPressed: () => context.go(Uri(path: '/sign-in', queryParameters: {'from': '/profile'}).toString()),
            child: Text(l10n.actionSignIn),
          ),
        ],
      ),
    );
  }
}

/// A settings row whose control sits under the title, so it never squeezes at large text sizes.
class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({required this.icon, required this.title, required this.control});

  final IconData icon;
  final String title;
  final Widget control;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ExcludeSemantics(child: Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(width: double.infinity, child: control),
        ],
      ),
    );
  }
}

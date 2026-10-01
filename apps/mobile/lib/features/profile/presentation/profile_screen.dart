import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ob_core/ob_core.dart';
import 'package:ob_l10n/ob_l10n.dart';

import '../../../core/settings/app_settings.dart';
import '../../auth/presentation/auth_controller.dart';

/// Profile and settings: language, theme, sign-out.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ObLocalizations.of(context);
    final auth = ref.watch(authControllerProvider).value;
    final user = auth is AuthSignedIn ? auth.user : null;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.profileTitle)),
      body: ConstrainedContent(
        maxWidth: AppSizes.maxReadableWidth,
        child: ListView(
          children: [
            if (user != null)
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text(user.displayName),
                subtitle: Text(user.email ?? user.phone ?? ''),
              ),
            const Divider(),
            ListTile(title: Text(l10n.settingsLanguage)),
            Padding(
              padding: AppSpacing.listTilePadding,
              child: SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'bn', label: Text(l10n.languageBangla)),
                  ButtonSegment(value: 'en', label: Text(l10n.languageEnglish)),
                ],
                selected: {ref.watch(localeProvider).languageCode},
                onSelectionChanged: (s) => ref.read(localeProvider.notifier).set(Locale(s.first)),
              ),
            ),
            ListTile(title: Text(l10n.settingsTheme)),
            Padding(
              padding: AppSpacing.listTilePadding,
              child: SegmentedButton<ThemeMode>(
                segments: [
                  ButtonSegment(value: ThemeMode.system, label: Text(l10n.themeSystem)),
                  ButtonSegment(value: ThemeMode.light, label: Text(l10n.themeLight)),
                  ButtonSegment(value: ThemeMode.dark, label: Text(l10n.themeDark)),
                ],
                selected: {ref.watch(themeModeProvider)},
                onSelectionChanged: (s) => ref.read(themeModeProvider.notifier).set(s.first),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            if (user != null)
              ListTile(
                leading: const Icon(Icons.logout),
                title: Text(l10n.actionSignOut),
                onTap: () => ref.read(authControllerProvider.notifier).signOut(),
              ),
          ],
        ),
      ),
    );
  }
}

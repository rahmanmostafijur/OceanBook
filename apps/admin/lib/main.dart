import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ob_l10n/ob_l10n.dart';

import 'core/providers.dart';
import 'core/router.dart';

void main() => runApp(const ProviderScope(child: AdminApp()));

class AdminApp extends ConsumerWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      onGenerateTitle: (context) => ObLocalizations.of(context).adminTitle,
      debugShowCheckedModeBanner: false,
      // Same tokens as the mobile app, compact density for desktop workflows.
      theme: AppTheme.light(density: AppDensity.compact),
      darkTheme: AppTheme.dark(density: AppDensity.compact),
      locale: ref.watch(adminLocaleProvider),
      supportedLocales: ObLocalizations.supportedLocales,
      localizationsDelegates: const [
        ObLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: ref.watch(adminRouterProvider),
    );
  }
}

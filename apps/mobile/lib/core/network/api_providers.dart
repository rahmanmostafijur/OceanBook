import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ob_core/ob_core.dart';

import '../config/app_config.dart';
import '../settings/app_settings.dart';

/// Overridden in main() with values read before the first frame (secure storage is async).
final installationIdProvider = Provider<String>((ref) => throw UnimplementedError('override in main()'));
final tokenStoreProvider = Provider<TokenStore>((ref) => throw UnimplementedError('override in main()'));

final sessionEventsProvider = Provider<SessionEvents>((ref) {
  final events = SessionEvents();
  ref.onDispose(events.dispose);
  return events;
});

/// The single API client for the app. Widgets never use it directly; repositories do.
final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    baseUrl: AppConfig.apiBaseUrl,
    tokens: ref.watch(tokenStoreProvider),
    events: ref.watch(sessionEventsProvider),
    identity: ClientIdentity(
      installationId: ref.watch(installationIdProvider),
      appVersion: AppConfig.appVersion,
      platform: Platform.isIOS ? 'ios' : 'android',
    ),
    locale: () => ref.read(localeProvider).languageCode,
  );
});

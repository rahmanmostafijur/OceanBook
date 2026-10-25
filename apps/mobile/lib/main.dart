import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/network/api_providers.dart';
import 'core/settings/app_settings.dart';
import 'core/storage/secure_token_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final installationId = await InstallationIdStore().readOrCreate();
  final preferences = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [
        installationIdProvider.overrideWithValue(installationId),
        tokenStoreProvider.overrideWithValue(SecureTokenStore()),
        preferenceStoreProvider.overrideWithValue(SharedPreferenceStore(preferences)),
      ],
      child: const OceanBookApp(),
    ),
  );
}

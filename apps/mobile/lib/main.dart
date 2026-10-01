import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/network/api_providers.dart';
import 'core/storage/secure_token_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final installationId = await InstallationIdStore().readOrCreate();
  runApp(
    ProviderScope(
      overrides: [
        installationIdProvider.overrideWithValue(installationId),
        tokenStoreProvider.overrideWithValue(SecureTokenStore()),
      ],
      child: const OceanBookApp(),
    ),
  );
}

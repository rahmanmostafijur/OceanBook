import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Small key-value store for device preferences (language, theme). Not for secrets or user data.
abstract interface class PreferenceStore {
  String? read(String key);
  Future<void> write(String key, String value);
}

/// Process-lifetime store: the default, and what tests use.
class MemoryPreferenceStore implements PreferenceStore {
  final _values = <String, String>{};

  @override
  String? read(String key) => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;
}

/// Backed by the platform's preferences (SharedPreferences on Android, NSUserDefaults on iOS).
class SharedPreferenceStore implements PreferenceStore {
  SharedPreferenceStore(this._prefs);

  final SharedPreferences _prefs;

  @override
  String? read(String key) => _prefs.getString(key);

  @override
  Future<void> write(String key, String value) => _prefs.setString(key, value);
}

/// Overridden in main() with [SharedPreferenceStore], loaded before the first frame.
final preferenceStoreProvider = Provider<PreferenceStore>((ref) => MemoryPreferenceStore());

const _localeKey = 'ui.locale';
const _themeModeKey = 'ui.theme_mode';
const _supportedLanguages = {'bn', 'en'};

/// UI language: Bangla by default (the product is Bangla-first); English available from day one.
/// The choice is remembered on this device.
class LocaleNotifier extends Notifier<Locale> {
  @override
  Locale build() {
    final saved = ref.watch(preferenceStoreProvider).read(_localeKey);
    return Locale(_supportedLanguages.contains(saved) ? saved! : 'bn');
  }

  void set(Locale locale) {
    state = locale;
    ref.read(preferenceStoreProvider).write(_localeKey, locale.languageCode);
  }
}

final localeProvider = NotifierProvider<LocaleNotifier, Locale>(LocaleNotifier.new);

/// Light / dark / follow the system, remembered on this device.
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    final saved = ref.watch(preferenceStoreProvider).read(_themeModeKey);
    return ThemeMode.values.firstWhere((m) => m.name == saved, orElse: () => ThemeMode.system);
  }

  void set(ThemeMode mode) {
    state = mode;
    ref.read(preferenceStoreProvider).write(_themeModeKey, mode.name);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

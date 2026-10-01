/// Build-time configuration (`--dart-define`). No secrets live in the app: everything here is public.
abstract final class AppConfig {
  /// Android emulators reach the host machine at 10.0.2.2.
  static const String apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:8000/api/v1');
  static const String appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '0.1.0');

  /// Social sign-in buttons appear only when the provider is configured for this build (production client
  /// ids are inserted later). The backend independently refuses unconfigured providers.
  static const bool googleSignInEnabled = bool.fromEnvironment('GOOGLE_SIGN_IN_ENABLED');
  static const bool appleSignInEnabled = bool.fromEnvironment('APPLE_SIGN_IN_ENABLED');
}

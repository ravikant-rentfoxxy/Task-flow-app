/// Build-time configuration.
///
/// Override the backend with `--dart-define=API_URL=http://192.168.1.10:8000/api`.
class AppConfig {
  static const String apiUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://task.rentfoxxy.com/api',
  );

  /// Base URL without a trailing slash, always ending in `/api`.
  static String get apiBase => apiUrl.replaceAll(RegExp(r'/+$'), '');

  /// Socket.IO origin — the API host without the `/api` suffix.
  static String socketOrigin(String apiBase) => apiBase.replaceAll(RegExp(r'/api/?$'), '');
}

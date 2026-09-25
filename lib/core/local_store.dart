import 'package:hive_flutter/hive_flutter.dart';

/// Hive storage for the signed-in session (tokens + user profile) and small app state.
/// Values are plain maps/strings, so no type adapters are needed.
class LocalStore {
  LocalStore(this._session, this._app);

  static const sessionBoxName = 'tf_session';
  static const appBoxName = 'tf_app';

  final Box<dynamic> _session;
  final Box<dynamic> _app;

  /// Opens the boxes in the app documents directory.
  static Future<LocalStore> open() async {
    await Hive.initFlutter();
    return LocalStore(await Hive.openBox(sessionBoxName), await Hive.openBox(appBoxName));
  }

  String? get accessToken => _session.get('accessToken') as String?;
  String? get refreshToken => _session.get('refreshToken') as String?;

  Future<void> saveTokens(String? access, String? refresh) async {
    await _session.put('accessToken', access);
    await _session.put('refreshToken', refresh);
  }

  /// Last known profile of the signed-in user (shown instantly on the next launch).
  Map<String, dynamic>? get user {
    final raw = _session.get('user');
    return raw is Map ? Map<String, dynamic>.from(raw) : null;
  }

  Future<void> saveUser(Map<String, dynamic>? user) => _session.put('user', user);

  Future<void> clearSession() => _session.clear();

  dynamic read(String key) => _app.get(key);
  Future<void> write(String key, dynamic value) => _app.put(key, value);
}

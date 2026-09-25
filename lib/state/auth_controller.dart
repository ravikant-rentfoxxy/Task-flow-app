import 'dart:async';

import 'package:get/get.dart';

import '../core/api_client.dart';
import '../core/local_store.dart';
import '../data/taskflow_api.dart';
import '../models/models.dart';

enum AuthStatus { unknown, signedOut, signedIn }

/// Signed-in user, unread notification count, and login/logout.
/// The user profile is cached in Hive so the app opens straight into the session.
class AuthController extends GetxController {
  AuthController(this.api, {this.store, this.pollInterval = const Duration(seconds: 30)}) {
    api.client.onSessionExpired = _expire;
  }

  final TaskFlowApi api;
  final LocalStore? store;
  final Duration pollInterval;

  final _status = AuthStatus.unknown.obs;
  final _me = Rxn<Me>();
  final _unread = 0.obs;
  Timer? _poll;

  AuthStatus get status => _status.value;
  Me? get me => _me.value;
  int get unread => _unread.value;

  Future<void> init() async {
    await api.client.restore();
    if (!api.client.hasSession) {
      _setSignedOut();
      return;
    }
    // Show the cached profile immediately, then confirm with the server.
    final cached = store?.user;
    if (cached != null) {
      _me.value = Me.fromJson(cached);
      _signIn();
    }
    try {
      await refreshMe();
    } on ApiException catch (e) {
      if (e.isUnauthorized || cached == null) {
        await api.client.clearTokens();
        _setSignedOut();
      }
      // Offline with a cached user: stay signed in and retry on the next poll.
    }
  }

  Future<void> login(String email, String password) async {
    await api.login(email.trim(), password);
    await refreshMe();
  }

  Future<void> refreshMe() async {
    final r = await api.me();
    _me.value = r.me;
    _unread.value = r.unread;
    await store?.saveUser(r.me.toJson());
    _signIn();
  }

  /// Background refresh — swallows errors (session expiry is handled by the client hook).
  Future<void> refreshQuietly() async {
    try {
      await refreshMe();
    } catch (_) {}
  }

  Future<void> logout() async {
    await api.logout();
    _setSignedOut();
  }

  void _signIn() {
    if (_status.value == AuthStatus.signedIn) return;
    _status.value = AuthStatus.signedIn;
    _poll?.cancel();
    if (pollInterval > Duration.zero) _poll = Timer.periodic(pollInterval, (_) => refreshQuietly());
  }

  void _expire() {
    if (_status.value == AuthStatus.signedOut) return;
    api.client.clearTokens();
    _setSignedOut();
  }

  void _setSignedOut() {
    _poll?.cancel();
    _poll = null;
    _me.value = null;
    _unread.value = 0;
    _status.value = AuthStatus.signedOut;
  }

  @override
  void onClose() {
    _poll?.cancel();
    super.onClose();
  }
}

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_logger.dart';
import 'local_store.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.code, this.status});

  final String message;
  final String? code;
  final int? status;

  bool get isUnauthorized => status == 401;

  @override
  String toString() => message;
}

/// Persists the session tokens between launches.
abstract class TokenStore {
  Future<({String? access, String? refresh})> read();
  Future<void> write(String? access, String? refresh);
  Future<void> clear();
}

class HiveTokenStore implements TokenStore {
  HiveTokenStore(this.store);
  final LocalStore store;

  @override
  Future<({String? access, String? refresh})> read() async => (access: store.accessToken, refresh: store.refreshToken);

  @override
  Future<void> write(String? access, String? refresh) => store.saveTokens(access, refresh);

  @override
  Future<void> clear() => store.clearSession();
}

class MemoryTokenStore implements TokenStore {
  String? access;
  String? refresh;

  @override
  Future<({String? access, String? refresh})> read() async => (access: access, refresh: refresh);

  @override
  Future<void> write(String? access, String? refresh) async {
    this.access = access;
    this.refresh = refresh;
  }

  @override
  Future<void> clear() => write(null, null);
}

/// Dio client for TMS_BE. Sends the access token as a Bearer header and
/// transparently refreshes it (the backend reads the refresh token from a cookie).
class ApiClient {
  /// [logRequests] logs every request/response via [ApiLogger]; defaults to debug builds only.
  ApiClient({required String baseUrl, Dio? dio, TokenStore? store, bool logRequests = kDebugMode})
      : baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
        _store = store ?? MemoryTokenStore(),
        dio = dio ?? Dio() {
    if (logRequests && !this.dio.interceptors.any((i) => i is ApiLogger)) this.dio.interceptors.add(ApiLogger());
    this.dio.options
      ..connectTimeout = const Duration(seconds: 15)
      ..receiveTimeout = const Duration(seconds: 30)
      // Status handling (401 refresh, error messages) is done here, not by Dio.
      ..validateStatus = (_) => true;
  }

  final String baseUrl;
  final Dio dio;
  final TokenStore _store;

  String? _access;
  String? _refresh;
  Future<bool>? _refreshing;

  /// Called when the session can no longer be recovered (refresh failed).
  void Function()? onSessionExpired;

  static const _noRetryPaths = {
    '/auth/login',
    '/auth/logout',
    '/auth/forgot-password',
    '/auth/reset-password',
    '/auth/refresh',
  };

  String? get accessToken => _access;
  bool get hasSession => (_access?.isNotEmpty ?? false) || (_refresh?.isNotEmpty ?? false);

  Future<void> restore() async {
    final t = await _store.read();
    _access = t.access;
    _refresh = t.refresh;
  }

  Future<void> saveTokens(String? access, String? refresh) async {
    _access = access;
    _refresh = refresh;
    await _store.write(access, refresh);
  }

  Future<void> clearTokens() async {
    _access = null;
    _refresh = null;
    await _store.clear();
  }

  /// Cookie header understood by the backend's cookie-based auth (Socket.IO handshake).
  String get cookieHeader => [
        if (_access != null) 'accessToken=$_access',
        if (_refresh != null) 'refreshToken=$_refresh',
      ].join('; ');

  Map<String, String> get authHeaders => {
        if (_access != null) 'Authorization': 'Bearer $_access',
      };

  Uri uri(String path, [Map<String, dynamic>? query]) {
    final normalized = path.startsWith('/') ? path : '/$path';
    final q = <String, String>{};
    query?.forEach((k, v) {
      if (v == null) return;
      final s = v.toString();
      if (s.isEmpty) return;
      q[k] = s;
    });
    final u = Uri.parse('$baseUrl$normalized');
    return q.isEmpty ? u : u.replace(queryParameters: {...u.queryParameters, ...q});
  }

  String uploadUrl(int id) => '$baseUrl/uploads/$id';

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) => _send('GET', path, query: query);

  Future<dynamic> post(String path, [Object? body]) => _send('POST', path, body: body);

  Future<dynamic> patch(String path, [Object? body]) => _send('PATCH', path, body: body);

  Future<dynamic> delete(String path, {Map<String, dynamic>? query}) => _send('DELETE', path, query: query);

  Future<Map<String, dynamic>> upload(
    String path, {
    required List<int> bytes,
    required String filename,
    String? mimeType,
    Map<String, String> fields = const {},
  }) async {
    final res = await _withRefresh(path, () {
      final form = FormData.fromMap({
        ...fields,
        'file': MultipartFile.fromBytes(bytes, filename: filename, contentType: DioMediaType.parse(mimeType ?? guessMimeType(filename))),
      });
      return dio.requestUri(uri(path), data: form, options: Options(method: 'POST', headers: authHeaders));
    });
    return Map<String, dynamic>.from(_decode(res) as Map);
  }

  Future<Uint8List> getBytes(String path) async {
    final res = await _withRefresh(
      path,
      () => dio.requestUri<List<int>>(uri(path), options: Options(method: 'GET', headers: authHeaders, responseType: ResponseType.bytes)),
    );
    if ((res.statusCode ?? 500) >= 400) throw ApiException('Download failed (${res.statusCode})', status: res.statusCode);
    return Uint8List.fromList(res.data as List<int>);
  }

  Future<dynamic> _send(String method, String path, {Object? body, Map<String, dynamic>? query}) async {
    final res = await _withRefresh(
      path,
      () => dio.requestUri(
        uri(path, query),
        data: body,
        options: Options(method: method, headers: authHeaders, contentType: body == null ? null : Headers.jsonContentType),
      ),
    );
    return _decode(res);
  }

  Future<Response<T>> _withRefresh<T>(String path, Future<Response<T>> Function() build) async {
    Response<T> res;
    try {
      res = await build();
    } on DioException {
      throw ApiException('Could not reach the server. Check your connection.');
    }
    if (res.statusCode != 401 || _noRetryPaths.contains(path)) return res;

    final refreshed = await _refreshSession();
    if (!refreshed) {
      onSessionExpired?.call();
      return res;
    }
    try {
      res = await build();
    } on DioException {
      throw ApiException('Could not reach the server. Check your connection.');
    }
    if (res.statusCode == 401) onSessionExpired?.call();
    return res;
  }

  Future<bool> _refreshSession() {
    return _refreshing ??= () async {
      try {
        if (_refresh == null) return false;
        final res = await dio.requestUri(uri('/auth/refresh'),
            options: Options(method: 'POST', headers: {'Cookie': 'refreshToken=$_refresh'}));
        if ((res.statusCode ?? 500) >= 400) return false;
        final cookies = (res.headers['set-cookie'] ?? const <String>[]).join(',');
        final access = RegExp(r'accessToken=([^;,\s]+)').firstMatch(cookies)?.group(1);
        final refresh = RegExp(r'refreshToken=([^;,\s]+)').firstMatch(cookies)?.group(1);
        if (access == null) return false;
        await saveTokens(access, refresh ?? _refresh);
        return true;
      } catch (_) {
        return false;
      } finally {
        _refreshing = null;
      }
    }();
  }

  dynamic _decode(Response res) {
    final data = res.data;
    final status = res.statusCode ?? 500;
    if (status >= 400) {
      final map = data is Map ? data : const {};
      throw ApiException(
        (map['error'] ?? map['message'] ?? 'Request failed ($status)').toString(),
        code: map['code']?.toString(),
        status: status,
      );
    }
    return data is Map || data is List ? data : <String, dynamic>{};
  }
}

String guessMimeType(String filename) {
  final ext = filename.split('.').last.toLowerCase();
  const map = {
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'heic': 'image/heic',
    'pdf': 'application/pdf',
    'txt': 'text/plain',
    'csv': 'text/csv',
    'mp3': 'audio/mpeg',
    'm4a': 'audio/mp4',
    'wav': 'audio/wav',
    'mp4': 'video/mp4',
    'mov': 'video/quicktime',
    'zip': 'application/zip',
    'doc': 'application/msword',
    'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls': 'application/vnd.ms-excel',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'ppt': 'application/vnd.ms-powerpoint',
    'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  };
  return map[ext] ?? 'application/octet-stream';
}

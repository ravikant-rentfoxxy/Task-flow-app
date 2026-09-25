import 'dart:convert';
import 'dart:developer' as developer;

import 'package:dio/dio.dart';

/// Logs every API request and response (method, URL, status, duration, bodies).
///
/// Tokens, cookies and passwords are redacted, and long bodies are truncated.
/// Output goes to `dart:developer` log (visible in the IDE debug console / DevTools).
class ApiLogger extends Interceptor {
  ApiLogger({this.maxBodyLength = 1200, this.logBodies = true, void Function(String message)? sink})
      : _sink = sink ?? ((m) => developer.log(m, name: 'API'));

  final int maxBodyLength;
  final bool logBodies;
  final void Function(String message) _sink;

  static const _startKey = 'tf_log_start';
  static const _secretKeys = {
    'password',
    'newpassword',
    'confirmpassword',
    'otp',
    'accesstoken',
    'refreshtoken',
    'authorization',
    'cookie',
    'set-cookie',
  };

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_startKey] = DateTime.now().millisecondsSinceEpoch;
    final lines = ['→ ${options.method} ${options.uri}'];
    final headers = _redactHeaders(options.headers);
    if (headers.isNotEmpty) lines.add('  headers: $headers');
    if (logBodies && options.data != null) lines.add('  body: ${_body(options.data)}');
    _sink(lines.join('\n'));
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final req = response.requestOptions;
    final status = response.statusCode ?? 0;
    final mark = status >= 400 ? '✗' : '←';
    final lines = ['$mark $status ${req.method} ${req.uri} (${_elapsed(req)} ms)'];
    if (logBodies && response.data != null) lines.add('  body: ${_body(response.data)}');
    _sink(lines.join('\n'));
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final req = err.requestOptions;
    _sink('✗ ${err.type.name} ${req.method} ${req.uri} (${_elapsed(req)} ms)'
        '${err.message == null ? '' : '\n  error: ${err.message}'}');
    handler.next(err);
  }

  int _elapsed(RequestOptions req) {
    final start = req.extra[_startKey];
    return start is int ? DateTime.now().millisecondsSinceEpoch - start : -1;
  }

  Map<String, dynamic> _redactHeaders(Map<String, dynamic> headers) => {
        for (final e in headers.entries)
          if (e.key.toLowerCase() != 'content-type') e.key: _isSecret(e.key) ? '***' : e.value,
      };

  String _body(dynamic data) {
    String text;
    if (data is FormData) {
      text = jsonEncode({
        'fields': {for (final f in data.fields) f.key: _isSecret(f.key) ? '***' : f.value},
        'files': [for (final f in data.files) '${f.key}: ${f.value.filename} (${f.value.length} bytes)'],
      });
    } else if (data is List<int>) {
      text = '<${data.length} bytes>';
    } else if (data is Map || data is List) {
      text = jsonEncode(_redact(data));
    } else {
      text = data.toString();
    }
    return text.length > maxBodyLength ? '${text.substring(0, maxBodyLength)}… (${text.length} chars)' : text;
  }

  dynamic _redact(dynamic v) {
    if (v is Map) {
      return {for (final e in v.entries) e.key: _isSecret('${e.key}') ? '***' : _redact(e.value)};
    }
    if (v is List) return v.map(_redact).toList();
    return v;
  }

  bool _isSecret(String key) => _secretKeys.contains(key.toLowerCase());
}

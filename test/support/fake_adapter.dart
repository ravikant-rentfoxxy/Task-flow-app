import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

class FakeResponse {
  FakeResponse(this.status, this.body, {this.headers = const {}});
  final int status;
  final Object? body;
  final Map<String, List<String>> headers;
}

typedef FakeHandler = Future<FakeResponse> Function(RequestOptions req);

/// Dio adapter that answers requests from a Dart function instead of the network.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handler);
  final FakeHandler handler;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final r = await handler(options);
    final bytes = r.body is List<int> ? r.body as List<int> : utf8.encode(jsonEncode(r.body));
    return ResponseBody.fromBytes(bytes, r.status, headers: {
      Headers.contentTypeHeader: [r.body is List<int> ? 'application/octet-stream' : 'application/json'],
      ...r.headers,
    });
  }

  @override
  void close({bool force = false}) {}
}

Dio fakeDio(FakeHandler handler) => Dio()..httpClientAdapter = FakeAdapter(handler);

/// JSON body of a request (null for multipart / empty bodies).
dynamic jsonBody(RequestOptions r) => r.data is Map || r.data is List ? r.data : null;

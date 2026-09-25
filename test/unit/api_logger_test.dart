import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/core/api_client.dart';
import 'package:taskflow/core/api_logger.dart';
import 'package:taskflow/data/taskflow_api.dart';

import '../support/fake_adapter.dart';

void main() {
  late List<String> logs;
  late Dio dio;

  setUp(() {
    logs = [];
    dio = fakeDio((req) async {
      if (req.path.endsWith('/auth/login')) {
        return FakeResponse(200, {'ok': true, 'accessToken': 'SECRET_A', 'refreshToken': 'SECRET_R', 'user': {'id': 1}});
      }
      if (req.path.endsWith('/tasks/9')) return FakeResponse(404, {'error': 'Task not found'});
      return FakeResponse(200, {'tasks': [], 'pagination': {'page': 1}});
    });
    dio.interceptors.add(ApiLogger(sink: logs.add));
  });

  test('logs request and response with method, url, status and body', () async {
    final api = ApiClient(baseUrl: 'http://h/api', dio: dio, logRequests: false);
    await api.get('/tasks', query: {'filter': 'mine'});
    expect(logs, hasLength(2));
    expect(logs[0], startsWith('→ GET http://h/api/tasks?filter=mine'));
    expect(logs[1], matches(RegExp(r'^← 200 GET http://h/api/tasks\?filter=mine \(\d+ ms\)')));
    expect(logs[1], contains('"tasks":[]'));
  });

  test('redacts passwords, tokens and auth headers', () async {
    final client = ApiClient(baseUrl: 'http://h/api', dio: dio, logRequests: false);
    await TaskFlowApi(client).login('a@x.com', 'hunter2');
    await client.get('/tasks');
    final all = logs.join('\n');
    expect(all, isNot(contains('hunter2')));
    expect(all, isNot(contains('SECRET_A')));
    expect(all, isNot(contains('SECRET_R')));
    expect(all, contains('"password":"***"'));
    expect(all, contains('"accessToken":"***"'));
    expect(all, contains('Authorization: ***'));
    expect(all, contains('a@x.com'), reason: 'non-secret fields stay visible');
  });

  test('marks error responses and summarises uploads', () async {
    final client = ApiClient(baseUrl: 'http://h/api', dio: dio, logRequests: false);
    await expectLater(client.get('/tasks/9'), throwsA(isA<ApiException>()));
    expect(logs.last, startsWith('✗ 404 GET http://h/api/tasks/9'));
    expect(logs.last, contains('Task not found'));

    await client.upload('/uploads', bytes: List.filled(10, 1), filename: 'a.png', fields: {'projectId': '3'});
    expect(logs.firstWhere((l) => l.startsWith('→ POST http://h/api/uploads')), contains('a.png (10 bytes)'));
  });

  test('truncates long bodies', () async {
    final big = Dio()
      ..httpClientAdapter = FakeAdapter((_) async => FakeResponse(200, {'text': 'x' * 5000}))
      ..interceptors.add(ApiLogger(sink: logs.add, maxBodyLength: 100));
    await ApiClient(baseUrl: 'http://h/api', dio: big, logRequests: false).get('/big');
    expect(logs.last, contains('… ('));
    expect(logs.last.length, lessThan(300));
  });

  test('client adds the logger once when enabled', () {
    final d = Dio();
    ApiClient(baseUrl: 'http://h/api', dio: d, logRequests: true);
    ApiClient(baseUrl: 'http://h/api', dio: d, logRequests: true);
    expect(d.interceptors.whereType<ApiLogger>(), hasLength(1));
    expect(ApiClient(baseUrl: 'http://h/api', logRequests: false).dio.interceptors.whereType<ApiLogger>(), isEmpty);
  });
}

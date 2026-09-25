import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:taskflow/core/api_client.dart';
import 'package:taskflow/core/local_store.dart';
import 'package:taskflow/data/taskflow_api.dart';
import 'package:taskflow/state/auth_controller.dart';

import '../support/fake_adapter.dart';

const meJson = {'id': 1, 'name': 'Admin', 'email': 'a@x.com', 'role': 'ADMIN', 'team_id': null, 'team': null};

void main() {
  test('login stores tokens and sends bearer on later calls', () async {
    final seen = <RequestOptions>[];
    final dio = fakeDio((req) async {
      seen.add(req);
      if (req.path.endsWith('/auth/login')) return FakeResponse(200, {'ok': true, 'accessToken': 'A1', 'refreshToken': 'R1'});
      return FakeResponse(200, {'user': meJson, 'unread': 3});
    });
    final store = MemoryTokenStore();
    final api = TaskFlowApi(ApiClient(baseUrl: 'http://h/api/', dio: dio, store: store));
    await api.login('a@x.com', 'pw');
    final me = await api.me();
    expect(me.me.isAdmin, isTrue);
    expect(me.unread, 3);
    expect(store.access, 'A1');
    expect(store.refresh, 'R1');
    expect(seen.last.headers['Authorization'], 'Bearer A1');
    expect(seen.first.uri.toString(), 'http://h/api/auth/login');
    expect(jsonBody(seen.first), {'email': 'a@x.com', 'password': 'pw'});
    expect(api.client.cookieHeader, 'accessToken=A1; refreshToken=R1');
  });

  test('errors carry message, code and status', () async {
    final api = ApiClient(
      baseUrl: 'http://h/api',
      dio: fakeDio((_) async => FakeResponse(400, {'error': 'Close subtasks first', 'code': 'OPEN_SUBTASKS'})),
    );
    await expectLater(
      api.patch('/tasks/1', {'action': 'done'}),
      throwsA(isA<ApiException>()
          .having((e) => e.code, 'code', 'OPEN_SUBTASKS')
          .having((e) => e.status, 'status', 400)
          .having((e) => e.message, 'message', 'Close subtasks first')),
    );
  });

  test('401 refreshes via cookie and retries once', () async {
    var calls = 0;
    final dio = fakeDio((req) async {
      if (req.path.endsWith('/auth/refresh')) {
        expect(req.headers['Cookie'], 'refreshToken=R1');
        return FakeResponse(200, {'ok': true}, headers: {
          'set-cookie': ['accessToken=A2; Path=/; HttpOnly', 'refreshToken=R2; Path=/; HttpOnly'],
        });
      }
      calls++;
      if (req.headers['Authorization'] == 'Bearer A1') return FakeResponse(401, {'error': 'Please authenticate'});
      return FakeResponse(200, {'tasks': [], 'pagination': {'page': 1, 'limit': 15, 'total': 0, 'totalPages': 1}});
    });
    final store = MemoryTokenStore()
      ..access = 'A1'
      ..refresh = 'R1';
    final c = ApiClient(baseUrl: 'http://h/api', dio: dio, store: store);
    await c.restore();
    final page = await TaskFlowApi(c).tasks(const TaskQuery());
    expect(page.tasks, isEmpty);
    expect(calls, 2);
    expect(store.access, 'A2');
    expect(store.refresh, 'R2');
  });

  test('failed refresh reports session expiry', () async {
    var expired = false;
    final c = ApiClient(
      baseUrl: 'http://h/api',
      dio: fakeDio((_) async => FakeResponse(401, {'error': 'Please authenticate'})),
      store: MemoryTokenStore()..refresh = 'R',
    )..onSessionExpired = () => expired = true;
    await c.restore();
    await expectLater(c.get('/me'), throwsA(isA<ApiException>().having((e) => e.isUnauthorized, 'unauthorized', isTrue)));
    expect(expired, isTrue);
  });

  test('network failure becomes a friendly ApiException', () async {
    final c = ApiClient(
      baseUrl: 'http://h/api',
      dio: fakeDio((r) async => throw DioException.connectionError(requestOptions: r, reason: 'socket')),
    );
    await expectLater(c.get('/me'), throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('reach the server'))));
  });

  test('query builder drops empty values and TaskQuery maps filters', () {
    final c = ApiClient(baseUrl: 'http://h/api');
    final u = c.uri('/tasks', const TaskQuery(filter: 'all', status: '', q: 'lead', assigneeId: 4, page: 2).toQuery());
    expect(u.queryParameters, {'filter': 'all', 'q': 'lead', 'assigneeId': '4', 'page': '2', 'limit': '15'});
  });

  test('upload sends multipart with file and fields', () async {
    late RequestOptions captured;
    final api = TaskFlowApi(ApiClient(
      baseUrl: 'http://h/api',
      dio: fakeDio((req) async {
        captured = req;
        return FakeResponse(200, {'id': 9, 'fileName': 'a.png', 'mimeType': 'image/png'});
      }),
    ));
    final a = await api.upload([1, 2, 3], 'a.png', projectId: 3);
    expect(a.id, 9);
    expect(a.isImage, isTrue);
    final form = captured.data as FormData;
    expect({for (final f in form.fields) f.key: f.value}, {'projectId': '3'});
    expect(form.files.single.value.filename, 'a.png');
    expect(form.files.single.value.contentType.toString(), 'image/png');
  });

  test('download returns raw bytes', () async {
    final c = ApiClient(baseUrl: 'http://h/api', dio: fakeDio((_) async => FakeResponse(200, [104, 105])));
    expect(await c.getBytes('/uploads/1'), [104, 105]);
  });

  group('Hive session storage', () {
    late Directory dir;
    late LocalStore store;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('tf_hive');
      Hive.init(dir.path);
      store = LocalStore(await Hive.openBox(LocalStore.sessionBoxName), await Hive.openBox(LocalStore.appBoxName));
    });

    tearDown(() async {
      await Hive.deleteFromDisk();
      await dir.delete(recursive: true);
    });

    test('tokens and user survive, logout clears them', () async {
      final tokens = HiveTokenStore(store);
      await tokens.write('A', 'R');
      await store.saveUser(meJson);
      expect(await tokens.read(), (access: 'A', refresh: 'R'));
      expect(store.user?['email'], 'a@x.com');
      await tokens.clear();
      expect(store.accessToken, isNull);
      expect(store.user, isNull);
    });

    test('AuthController restores cached user and caches fresh profile', () async {
      await store.saveTokens('A', 'R');
      await store.saveUser({...meJson, 'name': 'Cached Name'});
      final api = TaskFlowApi(ApiClient(
        baseUrl: 'http://h/api',
        store: HiveTokenStore(store),
        dio: fakeDio((_) async => FakeResponse(200, {'user': {...meJson, 'name': 'Fresh Name'}, 'unread': 2})),
      ));
      final auth = AuthController(api, store: store, pollInterval: Duration.zero);
      await auth.init();
      expect(auth.status, AuthStatus.signedIn);
      expect(auth.me?.name, 'Fresh Name');
      expect(auth.unread, 2);
      expect(store.user?['name'], 'Fresh Name');
    });

    test('offline start keeps the cached session; 401 signs out', () async {
      await store.saveTokens('A', 'R');
      await store.saveUser(meJson);
      final offline = TaskFlowApi(ApiClient(
        baseUrl: 'http://h/api',
        store: HiveTokenStore(store),
        dio: fakeDio((r) async => throw DioException.connectionError(requestOptions: r, reason: 'offline')),
      ));
      final a1 = AuthController(offline, store: store, pollInterval: Duration.zero);
      await a1.init();
      expect(a1.status, AuthStatus.signedIn);
      expect(a1.me?.email, 'a@x.com');

      final revoked = TaskFlowApi(ApiClient(
        baseUrl: 'http://h/api',
        store: HiveTokenStore(store),
        dio: fakeDio((_) async => FakeResponse(401, {'error': 'Please authenticate'})),
      ));
      final a2 = AuthController(revoked, store: store, pollInterval: Duration.zero);
      await a2.init();
      expect(a2.status, AuthStatus.signedOut);
      expect(store.accessToken, isNull);
    });
  });
}

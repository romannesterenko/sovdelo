import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sovdelo_probe/account_store.dart';
import 'package:sovdelo_probe/account_sync.dart';
import 'package:sovdelo_probe/workspace_api.dart';

Map<String, dynamic> remote(int id, String uuid, {int version = 1, String status = 'todo', bool active = true}) => {
  'id': id, 'uuid': uuid, 'version': version, 'title': 'Задача', 'status': status, 'active': active,
};

void main() {
  sqfliteFfiInit();
  late Directory dir;
  late AccountStore store;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('account-sync-');
    store = await AccountStore.open(databaseFactoryFfi, '${dir.path}/account.db');
  });
  tearDown(() async { await store.db.close(); await dir.delete(recursive: true); });

  test('Очередь и точное тело сохраняются после перезапуска и последующих правок', () async {
    await store.add('Задача');
    final task = (await store.tasks()).single;
    final first = await store.prepare();
    await store.setStatus(task['local_id'] as String, 'done');
    expect((await store.prepare())!['body'], first!['body']);
    await store.db.close();
    store = await AccountStore.open(databaseFactoryFfi, '${dir.path}/account.db');
    expect((await store.prepare())!['body'], first['body']);
    expect(await store.pendingCount(), 2);
  });

  test('Потерянный ответ создания не дублирует задачу при pull перед повтором', () async {
    await store.add('Задача');
    final local = (await store.tasks()).single;
    await store.setStatus(local['local_id'] as String, 'done');
    final receipts = <String, Map<String, dynamic>>{};
    Map<String, dynamic>? server;
    var loseFirstReply = true;
    var creates = 0;
    final api = WorkspaceApi(transport: (method, path, token, body) async {
      if (path.startsWith('projects?')) return {'data': [], 'meta': {'last_page': 1}};
      if (method == 'GET') return {'data': server == null ? [] : [server],
        'meta': {'through_id': server == null ? 0 : 7, 'after_id': 7, 'has_more': false}};
      final request = body!;
      final key = request['operation_uuid'] as String;
      if (receipts.containsKey(key)) return {'data': receipts[key]};
      if (request['kind'] == 'create') {
        creates++; server = remote(7, key);
      } else {
        expect(request['expected_version'], server!['version']);
        server = {...server!, 'status': request['status'], 'version': (server!['version'] as int) + 1};
      }
      final receipt = {'operation_uuid': key, 'task': {...server!}};
      receipts[key] = receipt;
      if (loseFirstReply) { loseFirstReply = false; throw const ApiFailure(0, 'Reply lost'); }
      return {'data': receipt};
    });
    final sync = AccountSync(api, store);
    await expectLater(sync.synchronize('token', write: true), throwsA(isA<ApiFailure>()));
    expect(await store.pendingCount(), 2);
    expect(await sync.synchronize('token', write: true), 2);
    expect(creates, 1);
    expect(await store.pendingCount(), 0);
    expect((await store.tasks()).length, 1);
    expect((await store.tasks()).single['status'], 'done');
    expect(server!['status'], 'done');
  });

  test('Pull не перезаписывает офлайн-правку и её ожидаемую серверную версию', () async {
    final task = remote(1, operationUuid());
    await store.merge([task]);
    final local = (await store.tasks()).single;
    await store.setStatus(local['local_id'] as String, 'done');
    await store.merge([{...task, 'version': 2, 'status': 'doing'}]);
    final op = await store.prepare();
    expect(jsonDecode(op!['body'] as String)['expected_version'], 1);
    expect((await store.tasks()).single['status'], 'done');
    expect(jsonDecode((await store.tasks()).single['remote_json'] as String)['status'], 'doing');
  });

  test('409 блокирует только конфликтную задачу, не очищает её очередь', () async {
    final task = remote(1, operationUuid());
    await store.merge([task]);
    final local = (await store.tasks()).single;
    await store.setStatus(local['local_id'] as String, 'done');
    await store.setStatus(local['local_id'] as String, 'todo');
    final api = WorkspaceApi(transport: (method, path, token, body) async {
      if (path.startsWith('projects?')) return {'data': [], 'meta': {'last_page': 1}};
      if (method == 'POST') throw const ApiFailure(409, 'Conflict');
      return {'data': [task], 'meta': {'through_id': 1, 'after_id': 1, 'has_more': false}};
    });
    await AccountSync(api, store).synchronize('token', write: true);
    expect(await store.pendingCount(), 2);
    expect((await store.tasks()).single['blocked'], 1);
    expect(await store.prepare(), isNull);
    await store.acceptServer(local['local_id'] as String, {...task, 'version': 2, 'status': 'doing'});
    expect(await store.pendingCount(), 0);
    expect((await store.tasks()).single['status'], 'doing');
  });

  test('Незавершённый обход не затирает прежний кэш', () async {
    final task = remote(1, operationUuid());
    await store.merge([task]);
    var call = 0;
    final api = WorkspaceApi(transport: (method, path, token, body) async {
      if (path.startsWith('projects?')) return {'data': [], 'meta': {'last_page': 1}};
      call++;
      if (call == 2) throw const ApiFailure(0, 'Offline');
      return {'data': [remote(2, operationUuid())], 'meta': {'through_id': 3, 'after_id': 2, 'has_more': true}};
    });
    await expectLater(AccountSync(api, store).pull('token'), throwsA(isA<ApiFailure>()));
    expect((await store.tasks()).single['server_id'], 1);
  });

  test('Чистая удалённая задача скрывается, грязная сохраняется', () async {
    final a = remote(1, operationUuid()), b = remote(2, operationUuid());
    await store.merge([a, b]);
    final local = (await store.tasks()).firstWhere((r) => r['server_id'] == 1);
    await store.setStatus(local['local_id'] as String, 'done');
    await store.merge([]);
    expect((await store.tasks()).length, 1);
    expect((await store.tasks()).single['server_id'], 1);
    expect(await store.pendingCount(), 1);
  });

  test('Read-сессия не отправляет очередь', () async {
    await store.add('Задача');
    final api = WorkspaceApi(transport: (method, path, token, body) async {
      if (path.startsWith('projects?')) return {'data': [], 'meta': {'last_page': 1}};
      expect(method, 'GET');
      return {'data': [], 'meta': {'through_id': 0, 'after_id': 0, 'has_more': false}};
    });
    await AccountSync(api, store).synchronize('read', write: false);
    expect(await store.pendingCount(), 1);
  });

  test('SQLite разных аккаунтов не делит очередь', () async {
    await store.add('Аккаунт 1');
    final other = await AccountStore.open(databaseFactoryFfi, '${dir.path}/other.db');
    try { expect(await other.tasks(), isEmpty); expect(await other.pendingCount(), 0); }
    finally { await other.db.close(); }
  });
  test('Сбой SQLite-очереди откатывает создание задачи аккаунта', () async {
    await store.db.execute("CREATE TRIGGER fail_account_queue BEFORE INSERT ON account_queue "
        "BEGIN SELECT RAISE(ABORT, 'test failure'); END");
    await expectLater(store.add('Не сохранится'), throwsA(isA<DatabaseException>()));
    expect(await store.tasks(), isEmpty);
    expect(await store.pendingCount(), 0);
  });

  test('401 оставляет точное тело очереди для повторного входа', () async {
    await store.add('Задача');
    final original = await store.prepare();
    final api = WorkspaceApi(transport: (method, path, token, body) async {
      if (path.startsWith('projects?')) return {'data': [], 'meta': {'last_page': 1}};
      throw const ApiFailure(401, 'Revoked');
    });
    await expectLater(AccountSync(api, store).synchronize('expired', write: true), throwsA(isA<ApiFailure>()));
    expect(await store.pendingCount(), 1);
    expect((await store.prepare())!['body'], original!['body']);
  });

}

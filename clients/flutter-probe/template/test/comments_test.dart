import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sovdelo_probe/account_store.dart';
import 'package:sovdelo_probe/account_sync.dart';
import 'package:sovdelo_probe/comments_sync.dart';
import 'package:sovdelo_probe/workspace_api.dart';

void main() {
  sqfliteFfiInit();
  late Directory dir;
  late AccountStore store;
  final taskUuid = operationUuid();
  Map<String, dynamic> task({int count = 0}) => {'id': 7, 'uuid': taskUuid, 'version': 1,
    'title': 'Задача', 'status': 'todo', 'active': true, 'comments_count': count};
  Map<String, dynamic> comment(String uuid, {String body = 'Текст', int id = 11}) => {
    'id': id, 'uuid': uuid, 'task_id': 7, 'body': body, 'author': 'Роман',
    'created_at': '2026-11-15T10:00:00Z', 'updated_at': '2026-11-15T10:00:00Z',
  };
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('comments-');
    store = await AccountStore.open(databaseFactoryFfi, '${dir.path}/account.db');
    await store.merge([task()]);
  });
  tearDown(() async { await store.db.close(); await dir.delete(recursive: true); });

  test('Комментарий и точное тело сохраняются после перезапуска', () async {
    await store.addComment(taskUuid, '  Текст  ', 'Роман');
    final first = (await store.prepareComment())!;
    final body = jsonDecode(first['request_json'] as String) as Map;
    expect(body['comment_body'], 'Текст'); expect(body.containsKey('expected_version'), isFalse);
    await store.db.close();
    store = await AccountStore.open(databaseFactoryFfi, '${dir.path}/account.db');
    expect((await store.prepareComment())!['request_json'], first['request_json']);
    expect(await store.pendingCount(), 1);
    expect((await store.comments(taskUuid)).single['state'], 'pending');
  });

  test('Потеря ответа не создаёт дубликат после повторной отправки', () async {
    await store.addComment(taskUuid, 'Текст', 'Роман');
    Map<String, dynamic>? saved;
    Map<String, dynamic>? receipt;
    var creates = 0;
    final api = WorkspaceApi(transport: (method, path, token, body) async {
      if (path.startsWith('labels?')) return {'data': [], 'meta': {'through_id': 0, 'after_id': 0, 'has_more': false}};
      if (path.startsWith('projects?')) return {'data': [], 'meta': {'last_page': 1}};
      if (path.startsWith('tasks/7/comments?')) return {'data': saved == null ? [] : [saved],
        'meta': {'through_id': 11, 'after_id': 11, 'has_more': false}};
      if (method == 'GET') return {'data': [task(count: saved == null ? 0 : 1)],
        'meta': {'through_id': 7, 'after_id': 7, 'has_more': false}};
      final request = body!;
      expect(request['kind'], 'comment');
      if (receipt != null) return {'data': receipt};
      creates++; saved = comment(request['operation_uuid'] as String);
      receipt = {'operation_uuid': request['operation_uuid'], 'comment': saved, 'task': task(count: 1)};
      throw const ApiFailure(0, 'Reply lost');
    });
    await expectLater(AccountSync(api, store).synchronize('token', write: true), throwsA(isA<ApiFailure>()));
    expect(await store.pendingCount(), 1);
    await AccountSync(api, store).synchronize('token', write: true);
    expect(creates, 1); expect(await store.pendingCount(), 0);
    expect((await store.comments(taskUuid)).length, 1);
    expect((await store.comments(taskUuid)).single['state'], 'sent');
    expect((await store.task(taskUuid))['server_version'], 1);
  });

  test('Чтение уже записанного комментария узнаёт его UUID и не дублирует локальный', () async {
    await store.addComment(taskUuid, 'Текст', 'Роман');
    final op = (await store.prepareComment())!;
    await store.mergeComments(taskUuid, [comment(op['local_id'] as String)]);
    expect(await store.pendingCount(), 0);
    expect((await store.comments(taskUuid)).length, 1);
    expect(await store.prepareComment(), isNull);
  });

  test('Комментарий к офлайн-задаче ждёт подтверждения создания', () async {
    await store.add('Офлайн задача');
    final local = (await store.tasks()).firstWhere((t) => t['server_id'] == null);
    final id = local['local_id'] as String;
    await store.addComment(id, 'К новой задаче', 'Роман');
    expect(await store.prepareComment(), isNull);
    final creation = (await store.prepare())!;
    await store.acknowledge(creation, {'operation_uuid': creation['operation_uuid'], 'task': {...task(), 'uuid': id, 'id': 9}});
    final prepared = (await store.prepareComment())!;
    expect(jsonDecode(prepared['request_json'] as String)['task_id'], 9);
  });

  test('Полное обновление отражает правки/удаления сайта, сохраняя неотправленное', () async {
    final uuid = operationUuid();
    await store.mergeComments(taskUuid, [comment(uuid)]);
    await store.addComment(taskUuid, 'Локальное', 'Роман');
    await store.mergeComments(taskUuid, [comment(uuid, body: 'Изменён на сайте')]);
    expect((await store.comments(taskUuid)).first['body'], 'Изменён на сайте');
    await store.mergeComments(taskUuid, []);
    expect((await store.comments(taskUuid)).length, 1);
    expect((await store.comments(taskUuid)).single['body'], 'Локальное');
  });

  test('Незавершённый обход не очищает историю', () async {
    await store.mergeComments(taskUuid, [comment(operationUuid())]);
    var calls = 0;
    final api = WorkspaceApi(transport: (method, path, token, body) async {
      if (path.startsWith('labels?')) return {'data': [], 'meta': {'through_id': 0, 'after_id': 0, 'has_more': false}};
      calls++;
      if (calls == 2) throw const ApiFailure(0, 'Offline');
      return {'data': [comment(operationUuid(), body: 'Не применять')],
        'meta': {'through_id': 12, 'after_id': 11, 'has_more': true}};
    });
    await expectLater(CommentsSync.refresh(api, store, 'token', taskUuid), throwsA(isA<ApiFailure>()));
    expect((await store.comments(taskUuid)).single['body'], 'Текст');
  });

  test('Конфликт полей не удаляет комментарии, блокированный комментарий не скрывает задачу', () async {
    await store.addComment(taskUuid, 'Отдельное обсуждение', 'Роман');
    final op = (await store.prepareComment())!;
    await store.blockComment(op['local_id'] as String, 'Недоступно');
    await store.acceptServer(taskUuid, {...task(), 'active': false});
    expect((await store.tasks()).length, 1);
    expect(await store.pendingCount(), 1);
    await store.retryComment(op['local_id'] as String);
    expect((await store.prepareComment())!['request_json'], op['request_json']);
    await store.blockComment(op['local_id'] as String, 'Недоступно');
    await store.discardComment(op['local_id'] as String);
    expect(await store.pendingCount(), 0);
    expect(await store.tasks(), isEmpty);
  });

  test('Валидация и ошибка SQLite не создают полузаписанное сообщение', () async {
    await expectLater(store.addComment(taskUuid, '  ', 'Роман'), throwsArgumentError);
    await store.db.execute("CREATE TRIGGER fail_comment BEFORE INSERT ON account_comments BEGIN SELECT RAISE(ABORT, 'test failure'); END");
    await expectLater(store.addComment(taskUuid, 'Текст', 'Роман'), throwsA(isA<DatabaseException>()));
    expect(await store.comments(taskUuid), isEmpty); expect(await store.pendingCount(), 0);
  });

  test('Миграция v3 не меняет замороженную операцию полей', () async {
    await store.db.close();
    final path = '${dir.path}/old.db';
    final old = await databaseFactoryFfi.openDatabase(path, options: OpenDatabaseOptions(version: 3, onCreate: (db, version) async {
      await db.execute("CREATE TABLE account_tasks (local_id TEXT PRIMARY KEY, server_id INTEGER UNIQUE, server_version INTEGER, title TEXT NOT NULL, status TEXT NOT NULL, active INTEGER NOT NULL DEFAULT 1, remote_json TEXT, description TEXT, due_date TEXT, priority TEXT NOT NULL DEFAULT 'normal', project_id INTEGER, checklist_json TEXT NOT NULL DEFAULT '[]')");
      await db.execute('CREATE TABLE account_queue (sequence INTEGER PRIMARY KEY AUTOINCREMENT, operation_uuid TEXT UNIQUE NOT NULL, local_id TEXT NOT NULL, kind TEXT NOT NULL, title TEXT, status TEXT, body TEXT, blocked INTEGER NOT NULL DEFAULT 0, error TEXT, fields TEXT)');
      await db.execute('CREATE TABLE account_projects (id INTEGER PRIMARY KEY, name TEXT NOT NULL)');
    }));
    final key = operationUuid();
    final body = jsonEncode({'operation_uuid': key, 'kind': 'status', 'task_id': 7, 'expected_version': 1, 'status': 'done'});
    await old.insert('account_tasks', {'local_id': taskUuid, 'server_id': 7, 'server_version': 1, 'title': 'Задача', 'status': 'done'});
    await old.insert('account_queue', {'operation_uuid': key, 'local_id': taskUuid, 'kind': 'status', 'status': 'done', 'body': body});
    await old.close();
    store = await AccountStore.open(databaseFactoryFfi, path);
    expect((await store.prepare())!['body'], body);
    expect((await store.task(taskUuid))['status'], 'done');
    expect(await store.comments(taskUuid), isEmpty);
    await store.addComment(taskUuid, 'После обновления', 'Роман');
    expect(await store.pendingCount(), 2);
  });
}

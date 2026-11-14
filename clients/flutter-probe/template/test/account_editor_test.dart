import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sovdelo_probe/account_store.dart';

void main() {
  sqfliteFfiInit();
  late Directory dir;
  late AccountStore store;
  final uuid = operationUuid();
  Map<String, dynamic> remote({int version = 1, String title = 'Задача', String? description = 'Описание'}) => {
    'id': 7, 'uuid': uuid, 'version': version, 'title': title, 'description': description,
    'status': 'todo', 'active': true, 'priority': 'normal', 'project_id': null, 'due_date': null,
  };
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('account-edit-');
    store = await AccountStore.open(databaseFactoryFfi, '${dir.path}/account.db');
  });
  tearDown(() async { await store.db.close(); await dir.delete(recursive: true); });

  test('Офлайн-редактор сохраняет поля, проекты и очередь после перезапуска', () async {
    await store.merge([remote()], projects: [{'id': 5, 'name': 'Проект'}]);
    await store.edit(uuid, {'title': 'Новое название', 'description': 'Новый текст', 'due_date': '2026-12-25', 'priority': 'high', 'project_id': 5});
    final before = await store.prepare();
    await store.db.close();
    store = await AccountStore.open(databaseFactoryFfi, '${dir.path}/account.db');
    final task = (await store.tasks()).single;
    expect(task['title'], 'Новое название'); expect(task['description'], 'Новый текст');
    expect(task['project_id'], 5); expect(task['due_date'], '2026-12-25'); expect(task['priority'], 'high');
    expect((await store.projects()).single['name'], 'Проект');
    expect((await store.prepare())!['body'], before!['body']);
  });

  test('Правка до подтверждения создания отправляется после create с новой версией', () async {
    await store.add('Первоначальное название');
    final local = (await store.tasks()).single;
    final id = local['local_id'] as String;
    final creation = (await store.prepare())!;
    await store.edit(id, {'title': 'Исправлено', 'description': 'Офлайн текст'});
    expect(jsonDecode((await store.prepare())!['body'] as String)['title'], 'Первоначальное название');
    await store.acknowledge(creation, {'operation_uuid': creation['operation_uuid'],
      'task': {...remote(version: 2), 'uuid': id, 'title': 'Первоначальное название'}});
    expect((await store.tasks()).single['title'], 'Исправлено');
    expect((await store.tasks()).single['description'], 'Офлайн текст');
    final edit = (await store.prepare())!;
    final body = jsonDecode(edit['body'] as String) as Map;
    expect(body['kind'], 'edit'); expect(body['expected_version'], 2);
    expect(body['fields'], {'title': 'Исправлено', 'description': 'Офлайн текст'});
    await store.acknowledge(edit, {'operation_uuid': edit['operation_uuid'],
      'task': {...remote(version: 3, title: 'Исправлено', description: 'Офлайн текст'), 'uuid': id}});
    expect(await store.pendingCount(), 0);
    expect((await store.tasks()).single['description'], 'Офлайн текст');
  });

  test('Pull не затирает поля редактора и базовую версию до подтверждения', () async {
    await store.merge([remote()]);
    await store.edit(uuid, {'description': 'Мой офлайн текст'});
    await store.merge([remote(version: 2, description: 'Текст на сайте')]);
    expect((await store.tasks()).single['description'], 'Мой офлайн текст');
    final op = (await store.prepare())!;
    expect(jsonDecode(op['body'] as String)['expected_version'], 1);
    await store.acceptServer(uuid, remote(version: 2, description: 'Текст на сайте'));
    expect((await store.tasks()).single['description'], 'Текст на сайте');
    expect(await store.pendingCount(), 0);
  });

  test('Очистка срока и проекта передаёт null, неизменные поля не отправляются', () async {
    await store.merge([{...remote(), 'due_date': '2026-12-25', 'project_id': 5}]);
    await store.edit(uuid, {'title': 'Задача', 'due_date': null, 'project_id': null});
    final body = jsonDecode((await store.prepare())!['body'] as String);
    expect(body['fields'], {'due_date': null, 'project_id': null});
    await store.edit(uuid, {'title': 'Задача', 'due_date': null, 'project_id': null});
    expect(await store.pendingCount(), 1);
  });

  test('Ошибка очереди откатывает правку; некорректная дата не записывается', () async {
    await store.merge([remote()]);
    await expectLater(store.edit(uuid, {'due_date': '2026-02-31'}), throwsArgumentError);
    await expectLater(store.edit(uuid, {'user_id': 99}), throwsArgumentError);
    await store.db.execute("CREATE TRIGGER fail_edit BEFORE INSERT ON account_queue BEGIN SELECT RAISE(ABORT, 'test failure'); END");
    await expectLater(store.edit(uuid, {'title': 'Не сохранится'}), throwsA(isA<DatabaseException>()));
    expect((await store.tasks()).single['title'], 'Задача'); expect(await store.pendingCount(), 0);
  });

  test('Миграция v1 сохраняет подготовленное тело и локальный статус', () async {
    await store.db.close();
    final path = '${dir.path}/old.db';
    final old = await databaseFactoryFfi.openDatabase(path, options: OpenDatabaseOptions(version: 1, onCreate: (db, version) async {
      await db.execute('CREATE TABLE account_tasks (local_id TEXT PRIMARY KEY, server_id INTEGER UNIQUE, server_version INTEGER, title TEXT NOT NULL, status TEXT NOT NULL, active INTEGER NOT NULL DEFAULT 1, remote_json TEXT)');
      await db.execute('CREATE TABLE account_queue (sequence INTEGER PRIMARY KEY AUTOINCREMENT, operation_uuid TEXT UNIQUE NOT NULL, local_id TEXT NOT NULL, kind TEXT NOT NULL, title TEXT, status TEXT, body TEXT, blocked INTEGER NOT NULL DEFAULT 0, error TEXT)');
      await db.execute('CREATE INDEX queue_task ON account_queue(local_id, sequence)');
    }));
    final body = jsonEncode({'operation_uuid': 'fixed', 'kind': 'status', 'task_id': 7, 'expected_version': 1, 'status': 'done'});
    await old.insert('account_tasks', {'local_id': uuid, 'server_id': 7, 'server_version': 1, 'title': 'Задача', 'status': 'done', 'remote_json': jsonEncode(remote())});
    await old.insert('account_queue', {'operation_uuid': 'fixed', 'local_id': uuid, 'kind': 'status', 'status': 'done', 'body': body});
    await old.close();
    store = await AccountStore.open(databaseFactoryFfi, path);
    expect((await store.tasks()).single['status'], 'done');
    expect((await store.tasks()).single['description'], 'Описание');
    expect((await store.prepare())!['body'], body);
    expect(await store.projects(), isEmpty);
  });
}

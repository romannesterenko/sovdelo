import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sovdelo_probe/account_store.dart';
import 'package:sovdelo_probe/account_sync.dart';
import 'package:sovdelo_probe/task_labels.dart';
import 'package:sovdelo_probe/workspace_api.dart';

void main() {
  sqfliteFfiInit();
  late Directory dir;
  late AccountStore store;
  final uuid = operationUuid();
  Map<String, dynamic> task({int version = 1, List<Map<String, dynamic>> labels = const []}) =>
    {'id': 7, 'uuid': uuid, 'version': version, 'title': 'Задача', 'status': 'todo', 'active': true, 'labels': labels};
  final label = <String, dynamic>{'id': 5, 'name': 'Работа', 'color': 'red'};
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('labels-');
    store = await AccountStore.open(databaseFactoryFfi, '${dir.path}/account.db');
    await store.merge([task()]);
  });
  tearDown(() async { await store.db.close(); await dir.delete(recursive: true); });

  test('Офлайн-метка и назначение переживают рестарт; после подтверждения используются ID', () async {
    final key = await store.addLabel('Работа', 'red');
    await store.edit(uuid, {'label_keys': [key]});
    final prepared = (await store.prepareLabel())!;
    await store.db.close();
    store = await AccountStore.open(databaseFactoryFfi, '${dir.path}/account.db');
    expect((await store.prepareLabel())!['request_json'], prepared['request_json']);
    expect(TaskLabels.read((await store.task(uuid))['labels_json']), [key]);
    await store.acknowledgeLabel(prepared, {'operation_uuid': key, 'label': label});
    final op = (await store.prepare())!;
    expect(jsonDecode(op['body'] as String)['fields'], {'label_ids': [5]});
    expect(TaskLabels.read((await store.task(uuid))['labels_json']), ['server-label-5']);
    expect((await store.labels()).single['state'], 'sent');
  });

  test('Потерянный ответ создания распознаётся по каталогу без дубля', () async {
    final key = await store.addLabel('Работа', 'red');
    await store.edit(uuid, {'label_keys': [key]});
    var exists = false, assigned = false;
    var creates = 0;
    final api = WorkspaceApi(transport: (method, path, token, body) async {
      if (path.startsWith('projects?')) return {'data': [], 'meta': {'last_page': 1}};
      if (path.startsWith('labels?')) return {'data': exists ? [label] : [], 'meta': {'through_id': exists ? 5 : 0, 'after_id': 5, 'has_more': false}};
      if (method == 'GET') return {'data': [task(version: assigned ? 2 : 1, labels: assigned ? [label] : [])],
        'meta': {'through_id': 7, 'after_id': 7, 'has_more': false}};
      final request = body!;
      if (request['kind'] == 'label') { exists = true; creates++; throw const ApiFailure(0, 'Reply lost'); }
      expect(request['fields'], {'label_ids': [5]}); assigned = true;
      return {'data': {'operation_uuid': request['operation_uuid'], 'task': task(version: 2, labels: [label])}};
    });
    await expectLater(AccountSync(api, store).synchronize('token', write: true), throwsA(isA<ApiFailure>()));
    expect(await store.pendingCount(), 2);
    await AccountSync(api, store).synchronize('token', write: true);
    expect(creates, 1); expect(assigned, isTrue); expect(await store.pendingCount(), 0);
    expect((await store.labels()).length, 1);
  });

  test('Совпадение имени принимает серверный цвет и не меняет замороженное тело другой правки', () async {
    await store.edit(uuid, {'description': 'Текст'});
    final first = (await store.prepare())!;
    final key = await store.addLabel('Работа', 'red');
    await store.edit(uuid, {'label_keys': [key]});
    await store.merge([task()], labels: [{...label, 'color': 'blue'}]);
    expect((await store.labels()).single['color'], 'blue');
    expect((await store.prepare())!['body'], first['body']);
    expect(TaskLabels.read((await store.task(uuid))['labels_json']), ['server-label-5']);
  });

  test('Снятие всех меток отправляет [], одинаковый набор не создаёт операцию', () async {
    await store.merge([task(labels: [label])], labels: [label]);
    await store.edit(uuid, {'label_keys': ['server-label-5']}); expect(await store.pendingCount(), 0);
    await store.edit(uuid, {'label_keys': []});
    expect(jsonDecode((await store.prepare())!['body'] as String)['fields'], {'label_ids': []});
  });

  test('Неподтверждённая метка блокирует лишь зависимую правку, подтверждение снимает эту блокировку', () async {
    final key = await store.addLabel('Работа', 'red');
    await store.edit(uuid, {'label_keys': [key]});
    expect((await store.prepare())!['blocked'], 1);
    final pendingLabel = (await store.prepareLabel())!;
    await store.acknowledgeLabel(pendingLabel, {'operation_uuid': key, 'label': label});
    expect(jsonDecode((await store.prepare())!['body'] as String)['fields'], {'label_ids': [5]});
  });

  test('Повтор имени локально не создаёт метку, валидация не оставляет изменений', () async {
    final key = await store.addLabel(' Работа ', 'red');
    expect(await store.addLabel('Работа', 'blue'), key);
    expect((await store.labels()).length, 1);
    await expectLater(store.addLabel('', 'red'), throwsArgumentError);
    await expectLater(store.addLabel('Имя', 'invalid'), throwsArgumentError);
    await expectLater(store.edit(uuid, {'label_keys': List.generate(21, (i) => 'server-label-${i+1}')}), throwsArgumentError);
    expect(await store.pendingCount(), 1);
  });

  test('Миграция v4 сохраняет поля/очередь и узнаёт прежние метки из remote_json', () async {
    await store.db.close();
    final path = '${dir.path}/old.db';
    final old = await databaseFactoryFfi.openDatabase(path, options: OpenDatabaseOptions(version: 4, onCreate: (db, version) async {
      await db.execute("CREATE TABLE account_tasks (local_id TEXT PRIMARY KEY, server_id INTEGER UNIQUE, server_version INTEGER, title TEXT NOT NULL, status TEXT NOT NULL, active INTEGER NOT NULL DEFAULT 1, remote_json TEXT, description TEXT, due_date TEXT, priority TEXT NOT NULL DEFAULT 'normal', project_id INTEGER, checklist_json TEXT NOT NULL DEFAULT '[]')");
      await db.execute('CREATE TABLE account_queue (sequence INTEGER PRIMARY KEY AUTOINCREMENT, operation_uuid TEXT UNIQUE NOT NULL, local_id TEXT NOT NULL, kind TEXT NOT NULL, title TEXT, status TEXT, body TEXT, blocked INTEGER NOT NULL DEFAULT 0, error TEXT, fields TEXT)');
      await db.execute('CREATE TABLE account_projects (id INTEGER PRIMARY KEY, name TEXT NOT NULL)');
      await db.execute('CREATE TABLE account_comments (local_id TEXT PRIMARY KEY, server_id INTEGER UNIQUE, task_local_id TEXT NOT NULL, body TEXT NOT NULL, author TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, state TEXT NOT NULL, request_json TEXT, error TEXT)');
    }));
    final key = operationUuid();
    final body = jsonEncode({'operation_uuid': key, 'kind': 'status', 'task_id': 7, 'expected_version': 1, 'status': 'done'});
    await old.insert('account_tasks', {'local_id': uuid, 'server_id': 7, 'server_version': 1, 'title': 'Задача', 'status': 'done', 'remote_json': jsonEncode(task(labels: [label]))});
    await old.insert('account_queue', {'operation_uuid': key, 'local_id': uuid, 'kind': 'status', 'status': 'done', 'body': body});
    await old.close(); store = await AccountStore.open(databaseFactoryFfi, path);
    expect((await store.prepare())!['body'], body);
    expect((await store.task(uuid))['status'], 'done');
    expect((await store.labels()).single['name'], 'Работа');
    expect(TaskLabels.read((await store.task(uuid))['labels_json']), ['server-label-5']);
  });
}

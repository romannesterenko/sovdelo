import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sovdelo_probe/account_store.dart';
import 'package:sovdelo_probe/checklists.dart';

void main() {
  sqfliteFfiInit();
  late Directory dir;
  late AccountStore store;
  final uuid = operationUuid();
  final original = [{'text': 'Исходный', 'done': false}];
  Map<String, dynamic> task({int version = 1, List<Map<String, dynamic>>? checklist}) => {
    'id': 7, 'uuid': uuid, 'version': version, 'title': 'Задача', 'status': 'todo',
    'active': true, 'checklist': checklist ?? original,
  };
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('checklist-');
    store = await AccountStore.open(databaseFactoryFfi, '${dir.path}/account.db');
  });
  tearDown(() async { await store.db.close(); await dir.delete(recursive: true); });

  test('Добавление, переименование, удаление и отметки сохраняются в очереди после рестарта', () async {
    await store.merge([task()]);
    final changed = [{'text': '  Переименован  ', 'done': true}, {'text': 'Новый', 'done': false}];
    await store.edit(uuid, {'checklist': changed});
    final first = (await store.prepare())!;
    expect(Checklists.summary((await store.tasks()).single['checklist_json']), '1/2');
    await store.edit(uuid, {'checklist': [{'text': 'Новый', 'done': true}]});
    expect((await store.prepare())!['body'], first['body']);
    await store.db.close();
    store = await AccountStore.open(databaseFactoryFfi, '${dir.path}/account.db');
    expect(Checklists.read((await store.tasks()).single['checklist_json']), [{'text': 'Новый', 'done': true}]);
    expect(jsonDecode(first['body'] as String)['fields']['checklist'][0]['text'], 'Переименован');
    expect(await store.pendingCount(), 2);
    await store.acknowledge(first, {'operation_uuid': first['operation_uuid'], 'task': task(version: 2, checklist: Checklists.normalize(changed))});
    expect(Checklists.read((await store.tasks()).single['checklist_json']), [{'text': 'Новый', 'done': true}]);
    expect(jsonDecode((await store.prepare())!['body'] as String)['expected_version'], 2);
  });

  test('Повтор неизменённого списка не создаёт операцию, очистка отправляет []', () async {
    await store.merge([task()]);
    await store.edit(uuid, {'checklist': original});
    expect(await store.pendingCount(), 0);
    await store.edit(uuid, {'checklist': []});
    expect(Checklists.summary((await store.tasks()).single['checklist_json']), '0/0');
    expect(jsonDecode((await store.prepare())!['body'] as String)['fields'], {'checklist': []});
  });

  test('Pull сохраняет офлайн-список и базовую версию; принять сайт заменяет список', () async {
    await store.merge([task()]);
    await store.edit(uuid, {'checklist': [{'text': 'Мой', 'done': true}]});
    final server = task(version: 2, checklist: [{'text': 'Сайт', 'done': false}]);
    await store.merge([server]);
    expect(Checklists.read((await store.tasks()).single['checklist_json']).single['text'], 'Мой');
    expect(jsonDecode((await store.prepare())!['body'] as String)['expected_version'], 1);
    await store.acceptServer(uuid, server);
    expect(Checklists.read((await store.tasks()).single['checklist_json']).single['text'], 'Сайт');
    expect(await store.pendingCount(), 0);
  });

  test('Невалидный список и сбой очереди не меняют задачу', () async {
    await store.merge([task()]);
    for (final list in [null, [{'text': ' ', 'done': true}], [{'text': 'Без done'}], [{'text': 'Лишнее', 'done': true, 'id': 5}], List.filled(101, {'text': 'Пункт', 'done': false})]) {
      await expectLater(store.edit(uuid, {'title': 'Не менять', 'checklist': list}), throwsArgumentError);
    }
    await store.db.execute("CREATE TRIGGER fail_checklist BEFORE INSERT ON account_queue BEGIN SELECT RAISE(ABORT, 'test failure'); END");
    await expectLater(store.edit(uuid, {'checklist': []}), throwsA(isA<DatabaseException>()));
    expect((await store.tasks()).single['title'], 'Задача');
    expect(Checklists.read((await store.tasks()).single['checklist_json']), original);
    expect(await store.pendingCount(), 0);
  });

  test('Старые числовые отметки приводятся к bool при чтении сервера', () {
    expect(Checklists.fromRemote([{'text': 'Первый', 'done': 1}, {'text': 'Второй', 'done': '0'}]),
      [{'text': 'Первый', 'done': true}, {'text': 'Второй', 'done': false}]);
  });

  test('Большая UTF-8 правка отклоняется до записи в SQLite', () async {
    await store.merge([task()]);
    final items = List.generate(100, (_) => {'text': List.filled(500, 'я').join(), 'done': false});
    await expectLater(store.edit(uuid, {'description': List.filled(20000, 'я').join(), 'checklist': items}), throwsArgumentError);
    expect(await store.pendingCount(), 0);
    expect(Checklists.read((await store.tasks()).single['checklist_json']), original);
  });

  test('Миграция v2 сохраняет подготовленное тело, описание и чек-лист сайта', () async {
    await store.db.close();
    final path = '${dir.path}/old.db';
    final old = await databaseFactoryFfi.openDatabase(path, options: OpenDatabaseOptions(version: 2, onCreate: (db, version) async {
      await db.execute("CREATE TABLE account_tasks (local_id TEXT PRIMARY KEY, server_id INTEGER UNIQUE, server_version INTEGER, title TEXT NOT NULL, status TEXT NOT NULL, active INTEGER NOT NULL DEFAULT 1, remote_json TEXT, description TEXT, due_date TEXT, priority TEXT NOT NULL DEFAULT 'normal', project_id INTEGER)");
      await db.execute('CREATE TABLE account_queue (sequence INTEGER PRIMARY KEY AUTOINCREMENT, operation_uuid TEXT UNIQUE NOT NULL, local_id TEXT NOT NULL, kind TEXT NOT NULL, title TEXT, status TEXT, body TEXT, blocked INTEGER NOT NULL DEFAULT 0, error TEXT, fields TEXT)');
      await db.execute('CREATE TABLE account_projects (id INTEGER PRIMARY KEY, name TEXT NOT NULL)');
    }));
    final key = operationUuid();
    final body = jsonEncode({'operation_uuid': key, 'kind': 'edit', 'task_id': 7, 'expected_version': 1, 'fields': {'description': 'Офлайн'}});
    await old.insert('account_tasks', {'local_id': uuid, 'server_id': 7, 'server_version': 1, 'title': 'Задача', 'status': 'todo', 'description': 'Офлайн', 'remote_json': jsonEncode(task())});
    await old.insert('account_queue', {'operation_uuid': key, 'local_id': uuid, 'kind': 'edit', 'body': body, 'fields': jsonEncode({'description': 'Офлайн'})});
    await old.close();
    store = await AccountStore.open(databaseFactoryFfi, path);
    expect((await store.tasks()).single['description'], 'Офлайн');
    expect(Checklists.read((await store.tasks()).single['checklist_json']), original);
    expect((await store.prepare())!['body'], body);
  });
}

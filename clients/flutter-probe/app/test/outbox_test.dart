import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sovdelo_probe/store.dart';

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late String path;
  TaskStore? store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('sovdelo-outbox-');
    path = '${directory.path}/tasks.db';
  });
  tearDown(() async {
    await store?.db.close();
    store = null;
    await directory.delete(recursive: true);
  });

  test('Очередь сохраняет порядок и неизменяемые снимки после перезапуска', () async {
    store = await TaskStore.open(databaseFactoryFfi, path);
    await store!.add('Первая');
    final task = (await store!.list()).single;
    await store!.toggle(task['id'] as int, true);
    final before = await store!.pending();
    expect(before.length, 2);
    expect(before[0]['task_uuid'], task['uuid']);
    expect(before[1]['task_uuid'], task['uuid']);
    expect(before[0]['operation_uuid'], isNot(before[1]['operation_uuid']));
    expect(jsonDecode(before[0]['payload'] as String)['status'], 'todo');
    expect(jsonDecode(before[1]['payload'] as String)['status'], 'done');
    await store!.db.close();
    store = await TaskStore.open(databaseFactoryFfi, path);
    expect(await store!.pending(), before);
    expect(await store!.pendingCount(), 2);
    expect((await store!.list()).single['local_revision'], 2);
  });

  test('Повтор текущего статуса не создаёт лишнюю операцию', () async {
    store = await TaskStore.open(databaseFactoryFfi, path);
    await store!.add('Задача');
    final id = (await store!.list()).single['id'] as int;
    await store!.toggle(id, false);
    expect(await store!.pendingCount(), 1);
    await store!.toggle(id, true);
    await store!.toggle(id, true);
    expect(await store!.pendingCount(), 2);
    await expectLater(store!.toggle(999999, true), throwsStateError);
    expect(await store!.pendingCount(), 2);
  });

  test('Сбой записи очереди откатывает создание и изменение задачи', () async {
    store = await TaskStore.open(databaseFactoryFfi, path);
    await store!.add('Существующая');
    final original = (await store!.list()).single;
    await store!.db.execute("CREATE TRIGGER fail_outbox BEFORE INSERT ON outbox "
        "BEGIN SELECT RAISE(ABORT, 'test failure'); END");
    await expectLater(store!.add('Не должна сохраниться'), throwsA(isA<DatabaseException>()));
    await expectLater(store!.toggle(original['id'] as int, true), throwsA(isA<DatabaseException>()));
    expect(await store!.list(), [original]);
    expect(await store!.pendingCount(), 1);
  });

  test('Миграция v1 сохраняет старые задачи и добавляет их в очередь один раз', () async {
    final old = await databaseFactoryFfi.openDatabase(path,
        options: OpenDatabaseOptions(version: 1, onCreate: (db, version) async {
      await db.execute('CREATE TABLE tasks (id INTEGER PRIMARY KEY AUTOINCREMENT, '
          'title TEXT NOT NULL, done INTEGER NOT NULL DEFAULT 0)');
    }));
    await old.insert('tasks', {'title': 'Старая задача', 'done': 1});
    await old.close();
    store = await TaskStore.open(databaseFactoryFfi, path);
    final task = (await store!.list()).single;
    expect(task['title'], 'Старая задача');
    expect(task['done'], 1);
    expect(task['uuid'], matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    expect(await store!.pendingCount(), 1);
    final queue = await store!.pending();
    await store!.db.close();
    store = await TaskStore.open(databaseFactoryFfi, path);
    expect(await store!.pending(), queue);
    expect((await store!.list()).single['uuid'], task['uuid']);
  });

  test('Недопустимое название не меняет базу и очередь', () async {
    store = await TaskStore.open(databaseFactoryFfi, path);
    await store!.add('   ');
    await expectLater(store!.add(List.filled(241, 'я').join()), throwsArgumentError);
    expect(await store!.list(), isEmpty);
    expect(await store!.pending(), isEmpty);
  });
}

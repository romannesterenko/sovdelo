import 'dart:convert';
import 'dart:math';
import 'package:sqflite_common/sqlite_api.dart';

/// Local-only repository. No operation is sent until account binding and sync exist.
class TaskStore {
  final Database db;
  TaskStore(this.db);

  static String _uuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  static Future<TaskStore> open(DatabaseFactory factory, String path) async {
    final db = await factory.openDatabase(path,
        options: OpenDatabaseOptions(
      version: 2,
      onCreate: (db, version) async {
        await db.execute('CREATE TABLE tasks (id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'title TEXT NOT NULL, done INTEGER NOT NULL DEFAULT 0, '
            'uuid TEXT NOT NULL UNIQUE, local_revision INTEGER NOT NULL DEFAULT 1)');
        await _createOutbox(db);
      },
      onUpgrade: (db, old, version) async {
        if (old < 2) {
          await db.execute('ALTER TABLE tasks ADD COLUMN uuid TEXT');
          await db.execute('ALTER TABLE tasks ADD COLUMN local_revision INTEGER NOT NULL DEFAULT 1');
          await _createOutbox(db);
          for (final row in await db.query('tasks')) {
            final uuid = _uuid();
            await db.update('tasks', {'uuid': uuid}, where: 'id = ?', whereArgs: [row['id']]);
            await _enqueue(db, uuid, 1, 'create', row['title'] as String, row['done'] == 1);
          }
          await db.execute('CREATE UNIQUE INDEX tasks_uuid ON tasks(uuid)');
        }
      },
    ));
    return TaskStore(db);
  }

  static Future<void> _createOutbox(DatabaseExecutor db) async {
    await db.execute('CREATE TABLE outbox ('
        'sequence INTEGER PRIMARY KEY AUTOINCREMENT, '
        'operation_uuid TEXT NOT NULL UNIQUE, task_uuid TEXT NOT NULL, '
        'local_revision INTEGER NOT NULL, kind TEXT NOT NULL, '
        'payload TEXT NOT NULL, created_at TEXT NOT NULL, '
        'UNIQUE(task_uuid, local_revision))');
  }

  static Future<void> _enqueue(DatabaseExecutor db, String taskUuid, int revision,
      String kind, String title, bool done) async {
    await db.insert('outbox', {
      'operation_uuid': _uuid(),
      'task_uuid': taskUuid,
      'local_revision': revision,
      'kind': kind,
      'payload': jsonEncode({'title': title, 'status': done ? 'done' : 'todo'}),
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<List<Map<String, Object?>>> list() => db.query('tasks', orderBy: 'id DESC');

  Future<int> pendingCount() async {
    final rows = await db.rawQuery('SELECT COUNT(*) AS count FROM outbox');
    return rows.single['count'] as int;
  }

  /// Immutable snapshots in insertion order; this does NOT acknowledge delivery.
  Future<List<Map<String, Object?>>> pending() => db.query('outbox', orderBy: 'sequence');

  Future<void> add(String title) async {
    final text = title.trim();
    if (text.isEmpty) return;
    if (text.length > 240) throw ArgumentError('Название — не более 240 символов');
    await db.transaction((tx) async {
      final uuid = _uuid();
      await tx.insert('tasks', {'title': text, 'done': 0, 'uuid': uuid, 'local_revision': 1});
      await _enqueue(tx, uuid, 1, 'create', text, false);
    });
  }

  Future<void> toggle(int id, bool done) async {
    await db.transaction((tx) async {
      final rows = await tx.query('tasks', where: 'id = ?', whereArgs: [id]);
      if (rows.isEmpty) throw StateError('Задача не найдена');
      final row = rows.single;
      if ((row['done'] == 1) == done) return;
      final revision = (row['local_revision'] as int) + 1;
      await tx.update('tasks', {'done': done ? 1 : 0, 'local_revision': revision},
          where: 'id = ?', whereArgs: [id]);
      await _enqueue(tx, row['uuid'] as String, revision, 'update', row['title'] as String, done);
    });
  }
}

import 'dart:convert';
import 'dart:math';
import 'package:sqflite_common/sqlite_api.dart';

String operationUuid() {
  final random = Random.secure();
  final b = List.generate(16, (_) => random.nextInt(256));
  b[6] = (b[6] & 15) | 64; b[8] = (b[8] & 63) | 128;
  final h = b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

class AccountStore {
  final Database db;
  AccountStore(this.db);
  static Future<AccountStore> open(DatabaseFactory factory, String path) async {
    final db = await factory.openDatabase(path, options: OpenDatabaseOptions(version: 1, onCreate: (db, version) async {
      await db.execute('CREATE TABLE account_tasks ('
          'local_id TEXT PRIMARY KEY, server_id INTEGER UNIQUE, server_version INTEGER, '
          'title TEXT NOT NULL, status TEXT NOT NULL, active INTEGER NOT NULL DEFAULT 1, remote_json TEXT)');
      await db.execute('CREATE TABLE account_queue ('
          'sequence INTEGER PRIMARY KEY AUTOINCREMENT, operation_uuid TEXT UNIQUE NOT NULL, '
          'local_id TEXT NOT NULL, kind TEXT NOT NULL, title TEXT, status TEXT, '
          'body TEXT, blocked INTEGER NOT NULL DEFAULT 0, error TEXT)');
      await db.execute('CREATE INDEX queue_task ON account_queue(local_id, sequence)');
    }));
    return AccountStore(db);
  }

  Future<List<Map<String, Object?>>> tasks() => db.rawQuery('''
    SELECT t.*, (SELECT COUNT(*) FROM account_queue q WHERE q.local_id=t.local_id) AS pending,
      (SELECT MAX(blocked) FROM account_queue q WHERE q.local_id=t.local_id) AS blocked,
      (SELECT error FROM account_queue q WHERE q.local_id=t.local_id AND blocked=1 LIMIT 1) AS error
    FROM account_tasks t WHERE t.active=1 OR EXISTS
      (SELECT 1 FROM account_queue q WHERE q.local_id=t.local_id)
    ORDER BY t.server_id IS NULL DESC, t.server_id DESC
  ''');
  Future<int> pendingCount() async => (await db.rawQuery('SELECT COUNT(*) AS n FROM account_queue')).single['n'] as int;

  Future<void> add(String title) async {
    final text = title.trim();
    if (text.isEmpty || text.length > 240) throw ArgumentError('Название: от 1 до 240 символов');
    await db.transaction((tx) async {
      final id = operationUuid();
      await tx.insert('account_tasks', {'local_id': id, 'title': text, 'status': 'todo'});
      await tx.insert('account_queue', {'operation_uuid': id, 'local_id': id, 'kind': 'create', 'title': text});
    });
  }

  Future<void> setStatus(String id, String status) async {
    if (!['todo', 'doing', 'done'].contains(status)) throw ArgumentError('Неизвестный статус');
    await db.transaction((tx) async {
      final row = (await tx.query('account_tasks', where: 'local_id=?', whereArgs: [id])).single;
      if (row['status'] == status) return;
      await tx.update('account_tasks', {'status': status}, where: 'local_id=?', whereArgs: [id]);
      await tx.insert('account_queue', {'operation_uuid': operationUuid(), 'local_id': id, 'kind': 'status', 'status': status});
    });
  }

  /// Prepare once, persist BEFORE sending. Retry always uses these same bytes/UUID.
  Future<Map<String, Object?>?> prepare() => db.transaction((tx) async {
    final rows = await tx.rawQuery('''SELECT q.* FROM account_queue q
      WHERE q.blocked=0 AND NOT EXISTS
        (SELECT 1 FROM account_queue b WHERE b.local_id=q.local_id AND b.blocked=1)
      ORDER BY q.sequence LIMIT 1''');
    if (rows.isEmpty) return null;
    final row = rows.single;
    if (row['body'] != null) return row;
    final task = (await tx.query('account_tasks', where: 'local_id=?', whereArgs: [row['local_id']])).single;
    final body = <String, dynamic>{'operation_uuid': row['operation_uuid'], 'kind': row['kind']};
    if (row['kind'] == 'create') {
      body['title'] = row['title'];
    } else {
      if (task['server_id'] == null || task['server_version'] == null) throw StateError('Нет серверной версии');
      body.addAll({'task_id': task['server_id'], 'expected_version': task['server_version'], 'status': row['status']});
    }
    final encoded = jsonEncode(body);
    await tx.update('account_queue', {'body': encoded}, where: 'sequence=?', whereArgs: [row['sequence']]);
    return {...row, 'body': encoded};
  });

  Future<void> acknowledge(Map<String, Object?> op, Map<String, dynamic> receipt) async {
    if (receipt['operation_uuid'] != op['operation_uuid'] || receipt['task'] is! Map) {
      throw StateError('Некорректное подтверждение операции');
    }
    final task = Map<String, dynamic>.from(receipt['task'] as Map);
    if (task['id'] is! int || task['version'] is! int) throw StateError('Нет версии задачи');
    await db.transaction((tx) async {
      final queue = await tx.query('account_queue', where: 'operation_uuid=?', whereArgs: [op['operation_uuid']]);
      if (queue.isEmpty) return;
      await tx.delete('account_queue', where: 'operation_uuid=?', whereArgs: [op['operation_uuid']]);
      final more = await tx.query('account_queue', where: 'local_id=?', whereArgs: [op['local_id']], limit: 1);
      final values = <String, Object?>{'server_id': task['id'], 'server_version': task['version'], 'remote_json': jsonEncode(task)};
      if (more.isEmpty) values.addAll({'title': task['title'], 'status': task['status'], 'active': task['active'] == true ? 1 : 0});
      await tx.update('account_tasks', values, where: 'local_id=?', whereArgs: [op['local_id']]);
    });
  }

  Future<void> block(Map<String, Object?> op, String message) => db.transaction((tx) async {
    await tx.update('account_queue', {'blocked': 1, 'error': message},
        where: 'operation_uuid=?', whereArgs: [op['operation_uuid']]);
  });

  /// Commit the complete scan at once. Never overwrite pending local changes.
  Future<void> merge(List<Map<String, dynamic>> snapshot) => db.transaction((tx) async {
    final seen = <int>{};
    for (final task in snapshot) {
      final id = task['id'] as int;
      seen.add(id);
      final existing = await tx.query('account_tasks', where: 'server_id=? OR local_id=?', whereArgs: [id, task['uuid']]);
      final values = <String, Object?>{'remote_json': jsonEncode(task)};
      if (existing.isEmpty) {
        values.addAll({'local_id': task['uuid'], 'server_id': id, 'server_version': task['version'],
          'title': task['title'], 'status': task['status'], 'active': task['active'] == true ? 1 : 0});
        await tx.insert('account_tasks', values);
      } else {
        final localId = existing.single['local_id'];
        final pending = await tx.query('account_queue', where: 'local_id=?', whereArgs: [localId], limit: 1);
        if (pending.isEmpty) values.addAll({'server_version': task['version'], 'title': task['title'],
          'status': task['status'], 'active': task['active'] == true ? 1 : 0});
        await tx.update('account_tasks', values, where: 'local_id=?', whereArgs: [localId]);
      }
    }
    // Missing hard-deleted records become hidden only when they have no local changes.
    for (final row in await tx.query('account_tasks', where: 'server_id IS NOT NULL')) {
      if (seen.contains(row['server_id'])) continue;
      final pending = await tx.query('account_queue', where: 'local_id=?', whereArgs: [row['local_id']], limit: 1);
      if (pending.isEmpty) await tx.update('account_tasks', {'active': 0}, where: 'local_id=?', whereArgs: [row['local_id']]);
    }
  });

  Future<void> discardMissing(String localId) => db.transaction((tx) async {
    await tx.delete('account_queue', where: 'local_id=?', whereArgs: [localId]);
    await tx.update('account_tasks', {'active': 0}, where: 'local_id=?', whereArgs: [localId]);
  });

  /// Explicit user choice: discard THIS task's queued edits, take the fresh server record.
  Future<void> acceptServer(String localId, Map<String, dynamic> task) => db.transaction((tx) async {
    final row = (await tx.query('account_tasks', where: 'local_id=?', whereArgs: [localId])).single;
    if (row['server_id'] != task['id']) throw StateError('Другая задача');
    await tx.delete('account_queue', where: 'local_id=?', whereArgs: [localId]);
    await tx.update('account_tasks', {'server_version': task['version'], 'title': task['title'],
      'status': task['status'], 'active': task['active'] == true ? 1 : 0, 'remote_json': jsonEncode(task)},
      where: 'local_id=?', whereArgs: [localId]);
  });
}

import 'dart:convert';
import 'dart:math';
import 'checklists.dart';
import 'task_labels.dart';
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
    final db = await factory.openDatabase(path, options: OpenDatabaseOptions(version: 5, onCreate: (db, version) async {
      await db.execute('CREATE TABLE account_tasks ('
          'local_id TEXT PRIMARY KEY, server_id INTEGER UNIQUE, server_version INTEGER, '
          'title TEXT NOT NULL, status TEXT NOT NULL, active INTEGER NOT NULL DEFAULT 1, remote_json TEXT)');
      await db.execute('CREATE TABLE account_queue ('
          'sequence INTEGER PRIMARY KEY AUTOINCREMENT, operation_uuid TEXT UNIQUE NOT NULL, '
          'local_id TEXT NOT NULL, kind TEXT NOT NULL, title TEXT, status TEXT, '
          'body TEXT, blocked INTEGER NOT NULL DEFAULT 0, error TEXT)');
      await db.execute('CREATE INDEX queue_task ON account_queue(local_id, sequence)');
      await _addDetails(db);
      await _addChecklist(db);
      await _addComments(db);
      await _addLabels(db);
    }, onUpgrade: (db, old, version) async {
      if (old < 2) await _addDetails(db);
      if (old < 3) await _addChecklist(db);
      if (old < 4) await _addComments(db);
      if (old < 5) await _addLabels(db);
    }));
    return AccountStore(db);
  }

  static Map<String, Object?> _details(Map<String, dynamic> task) => {
    'description': task['description'], 'due_date': task['due_date'],
    'priority': task['priority'] ?? 'normal', 'project_id': task['project_id'],
    'checklist_json': jsonEncode(Checklists.fromRemote(task['checklist'] ?? [])),
    'labels_json': jsonEncode(TaskLabels.fromRemote(task['labels'] ?? [])),
  };

  static Future<void> _addDetails(DatabaseExecutor db) async {
    await db.execute('ALTER TABLE account_tasks ADD COLUMN description TEXT');
    await db.execute('ALTER TABLE account_tasks ADD COLUMN due_date TEXT');
    await db.execute("ALTER TABLE account_tasks ADD COLUMN priority TEXT NOT NULL DEFAULT 'normal'");
    await db.execute('ALTER TABLE account_tasks ADD COLUMN project_id INTEGER');
    await db.execute('ALTER TABLE account_queue ADD COLUMN fields TEXT');
    await db.execute('CREATE TABLE account_projects (id INTEGER PRIMARY KEY, name TEXT NOT NULL)');
    for (final row in await db.query('account_tasks', where: 'remote_json IS NOT NULL')) {
      final remote = Map<String, dynamic>.from(jsonDecode(row['remote_json'] as String) as Map);
      await db.update('account_tasks', _details(remote)..remove('checklist_json')..remove('labels_json'), where: 'local_id=?', whereArgs: [row['local_id']]);
    }
  }

  static Future<void> _addChecklist(DatabaseExecutor db) async {
    await db.execute("ALTER TABLE account_tasks ADD COLUMN checklist_json TEXT NOT NULL DEFAULT '[]'");
    for (final row in await db.query('account_tasks', where: 'remote_json IS NOT NULL')) {
      final remote = Map<String, dynamic>.from(jsonDecode(row['remote_json'] as String) as Map);
      await db.update('account_tasks', {'checklist_json': jsonEncode(Checklists.fromRemote(remote['checklist'] ?? []))},
          where: 'local_id=?', whereArgs: [row['local_id']]);
    }
  }

  static Future<void> _addComments(DatabaseExecutor db) async {
    await db.execute('CREATE TABLE account_comments ('
        'local_id TEXT PRIMARY KEY, server_id INTEGER UNIQUE, task_local_id TEXT NOT NULL, '
        'body TEXT NOT NULL, author TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, '
        'state TEXT NOT NULL, request_json TEXT, error TEXT)');
    await db.execute('CREATE INDEX comments_task ON account_comments(task_local_id, state)');
  }

  static Future<void> _addLabels(DatabaseExecutor db) async {
    await db.execute("ALTER TABLE account_tasks ADD COLUMN labels_json TEXT NOT NULL DEFAULT '[]'");
    await db.execute('CREATE TABLE account_labels ('
      'local_id TEXT PRIMARY KEY, server_id INTEGER UNIQUE, name TEXT UNIQUE NOT NULL, color TEXT NOT NULL, '
      'state TEXT NOT NULL, request_json TEXT, error TEXT)');
    for (final row in await db.query('account_tasks', where: 'remote_json IS NOT NULL')) {
      final remote = Map<String, dynamic>.from(jsonDecode(row['remote_json'] as String) as Map);
      final labels = remote['labels'] as List? ?? [];
      await db.update('account_tasks', {'labels_json': jsonEncode(TaskLabels.fromRemote(labels))},
        where: 'local_id=?', whereArgs: [row['local_id']]);
      for (final label in labels) {
        await db.insert('account_labels', {'local_id': 'server-label-${label['id']}', 'server_id': label['id'],
          'name': label['name'], 'color': label['color'], 'state': 'sent'}, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    }
  }

  Future<List<Map<String, Object?>>> labels() => db.query('account_labels', orderBy: 'name, local_id');
  Future<String> addLabel(String name, String color) async {
    final text = name.trim();
    if (text.isEmpty || text.length > 40 || !TaskLabels.colors.containsKey(color)) throw ArgumentError('Название метки: 1–40 символов, выбери цвет');
    return db.transaction((tx) async {
      final existing = await tx.query('account_labels', where: 'name=?', whereArgs: [text]);
      if (existing.isNotEmpty) return existing.single['local_id'] as String;
      final key = operationUuid();
      await tx.insert('account_labels', {'local_id': key, 'name': text, 'color': color, 'state': 'pending'});
      return key;
    });
  }

  Future<Map<String, Object?>?> prepareLabel() => db.transaction((tx) async {
    final rows = await tx.query('account_labels', where: "state='pending'", orderBy: 'local_id', limit: 1);
    if (rows.isEmpty) return null;
    final row = rows.single;
    if (row['request_json'] != null) return row;
    final body = jsonEncode({'operation_uuid': row['local_id'], 'kind': 'label', 'label_name': row['name'], 'label_color': row['color']});
    await tx.update('account_labels', {'request_json': body}, where: 'local_id=?', whereArgs: [row['local_id']]);
    return {...row, 'request_json': body};
  });

  static Future<void> _resolveLabel(DatabaseExecutor tx, String oldKey, Map<String, dynamic> label) async {
    final key = 'server-label-${label['id']}';
    if (oldKey != key) {
    for (final row in await tx.query('account_tasks')) {
      final selected = TaskLabels.read(row['labels_json']);
      if (!selected.contains(oldKey)) continue;
      final updated = selected.map((value) => value == oldKey ? key : value).toSet().toList()..sort();
      await tx.update('account_tasks', {'labels_json': jsonEncode(updated)}, where: 'local_id=?', whereArgs: [row['local_id']]);
    }
    for (final op in await tx.query('account_queue', where: "kind='edit' AND fields IS NOT NULL")) {
      final fields = Map<String, dynamic>.from(jsonDecode(op['fields'] as String) as Map);
      if (fields['label_keys'] is! List || !(fields['label_keys'] as List).contains(oldKey)) continue;
      fields['label_keys'] = (fields['label_keys'] as List).map((v) => v == oldKey ? key : v).toSet().toList()..sort();
      // Only local references change. An already frozen HTTP body must never change.
      final values = <String, Object?>{'fields': jsonEncode(fields)};
      if (op['blocked'] == 1 && op['body'] == null && op['error'] == 'Метка ещё не отправлена. Проверь каталог меток.' &&
          (fields['label_keys'] as List).every((key) => RegExp(r'^server-label-[1-9][0-9]*$').hasMatch(key as String))) {
        values.addAll({'blocked': 0, 'error': null});
      }
      await tx.update('account_queue', values, where: 'sequence=?', whereArgs: [op['sequence']]);
    }
    }
    await tx.delete('account_labels', where: 'local_id=?', whereArgs: [oldKey]);
    await tx.insert('account_labels', {'local_id': key, 'server_id': label['id'], 'name': label['name'],
      'color': label['color'], 'state': 'sent'}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> acknowledgeLabel(Map<String, Object?> op, Map<String, dynamic> receipt) async {
    if (receipt['operation_uuid'] != op['local_id'] || receipt['label'] is! Map) throw StateError('Некорректное подтверждение метки');
    final label = Map<String, dynamic>.from(receipt['label'] as Map);
    if (label['id'] is! int || label['name'] != op['name']) throw StateError('Подтверждена другая метка');
    await db.transaction((tx) async { await _resolveLabel(tx, op['local_id'] as String, label); });
  }
  Future<void> blockLabel(String key) async {
    await db.update('account_labels', {'state': 'blocked', 'error': 'Метка не принята сервером. Повтори после проверки аккаунта.'}, where: 'local_id=?', whereArgs: [key]);
  }
  Future<void> retryLabel(String key) async {
    await db.update('account_labels', {'state': 'pending', 'error': null}, where: "local_id=? AND state='blocked'", whereArgs: [key]);
  }

  Future<Map<String, Object?>> task(String localId) async =>
      (await db.query('account_tasks', where: 'local_id=?', whereArgs: [localId])).single;

  Future<List<Map<String, Object?>>> comments(String localId) => db.query('account_comments',
      where: 'task_local_id=?', whereArgs: [localId], orderBy: 'server_id IS NULL, server_id, created_at, local_id');

  Future<void> addComment(String localId, String body, String author) async {
    final text = body.trim();
    if (text.isEmpty || text.length > 10000) throw ArgumentError('Комментарий: от 1 до 10000 символов');
    await db.transaction((tx) async {
      if ((await tx.query('account_tasks', where: 'local_id=?', whereArgs: [localId])).isEmpty) throw StateError('Нет задачи');
      final now = DateTime.now().toUtc().toIso8601String();
      await tx.insert('account_comments', {'local_id': operationUuid(), 'task_local_id': localId,
        'body': text, 'author': author, 'created_at': now, 'updated_at': now, 'state': 'pending'});
    });
  }

  Future<Map<String, Object?>?> prepareComment() => db.transaction((tx) async {
    final rows = await tx.rawQuery("SELECT c.*, t.server_id AS task_server_id FROM account_comments c "
        "JOIN account_tasks t ON t.local_id=c.task_local_id "
        "WHERE c.state='pending' AND t.server_id IS NOT NULL ORDER BY c.created_at,c.local_id LIMIT 1");
    if (rows.isEmpty) return null;
    final row = rows.single;
    if (row['request_json'] != null) return row;
    final body = jsonEncode({'operation_uuid': row['local_id'], 'kind': 'comment',
      'task_id': row['task_server_id'], 'comment_body': row['body']});
    await tx.update('account_comments', {'request_json': body}, where: 'local_id=?', whereArgs: [row['local_id']]);
    return {...row, 'request_json': body};
  });

  Future<void> acknowledgeComment(Map<String, Object?> op, Map<String, dynamic> receipt) async {
    if (receipt['operation_uuid'] != op['local_id'] || receipt['comment'] is! Map) throw StateError('Некорректное подтверждение комментария');
    final comment = Map<String, dynamic>.from(receipt['comment'] as Map);
    if (comment['uuid'] != op['local_id'] || comment['task_id'] != op['task_server_id']) throw StateError('Подтверждена другая задача');
    await db.transaction((tx) async {
      final rows = await tx.query('account_comments', where: 'local_id=?', whereArgs: [op['local_id']]);
      if (rows.isEmpty) return;
      await tx.update('account_comments', {'server_id': comment['id'], 'body': comment['body'],
        'author': comment['author'], 'created_at': comment['created_at'], 'updated_at': comment['updated_at'],
        'state': 'sent', 'error': null}, where: 'local_id=?', whereArgs: [op['local_id']]);
    });
  }

  Future<void> blockComment(String id, String error) async {
    await db.update('account_comments', {'state': 'blocked', 'error': error}, where: 'local_id=?', whereArgs: [id]);
  }
  Future<void> retryComment(String id) async {
    await db.update('account_comments', {'state': 'pending', 'error': null}, where: "local_id=? AND state='blocked'", whereArgs: [id]);
  }
  Future<void> discardComment(String id) async {
    await db.delete('account_comments', where: "local_id=? AND state='blocked'", whereArgs: [id]);
  }

  Future<void> mergeComments(String localId, List<Map<String, dynamic>> snapshot) => db.transaction((tx) async {
    final owner = (await tx.query('account_tasks', where: 'local_id=?', whereArgs: [localId])).single;
    if (snapshot.any((c) => c['task_id'] != owner['server_id'])) throw StateError('Комментарии другой задачи');
    await tx.delete('account_comments', where: "task_local_id=? AND state='sent'", whereArgs: [localId]);
    for (final comment in snapshot) {
      final key = comment['uuid'] as String? ?? 'server-comment-${comment['id']}';
      final existing = await tx.query('account_comments', where: 'task_local_id=? AND (local_id=? OR server_id=?)',
        whereArgs: [localId, key, comment['id']]);
      final values = <String, Object?>{'server_id': comment['id'], 'task_local_id': localId, 'body': comment['body'],
        'author': comment['author'], 'created_at': comment['created_at'], 'updated_at': comment['updated_at'], 'state': 'sent', 'error': null};
      if (existing.isEmpty) {
        await tx.insert('account_comments', {...values, 'local_id': key});
      } else {
        await tx.update('account_comments', values, where: 'local_id=?', whereArgs: [existing.single['local_id']]);
      }
    }
    if (owner['remote_json'] != null) {
      final remote = Map<String, dynamic>.from(jsonDecode(owner['remote_json'] as String) as Map);
      remote['comments_count'] = snapshot.length;
      await tx.update('account_tasks', {'remote_json': jsonEncode(remote)}, where: 'local_id=?', whereArgs: [localId]);
    }
  });

  Future<List<Map<String, Object?>>> projects() => db.query('account_projects', orderBy: 'name, id');

  Future<void> edit(String id, Map<String, Object?> fields) async {
    const allowed = {'title', 'description', 'due_date', 'priority', 'project_id', 'checklist', 'label_keys'};
    if (fields.keys.any((key) => !allowed.contains(key))) throw ArgumentError('Неизвестное поле');
    if (fields.containsKey('title') &&
        (fields['title'] is! String || (fields['title'] as String).trim().isEmpty || (fields['title'] as String).length > 240)) {
      throw ArgumentError('Название: от 1 до 240 символов');
    }
    if (fields['description'] != null &&
        (fields['description'] is! String || (fields['description'] as String).length > 20000)) {
      throw ArgumentError('Описание: не более 20000 символов');
    }
    if (fields.containsKey('priority') && !['normal', 'high'].contains(fields['priority'])) throw ArgumentError('Неизвестный приоритет');
    if (fields['project_id'] != null && (fields['project_id'] is! int || (fields['project_id'] as int) <= 0)) throw ArgumentError('Некорректный проект');
    if (fields['due_date'] != null) {
      final value = fields['due_date'];
      final date = value is String ? DateTime.tryParse(value) : null;
      if (date == null || date.year < 1 || date.year > 9999 || date.toIso8601String().substring(0, 10) != value) throw ArgumentError('Некорректная дата');
    }
    final labelKeys = fields.containsKey('label_keys') ? TaskLabels.keys(fields['label_keys']) : null;
    final checklist = fields.containsKey('checklist') ? Checklists.normalize(fields['checklist']) : null;
    await db.transaction((tx) async {
      final row = (await tx.query('account_tasks', where: 'local_id=?', whereArgs: [id])).single;
      final changed = <String, Object?>{};
      for (final field in fields.entries) {
        if (field.key == 'label_keys') {
          if (row['labels_json'] != jsonEncode(labelKeys)) changed['label_keys'] = labelKeys;
          continue;
        }
        if (field.key == 'checklist') {
          if (row['checklist_json'] != jsonEncode(checklist)) changed['checklist'] = checklist;
          continue;
        }
        final value = field.key == 'title' ? (field.value as String).trim() : field.value;
        if (row[field.key] != value) changed[field.key] = value;
      }
      if (changed.isEmpty) return;
      if (utf8.encode(jsonEncode(changed)).length > 120 * 1024) {
        throw ArgumentError('Правка слишком большая для API. Сократи текст или сохрани описание и чек-лист отдельно.');
      }
      final values = <String, Object?>{...changed};
      if (values.containsKey('label_keys')) values['labels_json'] = jsonEncode(values.remove('label_keys'));
      if (values.containsKey('checklist')) values['checklist_json'] = jsonEncode(values.remove('checklist'));
      await tx.update('account_tasks', values, where: 'local_id=?', whereArgs: [id]);
      await tx.insert('account_queue', {'operation_uuid': operationUuid(), 'local_id': id,
        'kind': 'edit', 'fields': jsonEncode(changed)});
    });
  }

  Future<List<Map<String, Object?>>> tasks() => db.rawQuery('''
    SELECT t.*, (SELECT COUNT(*) FROM account_queue q WHERE q.local_id=t.local_id) AS pending,
      (SELECT MAX(blocked) FROM account_queue q WHERE q.local_id=t.local_id) AS blocked,
      (SELECT error FROM account_queue q WHERE q.local_id=t.local_id AND blocked=1 LIMIT 1) AS error,
      (SELECT COUNT(*) FROM account_comments c WHERE c.task_local_id=t.local_id AND c.state!='sent') AS pending_comments
    FROM account_tasks t WHERE t.active=1 OR EXISTS
      (SELECT 1 FROM account_queue q WHERE q.local_id=t.local_id) OR EXISTS
      (SELECT 1 FROM account_comments c WHERE c.task_local_id=t.local_id AND c.state!='sent')
    ORDER BY t.server_id IS NULL DESC, t.server_id DESC
  ''');
  Future<int> pendingCount() async => (await db.rawQuery("SELECT (SELECT COUNT(*) FROM account_queue) + (SELECT COUNT(*) FROM account_comments WHERE state!='sent') + (SELECT COUNT(*) FROM account_labels WHERE state!='sent') AS n")).single['n'] as int;

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
      body.addAll({'task_id': task['server_id'], 'expected_version': task['server_version']});
      if (row['kind'] == 'edit') {
        final fields = Map<String, dynamic>.from(jsonDecode(row['fields'] as String) as Map);
        if (fields.containsKey('label_keys')) {
          try {
            fields['label_ids'] = TaskLabels.keys(fields.remove('label_keys')).map(TaskLabels.id).toList();
          } on ArgumentError {
            await tx.update('account_queue', {'blocked': 1, 'error': 'Метка ещё не отправлена. Проверь каталог меток.'}, where: 'sequence=?', whereArgs: [row['sequence']]);
            return {...row, 'blocked': 1};
          }
        }
        body['fields'] = fields;
      } else {
        body['status'] = row['status'];
      }
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
      if (more.isEmpty) values.addAll({..._details(task), 'title': task['title'], 'status': task['status'], 'active': task['active'] == true ? 1 : 0});
      await tx.update('account_tasks', values, where: 'local_id=?', whereArgs: [op['local_id']]);
    });
  }

  Future<void> block(Map<String, Object?> op, String message) => db.transaction((tx) async {
    await tx.update('account_queue', {'blocked': 1, 'error': message},
        where: 'operation_uuid=?', whereArgs: [op['operation_uuid']]);
  });

  /// Commit the complete scan at once. Never overwrite pending local changes.
  Future<void> merge(List<Map<String, dynamic>> snapshot, {List<Map<String, dynamic>>? projects, List<Map<String, dynamic>>? labels}) => db.transaction((tx) async {
    if (labels != null) {
      await tx.delete('account_labels', where: "state='sent'");
      for (final label in labels) {
        final pending = await tx.query('account_labels', where: 'name=?', whereArgs: [label['name']]);
        await _resolveLabel(tx, pending.isEmpty ? 'server-label-${label['id']}' : pending.single['local_id'] as String, label);
      }
    }
    if (projects != null) {
      await tx.delete('account_projects');
      for (final project in projects) {
        await tx.insert('account_projects', {'id': project['id'], 'name': project['name']});
      }
    }
    final seen = <int>{};
    for (final task in snapshot) {
      final id = task['id'] as int;
      seen.add(id);
      final existing = await tx.query('account_tasks', where: 'server_id=? OR local_id=?', whereArgs: [id, task['uuid']]);
      final values = <String, Object?>{'remote_json': jsonEncode(task)};
      if (existing.isEmpty) {
        values.addAll({..._details(task), 'local_id': task['uuid'], 'server_id': id, 'server_version': task['version'],
          'title': task['title'], 'status': task['status'], 'active': task['active'] == true ? 1 : 0});
        await tx.insert('account_tasks', values);
      } else {
        final localId = existing.single['local_id'];
        final pending = await tx.query('account_queue', where: 'local_id=?', whereArgs: [localId], limit: 1);
        if (pending.isEmpty) values.addAll({..._details(task), 'server_version': task['version'], 'title': task['title'],
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
    await tx.delete('account_comments', where: "task_local_id=? AND state!='sent'", whereArgs: [localId]);
    await tx.delete('account_queue', where: 'local_id=?', whereArgs: [localId]);
    await tx.update('account_tasks', {'active': 0}, where: 'local_id=?', whereArgs: [localId]);
  });

  /// Explicit user choice: discard THIS task's queued edits, take the fresh server record.
  Future<void> acceptServer(String localId, Map<String, dynamic> task) => db.transaction((tx) async {
    final row = (await tx.query('account_tasks', where: 'local_id=?', whereArgs: [localId])).single;
    if (row['server_id'] != task['id']) throw StateError('Другая задача');
    await tx.delete('account_queue', where: 'local_id=?', whereArgs: [localId]);
    await tx.update('account_tasks', {..._details(task), 'server_version': task['version'], 'title': task['title'],
      'status': task['status'], 'active': task['active'] == true ? 1 : 0, 'remote_json': jsonEncode(task)},
      where: 'local_id=?', whereArgs: [localId]);
  });
}

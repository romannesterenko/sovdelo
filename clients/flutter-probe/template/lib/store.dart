import 'package:sqflite_common/sqlite_api.dart';

class TaskStore {
  final Database db;
  TaskStore(this.db);

  static Future<TaskStore> open(DatabaseFactory factory, String path) async {
    final db = await factory.openDatabase(path,
        options: OpenDatabaseOptions(version: 1, onCreate: (db, version) async {
      await db.execute('CREATE TABLE tasks (id INTEGER PRIMARY KEY AUTOINCREMENT, '
          'title TEXT NOT NULL, done INTEGER NOT NULL DEFAULT 0)');
    }));
    return TaskStore(db);
  }

  Future<List<Map<String, Object?>>> list() => db.query('tasks', orderBy: 'id DESC');
  Future<void> add(String title) async {
    if (title.trim().isEmpty) return;
    await db.insert('tasks', {'title': title.trim(), 'done': 0});
  }

  Future<void> toggle(int id, bool done) async {
    await db.update('tasks', {'done': done ? 1 : 0}, where: 'id = ?', whereArgs: [id]);
  }
}

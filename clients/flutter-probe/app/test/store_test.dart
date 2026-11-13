import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sovdelo_probe/store.dart';

void main() {
  test('SQLite сохраняет задачи и статусы после повторного открытия', () async {
    sqfliteFfiInit();
    final dir = await Directory.systemTemp.createTemp('sovdelo-probe-');
    final path = '${dir.path}/tasks.db';
    try {
      final first = await TaskStore.open(databaseFactoryFfi, path);
      await first.add('  Проверить офлайн  ');
      await first.add('   ');
      final tasks = await first.list();
      expect(tasks.length, 1);
      await first.toggle(tasks.single['id'] as int, true);
      await first.db.close();
      final second = await TaskStore.open(databaseFactoryFfi, path);
      final restored = await second.list();
      expect(restored.single['title'], 'Проверить офлайн');
      expect(restored.single['done'], 1);
      await second.db.close();
    } finally {
      await dir.delete(recursive: true);
    }
  });
}

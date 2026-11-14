import 'dart:convert';
import 'account_store.dart';
import 'workspace_api.dart';

class AccountSync {
  final WorkspaceApi api;
  final AccountStore store;
  AccountSync(this.api, this.store);
  Future<void> pull(String token) async {
    final tasks = <Map<String, dynamic>>[];
    int after = 0;
    int? through;
    while (true) {
      final response = await api.scan(token, after, through);
      final meta = response['meta'] as Map;
      through ??= meta['through_id'] as int;
      final rows = (response['data'] as List).map((t) => Map<String, dynamic>.from(t as Map)).toList();
      tasks.addAll(rows);
      if (meta['has_more'] != true) break;
      final next = meta['after_id'] as int;
      if (next <= after) throw StateError('Сервер повторяет страницу');
      after = next;
    }
    final projects = <Map<String, dynamic>>[];
    var page = 1;
    while (true) {
      final result = await api.page(token, 'projects', page);
      projects.addAll((result['data'] as List).map((p) => Map<String, dynamic>.from(p as Map)));
      if (page >= (result['meta'] as Map)['last_page']) break;
      page++;
    }
    await store.merge(tasks, projects: projects);
  }

  Future<int> synchronize(String token, {required bool write}) async {
    // Also checks that this server version supports sync before sending anything.
    await pull(token);
    var sent = 0;
    if (write) {
      while (true) {
        final op = await store.prepare();
        if (op == null) break;
        try {
          final receipt = await api.operation(token, Map<String, dynamic>.from(jsonDecode(op['body'] as String) as Map));
          await store.acknowledge(op, receipt);
          sent++;
        } on ApiFailure catch (error) {
          if ([404, 409, 422].contains(error.status)) {
            await store.block(op, error.status == 409
                ? 'Задача изменилась на сайте. Нужно выбрать версию.'
                : 'Правка недоступна: проверь задачу, проект и данные на сайте.');
            continue;
          }
          rethrow; // Offline/401/403/429/5xx preserve the exact operation for retry.
        }
      }
      await pull(token);
    }
    return sent;
  }
}

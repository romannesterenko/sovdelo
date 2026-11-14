import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as native;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;
import 'workspace_api.dart';
import 'account_store.dart';
import 'account_sync.dart';

class SecureTokenVault implements TokenVault {
  final storage = const FlutterSecureStorage();
  static const key = 'sovdelo.production.read-session.v1';
  Future<Map<String, dynamic>?> record() async {
    final value = await storage.read(key: key);
    if (value == null) return null;
    if (!value.startsWith('{')) return {'token': value}; // Patch 21 sessions.
    return Map<String, dynamic>.from(jsonDecode(value) as Map);
  }
  @override
  Future<String?> read() async => (await record())?['token'] as String?;
  @override
  Future<void> write(String token) => storage.write(key: key, value: token);
  Future<void> remember(String token, Map<String, dynamic> profile) => storage.write(
      key: key, value: jsonEncode({'token': token, 'profile': profile}));
  Future<Map<String, dynamic>?> profile(String token) async {
    final saved = await record();
    if (saved?['token'] != token || saved?['profile'] is! Map) return null;
    return Map<String, dynamic>.from(saved!['profile'] as Map);
  }
  @override
  Future<void> delete() => storage.delete(key: key);
}

class ServerPage extends StatefulWidget {
  const ServerPage({super.key});
  @override
  State<ServerPage> createState() => _ServerPageState();
}

class _ServerPageState extends State<ServerPage> {
  final email = TextEditingController(), password = TextEditingController(), title = TextEditingController();
  final api = WorkspaceApi();
  final vault = SecureTokenVault();
  late final session = AccountSession(api, vault);
  String? token;
  Map<String, dynamic>? profile;
  AccountStore? store;
  List<Map<String, Object?>> items = [];
  String message = 'Открываем аккаунт…';
  bool busy = true;
  int pending = 0;
  bool get canWrite => profile?['access'] == 'write';

  @override
  void initState() { super.initState(); restore(); }

  Future<void> openStore() async {
    if (store != null) return;
    final id = profile!['id'] as int;
    if (id <= 0) throw StateError('Некорректный аккаунт');
    final directory = await getApplicationSupportDirectory();
    if (Platform.isLinux || Platform.isWindows) ffi.sqfliteFfiInit();
    store = await AccountStore.open(Platform.isAndroid ? native.databaseFactory : ffi.databaseFactoryFfi,
        p.join(directory.path, 'production-account-$id-v1.sqlite3'));
    await reload();
  }

  Future<void> reload() async {
    if (store == null) return;
    items = await store!.tasks();
    pending = await store!.pendingCount();
  }

  Future<void> restore() async {
    try {
      token = await vault.read();
      if (token == null) { message = 'Войди в аккаунт сайта совдело.рф.'; return; }
      profile = await vault.profile(token!);
      if (profile != null) await openStore();
      await synchronize();
    } catch (e) { await handleError(e); }
    finally {
      if (mounted) { setState(() => busy = false); }
      else { await store?.db.close(); }
    }
  }

  Future<void> handleError(Object error) async {
    if (error is ApiFailure && error.status == 401) {
      await store?.db.close(); store = null;
      token = null; profile = null; items = []; pending = 0;
      try { await vault.delete(); } catch (_) { /* Revoked token cannot authorize requests. */ }
    }
    message = error is ApiFailure ? error.message
        : 'Не удалось выполнить действие. Проверь хранилище и повтори. Очередь не очищена.';
    await reload();
  }

  Future<void> perform(Future<void> Function() operation) async {
    setState(() => busy = true);
    try { await operation(); }
    catch (e) { await handleError(e); }
    finally {
      if (mounted) { setState(() => busy = false); }
      else { await store?.db.close(); }
    }
  }

  Future<void> synchronize() async {
    final me = await api.me(token!);
    if (profile != null && profile!['id'] != me['id']) throw StateError('Аккаунт изменился');
    profile = me;
    await vault.remember(token!, me);
    await openStore();
    final count = await AccountSync(api, store!).synchronize(token!, write: canWrite);
    await reload();
    message = pending == 0 ? 'Синхронизировано. Отправлено операций: $count.'
        : 'Осталось операций: $pending. Проверь карточки с конфликтами.';
  }

  Future<void> signIn() async {
    if (email.text.trim().isEmpty || password.text.isEmpty) {
      setState(() => message = 'Введи email и пароль.'); return;
    }
    final entered = password.text; password.clear();
    await perform(() async {
      token = await session.login(email.text, entered);
      await synchronize();
    });
  }

  Future<void> signOut() => perform(() async {
    final revoked = await session.logout(token!);
    await store?.db.close(); store = null;
    token = null; profile = null; items = []; pending = 0;
    message = revoked ? 'Выход выполнен. Очередь сохранена для этого аккаунта.'
        : 'Выход выполнен локально. Отзови устройство в профиле сайта. Очередь сохранена.';
  });

  Future<void> editStatus(Map<String, Object?> task, String status) => perform(() async {
    await store!.setStatus(task['local_id'] as String, status);
    await reload();
    message = 'Статус сохранён на устройстве.';
    await synchronize();
  });

  Future<void> resolve(Map<String, Object?> local) => perform(() async {
    if (local['server_id'] == null) {
      message = 'Не удалось создать задачу. Локальная запись сохранена; проверь доступность сайта.';
      return;
    }
    Map<String, dynamic> remote;
    try {
      remote = await api.task(token!, local['server_id'] as int);
    } on ApiFailure catch (error) {
      if (error.status != 404) rethrow;
      if (!mounted) return;
      final discard = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
        title: const Text('Задача больше недоступна'),
        content: const Text('Удалить ожидающие локальные изменения этой задачи? Остальные задачи останутся.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Сохранить изменения')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить локальные изменения')),
        ],
      ));
      if (discard == true) { await store!.discardMissing(local['local_id'] as String); await reload(); }
      return;
    }
    if (!mounted) return;
    final accept = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Конфликт изменений'),
      content: Text('На устройстве: ${local['status']}\nНа сайте: ${remote['status']}\n\n'
          'Принять версию сайта и удалить ожидающие изменения этой задачи?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Оставить конфликт')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Принять сайт')),
      ],
    ));
    if (accept == true) {
      await store!.acceptServer(local['local_id'] as String, remote);
      await reload(); message = 'Принята версия сайта.';
    }
  });
  Future<void> showProjects() => perform(() async {
    final rows = <Map<String, dynamic>>[];
    var number = 1;
    while (true) {
      final result = await api.page(token!, 'projects', number);
      rows.addAll((result['data'] as List).map((r) => Map<String, dynamic>.from(r as Map)));
      if (number >= (result['meta'] as Map)['last_page']) break;
      number++;
    }
    if (!mounted) return;
    await showDialog<void>(context: context, builder: (context) => AlertDialog(
      title: const Text('Активные проекты'),
      content: SizedBox(width: 560, child: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows.isEmpty ? [const Text('Проектов пока нет.')] : [for (final row in rows) ListTile(title: Text(row['name'] as String))],
      ))),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Закрыть'))],
    ));
  });

  void showDetails(Map<String, dynamic> task) {
    final status = {'todo': 'К выполнению', 'doing': 'В работе', 'done': 'Готово'}[task['status']] ?? task['status'];
    showDialog<void>(context: context, builder: (context) => AlertDialog(
      title: Text(task['title'] as String),
      content: SizedBox(width: 560, child: SingleChildScrollView(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Статус: $status · версия ${task['version']}'),
          if (task['due_date'] != null) Text('Срок: ${task['due_date']}'),
          const SizedBox(height: 16),
          SelectableText((task['description'] as String?)?.isNotEmpty == true
              ? task['description'] as String : 'Без описания'),
          const SizedBox(height: 16),
          for (final row in (task['checklist'] as List? ?? []))
            Text('${row['done'] == true ? '✓' : '○'} ${row['text']}'),
          const SizedBox(height: 16),
          Text('Комментарии: ${task['comments_count']} · файлы: ${task['attachments_count']}'),
          const Text('Описание и чек-лист пока доступны только для просмотра.'),
        ],
      ))),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Закрыть'))],
    ));
  }

  @override
  void dispose() {
    email.dispose(); password.dispose(); title.dispose();
    if (!busy) store?.db.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
    appBar: AppBar(title: const Text('Мои задачи · аккаунт')),
    body: SingleChildScrollView(padding: const EdgeInsets.all(24), child: Center(
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900), child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (busy) const LinearProgressIndicator(),
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(message))),
          if (token == null) ...[
            TextField(controller: email, enabled: !busy, keyboardType: TextInputType.emailAddress,
              autocorrect: false, decoration: const InputDecoration(labelText: 'Email')),
            TextField(controller: password, enabled: !busy, obscureText: true, autocorrect: false,
              enableSuggestions: false, decoration: const InputDecoration(labelText: 'Пароль')),
            FilledButton(onPressed: busy ? null : signIn, child: const Text('Войти')),
          ] else ...[
            if (profile != null) Text('${profile!['name']} · ${profile!['email']}'),
            Text('Ожидает отправки: $pending'),
            Wrap(spacing: 12, children: [
              OutlinedButton(onPressed: busy ? null : () => perform(synchronize), child: const Text('Синхронизировать')),
              TextButton(onPressed: busy ? null : showProjects, child: const Text('Проекты')) ,
              TextButton(onPressed: busy ? null : signOut, child: const Text('Выйти')),
            ]),
            if (profile != null && !canWrite)
              const Text('Текущий токен только на чтение. Выйди и войди снова, чтобы включить изменения.'),
            if (store != null && canWrite) ...[
              const SizedBox(height: 16),
              TextField(controller: title, enabled: !busy, maxLength: 240,
                decoration: const InputDecoration(labelText: 'Новая задача в аккаунте')),
              FilledButton.icon(onPressed: busy ? null : () => perform(() async {
                await store!.add(title.text); title.clear(); await reload();
                message = 'Задача сохранена на устройстве.';
                await synchronize();
              }), icon: const Icon(Icons.add), label: const Text('Добавить')),
            ],
            const SizedBox(height: 16),
            if (items.isEmpty && !busy) const Text('Нет активных задач в локальной копии аккаунта.'),
            for (final task in items) Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(task['title'] as String, style: Theme.of(context).textTheme.titleMedium),
                Text(task['blocked'] == 1 ? 'Конфликт: ${task['error']}'
                    : (task['pending'] as int) > 0 ? 'Сохранено на устройстве · ожидает отправки' : 'Сохранено на сайте'),
                Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  DropdownButton<String>(value: task['status'] as String,
                    items: const [
                      DropdownMenuItem(value: 'todo', child: Text('К выполнению')),
                      DropdownMenuItem(value: 'doing', child: Text('В работе')),
                      DropdownMenuItem(value: 'done', child: Text('Готово')),
                    ], onChanged: busy || !canWrite || task['blocked'] == 1 ? null
                        : (status) { if (status != null) editStatus(task, status); }),
                  if (task['remote_json'] != null) TextButton(
                    onPressed: () => showDetails(Map<String, dynamic>.from(jsonDecode(task['remote_json'] as String) as Map)),
                    child: const Text('Детали с сайта')),
                  if (task['blocked'] == 1) TextButton(onPressed: busy ? null : () => resolve(task),
                    child: const Text('Разобрать конфликт')),
                ]),
              ],
            ))),
          ],
          const SizedBox(height: 24),
          const Text('Тестовые задачи на предыдущем экране остаются отдельно. Новые задачи здесь создаются без проекта. '
              'Отправка выполняется при изменении и по кнопке, пока экран открыт; фоновой синхронизации пока нет.'),
        ],
      )),
    )),
  ));
}

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'workspace_api.dart';

class SecureTokenVault implements TokenVault {
  final storage = const FlutterSecureStorage();
  static const key = 'sovdelo.production.read-session.v1';
  @override
  Future<String?> read() => storage.read(key: key);
  @override
  Future<void> write(String token) => storage.write(key: key, value: token);
  @override
  Future<void> delete() => storage.delete(key: key);
}

class ServerPage extends StatefulWidget {
  const ServerPage({super.key});
  @override
  State<ServerPage> createState() => _ServerPageState();
}

class _ServerPageState extends State<ServerPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  final api = WorkspaceApi();
  final vault = SecureTokenVault();
  late final session = AccountSession(api, vault);
  String? token;
  Map<String, dynamic>? profile;
  List<Map<String, dynamic>> items = [];
  String resource = 'tasks';
  String message = 'Открываем защищённое хранилище…';
  bool busy = true;
  int page = 1, lastPage = 1, total = 0;

  @override
  void initState() {
    super.initState();
    restore();
  }

  String readable(Object error) => error is ApiFailure
      ? error.message : 'Не удалось выполнить действие. Проверь доступ к системному хранилищу и повтори.';

  Future<void> restore() async {
    try {
      token = await vault.read();
      if (token != null) {
        profile = await api.me(token!);
        await load(1);
      } else {
        message = 'Войди в аккаунт с сайта совдело.рф.';
      }
    } catch (e) {
      await handleError(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> handleError(Object error) async {
    if (error is ApiFailure && error.status == 401) {
      token = null;
      profile = null;
      items = [];
      try { await vault.delete(); } catch (_) { /* Stale token remains unusable. */ }
    }
    message = readable(error);
  }

  Future<void> perform(Future<void> Function() operation) async {
    setState(() => busy = true);
    try {
      await operation();
    } catch (e) {
      await handleError(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> load(int number) async {
    final current = token;
    if (current == null) return;
    final result = await api.page(current, resource, number);
    final loaded = (result['data'] as List)
        .map((row) => Map<String, dynamic>.from(row as Map)).toList();
    final meta = result['meta'] as Map;
    items = loaded;
    page = number;
    lastPage = meta['last_page'] as int;
    total = meta['total'] as int;
    message = 'Загружено с сайта. Только просмотр · всего $total.';
  }

  Future<void> signIn() async {
    if (email.text.trim().isEmpty || password.text.isEmpty) {
      setState(() => message = 'Введи email и пароль.');
      return;
    }
    final enteredPassword = password.text;
    password.clear();
    await perform(() async {
      token = await session.login(email.text, enteredPassword);
      profile = await api.me(token!);
      await load(1);
    });
  }

  Future<void> signOut() => perform(() async {
    final revoked = await session.logout(token!);
    token = null;
    profile = null;
    items = [];
    page = lastPage = 1;
    total = 0;
    password.clear();
    message = revoked ? 'Выход выполнен, токен устройства отозван.'
        : 'На устройстве выполнен выход. Отзыв на сервере не подтверждён: отзови устройство в профиле сайта.';
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
          const Text('Редактирование подключим следующим этапом.'),
        ],
      ))),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Закрыть'))],
    ));
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Аккаунт СовДела')),
    body: SingleChildScrollView(padding: const EdgeInsets.all(24), child: Center(
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900), child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('совдело.рф · подключение к сайту'),
          const SizedBox(height: 12),
          if (busy) const LinearProgressIndicator(),
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(message))),
          if (token == null) ...[
            TextField(controller: email, enabled: !busy, keyboardType: TextInputType.emailAddress,
              autocorrect: false, decoration: const InputDecoration(labelText: 'Email')),
            const SizedBox(height: 12),
            TextField(controller: password, enabled: !busy, obscureText: true, autocorrect: false,
              enableSuggestions: false, decoration: const InputDecoration(labelText: 'Пароль'),
              onSubmitted: busy ? null : (_) => signIn()),
            const SizedBox(height: 16),
            FilledButton(onPressed: busy ? null : signIn, child: const Text('Войти')),
            const Text('Пароль не сохраняется. Токен устройства хранится в защищённом хранилище.'),
          ] else ...[
            if (profile != null) Text('${profile!['name']} · ${profile!['email']}'),
            Wrap(spacing: 8, children: [
              OutlinedButton(onPressed: busy ? null : () => perform(() async {
                profile = await api.me(token!);
                await load(1);
              }), child: const Text('Обновить')),
              TextButton(onPressed: busy ? null : signOut, child: const Text('Выйти')),
            ]),
            const SizedBox(height: 16),
            Wrap(spacing: 8, children: [
              ChoiceChip(label: const Text('Задачи'), selected: resource == 'tasks',
                onSelected: busy ? null : (_) => perform(() async {
                  resource = 'tasks'; items = []; await load(1);
                })),
              ChoiceChip(label: const Text('Проекты'), selected: resource == 'projects',
                onSelected: busy ? null : (_) => perform(() async {
                  resource = 'projects'; items = []; await load(1);
                })),
            ]),
            const SizedBox(height: 12),
            if (items.isEmpty && !busy) const Text('На этой странице пока пусто.'),
            for (final item in items) Card(child: ListTile(
              title: Text((resource == 'tasks' ? item['title'] : item['name']) as String),
              subtitle: resource == 'tasks' ? Text(
                '${{'todo': 'К выполнению', 'doing': 'В работе', 'done': 'Готово'}[item['status']] ?? item['status']} · версия ${item['version']}')
                : Text('Версия ${item['version']}'),
              trailing: resource == 'tasks' ? const Icon(Icons.chevron_right) : null,
              onTap: busy || resource != 'tasks' ? null : () => showDetails(item),
            )),
            Wrap(spacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
              TextButton(onPressed: busy || page <= 1 ? null : () => perform(() => load(page - 1)),
                child: const Text('Назад')),
              Text('Страница $page из $lastPage · всего $total'),
              TextButton(onPressed: busy || page >= lastPage ? null : () => perform(() => load(page + 1)),
                child: const Text('Далее')),
            ]),
          ],
          const SizedBox(height: 24),
          const Text('Локальные тестовые задачи остаются отдельно. Они не отправляются в аккаунт. Список с сайта пока доступен только онлайн.'),
        ],
      )),
    )),
  );
}

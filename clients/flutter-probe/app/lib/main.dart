import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as native;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;
import 'store.dart';
import 'server_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProbeApp());
}

class ProbeApp extends StatelessWidget {
  const ProbeApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'СовДело · проверка',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          colorSchemeSeed: const Color(0xff56c89b),
          scaffoldBackgroundColor: const Color(0xff111b18),
          useMaterial3: true,
        ),
        home: const ProbePage(),
      );
}

class ProbePage extends StatefulWidget {
  const ProbePage({super.key});
  @override
  State<ProbePage> createState() => _ProbePageState();
}

class _ProbePageState extends State<ProbePage> {
  TaskStore? store;
  List<Map<String, Object?>> tasks = [];
  final title = TextEditingController();
  final vault = const FlutterSecureStorage();
  final notifications = FlutterLocalNotificationsPlugin();
  String message = 'Открываем локальную базу…';
  int pendingCount = 0;
  bool busy = true;
  bool readyNotifications = false;
  static const vaultKey = 'sovdelo.probe.marker';

  @override
  void initState() {
    super.initState();
    initialize();
  }

  Future<void> initialize() async {
    try {
      final directory = await getApplicationSupportDirectory();
      if (Platform.isLinux || Platform.isWindows) ffi.sqfliteFfiInit();
      store = await TaskStore.open(
        Platform.isAndroid ? native.databaseFactory : ffi.databaseFactoryFfi,
        p.join(directory.path, 'probe.sqlite3'),
      );
      tasks = await store!.list();
      pendingCount = await store!.pendingCount();
      message = 'Локальная база готова. Изменения сохраняются вместе с очередью.';
    } catch (e) {
      message = 'Не удалось открыть базу: $e';
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> action(Future<String> Function() operation) async {
    setState(() => busy = true);
    try {
      final result = await operation();
      if (store != null) pendingCount = await store!.pendingCount();
      if (mounted) setState(() => message = result);
    } catch (e) {
      if (mounted) setState(() => message = 'Проверка не прошла: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<String> testNotification() async {
    if (!readyNotifications) {
      await notifications.initialize(const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        linux: LinuxInitializationSettings(defaultActionName: 'Открыть'),
        windows: WindowsInitializationSettings(
          appName: 'СовДело · проверка',
          appUserModelId: 'ru.sovdelo.probe',
          guid: '5534bff1-3e0e-4844-a61d-0497abb032e4',
        ),
      ));
      readyNotifications = true;
    }
    if (Platform.isAndroid) {
      final allowed = await notifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      if (allowed == false) return 'Разрешение на уведомления не выдано.';
    }
    await notifications.show(17, 'СовДело', 'Локальные уведомления работают.',
        const NotificationDetails(
          android: AndroidNotificationDetails('probe', 'Проверка СовДело',
              importance: Importance.high, priority: Priority.high),
          linux: LinuxNotificationDetails(),
          windows: WindowsNotificationDetails(),
        ));
    return 'Запрос отправлен. Подтверди, что уведомление видно в системе.';
  }

  @override
  void dispose() {
    title.dispose();
    store?.db.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final checks = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Проверка устройства', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      const Text('Тестовое хранилище использует отдельную метку. Пароль и API-токен здесь не нужны.'),
      const SizedBox(height: 16),
      OutlinedButton.icon(
        icon: const Icon(Icons.lock_outline),
        label: const Text('Записать защищённую метку'),
        onPressed: busy ? null : () => action(() async {
          await vault.write(key: vaultKey, value: 'sovdelo-probe-v1');
          if (await vault.read(key: vaultKey) != 'sovdelo-probe-v1') {
            throw StateError('Запись не прочиталась');
          }
          return 'Метка записана. Перезапусти приложение и нажми «Прочитать».';
        }),
      ),
      OutlinedButton(
        onPressed: busy ? null : () => action(() async {
          final value = await vault.read(key: vaultKey);
          return value == 'sovdelo-probe-v1'
              ? 'Защищённая метка прочитана.' : 'Метка отсутствует. Сначала запиши её.';
        }),
        child: const Text('Прочитать защищённую метку'),
      ),
      OutlinedButton(
        onPressed: busy ? null : () => action(() async {
          await vault.delete(key: vaultKey);
          return 'Тестовая метка удалена.';
        }),
        child: const Text('Удалить метку'),
      ),
      OutlinedButton.icon(
        onPressed: busy ? null : () => action(testNotification),
        icon: const Icon(Icons.notifications_outlined),
        label: const Text('Показать уведомление'),
      ),
      const SizedBox(height: 16),
      Text('В очереди: $pendingCount локальных изменений. Они пока не отправляются на сайт.'),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ServerPage())),
        icon: const Icon(Icons.account_circle_outlined), label: const Text('Открыть аккаунт СовДела'),
      ),
    ]);
    final editor = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Мои задачи · офлайн', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 16),
      TextField(controller: title, maxLength: 240,
          decoration: const InputDecoration(labelText: 'Новая задача', border: OutlineInputBorder())),
      FilledButton.icon(
        onPressed: busy || store == null ? null : () => action(() async {
          await store!.add(title.text);
          title.clear();
          final loaded = await store!.list();
          if (mounted) setState(() => tasks = loaded);
          return 'Задача и операция очереди сохранены одной транзакцией.';
        }),
        icon: const Icon(Icons.add), label: const Text('Добавить задачу'),
      ),
      const SizedBox(height: 16),
      if (tasks.isEmpty) const Text('Пока пусто. Создай первую тестовую задачу.'),
      for (final task in tasks)
        Card(child: CheckboxListTile(
          value: task['done'] == 1,
          title: Text(task['title'] as String),
          subtitle: Text('Локальная версия ${task['local_revision']} · ожидает подключения синхронизации'),
          onChanged: busy ? null : (value) => action(() async {
            await store!.toggle(task['id'] as int, value ?? false);
            final loaded = await store!.list();
            if (mounted) setState(() => tasks = loaded);
            return 'Статус сохранён локально.';
          }),
        )),
    ]);
    return Scaffold(
      appBar: AppBar(title: const Text('СовДело'), actions: const [
        Padding(padding: EdgeInsets.all(16), child: Text('Локальные задачи')),
      ]),
      body: LayoutBuilder(builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(message))),
            if (busy) const LinearProgressIndicator(),
            const SizedBox(height: 24),
            if (constraints.maxWidth >= 800)
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(flex: 3, child: editor), const SizedBox(width: 32),
                Expanded(flex: 2, child: checks),
              ])
            else ...[editor, const SizedBox(height: 32), checks],
          ]),
        )),
      )),
    );
  }
}

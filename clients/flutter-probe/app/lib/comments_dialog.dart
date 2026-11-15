import 'package:flutter/material.dart';
import 'account_store.dart';
import 'comments_sync.dart';
import 'workspace_api.dart';

class CommentsDialog extends StatefulWidget {
  final AccountStore store;
  final WorkspaceApi api;
  final String token, localId, taskTitle, author;
  final bool canWrite;
  final Future<void> Function() synchronize;
  const CommentsDialog({super.key, required this.store, required this.api,
    required this.token, required this.localId, required this.taskTitle, required this.author,
    required this.canWrite, required this.synchronize});
  @override
  State<CommentsDialog> createState() => _CommentsDialogState();
}

class _CommentsDialogState extends State<CommentsDialog> {
  final body = TextEditingController();
  List<Map<String, Object?>> rows = [];
  bool busy = true;
  String message = 'Открываем сохранённую историю…';
  @override
  void initState() { super.initState(); initialize(); }

  Future<void> initialize() => run(() async {
    rows = await widget.store.comments(widget.localId);
    if (mounted) setState(() {});
    await refresh();
  });

  Future<void> refresh() async {
    final task = await widget.store.task(widget.localId);
    if (task['server_id'] == null) {
      message = 'Задача ещё не отправлена. Комментарии сохраняются на устройстве.';
      return;
    }
    await CommentsSync.refresh(widget.api, widget.store, widget.token, widget.localId);
    message = 'История обновлена с сайта.';
  }

  Future<void> run(Future<void> Function() operation) async {
    if (mounted) setState(() => busy = true);
    try { await operation(); }
    catch (error) {
      message = error is ApiFailure ? error.message
          : error is ArgumentError ? error.message.toString()
          : 'Не удалось выполнить действие. Сохранённые комментарии остаются на устройстве.';
    } finally {
      try { rows = await widget.store.comments(widget.localId); }
      catch (_) { message = 'Не удалось прочитать локальное хранилище.'; }
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> send() => run(() async {
    await widget.store.addComment(widget.localId, body.text, widget.author);
    body.clear();
    message = 'Комментарий сохранён на устройстве и ожидает отправки.';
    await widget.synchronize();
    await refresh();
  });

  Future<void> discard(Map<String, Object?> comment) => run(() async {
    final yes = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Убрать неотправленный комментарий?'),
      content: const Text('Текст будет удалён с этого устройства. Комментарии на сайте не удаляются.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Убрать'))],
    ));
    if (yes == true) await widget.store.discardComment(comment['local_id'] as String);
  });

  String date(Object? value) {
    final time = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (time == null) return '';
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(time.day)}.${two(time.month)}.${time.year} ${two(time.hour)}:${two(time.minute)}';
  }

  @override
  void dispose() { body.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => PopScope(canPop: !busy, child: AlertDialog(
    title: Text('Комментарии · ${widget.taskTitle}'),
    content: SizedBox(width: 680, child: SingleChildScrollView(child: Column(
      mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (busy) const LinearProgressIndicator(),
        Text(message),
        Align(alignment: Alignment.centerLeft, child: TextButton.icon(
          onPressed: busy ? null : () => run(() async { await widget.synchronize(); await refresh(); }),
          icon: const Icon(Icons.refresh), label: const Text('Обновить и отправить очередь'))),
        if (rows.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('В сохранённой истории пока нет комментариев.')),
        for (final row in rows) Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('${row['author']} · ${date(row['created_at'])}', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 8), SelectableText(row['body'] as String),
            const SizedBox(height: 8),
            Text(row['state'] == 'sent' ? 'На сайте'
                : row['state'] == 'blocked' ? 'Не отправлен: ${row['error']}' : 'Ожидает отправки'),
            if (row['state'] == 'blocked') Wrap(spacing: 8, children: [
              TextButton(onPressed: busy || !widget.canWrite ? null : () => run(() async {
                await widget.store.retryComment(row['local_id'] as String);
                await widget.synchronize(); await refresh();
              }), child: const Text('Повторить')),
              TextButton(onPressed: busy ? null : () => discard(row), child: const Text('Убрать с устройства')),
            ]),
          ],
        ))),
        const Divider(height: 32),
        TextField(controller: body, enabled: !busy && widget.canWrite, minLines: 3, maxLines: 8,
          maxLength: 10000, decoration: const InputDecoration(labelText: 'Новый комментарий', border: OutlineInputBorder())),
        FilledButton.icon(onPressed: busy || !widget.canWrite ? null : send,
          icon: const Icon(Icons.send_outlined), label: const Text('Сохранить и отправить')),
        const Text('Без сети комментарий останется в очереди. Набранный текст сохраняется после нажатия кнопки.'),
      ],
    ))),
    actions: [TextButton(onPressed: busy ? null : () => Navigator.pop(context), child: const Text('Закрыть'))],
  ));
}

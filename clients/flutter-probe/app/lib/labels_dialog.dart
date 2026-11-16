import 'dart:async';
import 'package:flutter/material.dart';
import 'account_store.dart';
import 'task_labels.dart';
import 'workspace_api.dart';

class LabelsDialog extends StatefulWidget {
  final AccountStore store;
  final bool canWrite;
  final Listenable? changes;
  final String Function()? syncMessage;

  final Future<void> Function() synchronize;
  const LabelsDialog({super.key, required this.store, required this.canWrite, required this.synchronize,this.changes,this.syncMessage});
  @override
  State<LabelsDialog> createState() => _LabelsDialogState();
}

class _LabelsDialogState extends State<LabelsDialog> {
  final name = TextEditingController();
  String color = 'green';
  String message = 'Метки доступны из локальной копии.';
  bool busy = true;
  List<Map<String, Object?>> rows = [];
  @override
  void initState() { super.initState();widget.changes?.addListener(cacheChanged); run(() async {}); }
  Future<void> run(Future<void> Function() operation) async {
    setState(() => busy = true);
    try { await operation(); }
    catch (error) {
      message = error is ApiFailure ? error.message : error is ArgumentError ? error.message.toString()
          : 'Не удалось обновить метки. Локальная очередь сохранена.';
    } finally {
      try { rows = await widget.store.labels(); }
      catch (_) { message = 'Не удалось прочитать локальный каталог.'; }
      if (mounted) setState(() => busy = false);
    }
  }
  int cacheVersion=0;
  void cacheChanged(){unawaited(readCache());}
  Future<void> readCache() async {
    final version=++cacheVersion;
    try{
      final loaded=await widget.store.labels();
      if(mounted&&version==cacheVersion)setState((){rows=loaded;if(!busy&&widget.syncMessage!=null)message=widget.syncMessage!();});
    }catch(_){/* Retain the last displayed cache if closing or a storage read fails. */}
  }

  @override
  void dispose() { widget.changes?.removeListener(cacheChanged);name.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => PopScope(canPop: !busy, child: AlertDialog(
    title: const Text('Метки'),
    content: SizedBox(width: 580, child: SingleChildScrollView(child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        if (busy) const LinearProgressIndicator(),
        Text(message),
        TextButton(onPressed: busy ? null : () => run(() async { await widget.synchronize(); message = 'Обновление каталога запрошено.'; }),
          child: const Text('Обновить и отправить очередь')),
        for (final label in rows) ListTile(
          leading: Icon(Icons.label, color: Color(TaskLabels.colors[label['color']] ?? 0xff929a9e)),
          title: Text(label['name'] as String),
          subtitle: Text(label['state'] == 'sent' ? 'На сайте' : label['state'] == 'blocked' ? '${label['error']}' : 'Ожидает отправки'),
          trailing: label['state'] != 'blocked' ? null : TextButton(
            onPressed: busy || !widget.canWrite ? null : () => run(() async {
              await widget.store.retryLabel(label['local_id'] as String); await widget.synchronize();
            }), child: const Text('Повторить')),
        ),
        const Divider(),
        TextField(controller: name, enabled: !busy && widget.canWrite, maxLength: 40,
          decoration: const InputDecoration(labelText: 'Название новой метки')),
        DropdownButton<String>(value: color, isExpanded: true,
          items: [for (final entry in TaskLabels.colorNames.entries)
            DropdownMenuItem(value: entry.key, child: Text(entry.value, style: TextStyle(color: Color(TaskLabels.colors[entry.key]!))))],
          onChanged: busy || !widget.canWrite ? null : (value) { if (value != null) setState(() => color = value); }),
        FilledButton(onPressed: busy || !widget.canWrite ? null : () => run(() async {
          await widget.store.addLabel(name.text, color); name.clear();
          message = 'Метка сохранена на устройстве.'; await widget.synchronize();
          message = 'Метка сохранена. Отправка выполняется в фоне.';
        }), child: const Text('Создать метку')),
        const Text('Без сети новая метка сохранится в очереди. Если такое имя уже есть на сайте, используем существующую метку и её цвет.'),
      ],
    ))),
    actions: [TextButton(onPressed: busy ? null : () => Navigator.pop(context), child: const Text('Закрыть'))],
  ));
}

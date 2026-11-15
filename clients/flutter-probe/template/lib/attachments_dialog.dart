import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'account_store.dart';
import 'attachment_files.dart';
import 'attachments_sync.dart';
import 'file_transfers.dart';
import 'workspace_api.dart';

class AttachmentsDialog extends StatefulWidget {
  final AccountStore store;final WorkspaceApi api;
  final String token,localId,taskTitle;final bool canWrite;
  final Future<void> Function() synchronize;
  const AttachmentsDialog({super.key,required this.store,required this.api,required this.token,
    required this.localId,required this.taskTitle,required this.canWrite,required this.synchronize});
  @override
  State<AttachmentsDialog> createState()=>_AttachmentsDialogState();
}
class _AttachmentsDialogState extends State<AttachmentsDialog> {
  final transport=NativeFileTransfers();
  List<Map<String,Object?>> rows=[];bool busy=true;String message='Открываем сохранённый список файлов…';
  @override
  void initState(){super.initState();run(() async {rows=await widget.store.attachments(widget.localId);if(mounted)setState((){});await refresh();});}
  Future<void> run(Future<void> Function() operation) async {
    setState(()=>busy=true);
    try {await operation();}
    catch(error){message=error is ApiFailure?error.message:error is ArgumentError?error.message.toString():'Не удалось выполнить действие. Очередь файлов сохранена.';}
    finally {try {rows=await widget.store.attachments(widget.localId);}catch(_){message='Не удалось прочитать локальный список';}if(mounted)setState(()=>busy=false);}
  }
  Future<void> refresh() async {
    await AttachmentsSync.refresh(widget.api,widget.store,widget.token,widget.localId);
    message='Список обновлён. Скачанные копии доступны без сети.';
  }
  Future<void> add() =>run(() async {
    final picked=await FilePicker.pickFile(type:FileType.custom,allowedExtensions:AttachmentFiles.extensions);
    if(picked==null)return;
    message='Сохраняем собственную копию файла…';if(mounted)setState((){});
    final size=await picked.length();
    await AttachmentFiles(widget.store).stage(widget.localId,picked.name,picked.readAsByteStream(),length:size);
    message='Копия сохранена. Отправляем очередь…';if(mounted)setState((){});
    await widget.synchronize();await refresh();
  });
  Future<void> save(Map<String,Object?> file)=>run(() async {
    message='Проверяем или скачиваем файл…';if(mounted)setState((){});
    final local=await AttachmentsSync.cached(widget.store,transport,widget.token,file);
    final saved=await FilePicker.saveFile(fileName:file['name'] as String,bytes:await File(local).readAsBytes());
    message=saved==null?'Сохранение отменено. Копия осталась в приложении.':'Файл сохранён в выбранное место.';
  });
  Future<void> remove(Map<String,Object?> file)=>run(() async {
    final pending=file['state']!='sent';
    final yes=await showDialog<bool>(context:context,builder:(context)=>AlertDialog(
      title:Text(pending?'Убрать неотправленную копию?':'Удалить скачанную копию?'),
      content:const Text('Удалится только локальная копия приложения. Исходный файл и вложения на сайте останутся.'),
      actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('Отмена')),
        FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('Удалить копию'))],
    ));
    if(yes!=true)return;
    if(pending)await widget.store.discardAttachment(file['local_id'] as String);
    else await widget.store.uncacheAttachment(file['local_id'] as String);
    await AttachmentFiles(widget.store).remove(file['local_path'] as String?);
  });
  @override
  Widget build(BuildContext context)=>PopScope(canPop:!busy,child:AlertDialog(
    title:Text('Файлы · ${widget.taskTitle}'),
    content:SizedBox(width:680,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      if(busy)const LinearProgressIndicator(),Text(message),
      Wrap(spacing:8,children:[
        TextButton(onPressed:busy?null:()=>run(() async {await widget.synchronize();await refresh();}),child:const Text('Обновить и отправить очередь')),
        FilledButton.icon(onPressed:busy||!widget.canWrite||rows.length>=50?null:add,icon:const Icon(Icons.attach_file),label:const Text('Добавить файл')),
      ]),
      if(rows.isEmpty)const Padding(padding:EdgeInsets.all(16),child:Text('В сохранённом списке пока нет файлов.')),
      for(final file in rows)Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Text(file['name'] as String,style:Theme.of(context).textTheme.titleMedium),
        Text('${((file['bytes'] as int)/1024).toStringAsFixed(1)} КБ · ${file['state']=='sent'?'на сайте':file['state']=='blocked'?'не отправлен: ${file['error']}':'ожидает отправки'}'),
        Wrap(spacing:8,children:[
          TextButton(onPressed:busy?null:()=>save(file),child:const Text('Сохранить как…')),
          if(file['state']=='blocked')TextButton(onPressed:busy||!widget.canWrite?null:()=>run(() async {
            await widget.store.retryAttachment(file['local_id'] as String);await widget.synchronize();await refresh();
          }),child:const Text('Повторить')),
          if(file['local_path']!=null&&(file['state']=='sent'||file['state']=='blocked'))TextButton(onPressed:busy?null:()=>remove(file),child:const Text('Убрать локальную копию')),
        ]),
      ]))),
      const Text('До 10 МБ на файл. Без сети выбранный файл копируется в приложение и ждёт отправки. Удаление вложений с сайта пока выполняется через сайт.'),
    ]))),
    actions:[TextButton(onPressed:busy?null:()=>Navigator.pop(context),child:const Text('Закрыть'))],
  ));
}

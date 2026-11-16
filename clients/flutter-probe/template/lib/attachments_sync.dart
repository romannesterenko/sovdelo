import 'dart:io';
import 'account_store.dart';
import 'attachment_files.dart';
import 'file_transfers.dart';
import 'workspace_api.dart';

class AttachmentsSync {
  static Future<void> refresh(WorkspaceApi api,AccountStore store,String token,String id,{void Function()? check}) async {
    final task=await store.task(id);if(task['server_id']==null)return;
    check?.call();final list=await api.attachments(token,task['server_id'] as int);
    check?.call();await store.mergeAttachments(id,list);
  }
  static Future<String> cached(AccountStore store,AttachmentTransport transport,String token,Map<String,Object?> file) async {
    final files=AttachmentFiles(store);
    try {await files.verify(file);return file['local_path'] as String;}on ArgumentError{/* Download a verified replacement. */}
    final task=await store.task(file['task_local_id'] as String);
    if(task['server_id']==null||file['server_id']==null)throw ArgumentError('Локальная копия ещё не отправленного файла недоступна');
    await files.capacity(file['bytes'] as int);
    final target=files.path('cache-${file['local_id']}');
    final partial=File('$target.part');
    try {
      final hash=await transport.download(token,task['server_id'] as int,file['server_id'] as int,partial.path);
      if(!await partial.exists()||await partial.length()!=file['bytes']||await files.digest(partial.path)!=hash||
          (file['sha256']!=null&&file['sha256']!=hash))throw const ApiFailure(0,'Скачанный файл не прошёл проверку целостности');
      await partial.rename(target);await store.cacheAttachment(file['local_id'] as String,target,hash);
      return target;
    }finally{if(await partial.exists())await partial.delete();}
  }
}

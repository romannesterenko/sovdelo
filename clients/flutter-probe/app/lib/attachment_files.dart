import 'dart:io';
import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;
import 'account_store.dart';

class AttachmentFiles {
  static const maxBytes=10*1024*1024, quota=250*1024*1024;
  static const extensions=['pdf','txt','csv','jpg','jpeg','png','webp','zip','doc','docx','xls','xlsx'];
  final AccountStore store;
  AttachmentFiles(this.store);
  Directory get root=>Directory('${store.db.path}.files');
  String path(String key) {
    if(!RegExp(r'^[a-zA-Z0-9-]+$').hasMatch(key)) throw ArgumentError('Некорректное имя локальной копии');
    return p.join(root.path,'$key.bin');
  }
  static String safeName(String name) {
    final base=p.basename(name.replaceAll('\\','/')).replaceAll(RegExp(r'[\x00-\x1f\x7f]'),'_');
    final ext=p.extension(base).replaceFirst('.','').toLowerCase();
    if(!extensions.contains(ext)) throw ArgumentError('Этот тип файла пока не поддерживается');
    final stem=String.fromCharCodes(p.basenameWithoutExtension(base).runes.take(239-ext.length));
    return '${stem.isEmpty?'file':stem}.$ext';
  }
  Future<void> capacity(int bytes) async {
    if(bytes<1||bytes>maxBytes) throw ArgumentError('Файл должен быть непустым и не больше 10 МБ');
    await root.create(recursive:true);
    var used=0;
    await for(final entity in root.list(followLinks:false)) {
      if(entity is File) used+=await entity.length();
    }
    if(used+bytes>quota) throw ArgumentError('Локальные копии заняли 250 МБ. Удали ненужные скачанные копии');
  }
  Future<String> digest(String file) async =>(await crypto.sha256.bind(File(file).openRead()).first).toString();
  Future<void> stage(String taskId,String name,Stream<List<int>> input,{int? length}) async {
    final safe=safeName(name);
    if(length!=null&&(length<1||length>maxBytes)) throw ArgumentError('Файл должен быть непустым и не больше 10 МБ');
    await capacity(length??maxBytes);
    final key=operationUuid(); final target=path(key);
    final partial=File('$target.part');
    final sink=partial.openWrite();var bytes=0;var committed=false;
    try {
      try {
        await for(final chunk in input.timeout(const Duration(seconds:120))) {
          bytes+=chunk.length;if(bytes>maxBytes)throw ArgumentError('Файл больше 10 МБ');sink.add(chunk);
        }
        await sink.flush();
      } finally {await sink.close();}
      if(bytes<1||(length!=null&&length!=bytes))throw ArgumentError('Файл пуст или изменился во время копирования');
      await partial.rename(target);
      final hash=await digest(target);
      await store.addAttachment(taskId,key,safe,target,bytes,hash);committed=true;
    } finally {
      if(await partial.exists())await partial.delete();
      if(!committed&&await File(target).exists())await File(target).delete();
    }
  }
  Future<void> verify(Map<String,Object?> file) async {
    final name=file['local_path'] as String?;
    if(name==null||!p.isWithin(root.absolute.path,File(name).absolute.path)||!await File(name).exists())throw ArgumentError('Локальная копия файла недоступна');
    if(await File(name).length()!=file['bytes']||await digest(name)!=file['sha256'])throw ArgumentError('Локальная копия повреждена. Выбери исходный файл заново');
  }
  Future<void> remove(String? file) async {
    if(file==null)return;
    if(!p.isWithin(root.absolute.path,File(file).absolute.path))throw ArgumentError('Файл вне каталога приложения');
    if(await File(file).exists())await File(file).delete();
  }
  Future<void> cleanOrphans() async {
    if(!await root.exists())return;
    final referenced=(await store.db.query('account_attachments',columns:['local_path'])).map((r)=>r['local_path']).toSet();
    await for(final entity in root.list(followLinks:false)) {
      if(entity is! File||referenced.contains(entity.path))continue;
      if(DateTime.now().difference((await entity.stat()).modified)>const Duration(days:1))await entity.delete();
    }
  }
}

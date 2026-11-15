import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sovdelo_probe/account_store.dart';
import 'package:sovdelo_probe/account_sync.dart';
import 'package:sovdelo_probe/attachment_files.dart';
import 'package:sovdelo_probe/attachments_sync.dart';
import 'package:sovdelo_probe/file_transfers.dart';
import 'package:sovdelo_probe/workspace_api.dart';

class TestTransfers implements AttachmentTransport {
  Map<String,dynamic>? receipt;bool loseReply=false;int creates=0,uploads=0,downloads=0;
  List<int> downloadBytes=utf8.encode('hello');
  @override
  Future<Map<String,dynamic>> upload(String token,Map<String,Object?> op) async {
    uploads++;
    if(receipt!=null)return receipt!;
    creates++;
    receipt={'operation_uuid':op['local_id'],'attachment':{'id':11,'uuid':op['local_id'],'name':op['name'],
      'bytes':op['bytes'],'sha256':op['sha256'],'created_at':'2026-11-15T10:00:00Z'}};
    if(loseReply){loseReply=false;throw const ApiFailure(0,'Reply lost');}
    return receipt!;
  }
  @override
  Future<String> download(String token,int task,int attachment,String target) async {
    downloads++;await File(target).writeAsBytes(downloadBytes);return crypto.sha256.convert(downloadBytes).toString();
  }
}

void main(){
  sqfliteFfiInit();late Directory dir;late AccountStore store;
  final uuid=operationUuid();
  Map<String,dynamic> task({int count=0})=>{'id':7,'uuid':uuid,'version':1,'title':'Задача','status':'todo','active':true,'attachments_count':count};
  setUp(()async{dir=await Directory.systemTemp.createTemp('attachments-');store=await AccountStore.open(databaseFactoryFfi,'${dir.path}/account.db');await store.merge([task()]);});
  tearDown(()async{await store.db.close();await dir.delete(recursive:true);});

  test('Собственная копия не зависит от исходника; очередь сохраняется после рестарта',()async{
    final source=File('${dir.path}/original.txt');await source.writeAsString('hello');
    await AttachmentFiles(store).stage(uuid,'original.txt',source.openRead(),length:5);
    await source.writeAsString('changed');
    final op=(await store.prepareAttachment())!;
    expect(await File(op['local_path'] as String).readAsString(),'hello');
    final request=op['request_json'];await store.db.close();
    store=await AccountStore.open(databaseFactoryFfi,'${dir.path}/account.db');
    expect((await store.prepareAttachment())!['request_json'],request);
    await AttachmentFiles(store).verify((await store.attachments(uuid)).single);
    expect(await store.pendingCount(),1);expect(await source.readAsString(),'changed');
  });

  test('Потеря ответа загрузки повторяет UUID/хэш, не создаёт второй файл',()async{
    await AttachmentFiles(store).stage(uuid,'note.txt',Stream.value(utf8.encode('hello')),length:5);
    final transfers=TestTransfers()..loseReply=true;
    final api=WorkspaceApi(transport:(method,path,token,body)async{
      if(path.startsWith('projects?'))return {'data':[],'meta':{'last_page':1}};
      if(path.startsWith('labels?'))return {'data':[],'meta':{'through_id':0,'after_id':0,'has_more':false}};
      if(path=='tasks/7/attachments')return {'data':transfers.receipt==null?[]:[transfers.receipt!['attachment']]};
      return {'data':[task(count:transfers.receipt==null?0:1)],'meta':{'through_id':7,'after_id':7,'has_more':false}};
    });
    await expectLater(AccountSync(api,store,transport:transfers).synchronize('token',write:true),throwsA(isA<ApiFailure>()));
    expect(await store.pendingCount(),1);
    await store.db.close();store=await AccountStore.open(databaseFactoryFfi,'${dir.path}/account.db');
    await AccountSync(api,store,transport:transfers).synchronize('token',write:true);
    expect(transfers.creates,1);expect(transfers.uploads,2);expect(await store.pendingCount(),0);
    expect((await store.attachments(uuid)).length,1);expect((await store.attachments(uuid)).single['state'],'sent');
  });

  test('Ошибка SQLite или превышение размера не оставляют копию и полузапись',()async{
    await store.db.execute("CREATE TRIGGER fail_file BEFORE INSERT ON account_attachments BEGIN SELECT RAISE(ABORT, 'test failure'); END");
    await expectLater(AttachmentFiles(store).stage(uuid,'note.txt',Stream.value(utf8.encode('hello')),length:5),throwsA(isA<DatabaseException>()));
    expect(await AttachmentFiles(store).root.list().toList(),isEmpty);
    await expectLater(AttachmentFiles(store).stage(uuid,'big.txt',Stream.value(List.filled(AttachmentFiles.maxBytes+1,65))),throwsArgumentError);
    expect(await AttachmentFiles(store).root.list().toList(),isEmpty);expect(await store.attachments(uuid),isEmpty);
  });

  test('Повреждённая копия не отправляется, остаётся как блокированное вложение',()async{
    await AttachmentFiles(store).stage(uuid,'note.txt',Stream.value(utf8.encode('hello')),length:5);
    final row=(await store.attachments(uuid)).single;await File(row['local_path'] as String).writeAsString('world');
    final transfers=TestTransfers();
    final api=WorkspaceApi(transport:(method,path,token,body)async{
      if(path.startsWith('projects?'))return {'data':[],'meta':{'last_page':1}};
      if(path.startsWith('labels?'))return {'data':[],'meta':{'through_id':0,'after_id':0,'has_more':false}};
      return {'data':[task()],'meta':{'through_id':7,'after_id':7,'has_more':false}};
    });
    await AccountSync(api,store,transport:transfers).synchronize('token',write:true);
    expect(transfers.uploads,0);expect((await store.attachments(uuid)).single['state'],'blocked');expect(await store.pendingCount(),1);
  });

  test('Скачивание проверяет хэш, следующая выдача работает из кэша без сети',()async{
    final hash=crypto.sha256.convert(utf8.encode('hello')).toString();
    await store.mergeAttachments(uuid,[{'id':11,'uuid':null,'name':'note.txt','bytes':5,'sha256':hash,'created_at':'now'}]);
    final transfers=TestTransfers();
    final first=await AttachmentsSync.cached(store,transfers,'token',(await store.attachments(uuid)).single);
    expect(await File(first).readAsString(),'hello');
    final second=await AttachmentsSync.cached(store,transfers,'token',(await store.attachments(uuid)).single);
    expect(second,first);expect(transfers.downloads,1);
  });

  test('Неверный хэш скачивания не попадает в кэш',()async{
    await store.mergeAttachments(uuid,[{'id':11,'uuid':null,'name':'note.txt','bytes':5,
      'sha256':crypto.sha256.convert(utf8.encode('hello')).toString(),'created_at':'now'}]);
    final transfers=TestTransfers()..downloadBytes=utf8.encode('world');
    await expectLater(AttachmentsSync.cached(store,transfers,'token',(await store.attachments(uuid)).single),throwsA(isA<ApiFailure>()));
    expect((await store.attachments(uuid)).single['local_path'],isNull);
    expect(await AttachmentFiles(store).root.list().toList(),isEmpty);
  });

  test('Файл новой задачи ждёт подтверждения create, принятие полей сайта не удаляет файл',()async{
    await store.add('Новая');final local=(await store.tasks()).firstWhere((t)=>t['server_id']==null);final id=local['local_id'] as String;
    await AttachmentFiles(store).stage(id,'note.txt',Stream.value(utf8.encode('hello')),length:5);
    expect(await store.prepareAttachment(),isNull);
    final op=(await store.prepare())!;await store.acknowledge(op,{'operation_uuid':op['operation_uuid'],'task':{...task(),'id':9,'uuid':id}});
    expect(jsonDecode((await store.prepareAttachment())!['request_json'] as String)['task_id'],9);
    await store.acceptServer(id,{...task(),'id':9,'uuid':id,'active':false});
    expect((await store.tasks()).any((t)=>t['local_id']==id),isTrue);expect((await store.attachments(id)).length,1);
  });

  test('Миграция v5 сохраняет замороженную операцию и прежние данные',()async{
    await store.db.close();final path='${dir.path}/old.db';
    final old=await databaseFactoryFfi.openDatabase(path,options:OpenDatabaseOptions(version:5,onCreate:(db,version)async{
      await db.execute("CREATE TABLE account_tasks(local_id TEXT PRIMARY KEY,server_id INTEGER UNIQUE,server_version INTEGER,title TEXT NOT NULL,status TEXT NOT NULL,active INTEGER NOT NULL DEFAULT 1,remote_json TEXT,description TEXT,due_date TEXT,priority TEXT NOT NULL DEFAULT 'normal',project_id INTEGER,checklist_json TEXT NOT NULL DEFAULT '[]',labels_json TEXT NOT NULL DEFAULT '[]')");
      await db.execute('CREATE TABLE account_queue(sequence INTEGER PRIMARY KEY AUTOINCREMENT,operation_uuid TEXT UNIQUE NOT NULL,local_id TEXT NOT NULL,kind TEXT NOT NULL,title TEXT,status TEXT,body TEXT,blocked INTEGER NOT NULL DEFAULT 0,error TEXT,fields TEXT)');
      await db.execute('CREATE TABLE account_projects(id INTEGER PRIMARY KEY,name TEXT NOT NULL)');
      await db.execute('CREATE TABLE account_comments(local_id TEXT PRIMARY KEY,server_id INTEGER UNIQUE,task_local_id TEXT NOT NULL,body TEXT NOT NULL,author TEXT NOT NULL,created_at TEXT NOT NULL,updated_at TEXT NOT NULL,state TEXT NOT NULL,request_json TEXT,error TEXT)');
      await db.execute('CREATE TABLE account_labels(local_id TEXT PRIMARY KEY,server_id INTEGER UNIQUE,name TEXT UNIQUE NOT NULL,color TEXT NOT NULL,state TEXT NOT NULL,request_json TEXT,error TEXT)');
    }));
    final key=operationUuid();final body=jsonEncode({'operation_uuid':key,'kind':'status','task_id':7,'expected_version':1,'status':'done'});
    await old.insert('account_tasks',{'local_id':uuid,'server_id':7,'server_version':1,'title':'Задача','status':'done'});
    await old.insert('account_queue',{'operation_uuid':key,'local_id':uuid,'kind':'status','status':'done','body':body});await old.close();
    store=await AccountStore.open(databaseFactoryFfi,path);expect((await store.prepare())!['body'],body);
    expect((await store.task(uuid))['status'],'done');expect(await store.attachments(uuid),isEmpty);
  });
}

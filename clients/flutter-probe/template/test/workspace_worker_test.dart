import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sovdelo_probe/account_store.dart';
import 'package:sovdelo_probe/workspace_api.dart';
import 'package:sovdelo_probe/workspace_worker.dart';

class WorkerServer {
  int active=0,maxActive=0,meCalls=0,creates=0;
  ApiFailure? failure;
  Completer<void>? gateMe,gatePost;
  final meStarted=Completer<void>(),postStarted=Completer<void>();
  final records=<Map<String,dynamic>>[];
  late final api=WorkspaceApi(transport:request);
  Future<Map<String,dynamic>> request(String method,String path,String? token,Map<String,dynamic>? body) async {
    active++;if(active>maxActive)maxActive=active;
    try {
      if(path=='me') {
        meCalls++;if(!meStarted.isCompleted)meStarted.complete();
        final gate=gateMe;gateMe=null;if(gate!=null)await gate.future;
        if(failure!=null)throw failure!;
        return {'data':{'id':1,'name':'Роман','email':'one@example.com','access':'write'}};
      }
      if(path.startsWith('projects?'))return {'data':[],'meta':{'last_page':1}};
      if(path.startsWith('labels?'))return {'data':[],'meta':{'through_id':0,'after_id':0,'has_more':false}};
      if(method=='GET')return {'data':records.map((r)=>Map<String,dynamic>.from(r)).toList(),
        'meta':{'through_id':records.length,'after_id':records.length,'has_more':false}};
      final payload=body!;
      if(!postStarted.isCompleted)postStarted.complete();
      final gate=gatePost;gatePost=null;if(gate!=null)await gate.future;
      if(payload['kind']=='create') {
        creates++;
        final task=<String,dynamic>{'id':creates,'uuid':payload['operation_uuid'],'version':1,'title':payload['title'],'status':'todo','active':true};
        records.add(task);return {'data':{'operation_uuid':payload['operation_uuid'],'task':task}};
      }
      throw StateError('Unexpected test request');
    }finally{active--;}
  }
}

void main(){
  sqfliteFfiInit();late Directory dir;late AccountStore store;WorkspaceWorker? worker;
  var now=DateTime(2026,11,16,10);
  WorkspaceWorker make(WorkerServer server)=>WorkspaceWorker(store:store,api:server.api,token:'fake-token',
    profile:{'id':1,'access':'write'},saveProfile:(_)async{},clock:()=>now,tick:null);
  setUp(()async{now=DateTime(2026,11,16,10);dir=await Directory.systemTemp.createTemp('worker-');store=await AccountStore.open(databaseFactoryFfi,'${dir.path}/account.db');});
  tearDown(()async{await worker?.close();if(store.db.isOpen)await store.db.close();await dir.delete(recursive:true);worker=null;});

  test('Локальная запись не ждёт сеть; повторные запросы используют один worker',()async{
    final server=WorkerServer();final gate=Completer<void>();server.gateMe=gate;
    worker=make(server);worker!.request();await server.meStarted.future;
    final id=await store.add('Без ожидания сети').timeout(const Duration(seconds:2));
    await worker!.refreshLocal();expect(worker!.tasks.single['local_id'],id);expect(worker!.pending,1);
    for(var i=0;i<10;i++){worker!.request();}
    gate.complete();await worker!.idle;
    expect(server.maxActive,1);expect(server.creates,1);expect(worker!.pending,0);
  });

  test('429 запрещает ручной и автоматический повтор до Retry-After',()async{
    final server=WorkerServer()..failure=const ApiFailure(429,'Wait',retryAfter:120);
    worker=make(server);worker!.request();await worker!.idle;
    expect(worker!.retryAt,now.add(const Duration(seconds:120)));
    server.failure=null;
    worker!.request(manual:true);await worker!.idle;expect(server.meCalls,1);
    now=now.add(const Duration(seconds:119));worker!.poll();await worker!.idle;expect(server.meCalls,1);
    now=now.add(const Duration(seconds:2));worker!.poll();await worker!.idle;expect(server.meCalls,2);
  });

  test('Повтор после восстановления связи сохраняет исходную очередь',()async{
    final id=await store.add('Офлайн');
    final server=WorkerServer()..failure=const ApiFailure(0,'Offline');worker=make(server);
    worker!.request();await worker!.idle;
    expect(worker!.pending,1);expect((await store.task(id))['title'],'Офлайн');
    server.failure=null;now=now.add(const Duration(seconds:31));worker!.poll();await worker!.idle;
    expect(worker!.pending,0);expect(server.records.single['uuid'],id);
  });

  test('В фоне новый цикл не запускается, возврат возобновляет обновление',()async{
    final server=WorkerServer();worker=make(server);worker!.setForeground(false);worker!.poll();
    expect(server.meCalls,0);worker!.setForeground(true);await worker!.idle;expect(server.meCalls,1);
  });

  test('Уход в фон завершает текущую операцию, но не досылает оставшуюся очередь',()async{
    await store.add('Первая');await store.add('Вторая');
    final server=WorkerServer();final gate=Completer<void>();server.gatePost=gate;
    worker=make(server);worker!.request();await server.postStarted.future;
    worker!.setForeground(false);gate.complete();await worker!.idle;
    expect(server.creates,1);expect(await store.pendingCount(),1);
    worker!.setForeground(true);await worker!.idle;
    expect(server.creates,2);expect(await store.pendingCount(),0);
  });

  test('401 останавливает отправку и оставляет намерения в SQLite',()async{
    await store.add('Не терять');final server=WorkerServer()..failure=const ApiFailure(401,'Expired');
    worker=make(server);worker!.request();await worker!.idle;
    expect(worker!.requiresLogin,isTrue);expect(await store.pendingCount(),1);
    worker!.request(manual:true);worker!.poll();await worker!.idle;expect(server.meCalls,1);
  });

  test('Закрытие ждёт текущий запрос, подтверждает его и не отправляет всю оставшуюся очередь',()async{
    await store.add('Первая');await store.add('Вторая');
    final server=WorkerServer();final gate=Completer<void>();server.gatePost=gate;
    worker=make(server);worker!.request();await server.postStarted.future;
    final closing=worker!.close();gate.complete();await closing;
    expect(server.creates,1);
    store=await AccountStore.open(databaseFactoryFfi,'${dir.path}/account.db');
    expect(await store.pendingCount(),1);expect((await store.tasks()).length,2);
  });
}

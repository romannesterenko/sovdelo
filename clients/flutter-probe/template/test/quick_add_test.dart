import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sovdelo_probe/account_store.dart';

void main(){
  test('Быстрое создание в проекте сохраняет задачу и оба намерения одной транзакцией',()async{
    sqfliteFfiInit();final dir=await Directory.systemTemp.createTemp('quick-add-');
    final store=await AccountStore.open(databaseFactoryFfi,'${dir.path}/account.db');
    try{
      final id=await store.add('Создать в выбранном проекте',projectId:7);
      expect((await store.task(id))['project_id'],7);
      final operations=await store.db.query('account_queue',orderBy:'sequence');
      expect(operations.length,2);expect(operations[0]['kind'],'create');
      expect(jsonDecode(operations[1]['fields'] as String),{'project_id':7});
      final first=(await store.prepare())!;
      expect(jsonDecode(first['body'] as String)['kind'],'create');
      await store.acknowledge(first,{'operation_uuid':id,'task':{'id':21,'uuid':id,'version':2,
        'title':'Создать в выбранном проекте','status':'todo','project_id':null,'active':true}});
      expect((await store.task(id))['project_id'],7);
      final next=jsonDecode((await store.prepare())!['body'] as String);
      expect(next['expected_version'],2);expect(next['fields'],{'project_id':7});
    }finally{await store.db.close();await dir.delete(recursive:true);}
  });
}

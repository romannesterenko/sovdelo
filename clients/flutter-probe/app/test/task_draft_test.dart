import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sovdelo_probe/account_store.dart';
import 'package:sovdelo_probe/task_draft.dart';
import 'package:sovdelo_probe/task_editor.dart';

void main(){
  sqfliteFfiInit();
  test('Открытый редактор не затирает фоновую правку того же поля',()async{
    final dir=await Directory.systemTemp.createTemp('draft-');final store=await AccountStore.open(databaseFactoryFfi,'${dir.path}/account.db');
    try{
      final dto=<String,dynamic>{'id':1,'uuid':'task','version':1,'title':'До','description':'Описание','status':'todo','active':true};
      await store.merge([dto]);final baseline=await store.task('task');
      await store.merge([{...dto,'version':2,'title':'Изменено на сайте'}]);
      final changed=TaskDraft.changed(baseline,{'title':'Мой текст','description':'Описание'});
      expect(changed,{'title':'Мой текст'});
      await expectLater(store.edit('task',changed,baseline:baseline),throwsA(isA<DraftConflict>()));
      expect((await store.task('task'))['title'],'Изменено на сайте');expect(await store.pendingCount(),0);
      await store.merge([{...dto,'version':3,'description':'Новое описание'}]);
      await store.edit('task',changed,baseline:baseline);
      expect((await store.task('task'))['description'],'Новое описание');
      expect(jsonDecode((await store.prepare())!['body'] as String)['expected_version'],3);
    }finally{await store.db.close();await dir.delete(recursive:true);}
  });
  test('Быстрый статус проверяет состояние, которое видел пользователь',()async{
    final dir=await Directory.systemTemp.createTemp('status-');final store=await AccountStore.open(databaseFactoryFfi,'${dir.path}/account.db');
    try{
      final dto=<String,dynamic>{'id':1,'uuid':'task','version':1,'title':'До','status':'todo','active':true};
      await store.merge([dto]);final before=await store.task('task');
      await store.merge([{...dto,'version':2,'status':'doing'}]);
      await expectLater(store.setStatus('task','done',baseline:before),throwsA(isA<DraftConflict>()));
      expect((await store.task('task'))['status'],'doing');expect(await store.pendingCount(),0);
    }finally{await store.db.close();await dir.delete(recursive:true);}
  });
  test('Устаревшее действие удаления не забирает копию ожидающего файла',()async{
    sqfliteFfiInit();final dir=await Directory.systemTemp.createTemp('pending-file-');
    final store=await AccountStore.open(databaseFactoryFfi,'${dir.path}/account.db');
    try{
      final task=await store.add('Файл');final key=operationUuid();
      await store.addAttachment(task,key,'note.txt','private-copy',5,'sha');
      await store.blockAttachment(key,'Retry');await store.retryAttachment(key);
      expect(await store.discardAttachment(key),isNull);
      expect(await store.uncacheAttachment(key),isNull);
      expect((await store.attachments(task)).single['local_path'],'private-copy');
      expect((await store.attachments(task)).single['state'],'pending');
    }finally{await store.db.close();await dir.delete(recursive:true);}
  });

  testWidgets('Ошибка сохранения оставляет введённый текст в редакторе',(tester)async{
    tester.view.physicalSize=const Size(390,850);tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    Map<String,Object?>? sent;
    await tester.pumpWidget(MaterialApp(home:TaskEditor(task:const {'title':'Исходный','status':'todo','priority':'normal'},projects:const [],fullScreen:true,
      onSave:(fields)async{sent=fields;throw const DraftConflict('Поле изменилось');})));
    await tester.enterText(find.byType(TextFormField).first,'Мой новый текст');
    await tester.tap(find.text('Сохранить'));await tester.pumpAndSettle();
    expect(sent,{'title':'Мой новый текст'});expect(find.text('Поле изменилось'),findsOneWidget);
    expect(find.text('Мой новый текст'),findsOneWidget);expect(find.byType(TaskEditor),findsOneWidget);
  });
}

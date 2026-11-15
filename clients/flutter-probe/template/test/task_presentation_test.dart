import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sovdelo_probe/task_presentation.dart';
import 'package:sovdelo_probe/task_tile.dart';
import 'package:sovdelo_probe/task_detail_view.dart';

Map<String,Object?> sample()=>{'local_id':'local-task','title':'Проверить большой отчёт и отправить коллегам подробное описание результата',
  'description':'Описание для поиска','status':'doing','project_id':7,'due_date':'2026-11-14','priority':'high',
  'pending':1,'pending_comments':2,'pending_attachments':0,'checklist_json':'[{"text":"Первый пункт","done":true}]',
  'labels_json':'["server-label-5"]','remote_json':'{"comments_count":3,"attachments_count":2}'};

void main(){
  test('Поиск и фильтры не теряют офлайн-задачи и совместно сужают список',(){
    final task=sample();
    expect(TaskPresentation.matches(task,query:'ОТЧЁТ',status:'doing',project:7,label:'server-label-5',queued:true),isTrue);
    expect(TaskPresentation.matches(task,query:'для поиска'),isTrue);
    expect(TaskPresentation.matches(task,project:0),isFalse);
    expect(TaskPresentation.matches(task,status:'done'),isFalse);
    expect(TaskPresentation.matches({...task,'pending':0,'pending_comments':0,'pending_attachments':0},queued:true),isFalse);
    expect(TaskPresentation.matches({...task,'project_id':null},project:0),isTrue);
  });
  test('Просрочка считается по дню, выполненная задача не подсвечивается',(){
    final task=sample();
    expect(TaskPresentation.overdue(task,DateTime(2026,11,15)),isTrue);
    expect(TaskPresentation.overdue({...task,'status':'done'},DateTime(2026,11,15)),isFalse);
    expect(TaskPresentation.overdue({...task,'due_date':'2026-11-15'},DateTime(2026,11,15,23)),isFalse);
    expect(TaskPresentation.pending(task),3);
    expect(TaskPresentation.checklist(task),'1/1');
  });
  for(final width in [320.0,1280.0]){
    testWidgets('Карточка помещается на ширине $width и открывает задачу',(tester)async{
      tester.view.physicalSize=Size(width,850);tester.view.devicePixelRatio=1;
      addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
      var opened=0,toggled=0;
      await tester.pumpWidget(MaterialApp(home:Scaffold(body:ListView(children:[TaskTile(task:sample(),
        labels:const [{'local_id':'server-label-5','name':'Очень длинная метка для проверки ширины карточки','color':'red'}],
        projectName:'Очень длинное название проекта с подробностями',onOpen:()=>opened++,onToggle:()=>toggled++)]))));
      expect(tester.takeException(),isNull);
      await tester.tap(find.text(sample()['title'] as String));await tester.pump();expect(opened,1);
      await tester.tap(find.byTooltip('Отметить выполненной'));await tester.pump();expect(toggled,1);
      expect(tester.takeException(),isNull);
    });
  }
  testWidgets('Деталка показывает локальные поля и передаёт отметку чек-листа',(tester)async{
    tester.view.physicalSize=const Size(390,850);tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    String? action;Object? payload;
    await tester.pumpWidget(MaterialApp(home:TaskDetailView(initial:sample(),projects:const [{'id':7,'name':'Работа'}],labels:const [],
      fullScreen:true,canWrite:true,message:()=> 'Сохранено локально',action:(kind,task,value)async{action=kind;payload=value;return task;})));
    expect(find.text(sample()['title'] as String),findsOneWidget);
    await tester.tap(find.text('Чек-лист'));await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));await tester.pumpAndSettle();
    expect(action,'checklist');expect((payload as List).single['done'],isFalse);expect(tester.takeException(),isNull);
  });
}

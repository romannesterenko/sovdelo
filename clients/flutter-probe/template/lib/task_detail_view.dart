import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'checklists.dart';
import 'task_labels.dart';
import 'task_presentation.dart';

typedef TaskAction=Future<Map<String,Object?>?> Function(String action,Map<String,Object?> task,Object? value);
class TaskDetailView extends StatefulWidget {
  final Map<String,Object?> initial;
  final List<Map<String,Object?>> projects,labels;
  final bool fullScreen,canWrite;
  final TaskAction action;
  final Listenable? changes;
  final Future<Map<String,Object?>?> Function()? readTask;
  final String Function() message;
  final Future<List<Map<String,Object?>>> Function()? readProjects,readLabels;
  const TaskDetailView({super.key,required this.initial,required this.projects,required this.labels,
    required this.fullScreen,required this.canWrite,required this.action,required this.message,this.readProjects,this.readLabels,this.changes,this.readTask});
  @override
  State<TaskDetailView> createState()=>_TaskDetailViewState();
}
class _TaskDetailViewState extends State<TaskDetailView> {
  late Map<String,Object?> task={...widget.initial};
  bool busy=false;String note='';
  late List<Map<String,Object?>> projectRows=[...widget.projects],labelRows=[...widget.labels];
  int cacheVersion=0;
  @override
  void initState(){super.initState();widget.changes?.addListener(cacheChanged);}
  @override
  void dispose(){widget.changes?.removeListener(cacheChanged);super.dispose();}
  void cacheChanged(){if(!busy)unawaited(readCache());}
  Future<void> readCache() async {
    final version=++cacheVersion;
    try{
      final updated=await widget.readTask?.call();
      final projects=await widget.readProjects?.call()??projectRows;
      final labels=await widget.readLabels?.call()??labelRows;
      if(mounted&&!busy&&version==cacheVersion&&updated!=null)setState((){task=updated;projectRows=projects;labelRows=labels;note=widget.message();});
    }catch(_){/* Keep the displayed cache if the account is closing. */}
  }
  Future<void> perform(String action,[Object? value,Map<String,Object?>? baseline]) async {
    setState(()=>busy=true);
    try {
      final updated=await widget.action(action,baseline??task,value);
      if(!mounted)return;
      if(updated==null){Navigator.pop(context);return;}
      final projects=await widget.readProjects?.call()??projectRows;
      final labels=await widget.readLabels?.call()??labelRows;
      if(mounted)setState((){task=updated;projectRows=projects;labelRows=labels;note=widget.message();});
    }catch(_){if(mounted)setState(()=>note='Не удалось выполнить действие. Повтори после обновления.');}
    finally{if(mounted)setState(()=>busy=false);}
  }
  Widget section(String title,Widget child)=>Padding(padding:const EdgeInsets.only(bottom:24),child:Column(
    crossAxisAlignment:CrossAxisAlignment.stretch,children:[Text(title,style:Theme.of(context).textTheme.titleSmall),const SizedBox(height:8),child],
  ));
  @override
  Widget build(BuildContext context){
    final projects=projectRows.where((p)=>p['id']==task['project_id']);
    final checklist=Checklists.read(task['checklist_json']);
    final locked=busy||!widget.canWrite||task['blocked']==1;
    final page=DefaultTabController(length:2,child:Scaffold(
      appBar:AppBar(title:const Text('Задача'),leading:IconButton(onPressed:busy?null:()=>Navigator.pop(context),icon:Icon(widget.fullScreen?Icons.arrow_back:Icons.close)),
        actions:[IconButton(tooltip:'Редактировать',onPressed:locked?null:()=>perform('edit'),icon:const Icon(Icons.edit_outlined))],
        bottom:const TabBar(tabs:[Tab(text:'Описание'),Tab(text:'Чек-лист')]),
      ),
      body:Column(children:[
        if(busy)const LinearProgressIndicator(),
        if(note.isNotEmpty)Padding(padding:const EdgeInsets.fromLTRB(20,12,20,0),child:Text(note,maxLines:3,overflow:TextOverflow.ellipsis)),
        Expanded(child:TabBarView(children:[
          ListView(padding:const EdgeInsets.all(20),children:[
            Text(task['title'] as String,style:Theme.of(context).textTheme.headlineSmall),const SizedBox(height:16),
            if(task['blocked']==1)Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
              Text('Нужно разобрать конфликт: ${task['error']}'),TextButton(onPressed:busy?null:()=>perform('resolve'),child:const Text('Сравнить версии')),
            ]))),
            Row(children:[Expanded(child:DropdownButton<String>(value:task['status'] as String,isExpanded:true,
              items:[for(final entry in TaskPresentation.statuses.entries)DropdownMenuItem(value:entry.key,child:Text(entry.value))],
              onChanged:locked?null:(value){if(value!=null){final baseline={...task};setState(()=>task={...task,'status':value});perform('status',value,baseline);}})),
              if(task['priority']=='high')const Padding(padding:EdgeInsets.only(left:16),child:Icon(Icons.flag,color:Color(0xffe3a057))),
            ]),
            const SizedBox(height:12),
            section('Проект',Text(projects.isEmpty?(task['project_id']==null?'Без проекта':'Проект #${task['project_id']} · недоступен'):projects.first['name'] as String)),
            section('Срок',Text(task['due_date']==null?'Не задан':TaskPresentation.due(task['due_date']))),
            if(TaskLabels.read(task['labels_json']).isNotEmpty)section('Метки',Wrap(spacing:6,runSpacing:4,children:[
              for(final key in TaskLabels.read(task['labels_json']))Builder(builder:(_){
                final found=labelRows.where((l)=>l['local_id']==key);final label=found.isEmpty?null:found.first;
                return Chip(label:Text(label?['name'] as String? ?? 'Недоступная метка'),avatar:Icon(Icons.label,size:16,color:Color(TaskLabels.colors[label?['color']]??0xff929a9e)));
              }),
            ])),
            section('Описание',SelectableText((task['description'] as String?)?.isNotEmpty==true?task['description'] as String:'Пока без описания')),
            if(TaskPresentation.pending(task)>0)const Text('Есть изменения, ожидающие отправки.'),
            const Divider(height:32),
            ListTile(contentPadding:EdgeInsets.zero,leading:const Icon(Icons.chat_bubble_outline),
              title:const Text('Комментарии'),subtitle:Text('На сайте: ${TaskPresentation.count(task,'comments_count')} · в очереди: ${task['pending_comments']??0}'),
              trailing:const Icon(Icons.chevron_right),onTap:busy?null:()=>perform('comments')),
            ListTile(contentPadding:EdgeInsets.zero,leading:const Icon(Icons.attach_file),
              title:const Text('Файлы'),subtitle:Text('На сайте: ${TaskPresentation.count(task,'attachments_count')} · в очереди: ${task['pending_attachments']??0}'),
              trailing:const Icon(Icons.chevron_right),onTap:busy?null:()=>perform('files')),
          ]),
          ListView(padding:const EdgeInsets.all(16),children:[
            Padding(padding:const EdgeInsets.all(8),child:Text('Выполнено ${TaskPresentation.checklist(task)}')),
            if(checklist.isEmpty)const Padding(padding:EdgeInsets.all(16),child:Text('Пунктов пока нет. Добавь их в редакторе задачи.')),
            for(var index=0;index<checklist.length;index++)CheckboxListTile(
              value:checklist[index]['done'] as bool,title:Text(checklist[index]['text'] as String),controlAffinity:ListTileControlAffinity.leading,
              onChanged:locked?null:(done){
                final updated=checklist.map((item)=>Map<String,dynamic>.from(item)).toList();updated[index]['done']=done??false;
                final baseline={...task};setState(()=>task={...task,'checklist_json':jsonEncode(updated)});perform('checklist',updated,baseline);
              },
            ),
            TextButton.icon(onPressed:locked?null:()=>perform('edit'),icon:const Icon(Icons.edit_outlined),label:const Text('Изменить пункты')),
          ]),
        ])),
      ]),
    ));
    return PopScope(canPop:!busy,child:widget.fullScreen?page:Dialog(
      clipBehavior:Clip.antiAlias,child:SizedBox(width:1000,height:MediaQuery.sizeOf(context).height*.9,child:page),
    ));
  }
}

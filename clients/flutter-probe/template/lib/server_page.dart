import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as native;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;
import 'workspace_api.dart';
import 'account_store.dart';
import 'workspace_worker.dart';
import 'task_draft.dart';
import 'task_editor.dart';
import 'checklists.dart';
import 'comments_dialog.dart';
import 'labels_dialog.dart';
import 'task_labels.dart';
import 'attachments_dialog.dart';
import 'attachment_files.dart';
import 'diagnostics_page.dart';
import 'task_tile.dart';
import 'task_presentation.dart';
import 'task_detail_view.dart';

class SecureTokenVault implements TokenVault {
  final storage = const FlutterSecureStorage();
  static const key = 'sovdelo.production.read-session.v1';
  Future<Map<String, dynamic>?> record() async {
    final value = await storage.read(key: key);
    if (value == null) return null;
    if (!value.startsWith('{')) return {'token': value}; // Patch 21 sessions.
    return Map<String, dynamic>.from(jsonDecode(value) as Map);
  }
  @override
  Future<String?> read() async => (await record())?['token'] as String?;
  @override
  Future<void> write(String token) => storage.write(key: key, value: token);
  Future<void> remember(String token, Map<String, dynamic> profile) => storage.write(
      key: key, value: jsonEncode({'token': token, 'profile': profile}));
  Future<Map<String, dynamic>?> profile(String token) async {
    final saved = await record();
    if (saved?['token'] != token || saved?['profile'] is! Map) return null;
    return Map<String, dynamic>.from(saved!['profile'] as Map);
  }
  @override
  Future<void> delete() => storage.delete(key: key);
}

class ServerPage extends StatefulWidget {
  const ServerPage({super.key});
  @override
  State<ServerPage> createState() => _ServerPageState();
}

class _ServerPageState extends State<ServerPage> with WidgetsBindingObserver {
  final email = TextEditingController(), password = TextEditingController(), title = TextEditingController();
  final api = WorkspaceApi();
  final vault = SecureTokenVault();
  late final session = AccountSession(api, vault);
  String? token;
  Map<String, dynamic>? profile;
  AccountStore? store;
  WorkspaceWorker? worker;
  int _uiDepth=0;
  bool _expiring=false;
  List<Map<String, Object?>> items = [];
  String message = 'Открываем аккаунт…';
  bool busy = true;
  int pending = 0;
  List<Map<String, Object?>> labelCatalog = [];
  int navigation=0, projectFilter=-1;
  String searchQuery='', statusFilter='', labelFilter='';
  bool queuedOnly=false;
  List<Map<String,Object?>> projectCatalog=[];
  final search=TextEditingController();
  bool get canWrite => profile?['access'] == 'write'&&worker?.requiresLogin!=true&&worker?.closing!=true;

  @override
  void initState() { super.initState();WidgetsBinding.instance.addObserver(this);restore(); }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state){
    if(state==AppLifecycleState.resumed)worker?.setForeground(true);
    if(state==AppLifecycleState.paused||state==AppLifecycleState.hidden||state==AppLifecycleState.detached)worker?.setForeground(false);
  }

  Future<void> openStore() async {
    if (worker != null) return;
    final id = profile!['id'] as int;
    if (id <= 0) throw StateError('Некорректный аккаунт');
    final directory = await getApplicationSupportDirectory();
    if (Platform.isLinux || Platform.isWindows) ffi.sqfliteFfiInit();
    store ??= await AccountStore.open(Platform.isAndroid ? native.databaseFactory : ffi.databaseFactoryFfi,
        p.join(directory.path, 'production-account-$id-v1.sqlite3'));
    await AttachmentFiles(store!).cleanOrphans();
    final accountToken=token!;
    worker=WorkspaceWorker(store:store!,api:api,token:accountToken,profile:profile!,
      saveProfile:(value)=>vault.remember(accountToken,value));
    final lifecycle=WidgetsBinding.instance.lifecycleState;
    worker!.foreground=lifecycle!=AppLifecycleState.paused&&lifecycle!=AppLifecycleState.hidden&&lifecycle!=AppLifecycleState.detached;
    worker!.addListener(workerChanged);
    await reload();
  }

  void workerChanged(){
    final current=worker;if(!mounted||current==null)return;
    items=current.tasks;projectCatalog=current.projects;labelCatalog=current.labels;pending=current.pending;
    profile=current.profile;message=current.message;
    setState((){});
    if(current.requiresLogin&&_uiDepth==0&&!busy&&!_expiring)unawaited(expireAccount());
  }
  Future<void> reload() async {
    if(worker==null)return;
    await worker!.refreshLocal();
  }
  Future<void> expireAccount() async {
    if(_expiring||worker?.requiresLogin!=true)return;
    _expiring=true;if(mounted)setState(()=>busy=true);
    final current=worker;current?.removeListener(workerChanged);
    try{
      try{await current?.close();}catch(_){}
      if(worker!=current)return;
      try{await vault.delete();}catch(_){}worker=null;store=null;token=null;profile=null;
      items=[];projectCatalog=[];labelCatalog=[];pending=0;navigation=0;projectFilter=-1;statusFilter=labelFilter=searchQuery='';queuedOnly=false;search.clear();
      message='Сессия истекла. Войди снова — локальная очередь сохранена.';
    }finally{_expiring=false;if(mounted)setState(()=>busy=false);}
  }

  Future<void> restore() async {
    try {
      token = await vault.read();
      if (token == null) { message = 'Войди в аккаунт сайта совдело.рф.'; return; }
      profile = await vault.profile(token!);
      if (profile != null) {await openStore();if(mounted)setState((){});}
      await synchronize();
    } catch (e) { await handleError(e); }
    finally {
      if (mounted) { setState(() => busy = false);if(worker?.requiresLogin==true&&_uiDepth==0)unawaited(expireAccount()); }
      else { worker?.dispose(); }
    }
  }

  Future<void> handleError(Object error) async {
    if(error is ApiFailure&&error.status==401){
      if(worker!=null){worker!.requireLogin();return;}
      token=null;profile=null;try{await vault.delete();}catch(_){}
    }
    final errorMessage=error is ApiFailure?error.message:error is DraftConflict?error.message:
      error is ArgumentError?error.message.toString():'Не удалось выполнить действие. Очередь сохранена.';
    await reload();message=errorMessage;
  }

  Future<void> perform(Future<void> Function() operation) async {
    _uiDepth++;if(mounted)setState(()=>busy=true);
    try{await operation();}catch(error){await handleError(error);}
    finally{
      _uiDepth--;
      if(mounted){setState(()=>busy=_uiDepth>0);if(_uiDepth==0&&worker?.requiresLogin==true)await expireAccount();}
      else{worker?.dispose();}
    }
  }

  Future<void> synchronize({bool manual=false}) async {
    if(worker==null){
      final me=await api.me(token!);profile=me;await vault.remember(token!,me);await openStore();
    }
    worker!.request(manual:manual);
  }

  Future<void> signIn() async {
    if (email.text.trim().isEmpty || password.text.isEmpty) {
      setState(() => message = 'Введи email и пароль.'); return;
    }
    final entered = password.text; password.clear();
    await perform(() async {
      token = await session.login(email.text, entered);
      await synchronize();
    });
  }

  Future<void> signOut() => perform(() async {
    final current=worker;current?.removeListener(workerChanged);try{if(current!=null)await current.close();else await store?.db.close();}catch(_){}worker=null;store=null;
    final revoked = await session.logout(token!);
    token = null; profile = null; items = []; pending = 0; labelCatalog = []; projectCatalog=[]; navigation=0; projectFilter=-1; statusFilter=labelFilter=searchQuery=''; queuedOnly=false;search.clear();
    message = revoked ? 'Выход выполнен. Очередь сохранена для этого аккаунта.'
        : 'Выход выполнен локально. Отзови устройство в профиле сайта. Очередь сохранена.';
  });

  Future<void> editStatus(Map<String, Object?> task, String status) => perform(() async {
    if(!canWrite)throw const ApiFailure(401,'Войди снова для изменения задачи');
    await store!.setStatus(task['local_id'] as String, status,baseline:task);
    await reload();
    message = 'Статус сохранён на устройстве.';
    if(mounted)setState((){});
    await synchronize();
  });

  Future<void> resolve(Map<String, Object?> local) => perform(() async {
    if (local['server_id'] == null) {
      message = 'Не удалось создать задачу. Локальная запись сохранена; проверь доступность сайта.';
      return;
    }
    Map<String, dynamic> remote;
    try {
      remote = await api.task(token!, local['server_id'] as int);
    } on ApiFailure catch (error) {
      if (error.status != 404) rethrow;
      if (!mounted) return;
      final discard = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
        title: const Text('Задача больше недоступна'),
        content: const Text('Удалить ожидающие локальные изменения этой задачи? Остальные задачи останутся.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Сохранить изменения')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить локальные изменения')),
        ],
      ));
      if (discard == true) { await store!.discardMissing(local['local_id'] as String); await reload(); }
      return;
    }
    if (!mounted) return;
    final accept = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Конфликт изменений'),
      content: SizedBox(width: 640, child: SingleChildScrollView(child: Text(
          'НА УСТРОЙСТВЕ\n${local['title']} · ${local['status']}\n'
          'Проект: ${local['project_id'] ?? 'без проекта'} · срок: ${local['due_date'] ?? 'нет'}\n'
          'Метки на устройстве: ${TaskLabels.read(local['labels_json']).join(', ')}\n'
          'Приоритет: ${local['priority']}\n${local['description'] ?? ''}\n'
          'Чек-лист:\n${Checklists.read(local['checklist_json']).map((i) => '${i['done'] == true ? '✓' : '○'} ${i['text']}').join('\n')}\n\n'
          'НА САЙТЕ\n${remote['title']} · ${remote['status']}\n'
          'Проект: ${remote['project_id'] ?? 'без проекта'} · срок: ${remote['due_date'] ?? 'нет'}\n'
          'Метки на сайте: ${(remote['labels'] as List? ?? []).map((l) => l['name']).join(', ')}\n'
          'Приоритет: ${remote['priority']}\n${remote['description'] ?? ''}\n'
          'Чек-лист:\n${(remote['checklist'] as List? ?? []).map((i) => '${i['done'] == true ? '✓' : '○'} ${i['text']}').join('\n')}\n\n'
          'Принять все поля версии сайта и удалить ожидающие правки полей этой задачи? Комментарии и вложения сохранятся.'))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Оставить конфликт')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Принять сайт')),
      ],
    ));
    if (accept == true) {
      await store!.acceptServer(local['local_id'] as String, remote);
      await reload(); message = 'Принята версия сайта.';
    }
  });

  Future<void> editTask(Map<String, Object?> task) => perform(() async {
    final projects = await store!.projects();
    final labels = await store!.labels();
    if (!mounted) return;
    final mobile=MediaQuery.sizeOf(context).width<720;
    final fields = mobile
      ? await Navigator.of(context).push<Map<String,Object?>>(MaterialPageRoute<Map<String,Object?>>(builder:(_)=>TaskEditor(task:task,projects:projects,labels:labels,fullScreen:true,onSave:(fields)=>store!.edit(task['local_id'] as String,fields,baseline:task))))
      : await showDialog<Map<String,Object?>>(context:context,builder:(_)=>TaskEditor(task:task,projects:projects,labels:labels,onSave:(fields)=>store!.edit(task['local_id'] as String,fields,baseline:task)));
    if (fields == null||fields.isEmpty) return;
    await reload();
    message = 'Правки сохранены на устройстве.';
    if(mounted)setState((){});
    await synchronize();
  });


  Future<void> openLabels() => perform(() async {
    await showDialog<void>(context: context, barrierDismissible: false, builder: (_) => LabelsDialog(
      store: store!, canWrite: canWrite,changes:worker,syncMessage:()=>worker?.message??message,
      synchronize: () async { await synchronize(); },
    ));
    await reload();
  });


  Future<void> openAttachments(Map<String,Object?> task) => perform(() async {
    final mobile=MediaQuery.sizeOf(context).width<720;
    Widget page()=>AttachmentsDialog(store:store!,api:api,token:token!,localId:task['local_id'] as String,
      taskTitle:task['title'] as String,canWrite:canWrite,fullScreen:mobile,changes:worker,syncMessage:()=>worker?.message??message,
      scheduleRefresh:()=>worker?.files(task['local_id'] as String),
      synchronize:() async {await synchronize();});
    if(mobile) {await Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>page()));}
    else {await showDialog<void>(context:context,barrierDismissible:false,builder:(_)=>page());}
    await reload();
  });

  Future<void> openComments(Map<String,Object?> task) => perform(() async {
    final mobile=MediaQuery.sizeOf(context).width<720;
    Widget page()=>CommentsDialog(store:store!,api:api,token:token!,localId:task['local_id'] as String,
      taskTitle:task['title'] as String,author:(profile?['name']??profile?['email']??'Я').toString(),
      canWrite:canWrite,fullScreen:mobile,changes:worker,syncMessage:()=>worker?.message??message,
      scheduleRefresh:()=>worker?.comments(task['local_id'] as String),
      synchronize:() async {await synchronize();});
    if(mobile) {await Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>page()));}
    else {await showDialog<void>(context:context,barrierDismissible:false,builder:(_)=>page());}
    await reload();
  });

  Future<void> openTask(Map<String,Object?> task) => perform(() async {
    final mobile=MediaQuery.sizeOf(context).width<720;
    Future<Map<String,Object?>?> action(String kind,Map<String,Object?> current,Object? value) async {
      switch(kind) {
        case 'edit': await editTask(current); break;
        case 'status': await editStatus(current,value as String); break;
        case 'comments': await openComments(current); break;
        case 'files': await openAttachments(current); break;
        case 'resolve': await resolve(current); break;
        case 'checklist': await perform(() async {
          await store!.edit(current['local_id'] as String,{'checklist':value},baseline:current);await reload();await synchronize();
        }); break;
      }
      return store==null?null:await store!.task(current['local_id'] as String);
    }
    Widget page()=>TaskDetailView(initial:task,projects:projectCatalog,labels:labelCatalog,fullScreen:mobile,
      canWrite:canWrite,action:action,message:()=>message,changes:worker,readTask:()=>store?.task(task['local_id'] as String)??Future<Map<String,Object?>?>.value(),readProjects:()=>store!.projects(),readLabels:()=>store!.labels());
    if(mobile) {await Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>page()));}
    else {await showDialog<void>(context:context,barrierDismissible:false,builder:(_)=>page());}
    await reload();
  });

  Future<void> addTask() => perform(() async {
    title.clear();
    int? selectedProject=projectFilter>0&&projectCatalog.any((p)=>p['id']==projectFilter)?projectFilter:null;
    final value=await showDialog<String>(context:context,builder:(dialogContext)=>StatefulBuilder(builder:(dialogContext,setDialog)=>AlertDialog(
      title:const Text('Новая задача'),content:SizedBox(width:480,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        TextField(controller:title,autofocus:true,maxLength:240,textInputAction:TextInputAction.done,
          decoration:const InputDecoration(hintText:'Что нужно сделать?'),
          onSubmitted:(value){if(value.trim().isNotEmpty)Navigator.pop(dialogContext,value.trim());}),
        DropdownButton<int>(value:selectedProject??0,isExpanded:true,items:[
          const DropdownMenuItem(value:0,child:Text('Без проекта')),
          for(final p in projectCatalog)DropdownMenuItem(value:p['id'] as int,child:Text(p['name'] as String,maxLines:1,overflow:TextOverflow.ellipsis)),
        ],onChanged:(id)=>setDialog(()=>selectedProject=id==0?null:id)),
      ]))),
      actions:[TextButton(onPressed:()=>Navigator.pop(dialogContext),child:const Text('Отмена')),
        FilledButton(onPressed:(){if(title.text.trim().isNotEmpty)Navigator.pop(dialogContext,title.text.trim());},child:const Text('Добавить'))],
    )));
    if(value==null)return;
    await store!.add(value,projectId:selectedProject);
    search.clear();searchQuery=statusFilter=labelFilter='';queuedOnly=false;projectFilter=selectedProject??0;
    await reload();message='Задача сохранена на устройстве.';if(mounted)setState((){});await synchronize();
  });

  @override
  void dispose() {
    email.dispose(); password.dispose(); title.dispose(); search.dispose();
    WidgetsBinding.instance.removeObserver(this);worker?.removeListener(workerChanged);if(worker!=null){worker!.dispose();}else{final database=store?.db;if(database!=null)unawaited(database.close().catchError((Object _){}));}
    super.dispose();
  }

  Widget syncStatus()=>Padding(padding:const EdgeInsets.symmetric(horizontal:20,vertical:10),child:Row(children:[
    if(worker?.running==true)const SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2))
    else Icon(pending>0?Icons.cloud_upload_outlined:Icons.cloud_done_outlined,size:18),
    const SizedBox(width:10),Expanded(child:Tooltip(message:message,child:Text(worker?.running==true?'Синхронизация в фоне · можно продолжать работу':message,maxLines:2,overflow:TextOverflow.ellipsis,style:Theme.of(context).textTheme.bodySmall))),
    if(pending>0)Padding(padding:const EdgeInsets.only(left:8),child:Text('$pending в очереди',style:Theme.of(context).textTheme.labelSmall)),
  ]));

  Widget loginView()=>Center(child:SingleChildScrollView(padding:const EdgeInsets.all(24),child:ConstrainedBox(
    constraints:const BoxConstraints(maxWidth:420),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      const Icon(Icons.check_circle_outline,size:64,color:Color(0xff56c89b)),const SizedBox(height:20),
      Text('Дела вместе',textAlign:TextAlign.center,style:Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height:8),const Text('Войди в аккаунт СовДела',textAlign:TextAlign.center),const SizedBox(height:32),
      TextField(controller:email,enabled:!busy,keyboardType:TextInputType.emailAddress,autocorrect:false,
        textInputAction:TextInputAction.next,decoration:const InputDecoration(labelText:'Email')),
      const SizedBox(height:16),TextField(controller:password,enabled:!busy,obscureText:true,autocorrect:false,enableSuggestions:false,
        onSubmitted:busy?null:(_)=>signIn(),decoration:const InputDecoration(labelText:'Пароль')),
      const SizedBox(height:20),FilledButton(onPressed:busy?null:signIn,child:const Padding(padding:EdgeInsets.all(12),child:Text('Войти'))),
      const SizedBox(height:16),Text(message,textAlign:TextAlign.center),
      TextButton(onPressed:busy?null:()=>Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>const DiagnosticsPage())),child:const Text('Диагностика устройства')),
    ]),
  )));

  Widget tasksView(){
    final visible=items.where((task)=>TaskPresentation.matches(task,query:searchQuery,status:statusFilter,
      project:projectFilter,label:labelFilter,queued:queuedOnly)).toList();
    final filters=<DropdownMenuItem<int>>[
      const DropdownMenuItem(value:-1,child:Text('Все проекты')),const DropdownMenuItem(value:0,child:Text('Без проекта')),
      for(final project in projectCatalog)DropdownMenuItem(value:project['id'] as int,child:Text(project['name'] as String,maxLines:1,overflow:TextOverflow.ellipsis)),
      if(projectFilter>0&&!projectCatalog.any((p)=>p['id']==projectFilter))DropdownMenuItem(value:projectFilter,child:const Text('Недоступный проект')),
    ];
    return CustomScrollView(slivers:[
      SliverToBoxAdapter(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Padding(padding:const EdgeInsets.fromLTRB(20,12,20,8),child:TextField(controller:search,
        decoration:InputDecoration(hintText:'Найти задачу',prefixIcon:const Icon(Icons.search),
          suffixIcon:searchQuery.isEmpty?null:IconButton(tooltip:'Очистить поиск',onPressed:(){search.clear();setState(()=>searchQuery='');},icon:const Icon(Icons.close))),
        onChanged:(value)=>setState(()=>searchQuery=value))),
      SingleChildScrollView(scrollDirection:Axis.horizontal,padding:const EdgeInsets.symmetric(horizontal:20),child:Row(children:[
        ChoiceChip(label:const Text('Все'),selected:statusFilter.isEmpty,onSelected:(_)=>setState(()=>statusFilter='')),
        for(final entry in TaskPresentation.statuses.entries)Padding(padding:const EdgeInsets.only(left:8),child:ChoiceChip(label:Text(entry.value),selected:statusFilter==entry.key,onSelected:(_)=>setState(()=>statusFilter=entry.key))),
        const SizedBox(width:8),FilterChip(label:const Text('В очереди'),selected:queuedOnly,onSelected:(value)=>setState(()=>queuedOnly=value)),
      ])),
      Padding(padding:const EdgeInsets.symmetric(horizontal:20,vertical:8),child:Wrap(spacing:16,runSpacing:6,children:[
        SizedBox(width:230,child:DropdownButton<int>(isExpanded:true,value:projectFilter,items:filters,onChanged:(value){if(value!=null)setState(()=>projectFilter=value);})),
        SizedBox(width:230,child:DropdownButton<String>(isExpanded:true,value:labelFilter,
          items:[const DropdownMenuItem(value:'',child:Text('Все метки')),
            for(final label in labelCatalog)DropdownMenuItem(value:label['local_id'] as String,child:Text(label['name'] as String,maxLines:1,overflow:TextOverflow.ellipsis)),
            if(labelFilter.isNotEmpty&&!labelCatalog.any((l)=>l['local_id']==labelFilter))DropdownMenuItem(value:labelFilter,child:const Text('Недоступная метка'))],
          onChanged:(value){if(value!=null)setState(()=>labelFilter=value);})),
      ])),
      Padding(padding:const EdgeInsets.symmetric(horizontal:20,vertical:4),child:Text('Задач: ${visible.length}',style:Theme.of(context).textTheme.labelMedium)),
      ])),
      if(visible.isEmpty)SliverFillRemaining(hasScrollBody:false,child:Center(child:Padding(padding:const EdgeInsets.all(24),child:Column(mainAxisSize:MainAxisSize.min,children:[
        const Icon(Icons.task_alt,size:48),const SizedBox(height:12),const Text('Здесь пока пусто'),
        const SizedBox(height:8),const Text('Добавь задачу или измени фильтры',textAlign:TextAlign.center),
        TextButton(onPressed:(){search.clear();setState((){searchQuery=statusFilter=labelFilter='';projectFilter=-1;queuedOnly=false;});},child:const Text('Сбросить фильтры')),
      ]))))
      else SliverPadding(padding:const EdgeInsets.fromLTRB(16,4,16,100),sliver:SliverList(delegate:SliverChildBuilderDelegate((context,index){
        final task=visible[index];final project=projectCatalog.where((p)=>p['id']==task['project_id']);
        return TaskTile(key:ValueKey(task['local_id']),task:task,labels:labelCatalog,projectName:project.isEmpty?null:project.first['name'] as String,
          onOpen:busy?null:()=>openTask(task),onToggle:busy||!canWrite||task['blocked']==1?null:()=>editStatus(task,task['status']=='done'?'todo':'done'));
      },childCount:visible.length))),
    ]);
  }

  Widget projectsView()=>ListView(padding:const EdgeInsets.all(20),children:[
    Text('Проекты',style:Theme.of(context).textTheme.headlineSmall),const SizedBox(height:16),
    if(projectCatalog.isEmpty)const Text('Проектов пока нет в локальной копии.'),
    for(final project in projectCatalog)Card(child:ListTile(leading:const Icon(Icons.folder_outlined),
      title:Text(project['name'] as String),subtitle:Text('Задач: ${items.where((task)=>task['project_id']==project['id']).length}'),
      trailing:const Icon(Icons.chevron_right),onTap:()=>setState((){navigation=0;projectFilter=project['id'] as int;statusFilter=labelFilter=searchQuery='';queuedOnly=false;search.clear();}))),
  ]);

  Widget settingsView()=>ListView(padding:const EdgeInsets.all(20),children:[
    Text('Настройки',style:Theme.of(context).textTheme.headlineSmall),const SizedBox(height:20),
    ListTile(leading:const Icon(Icons.account_circle_outlined),title:Text(profile?['name']?.toString()??'Аккаунт'),subtitle:Text(profile?['email']?.toString()??'')),
    ListTile(leading:const Icon(Icons.cloud_outlined),title:Text('Ожидает отправки: $pending'),subtitle:Text(message)),
    if(!canWrite)const Padding(padding:EdgeInsets.all(12),child:Text('Токен только на чтение. Для редактирования выйди и войди снова.')),
    ListTile(leading:const Icon(Icons.label_outline),title:const Text('Метки'),trailing:const Icon(Icons.chevron_right),onTap:busy?null:openLabels),
    ListTile(leading:const Icon(Icons.build_outlined),title:const Text('Диагностика и тестовые задачи'),subtitle:const Text('Проверка хранилища и уведомлений'),
      onTap:busy?null:()=>Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>const DiagnosticsPage()))),
    ListTile(leading:const Icon(Icons.logout),title:const Text('Выйти из аккаунта'),subtitle:const Text('Локальная очередь останется сохранённой'),onTap:busy?null:signOut),
  ]);

  @override
  Widget build(BuildContext context)=>PopScope(canPop:!busy,child:LayoutBuilder(builder:(context,constraints){
    final wide=constraints.maxWidth>=1000;
    final authenticated=token!=null&&store!=null&&worker!=null;
    Widget content=authenticated?(navigation==0?tasksView():navigation==1?projectsView():settingsView()):token==null?loginView():Center(
      child:Padding(padding:const EdgeInsets.all(24),child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:420),child:Column(
        mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          if(busy)const LinearProgressIndicator(),Text(message,textAlign:TextAlign.center),const SizedBox(height:16),
          FilledButton(onPressed:busy?null:()=>perform(()=>synchronize(manual:true)),child:const Text('Повторить подключение')),
          TextButton(onPressed:busy?null:signOut,child:const Text('Выйти из аккаунта')),
        ],
      ))),
    );
    if(authenticated)content=Column(children:[syncStatus(),Expanded(child:content)]);
    return Scaffold(
      appBar:AppBar(title:const Text('СовДело'),actions:[
        if(token!=null)IconButton(tooltip:'Синхронизировать',onPressed:busy?null:()=>perform(()=>synchronize(manual:true)),icon:const Icon(Icons.sync)),
      ]),
      body:Row(children:[
        if(authenticated&&wide)NavigationRail(extended:true,selectedIndex:navigation,onDestinationSelected:(value)=>setState(()=>navigation=value),
          destinations:const [NavigationRailDestination(icon:Icon(Icons.task_alt),label:Text('Задачи')),
            NavigationRailDestination(icon:Icon(Icons.folder_outlined),label:Text('Проекты')),
            NavigationRailDestination(icon:Icon(Icons.settings_outlined),label:Text('Настройки'))]),
        Expanded(child:content),
      ]),
      bottomNavigationBar:authenticated&&!wide?NavigationBar(selectedIndex:navigation,onDestinationSelected:(value)=>setState(()=>navigation=value),
        destinations:const [NavigationDestination(icon:Icon(Icons.task_alt),label:'Задачи'),NavigationDestination(icon:Icon(Icons.folder_outlined),label:'Проекты'),NavigationDestination(icon:Icon(Icons.settings_outlined),label:'Настройки')]):null,
      floatingActionButton:authenticated&&navigation==0&&canWrite?FloatingActionButton(tooltip:'Новая задача',onPressed:busy?null:addTask,child:const Icon(Icons.add)):null,
    );
  }));
}

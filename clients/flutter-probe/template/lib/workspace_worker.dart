import 'dart:async';
import 'package:flutter/foundation.dart';
import 'account_store.dart';
import 'account_sync.dart';
import 'comments_sync.dart';
import 'attachments_sync.dart';
import 'workspace_api.dart';
import 'file_transfers.dart';

/// One in-process network worker per open account. Durable intents remain in SQLite.
class WorkspaceWorker extends ChangeNotifier {
  final AccountStore store;
  final WorkspaceApi api;
  final String token;
  final Future<void> Function(Map<String,dynamic>) saveProfile;
  final AttachmentTransport? transport;
  final DateTime Function() clock;
  Map<String,dynamic> profile;
  List<Map<String,Object?>> tasks=[],projects=[],labels=[];
  int pending=0;
  bool running=false,requiresLogin=false,foreground=true;
  String message='Работаем с сохранёнными данными.';
  DateTime? lastSuccess,retryAt;
  int _failures=0;
  bool _closing=false,_disposed=false,_again=false,_refreshAgain=false;
  Future<void>? _flight,_refreshing,_close;
  Timer? _timer;
  final _comments=<String,int>{},_files=<String,int>{};
  WorkspaceWorker({required this.store,required this.api,required this.token,required this.profile,
    required this.saveProfile,this.transport,DateTime Function()? clock,Duration? tick=const Duration(seconds:30)})
      :clock=clock??DateTime.now {
    if(tick!=null)_timer=Timer.periodic(tick,(_)=>poll());
  }
  bool get closing=>_closing;
  void check(){if(_closing||requiresLogin||!foreground)throw const SyncInterrupted();}
  Future<void> get idle=>_flight??Future<void>.value();
  void _notify(){if(!_closing&&!_disposed)notifyListeners();}
  void requireLogin(){requiresLogin=true;_again=false;message='Сессия истекла. Закрой открытый редактор и войди снова. Очередь сохранена.';_notify();}

  Future<void> refreshLocal(){
    if(_closing)return Future<void>.value();
    _refreshAgain=true;
    if(_refreshing!=null)return _refreshing!;
    final complete=Completer<void>();_refreshing=complete.future;
    unawaited(()async{
      try {
        while(_refreshAgain&&!_closing){
          _refreshAgain=false;
          final newTasks=await store.tasks(),newProjects=await store.projects(),newLabels=await store.labels();
          final count=await store.pendingCount();
          if(_closing)break;
          tasks=newTasks;projects=newProjects;labels=newLabels;pending=count;_notify();
        }
        complete.complete();
      }catch(error,stack){complete.completeError(error,stack);}
      finally{_refreshing=null;}
    }());
    return complete.future;
  }

  void request({bool manual=false}){
    if(_closing||requiresLogin)return;
    if(!foreground&&!manual){_again=true;return;}
    if(retryAt!=null&&clock().isBefore(retryAt!)){
      // Explicit refresh may bypass a network backoff, but never server Retry-After.
      if(!manual||_rateLimited)return;
    }
    if(running){_again=true;return;}
    running=true;_again=false;message='Синхронизация в фоне. Можно продолжать работу.';_notify();
    _flight=Future<void>(()async{
      try{
        do{
          _again=false;
          final me=await api.me(token);
          if(_closing)throw const SyncInterrupted();
          if(me['id']!=profile['id'])throw const ApiFailure(401,'Аккаунт изменился');
          await saveProfile(me);profile=me;
          if(_closing)throw const SyncInterrupted();
          await AccountSync(api,store,transport:transport,cancelled:()=>_closing||requiresLogin||!foreground,progress:refreshLocal)
              .synchronize(token,write:profile['access']=='write');
          String? resourceNotice;
          final requestedComments=Map<String,int>.from(_comments),requestedFiles=Map<String,int>.from(_files);
          for(final id in requestedComments.keys){
            if(_closing)throw const SyncInterrupted();
            try{await CommentsSync.refresh(api,store,token,id,check:check);}on ApiFailure catch(e){if(e.status!=404)rethrow;resourceNotice='История задачи недоступна. Показана сохранённая копия.';}
            if(_comments[id]==requestedComments[id])_comments.remove(id);
          }
          for(final id in requestedFiles.keys){
            if(_closing)throw const SyncInterrupted();
            try{await AttachmentsSync.refresh(api,store,token,id,check:check);}on ApiFailure catch(e){if(e.status!=404)rethrow;resourceNotice='Список файлов недоступен. Показана сохранённая копия.';}
            if(_files[id]==requestedFiles[id])_files.remove(id);
          }
          await refreshLocal();lastSuccess=clock();retryAt=null;_failures=0;_rateLimited=false;
          message=resourceNotice??(pending==0?'Всё сохранено и синхронизировано.':'Сохранено на устройстве. Есть ожидающие изменения или конфликты.');
          _notify();
        }while(_again&&!_closing&&!requiresLogin&&foreground);
      }on SyncInterrupted{if(!_closing&&!requiresLogin)message='Синхронизация продолжится при возвращении в приложение.';}
      catch(error){
        if(!_closing){
          if(error is ApiFailure&&error.status==401){requireLogin();}
          else {
            _failures++;
            _rateLimited=error is ApiFailure&&error.status==429;
            final delay=_rateLimited?(error is ApiFailure?error.retryAfter??60:60).clamp(1,3600).toInt():(30*(1<<(_failures-1).clamp(0,4).toInt())).clamp(30,300).toInt();
            retryAt=clock().add(Duration(seconds:delay));
            message=error is ApiFailure?error.message:'Не удалось синхронизировать. Изменения остались на устройстве.';
            _notify();
          }
        }
      }finally{
        if(!_closing){try{await refreshLocal();}catch(_){message='Не удалось прочитать локальное хранилище.';}}
        running=false;_flight=null;_notify();
      }
    });
  }
  bool _rateLimited=false;
  void comments(String id){_comments[id]=(_comments[id]??0)+1;request(manual:true);}
  void files(String id){_files[id]=(_files[id]??0)+1;request(manual:true);}
  void poll(){
    if(!foreground||_closing||requiresLogin||running)return;
    if(pending>0||_comments.isNotEmpty||_files.isNotEmpty||_again||lastSuccess==null||clock().difference(lastSuccess!)>=const Duration(minutes:1))request();
  }
  void setForeground(bool active){final previous=foreground;foreground=active;if(active&&!previous)request();else if(active)poll();}

  Future<void> close(){
    if(_close!=null)return _close!;
    _closing=true;_again=false;_timer?.cancel();
    _close=finishClose();dispose();return _close!;
  }
  Future<void> finishClose() async {
    try{await idle;await _refreshing;}
    finally{await store.db.close();}
  }
  @override
  void dispose(){
    if(_disposed)return;
    _disposed=true;
    super.dispose();
    unawaited(close().catchError((Object _){}));
  }
}

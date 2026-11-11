<?php
namespace App\Http\Controllers;
use App\Models\{User,Task,TaskNotification};
use App\Services\{RecurringTasks,TaskReminders};
use Carbon\CarbonImmutable;
use Illuminate\Http\Request;
use Illuminate\Validation\ValidationException;
class TaskNotificationsController {
 public function settings(Request $r):array {$u=$r->user();return ['notifications_enabled'=>(bool)$u->notifications_enabled,'deadline_notifications'=>(bool)$u->deadline_notifications,'notification_time'=>$u->notification_time];}
 public function saveSettings(Request $r,RecurringTasks $lock){$d=$r->validate(['notifications_enabled'=>'required|boolean','deadline_notifications'=>'required|boolean','notification_time'=>'required|date_format:H:i']);return $lock->locked($r->user()->id,function()use($r,$d){$u=User::findOrFail($r->user()->id);$u->forceFill($d)->save();return $d;});}
 public function index(Request $r,TaskReminders $service){
  $d=$r->validate(['before'=>'nullable|integer|min:1']);$uid=$r->user()->id;$service->generate($uid);
  $q=TaskNotification::where('user_id',$uid);if(isset($d['before']))$q->where('id','<',$d['before']);$rows=$q->orderByDesc('id')->limit(31)->get();$more=$rows->count()>30;$items=$rows->take(30)->values();
  return ['items'=>$items,'has_more'=>$more,'unread'=>TaskNotification::where('user_id',$uid)->whereNull('read_at')->count()];
 }
 public function read(Request $r,int $notification){$n=TaskNotification::where('user_id',$r->user()->id)->findOrFail($notification);if(!$n->read_at){$n->read_at=now();$n->save();}return $n;}
 public function readAll(Request $r){$d=$r->validate(['through_id'=>'required|integer|min:1']);TaskNotification::where('user_id',$r->user()->id)->where('id','<=',$d['through_id'])->whereNull('read_at')->update(['read_at'=>now()]);return ['ok'=>true];}
 public function reminder(Request $r,int $task,TaskReminders $service){return $service->reminder($r->user()->id,$task);}
 public function saveReminder(Request $r,int $task,RecurringTasks $lock,TaskReminders $service){
  $d=$r->validate(['local'=>'present|nullable|date_format:Y-m-d\TH:i']);
  return $lock->locked($r->user()->id,function()use($r,$task,$d,$service){
   $t=Task::where('user_id',$r->user()->id)->activeBoard()->where('status','!=','done')->findOrFail($task);$at=null;
   if($d['local']!==null){$zone=User::findOrFail($r->user()->id)->timezone?:'Europe/Moscow';$at=CarbonImmutable::createFromFormat('!Y-m-d\TH:i',$d['local'],$zone);
    if(!$at||$at->format('Y-m-d\TH:i')!==$d['local']||$at->lte(CarbonImmutable::now())||$at->year>2100)throw ValidationException::withMessages(['local'=>'Выберите существующее время в будущем (до 2101 года).']);
    $at=$at->utc();
   }
   $t->remind_at=$at;$t->save();return $service->reminder($r->user()->id,$task);
  });
 }
}

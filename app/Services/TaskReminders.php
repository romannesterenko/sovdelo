<?php
namespace App\Services;
use App\Models\{User,Task,TaskNotification};
use Carbon\CarbonImmutable;
class TaskReminders {
 public function customKey(int $taskId,CarbonImmutable $date):string{return 'custom:'.$taskId.':'.$date->utc()->format('Y-m-d\TH:i:s\Z');}
 public function generate(int $userId):int {
  return app(RecurringTasks::class)->locked($userId,function()use($userId){
   $u=User::findOrFail($userId);if(!$u->notifications_enabled)return 0;
   $zone=$u->timezone?:'Europe/Moscow';$now=CarbonImmutable::now();$today=$now->setTimezone($zone)->toDateString();$count=0;
   Task::where('user_id',$userId)->activeBoard()->where('status','!=','done')
    ->where(function($q)use($u,$today,$now){$q->where('remind_at','<=',$now);if($u->deadline_notifications)$q->orWhere('due_date','<=',$today);})
    ->reorder()->chunkById(100,function($tasks)use($u,$zone,$now,&$count){$known=array_fill_keys(TaskNotification::where('user_id',$u->id)->whereIn('task_id',$tasks->pluck('id'))->pluck('event_key')->all(),true);foreach($tasks as $t){
     $events=[];
     if($t->remind_at&&$t->remind_at->lte($now))$events[]=['key'=>$this->customKey($t->id,$t->remind_at),'kind'=>'custom','at'=>$t->remind_at];
     if($u->deadline_notifications&&$t->due_date){$at=CarbonImmutable::parse($t->due_date.' '.$u->notification_time,$zone)->utc();if($at->lte($now))$events[]=['key'=>'deadline:'.$t->id.':'.$t->due_date,'kind'=>'deadline','at'=>$at];}
     foreach($events as $event){if(isset($known[$event['key']]))continue;$n=TaskNotification::firstOrCreate(['user_id'=>$u->id,'event_key'=>$event['key']],['task_id'=>$t->id,'kind'=>$event['kind'],'title'=>$t->title,'scheduled_at'=>$event['at']]);if($n->wasRecentlyCreated)$count++;}
    }});return $count;
  });
 }
 public function reminder(int $userId,int $taskId):array {
  $u=User::findOrFail($userId);$t=Task::where('user_id',$userId)->findOrFail($taskId);$at=$t->remind_at;
  return ['local'=>$at?$at->setTimezone($u->timezone?:'Europe/Moscow')->format('Y-m-d\TH:i'):null,'at'=>$at?->toIso8601String(),'sent'=>$at?TaskNotification::where('user_id',$userId)->where('event_key',$this->customKey($taskId,$at))->exists():false];
 }
}

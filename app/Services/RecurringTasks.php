<?php
namespace App\Services;
use App\Models\{User,Task,TaskSeries,Project,Label};
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\DB;
class RecurringTasks {
 public function locked(int $userId,callable $fn):mixed {return DB::transaction(function()use($userId,$fn){User::whereKey($userId)->lockForUpdate()->firstOrFail();return $fn();},3);}
 public function advance(string $date,string $frequency,int $anchor):string {
  $d=CarbonImmutable::parse($date,'UTC');
  if($frequency==='monthly'){$d=$d->startOfMonth()->addMonth();return $d->day(min($anchor,$d->daysInMonth))->toDateString();}
  return $d->addDays($frequency==='weekly'?7:1)->toDateString();
 }
 public function generate(int $userId):int {
  return $this->locked($userId,function()use($userId){
   $today=CarbonImmutable::now(User::findOrFail($userId)->timezone?:'Europe/Moscow')->toDateString();$count=0;
   foreach(TaskSeries::where('user_id',$userId)->where('active',true)->where('next_date','<=',$today)->get() as $s){
    // Archived projects pause generation and leave their schedule intact.
    if($s->project_id&&!Project::whereKey($s->project_id)->where('user_id',$userId)->whereNull('archived_at')->exists())continue;
    $date=$s->next_date;$next=$this->advance($date,$s->frequency,$s->anchor_day);
    while($next<=$today){$date=$next;$next=$this->advance($date,$s->frequency,$s->anchor_day);}
    if(!Task::withTrashed()->where('task_series_id',$s->id)->where('occurrence_date',$date)->exists()){
     $task=new Task(['user_id'=>$userId,'project_id'=>$s->project_id,'title'=>$s->title,'description'=>$s->description,'priority'=>$s->priority,'status'=>'todo','planned_date'=>$date,'checklist'=>array_map(fn($i)=>['text'=>$i['text'],'done'=>false],$s->checklist)]);
     $task->task_series_id=$s->id;$task->occurrence_date=$date;$task->sort_order=((int)Task::where('user_id',$userId)->where('board_column','todo')->max('sort_order'))+1024;$task->save();
     $task->labels()->sync(Label::where('user_id',$userId)->whereIn('id',$s->label_ids)->pluck('id'));$count++;
    }
    $s->next_date=$next;$s->save();
   }return $count;
  });
 }
}

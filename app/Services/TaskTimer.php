<?php
namespace App\Services;
use App\Models\{User,Task,TimeSession};
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;
class TaskTimer
{
 private function locked(int $userId,callable $fn):mixed{return DB::transaction(function()use($userId,$fn){User::whereKey($userId)->lockForUpdate()->firstOrFail();return $fn();},3);}
 private function elapsed(TimeSession $s):int{return max(0,(int)$s->started_at->diffInSeconds(now(),false));}
 private function close(TimeSession $s,string $reason):void {$s->duration_seconds=$this->elapsed($s);$s->ended_at=now();$s->end_reason=$reason;$s->save();}
 // Caller must hold the account lock; task mutation services already do so.
 public function closeTask(int $userId,int $taskId,string $reason):void {foreach(TimeSession::where('user_id',$userId)->where('task_id',$taskId)->whereNull('ended_at')->get() as $s)$this->close($s,$reason);}
 private function state(int $userId):array {
  $active=TimeSession::where('user_id',$userId)->whereNull('ended_at')->with('task')->first();
  $paused=null;if(!$active){$last=TimeSession::where('user_id',$userId)->latest('id')->with('task')->first();if($last&&$last->end_reason==='pause'&&$last->task&&Task::whereKey($last->task_id)->activeBoard()->where('status','!=','done')->exists())$paused=$last;}
  $row=$active??$paused;$data=null;
  if($row){$seconds=$active?$this->elapsed($row):0;$total=(int)TimeSession::where('user_id',$userId)->where('task_id',$row->task_id)->whereNotNull('ended_at')->sum('duration_seconds');$data=['id'=>$row->id,'task_id'=>$row->task_id,'title'=>$row->task?->title??'Задача','started_at'=>$row->started_at->toIso8601String(),'elapsed_seconds'=>$seconds,'task_seconds'=>$total+$seconds];}
  return ['active'=>$active?$data:null,'paused'=>$paused?$data:null,'server_now'=>now()->toIso8601String()];
 }
 public function snapshot(int $userId):array{return $this->locked($userId,fn()=>$this->state($userId));}
 public function start(int $userId,int $taskId,string $key):array {
  return $this->locked($userId,function()use($userId,$taskId,$key){
   $existing=DB::table('timer_start_requests')->where('user_id',$userId)->where('request_key',$key)->first();
   if($existing){abort_unless((int)$existing->task_id===$taskId,422);return $this->state($userId);}
   $t=Task::where('user_id',$userId)->activeBoard()->where('status','!=','done')->findOrFail($taskId);
   $active=TimeSession::where('user_id',$userId)->whereNull('ended_at')->first();
   DB::table('timer_start_requests')->insert(['user_id'=>$userId,'task_id'=>$taskId,'request_key'=>$key,'created_at'=>now(),'updated_at'=>now()]);
   if($active&&$active->task_id===$taskId)return $this->state($userId);
   if($active)$this->close($active,'switch');
   TimeSession::create(['user_id'=>$userId,'task_id'=>$taskId,'request_key'=>$key,'started_at'=>now()]);
   if($t->status==='todo'){$t->sort_order=((int)Task::where('user_id',$userId)->where('board_column','doing')->max('sort_order'))+1024;$t->status='doing';$t->board_column='doing';$t->save();}
   return $this->state($userId);
  });
 }
 public function stop(int $userId,int $sessionId,string $reason):array {
  return $this->locked($userId,function()use($userId,$sessionId,$reason){$s=TimeSession::where('user_id',$userId)->findOrFail($sessionId);if(!$s->ended_at)$this->close($s,$reason);elseif($reason==='stop'&&$s->end_reason==='pause'){$s->end_reason='stop';$s->save();}return $this->state($userId);});
 }
 public function history(int $userId,int $taskId):array {
  return $this->locked($userId,function()use($userId,$taskId){Task::where('user_id',$userId)->findOrFail($taskId);$active=TimeSession::where('user_id',$userId)->where('task_id',$taskId)->whereNull('ended_at')->first();return ['sessions'=>TimeSession::where('user_id',$userId)->where('task_id',$taskId)->latest('id')->limit(30)->get(),'total_seconds'=>(int)TimeSession::where('user_id',$userId)->where('task_id',$taskId)->whereNotNull('ended_at')->sum('duration_seconds')+($active?$this->elapsed($active):0),'adjustments'=>DB::table('time_adjustments')->where('user_id',$userId)->whereIn('time_session_id',TimeSession::where('user_id',$userId)->where('task_id',$taskId)->select('id'))->latest('id')->limit(30)->get()];});
 }
 public function adjust(int $userId,int $sessionId,int $seconds,string $reason):array {
  return $this->locked($userId,function()use($userId,$sessionId,$seconds,$reason){$s=TimeSession::where('user_id',$userId)->findOrFail($sessionId);if(!$s->ended_at)throw ValidationException::withMessages(['seconds'=>'Сначала приостановите таймер.']);Task::where('user_id',$userId)->findOrFail($s->task_id);DB::table('time_adjustments')->insert(['time_session_id'=>$s->id,'user_id'=>$userId,'previous_seconds'=>$s->duration_seconds,'new_seconds'=>$seconds,'reason'=>$reason,'created_at'=>now(),'updated_at'=>now()]);$s->duration_seconds=$seconds;$s->save();return $this->state($userId);});
 }
}

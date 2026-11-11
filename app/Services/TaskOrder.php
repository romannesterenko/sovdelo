<?php
namespace App\Services;
use App\Models\{Task,User,Project};
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;
class TaskOrder
{
 private function locked(int $userId, callable $action): mixed {
  return DB::transaction(function()use($userId,$action){User::whereKey($userId)->lockForUpdate()->firstOrFail();return $action();},3);
 }
 private function owned(int $userId,int $id):Task {return Task::where('user_id',$userId)->findOrFail($id);}
 private function tail(int $userId,string $status):int {
  return ((int)Task::where('user_id',$userId)->where('status',$status)->max('sort_order'))+1024;
 }
 private function checkProject(int $userId,?int $project):void {if($project!==null&&!Project::whereKey($project)->where('user_id',$userId)->whereNull('archived_at')->exists())throw ValidationException::withMessages(['project_id'=>'Проект недоступен или находится в архиве.']);}
 public function create(int $userId,array $data):Task {
  return $this->locked($userId,function()use($userId,$data){$this->checkProject($userId,$data['project_id']??null);$t=new Task($data+['user_id'=>$userId,'checklist'=>[]]);$t->status='todo';$t->sort_order=$this->tail($userId,'todo');$t->save();return $t->fresh();});
 }
 public function update(int $userId,int $id,array $data):Task {
  return $this->locked($userId,function()use($userId,$id,$data){$t=$this->owned($userId,$id);$project=$t->project_id;$status=$t->status;$t->fill($data);$this->checkProject($userId,$t->project_id);
   if($project!==$t->project_id||$status!==$t->status)$t->sort_order=$this->tail($userId,$t->status);
   if($t->status==='done')app(TaskTimer::class)->closeTask($userId,$id,'completed');$t->save();return $t->fresh();});
 }
 public function delete(int $userId,int $id):void {$this->locked($userId,function()use($userId,$id){$t=$this->owned($userId,$id);app(TaskTimer::class)->closeTask($userId,$id,'trash');$t->delete();});}
 public function move(int $userId,int $id,string $status,?int $before):array {
  return $this->locked($userId,function()use($userId,$id,$status,$before){
   $t=$this->owned($userId,$id);abort_unless(Task::whereKey($id)->activeBoard()->exists(),422,'Восстановите задачу и проект из архива перед переносом.');
   $rows=Task::where('user_id',$userId)->activeBoard()->where('status',$status)->where('id','!=',$id)->orderBy('sort_order')->orderBy('id')->get();
   $ids=$rows->pluck('id')->all();
   if($before!==null){$index=array_search($before,$ids,true);if($index===false)throw ValidationException::withMessages(['before_id'=>'Место вставки изменилось или недоступно. Обновите доску.']);}
   else $index=count($ids);
   array_splice($ids,$index,0,[$id]);if($status==='done')app(TaskTimer::class)->closeTask($userId,$id,'completed');
   // One order per user/status; project filters preserve the relative order of hidden tasks.
   foreach($ids as $position=>$taskId){$values=['sort_order'=>($position+1)*1024];if($taskId===$id)$values['status']=$status;Task::where('user_id',$userId)->whereKey($taskId)->update($values);}
   return Task::where('user_id',$userId)->activeBoard()->orderBy('sort_order')->orderBy('id')->get()->all();
  });
 }
}

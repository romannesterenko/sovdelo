<?php
namespace App\Services;
use App\Models\{Task,User};
use Illuminate\Support\Facades\{DB,Storage};
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
 public function create(int $userId,array $data):Task {
  return $this->locked($userId,function()use($userId,$data){$t=new Task($data+['user_id'=>$userId,'checklist'=>[]]);$t->status='todo';$t->sort_order=$this->tail($userId,'todo');$t->save();return $t->fresh();});
 }
 public function update(int $userId,int $id,array $data):Task {
  return $this->locked($userId,function()use($userId,$id,$data){$t=$this->owned($userId,$id);$project=$t->project_id;$status=$t->status;$t->fill($data);
   if($project!==$t->project_id||$status!==$t->status)$t->sort_order=$this->tail($userId,$t->status);
   $t->save();return $t->fresh();});
 }
 public function delete(int $userId,int $id):void {$this->locked($userId,function()use($userId,$id){$t=$this->owned($userId,$id);$paths=$t->attachments()->pluck('path')->all();$t->delete();DB::afterCommit(fn()=>Storage::disk('local')->delete($paths));});}
 public function move(int $userId,int $id,string $status,?int $before):array {
  return $this->locked($userId,function()use($userId,$id,$status,$before){
   $t=$this->owned($userId,$id);
   $rows=Task::where('user_id',$userId)->where('status',$status)->where('id','!=',$id)->orderBy('sort_order')->orderBy('id')->get();
   $ids=$rows->pluck('id')->all();
   if($before!==null){$index=array_search($before,$ids,true);if($index===false)throw ValidationException::withMessages(['before_id'=>'Место вставки изменилось или недоступно. Обновите доску.']);}
   else $index=count($ids);
   array_splice($ids,$index,0,[$id]);
   // One order per user/status; project filters preserve the relative order of hidden tasks.
   foreach($ids as $position=>$taskId){$values=['sort_order'=>($position+1)*1024];if($taskId===$id)$values['status']=$status;Task::where('user_id',$userId)->whereKey($taskId)->update($values);}
   return Task::where('user_id',$userId)->orderBy('sort_order')->orderBy('id')->get()->all();
  });
 }
}

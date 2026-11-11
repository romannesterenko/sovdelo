<?php
namespace App\Http\Controllers;
use App\Models\{User,Task,Project};
use Illuminate\Http\Request;
use App\Services\TaskTimer;
use Illuminate\Support\Facades\DB;
class TaskLifecycleController
{
 private function locked(Request $r,callable $fn){return DB::transaction(function()use($r,$fn){User::whereKey($r->user()->id)->lockForUpdate()->firstOrFail();return $fn();},3);}
 public function index(Request $r){
  $uid=$r->user()->id;
  return ['archived_tasks'=>Task::where('user_id',$uid)->where(fn($q)=>$q->whereNotNull('tasks.archived_at')->orWhereHas('project',fn($p)=>$p->whereNotNull('archived_at')))->with('project:id,name,archived_at')->orderByDesc('tasks.updated_at')->get(),
   'trashed_tasks'=>Task::onlyTrashed()->where('user_id',$uid)->with('project:id,name,archived_at')->orderByDesc('deleted_at')->get(),
   'archived_projects'=>Project::where('user_id',$uid)->whereNotNull('archived_at')->orderBy('name')->get()];
 }
 public function archive(Request $r,int $task){return $this->locked($r,function()use($r,$task){$t=Task::where('user_id',$r->user()->id)->findOrFail($task);app(TaskTimer::class)->closeTask($r->user()->id,$task,'archive');$t->archived_at=now();$t->save();return $t->fresh();});}
 public function restore(Request $r,int $task){return $this->locked($r,function()use($r,$task){$t=Task::withTrashed()->where('user_id',$r->user()->id)->findOrFail($task);$t->deleted_at=null;$t->archived_at=null;$t->sort_order=((int)Task::where('user_id',$r->user()->id)->where('status',$t->status)->max('sort_order'))+1024;$t->save();return $t->fresh();});}
 public function archiveProject(Request $r,int $project){return $this->locked($r,function()use($r,$project){$p=Project::where('user_id',$r->user()->id)->findOrFail($project);foreach(Task::where('user_id',$r->user()->id)->where('project_id',$project)->pluck('id') as $id)app(TaskTimer::class)->closeTask($r->user()->id,$id,'archive');$p->archived_at=now();$p->save();return $p;});}
 public function restoreProject(Request $r,int $project){return $this->locked($r,function()use($r,$project){$p=Project::where('user_id',$r->user()->id)->findOrFail($project);$p->archived_at=null;$p->save();return $p;});}
}

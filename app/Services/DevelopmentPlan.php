<?php
namespace App\Services;
use App\Models\{Project,Task};
use Illuminate\Validation\ValidationException;

class DevelopmentPlan {
 public function document():array {return json_decode(file_get_contents(resource_path('plans/sovdelo-development.json')),true,64,JSON_THROW_ON_ERROR);}
 public function fingerprint():string{return hash_file('sha256',resource_path('plans/sovdelo-development.json'));}
 private function project(int $owner,array $d):?Project {
  $p=Project::where('user_id',$owner)->where('transfer_uuid',$d['project']['uuid'])->first();
  if($p)return $p;
  $candidates=Project::where('user_id',$owner)->whereRaw('LOWER(name) = ?', [mb_strtolower($d['project']['name'])])->get();
  if($candidates->count()>1)throw ValidationException::withMessages(['project'=>'Найдено несколько проектов СовДело. Переименуй лишние перед переносом.']);
  return $candidates->first();
 }
 private function match(int $owner,?Project $project,array $row):?Task {
  $t=Task::withTrashed()->where('user_id',$owner)->where('transfer_uuid',$row['uuid'])->first();
  if($t){abort_unless($project&&$t->project_id===$project->id,409);return $t;}
  if(!$project)return null;
  $q=Task::withTrashed()->where('user_id',$owner)->where('project_id',$project->id);
  $matches=isset($row['code'])?$q->where('title','like',$row['code'].' · %')->get():$q->where('title',$row['title'])->get();
  if($matches->count()>1)throw ValidationException::withMessages(['tasks'=>'Несколько задач с кодом '.$row['code'].'. Устрани дубли перед переносом.']);
  return $matches->first();
 }
 public function preview(int $owner):array {
  $d=$this->document();$p=$this->project($owner,$d);$items=[];$existing=0;
  foreach($d['tasks'] as $row){$t=$p?$this->match($owner,$p,$row):null;if($t)$existing++;
   $items[]=['title'=>$row['title'],'existing'=>$t!==null,'task_id'=>$t?->id,'state'=>$t?app(ProjectAgents::class)->effectiveState($t):$row['state']];}
  return ['fingerprint'=>$this->fingerprint(),'project_id'=>$p?->id,'project_name'=>$p?->name??$d['project']['name'],'total'=>count($items),'existing'=>$existing,'create'=>count($items)-$existing,'items'=>$items];
 }
 public function import(int $owner,string $fingerprint):array {
  return app(RecurringTasks::class)->locked($owner,function()use($owner,$fingerprint){
   abort_unless(hash_equals($this->fingerprint(),$fingerprint),409);
   $d=$this->document();$p=$this->project($owner,$d);abort_if($p?->archived_at!==null,422,'Сначала восстанови проект СовДело из архива.');
   if(!$p){$p=new Project(['user_id'=>$owner,'name'=>$d['project']['name']]);$p->transfer_uuid=$d['project']['uuid'];$p->save();}
   $created=0;$existing=0;$service=app(ProjectAgents::class);
   foreach($d['tasks'] as $row){
    $t=$this->match($owner,$p,$row);
    if($t){$existing++;$service->responsibility($t);continue;}
    $t=app(TaskOrder::class)->create($owner,['project_id'=>$p->id,'title'=>$row['title'],'description'=>$row['description'],'checklist'=>$row['checklist']]);
    $t->transfer_uuid=$row['uuid'];$t->save();$service->state($t,$row['state'],null,null);$created++;
   }
   if($created)$service->activity($owner,$p->id,null,null,'plan_imported',['created'=>$created,'existing'=>$existing,'fingerprint'=>$fingerprint]);
   return ['project_id'=>$p->id,'created'=>$created,'existing'=>$existing,'total'=>count($d['tasks'])];
  });
 }
}

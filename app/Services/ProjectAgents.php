<?php
namespace App\Services;
use App\Models\{User,Project,ProjectAgent,Task,TaskComment};
use Illuminate\Support\Facades\{DB,Hash};
use Illuminate\Validation\ValidationException;
use Laravel\Sanctum\PersonalAccessToken;

class ProjectAgents {
 public const STATES=['backlog','todo','doing','blocked','review','done'];
 public function password(User $user,string $password):void {
  if(!Hash::check($password,$user->password))throw ValidationException::withMessages(['current_password'=>'Текущий пароль неверен.']);
 }
 public function project(int $owner,int $id):Project{return Project::where('user_id',$owner)->whereNull('archived_at')->findOrFail($id);}
 public function task(int $owner,int $project,int $id):Task {
  $this->project($owner,$project);
  return Task::where('user_id',$owner)->where('project_id',$project)->whereNull('archived_at')->findOrFail($id);
 }
 public function activity(int $owner,int $project,?int $task,?ProjectAgent $agent,string $action,array $details=[]):void {
  DB::table('project_activity')->insert(['user_id'=>$owner,'project_id'=>$project,'task_id'=>$task,'agent_id'=>$agent?->id,
   'actor'=>$agent?'Помощник: '.$agent->name:'Владелец','action'=>$action,'details'=>json_encode($details,JSON_THROW_ON_ERROR),'created_at'=>now(),'updated_at'=>now()]);
 }
 public function issue(User $owner,int $project,string $name,string $password):array {
  return app(RecurringTasks::class)->locked($owner->id,function()use($owner,$project,$name,$password){
   $owner=User::findOrFail($owner->id);$this->password($owner,$password);$this->project($owner->id,$project);
   abort_if(ProjectAgent::where('user_id',$owner->id)->whereNull('revoked_at')->whereNotNull('token_id')->count()>=20,422);
   $expires=now()->addDays(30);$token=$owner->createToken('Помощник: '.$name,['agent:project'],$expires);
   $token->accessToken->auth_version=$owner->auth_version;$token->accessToken->save();
   $agent=ProjectAgent::create(['user_id'=>$owner->id,'project_id'=>$project,'token_id'=>$token->accessToken->id,'name'=>$name]);
   $this->activity($owner->id,$project,null,null,'agent_created',['name'=>$name,'agent_id'=>$agent->id]);
   return ['agent_id'=>$agent->id,'token'=>$token->plainTextToken,'expires_at'=>$expires->toIso8601String()];
  });
 }
 public function revoke(User $owner,int $id,string $password):void {
  app(RecurringTasks::class)->locked($owner->id,function()use($owner,$id,$password){
   $this->password(User::findOrFail($owner->id),$password);
   $agent=ProjectAgent::where('user_id',$owner->id)->findOrFail($id);
   if(!$agent->revoked_at){PersonalAccessToken::whereKey($agent->token_id)->delete();$agent->revoked_at=now();$agent->save();
    $this->activity($owner->id,$agent->project_id,null,null,'agent_revoked',['agent_id'=>$id,'name'=>$agent->name]);}
  });
 }
 public function effectiveState(Task $t):string {
  return match($t->board_column){'sd-backlog'=>'backlog','sd-blocked'=>'blocked','sd-review'=>'review',default=>$t->status};
 }
 public function responsibility(Task $t):object {
  DB::table('task_responsibilities')->insertOrIgnore(['task_id'=>$t->id,'state'=>$t->status,'created_at'=>now(),'updated_at'=>now()]);
  $row=DB::table('task_responsibilities')->where('task_id',$t->id)->first();$row->state=$this->effectiveState($t);return $row;
 }
 public function data(Task $t):array {
  $w=DB::table('task_responsibilities')->where('task_id',$t->id)->first();
  $agent=$w?->agent_id?ProjectAgent::find($w->agent_id):null;
  return ApiData::task($t)+['workflow'=>['state'=>$this->effectiveState($t),'report'=>$w?->report,'agent_id'=>$w?->agent_id,'agent_name'=>$agent?->name,'owner_id'=>$t->user_id]];
 }
 public function version(Task $t,int $version):void {abort_unless((int)$t->version===$version,409);}
 public function state(Task $t,string $state,?int $agentId,?string $report):Task {
  $kind=in_array($state,['doing','blocked','review'],true)?'doing':($state==='done'?'done':'todo');
  app(BoardColumns::class)->ensure($t->user_id);
  $key=match($state){'backlog'=>'sd-backlog','blocked'=>'sd-blocked','review'=>'sd-review',default=>$kind};
  if($key!==$kind){
   $names=['sd-backlog'=>'Бэклог','sd-blocked'=>'Заблокировано','sd-review'=>'Проверка'];
   $column=\App\Models\BoardColumn::firstOrCreate(['user_id'=>$t->user_id,'key'=>$key],['name'=>$names[$key],'kind'=>$kind,'sort_order'=>$state==='backlog'?-1024:($state==='review'?1800:1600)]);
   abort_unless($column->kind===$kind,409);
  }
  $this->responsibility($t);
  DB::table('task_responsibilities')->where('task_id',$t->id)->update(['state'=>$state,'agent_id'=>$agentId,'report'=>$report,'updated_at'=>now()]);
  if($kind==='done')app(TaskTimer::class)->closeTask($t->user_id,$t->id,'completed');
  if($t->board_column!==$key)$t->sort_order=((int)Task::where('user_id',$t->user_id)->where('board_column',$key)->max('sort_order'))+1024;
  $t->status=$kind;$t->board_column=$key;$t->save();
  return $t->fresh();
 }
 public function active(ProjectAgent $agent):void {
  $fresh=ProjectAgent::whereKey($agent->id)->whereNull('revoked_at')->first();
  $token=$fresh?PersonalAccessToken::find($fresh->token_id):null;
  abort_unless($token&&(!$token->expires_at||$token->expires_at->isFuture())&&(int)$token->auth_version===(int)User::findOrFail($agent->user_id)->auth_version,401);
 }
 public function agentWrite(ProjectAgent $agent,string $key,string $fingerprint,callable $fn):array {
  return app(RecurringTasks::class)->locked($agent->user_id,function()use($agent,$key,$fingerprint,$fn){
   $this->active($agent);$this->project($agent->user_id,$agent->project_id);
   $old=DB::table('agent_receipts')->where('agent_id',$agent->id)->where('request_key',$key)->first();
   if($old){abort_unless(hash_equals($old->fingerprint,$fingerprint),409);return json_decode($old->response,true,512,JSON_THROW_ON_ERROR);}
   $result=$fn();DB::table('agent_receipts')->insert(['agent_id'=>$agent->id,'request_key'=>$key,'fingerprint'=>$fingerprint,'response'=>json_encode($result,JSON_THROW_ON_ERROR),'created_at'=>now(),'updated_at'=>now()]);return $result;
  });
 }
 public function agentAction(ProjectAgent $agent,int $id,array $d):array {
  $t=$this->task($agent->user_id,$agent->project_id,$id);$this->version($t,$d['expected_version']);$w=$this->responsibility($t);
  abort_unless($w->agent_id===null||(int)$w->agent_id===$agent->id,403);
  $state=$w->state;$report=$w->report;
  switch($d['action']){
   case 'claim':abort_unless(in_array($state,['todo','doing'],true),422);$state='doing';break;
   case 'block':abort_unless((int)$w->agent_id===$agent->id&&$state==='doing',422);$state='blocked';break;
   case 'resume':abort_unless((int)$w->agent_id===$agent->id&&$state==='blocked',422);$state='doing';break;
   case 'submit':abort_unless((int)$w->agent_id===$agent->id&&$state==='doing',422);$state='review';$report=trim($d['report']??'');
    if($report==='')throw ValidationException::withMessages(['report'=>'Нужен отчёт: результат, проверки и ограничения.']);break;
   case 'comment':break;
  }
  $note=trim($d['note']??'');
  if(in_array($d['action'],['block','comment'],true)&&$note==='')throw ValidationException::withMessages(['note'=>'Напиши комментарий.']);
  if($d['action']!=='comment')$t=$this->state($t,$state,$agent->id,$report);
  else {$t->touch();$t=$t->fresh();}
  $text=$d['action']==='submit'?$report:$note;
  if($text)TaskComment::create(['user_id'=>$agent->user_id,'task_id'=>$id,'body'=>'[Помощник: '.$agent->name.' · '.$d['action'].'] '.$text]);
  $this->activity($agent->user_id,$agent->project_id,$id,$agent,$d['action'],['state'=>$state,'note'=>$note,'report'=>$d['action']==='submit'?$report:null]);
  return $this->data($t);
 }
}

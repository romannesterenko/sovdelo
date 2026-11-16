<?php
namespace App\Http\Controllers;
use App\Models\{Project,ProjectAgent,Task,User};
use App\Services\{ApiData,ProjectAgents,RecurringTasks,TaskOrder};
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;

class AgentWorkspaceController {
 public function __construct(private ProjectAgents $service){}
 private function agent(Request $r):ProjectAgent{return $r->attributes->get('project_agent');}
 public function context(Request $r){$a=$this->agent($r);return ApiData::response(['agent'=>['id'=>$a->id,'name'=>$a->name,'role'=>'executor'],
  'project'=>ApiData::project($this->service->project($a->user_id,$a->project_id)),'policy'=>['owner_accepts'=>true,'delete'=>false,'other_projects'=>false,'background_execution'=>false]]);}
 public function tasks(Request $r){
  $a=$this->agent($r);$d=$r->validate(['page'=>'sometimes|integer|min:1','per_page'=>'sometimes|integer|min:1|max:100','q'=>'sometimes|string|max:240']);
  $q=Task::where('user_id',$a->user_id)->where('project_id',$a->project_id)->whereNull('archived_at');
  if(isset($d['q']))$q->where('title','like','%'.$d['q'].'%');
  return ApiData::page($q->orderBy('id')->paginate($d['per_page']??50),fn($t)=>$this->service->data($t));
 }
 public function show(Request $r,int $task){$a=$this->agent($r);return ApiData::response($this->service->data($this->service->task($a->user_id,$a->project_id,$task)));}
 private function write(Request $r,callable $fn){
  $key=$r->header('Idempotency-Key');validator(['request_key'=>$key],['request_key'=>'required|uuid'])->validate();
  $payload=$r->all();ksort($payload);$fingerprint=hash('sha256',$r->method().' '.$r->path().' '.json_encode($payload,JSON_THROW_ON_ERROR));
  return ApiData::response($this->service->agentWrite($this->agent($r),$key,$fingerprint,$fn));
 }
 public function create(Request $r){
  $d=$r->validate(['title'=>'required|string|max:240','description'=>'nullable|string|max:20000','priority'=>['sometimes',Rule::in(['normal','high'])]]);
  return $this->write($r,function()use($r,$d){
   $a=$this->agent($r);$t=app(TaskOrder::class)->create($a->user_id,$d+['project_id'=>$a->project_id]);
   $t=$this->service->state($t,'backlog',null,null);
   $this->service->activity($a->user_id,$a->project_id,$t->id,$a,'created',['title'=>$t->title,'state'=>'backlog']);
   return $this->service->data($t);
  });
 }
 public function action(Request $r,int $task){
  $d=$r->validate(['action'=>['required',Rule::in(['claim','block','resume','submit','comment'])],
   'expected_version'=>'required|integer|min:1','note'=>'nullable|string|max:8000','report'=>'nullable|string|max:8000']);
  return $this->write($r,fn()=>$this->service->agentAction($this->agent($r),$task,$d));
 }
 public function activity(Request $r){$a=$this->agent($r);return ApiData::response($this->history($a->user_id,$a->project_id,$r));}
 private function history(int $owner,int $project,Request $r):array {
  $d=$r->validate(['before_id'=>'sometimes|integer|min:1']);$q=DB::table('project_activity')->where('user_id',$owner)->where('project_id',$project);
  if(isset($d['before_id']))$q->where('id','<',$d['before_id']);
  return $q->orderByDesc('id')->limit(100)->get()->map(function($row){$row->details=json_decode($row->details,true);return $row;})->all();
 }
 public function ownerIndex(Request $r){
  $projects=Project::where('user_id',$r->user()->id)->whereNull('archived_at')->orderBy('id')->get();
  $agents=ProjectAgent::where('user_id',$r->user()->id)->orderByDesc('id')->get()->map(function($a)use($r){
   $token=$a->token_id?\Laravel\Sanctum\PersonalAccessToken::find($a->token_id):null;
   return ['id'=>$a->id,'name'=>$a->name,'project_id'=>$a->project_id,'valid'=>!$a->revoked_at&&$token&&(!$token->expires_at||$token->expires_at->isFuture())&&(int)$token->auth_version===(int)$r->user()->auth_version,
    'expires_at'=>$token?->expires_at,'last_used_at'=>$token?->last_used_at];
  });return ['projects'=>$projects,'agents'=>$agents];
 }
 public function ownerProject(Request $r,int $project){
  $this->service->project($r->user()->id,$project);$d=$r->validate(['page'=>'sometimes|integer|min:1']);
  $page=Task::where('user_id',$r->user()->id)->where('project_id',$project)->whereNull('archived_at')->orderBy('id')->paginate(100);
  return ['tasks'=>$page->getCollection()->map(fn($t)=>$this->service->data($t)),'page'=>$page->currentPage(),'last_page'=>$page->lastPage(),'activity'=>$this->history($r->user()->id,$project,$r)];
 }
 public function ownerIssue(Request $r){$d=$r->validate(['project_id'=>'required|integer|min:1','name'=>'required|string|max:60','current_password'=>'required|string|max:128']);return response()->json($this->service->issue($r->user(),$d['project_id'],$d['name'],$d['current_password']),201)->header('Cache-Control','no-store');}
 public function ownerRevoke(Request $r,int $agent){$d=$r->validate(['current_password'=>'required|string|max:128']);$this->service->revoke($r->user(),$agent,$d['current_password']);return ['revoked'=>true];}
 public function ownerAction(Request $r,int $project,int $task){
  $d=$r->validate(['expected_version'=>'required|integer|min:1','action'=>['required',Rule::in(['assign','ready','accept','changes','backlog'])],'agent_id'=>'nullable|integer|min:1','note'=>'nullable|string|max:8000']);
  return app(RecurringTasks::class)->locked($r->user()->id,function()use($r,$project,$task,$d){
   $t=$this->service->task($r->user()->id,$project,$task);$this->service->version($t,$d['expected_version']);$w=$this->service->responsibility($t);
   if($d['action']==='assign'){
    $id=$d['agent_id']??null;if($id!==null){$agent=ProjectAgent::where('user_id',$r->user()->id)->where('project_id',$project)->findOrFail($id);$this->service->active($agent);}
    abort_if($w->state==='done',422);$t=$this->service->state($t,$w->state,$id,$w->report);
    $this->service->activity($r->user()->id,$project,$task,null,'assigned',['agent_id'=>$id]);
   }else{
    $state=match($d['action']){'accept'=>'done','backlog'=>'backlog',default=>'todo'};
    if($d['action']==='accept')abort_unless($w->state==='review',422);
    if($d['action']==='changes')abort_unless($w->state==='review',422);
    if($d['action']==='changes'&&trim($d['note']??'')==='')throw \Illuminate\Validation\ValidationException::withMessages(['note'=>'Опиши нужные доработки.']);
    $t=$this->service->state($t,$state,$w->agent_id,$w->report);
    $this->service->activity($r->user()->id,$project,$task,null,$d['action'],['state'=>$state,'note'=>$d['note']??null]);
    if(!empty($d['note']))\App\Models\TaskComment::create(['user_id'=>$r->user()->id,'task_id'=>$task,'body'=>'[Владелец · '.$d['action'].'] '.$d['note']]);
   }
   return ['task'=>$this->service->data($t)];
  });
 }
}

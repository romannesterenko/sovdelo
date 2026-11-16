<?php
namespace Tests\Feature;
use App\Models\{User,Project,ProjectAgent,Task};
use App\Services\{DevelopmentPlan,ProjectAgents};
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;
class ProjectAgentsTest extends TestCase {
 use RefreshDatabase;
 private function fixture():array {
  $owner=User::create(['name'=>'Владелец','email'=>'owner@example.com','password'=>'example-password-123']);
  $project=Project::create(['user_id'=>$owner->id,'name'=>'Рабочий проект']);
  $issued=app(ProjectAgents::class)->issue($owner,$project->id,'Исполнитель','example-password-123');
  $agent=ProjectAgent::findOrFail($issued['agent_id']);
  $task=Task::create(['user_id'=>$owner->id,'project_id'=>$project->id,'title'=>'Задача','status'=>'todo']);
  return [$owner,$project,$agent,$issued['token'],$task];
 }
 private function headers(string $token,?string $key=null):array {return ['Authorization'=>'Bearer '.$token,'Idempotency-Key'=>$key??(string)Str::uuid()];}
 public function test_agent_is_scoped_to_one_project_and_cannot_use_ordinary_api():void {
  [$owner,$project,$agent,$token,$task]=$this->fixture();
  $other=Project::create(['user_id'=>$owner->id,'name'=>'Другой']);$foreign=Task::create(['user_id'=>$owner->id,'project_id'=>$other->id,'title'=>'Не показывать']);
  $this->getJson('/api/v1/agent/context',$this->headers($token))->assertOk()->assertJsonPath('data.project.id',$project->id);
  $this->getJson('/api/v1/agent/tasks',$this->headers($token))->assertOk()->assertJsonCount(1,'data')->assertJsonPath('data.0.id',$task->id);
  $this->getJson('/api/v1/agent/tasks/'.$foreign->id,$this->headers($token))->assertNotFound();
  $this->getJson('/api/v1/tasks',$this->headers($token))->assertForbidden();
  $this->postJson('/api/v1/sync/operations',['kind'=>'create'],$this->headers($token))->assertForbidden();
  $this->getJson('/api/v1/auth/devices',$this->headers($token))->assertForbidden();
  $this->deleteJson('/api/v1/tasks/'.$task->id,[],$this->headers($token))->assertForbidden();
 }
 public function test_regular_device_is_not_an_agent():void {
  [$owner]=$this->fixture();$token=$owner->createToken('Обычный',['workspace:read','workspace:write']);$token->accessToken->auth_version=$owner->auth_version;$token->accessToken->save();
  $this->getJson('/api/v1/agent/context',$this->headers($token->plainTextToken))->assertUnauthorized();
 }
 public function test_claim_report_review_and_owner_acceptance():void {
  [$owner,$project,$agent,$token,$task]=$this->fixture();$url='/api/v1/agent/tasks/'.$task->id.'/actions';
  $data=$this->postJson($url,['action'=>'claim','expected_version'=>1],$this->headers($token))->assertOk()->assertJsonPath('data.workflow.state','doing')->json('data');
  $this->postJson($url,['action'=>'submit','expected_version'=>$data['version']],$this->headers($token))->assertUnprocessable();
  $key=(string)Str::uuid();$body=['action'=>'submit','expected_version'=>$data['version'],'report'=>'Результат: готово. Проверки: тесты. Ограничения: нет.'];
  $review=$this->postJson($url,$body,$this->headers($token,$key))->assertOk()->assertJsonPath('data.workflow.state','review')->json('data');
  $this->postJson($url,$body,$this->headers($token,$key))->assertOk()->assertJsonPath('data.version',$review['version']);
  $this->postJson($url,['action'=>'accept','expected_version'=>$review['version']],$this->headers($token))->assertUnprocessable();
  $this->assertDatabaseCount('task_comments',1);
  $this->actingAs($owner)->postJson('/project-control/projects/'.$project->id.'/tasks/'.$task->id,['action'=>'accept','expected_version'=>$review['version']])->assertOk()->assertJsonPath('task.workflow.state','done');
  $this->assertDatabaseHas('project_activity',['task_id'=>$task->id,'action'=>'accept','agent_id'=>null]);
 }
 public function test_stale_version_and_other_assignee_are_rejected():void {
  [$owner,$project,$agent,$token,$task]=$this->fixture();$task->title='Новая версия';$task->save();
  $this->postJson('/api/v1/agent/tasks/'.$task->id.'/actions',['action'=>'claim','expected_version'=>1],$this->headers($token))->assertConflict();
  $second=app(ProjectAgents::class)->issue($owner,$project->id,'Другой','example-password-123');
  app(ProjectAgents::class)->state($task,'todo',$second['agent_id'],null);
  $this->postJson('/api/v1/agent/tasks/'.$task->id.'/actions',['action'=>'claim','expected_version'=>$task->fresh()->version],$this->headers($token))->assertForbidden();
 }
 public function test_creation_is_idempotent_and_only_goes_to_backlog():void {
  [$owner,$project,$agent,$token]=$this->fixture();$key=(string)Str::uuid();$body=['title'=>'Предложение'];
  $first=$this->postJson('/api/v1/agent/tasks',$body,$this->headers($token,$key))->assertOk()->assertJsonPath('data.workflow.state','backlog')->json('data');
  $this->postJson('/api/v1/agent/tasks',$body,$this->headers($token,$key))->assertOk()->assertJsonPath('data.id',$first['id']);
  $this->postJson('/api/v1/agent/tasks',['title'=>'Другое'],$this->headers($token,$key))->assertConflict();
  $this->assertDatabaseCount('tasks',2);
  $this->postJson('/api/v1/agent/tasks/'.$first['id'].'/actions',['action'=>'claim','expected_version'=>$first['version']],$this->headers($token))->assertUnprocessable();
 }
 public function test_revocation_and_password_change_stop_access():void {
  [$owner,$project,$agent,$token]=$this->fixture();app(ProjectAgents::class)->revoke($owner,$agent->id,'example-password-123');
  $this->getJson('/api/v1/agent/context',$this->headers($token))->assertUnauthorized();
  $second=app(ProjectAgents::class)->issue($owner,$project->id,'Новый','example-password-123');$owner->auth_version++;$owner->save();
  $this->getJson('/api/v1/agent/context',$this->headers($second['token']))->assertUnauthorized();
 }
 public function test_plan_import_is_repeatable_and_preserves_existing_work():void {
  [$owner]=$this->fixture();$service=app(DevelopmentPlan::class);$preview=$service->preview($owner->id);
  $this->assertSame(47,$preview['create']);$first=$service->import($owner->id,$preview['fingerprint']);$this->assertSame(47,$first['created']);
  $task=Task::where('user_id',$owner->id)->where('project_id',$first['project_id'])->firstOrFail();$task->title='Мой изменённый заголовок';$task->status='doing';$task->board_column='doing';$task->save();
  $second=$service->import($owner->id,$preview['fingerprint']);$this->assertSame(0,$second['created']);$this->assertSame(47,$second['existing']);
  $this->assertSame('Мой изменённый заголовок',$task->fresh()->title);$this->assertSame('doing',$task->fresh()->status);
 }
 public function test_previous_json_import_uuid_is_adopted_including_archived_task():void {
  [$owner]=$this->fixture();$service=app(DevelopmentPlan::class);$document=$service->document();
  $p=new Project(['user_id'=>$owner->id,'name'=>'Переименован']);$p->transfer_uuid=$document['project']['uuid'];$p->save();
  $t=new Task(['user_id'=>$owner->id,'project_id'=>$p->id,'title'=>'Мой заголовок']);$t->transfer_uuid=$document['tasks'][0]['uuid'];$t->archived_at=now();$t->save();
  $preview=$service->preview($owner->id);$this->assertSame(1,$preview['existing']);$this->assertSame($p->id,$preview['project_id']);
  $result=$service->import($owner->id,$preview['fingerprint']);$this->assertSame(46,$result['created']);$this->assertNotNull($t->fresh()->archived_at);
 }
 public function test_owners_cannot_manage_other_owners_agents_or_projects():void {
  [$owner,$project,$agent,$token,$task]=$this->fixture();$other=User::create(['name'=>'Другой','email'=>'other@example.com','password'=>'other-password-123']);
  $this->actingAs($other)->getJson('/project-control/projects/'.$project->id)->assertNotFound();
  $this->postJson('/project-control/agents',['project_id'=>$project->id,'name'=>'Нельзя','current_password'=>'other-password-123'])->assertNotFound();
  $this->postJson('/project-control/agents/'.$agent->id.'/revoke',['current_password'=>'other-password-123'])->assertNotFound();
  $this->postJson('/project-control/projects/'.$project->id.'/tasks/'.$task->id,['action'=>'ready','expected_version'=>1])->assertNotFound();
 }
 public function test_owner_return_and_agent_block_resume_have_audit_and_versions():void {
  [$owner,$project,$agent,$token,$task]=$this->fixture();$url='/api/v1/agent/tasks/'.$task->id.'/actions';
  foreach([['claim',null],['block','Нужен доступ'],['resume',null],['submit',null]] as [$action,$note]){
   $body=['action'=>$action,'expected_version'=>$task->fresh()->version,'note'=>$note,'report'=>$action==='submit'?'Проверено':null];
   $this->postJson($url,$body,$this->headers($token))->assertOk();
  }
  $this->actingAs($owner)->postJson('/project-control/projects/'.$project->id.'/tasks/'.$task->id,['action'=>'changes','expected_version'=>$task->fresh()->version,'note'=>'Добавь проверку'])->assertOk()->assertJsonPath('task.workflow.state','todo');
  $this->assertDatabaseHas('project_activity',['task_id'=>$task->id,'action'=>'block']);$this->assertDatabaseHas('project_activity',['task_id'=>$task->id,'action'=>'changes']);
 }
 public function test_mcp_tools_share_project_permissions_and_receipts():void {
  [$owner,$project,$agent,$token,$task]=$this->fixture();
  $url='/api/v1/agent/mcp';
  $headers=$this->headers($token);
  $this->postJson($url,['jsonrpc'=>'2.0','id'=>1,'method'=>'initialize','params'=>['protocolVersion'=>'2025-06-18']],$headers)->assertOk()->assertJsonPath('result.serverInfo.name','sovdelo-project-agent');
  $this->postJson($url,['jsonrpc'=>'2.0','id'=>2,'method'=>'tools/list'],$headers)->assertOk()->assertJsonCount(6,'result.tools');
  $body=['jsonrpc'=>'2.0','id'=>3,'method'=>'tools/call','params'=>['name'=>'sovdelo_create','arguments'=>['title'=>'Через MCP','request_key'=>(string)\Illuminate\Support\Str::uuid()]]];
  $first=$this->postJson($url,$body,$headers)->assertOk()->json('result.content.0.text');
  $this->postJson($url,$body,$headers)->assertOk()->assertJsonPath('result.content.0.text',$first);
  $this->assertDatabaseCount('tasks',2);
  $this->postJson($url,['jsonrpc'=>'2.0','id'=>4,'method'=>'tools/call','params'=>['name'=>'sovdelo_action','arguments'=>['task_id'=>$task->id,'expected_version'=>1,'action'=>'accept','request_key'=>(string)\Illuminate\Support\Str::uuid()]]],$headers)->assertOk()->assertJsonPath('result.isError',true);
 }
}

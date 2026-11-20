<?php
namespace Tests\Feature;
use App\Models\{User,Project,ProjectCredential,ProjectAttachment,Task,TaskAttachment};
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\{DB,Storage};
use Tests\TestCase;
class ProjectDetailsTest extends TestCase {
 use RefreshDatabase;
 private const PNG='iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGOwWFz+HwAEuwJScO11XwAAAABJRU5ErkJggg==';
 private function fixture():array {Storage::fake('local');$u=User::create(['name'=>'Роман','email'=>'project@example.com','password'=>'password-for-tests'])->fresh();$p=Project::create(['user_id'=>$u->id,'name'=>'СовДело']);$this->actingAs($u);return [$u,$p];}
 private function version(Project $p,array $d=[]):array {return ['expected_version'=>$p->fresh()->version]+$d;}
 private function image():UploadedFile {return UploadedFile::fake()->createWithContent('cover.png',base64_decode(self::PNG));}
 private function access(Project $p,string $secret='server-secret'):ProjectCredential {$this->postJson('/projects/'.$p->id.'/credentials',$this->version($p,['name'=>'SSH','kind'=>'server','address'=>'127.0.0.1:22','username'=>'roman','secret'=>$secret,'notes'=>'Сервер проекта']))->assertNoContent();return ProjectCredential::where('project_id',$p->id)->latest('id')->firstOrFail();}
 public function test_project_information_survives_reload_and_rejects_stale_updates():void {
  [$u,$p]=$this->fixture();$version=$p->version;
  $this->patchJson('/projects/'.$p->id.'/details',$this->version($p,['name'=>'Новый проект','description'=>'Описание проекта']))->assertNoContent();
  $this->getJson('/projects/'.$p->id.'/details')->assertOk()->assertJsonPath('project.name','Новый проект')->assertJsonPath('project.description','Описание проекта');
  $this->patchJson('/projects/'.$p->id.'/details',['expected_version'=>$version,'name'=>'Старые данные','description'=>''])->assertConflict();
  $this->assertSame('Новый проект',$p->fresh()->name);
 }
 public function test_secret_is_encrypted_and_is_only_returned_by_explicit_reveal():void {
  [$u,$p]=$this->fixture();$c=$this->access($p);
  $raw=DB::table('project_credentials')->where('id',$c->id)->value('secret');$this->assertNotSame('server-secret',$raw);$this->assertStringNotContainsString('server-secret',$raw);
  $this->assertStringNotContainsString('server-secret',$this->getJson('/projects/'.$p->id.'/details')->assertOk()->getContent());
  $this->assertStringNotContainsString('server-secret',$this->getJson('/data')->assertOk()->getContent());
  $this->assertStringNotContainsString('server-secret',$this->getJson('/transfer/export')->assertOk()->getContent());
  $this->postJson('/projects/'.$p->id.'/credentials/'.$c->id.'/reveal')->assertOk()->assertJsonPath('secret','server-secret')->assertHeader('Cache-Control','no-store, private');
 }
 public function test_secret_preserves_leading_and_trailing_whitespace():void {
  [$u,$p]=$this->fixture();$secret="  exact-password \n ";$c=$this->access($p,$secret);$this->assertSame($secret,$c->fresh()->secret);
  $this->postJson('/projects/'.$p->id.'/credentials/'.$c->id.'/reveal')->assertOk()->assertJsonPath('secret',$secret);
 }
 public function test_empty_secret_on_edit_keeps_password_but_zero_can_replace_it():void {
  [$u,$p]=$this->fixture();$c=$this->access($p);
  $this->patchJson('/projects/'.$p->id.'/credentials/'.$c->id,$this->version($p,['name'=>'Обновлённый SSH','kind'=>'server','secret'=>'']))->assertNoContent();$this->assertSame('server-secret',$c->fresh()->secret);
  $this->patchJson('/projects/'.$p->id.'/credentials/'.$c->id,$this->version($p,['name'=>'SSH','kind'=>'server','secret'=>'0']))->assertNoContent();$this->assertSame('0',$c->fresh()->secret);
 }
 public function test_images_become_cover_and_removal_preserves_the_attachment():void {
  [$u,$p]=$this->fixture();$this->postJson('/projects/'.$p->id.'/files',$this->version($p,['file'=>$this->image()]))->assertNoContent();$a=ProjectAttachment::firstOrFail();$this->assertSame($a->id,$p->fresh()->cover_attachment_id);
  $this->get('/projects/'.$p->id.'/files/'.$a->id.'/preview')->assertOk()->assertHeader('Content-Type','image/png');
  $this->get('/projects/'.$p->id.'/files/'.$a->id)->assertOk()->assertHeader('Content-Type','application/octet-stream');
  $this->putJson('/projects/'.$p->id.'/cover',$this->version($p,['attachment_id'=>null]))->assertNoContent();Storage::disk('local')->assertExists($a->path);
  $this->postJson('/projects/'.$p->id.'/files',$this->version($p,['file'=>$this->image()]))->assertNoContent();$this->assertNull($p->fresh()->cover_attachment_id);
  $this->putJson('/projects/'.$p->id.'/cover',$this->version($p,['attachment_id'=>$a->id]))->assertNoContent();
  $this->deleteJson('/projects/'.$p->id.'/files/'.$a->id,$this->version($p))->assertNoContent();$this->assertNull($p->fresh()->cover_attachment_id);$this->assertDatabaseMissing('project_attachments',['id'=>$a->id]);
 }
 public function test_non_cover_upload_and_credentials_always_advance_project_version():void {
  [$u,$p]=$this->fixture();$v=$p->version;
  $this->postJson('/projects/'.$p->id.'/files',$this->version($p,['file'=>UploadedFile::fake()->createWithContent('readme.txt','Project document')]))->assertNoContent();$this->assertGreaterThan($v,$p->fresh()->version);
  $a=ProjectAttachment::firstOrFail();$this->putJson('/projects/'.$p->id.'/cover',$this->version($p,['attachment_id'=>$a->id]))->assertUnprocessable();
  $v=$p->fresh()->version;$c=$this->access($p);$this->assertGreaterThan($v,$p->fresh()->version);
  $this->postJson('/projects/'.$p->id.'/files',['expected_version'=>$v,'file'=>$this->image()])->assertConflict();$this->assertDatabaseCount('project_attachments',1);
 }
 public function test_cross_project_and_cross_account_access_is_denied_for_all_private_resources():void {
  [$u,$p]=$this->fixture();$c=$this->access($p);$this->postJson('/projects/'.$p->id.'/files',$this->version($p,['file'=>$this->image()]))->assertNoContent();$f=ProjectAttachment::firstOrFail();
  $other=Project::create(['user_id'=>$u->id,'name'=>'Другой']);
  $this->postJson('/projects/'.$other->id.'/credentials/'.$c->id.'/reveal')->assertNotFound();
  $this->putJson('/projects/'.$other->id.'/cover',$this->version($other,['attachment_id'=>$f->id]))->assertNotFound();
  $this->patchJson('/projects/'.$other->id.'/credentials/'.$c->id,$this->version($other,['name'=>'Нет','kind'=>'site']))->assertNotFound();
  $this->deleteJson('/projects/'.$other->id.'/files/'.$f->id,$this->version($other))->assertNotFound();
  $stranger=User::create(['name'=>'Другой','email'=>'stranger-project@example.com','password'=>'password-for-tests'])->fresh();$this->actingAs($stranger);
  $this->getJson('/projects/'.$p->id.'/details')->assertNotFound();$this->getJson('/projects/'.$p->id.'/files/'.$f->id)->assertNotFound();$this->getJson('/projects/'.$p->id.'/files/'.$f->id.'/preview')->assertNotFound();
  $this->postJson('/projects/'.$p->id.'/credentials/'.$c->id.'/reveal')->assertNotFound();
  $this->patchJson('/projects/'.$p->id.'/details',$this->version($p,['name'=>'Нет']))->assertNotFound();
  $this->postJson('/projects/'.$p->id.'/files',$this->version($p,['file'=>$this->image()]))->assertNotFound();
  $this->deleteJson('/projects/'.$p->id.'/credentials/'.$c->id,$this->version($p))->assertNotFound();
 }
 public function test_project_and_task_files_share_the_same_quota():void {
  [$u,$p]=$this->fixture();$t=Task::create(['user_id'=>$u->id,'title'=>'Задача']);TaskAttachment::create(['task_id'=>$t->id,'name'=>'existing','path'=>'quota/existing','bytes'=>250*1024*1024]);
  $this->postJson('/projects/'.$p->id.'/files',$this->version($p,['file'=>$this->image()]))->assertUnprocessable();$this->assertDatabaseCount('project_attachments',0);
  TaskAttachment::query()->delete();ProjectAttachment::create(['project_id'=>$p->id,'name'=>'existing','path'=>'quota/project','bytes'=>250*1024*1024]);
  $this->postJson('/tasks/'.$t->id.'/attachments',['file'=>$this->image()])->assertUnprocessable();$this->assertDatabaseCount('task_attachments',0);
 }
 public function test_device_upload_also_respects_project_storage_quota():void {
  [$u,$p]=$this->fixture();$t=Task::create(['user_id'=>$u->id,'title'=>'Задача']);ProjectAttachment::create(['project_id'=>$p->id,'name'=>'existing','path'=>'quota/project','bytes'=>250*1024*1024]);
  $issued=$u->createToken('Android',['workspace:read','workspace:write'],now()->addDay());$issued->accessToken->auth_version=$u->auth_version;$issued->accessToken->save();$this->app['auth']->forgetGuards();
  $this->post('/api/v1/tasks/'.$t->id.'/attachments',['operation_uuid'=>(string)\Illuminate\Support\Str::uuid(),'name'=>'photo.png','sha256'=>hash('sha256',base64_decode(self::PNG)),'file'=>$this->image()],['Authorization'=>'Bearer '.$issued->plainTextToken,'Accept'=>'application/json'])->assertUnprocessable();$this->assertDatabaseCount('task_attachments',0);
 }
 public function test_guest_is_blocked_and_archived_projects_are_read_only():void {
  [$u,$p]=$this->fixture();$p->archived_at=now();$p->save();$this->getJson('/projects/'.$p->id.'/details')->assertOk();
  $this->patchJson('/projects/'.$p->id.'/details',$this->version($p,['name'=>'Нет']))->assertUnprocessable();
  $this->postJson('/logout')->assertSuccessful();
  $this->getJson('/projects/'.$p->id.'/details')->assertUnauthorized();$this->postJson('/projects/'.$p->id.'/credentials/1/reveal')->assertUnauthorized();
 }
}

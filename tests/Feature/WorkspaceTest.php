<?php
namespace Tests\Feature;
use App\Models\{User,Project,Task};
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;
class WorkspaceTest extends TestCase {
 use RefreshDatabase;
 private function account(string $email='one@example.com'):User {return User::create(['name'=>'Тест','email'=>$email,'password'=>'example-password-123']);}
 public function test_guests_cannot_read_tasks():void {$this->getJson('/data')->assertUnauthorized();}
 public function test_registration_and_login():void {
  $this->postJson('/register',['name'=>'Роман','email'=>'roman@example.com','password'=>'example-password-123','password_confirmation'=>'example-password-123'])->assertCreated()->assertJsonPath('user.name','Роман');
  $this->assertAuthenticated();$this->postJson('/logout')->assertOk();$this->assertGuest();
  $this->postJson('/login',['email'=>'roman@example.com','password'=>'example-password-123'])->assertOk();$this->assertAuthenticated();
 }
 public function test_accounts_are_isolated():void {
  $a=$this->account();$b=$this->account('two@example.com');
  $p=Project::create(['user_id'=>$a->id,'name'=>'Закрытый проект']);
  $t=Task::create(['user_id'=>$a->id,'project_id'=>$p->id,'title'=>'Личная задача']);
  $this->actingAs($b)->getJson('/data')->assertOk()->assertJsonCount(0,'tasks')->assertJsonCount(0,'projects');
  $this->patchJson('/tasks/'.$t->id,['title'=>'Чужое изменение'])->assertNotFound();
  $this->deleteJson('/tasks/'.$t->id)->assertNotFound();
  $this->postJson('/tasks',['title'=>'Попытка','project_id'=>$p->id])->assertUnprocessable();
 }
 public function test_task_and_checklist_are_persisted():void {
  $this->actingAs($this->account());
  $p=$this->postJson('/projects',['name'=>'СовДело'])->assertSuccessful()->json('id');
  $id=$this->postJson('/tasks',['title'=>'Первая задача','project_id'=>$p,'due_date'=>'2026-11-11'])->assertSuccessful()->json('id');
  $this->patchJson('/tasks/'.$id,['status'=>'doing','checklist'=>[['text'=>'Проверить сохранение','done'=>true]]])->assertOk()->assertJsonPath('checklist.0.done',true);
  $this->getJson('/data')->assertJsonPath('tasks.0.status','doing')->assertJsonPath('tasks.0.checklist.0.text','Проверить сохранение');
 }

 public function test_new_task_response_has_database_defaults():void {
  $this->actingAs($this->account())->postJson('/tasks',['title'=>'Новая задача'])
   ->assertCreated()->assertJsonPath('status','todo')->assertJsonPath('priority','normal')->assertJsonPath('checklist',[]);
 }
 public function test_guest_write_requests_are_rejected():void {
  $this->postJson('/projects',['name'=>'Запрещено'])->assertUnauthorized();
  $this->postJson('/tasks',['title'=>'Запрещено'])->assertUnauthorized();
  $this->patchJson('/tasks/1',['title'=>'Запрещено'])->assertUnauthorized();
  $this->deleteJson('/tasks/1')->assertUnauthorized();
 }
 public function test_wrong_password_does_not_create_session():void {
  $this->account();
  $this->postJson('/login',['email'=>'one@example.com','password'=>'wrong-password'])->assertUnprocessable();
  $this->assertGuest();
 }
 public function test_registration_normalizes_email_and_rejects_duplicate():void {
  $this->account();
  $this->postJson('/register',['name'=>'Другой','email'=>'ONE@EXAMPLE.COM','password'=>'example-password-123','password_confirmation'=>'example-password-123'])->assertUnprocessable();
  $this->assertDatabaseCount('users',1);
 }
 public function test_task_owner_cannot_be_reassigned_by_request():void {
  $a=$this->account();$b=$this->account('two@example.com');
  $id=$this->actingAs($a)->postJson('/tasks',['title'=>'Личная','user_id'=>$b->id])->assertCreated()->json('id');
  $this->assertDatabaseHas('tasks',['id'=>$id,'user_id'=>$a->id]);
  $this->patchJson('/tasks/'.$id,['user_id'=>$b->id,'title'=>'Личная 2'])->assertOk();
  $this->assertDatabaseHas('tasks',['id'=>$id,'user_id'=>$a->id]);
 }
 public function test_cannot_move_own_task_to_foreign_project():void {
  $a=$this->account();$b=$this->account('two@example.com');
  $p=Project::create(['user_id'=>$b->id,'name'=>'Чужой проект']);
  $t=Task::create(['user_id'=>$a->id,'title'=>'Моя задача']);
  $this->actingAs($a)->patchJson('/tasks/'.$t->id,['project_id'=>$p->id])->assertUnprocessable();
  $this->assertDatabaseHas('tasks',['id'=>$t->id,'project_id'=>null]);
 }
 public function test_invalid_status_date_and_checklist_are_rejected():void {
  $u=$this->account();$t=Task::create(['user_id'=>$u->id,'title'=>'Проверка']);
  $this->actingAs($u)->patchJson('/tasks/'.$t->id,['status'=>'unknown'])->assertUnprocessable();
  $this->patchJson('/tasks/'.$t->id,['due_date'=>'not-a-date'])->assertUnprocessable();
  $this->patchJson('/tasks/'.$t->id,['checklist'=>[['text'=>'Пункт']]])->assertUnprocessable();
  $this->patchJson('/tasks/'.$t->id,['checklist'=>[['text'=>'Пункт','done'=>false,'unexpected'=>'value']]])->assertUnprocessable();
 }
 public function test_task_can_be_completed_reopened_and_deleted():void {
  $this->actingAs($this->account());
  $id=$this->postJson('/tasks',['title'=>'Завершить'])->assertCreated()->json('id');
  $this->patchJson('/tasks/'.$id,['status'=>'done'])->assertOk()->assertJsonPath('status','done');
  $this->patchJson('/tasks/'.$id,['status'=>'todo'])->assertOk()->assertJsonPath('status','todo');
  $this->deleteJson('/tasks/'.$id)->assertNoContent();
  $this->assertDatabaseMissing('tasks',['id'=>$id]);
 }
}

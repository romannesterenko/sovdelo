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
  $this->assertSoftDeleted('tasks',['id'=>$id]);
 }

 private function boardTask(User $u,string $title,string $status='todo',int $order=1024,?int $project=null):Task {
  $t=Task::create(['user_id'=>$u->id,'project_id'=>$project,'title'=>$title,'status'=>$status]);$t->sort_order=$order;$t->save();return $t;
 }
 public function test_board_reorders_before_an_existing_card():void {
  $u=$this->account();$a=$this->boardTask($u,'A','todo',1024);$b=$this->boardTask($u,'B','todo',2048);$c=$this->boardTask($u,'C','todo',3072);
  $this->actingAs($u)->postJson('/tasks/'.$c->id.'/move',['status'=>'todo','before_id'=>$b->id])->assertOk();
  $this->assertSame([$a->id,$c->id,$b->id],Task::where('user_id',$u->id)->orderBy('sort_order')->orderBy('id')->pluck('id')->all());
  $this->getJson('/data')->assertJsonPath('tasks.1.id',$c->id);
 }
 public function test_board_move_into_empty_column_and_repeat():void {
  $u=$this->account();$a=$this->boardTask($u,'A');
  $this->actingAs($u)->postJson('/tasks/'.$a->id.'/move',['status'=>'doing','before_id'=>null])->assertOk();
  $this->postJson('/tasks/'.$a->id.'/move',['status'=>'doing','before_id'=>null])->assertOk();
  $this->assertDatabaseHas('tasks',['id'=>$a->id,'status'=>'doing','sort_order'=>1024]);$this->assertDatabaseCount('tasks',1);
 }
 public function test_board_rejects_foreign_task_and_anchor():void {
  $a=$this->account();$b=$this->account('two@example.com');$mine=$this->boardTask($a,'Mine');$foreign=$this->boardTask($b,'Foreign');
  $this->actingAs($a)->postJson('/tasks/'.$foreign->id.'/move',['status'=>'done'])->assertNotFound();
  $this->postJson('/tasks/'.$mine->id.'/move',['status'=>'todo','before_id'=>$foreign->id])->assertUnprocessable();
  $this->assertDatabaseHas('tasks',['id'=>$mine->id,'status'=>'todo','sort_order'=>1024]);
 }
 public function test_board_rejects_anchor_from_wrong_column():void {
  $u=$this->account();$a=$this->boardTask($u,'A');$b=$this->boardTask($u,'B','done');
  $this->actingAs($u)->postJson('/tasks/'.$a->id.'/move',['status'=>'doing','before_id'=>$b->id])->assertUnprocessable();
  $this->assertDatabaseHas('tasks',['id'=>$a->id,'status'=>'todo']);
 }
 public function test_board_preserves_hidden_cards_relative_order():void {
  $u=$this->account();$p=Project::create(['user_id'=>$u->id,'name'=>'Другой проект']);
  $a=$this->boardTask($u,'A','todo',1024);$hidden1=$this->boardTask($u,'H1','todo',2048,$p->id);$hidden2=$this->boardTask($u,'H2','todo',3072,$p->id);$c=$this->boardTask($u,'C','todo',4096);
  $this->actingAs($u)->postJson('/tasks/'.$c->id.'/move',['status'=>'todo','before_id'=>$a->id])->assertOk();
  $this->assertSame([$hidden1->id,$hidden2->id],Task::where('project_id',$p->id)->orderBy('sort_order')->pluck('id')->all());
 }
 public function test_board_new_and_status_changed_tasks_are_appended():void {
  $u=$this->account();$a=$this->boardTask($u,'A','todo',1024);$b=$this->boardTask($u,'B','done',8192);
  $this->actingAs($u);$id=$this->postJson('/tasks',['title'=>'New'])->assertCreated()->json('id');
  $this->assertGreaterThan($a->sort_order,Task::findOrFail($id)->sort_order);
  $this->patchJson('/tasks/'.$id,['status'=>'done'])->assertOk();
  $this->assertGreaterThan($b->sort_order,Task::findOrFail($id)->sort_order);
 }
 public function test_board_guest_and_invalid_status_are_rejected():void {
  $u=$this->account();$a=$this->boardTask($u,'A');
  $this->postJson('/tasks/'.$a->id.'/move',['status'=>'done'])->assertUnauthorized();
  $this->actingAs($u)->postJson('/tasks/'.$a->id.'/move',['status'=>'invalid'])->assertUnprocessable();
 }

 public function test_comments_create_edit_delete_and_counts():void {
  $u=$this->account();$t=$this->boardTask($u,'Обсуждение');$this->actingAs($u);
  $id=$this->postJson('/tasks/'.$t->id.'/comments',['body'=>'Результат работы'])->assertSuccessful()->json('id');
  $this->getJson('/data')->assertJsonPath('tasks.0.comments_count',1);
  $this->patchJson('/tasks/'.$t->id.'/comments/'.$id,['body'=>'Уточнение'])->assertOk();
  $this->getJson('/tasks/'.$t->id.'/details')->assertOk()->assertJsonPath('comments.0.body','Уточнение');
  $this->deleteJson('/tasks/'.$t->id.'/comments/'.$id)->assertNoContent();
  $this->assertDatabaseMissing('task_comments',['id'=>$id]);
 }
 public function test_labels_can_be_assigned_and_removed():void {
  $u=$this->account();$t=$this->boardTask($u,'Метки');$this->actingAs($u);
  $id=$this->postJson('/labels',['name'=>'Срочно','color'=>'red'])->assertSuccessful()->json('id');
  $this->putJson('/tasks/'.$t->id.'/labels',['ids'=>[$id]])->assertOk()->assertJsonPath('labels.0.name','Срочно');
  $this->getJson('/data')->assertJsonPath('tasks.0.labels.0.color','red');
  $this->putJson('/tasks/'.$t->id.'/labels',['ids'=>[]])->assertOk()->assertJsonCount(0,'labels');
 }
 public function test_extras_are_private_between_accounts():void {
  $a=$this->account();$b=$this->account('two@example.com');$t=$this->boardTask($a,'Private');
  $label=\App\Models\Label::create(['user_id'=>$a->id,'name'=>'Private','color'=>'green']);
  $comment=\App\Models\TaskComment::create(['task_id'=>$t->id,'user_id'=>$a->id,'body'=>'Private']);
  $mine=$this->boardTask($b,'Mine');$this->actingAs($b);
  $this->getJson('/tasks/'.$t->id.'/details')->assertNotFound();
  $this->postJson('/tasks/'.$t->id.'/comments',['body'=>'Attack'])->assertNotFound();
  $this->patchJson('/tasks/'.$t->id.'/comments/'.$comment->id,['body'=>'Attack'])->assertNotFound();
  $this->deleteJson('/tasks/'.$t->id.'/comments/'.$comment->id)->assertNotFound();
  $this->putJson('/tasks/'.$mine->id.'/labels',['ids'=>[$label->id]])->assertUnprocessable();
  $this->getJson('/labels')->assertJsonCount(0);
 }
 public function test_private_file_upload_download_and_foreign_denial():void {
  \Illuminate\Support\Facades\Storage::fake('local');
  $a=$this->account();$b=$this->account('two@example.com');$t=$this->boardTask($a,'File');
  $file=\Illuminate\Http\UploadedFile::fake()->create('notes.txt',1,'text/plain');
  $id=$this->actingAs($a)->post('/tasks/'.$t->id.'/attachments',['file'=>$file],['Accept'=>'application/json'])->assertSuccessful()->json('id');
  $this->getJson('/data')->assertJsonPath('tasks.0.attachments_count',1);
  $this->get('/tasks/'.$t->id.'/attachments/'.$id)->assertOk()->assertHeader('content-type','application/octet-stream');
  $this->actingAs($b)->get('/tasks/'.$t->id.'/attachments/'.$id,['Accept'=>'application/json'])->assertNotFound();
  $this->deleteJson('/tasks/'.$t->id.'/attachments/'.$id)->assertNotFound();
  $this->actingAs($a)->deleteJson('/tasks/'.$t->id.'/attachments/'.$id)->assertNoContent();
  $this->assertDatabaseMissing('task_attachments',['id'=>$id]);
 }
 public function test_oversize_and_disallowed_files_are_rejected():void {
  \Illuminate\Support\Facades\Storage::fake('local');$u=$this->account();$t=$this->boardTask($u,'Validation');$this->actingAs($u);
  $this->post('/tasks/'.$t->id.'/attachments',['file'=>\Illuminate\Http\UploadedFile::fake()->create('large.pdf',10241,'application/pdf')],['Accept'=>'application/json'])->assertUnprocessable();
  $this->post('/tasks/'.$t->id.'/attachments',['file'=>\Illuminate\Http\UploadedFile::fake()->create('run.exe',1,'application/x-msdownload')],['Accept'=>'application/json'])->assertUnprocessable();
  $this->assertDatabaseCount('task_attachments',0);
 }
 public function test_comment_cannot_be_edited_through_another_task():void {
  $u=$this->account();$a=$this->boardTask($u,'A');$b=$this->boardTask($u,'B');$c=\App\Models\TaskComment::create(['task_id'=>$a->id,'user_id'=>$u->id,'body'=>'Keep']);
  $this->actingAs($u)->patchJson('/tasks/'.$b->id.'/comments/'.$c->id,['body'=>'Wrong'])->assertNotFound();
  $this->assertDatabaseHas('task_comments',['id'=>$c->id,'body'=>'Keep']);
 }

 public function test_archived_task_is_hidden_and_restorable():void {
  $u=$this->account();$t=$this->boardTask($u,'Archive');$this->actingAs($u);
  $this->postJson('/tasks/'.$t->id.'/archive')->assertOk();
  $this->getJson('/data')->assertJsonCount(0,'tasks');
  $this->getJson('/lifecycle')->assertJsonPath('archived_tasks.0.id',$t->id);
  $this->postJson('/tasks/'.$t->id.'/restore')->assertOk();
  $this->getJson('/data')->assertJsonPath('tasks.0.id',$t->id);
 }
 public function test_trash_preserves_checklist_labels_comments_and_files():void {
  \Illuminate\Support\Facades\Storage::fake('local');$u=$this->account();$t=$this->boardTask($u,'Keep');
  $t->checklist=[['text'=>'Keep checklist','done'=>true]];$t->save();
  $l=\App\Models\Label::create(['user_id'=>$u->id,'name'=>'Keep label','color'=>'green']);$t->labels()->attach($l->id);
  \App\Models\TaskComment::create(['task_id'=>$t->id,'user_id'=>$u->id,'body'=>'Keep comment']);
  \Illuminate\Support\Facades\Storage::disk('local')->put('keep.txt','keep');
  \App\Models\TaskAttachment::create(['task_id'=>$t->id,'name'=>'keep.txt','path'=>'keep.txt','bytes'=>4]);
  $this->actingAs($u)->deleteJson('/tasks/'.$t->id)->assertNoContent();
  $this->assertSoftDeleted('tasks',['id'=>$t->id]);
  $this->getJson('/data')->assertJsonCount(0,'tasks');
  $this->getJson('/lifecycle')->assertJsonPath('trashed_tasks.0.id',$t->id);
  $this->postJson('/tasks/'.$t->id.'/restore')->assertOk();
  $this->getJson('/tasks/'.$t->id.'/details')->assertJsonPath('task.checklist.0.text','Keep checklist')->assertJsonPath('task.labels.0.name','Keep label')->assertJsonPath('comments.0.body','Keep comment')->assertJsonPath('attachments.0.name','keep.txt');
  \Illuminate\Support\Facades\Storage::disk('local')->assertExists('keep.txt');
 }
 public function test_archived_project_hides_tasks_and_restores_them():void {
  $u=$this->account();$p=Project::create(['user_id'=>$u->id,'name'=>'Archive project']);$this->boardTask($u,'Task','todo',1024,$p->id);$this->actingAs($u);
  $this->postJson('/projects/'.$p->id.'/archive')->assertOk();
  $this->getJson('/data')->assertJsonCount(0,'projects')->assertJsonCount(0,'tasks');
  $this->getJson('/lifecycle')->assertJsonPath('archived_projects.0.id',$p->id)->assertJsonCount(1,'archived_tasks');
  $this->postJson('/projects/'.$p->id.'/restore')->assertOk();
  $this->getJson('/data')->assertJsonCount(1,'projects')->assertJsonCount(1,'tasks');
 }
 public function test_cannot_create_in_archived_project_or_move_archived_task():void {
  $u=$this->account();$p=Project::create(['user_id'=>$u->id,'name'=>'Hidden']);$t=$this->boardTask($u,'Hidden','todo',1024,$p->id);$this->actingAs($u);
  $this->postJson('/projects/'.$p->id.'/archive')->assertOk();
  $this->postJson('/tasks',['title'=>'Denied','project_id'=>$p->id])->assertUnprocessable();
  $this->postJson('/tasks/'.$t->id.'/move',['status'=>'doing'])->assertUnprocessable();
 }
 public function test_other_account_cannot_restore_or_archive():void {
  $a=$this->account();$b=$this->account('two@example.com');$p=Project::create(['user_id'=>$a->id,'name'=>'Private']);$t=$this->boardTask($a,'Private');$t->delete();
  $this->actingAs($b)->postJson('/tasks/'.$t->id.'/restore')->assertNotFound();
  $this->postJson('/projects/'.$p->id.'/archive')->assertNotFound();
  $this->getJson('/lifecycle')->assertJsonCount(0,'trashed_tasks')->assertJsonCount(0,'archived_projects');
 }
 public function test_archived_task_does_not_return_from_board_move_response():void {
  $u=$this->account();$a=$this->boardTask($u,'Active');$b=$this->boardTask($u,'Hidden');$this->actingAs($u);
  $this->postJson('/tasks/'.$b->id.'/archive')->assertOk();
  $this->postJson('/tasks/'.$a->id.'/move',['status'=>'doing'])->assertOk()->assertJsonCount(1,'tasks')->assertJsonPath('tasks.0.id',$a->id);
 }

 public function test_planning_and_deadline_are_independent():void {
  $this->actingAs($this->account());$id=$this->postJson('/tasks',['title'=>'Plan','planned_date'=>'2026-11-11','due_date'=>'2026-11-20'])->assertCreated()->assertJsonPath('planned_date','2026-11-11')->json('id');
  $this->patchJson('/tasks/'.$id,['planned_date'=>'2026-11-12'])->assertOk()->assertJsonPath('due_date','2026-11-20')->assertJsonPath('planned_date','2026-11-12');
  $this->patchJson('/tasks/'.$id,['planned_date'=>null])->assertOk()->assertJsonPath('planned_date',null)->assertJsonPath('due_date','2026-11-20');
 }
 public function test_invalid_planned_date_is_rejected():void {
  $this->actingAs($this->account())->postJson('/tasks',['title'=>'Plan','planned_date'=>'invalid'])->assertUnprocessable();
 }
 public function test_timezone_preferences_are_per_account():void {
  $a=$this->account();$b=$this->account('two@example.com');
  $this->actingAs($a)->patchJson('/preferences',['timezone'=>'Asia/Vladivostok'])->assertOk()->assertJsonPath('user.timezone','Asia/Vladivostok');
  $this->assertDatabaseHas('users',['id'=>$a->id,'timezone'=>'Asia/Vladivostok']);$this->assertDatabaseHas('users',['id'=>$b->id,'timezone'=>'Europe/Moscow']);
  $this->patchJson('/preferences',['timezone'=>'Invalid/Zone'])->assertUnprocessable();
 }
}

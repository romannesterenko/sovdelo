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

 private function timerStart(Task $t,?string $key=null){return $this->postJson('/tasks/'.$t->id.'/timer',['request_key'=>$key??(string)\Illuminate\Support\Str::uuid()]);}
 public function test_timer_start_pause_resume_and_elapsed_time():void {
  $this->travelTo(\Carbon\Carbon::parse('2026-11-11 12:00:00','UTC'));$u=$this->account();$t=$this->boardTask($u,'Time');$this->actingAs($u);
  $id=$this->timerStart($t)->assertOk()->assertJsonPath('active.task_id',$t->id)->json('active.id');
  $this->travel(90)->seconds();$this->getJson('/timer')->assertJsonPath('active.elapsed_seconds',90);
  $this->postJson('/timer/'.$id.'/stop',['reason'=>'pause'])->assertOk()->assertJsonPath('paused.task_id',$t->id)->assertJsonPath('paused.task_seconds',90);
  $this->timerStart($t)->assertOk();$this->travel(30)->seconds();
  $this->getJson('/tasks/'.$t->id.'/time')->assertOk()->assertJsonPath('total_seconds',120);
 }
 public function test_starting_another_task_closes_the_previous_timer():void {
  $u=$this->account();$a=$this->boardTask($u,'A');$b=$this->boardTask($u,'B');$this->actingAs($u);
  $id=$this->timerStart($a)->assertOk()->json('active.id');$this->travel(10)->seconds();$this->timerStart($b)->assertOk()->assertJsonPath('active.task_id',$b->id);
  $this->assertDatabaseHas('time_sessions',['id'=>$id,'end_reason'=>'switch']);
  $this->assertSame(1,\App\Models\TimeSession::whereNull('ended_at')->count());
 }
 public function test_timer_start_retries_do_not_restart_old_task():void {
  $u=$this->account();$a=$this->boardTask($u,'A');$b=$this->boardTask($u,'B');$this->actingAs($u);$key=(string)\Illuminate\Support\Str::uuid();
  $this->timerStart($a,$key)->assertOk();$this->timerStart($a,$key)->assertOk();
  $this->timerStart($b)->assertOk();$this->timerStart($a,$key)->assertOk()->assertJsonPath('active.task_id',$b->id);
  $this->assertDatabaseCount('time_sessions',2);
 }
 public function test_timer_cannot_access_another_account():void {
  $a=$this->account();$b=$this->account('two@example.com');$t=$this->boardTask($a,'Private');$this->actingAs($a);$id=$this->timerStart($t)->json('active.id');
  $this->actingAs($b);$this->timerStart($t)->assertNotFound();$this->postJson('/timer/'.$id.'/stop',['reason'=>'pause'])->assertNotFound();
  $this->getJson('/tasks/'.$t->id.'/time')->assertNotFound();$this->getJson('/timer')->assertJsonPath('active',null);
 }
 public function test_timer_adjustments_are_audited_and_active_edit_is_rejected():void {
  $u=$this->account();$t=$this->boardTask($u,'Audit');$this->actingAs($u);$id=$this->timerStart($t)->json('active.id');
  $this->patchJson('/timer/'.$id,['seconds'=>60,'reason'=>'Исправление'])->assertUnprocessable();
  $this->postJson('/timer/'.$id.'/stop',['reason'=>'stop'])->assertOk();
  $this->patchJson('/timer/'.$id,['seconds'=>120,'reason'=>'Забыл выключить'])->assertOk();
  $this->assertDatabaseHas('time_adjustments',['time_session_id'=>$id,'new_seconds'=>120,'reason'=>'Забыл выключить']);
  $this->getJson('/tasks/'.$t->id.'/time')->assertJsonPath('total_seconds',120);
 }
 public function test_completing_archiving_and_trashing_stop_timer():void {
  $u=$this->account();$t=$this->boardTask($u,'Stop');$this->actingAs($u);$this->timerStart($t)->assertOk();
  $this->patchJson('/tasks/'.$t->id,['status'=>'done'])->assertOk();$this->getJson('/timer')->assertJsonPath('active',null);
  $this->patchJson('/tasks/'.$t->id,['status'=>'todo'])->assertOk();$this->timerStart($t)->assertOk();
  $this->postJson('/tasks/'.$t->id.'/archive')->assertOk();$this->getJson('/timer')->assertJsonPath('active',null);
  $this->postJson('/tasks/'.$t->id.'/restore')->assertOk();$this->timerStart($t)->assertOk();
  $this->deleteJson('/tasks/'.$t->id)->assertNoContent();$this->getJson('/timer')->assertJsonPath('active',null);
 }
 public function test_database_rejects_second_active_session():void {
  $u=$this->account();$t=$this->boardTask($u,'Unique');$this->actingAs($u);$this->timerStart($t)->assertOk();
  try{\Illuminate\Support\Facades\DB::transaction(fn()=>\App\Models\TimeSession::create(['user_id'=>$u->id,'task_id'=>$t->id,'request_key'=>(string)\Illuminate\Support\Str::uuid(),'started_at'=>now()]));$this->fail('Second active session was accepted');}
  catch(\Illuminate\Database\QueryException $e){$this->assertSame('23505',$e->errorInfo[0]);}
 }

 public function test_stale_stop_does_not_stop_new_active_session():void {
  $u=$this->account();$a=$this->boardTask($u,'A');$b=$this->boardTask($u,'B');$this->actingAs($u);$old=$this->timerStart($a)->json('active.id');$new=$this->timerStart($b)->json('active.id');
  $this->postJson('/timer/'.$old.'/stop',['reason'=>'pause'])->assertOk()->assertJsonPath('active.id',$new);
 }
 public function test_archiving_project_stops_its_running_task():void {
  $u=$this->account();$p=Project::create(['user_id'=>$u->id,'name'=>'Time project']);$t=$this->boardTask($u,'Time','todo',1024,$p->id);$this->actingAs($u);$this->timerStart($t)->assertOk();
  $this->postJson('/projects/'.$p->id.'/archive')->assertOk();$this->getJson('/timer')->assertJsonPath('active',null);
 }
 public function test_series_generates_independent_task_once_and_resets_checklist():void {
  $u=$this->account();$this->travelTo(\Carbon\CarbonImmutable::parse('2026-11-11 12:00:00','UTC'));$this->actingAs($u);
  $t=Task::create(['user_id'=>$u->id,'title'=>'Полить цветы','description'=>'Окно','planned_date'=>'2026-11-11','due_date'=>'2026-11-12','checklist'=>[['text'=>'Кухня','done'=>true]]]);
  $label=\App\Models\Label::create(['user_id'=>$u->id,'name'=>'Дом','color'=>'green']);$t->labels()->attach($label);
  $this->postJson('/task-series',['task_id'=>$t->id,'frequency'=>'daily','next_date'=>'2026-11-11','request_key'=>(string)\Illuminate\Support\Str::uuid()])->assertCreated();
  $this->getJson('/data')->assertOk()->assertJsonCount(2,'tasks');$this->getJson('/data')->assertJsonCount(2,'tasks');
  $copy=Task::whereNotNull('task_series_id')->firstOrFail();$this->assertSame('2026-11-11',$copy->planned_date);$this->assertNull($copy->due_date);$this->assertFalse($copy->checklist[0]['done']);$this->assertSame($label->id,$copy->labels->first()->id);
  $this->patchJson('/tasks/'.$copy->id,['title'=>'Один экземпляр','status'=>'done'])->assertOk();
  $this->assertDatabaseHas('task_series',['title'=>'Полить цветы','next_date'=>'2026-11-12']);$this->assertSame('Полить цветы',$t->fresh()->title);
 }
 public function test_series_skips_missed_occurrences_and_uses_account_timezone():void {
  $u=$this->account();$u->timezone='Asia/Vladivostok';$u->save();$this->travelTo(\Carbon\CarbonImmutable::parse('2026-11-01 12:00:00','UTC'));$this->actingAs($u);
  $t=Task::create(['user_id'=>$u->id,'title'=>'Утро']);
  $this->postJson('/task-series',['task_id'=>$t->id,'frequency'=>'daily','next_date'=>'2026-11-02','request_key'=>(string)\Illuminate\Support\Str::uuid()])->assertCreated();
  $this->travelTo(\Carbon\CarbonImmutable::parse('2026-11-10 18:00:00','UTC'));
  $this->artisan('sovdelo:recurring')->assertSuccessful();$this->artisan('sovdelo:recurring')->assertSuccessful();
  $this->assertDatabaseCount('tasks',2);$this->assertDatabaseHas('tasks',['occurrence_date'=>'2026-11-11']);$this->assertDatabaseHas('task_series',['next_date'=>'2026-11-12']);
 }
 public function test_monthly_schedule_preserves_day_after_short_month_and_leap_year():void {
  $s=app(\App\Services\RecurringTasks::class);
  $this->assertSame('2027-02-28',$s->advance('2027-01-31','monthly',31));$this->assertSame('2027-03-31',$s->advance('2027-02-28','monthly',31));
  $this->assertSame('2028-02-29',$s->advance('2028-01-31','monthly',31));$this->assertSame('2026-11-18',$s->advance('2026-11-11','weekly',11));
 }
 public function test_series_pause_resume_and_future_edit_preserve_existing_tasks():void {
  $u=$this->account();$this->travelTo(\Carbon\CarbonImmutable::parse('2026-11-11 12:00:00','UTC'));$this->actingAs($u);$t=Task::create(['user_id'=>$u->id,'title'=>'Исходная']);
  $id=$this->postJson('/task-series',['task_id'=>$t->id,'frequency'=>'weekly','next_date'=>'2026-11-11','request_key'=>(string)\Illuminate\Support\Str::uuid()])->assertCreated()->json('id');
  $this->patchJson('/task-series/'.$id,['active'=>false])->assertOk();$this->getJson('/data')->assertJsonCount(1,'tasks');
  $this->patchJson('/task-series/'.$id,['title'=>'Новая серия','active'=>true])->assertOk();$this->getJson('/data')->assertJsonCount(2,'tasks');
  $this->assertDatabaseHas('tasks',['id'=>$t->id,'title'=>'Исходная']);$this->assertDatabaseHas('tasks',['title'=>'Новая серия']);
  $this->patchJson('/task-series/'.$id,['title'=>'Ещё новее'])->assertOk();$this->assertDatabaseHas('tasks',['title'=>'Новая серия']);
 }
 public function test_series_accounts_are_isolated_and_schedule_validated():void {
  $a=$this->account();$b=$this->account('second@example.com');$this->travelTo(\Carbon\CarbonImmutable::parse('2026-11-11 12:00:00','UTC'));$t=Task::create(['user_id'=>$a->id,'title'=>'Личная']);
  $d=['task_id'=>$t->id,'frequency'=>'daily','next_date'=>'2026-11-12','request_key'=>(string)\Illuminate\Support\Str::uuid()];
  $id=$this->actingAs($a)->postJson('/task-series',$d)->assertCreated()->json('id');
  $this->actingAs($b)->getJson('/task-series')->assertJsonCount(0);$this->postJson('/task-series',$d)->assertNotFound();$this->patchJson('/task-series/'.$id,['active'=>false])->assertNotFound();
  $this->actingAs($a)->patchJson('/task-series/'.$id,['frequency'=>'hourly','next_date'=>'2026-11-10'])->assertUnprocessable();
 }
 public function test_archived_project_pauses_series_without_deleting_schedule():void {
  $u=$this->account();$this->travelTo(\Carbon\CarbonImmutable::parse('2026-11-11 12:00:00','UTC'));$this->actingAs($u);$p=Project::create(['user_id'=>$u->id,'name'=>'Проект']);$t=Task::create(['user_id'=>$u->id,'project_id'=>$p->id,'title'=>'Повтор']);
  $this->postJson('/task-series',['task_id'=>$t->id,'frequency'=>'daily','next_date'=>'2026-11-11','request_key'=>(string)\Illuminate\Support\Str::uuid()])->assertCreated();
  $this->postJson('/projects/'.$p->id.'/archive')->assertOk();$this->getJson('/data')->assertJsonCount(0,'tasks');$this->assertDatabaseCount('tasks',1);
  $this->postJson('/projects/'.$p->id.'/restore')->assertOk();$this->getJson('/data')->assertJsonCount(2,'tasks');
 }
 public function test_retry_series_creation_does_not_duplicate_template():void {
  $u=$this->account();$this->travelTo(\Carbon\CarbonImmutable::parse('2026-11-11 12:00:00','UTC'));$this->actingAs($u);$t=Task::create(['user_id'=>$u->id,'title'=>'Серия']);
  $d=['task_id'=>$t->id,'frequency'=>'daily','next_date'=>'2026-11-12','request_key'=>(string)\Illuminate\Support\Str::uuid()];
  $id=$this->postJson('/task-series',$d)->assertCreated()->json('id');$this->postJson('/task-series',$d)->assertCreated()->assertJsonPath('id',$id);$this->assertDatabaseCount('task_series',1);
 }
 public function test_trashed_occurrence_is_not_regenerated():void {
  $u=$this->account();$this->travelTo(\Carbon\CarbonImmutable::parse('2026-11-11 12:00:00','UTC'));$this->actingAs($u);$t=Task::create(['user_id'=>$u->id,'title'=>'Серия']);
  $id=$this->postJson('/task-series',['task_id'=>$t->id,'frequency'=>'daily','next_date'=>'2026-11-11','request_key'=>(string)\Illuminate\Support\Str::uuid()])->assertCreated()->json('id');
  $this->getJson('/data')->assertOk();$copy=Task::whereNotNull('task_series_id')->firstOrFail();$this->deleteJson('/tasks/'.$copy->id)->assertNoContent();
  $this->patchJson('/task-series/'.$id,['frequency'=>'daily','next_date'=>'2026-11-11'])->assertOk();$this->getJson('/data')->assertJsonCount(1,'tasks');$this->assertDatabaseCount('tasks',2);
 }
 public function test_deadline_notification_respects_account_time_and_is_sent_once():void {
  $u=$this->account();$this->actingAs($u);Task::create(['user_id'=>$u->id,'title'=>'Дедлайн','due_date'=>'2026-11-11']);
  $this->travelTo(\Carbon\CarbonImmutable::parse('2026-11-11 05:59:00','UTC'));$this->getJson('/notifications')->assertOk()->assertJsonCount(0,'items');
  $this->travelTo(\Carbon\CarbonImmutable::parse('2026-11-11 06:00:00','UTC'));$this->getJson('/notifications')->assertJsonCount(1,'items')->assertJsonPath('unread',1)->assertJsonPath('items.0.kind','deadline');
  $this->getJson('/notifications')->assertJsonCount(1,'items');$this->artisan('sovdelo:reminders')->assertSuccessful();$this->assertDatabaseCount('task_notifications',1);
 }
 public function test_custom_reminder_converts_local_time_to_utc_and_can_be_cancelled():void {
  $u=$this->account();$this->actingAs($u);$this->travelTo(\Carbon\CarbonImmutable::parse('2026-11-11 12:00:00','UTC'));$t=Task::create(['user_id'=>$u->id,'title'=>'Позвонить']);
  $this->putJson('/tasks/'.$t->id.'/reminder',['local'=>'2026-11-11T16:00'])->assertOk()->assertJsonPath('local','2026-11-11T16:00')->assertJsonPath('sent',false);
  $this->assertSame('13:00',$t->fresh()->remind_at->utc()->format('H:i'));$this->getJson('/notifications')->assertJsonCount(0,'items');
  $this->putJson('/tasks/'.$t->id.'/reminder',['local'=>null])->assertOk()->assertJsonPath('at',null);
  $this->travelTo(\Carbon\CarbonImmutable::parse('2026-11-11 14:00:00','UTC'));$this->getJson('/notifications')->assertJsonCount(0,'items');
 }
 public function test_missed_custom_reminder_is_delivered_once_after_return():void {
  $u=$this->account();$this->actingAs($u);$this->travelTo(\Carbon\CarbonImmutable::parse('2026-11-11 12:00:00','UTC'));$t=Task::create(['user_id'=>$u->id,'title'=>'Звонок']);
  $this->putJson('/tasks/'.$t->id.'/reminder',['local'=>'2026-11-11T16:00'])->assertOk();
  $this->travelTo(\Carbon\CarbonImmutable::parse('2026-11-15 12:00:00','UTC'));$this->getJson('/notifications')->assertJsonCount(1,'items')->assertJsonPath('items.0.kind','custom');$this->getJson('/notifications')->assertJsonCount(1,'items');
  $this->getJson('/tasks/'.$t->id.'/reminder')->assertJsonPath('sent',true);
 }
 public function test_completed_archived_and_trashed_tasks_do_not_emit_notifications():void {
  $u=$this->account();$this->actingAs($u);$this->travelTo(\Carbon\CarbonImmutable::parse('2026-11-11 12:00:00','UTC'));
  $p=Project::create(['user_id'=>$u->id,'name'=>'Архив']);
  foreach(['active','done','archive','trash','project'] as $kind){$t=Task::create(['user_id'=>$u->id,'title'=>$kind,'status'=>$kind==='done'?'done':'todo','due_date'=>'2026-11-10','project_id'=>$kind==='project'?$p->id:null]);if($kind==='archive')$this->postJson('/tasks/'.$t->id.'/archive')->assertOk();if($kind==='trash')$this->deleteJson('/tasks/'.$t->id)->assertNoContent();}
  $this->postJson('/projects/'.$p->id.'/archive')->assertOk();$this->getJson('/notifications')->assertJsonCount(1,'items')->assertJsonPath('items.0.title','active');
 }
 public function test_notification_settings_disable_delivery_and_reenable_catches_up():void {
  $u=$this->account();$this->actingAs($u);$this->travelTo(\Carbon\CarbonImmutable::parse('2026-11-11 12:00:00','UTC'));Task::create(['user_id'=>$u->id,'title'=>'Срок','due_date'=>'2026-11-11']);
  $d=['notifications_enabled'=>false,'deadline_notifications'=>true,'notification_time'=>'09:00'];$this->putJson('/notifications/settings',$d)->assertOk();$this->getJson('/notifications')->assertJsonCount(0,'items');
  $d['notifications_enabled']=true;$d['deadline_notifications']=false;$this->putJson('/notifications/settings',$d)->assertOk();$this->getJson('/notifications')->assertJsonCount(0,'items');
  $d['deadline_notifications']=true;$this->putJson('/notifications/settings',$d)->assertOk();$this->getJson('/notifications')->assertJsonCount(1,'items');
  $this->putJson('/notifications/settings',[...$d,'notification_time'=>'25:00'])->assertUnprocessable();
 }
 public function test_notification_read_and_read_all_are_scoped_and_preserve_new_arrivals():void {
  $a=$this->account();$b=$this->account('notices@example.com');$this->actingAs($a);
  $create=fn($user,$key)=>\App\Models\TaskNotification::create(['user_id'=>$user->id,'event_key'=>$key,'kind'=>'custom','title'=>$key,'scheduled_at'=>now()]);
  $old=$create($a,'old');$foreign=$create($b,'foreign');$new=$create($a,'new');
  $this->postJson('/notifications/'.$foreign->id.'/read')->assertNotFound();
  $this->postJson('/notifications/read-all',['through_id'=>$old->id])->assertOk();$this->assertNotNull($old->fresh()->read_at);$this->assertNull($new->fresh()->read_at);$this->assertNull($foreign->fresh()->read_at);
  $this->postJson('/notifications/'.$new->id.'/read')->assertOk();$this->getJson('/notifications')->assertJsonCount(2,'items')->assertJsonPath('unread',0);
 }
 public function test_reminder_accounts_and_guests_are_isolated():void {
  $this->getJson('/notifications')->assertUnauthorized();$this->getJson('/notifications/settings')->assertUnauthorized();
  $a=$this->account();$b=$this->account('reminders@example.com');$t=Task::create(['user_id'=>$a->id,'title'=>'Личная']);$this->actingAs($b);
  $this->getJson('/tasks/'.$t->id.'/reminder')->assertNotFound();$this->putJson('/tasks/'.$t->id.'/reminder',['local'=>null])->assertNotFound();
  $this->getJson('/notifications')->assertJsonCount(0,'items');
 }
 public function test_reminder_validation_rejects_past_and_nonexistent_local_time():void {
  $u=$this->account();$u->timezone='Europe/Berlin';$u->save();$this->actingAs($u);$this->travelTo(\Carbon\CarbonImmutable::parse('2026-11-11 12:00:00','UTC'));$t=Task::create(['user_id'=>$u->id,'title'=>'Часы']);
  $this->putJson('/tasks/'.$t->id.'/reminder',['local'=>'2026-11-10T09:00'])->assertUnprocessable();
  $this->putJson('/tasks/'.$t->id.'/reminder',['local'=>'2027-03-28T02:30'])->assertUnprocessable();
  $this->putJson('/tasks/'.$t->id.'/reminder',['local'=>'2027-03-28T03:30'])->assertOk();
 }
 public function test_notification_date_uses_timezone_across_utc_midnight():void {
  $u=$this->account();$u->timezone='Asia/Vladivostok';$u->save();$this->actingAs($u);$this->travelTo(\Carbon\CarbonImmutable::parse('2026-11-10 23:01:00','UTC'));Task::create(['user_id'=>$u->id,'title'=>'Утро','due_date'=>'2026-11-11']);
  $this->getJson('/notifications')->assertJsonCount(1,'items');$n=\App\Models\TaskNotification::firstOrFail();$this->assertSame('2026-11-10 23:00',$n->scheduled_at->utc()->format('Y-m-d H:i'));
 }
 public function test_notification_pagination_and_unread_count_include_older_items():void {
  $u=$this->account();$this->actingAs($u);for($i=1;$i<=35;$i++)\App\Models\TaskNotification::create(['user_id'=>$u->id,'event_key'=>'notice'.$i,'kind'=>'custom','title'=>'Задача','scheduled_at'=>now()]);
  $d=$this->getJson('/notifications')->assertJsonCount(30,'items')->assertJsonPath('unread',35)->assertJsonPath('has_more',true)->json();
  $this->getJson('/notifications?before='.$d['items'][29]['id'])->assertJsonCount(5,'items')->assertJsonPath('has_more',false);
 }
 public function test_queued_reminder_job_is_idempotent_and_deadline_change_is_new_event():void {
  $u=$this->account();$this->travelTo(\Carbon\CarbonImmutable::parse('2026-11-11 12:00:00','UTC'));$t=Task::create(['user_id'=>$u->id,'title'=>'Срок','due_date'=>'2026-11-10']);
  (new \App\Jobs\GenerateTaskReminders($u->id))->handle(app(\App\Services\TaskReminders::class));(new \App\Jobs\GenerateTaskReminders($u->id))->handle(app(\App\Services\TaskReminders::class));$this->assertDatabaseCount('task_notifications',1);
  $this->actingAs($u)->patchJson('/tasks/'.$t->id,['due_date'=>'2026-11-11'])->assertOk();$this->getJson('/notifications')->assertJsonCount(2,'items');
  \Illuminate\Support\Facades\Bus::fake();$this->artisan('sovdelo:reminders --queue')->assertSuccessful();\Illuminate\Support\Facades\Bus::assertDispatched(\App\Jobs\GenerateTaskReminders::class);
 }
 public function test_account_profile_preferences_are_saved_and_accounts_stay_separate():void {
  $a=$this->account();$b=$this->account('profile@example.com');$this->actingAs($a);
  $this->patchJson('/account',['name'=>'  Роман  ','timezone'=>'Asia/Vladivostok','theme'=>'system','email'=>$b->email,'password'=>'hacked-password','auth_version'=>99])->assertOk()->assertJsonPath('user.name','Роман')->assertJsonPath('user.theme','system');
  $this->assertDatabaseHas('users',['id'=>$a->id,'name'=>'Роман','timezone'=>'Asia/Vladivostok','theme'=>'system','email'=>$a->email,'auth_version'=>0]);$this->assertSame('Тест',$b->fresh()->name);
  $this->actingAs($a->fresh())->getJson('/account')->assertOk()->assertJsonPath('user.theme','system')->assertJsonMissingPath('user.password')->assertJsonMissingPath('user.auth_version')->assertJsonMissingPath('user.remember_token');
 }
 public function test_account_profile_rejects_invalid_values_and_guests():void {
  $this->getJson('/account')->assertUnauthorized();$this->patchJson('/account',['name'=>'Гость'])->assertUnauthorized();$this->putJson('/account/password',[])->assertUnauthorized();
  $this->actingAs($this->account());$this->patchJson('/account',['name'=>'   ','timezone'=>'Not/AZone','theme'=>'neon'])->assertUnprocessable();
 }
 public function test_wrong_current_password_does_not_change_password_or_revoke_sessions():void {
  $u=$this->account();$hash=$u->password;$this->actingAs($u);
  $this->putJson('/account/password',['current_password'=>'wrong','password'=>'new-password-12345','password_confirmation'=>'new-password-12345'])->assertUnprocessable();
  $this->assertSame($hash,$u->fresh()->password);$this->assertSame(0,$u->fresh()->auth_version);
 }
 public function test_password_change_keeps_current_login_rotates_token_and_deletes_other_sessions():void {
  $u=$this->account();$b=$this->account('other-password@example.com');$this->actingAs($u);$this->getJson('/account')->assertOk();
  foreach([['old-device',$u->id],['foreign-device',$b->id]] as [$id,$uid])\Illuminate\Support\Facades\DB::table('sessions')->insert(['id'=>$id,'user_id'=>$uid,'payload'=>'','last_activity'=>now()->timestamp]);
  $oldToken=$u->remember_token;$oldCsrf=session()->token();
  $this->putJson('/account/password',['current_password'=>'example-password-123','password'=>'new-password-12345','password_confirmation'=>'new-password-12345'])->assertOk()->assertJsonPath('user.email',$u->email)->assertJsonMissingPath('user.password');
  $fresh=$u->fresh();$this->assertTrue(\Illuminate\Support\Facades\Hash::check('new-password-12345',$fresh->password));$this->assertSame(1,$fresh->auth_version);$this->assertNotSame($oldToken,$fresh->remember_token);$this->assertNotSame($oldCsrf,session()->token());
  $this->assertDatabaseMissing('sessions',['id'=>'old-device']);$this->assertDatabaseHas('sessions',['id'=>'foreign-device']);$this->getJson('/account')->assertOk();
 }
 public function test_password_change_rejects_confirmation_mismatch_and_same_password():void {
  $this->actingAs($this->account());
  $this->putJson('/account/password',['current_password'=>'example-password-123','password'=>'new-password-12345','password_confirmation'=>'different-password'])->assertUnprocessable();
  $this->putJson('/account/password',['current_password'=>'example-password-123','password'=>'example-password-123','password_confirmation'=>'example-password-123'])->assertUnprocessable();
 }
 public function test_old_account_version_is_rejected_after_password_change():void {
  $u=$this->account();$u->auth_version=1;$u->save();$this->actingAs($u)->withSession(['account_auth_version_'.$u->id=>0])->getJson('/data')->assertUnauthorized();$this->assertGuest();
 }
 public function test_device_list_is_scoped_and_never_exposes_session_credentials():void {
  config(['session.driver'=>'database']);$a=$this->account();$b=$this->account('devices@example.com');
  foreach([['private-session-secret',$a->id],['foreign-session-secret',$b->id]] as [$id,$uid])\Illuminate\Support\Facades\DB::table('sessions')->insert(['id'=>$id,'user_id'=>$uid,'payload'=>'','ip_address'=>'127.0.0.1','user_agent'=>'Test browser','last_activity'=>now()->timestamp]);
  $d=$this->actingAs($a)->getJson('/account/sessions')->assertOk()->assertJsonPath('supported',true)->json();
  $agents=array_values(array_filter($d['items'],fn($s)=>$s['agent']==='Test browser'));$this->assertCount(1,$agents);$this->assertSame(64,strlen($agents[0]['id']));$this->assertStringNotContainsString('private-session-secret',json_encode($d));$this->assertStringNotContainsString('foreign-session-secret',json_encode($d));
 }
 public function test_selected_device_revocation_requires_password_and_rejects_foreign_sessions():void {
  config(['session.driver'=>'database']);$a=$this->account();$b=$this->account('revoke@example.com');
  foreach([['own-device',$a->id],['foreign-device',$b->id]] as [$id,$uid])\Illuminate\Support\Facades\DB::table('sessions')->insert(['id'=>$id,'user_id'=>$uid,'payload'=>'','last_activity'=>now()->timestamp]);
  $own=hash_hmac('sha256','own-device',(string)config('app.key'));$foreign=hash_hmac('sha256','foreign-device',(string)config('app.key'));$this->actingAs($a);
  $this->postJson('/account/sessions/'.$own.'/revoke',['current_password'=>'wrong'])->assertUnprocessable();$this->assertDatabaseHas('sessions',['id'=>'own-device']);
  $this->postJson('/account/sessions/'.$foreign.'/revoke',['current_password'=>'example-password-123'])->assertNotFound();
  $this->postJson('/account/sessions/'.$own.'/revoke',['current_password'=>'example-password-123'])->assertOk()->assertJsonStructure(['user','csrf']);$this->assertDatabaseMissing('sessions',['id'=>'own-device']);$this->assertDatabaseHas('sessions',['id'=>'foreign-device']);$this->getJson('/account')->assertOk();
 }
 public function test_device_management_reports_unsupported_session_storage():void {
  config(['session.driver'=>'array']);$this->actingAs($this->account())->getJson('/account/sessions')->assertJsonPath('supported',false)->assertJsonCount(0,'items');
  $this->postJson('/account/sessions/unknown/revoke',['current_password'=>'example-password-123'])->assertStatus(409);
 }
 public function test_login_attempts_are_limited():void {
  $this->account();for($i=0;$i<6;$i++)$this->postJson('/login',['email'=>'one@example.com','password'=>'wrong'])->assertUnprocessable();
  $this->postJson('/login',['email'=>'one@example.com','password'=>'wrong'])->assertStatus(429);
 }
 private function transferDocument():array {return ['format'=>'sovdelo.transfer','schema_version'=>1,'exported_at'=>'2026-11-11T12:00:00+00:00','projects'=>[],'tasks'=>[]];}
 private function transferTask(string $title='Из файла'):array {return ['uuid'=>(string)\Illuminate\Support\Str::uuid(),'project_uuid'=>null,'title'=>$title,'description'=>null,'status'=>'todo','priority'=>'normal','due_date'=>null,'planned_date'=>null,'archived_at'=>null,'deleted_at'=>null,'checklist'=>[],'labels'=>[],'comments'=>[],'time'=>[]];}
 private function transferRequest(array $document,string $strategy='skip',?string $key=null):array {$payload=json_encode($document,JSON_UNESCAPED_UNICODE|JSON_THROW_ON_ERROR);return ['payload'=>$payload,'strategy'=>$strategy,'fingerprint'=>hash('sha256',$payload),'request_key'=>$key??(string)\Illuminate\Support\Str::uuid()];}
 public function test_transfer_export_is_scoped_and_contains_archive_trash_without_credentials():void {
  $a=$this->account();$b=$this->account('export@example.com');$p=Project::create(['user_id'=>$a->id,'name'=>'Мой проект']);$p->archived_at=now();$p->save();$t=Task::create(['user_id'=>$a->id,'project_id'=>$p->id,'title'=>'Корзина']);$t->delete();Task::create(['user_id'=>$b->id,'title'=>'Чужая']);
  $d=$this->actingAs($a)->getJson('/transfer/export')->assertOk()->assertJsonPath('format','sovdelo.transfer')->assertJsonPath('schema_version',2)->assertJsonCount(1,'projects')->assertJsonCount(1,'tasks')->json();
  $this->assertNotNull($d['tasks'][0]['deleted_at']);$this->assertNotNull($d['projects'][0]['archived_at']);$this->assertArrayNotHasKey('user_id',$d['tasks'][0]);$this->assertArrayNotHasKey('id',$d['tasks'][0]);$this->assertStringNotContainsString('password',json_encode($d));
 }
 public function test_transfer_round_trip_preserves_content_labels_comments_and_time():void {
  $a=$this->account();$b=$this->account('import@example.com');$p=Project::create(['user_id'=>$a->id,'name'=>'Дом']);$t=Task::create(['user_id'=>$a->id,'project_id'=>$p->id,'title'=>'Уборка','description'=>'Комната','planned_date'=>'2026-11-12','checklist'=>[['text'=>'Пол','done'=>true]]]);$label=\App\Models\Label::create(['user_id'=>$a->id,'name'=>'Дом','color'=>'green']);$t->labels()->attach($label);\App\Models\TaskComment::create(['user_id'=>$a->id,'task_id'=>$t->id,'body'=>'Комментарий']);
  \App\Models\TimeSession::create(['user_id'=>$a->id,'task_id'=>$t->id,'request_key'=>(string)\Illuminate\Support\Str::uuid(),'started_at'=>'2026-11-11 12:00:00','ended_at'=>'2026-11-11 12:05:00','duration_seconds'=>300,'end_reason'=>'stop']);
  $d=$this->actingAs($a)->getJson('/transfer/export')->assertOk()->json();$r=$this->transferRequest($d);$this->actingAs($b)->postJson('/transfer/preview',$r)->assertOk()->assertJsonPath('summary.create_tasks',1);$this->postJson('/transfer/import',$r)->assertOk()->assertJsonPath('created_tasks',1);
  $copy=Task::where('user_id',$b->id)->firstOrFail();$this->assertTrue($copy->checklist[0]['done']);$this->assertSame('Дом',$copy->labels->first()->name);$this->assertSame('Комментарий',$copy->comments->first()->body);$this->assertSame($b->id,$copy->comments->first()->user_id);$this->assertSame('Дом',$copy->project->name);$this->assertDatabaseHas('time_sessions',['user_id'=>$b->id,'task_id'=>$copy->id,'duration_seconds'=>300,'end_reason'=>'import']);$this->assertSame('Уборка',$t->fresh()->title);
 }
 public function test_transfer_skip_uses_identity_even_in_trash_and_copy_keeps_original():void {
  $u=$this->account();$t=Task::create(['user_id'=>$u->id,'title'=>'Оригинал']);$t->delete();$d=$this->actingAs($u)->getJson('/transfer/export')->assertOk()->json();$d['tasks'][0]['title']='Изменённый файл';
  $r=$this->transferRequest($d);$this->postJson('/transfer/preview',$r)->assertJsonPath('summary.duplicate_tasks',1)->assertJsonPath('summary.create_tasks',0);$this->postJson('/transfer/import',$r)->assertOk()->assertJsonPath('skipped_tasks',1);$this->assertSame('Оригинал',Task::withTrashed()->findOrFail($t->id)->title);
  $this->postJson('/transfer/import',$this->transferRequest($d,'copy'))->assertOk()->assertJsonPath('created_tasks',1);$this->assertDatabaseCount('tasks',2);$this->assertSame(2,Task::withTrashed()->where('user_id',$u->id)->distinct()->count('transfer_uuid'));
 }
 public function test_transfer_preview_has_no_side_effects_and_rejects_invalid_schema():void {
  $this->actingAs($this->account());$d=$this->transferDocument();$d['tasks'][]=$this->transferTask();$this->postJson('/transfer/preview',$this->transferRequest($d))->assertOk();$this->assertDatabaseCount('tasks',0);$this->assertDatabaseCount('projects',0);$this->assertDatabaseCount('import_batches',0);
  $d['schema_version']=99;$this->postJson('/transfer/preview',$this->transferRequest($d))->assertUnprocessable();
 }
 public function test_transfer_rejects_unknown_project_and_privileged_fields():void {
  $this->actingAs($this->account());$d=$this->transferDocument();$d['tasks'][]=$this->transferTask();$d['tasks'][0]['project_uuid']=(string)\Illuminate\Support\Str::uuid();$this->postJson('/transfer/import',$this->transferRequest($d))->assertUnprocessable();$this->assertDatabaseCount('tasks',0);
  $d['tasks'][0]['project_uuid']=null;$d['tasks'][0]['user_id']=123;$this->postJson('/transfer/import',$this->transferRequest($d))->assertUnprocessable();
 }
 public function test_transfer_copy_retry_is_idempotent_and_changed_file_requires_preview():void {
  $this->actingAs($this->account());$d=$this->transferDocument();$d['tasks'][]=$this->transferTask();$r=$this->transferRequest($d,'copy');$this->postJson('/transfer/import',$r)->assertOk();$this->postJson('/transfer/import',$r)->assertOk()->assertJsonPath('created_tasks',1);$this->assertDatabaseCount('tasks',1);$this->assertDatabaseCount('import_batches',1);
  $r['payload'].=' ';$this->postJson('/transfer/import',$r)->assertUnprocessable();$r['fingerprint']=hash('sha256',$r['payload']);$this->postJson('/transfer/import',$r)->assertUnprocessable();$this->assertDatabaseCount('tasks',1);
 }
 public function test_transfer_import_rolls_back_all_rows_on_runtime_failure():void {
  $this->actingAs($this->account());$d=$this->transferDocument();$d['projects'][]=['uuid'=>(string)\Illuminate\Support\Str::uuid(),'name'=>'Не должен сохраниться','archived_at'=>null];$d['tasks'][]=$this->transferTask('Первая');$d['tasks'][]=$this->transferTask('Сбой импорта');
  \Illuminate\Support\Facades\Event::listen('eloquent.creating: '.Task::class,function($task){if($task->title==='Сбой импорта')throw new \RuntimeException('transfer-test-failure');});
  $this->withoutExceptionHandling();try{$this->postJson('/transfer/import',$this->transferRequest($d));$this->fail('Ожидалась ошибка записи');}catch(\RuntimeException $e){$this->assertSame('transfer-test-failure',$e->getMessage());}
  $this->assertDatabaseCount('tasks',0);$this->assertDatabaseCount('projects',0);$this->assertDatabaseCount('import_batches',0);
 }
 public function test_transfer_active_time_is_snapshot_and_import_does_not_start_timer():void {
  $a=$this->account();$b=$this->account('timer-import@example.com');$this->travelTo(\Carbon\CarbonImmutable::parse('2026-11-11 12:00:00','UTC'));$t=Task::create(['user_id'=>$a->id,'title'=>'Таймер']);$this->actingAs($a)->postJson('/tasks/'.$t->id.'/timer',['request_key'=>(string)\Illuminate\Support\Str::uuid()])->assertOk();$this->travelTo(\Carbon\CarbonImmutable::parse('2026-11-11 12:01:30','UTC'));
  $d=$this->getJson('/transfer/export')->assertOk()->json();$this->assertSame(90,$d['tasks'][0]['time'][0]['seconds']);$this->assertDatabaseHas('time_sessions',['user_id'=>$a->id,'ended_at'=>null]);
  $this->actingAs($b)->postJson('/transfer/import',$this->transferRequest($d))->assertOk();$this->assertSame(0,\App\Models\TimeSession::where('user_id',$b->id)->whereNull('ended_at')->count());$this->assertDatabaseHas('time_sessions',['user_id'=>$b->id,'duration_seconds'=>90]);
 }
 public function test_transfer_guests_malformed_json_and_oversized_files_are_rejected():void {
  $this->getJson('/transfer/export')->assertUnauthorized();$this->postJson('/transfer/preview',[])->assertUnauthorized();$this->postJson('/transfer/import',[])->assertUnauthorized();$this->actingAs($this->account());
  $this->postJson('/transfer/preview',['payload'=>'{bad','strategy'=>'skip'])->assertUnprocessable();$this->postJson('/transfer/preview',['payload'=>str_repeat('x',5*1024*1024+1),'strategy'=>'skip'])->assertUnprocessable();
 }
 public function test_transfer_duplicate_uuid_and_invalid_time_are_rejected():void {
  $this->actingAs($this->account());$d=$this->transferDocument();$task=$this->transferTask();$d['tasks']=[$task,$task];$d['tasks'][1]['uuid']=strtoupper($task['uuid']);$this->postJson('/transfer/preview',$this->transferRequest($d))->assertUnprocessable();
  $d['tasks']=[$task];$d['tasks'][0]['time'][]=['started_at'=>'2026-11-11T12:00:00+00:00','ended_at'=>'2026-11-11T11:00:00+00:00','seconds'=>60,'end_reason'=>'stop','adjustments'=>[]];$this->postJson('/transfer/preview',$this->transferRequest($d))->assertUnprocessable();
 }
 private function boardSettings(int $uid):array {return app(\App\Services\BoardColumns::class)->all($uid)->map(fn($c)=>['key'=>$c->key,'name'=>$c->name,'kind'=>$c->kind])->all();}
 public function test_board_columns_can_be_added_renamed_reordered_and_are_private():void {
  $a=$this->account();$b=$this->account('columns@example.com');$this->actingAs($a);$rows=$this->boardSettings($a->id);$rows[0]['name']='Планы';$rows[]=['key'=>null,'name'=>'Проверка','kind'=>'doing'];$rows=[$rows[3],$rows[0],$rows[1],$rows[2]];
  $this->putJson('/board-columns',['columns'=>$rows])->assertOk()->assertJsonPath('columns.0.name','Проверка')->assertJsonPath('columns.1.name','Планы');$this->getJson('/data')->assertJsonCount(4,'columns')->assertJsonPath('columns.0.kind','doing');
  $this->actingAs($b)->getJson('/data')->assertJsonCount(3,'columns')->assertJsonPath('columns.0.name','К выполнению');
 }
 public function test_move_to_filled_custom_column_preserves_order_and_semantic_status():void {
  $u=$this->account();$this->actingAs($u);$key=(string)\Illuminate\Support\Str::uuid();\App\Models\BoardColumn::create(['user_id'=>$u->id,'key'=>$key,'name'=>'Ревью','kind'=>'doing','sort_order'=>4096]);$ids=[];foreach(['A','B','C'] as $title)$ids[]=$this->postJson('/tasks',['title'=>$title])->assertCreated()->json('id');
  $this->postJson('/tasks/'.$ids[1].'/move',['column'=>$key])->assertOk();$this->postJson('/tasks/'.$ids[2].'/move',['column'=>$key])->assertOk();$this->postJson('/tasks/'.$ids[0].'/move',['column'=>$key,'before_id'=>$ids[2]])->assertOk();
  $this->assertSame([$ids[1],$ids[0],$ids[2]],Task::where('user_id',$u->id)->where('board_column',$key)->orderBy('sort_order')->pluck('id')->all());$this->assertSame(3,Task::where('board_column',$key)->where('status','doing')->count());
  $this->postJson('/tasks/'.$ids[0].'/move',['column'=>$key,'before_id'=>$ids[2]])->assertOk();$this->assertDatabaseCount('tasks',3);
 }
 public function test_custom_completed_column_stops_timer_and_excludes_reminders():void {
  $u=$this->account();$this->actingAs($u);$this->travelTo(\Carbon\CarbonImmutable::parse('2026-11-11 12:00:00','UTC'));$key=(string)\Illuminate\Support\Str::uuid();\App\Models\BoardColumn::create(['user_id'=>$u->id,'key'=>$key,'name'=>'Выпущено','kind'=>'done','sort_order'=>4096]);$t=Task::create(['user_id'=>$u->id,'title'=>'Таймер','due_date'=>'2026-11-10']);$this->postJson('/tasks/'.$t->id.'/timer',['request_key'=>(string)\Illuminate\Support\Str::uuid()])->assertOk();
  $this->postJson('/tasks/'.$t->id.'/move',['column'=>$key])->assertOk();$this->assertSame('done',$t->fresh()->status);$this->assertSame(0,\App\Models\TimeSession::where('user_id',$u->id)->whereNull('ended_at')->count());$this->getJson('/notifications')->assertJsonCount(0,'items');
 }
 public function test_board_cannot_remove_used_columns_or_change_types_or_reference_foreign_column():void {
  $a=$this->account();$b=$this->account('foreign-column@example.com');$this->actingAs($a);$key=(string)\Illuminate\Support\Str::uuid();\App\Models\BoardColumn::create(['user_id'=>$a->id,'key'=>$key,'name'=>'Позже','kind'=>'todo','sort_order'=>4096]);$t=Task::create(['user_id'=>$a->id,'title'=>'Корзина']);$this->postJson('/tasks/'.$t->id.'/move',['column'=>$key])->assertOk();$this->deleteJson('/tasks/'.$t->id)->assertNoContent();
  $rows=$this->boardSettings($a->id);$this->putJson('/board-columns',['columns'=>array_values(array_filter($rows,fn($c)=>$c['key']!==$key))])->assertUnprocessable();$rows[0]['name']='Не должно сохраниться';$rows[0]['kind']='done';$this->putJson('/board-columns',['columns'=>$rows])->assertUnprocessable();$this->assertDatabaseHas('board_columns',['user_id'=>$a->id,'key'=>'todo','name'=>'К выполнению']);
  $own=Task::create(['user_id'=>$b->id,'title'=>'Другая']);$this->actingAs($b)->postJson('/tasks/'.$own->id.'/move',['column'=>$key])->assertUnprocessable();
 }
 public function test_task_modal_column_update_derives_status_and_keeps_column_on_text_edit():void {
  $u=$this->account();$this->actingAs($u);$key=(string)\Illuminate\Support\Str::uuid();\App\Models\BoardColumn::create(['user_id'=>$u->id,'key'=>$key,'name'=>'Проверка','kind'=>'doing','sort_order'=>4096]);$t=Task::create(['user_id'=>$u->id,'title'=>'Карточка']);
  $this->patchJson('/tasks/'.$t->id,['board_column'=>$key,'status'=>'todo','title'=>'Проверить'])->assertOk()->assertJsonPath('status','doing')->assertJsonPath('board_column',$key);$this->patchJson('/tasks/'.$t->id,['description'=>'Детали'])->assertOk()->assertJsonPath('board_column',$key);$this->patchJson('/tasks/'.$t->id,['status'=>'done'])->assertOk()->assertJsonPath('board_column','done');
 }
 public function test_transfer_v2_preserves_custom_columns_and_v1_still_imports():void {
  $a=$this->account();$b=$this->account('columns-transfer@example.com');$this->actingAs($a);$key=(string)\Illuminate\Support\Str::uuid();\App\Models\BoardColumn::create(['user_id'=>$a->id,'key'=>$key,'name'=>'Ревью','kind'=>'doing','sort_order'=>4096]);$t=Task::create(['user_id'=>$a->id,'title'=>'Передать']);$this->postJson('/tasks/'.$t->id.'/move',['column'=>$key])->assertOk();
  $d=$this->getJson('/transfer/export')->assertOk()->assertJsonPath('schema_version',2)->json();$this->actingAs($b)->postJson('/transfer/import',$this->transferRequest($d))->assertOk();$this->assertDatabaseHas('board_columns',['user_id'=>$b->id,'key'=>$key,'kind'=>'doing']);$this->assertDatabaseHas('tasks',['user_id'=>$b->id,'board_column'=>$key,'status'=>'doing']);
  $old=$this->transferDocument();$old['tasks'][]=$this->transferTask('Версия 1');$this->postJson('/transfer/import',$this->transferRequest($old))->assertOk();$this->assertDatabaseHas('tasks',['user_id'=>$b->id,'title'=>'Версия 1','board_column'=>'todo']);
 }
 public function test_start_timer_moves_custom_todo_to_default_working_column():void {
  $u=$this->account();$this->actingAs($u);$key=(string)\Illuminate\Support\Str::uuid();\App\Models\BoardColumn::create(['user_id'=>$u->id,'key'=>$key,'name'=>'Ожидание','kind'=>'todo','sort_order'=>4096]);$t=Task::create(['user_id'=>$u->id,'title'=>'Начать']);$this->postJson('/tasks/'.$t->id.'/move',['column'=>$key])->assertOk();$this->postJson('/tasks/'.$t->id.'/timer',['request_key'=>(string)\Illuminate\Support\Str::uuid()])->assertOk();$this->assertDatabaseHas('tasks',['id'=>$t->id,'board_column'=>'doing','status'=>'doing']);
 }
}

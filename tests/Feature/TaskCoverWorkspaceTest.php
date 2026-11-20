<?php
namespace Tests\Feature;
use App\Models\{User,Task,TaskAttachment};
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use Tests\TestCase;
class TaskCoverWorkspaceTest extends TestCase {
 use RefreshDatabase;
 private const PNG='iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGOwWFz+HwAEuwJScO11XwAAAABJRU5ErkJggg==';
 private function fixture():array {Storage::fake('local');$u=User::create(['name'=>'Роман','email'=>'cover@example.com','password'=>'example-password-123'])->fresh();$t=Task::create(['user_id'=>$u->id,'title'=>'Обложка']);$this->actingAs($u);return [$u,$t];}
 private function image(string $name='cover.png'):UploadedFile{return UploadedFile::fake()->createWithContent($name,base64_decode(self::PNG));}
 private function upload(Task $task,string $name='cover.png'):int{return $this->postJson('/tasks/'.$task->id.'/attachments',['file'=>$this->image($name)])->assertSuccessful()->json('id');}
 private function cover(Task $task,?int $id){return $this->putJson('/tasks/'.$task->id.'/cover',['attachment_id'=>$id,'expected_version'=>$task->fresh()->version]);}
 public function test_first_image_is_automatic_and_another_upload_preserves_choice():void {
  [$u,$t]=$this->fixture();$first=$this->upload($t);$second=$this->upload($t,'second.png');
  $this->assertSame($first,$t->fresh()->cover_attachment_id);$this->assertNotSame($first,$second);
  $this->getJson('/data')->assertOk()->assertJsonPath('tasks.0.cover.id',$first);
  $this->getJson('/tasks/'.$t->id.'/details')->assertOk()->assertJsonPath('attachments.0.is_image',true);
 }
 public function test_removing_cover_preserves_file_and_stays_removed_after_upload():void {
  [$u,$t]=$this->fixture();$id=$this->upload($t);$path=TaskAttachment::findOrFail($id)->path;
  $this->cover($t,null)->assertOk()->assertJsonPath('cover',null)->assertJsonPath('cover_disabled',true);
  Storage::disk('local')->assertExists($path);$this->assertDatabaseHas('task_attachments',['id'=>$id]);
  $this->upload($t,'another.png');$this->assertNull($t->fresh()->cover_attachment_id);
  $this->cover($t,$id)->assertOk()->assertJsonPath('cover.id',$id)->assertJsonPath('cover_disabled',false);
 }
 public function test_cover_can_be_changed_and_survives_reload():void {
  [$u,$t]=$this->fixture();$first=$this->upload($t);$second=$this->upload($t,'another.png');
  $this->cover($t,$second)->assertOk()->assertJsonPath('cover.id',$second);
  $this->getJson('/data')->assertOk()->assertJsonPath('tasks.0.cover.id',$second);
  $this->assertDatabaseHas('task_attachments',['id'=>$first]);
  $this->deleteJson('/tasks/'.$t->id.'/attachments/'.$first)->assertNoContent();$this->assertSame($second,$t->fresh()->cover_attachment_id);
 }
 public function test_documents_are_not_cover_images_even_with_an_image_name():void {
  [$u,$t]=$this->fixture();$file=UploadedFile::fake()->create('not-image.png',1,'application/pdf');
  $id=$this->postJson('/tasks/'.$t->id.'/attachments',['file'=>$file])->assertSuccessful()->assertJsonPath('is_image',false)->json('id');
  $this->assertNull($t->fresh()->cover_attachment_id);$this->cover($t,$id)->assertUnprocessable();
  $this->getJson('/tasks/'.$t->id.'/attachments/'.$id.'/preview')->assertNotFound();
 }
 public function test_old_image_attachment_can_be_chosen_after_metadata_inspection():void {
  [$u,$t]=$this->fixture();Storage::disk('local')->put('old/image.png',base64_decode(self::PNG));
  $file=TaskAttachment::create(['task_id'=>$t->id,'name'=>'Старое изображение.png','path'=>'old/image.png','bytes'=>strlen(base64_decode(self::PNG))]);
  $this->getJson('/tasks/'.$t->id.'/details')->assertOk()->assertJsonPath('attachments.0.is_image',true);
  $this->cover($t,$file->id)->assertOk()->assertJsonPath('cover.id',$file->id);
 }
 public function test_preview_checks_ownership_and_has_safe_inline_headers():void {
  [$u,$t]=$this->fixture();$id=$this->upload($t);
  $this->get('/tasks/'.$t->id.'/attachments/'.$id.'/preview')->assertOk()->assertHeader('Content-Type','image/png')->assertHeader('X-Content-Type-Options','nosniff');
  $response=$this->get('/tasks/'.$t->id.'/attachments/'.$id.'/preview');
  $this->assertStringStartsWith('inline',$response->headers->get('Content-Disposition'));
  $this->assertStringContainsString('private',$response->headers->get('Cache-Control'));
  $other=User::create(['name'=>'Другой','email'=>'other-cover@example.com','password'=>'example-password-123']);
  $this->actingAs($other)->getJson('/tasks/'.$t->id.'/attachments/'.$id.'/preview')->assertNotFound();
  $this->cover($t,$id)->assertNotFound();
 }
 public function test_cannot_choose_attachment_of_another_task():void {
  [$u,$t]=$this->fixture();$id=$this->upload($t);$other=Task::create(['user_id'=>$u->id,'title'=>'Другая']);
  $this->cover($other,$id)->assertNotFound();$this->assertNull($other->fresh()->cover_attachment_id);
 }
 public function test_deleting_cover_attachment_clears_cover_without_selecting_another():void {
  [$u,$t]=$this->fixture();$id=$this->upload($t);$next=$this->upload($t,'next.png');
  $this->deleteJson('/tasks/'.$t->id.'/attachments/'.$id)->assertNoContent();
  $this->assertNull($t->fresh()->cover_attachment_id);$this->assertTrue($t->fresh()->cover_disabled);
  $this->assertDatabaseHas('task_attachments',['id'=>$next]);
 }
 public function test_stale_cover_selection_does_not_overwrite_new_choice():void {
  [$u,$t]=$this->fixture();$id=$this->upload($t);$version=$t->fresh()->version;$this->cover($t,null)->assertOk();
  $this->putJson('/tasks/'.$t->id.'/cover',['attachment_id'=>$id,'expected_version'=>$version])->assertConflict();$this->assertNull($t->fresh()->cover_attachment_id);
 }
 public function test_api_upload_retry_does_not_restore_a_removed_cover():void {
  [$u,$t]=$this->fixture();$issued=$u->createToken('Android',['workspace:read','workspace:write'],now()->addDay());$issued->accessToken->auth_version=$u->auth_version;$issued->accessToken->save();
  $key=(string)Str::uuid();$body=['operation_uuid'=>$key,'name'=>'photo.png','sha256'=>hash('sha256',base64_decode(self::PNG))];
  $headers=['Authorization'=>'Bearer '.$issued->plainTextToken,'Accept'=>'application/json'];
  // Match the existing WorkspaceTest multipart API helper: discard cached web/Sanctum guards.
  $this->app['auth']->forgetGuards();
  $id=$this->post('/api/v1/tasks/'.$t->id.'/attachments',$body+['file'=>$this->image('photo.png')],$headers)->assertCreated()->json('data.attachment.id');
  $this->assertSame($id,$t->fresh()->cover_attachment_id);
  $this->app['auth']->forgetGuards();$this->actingAs($u->fresh(),'web');$this->cover($t,null)->assertOk();
  $this->app['auth']->forgetGuards();
  $this->post('/api/v1/tasks/'.$t->id.'/attachments',$body+['file'=>$this->image('photo.png')],$headers)->assertCreated()->assertJsonPath('data.attachment.id',$id);
  $this->assertNull($t->fresh()->cover_attachment_id);$this->assertDatabaseCount('task_attachments',1);
 }
 public function test_guest_cannot_read_preview_or_change_cover():void {
  $u=User::create(['name'=>'Владелец','email'=>'guest-cover@example.com','password'=>'example-password-123']);$t=Task::create(['user_id'=>$u->id,'title'=>'Приватная']);
  $this->getJson('/tasks/'.$t->id.'/attachments/1/preview')->assertUnauthorized();
  $this->putJson('/tasks/'.$t->id.'/cover',['attachment_id'=>null,'expected_version'=>1])->assertUnauthorized();
 }
}

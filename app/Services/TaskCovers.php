<?php
namespace App\Services;
use App\Models\{Task,TaskAttachment};
use Illuminate\Support\Facades\Storage;
class TaskCovers {
 public const MIMES=['image/jpeg','image/png','image/webp','image/gif'];
 private function metadata(string $path):array {
  $size=@getimagesize($path);
  if(!$size||!in_array($size['mime']??null,self::MIMES,true)||$size[0]<1||$size[1]<1)return ['mime_type'=>'application/octet-stream','image_width'=>null,'image_height'=>null];
  return ['mime_type'=>$size['mime'],'image_width'=>$size[0],'image_height'=>$size[1]];
 }
 public function inspect(TaskAttachment $file):TaskAttachment {
  if($file->mime_type!==null)return $file;
  $disk=Storage::disk('local');
  if(!$disk->exists($file->path))return $file;
  $file->forceFill($this->metadata($disk->path($file->path)))->save();return $file;
 }
 /** Caller holds the owner's row lock and transaction. Only the first image is automatic. */
 public function uploaded(Task $task,TaskAttachment $file):void {
  $this->inspect($file);
  if($file->is_image&&!$task->cover_disabled&&!$task->cover_attachment_id){$task->cover_attachment_id=$file->id;$task->save();}
 }
 public function choose(Task $task,?int $attachment):Task {
  if($attachment!==null){$file=$this->inspect($task->attachments()->findOrFail($attachment));abort_unless($file->is_image&&Storage::disk('local')->exists($file->path),422,'Этот файл нельзя использовать как обложку.');}
  $task->cover_attachment_id=$attachment;$task->cover_disabled=$attachment===null;
  if($task->isDirty())$task->save();return $task->fresh();
 }
 public function deleting(Task $task,TaskAttachment $file):void {
  if((int)$task->cover_attachment_id===(int)$file->id){$task->cover_attachment_id=null;$task->cover_disabled=true;$task->save();}
 }
}

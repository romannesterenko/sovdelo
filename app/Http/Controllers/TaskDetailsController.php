<?php
namespace App\Http\Controllers;
use App\Models\{User,Task,Label,TaskComment,TaskAttachment};
use Illuminate\Http\Request;
use Illuminate\Support\Facades\{DB,Storage};
use Illuminate\Validation\Rule;
class TaskDetailsController
{
 private function owned(Request $r,int $id):Task {return Task::where('user_id',$r->user()->id)->findOrFail($id);}
 private function locked(Request $r,int $id,callable $fn):mixed {return DB::transaction(function()use($r,$id,$fn){User::whereKey($r->user()->id)->lockForUpdate()->firstOrFail();return $fn($this->owned($r,$id));});}
 public function show(Request $r,int $task){
  $t=$this->owned($r,$task);
  return ['task'=>$t,'comments'=>DB::table('task_comments')->join('users','users.id','=','task_comments.user_id')->where('task_id',$t->id)->orderBy('task_comments.id')->get(['task_comments.id','task_comments.body','task_comments.created_at','task_comments.updated_at','users.name as author']),'attachments'=>$t->attachments()->orderBy('id')->get()];
 }
 public function labels(Request $r){return Label::where('user_id',$r->user()->id)->orderBy('name')->get();}
 public function createLabel(Request $r){
  $d=$r->validate(['name'=>['required','string','max:40',Rule::unique('labels')->where('user_id',$r->user()->id)],'color'=>['required',Rule::in(['green','blue','purple','orange','red','gray'])]]);
  return Label::create($d+['user_id'=>$r->user()->id]);
 }
 public function setLabels(Request $r,int $task){
  $d=$r->validate(['ids'=>'present|array|max:20','ids.*'=>['required','integer','distinct',Rule::exists('labels','id')->where('user_id',$r->user()->id)]]);
  return $this->locked($r,$task,function($t)use($d){$t->labels()->sync($d['ids']);return $t->fresh();});
 }
 public function comment(Request $r,int $task){
  $d=$r->validate(['body'=>'required|string|max:10000']);
  return $this->locked($r,$task,fn($t)=>TaskComment::create($d+['task_id'=>$t->id,'user_id'=>$r->user()->id]));
 }
 public function editComment(Request $r,int $task,int $comment){
  $d=$r->validate(['body'=>'required|string|max:10000']);
  return $this->locked($r,$task,function($t)use($r,$comment,$d){$c=$t->comments()->where('user_id',$r->user()->id)->findOrFail($comment);$c->update($d);return $c;});
 }
 public function deleteComment(Request $r,int $task,int $comment){
  $this->locked($r,$task,fn($t)=>$t->comments()->where('user_id',$r->user()->id)->findOrFail($comment)->delete());return response()->noContent();
 }
 public function upload(Request $r,int $task){
  $this->owned($r,$task);
  $r->validate(['file'=>'required|file|max:10240|mimes:pdf,txt,csv,jpg,jpeg,png,webp,zip,doc,docx,xls,xlsx']);
  $path=null;
  try{return $this->locked($r,$task,function($t)use($r,&$path){
   abort_if($t->attachments()->count()>=50,422,'Максимум 50 файлов на задачу.');
   $bytes=(int)$r->file('file')->getSize();
   $total=TaskAttachment::whereIn('task_id',Task::where('user_id',$r->user()->id)->select('id'))->sum('bytes');
   abort_if($total+$bytes>250*1024*1024,422,'Превышен лимит вложений аккаунта: 250 МБ.');
   $path=$r->file('file')->store('task-files/'.$r->user()->id,'local');
   if(!$path)throw new \RuntimeException('Не удалось сохранить файл.');
   $name=mb_substr(str_replace(array_map('chr',array_merge(range(0,31),[47,92,127])),'_',$r->file('file')->getClientOriginalName()),0,240);
   return TaskAttachment::create(['task_id'=>$t->id,'name'=>$name?:'file','path'=>$path,'bytes'=>$bytes]);
  });}catch(\Throwable $e){if($path)Storage::disk('local')->delete($path);throw $e;}
 }
 public function download(Request $r,int $task,int $attachment){
  $a=$this->owned($r,$task)->attachments()->findOrFail($attachment);abort_unless(Storage::disk('local')->exists($a->path),404);
  return Storage::disk('local')->download($a->path,$a->name,['Content-Type'=>'application/octet-stream','X-Content-Type-Options'=>'nosniff','Cache-Control'=>'private, no-store']);
 }
 public function deleteFile(Request $r,int $task,int $attachment){
  $this->locked($r,$task,function($t)use($attachment){$a=$t->attachments()->findOrFail($attachment);$path=$a->path;$a->delete();DB::afterCommit(fn()=>Storage::disk('local')->delete($path));});return response()->noContent();
 }
}

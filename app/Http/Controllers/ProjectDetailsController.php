<?php
namespace App\Http\Controllers;
use App\Models\{User,Project,ProjectAttachment,ProjectCredential,Task,TaskAttachment};
use App\Services\TaskCovers;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\{DB,Storage};
use Illuminate\Validation\Rule;
class ProjectDetailsController {
 private function owned(Request $r,int $id):Project {return Project::where('user_id',$r->user()->id)->findOrFail($id);}
 private function mutate(Request $r,int $id,callable $fn):mixed {
  $r->validate(['expected_version'=>'required|integer|min:1']);
  return DB::transaction(function()use($r,$id,$fn){
   User::whereKey($r->user()->id)->lockForUpdate()->firstOrFail();$p=$this->owned($r,$id);
   abort_if($p->archived_at,422,'Сначала восстановите проект из архива.');
   abort_unless((int)$p->version===(int)$r->input('expected_version'),409,'Проект уже изменился. Закройте и откройте его заново, чтобы получить актуальные данные.');
   return $fn($p);
  },1);
 }
 // Explicit bump also covers attachment/credential changes with unchanged project attributes.
 private function saveProject(Project $p):void {$p->version=(int)$p->version+1;$p->saveQuietly();}
 private function noStore(array $data){return response()->json($data,200,['Cache-Control'=>'private, no-store']);}
 public function show(Request $r,int $project){
  $p=$this->owned($r,$project);
  return $this->noStore(['project'=>['id'=>$p->id,'name'=>$p->name,'description'=>$p->description,'version'=>$p->version,'archived_at'=>$p->archived_at,'cover_attachment_id'=>$p->cover_attachment_id],
   'files'=>ProjectAttachment::where('project_id',$p->id)->orderBy('id')->get(),
   'credentials'=>ProjectCredential::where('project_id',$p->id)->orderBy('id')->get()]);
 }
 public function update(Request $r,int $project){
  $d=$r->validate(['name'=>'required|string|max:120','description'=>'nullable|string|max:30000']);
  $this->mutate($r,$project,function($p)use($d){$p->fill($d);$this->saveProject($p);});return response()->noContent();
 }
 public function upload(Request $r,int $project){
  $this->owned($r,$project);$r->validate(['file'=>'required|file|max:10240|mimes:pdf,txt,csv,jpg,jpeg,png,webp,gif,zip,doc,docx,xls,xlsx']);$path=null;
  try{$this->mutate($r,$project,function($p)use($r,&$path){
   abort_if(ProjectAttachment::where('project_id',$p->id)->count()>=50,422,'Максимум 50 файлов на проект.');
   $bytes=(int)$r->file('file')->getSize();
   $total=ProjectAttachment::whereIn('project_id',Project::where('user_id',$r->user()->id)->select('id'))->sum('bytes')+TaskAttachment::whereIn('task_id',Task::withTrashed()->where('user_id',$r->user()->id)->select('id'))->sum('bytes');
   abort_if($total+$bytes>250*1024*1024,422,'Превышен общий лимит вложений аккаунта: 250 МБ.');
   $path=$r->file('file')->store('project-files/'.$r->user()->id,'local');if(!$path)throw new \RuntimeException('Не удалось сохранить файл.');
   $image=@getimagesize(Storage::disk('local')->path($path));$mime=$image&&in_array($image['mime']??null,TaskCovers::MIMES,true)?$image['mime']:null;
   $name=mb_substr(str_replace(array_map('chr',array_merge(range(0,31),[47,92,127])),'_',$r->file('file')->getClientOriginalName()),0,240);
   $file=ProjectAttachment::create(['project_id'=>$p->id,'name'=>$name?:'file','path'=>$path,'bytes'=>$bytes,'image_mime'=>$mime]);
   if($mime&&!$p->cover_disabled&&!$p->cover_attachment_id)$p->cover_attachment_id=$file->id;
   $this->saveProject($p);
  });}catch(\Throwable $e){if($path)Storage::disk('local')->delete($path);throw $e;}
  return response()->noContent();
 }
 public function cover(Request $r,int $project){
  $d=$r->validate(['attachment_id'=>'present|nullable|integer|min:1']);
  $this->mutate($r,$project,function($p)use($d){if($d['attachment_id']!==null){$a=ProjectAttachment::where('project_id',$p->id)->findOrFail($d['attachment_id']);abort_unless($a->image_mime&&Storage::disk('local')->exists($a->path),422,'Выберите изображение из файлов проекта.');}$p->cover_attachment_id=$d['attachment_id'];$p->cover_disabled=$d['attachment_id']===null;$this->saveProject($p);});return response()->noContent();
 }
 private function file(Request $r,int $project,int $file):ProjectAttachment {$p=$this->owned($r,$project);return ProjectAttachment::where('project_id',$p->id)->findOrFail($file);}
 public function download(Request $r,int $project,int $file){$a=$this->file($r,$project,$file);abort_unless(Storage::disk('local')->exists($a->path),404);return Storage::disk('local')->download($a->path,$a->name,['Content-Type'=>'application/octet-stream','X-Content-Type-Options'=>'nosniff','Cache-Control'=>'private, no-store']);}
 public function preview(Request $r,int $project,int $file){$a=$this->file($r,$project,$file);abort_unless($a->image_mime&&Storage::disk('local')->exists($a->path),404);return Storage::disk('local')->response($a->path,$a->name,['Content-Type'=>$a->image_mime,'X-Content-Type-Options'=>'nosniff','Cache-Control'=>'private, no-store','Content-Security-Policy'=>"default-src 'none'; sandbox"],'inline');}
 public function deleteFile(Request $r,int $project,int $file){$this->mutate($r,$project,function($p)use($file){$a=ProjectAttachment::where('project_id',$p->id)->findOrFail($file);if((int)$p->cover_attachment_id===$a->id){$p->cover_attachment_id=null;$p->cover_disabled=true;}$path=$a->path;$a->delete();$this->saveProject($p);DB::afterCommit(fn()=>Storage::disk('local')->delete($path));});return response()->noContent();}
 private function credentialData(Request $r,bool $create):array {
  $d=$r->validate(['name'=>'required|string|max:120','kind'=>['required',Rule::in(['site','server','other'])],'address'=>'nullable|string|max:500','username'=>'nullable|string|max:240','secret'=>'nullable|string|max:20000','notes'=>'nullable|string|max:10000']);
  if(!$create&&(($d['secret']??null)===null||$d['secret']===''))unset($d['secret']);return $d;
 }
 public function addCredential(Request $r,int $project){$d=$this->credentialData($r,true);$this->mutate($r,$project,function($p)use($d){abort_if(ProjectCredential::where('project_id',$p->id)->count()>=100,422,'Максимум 100 записей доступа на проект.');ProjectCredential::create($d+['project_id'=>$p->id]);$this->saveProject($p);});return response()->noContent();}
 public function updateCredential(Request $r,int $project,int $credential){$d=$this->credentialData($r,false);$this->mutate($r,$project,function($p)use($d,$credential){ProjectCredential::where('project_id',$p->id)->findOrFail($credential)->update($d);$this->saveProject($p);});return response()->noContent();}
 public function deleteCredential(Request $r,int $project,int $credential){$this->mutate($r,$project,function($p)use($credential){ProjectCredential::where('project_id',$p->id)->findOrFail($credential)->delete();$this->saveProject($p);});return response()->noContent();}
 public function reveal(Request $r,int $project,int $credential){$p=$this->owned($r,$project);$a=ProjectCredential::where('project_id',$p->id)->findOrFail($credential);return $this->noStore(['secret'=>$a->secret]);}
}

<?php
namespace App\Http\Controllers\Api;
use App\Models\{Task,TaskAttachment,User};
use App\Services\ApiData;
use App\Services\TaskCovers;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\{DB,Storage};

class AttachmentsController
{
 private function owned(Request $r,int $id):Task {return Task::where('user_id',$r->user()->id)->findOrFail($id);}
 private function data(TaskAttachment $a):array {return ['id'=>(int)$a->id,'uuid'=>$a->client_uuid,'name'=>$a->name,'bytes'=>(int)$a->bytes,'sha256'=>$a->sha256,'created_at'=>$a->created_at?->toIso8601String()??''];}
 public function index(Request $r,int $task){$t=$this->owned($r,$task);return ApiData::response($t->attachments()->orderBy('id')->get()->map(fn($a)=>$this->data($a)));}
 public function download(Request $r,int $task,int $attachment){
  $a=$this->owned($r,$task)->attachments()->findOrFail($attachment);$disk=Storage::disk('local');abort_unless($disk->exists($a->path),404);
  $sha=$a->sha256?:hash_file('sha256',$disk->path($a->path));
  return $disk->download($a->path,$a->name,['Content-Type'=>'application/octet-stream','X-Content-Type-Options'=>'nosniff','Cache-Control'=>'private, no-store','X-File-SHA256'=>$sha]);
 }
 public function upload(Request $r,int $task){
  $d=$r->validate(['operation_uuid'=>'required|uuid','name'=>'required|string|max:240','sha256'=>'required|regex:/^[a-f0-9]{64}$/','file'=>'required|file|max:10240|mimes:pdf,txt,csv,jpg,jpeg,png,webp,gif,zip,doc,docx,xls,xlsx']);
  $name=mb_substr(str_replace(array_map('chr',array_merge(range(0,31),[47,92,127])),'_',$d['name']),0,240);
  abort_unless(in_array(strtolower(pathinfo($name,PATHINFO_EXTENSION)),['pdf','txt','csv','jpg','jpeg','png','webp','gif','zip','doc','docx','xls','xlsx'],true),422,'Тип файла не поддерживается.');
  $file=$r->file('file');$bytes=(int)$file->getSize();abort_if($bytes<1,422,'Пустой файл.');$sha=hash_file('sha256',$file->getRealPath());
  abort_unless(hash_equals($d['sha256'],$sha),422,'Контрольная сумма файла не совпала.');
  $hash=hash('sha256',json_encode(['upload-v1',$task,$name,$bytes,$sha],JSON_THROW_ON_ERROR));$path=null;
  try {
   // No automatic transaction retries: a failed attempt must not leave a second stored blob.
   return DB::transaction(function()use($r,$task,$d,$name,$bytes,$sha,$hash,$file,&$path){
    $uid=$r->user()->id;User::whereKey($uid)->lockForUpdate()->firstOrFail();
    $old=DB::table('api_requests')->where('user_id',$uid)->where('request_key',$d['operation_uuid'])->first();
    if($old){abort_unless(hash_equals($old->fingerprint,$hash),409,'UUID уже использован для другого файла.');return ApiData::response(json_decode($old->result,true),$old->status);}
    $t=$this->owned($r,$task);abort_if($t->attachments()->count()>=50,422,'Максимум 50 файлов на задачу.');
    $projectBytes=\App\Models\ProjectAttachment::whereIn('project_id',\App\Models\Project::where('user_id',$uid)->select('id'))->sum('bytes');
    $total=$projectBytes+TaskAttachment::whereIn('task_id',Task::withTrashed()->where('user_id',$uid)->select('id'))->sum('bytes');
    abort_if($total+$bytes>250*1024*1024,422,'Превышен лимит аккаунта: 250 МБ.');
    $path=$file->store('task-files/'.$uid,'local');if(!$path)throw new \RuntimeException('Не удалось сохранить файл.');
    $a=new TaskAttachment(['task_id'=>$t->id,'name'=>$name,'path'=>$path,'bytes'=>$bytes]);$a->client_uuid=$d['operation_uuid'];$a->sha256=$sha;$a->save();app(TaskCovers::class)->uploaded($t,$a);
    $result=['operation_uuid'=>$d['operation_uuid'],'attachment'=>$this->data($a)];
    DB::table('api_requests')->insert(['user_id'=>$uid,'request_key'=>$d['operation_uuid'],'fingerprint'=>$hash,'result'=>json_encode($result,JSON_THROW_ON_ERROR),'status'=>201,'created_at'=>now(),'updated_at'=>now()]);
    return ApiData::response($result,201);
   },1);
  }catch(\Throwable $e){if($path)Storage::disk('local')->delete($path);throw $e;}
 }
}

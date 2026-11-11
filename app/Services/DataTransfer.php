<?php
namespace App\Services;
use App\Models\{Project,Task,Label,TaskComment,TimeSession};
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\{DB,Validator};
use Illuminate\Support\Str;
use Illuminate\Validation\{Rule,ValidationException};
class DataTransfer {
 private function fail(string $message):never {throw ValidationException::withMessages(['payload'=>$message]);}
 public function parse(string $payload):array {
  if(strlen($payload)>5*1024*1024)$this->fail('Максимальный размер JSON — 5 МБ.');
  try{$d=json_decode($payload,true,64,JSON_THROW_ON_ERROR);}catch(\JsonException){$this->fail('Некорректный JSON.');}
  if(!is_array($d)||!isset($d['projects'],$d['tasks'])||!is_array($d['projects'])||!is_array($d['tasks'])||!array_is_list($d['projects'])||!array_is_list($d['tasks']))$this->fail('Ожидается файл переноса СовДело с массивами projects и tasks.');
  $records=count($d['tasks'])+count($d['projects']);foreach($d['projects'] as $project)if(!is_array($project))$this->fail('Некорректный проект.');foreach($d['tasks'] as $t){if(!is_array($t))$this->fail('Некорректная задача.');foreach(['comments','time','labels','checklist'] as $key){if(isset($t[$key])&&!is_array($t[$key]))$this->fail('Некорректный список '.$key);$records+=count($t[$key]??[]);}foreach($t['time']??[] as $session){if(!is_array($session))$this->fail('Некорректная сессия времени.');if(isset($session['adjustments'])&&!is_array($session['adjustments']))$this->fail('Некорректная история корректировок.');$records+=count($session['adjustments']??[]);}}
  if($records>20000)$this->fail('В файле более 20 000 записей. Разделите перенос на несколько файлов.');
  foreach($d['projects'] as &$row)if(isset($row['uuid'])&&is_string($row['uuid']))$row['uuid']=strtolower($row['uuid']);unset($row);foreach($d['tasks'] as &$row){foreach(['uuid','project_uuid'] as $field)if(isset($row[$field])&&is_string($row[$field]))$row[$field]=strtolower($row[$field]);}unset($row);
  $v=Validator::make(['document'=>$d],[
   'document'=>'required|array:format,schema_version,exported_at,notes,projects,tasks',
   'document.format'=>['required',Rule::in(['sovdelo.transfer'])],'document.schema_version'=>['required','integer',Rule::in([1])],
   'document.exported_at'=>'required|date','document.notes'=>'sometimes|array|max:20','document.notes.*'=>'string|max:1000',
   'document.projects'=>'present|array|max:200','document.projects.*'=>'required|array:uuid,name,archived_at',
   'document.projects.*.uuid'=>'required|uuid|distinct','document.projects.*.name'=>'required|string|max:120','document.projects.*.archived_at'=>'present|nullable|date',
   'document.tasks'=>'present|array|max:1000','document.tasks.*'=>'required|array:uuid,project_uuid,title,description,status,priority,due_date,planned_date,checklist,labels,comments,time,archived_at,deleted_at',
   'document.tasks.*.uuid'=>'required|uuid|distinct','document.tasks.*.project_uuid'=>'present|nullable|uuid','document.tasks.*.title'=>'required|string|max:240',
   'document.tasks.*.description'=>'present|nullable|string|max:20000','document.tasks.*.status'=>['required',Rule::in(['todo','doing','done'])],'document.tasks.*.priority'=>['required',Rule::in(['normal','high'])],
   'document.tasks.*.due_date'=>'present|nullable|date_format:Y-m-d','document.tasks.*.planned_date'=>'present|nullable|date_format:Y-m-d','document.tasks.*.archived_at'=>'present|nullable|date','document.tasks.*.deleted_at'=>'present|nullable|date',
   'document.tasks.*.checklist'=>'present|array|max:100','document.tasks.*.checklist.*'=>'required|array:text,done','document.tasks.*.checklist.*.text'=>'required|string|max:500','document.tasks.*.checklist.*.done'=>'required|boolean',
   'document.tasks.*.labels'=>'present|array|max:20','document.tasks.*.labels.*'=>'required|array:name,color','document.tasks.*.labels.*.name'=>'required|string|max:40','document.tasks.*.labels.*.color'=>['required',Rule::in(['green','blue','purple','orange','red','gray'])],
   'document.tasks.*.comments'=>'present|array|max:1000','document.tasks.*.comments.*'=>'required|array:body,created_at','document.tasks.*.comments.*.body'=>'required|string|max:10000','document.tasks.*.comments.*.created_at'=>'required|date',
   'document.tasks.*.time'=>'present|array|max:1000','document.tasks.*.time.*'=>'required|array:started_at,ended_at,seconds,end_reason,adjustments',
   'document.tasks.*.time.*.started_at'=>'required|date','document.tasks.*.time.*.ended_at'=>'required|date','document.tasks.*.time.*.seconds'=>'required|integer|min:0|max:315576000','document.tasks.*.time.*.end_reason'=>'present|nullable|string|max:24',
   'document.tasks.*.time.*.adjustments'=>'present|array|max:100','document.tasks.*.time.*.adjustments.*'=>'required|array:previous_seconds,new_seconds,reason,created_at','document.tasks.*.time.*.adjustments.*.previous_seconds'=>'required|integer|min:0|max:315576000','document.tasks.*.time.*.adjustments.*.new_seconds'=>'required|integer|min:0|max:315576000','document.tasks.*.time.*.adjustments.*.reason'=>'required|string|max:500','document.tasks.*.time.*.adjustments.*.created_at'=>'required|date',
  ]);$v->validate();
  $projects=array_fill_keys(array_column($d['projects'],'uuid'),true);
  foreach($d['tasks'] as $t){if($t['project_uuid']!==null&&!isset($projects[$t['project_uuid']]))$this->fail('Проект задачи отсутствует в файле.');foreach(['checklist','labels','comments','time'] as $key)if(!array_is_list($t[$key]))$this->fail('Ожидается последовательный список '.$key);foreach($t['time'] as $s){if(!array_is_list($s['adjustments']))$this->fail('Некорректный список корректировок.');if(CarbonImmutable::parse($s['ended_at'])->lt(CarbonImmutable::parse($s['started_at'])))$this->fail('Завершение сессии раньше её начала.');}}
  return $d;
 }
 public function export(int $userId):array {
  return app(RecurringTasks::class)->locked($userId,function()use($userId){
   $now=CarbonImmutable::now();$projects=Project::where('user_id',$userId)->orderBy('id')->get();$tasks=Task::withTrashed()->where('user_id',$userId)->with('comments')->orderBy('sort_order')->orderBy('id')->get();
   // Fix identities for legacy/direct SQL rows without changing their content.
   foreach($projects->concat($tasks) as $row)if(!$row->transfer_uuid){$row->transfer_uuid=(string)Str::uuid();$row->save();}
   $projectMap=$projects->pluck('transfer_uuid','id');$time=TimeSession::where('user_id',$userId)->orderBy('id')->get();$adjustments=DB::table('time_adjustments')->where('user_id',$userId)->orderBy('id')->get()->groupBy('time_session_id');$time=$time->groupBy('task_id');
   $d=['format'=>'sovdelo.transfer','schema_version'=>1,'exported_at'=>$now->toIso8601String(),'notes'=>['Без содержимого вложений, расписаний повторов, напоминаний и настроек аккаунта.','Активное время сохранено как завершённый снимок; текущий таймер продолжает работу.'],'projects'=>$projects->map(fn($p)=>['uuid'=>$p->transfer_uuid,'name'=>$p->name,'archived_at'=>$p->archived_at?->toIso8601String()])->all(),
   'tasks'=>$tasks->map(fn($t)=>['uuid'=>$t->transfer_uuid,'project_uuid'=>$t->project_id?($projectMap[$t->project_id]??null):null,'title'=>$t->title,'description'=>$t->description,'status'=>$t->status,'priority'=>$t->priority,'due_date'=>$t->due_date,'planned_date'=>$t->planned_date,'checklist'=>$t->checklist??[],'archived_at'=>$t->archived_at?->toIso8601String(),'deleted_at'=>$t->deleted_at?->toIso8601String(),'labels'=>$t->labels->map(fn($l)=>['name'=>$l->name,'color'=>$l->color])->all(),'comments'=>$t->comments->where('user_id',$userId)->map(fn($c)=>['body'=>$c->body,'created_at'=>$c->created_at->toIso8601String()])->values()->all(),
    'time'=>($time[$t->id]??collect())->map(fn($s)=>['started_at'=>$s->started_at->toIso8601String(),'ended_at'=>($s->ended_at??($s->started_at->gt($now)?$s->started_at:$now))->toIso8601String(),'seconds'=>$s->ended_at?$s->duration_seconds:max(0,(int)$s->started_at->diffInSeconds($now,false)),'end_reason'=>$s->ended_at?$s->end_reason:'snapshot','adjustments'=>($adjustments[$s->id]??collect())->map(fn($a)=>['previous_seconds'=>(int)$a->previous_seconds,'new_seconds'=>(int)$a->new_seconds,'reason'=>$a->reason,'created_at'=>CarbonImmutable::parse($a->created_at)->toIso8601String()])->all()])->all()])->all()];
   $encoded=json_encode($d,JSON_UNESCAPED_UNICODE|JSON_THROW_ON_ERROR);$this->parse($encoded);return $d;
  });
 }
 public function preview(int $userId,array $d,string $strategy):array {
  $projectDup=Project::where('user_id',$userId)->whereIn('transfer_uuid',array_column($d['projects'],'uuid'))->count();$taskDup=Task::withTrashed()->where('user_id',$userId)->whereIn('transfer_uuid',array_column($d['tasks'],'uuid'))->count();
  return ['projects'=>count($d['projects']),'tasks'=>count($d['tasks']),'duplicate_projects'=>$projectDup,'duplicate_tasks'=>$taskDup,'create_projects'=>count($d['projects'])-($strategy==='skip'?$projectDup:0),'create_tasks'=>count($d['tasks'])-($strategy==='skip'?$taskDup:0),'seconds'=>array_sum(array_map(fn($t)=>array_sum(array_column($t['time'],'seconds')),$d['tasks'])),'samples'=>array_slice(array_column($d['tasks'],'title'),0,8)];
 }
 public function import(int $userId,array $d,string $strategy,string $fingerprint,string $key):array {
  return app(RecurringTasks::class)->locked($userId,function()use($userId,$d,$strategy,$fingerprint,$key){
   $old=DB::table('import_batches')->where('user_id',$userId)->where('request_key',$key)->first();if($old){if($old->fingerprint!==$fingerprint||$old->strategy!==$strategy)$this->fail('Ключ импорта уже использован для другого файла.');return json_decode($old->result,true,512,JSON_THROW_ON_ERROR);}
   $result=['created_projects'=>0,'created_tasks'=>0,'skipped_tasks'=>0];$map=[];
   foreach($d['projects'] as $row){$existing=$strategy==='skip'?Project::where('user_id',$userId)->where('transfer_uuid',$row['uuid'])->first():null;
    if($existing){$map[$row['uuid']]=$existing->id;continue;}$p=new Project(['user_id'=>$userId,'name'=>$row['name']]);$p->transfer_uuid=$strategy==='copy'?(string)Str::uuid():$row['uuid'];$p->archived_at=$row['archived_at']?CarbonImmutable::parse($row['archived_at'])->utc():null;$p->save();$map[$row['uuid']]=$p->id;$result['created_projects']++;
   }
   $tails=[];foreach(['todo','doing','done'] as $status)$tails[$status]=(int)Task::where('user_id',$userId)->where('status',$status)->max('sort_order');
   foreach($d['tasks'] as $row){if($strategy==='skip'&&Task::withTrashed()->where('user_id',$userId)->where('transfer_uuid',$row['uuid'])->exists()){$result['skipped_tasks']++;continue;}
    $t=new Task(['user_id'=>$userId,'project_id'=>$row['project_uuid']?$map[$row['project_uuid']]:null,'title'=>$row['title'],'description'=>$row['description'],'status'=>$row['status'],'priority'=>$row['priority'],'due_date'=>$row['due_date'],'planned_date'=>$row['planned_date'],'checklist'=>array_map(fn($i)=>['text'=>$i['text'],'done'=>(bool)$i['done']],$row['checklist'])]);$t->transfer_uuid=$strategy==='copy'?(string)Str::uuid():$row['uuid'];$t->sort_order=($tails[$row['status']]+=1024);$t->archived_at=$row['archived_at']?CarbonImmutable::parse($row['archived_at'])->utc():null;$t->deleted_at=$row['deleted_at']?CarbonImmutable::parse($row['deleted_at'])->utc():null;$t->save();
    $labels=[];foreach($row['labels'] as $l)$labels[]=Label::firstOrCreate(['user_id'=>$userId,'name'=>$l['name']],['color'=>$l['color']])->id;$t->labels()->sync($labels);
    foreach($row['comments'] as $c){$comment=new TaskComment(['user_id'=>$userId,'task_id'=>$t->id,'body'=>$c['body']]);$comment->created_at=CarbonImmutable::parse($c['created_at'])->utc();$comment->updated_at=$comment->created_at;$comment->save();}
    foreach($row['time'] as $s){$session=TimeSession::create(['user_id'=>$userId,'task_id'=>$t->id,'request_key'=>(string)Str::uuid(),'started_at'=>CarbonImmutable::parse($s['started_at'])->utc(),'ended_at'=>CarbonImmutable::parse($s['ended_at'])->utc(),'duration_seconds'=>$s['seconds'],'end_reason'=>'import']);foreach($s['adjustments'] as $a)DB::table('time_adjustments')->insert(['user_id'=>$userId,'time_session_id'=>$session->id,'previous_seconds'=>$a['previous_seconds'],'new_seconds'=>$a['new_seconds'],'reason'=>$a['reason'],'created_at'=>CarbonImmutable::parse($a['created_at'])->utc(),'updated_at'=>now()]);}
    $result['created_tasks']++;
   }
   DB::table('import_batches')->insert(['user_id'=>$userId,'request_key'=>$key,'fingerprint'=>$fingerprint,'strategy'=>$strategy,'result'=>json_encode($result,JSON_THROW_ON_ERROR),'created_at'=>now(),'updated_at'=>now()]);return $result;
  });
 }
}

<?php
namespace App\Http\Controllers;
use App\Models\{Task,TaskSeries};
use App\Services\RecurringTasks;
use Carbon\CarbonImmutable;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
class TaskSeriesController {
 private function rules(Request $r):array {return ['frequency'=>['required',Rule::in(['daily','weekly','monthly'])],'next_date'=>['required','date_format:Y-m-d','after_or_equal:'.CarbonImmutable::now($r->user()->timezone?:'Europe/Moscow')->toDateString(),'before:2101-01-01']];}
 public function index(Request $r){return TaskSeries::where('user_id',$r->user()->id)->orderByDesc('id')->get();}
 public function store(Request $r,RecurringTasks $service){
  $d=$r->validate($this->rules($r)+['task_id'=>'required|integer','request_key'=>'required|uuid']);
  return $service->locked($r->user()->id,function()use($r,$d){$existing=TaskSeries::where('user_id',$r->user()->id)->where('request_key',$d['request_key'])->first();if($existing)return response()->json($existing,201);$t=Task::where('user_id',$r->user()->id)->activeBoard()->findOrFail($d['task_id']);
   return response()->json(TaskSeries::create(['request_key'=>$d['request_key'],'user_id'=>$r->user()->id,'project_id'=>$t->project_id,'title'=>$t->title,'description'=>$t->description,'priority'=>$t->priority,'checklist'=>$t->checklist??[],'label_ids'=>$t->labels->pluck('id')->all(),'frequency'=>$d['frequency'],'next_date'=>$d['next_date'],'anchor_day'=>(int)substr($d['next_date'],8,2),'active'=>true]),201);
  });
 }
 public function update(Request $r,int $series,RecurringTasks $service){
  $d=$r->validate(['active'=>'sometimes|boolean','title'=>'sometimes|required|string|max:240','description'=>'sometimes|nullable|string|max:20000','priority'=>['sometimes',Rule::in(['normal','high'])]]+($r->has('frequency')||$r->has('next_date')?$this->rules($r):[]));
  return $service->locked($r->user()->id,function()use($r,$series,$d){$s=TaskSeries::where('user_id',$r->user()->id)->findOrFail($series);$s->fill($d);if(isset($d['next_date']))$s->anchor_day=(int)substr($d['next_date'],8,2);$s->save();return $s;});
 }
}

<?php
namespace App\Services;
use App\Models\{Task,Project};
class ApiData {
 public static function project(Project $p):array{return ['id'=>$p->id,'uuid'=>$p->transfer_uuid,'version'=>(int)$p->version,'name'=>$p->name,'archived_at'=>$p->archived_at?->toIso8601String(),'updated_at'=>$p->updated_at?->toIso8601String()];}
 public static function task(Task $t):array{return ['id'=>$t->id,'uuid'=>$t->transfer_uuid,'version'=>(int)$t->version,'project_id'=>$t->project_id,'title'=>$t->title,'description'=>$t->description,'status'=>$t->status,'column'=>$t->board_column,'priority'=>$t->priority,'due_date'=>$t->due_date,'planned_date'=>$t->planned_date,'checklist'=>$t->checklist??[],'sort_order'=>$t->sort_order,'labels'=>$t->labels->map(fn($l)=>['id'=>$l->id,'name'=>$l->name,'color'=>$l->color])->all(),'comments_count'=>(int)$t->comments_count,'attachments_count'=>(int)$t->attachments_count,'archived_at'=>$t->archived_at?->toIso8601String(),'deleted_at'=>$t->deleted_at?->toIso8601String(),'updated_at'=>$t->updated_at?->toIso8601String()];}
 public static function response(mixed $data,int $status=200){return response()->json(['data'=>$data,'meta'=>['api_version'=>'1']],$status);}
 public static function page($p,callable $map){return response()->json(['data'=>$p->getCollection()->map($map)->values(),'meta'=>['api_version'=>'1','page'=>$p->currentPage(),'per_page'=>$p->perPage(),'total'=>$p->total(),'last_page'=>$p->lastPage()]]);}
}

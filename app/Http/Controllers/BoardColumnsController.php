<?php
namespace App\Http\Controllers;
use App\Models\{BoardColumn,Task};
use App\Services\{BoardColumns,RecurringTasks};
use Illuminate\Http\Request;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;
class BoardColumnsController {
 public function save(Request $r,RecurringTasks $lock,BoardColumns $service){
  $d=$r->validate(['columns'=>'required|array|min:3|max:20','columns.*'=>'required|array:key,name,kind','columns.*.key'=>'nullable|string|max:40|distinct','columns.*.name'=>'required|string|max:80','columns.*.kind'=>['required',Rule::in(['todo','doing','done'])]]);
  return $lock->locked($r->user()->id,function()use($r,$d,$service){
   $uid=$r->user()->id;$old=$service->all($uid)->keyBy('key');$keys=array_column($d['columns'],'key');foreach(['todo','doing','done'] as $key)abort_unless(in_array($key,$keys,true),422,'Основные столбцы можно переименовать и переставить, но нельзя удалить.');
   foreach($old as $c)if(!in_array($c->key,$keys,true))abort_if(Task::withTrashed()->where('user_id',$uid)->where('board_column',$c->key)->exists(),422,'Перед удалением столбца перенесите все его задачи, включая архив и корзину.');
   $keep=[];foreach($d['columns'] as $index=>$row){$key=$row['key']??null;$name=trim($row['name']);abort_if($name==='',422,'Введите название столбца.');
    if($key){abort_unless(isset($old[$key]),422,'Неизвестный столбец.');$c=$old[$key];abort_unless($c->kind===$row['kind'],422,'Тип существующего столбца не меняется.');$c->name=$name;$c->sort_order=$index*1024;$c->save();}
    else {$key=(string)Str::uuid();BoardColumn::create(['user_id'=>$uid,'key'=>$key,'name'=>$name,'kind'=>$row['kind'],'sort_order'=>$index*1024]);}$keep[]=$key;
   }
   BoardColumn::where('user_id',$uid)->whereNotIn('key',$keep)->delete();return ['columns'=>$service->all($uid)];
  });
 }
}

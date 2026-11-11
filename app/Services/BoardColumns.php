<?php
namespace App\Services;
use App\Models\BoardColumn;
use Illuminate\Validation\ValidationException;
class BoardColumns {
 public function ensure(int $userId):void {foreach(['todo'=>'К выполнению','doing'=>'В работе','done'=>'Готово'] as $key=>$name)BoardColumn::firstOrCreate(['user_id'=>$userId,'key'=>$key],['name'=>$name,'kind'=>$key,'sort_order'=>array_search($key,['todo','doing','done'])*1024]);}
 public function resolve(int $userId,string $key):BoardColumn {$this->ensure($userId);$c=BoardColumn::where('user_id',$userId)->where('key',$key)->first();if(!$c)throw ValidationException::withMessages(['board_column'=>'Столбец недоступен. Обновите доску.']);return $c;}
 public function all(int $userId){$this->ensure($userId);return BoardColumn::where('user_id',$userId)->orderBy('sort_order')->orderBy('id')->get();}
}

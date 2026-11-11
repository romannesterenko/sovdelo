<?php
namespace App\Models;
use Illuminate\Database\Eloquent\Model;
class TimeSession extends Model {
 protected $guarded=['id'];
 protected function casts():array{return ['started_at'=>'immutable_datetime','ended_at'=>'immutable_datetime','duration_seconds'=>'integer','task_id'=>'integer','user_id'=>'integer'];}
 public function task(){return $this->belongsTo(Task::class)->withTrashed();}
}

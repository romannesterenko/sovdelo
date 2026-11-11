<?php
namespace App\Models;
use Illuminate\Database\Eloquent\Model;
class TaskNotification extends Model {
 protected $guarded=['id'];
 protected function casts():array{return ['user_id'=>'integer','task_id'=>'integer','scheduled_at'=>'immutable_datetime','read_at'=>'immutable_datetime'];}
}

<?php
namespace App\Models;
use Illuminate\Database\Eloquent\Model;
class TaskSeries extends Model {
 protected $table='task_series';
 protected $guarded=['id'];
 protected function casts():array{return ['checklist'=>'array','label_ids'=>'array','active'=>'boolean','anchor_day'=>'integer','user_id'=>'integer'];}
}

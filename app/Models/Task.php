<?php
namespace App\Models;
use Illuminate\Database\Eloquent\Model;
class Task extends Model {
 use \Illuminate\Database\Eloquent\SoftDeletes;
 public function project(){return $this->belongsTo(Project::class);}
 public function scopeActiveBoard($q){return $q->whereNull('tasks.archived_at')->where(fn($sub)=>$sub->whereNull('project_id')->orWhereHas('project',fn($p)=>$p->whereNull('archived_at')));}

 protected $with=['labels'];
 protected $withCount=['comments','attachments'];
 public function labels(){return $this->belongsToMany(Label::class,'task_label');}
 public function comments(){return $this->hasMany(TaskComment::class);}
 public function attachments(){return $this->hasMany(TaskAttachment::class);}
 protected static function booted():void {static::creating(function($model){if(!$model->board_column)$model->board_column=$model->status?:'todo';if(!$model->transfer_uuid)$model->transfer_uuid=(string)\Illuminate\Support\Str::uuid();});}
 protected $fillable=['user_id','project_id','title','description','status','priority','due_date','planned_date','checklist'];
 protected function casts(): array {return ['remind_at'=>'immutable_datetime','checklist'=>'array','user_id'=>'integer','project_id'=>'integer','sort_order'=>'integer','archived_at'=>'datetime'];}
}

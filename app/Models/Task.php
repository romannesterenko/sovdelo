<?php
namespace App\Models;
use Illuminate\Database\Eloquent\Model;
class Task extends Model {
 protected $with=['labels'];
 protected $withCount=['comments','attachments'];
 public function labels(){return $this->belongsToMany(Label::class,'task_label');}
 public function comments(){return $this->hasMany(TaskComment::class);}
 public function attachments(){return $this->hasMany(TaskAttachment::class);}
 protected $fillable=['user_id','project_id','title','description','status','priority','due_date','checklist'];
 protected function casts(): array {return ['checklist'=>'array','user_id'=>'integer','project_id'=>'integer','sort_order'=>'integer'];}
}

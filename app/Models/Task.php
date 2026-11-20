<?php
namespace App\Models;
use Illuminate\Database\Eloquent\Model;
class Task extends Model {
 use \Illuminate\Database\Eloquent\SoftDeletes;
 public function project(){return $this->belongsTo(Project::class);}
 public function scopeActiveBoard($q){return $q->whereNull('tasks.archived_at')->where(fn($sub)=>$sub->whereNull('project_id')->orWhereHas('project',fn($p)=>$p->whereNull('archived_at')));}

 protected $with=['labels','coverAttachment'];
 protected $hidden=['coverAttachment'];
 protected $appends=['cover'];
 public function coverAttachment(){return $this->belongsTo(TaskAttachment::class,'cover_attachment_id');}
 public function getCoverAttribute():?array {
  $file=$this->coverAttachment;
  if(!$file||!$file->is_image||(int)$file->task_id!==(int)$this->id)return null;
  return ['id'=>(int)$file->id,'url'=>$file->preview_url,'name'=>$file->name,'width'=>$file->image_width,'height'=>$file->image_height];
 }
 protected $withCount=['comments','attachments'];
 public function labels(){return $this->belongsToMany(Label::class,'task_label');}
 public function comments(){return $this->hasMany(TaskComment::class);}
 public function attachments(){return $this->hasMany(TaskAttachment::class);}
 protected static function booted():void {
  static::creating(function($m){$m->version=1;if(!$m->board_column)$m->board_column=$m->status?:'todo';if(!$m->transfer_uuid)$m->transfer_uuid=(string)\Illuminate\Support\Str::uuid();});
  static::updating(function($m){$m->version=(int)$m->version+1;});
  static::deleting(function($m){\Illuminate\Support\Facades\DB::table('tasks')->where('id',$m->id)->increment('version');});
 }

 protected $fillable=['user_id','project_id','title','description','status','priority','due_date','planned_date','checklist'];
 protected function casts(): array {return ['cover_attachment_id'=>'integer','cover_disabled'=>'boolean','version'=>'integer','remind_at'=>'immutable_datetime','checklist'=>'array','user_id'=>'integer','project_id'=>'integer','sort_order'=>'integer','archived_at'=>'datetime'];}
}

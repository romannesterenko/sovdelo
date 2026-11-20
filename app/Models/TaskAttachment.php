<?php
namespace App\Models;
use Illuminate\Database\Eloquent\Model;
class TaskAttachment extends Model {protected $fillable=['task_id','name','path','bytes'];protected $hidden=['path'];
 protected $appends=['is_image','preview_url'];
 protected function casts():array{return ['image_width'=>'integer','image_height'=>'integer','task_id'=>'integer','bytes'=>'integer'];}
 public function getIsImageAttribute():bool{return in_array($this->mime_type,\App\Services\TaskCovers::MIMES,true);}
 public function getPreviewUrlAttribute():?string{return $this->is_image?'/tasks/'.$this->task_id.'/attachments/'.$this->id.'/preview':null;}}

<?php
namespace App\Models;
use Illuminate\Database\Eloquent\Model;
class ProjectAttachment extends Model {
 protected $fillable=['project_id','name','path','bytes','image_mime'];
 protected $hidden=['path'];
 protected $appends=['preview_url','download_url'];
 protected function casts():array {return ['bytes'=>'integer','project_id'=>'integer'];}
 public function getPreviewUrlAttribute():?string {return $this->image_mime?'/projects/'.$this->project_id.'/files/'.$this->id.'/preview':null;}
 public function getDownloadUrlAttribute():string {return '/projects/'.$this->project_id.'/files/'.$this->id;}
}

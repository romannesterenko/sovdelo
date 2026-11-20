<?php
namespace App\Models;
use Illuminate\Database\Eloquent\Model;
class Project extends Model {protected static function booted():void {static::creating(function($m){$m->version=1;if(!$m->transfer_uuid)$m->transfer_uuid=(string)\Illuminate\Support\Str::uuid();});static::updating(function($m){$m->version=(int)$m->version+1;});}
 protected $fillable=['user_id','name','description'];protected $appends=['cover_url'];public function getCoverUrlAttribute():?string{return $this->cover_attachment_id?'/projects/'.$this->id.'/files/'.$this->cover_attachment_id.'/preview':null;}protected $hidden=['description','cover_attachment_id','cover_disabled'];protected function casts():array{return ['version'=>'integer','archived_at'=>'datetime','cover_attachment_id'=>'integer','cover_disabled'=>'boolean'];}}

<?php
namespace App\Models;
use Illuminate\Database\Eloquent\Model;
class Project extends Model {protected static function booted():void {static::creating(function($m){$m->version=1;if(!$m->transfer_uuid)$m->transfer_uuid=(string)\Illuminate\Support\Str::uuid();});static::updating(function($m){$m->version=(int)$m->version+1;});}
 protected $fillable=['user_id','name'];protected function casts():array{return ['version'=>'integer','archived_at'=>'datetime'];}}

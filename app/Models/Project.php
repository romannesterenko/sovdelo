<?php
namespace App\Models;
use Illuminate\Database\Eloquent\Model;
class Project extends Model {protected static function booted():void {static::creating(function($model){if(!$model->transfer_uuid)$model->transfer_uuid=(string)\Illuminate\Support\Str::uuid();});}
 protected $fillable=['user_id','name'];protected function casts():array{return ['archived_at'=>'datetime'];}}

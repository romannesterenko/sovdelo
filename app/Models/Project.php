<?php
namespace App\Models;
use Illuminate\Database\Eloquent\Model;
class Project extends Model {protected $fillable=['user_id','name'];protected function casts():array{return ['archived_at'=>'datetime'];}}

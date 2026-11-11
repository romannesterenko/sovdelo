<?php
namespace App\Models;
use Illuminate\Database\Eloquent\Model;
class TaskAttachment extends Model {protected $fillable=['task_id','name','path','bytes'];protected $hidden=['path'];}

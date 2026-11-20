<?php
namespace App\Models;
use Illuminate\Database\Eloquent\Model;
class ProjectCredential extends Model {
 protected $fillable=['project_id','name','kind','address','username','secret','notes'];
 protected $hidden=['secret'];
 protected function casts():array {return ['secret'=>'encrypted','project_id'=>'integer'];}
}

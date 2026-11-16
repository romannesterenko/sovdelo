<?php
namespace App\Models;
use Illuminate\Database\Eloquent\Model;
class ProjectAgent extends Model {
 protected $guarded=['id'];
 protected function casts():array{return ['user_id'=>'integer','project_id'=>'integer','token_id'=>'integer','revoked_at'=>'datetime'];}
}

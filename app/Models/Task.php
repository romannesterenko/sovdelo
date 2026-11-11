<?php
namespace App\Models;
use Illuminate\Database\Eloquent\Model;
class Task extends Model {
 protected $fillable=['user_id','project_id','title','description','status','priority','due_date','checklist'];
 protected function casts(): array {return ['checklist'=>'array','user_id'=>'integer','project_id'=>'integer'];}
}

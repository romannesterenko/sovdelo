<?php
namespace App\Models;
use Illuminate\Database\Eloquent\Model;
class BoardColumn extends Model {protected $guarded=['id'];protected function casts():array{return ['user_id'=>'integer','sort_order'=>'integer'];}}

<?php
namespace App\Models;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;
class User extends Authenticatable {
 use Notifiable;
 use \Laravel\Sanctum\HasApiTokens;
 protected $fillable=['name','email','password'];
 protected $hidden=['password','remember_token','auth_version'];
 protected function casts(): array {return ['auth_version'=>'integer','password'=>'hashed','notifications_enabled'=>'boolean','deadline_notifications'=>'boolean'];}
}

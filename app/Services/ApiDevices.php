<?php
namespace App\Services;
use App\Models\User;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\ValidationException;
class ApiDevices {
 public function listing(User $u):array{return $u->tokens()->latest('id')->limit(100)->get()->map(fn($t)=>['id'=>$t->id,'name'=>$t->name,'access'=>$t->can('workspace:write')?'write':'read','created_at'=>$t->created_at?->toIso8601String(),'last_used_at'=>$t->last_used_at?->toIso8601String(),'expires_at'=>$t->expires_at?->toIso8601String(),'valid'=>(int)$t->auth_version===(int)$u->auth_version&&(!$t->expires_at||$t->expires_at->isFuture())])->all();}
 public function revoke(int $userId,int $id,string $password):void {app(RecurringTasks::class)->locked($userId,function()use($userId,$id,$password){$u=User::findOrFail($userId);if(!Hash::check($password,$u->password))throw ValidationException::withMessages(['current_password'=>'Текущий пароль указан неверно.']);$u->tokens()->findOrFail($id)->delete();});}
}

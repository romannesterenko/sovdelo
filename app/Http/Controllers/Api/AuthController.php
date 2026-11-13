<?php
namespace App\Http\Controllers\Api;
use App\Models\User;
use App\Services\{ApiData,ApiDevices,RecurringTasks};
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\{Rule,ValidationException};
class AuthController {
 public function login(Request $r,RecurringTasks $lock){
  if(app()->environment('production'))abort_unless($r->isSecure(),403,'Для входа требуется HTTPS.');
  $r->merge(['email'=>strtolower(trim((string)$r->input('email')))]);
  $d=$r->validate(['email'=>'required|email|max:254','password'=>'required|string|max:128','device_name'=>'required|string|max:80','access'=>['required',Rule::in(['read','write'])]]);
  $u=User::where('email',$d['email'])->first();
  if(!$u||!Hash::check($d['password'],$u->password))throw ValidationException::withMessages(['email'=>'Неверный email или пароль.']);
  return $lock->locked($u->id,function()use($u,$d){$fresh=User::findOrFail($u->id);if(!Hash::check($d['password'],$fresh->password))throw ValidationException::withMessages(['email'=>'Неверный email или пароль.']);abort_if($fresh->tokens()->where('expires_at','>',now())->where('auth_version',$fresh->auth_version)->count()>=20,422,'Отзовите неиспользуемые токены устройств (максимум 20).');
   $abilities=['workspace:read'];if($d['access']==='write')$abilities[]='workspace:write';$expires=now()->addDays(30);$new=$fresh->createToken($d['device_name'],$abilities,$expires);$new->accessToken->auth_version=$fresh->auth_version;$new->accessToken->save();
   return ApiData::response(['token'=>$new->plainTextToken,'token_type'=>'Bearer','expires_at'=>$expires->toIso8601String(),'access'=>$d['access']],201);
  });
 }
 public function me(Request $r){$u=$r->user();return ApiData::response(['id'=>$u->id,'name'=>$u->name,'email'=>$u->email,'timezone'=>$u->timezone,'theme'=>$u->theme]);}
 public function logout(Request $r){$r->user()->currentAccessToken()->delete();return ApiData::response(['revoked'=>true]);}
 public function devices(Request $r,ApiDevices $service){return ApiData::response($service->listing($r->user()));}
 public function revoke(Request $r,int $device,ApiDevices $service){abort_unless($r->user()->currentAccessToken()->can('workspace:write'),403,'Недостаточно прав.');$d=$r->validate(['current_password'=>'required|string|max:128']);$service->revoke($r->user()->id,$device,$d['current_password']);return ApiData::response(['revoked'=>true]);}
}

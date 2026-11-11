<?php
namespace App\Http\Controllers;
use App\Models\User;
use App\Services\RecurringTasks;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\{Auth,DB,Hash};
use Illuminate\Support\Str;
use Illuminate\Validation\{Rule,ValidationException};
class AccountController {
 private function token(string $id):string{return hash_hmac('sha256',$id,(string)config('app.key'));}
 private function requirePassword(Request $r,User $u):void {if(!Hash::check((string)$r->input('current_password'),$u->password))throw ValidationException::withMessages(['current_password'=>'Текущий пароль указан неверно.']);}
 private function refreshLogin(Request $r,User $u):array {
  Auth::login($u,true);$r->session()->regenerateToken();$r->session()->put('account_auth_version_'.$u->id,(int)$u->auth_version);
  return ['user'=>$u,'csrf'=>csrf_token()];
 }
 public function profile(Request $r){return ['user'=>$r->user(),'timezones'=>\DateTimeZone::listIdentifiers()];}
 public function update(Request $r,RecurringTasks $lock){
  $r->merge($r->has('name')?['name'=>trim((string)$r->input('name'))]:[]);
  $d=$r->validate(['name'=>'sometimes|required|string|max:120','timezone'=>['sometimes','required',Rule::in(\DateTimeZone::listIdentifiers())],'theme'=>['sometimes','required',Rule::in(['dark','light','system'])]]);
  return $lock->locked($r->user()->id,function()use($r,$d){$u=User::findOrFail($r->user()->id);$u->forceFill($d)->save();return ['user'=>$u];});
 }
 public function password(Request $r,RecurringTasks $lock){
  $r->validate(['current_password'=>'required|string|max:128','password'=>'required|string|min:10|max:128|confirmed|different:current_password']);
  return $lock->locked($r->user()->id,function()use($r){$u=User::findOrFail($r->user()->id);$this->requirePassword($r,$u);
   $u->password=$r->input('password');$u->remember_token=Str::random(60);$u->auth_version++;$u->save();
   $data=$this->refreshLogin($r,$u);
   DB::table('sessions')->where('user_id',$u->id)->where('id','!=',$r->session()->getId())->delete();
   DB::table('password_reset_tokens')->where('email',$u->email)->delete();return $data;
  });
 }
 public function sessions(Request $r){
  if(config('session.driver')!=='database')return ['supported'=>false,'items'=>[]];
  $rows=DB::table('sessions')->where('user_id',$r->user()->id)->where('last_activity','>=',now()->timestamp-((int)config('session.lifetime',120))*60)->orderByDesc('last_activity')->get();
  return ['supported'=>true,'items'=>$rows->map(fn($s)=>['id'=>$this->token($s->id),'current'=>hash_equals($s->id,$r->session()->getId()),'ip'=>$s->ip_address,'agent'=>mb_substr((string)$s->user_agent,0,500),'last_activity'=>$s->last_activity])->values()];
 }
 public function revoke(Request $r,string $session,RecurringTasks $lock){
  abort_unless(config('session.driver')==='database',409,'Список устройств доступен при хранении сессий в базе данных.');
  $r->validate(['current_password'=>'required|string|max:128']);
  return $lock->locked($r->user()->id,function()use($r,$session){$u=User::findOrFail($r->user()->id);$this->requirePassword($r,$u);
   $rows=DB::table('sessions')->where('user_id',$u->id)->get();$target=$rows->first(fn($s)=>hash_equals($this->token($s->id),$session));abort_unless($target,404);
   abort_if(hash_equals($target->id,$r->session()->getId()),422,'Для текущего браузера используйте кнопку «Выйти».');
   DB::table('sessions')->where('user_id',$u->id)->where('id',$target->id)->delete();
   // Rotate persistent login credentials so a revoked browser cannot re-enter by its old remember cookie.
   $u->remember_token=Str::random(60);$u->save();return $this->refreshLogin($r,$u);
  });
 }
}

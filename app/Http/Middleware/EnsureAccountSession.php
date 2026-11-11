<?php
namespace App\Http\Middleware;
use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
class EnsureAccountSession {
 public function handle(Request $request,Closure $next){
  if($u=$request->user()){
   $key='account_auth_version_'.$u->id;$saved=$request->session()->get($key);
   if($saved!==null&&(int)$saved!==(int)$u->auth_version){Auth::logout();$request->session()->invalidate();$request->session()->regenerateToken();return response()->json(['message'=>'Пароль изменён. Войдите снова.'],401);}
   $request->session()->put($key,(int)$u->auth_version);
  }return $next($request);
 }
}

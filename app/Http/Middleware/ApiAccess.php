<?php
namespace App\Http\Middleware;
use Closure;
use Illuminate\Http\Request;
use Laravel\Sanctum\PersonalAccessToken;
class ApiAccess {
 public function handle(Request $r,Closure $next){
  $token=$r->user()?->currentAccessToken();
  abort_unless($token instanceof PersonalAccessToken,401,'Требуется токен устройства.');
  abort_unless((int)$token->auth_version===(int)$r->user()->auth_version,401,'Пароль изменён. Выполните вход снова.');
  abort_unless($token->can('workspace:read'),403,'Нет доступа на чтение.');
  if(!$r->isMethodSafe()&&!$r->is('api/v1/auth/*'))abort_unless($token->can('workspace:write'),403,'Токен разрешает только чтение.');
  if(app()->environment('production'))abort_unless($r->isSecure(),403,'Для API требуется HTTPS.');
  if(strlen($r->getContent())>131072)abort(413,'Слишком большой запрос.');
  return $next($r);
 }
}

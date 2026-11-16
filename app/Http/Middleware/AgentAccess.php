<?php
namespace App\Http\Middleware;
use App\Models\ProjectAgent;
use Closure;
use Illuminate\Http\Request;
use Laravel\Sanctum\PersonalAccessToken;
class AgentAccess {
 public function handle(Request $r,Closure $next){
  $token=$r->user()?->currentAccessToken();
  abort_unless($token instanceof PersonalAccessToken&&$token->can('agent:project'),401);
  abort_unless((int)$token->auth_version===(int)$r->user()->auth_version,401);
  $agent=ProjectAgent::where('user_id',$r->user()->id)->where('token_id',$token->id)->whereNull('revoked_at')->firstOrFail();
  abort_unless(\App\Models\Project::whereKey($agent->project_id)->where('user_id',$agent->user_id)->whereNull('archived_at')->exists(),403);
  if(app()->environment('production'))abort_unless($r->isSecure(),403);
  abort_if(strlen($r->getContent())>131072,413);
  $r->attributes->set('project_agent',$agent);
  return $next($r);
 }
}

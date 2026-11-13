<?php
namespace App\Providers;
use Illuminate\Support\ServiceProvider;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Cache\RateLimiting\Limit;
use Illuminate\Http\Request;
class AppServiceProvider extends ServiceProvider {
 public function register():void{}
 public function boot():void {
  RateLimiter::for('api-login',fn(Request $r)=>[Limit::perMinute(20)->by('api-login-ip:'.$r->ip()),Limit::perMinute(6)->by('api-login-account:'.$r->ip().':'.hash('sha256',strtolower((string)$r->input('email'))))]);
  RateLimiter::for('workspace-api',fn(Request $r)=>Limit::perMinute(120)->by('workspace-api:'.$r->user()->id));
 }
}

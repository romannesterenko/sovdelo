<?php
use Illuminate\Support\Facades\Route;
use App\Http\Controllers\Api\{AuthController,WorkspaceController};
use App\Http\Middleware\ApiAccess;
use Laravel\Sanctum\Http\Middleware\EnsureFrontendRequestsAreStateful;
Route::prefix('v1')->withoutMiddleware(EnsureFrontendRequestsAreStateful::class)->group(function(){
 Route::post('/auth/token',[AuthController::class,'login'])->middleware('throttle:api-login');
 Route::middleware(['auth:sanctum',ApiAccess::class,'throttle:workspace-api'])->group(function(){
  Route::get('/me',[AuthController::class,'me']);
  Route::delete('/auth/token',[AuthController::class,'logout']);
  Route::get('/auth/devices',[AuthController::class,'devices']);
  Route::delete('/auth/devices/{device}',[AuthController::class,'revoke'])->whereNumber('device')->middleware('throttle:6,1');
  Route::get('/projects',[WorkspaceController::class,'projects']);
  Route::post('/projects',[WorkspaceController::class,'createProject']);
  Route::get('/projects/{project}',[WorkspaceController::class,'showProject'])->whereNumber('project');
  Route::patch('/projects/{project}',[WorkspaceController::class,'updateProject'])->whereNumber('project');
  Route::post('/projects/{project}/{action}',[WorkspaceController::class,'projectLife'])->whereNumber('project')->whereIn('action',['archive','restore']);
  Route::get('/tasks',[WorkspaceController::class,'tasks']);
  Route::post('/tasks',[WorkspaceController::class,'createTask']);
  Route::get('/tasks/{task}',[WorkspaceController::class,'showTask'])->whereNumber('task');
  Route::patch('/tasks/{task}',[WorkspaceController::class,'updateTask'])->whereNumber('task');
  Route::delete('/tasks/{task}',[WorkspaceController::class,'delete'])->whereNumber('task');
  Route::post('/tasks/{task}/move',[WorkspaceController::class,'move'])->whereNumber('task');
  Route::post('/tasks/{task}/{action}',[WorkspaceController::class,'taskLife'])->whereNumber('task')->whereIn('action',['archive','restore']);
  Route::get('/columns',[WorkspaceController::class,'columns']);
  Route::put('/columns',[WorkspaceController::class,'saveColumns']);
  Route::get('/timer',[WorkspaceController::class,'timer']);
  Route::post('/tasks/{task}/timer',[WorkspaceController::class,'startTimer'])->whereNumber('task');
  Route::post('/timer/{session}/stop',[WorkspaceController::class,'stopTimer'])->whereNumber('session');
  Route::get('/tasks/{task}/time',[WorkspaceController::class,'time'])->whereNumber('task');
 });
});

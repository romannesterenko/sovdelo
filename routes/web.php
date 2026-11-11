<?php
use App\Models\{User,Project,Task};
use App\Services\TaskOrder;
use App\Services\TaskTimer;
use App\Http\Controllers\TaskDetailsController;
use App\Http\Controllers\TaskLifecycleController;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\{Auth,Route};
use Illuminate\Validation\{Rule,ValidationException};

Route::view('/', 'app');
Route::get('/session',fn(Request $r)=>['user'=>$r->user(),'csrf'=>csrf_token()])->middleware(\App\Http\Middleware\EnsureAccountSession::class);
Route::post('/register',function(Request $r){
 $r->merge(['email'=>strtolower((string)$r->input('email'))]);
 $data=$r->validate(['name'=>'required|string|max:120','email'=>'required|email|max:254|unique:users,email','password'=>'required|string|min:10|max:128|confirmed']);
 $data['email']=strtolower($data['email']);
 $u=User::create($data)->fresh();Auth::login($u);$r->session()->regenerate();$r->session()->put('account_auth_version_'.$u->id,(int)$u->auth_version);
 return response()->json(['user'=>$u,'csrf'=>csrf_token()],201);
})->middleware('throttle:6,1');
Route::post('/login',function(Request $r){
 $r->merge(['email'=>strtolower((string)$r->input('email'))]);
 $d=$r->validate(['email'=>'required|email|max:254','password'=>'required|string|max:128']);
 if(!Auth::attempt($d,true))throw ValidationException::withMessages(['email'=>'Неверный email или пароль.']);
 $r->session()->regenerate();$r->session()->put('account_auth_version_'.$r->user()->id,(int)$r->user()->auth_version);return ['user'=>$r->user(),'csrf'=>csrf_token()];
})->middleware('throttle:6,1');
Route::post('/logout',function(Request $r){Auth::logout();$r->session()->invalidate();$r->session()->regenerateToken();return ['csrf'=>csrf_token()];})->middleware('auth');
Route::middleware(['auth',\App\Http\Middleware\EnsureAccountSession::class])->group(function(){
 Route::get('/account',[\App\Http\Controllers\AccountController::class,'profile']);
 Route::patch('/account',[\App\Http\Controllers\AccountController::class,'update']);
 Route::put('/account/password',[\App\Http\Controllers\AccountController::class,'password'])->middleware('throttle:6,1');
 Route::get('/account/sessions',[\App\Http\Controllers\AccountController::class,'sessions']);
 Route::post('/account/sessions/{session}/revoke',[\App\Http\Controllers\AccountController::class,'revoke'])->middleware('throttle:6,1');

 Route::get('/notifications/settings',[\App\Http\Controllers\TaskNotificationsController::class,'settings']);
 Route::put('/notifications/settings',[\App\Http\Controllers\TaskNotificationsController::class,'saveSettings']);
 Route::get('/notifications',[\App\Http\Controllers\TaskNotificationsController::class,'index']);
 Route::post('/notifications/read-all',[\App\Http\Controllers\TaskNotificationsController::class,'readAll']);
 Route::post('/notifications/{notification}/read',[\App\Http\Controllers\TaskNotificationsController::class,'read']);
 Route::get('/tasks/{task}/reminder',[\App\Http\Controllers\TaskNotificationsController::class,'reminder']);
 Route::put('/tasks/{task}/reminder',[\App\Http\Controllers\TaskNotificationsController::class,'saveReminder']);

 Route::get('/task-series',[\App\Http\Controllers\TaskSeriesController::class,'index']);
 Route::post('/task-series',[\App\Http\Controllers\TaskSeriesController::class,'store']);
 Route::patch('/task-series/{series}',[\App\Http\Controllers\TaskSeriesController::class,'update']);

 Route::get('/timer',fn(Request $r)=>app(TaskTimer::class)->snapshot($r->user()->id));
 Route::post('/tasks/{task}/timer',function(Request $r,int $task){$d=$r->validate(['request_key'=>'required|uuid']);return app(TaskTimer::class)->start($r->user()->id,$task,$d['request_key']);});
 Route::post('/timer/{session}/stop',function(Request $r,int $session){$d=$r->validate(['reason'=>['required',Rule::in(['pause','stop'])]]);return app(TaskTimer::class)->stop($r->user()->id,$session,$d['reason']);});
 Route::get('/tasks/{task}/time',fn(Request $r,int $task)=>app(TaskTimer::class)->history($r->user()->id,$task));
 Route::patch('/timer/{session}',function(Request $r,int $session){$d=$r->validate(['seconds'=>'required|integer|min:0|max:604800','reason'=>'required|string|min:3|max:500']);return app(TaskTimer::class)->adjust($r->user()->id,$session,$d['seconds'],$d['reason']);});

 Route::patch('/preferences',function(Request $r){$d=$r->validate(['timezone'=>['required',Rule::in(\DateTimeZone::listIdentifiers())]]);$u=$r->user();$u->timezone=$d['timezone'];$u->save();return ['user'=>$u];});

 Route::get('/lifecycle',[TaskLifecycleController::class,'index']);
 Route::post('/tasks/{task}/archive',[TaskLifecycleController::class,'archive']);
 Route::post('/tasks/{task}/restore',[TaskLifecycleController::class,'restore']);
 Route::post('/projects/{project}/archive',[TaskLifecycleController::class,'archiveProject']);
 Route::post('/projects/{project}/restore',[TaskLifecycleController::class,'restoreProject']);

 Route::get('/labels',[TaskDetailsController::class,'labels']);
 Route::post('/labels',[TaskDetailsController::class,'createLabel']);
 Route::get('/tasks/{task}/details',[TaskDetailsController::class,'show']);
 Route::put('/tasks/{task}/labels',[TaskDetailsController::class,'setLabels']);
 Route::post('/tasks/{task}/comments',[TaskDetailsController::class,'comment']);
 Route::patch('/tasks/{task}/comments/{comment}',[TaskDetailsController::class,'editComment']);
 Route::delete('/tasks/{task}/comments/{comment}',[TaskDetailsController::class,'deleteComment']);
 Route::post('/tasks/{task}/attachments',[TaskDetailsController::class,'upload']);
 Route::get('/tasks/{task}/attachments/{attachment}',[TaskDetailsController::class,'download']);
 Route::delete('/tasks/{task}/attachments/{attachment}',[TaskDetailsController::class,'deleteFile']);

 Route::get('/data',function(Request $r){app(\App\Services\RecurringTasks::class)->generate($r->user()->id);return ['projects'=>Project::where('user_id',$r->user()->id)->whereNull('archived_at')->orderBy('id')->get(),'tasks'=>Task::where('user_id',$r->user()->id)->activeBoard()->orderBy('sort_order')->orderBy('id')->get()];});
 Route::post('/projects',function(Request $r){$d=$r->validate(['name'=>'required|string|max:120']);return Project::create($d+['user_id'=>$r->user()->id]);});
 Route::post('/tasks',function(Request $r){
  $d=$r->validate(['title'=>'required|string|max:240','project_id'=>['nullable',Rule::exists('projects','id')->where('user_id',$r->user()->id)->whereNull('archived_at')],'due_date'=>'nullable|date_format:Y-m-d','planned_date'=>'nullable|date_format:Y-m-d']);
  return response()->json(app(TaskOrder::class)->create($r->user()->id,$d),201);
 });
 Route::post('/tasks/{task}/move',function(Request $r,Task $task){
  abort_unless($task->user_id===$r->user()->id,404);
  $d=$r->validate(['status'=>['required',Rule::in(['todo','doing','done'])],'before_id'=>'nullable|integer|min:1']);
  return ['tasks'=>app(TaskOrder::class)->move($r->user()->id,$task->id,$d['status'],isset($d['before_id'])?(int)$d['before_id']:null)];
 });
 Route::patch('/tasks/{task}',function(Request $r,Task $task){
  abort_unless($task->user_id===$r->user()->id,404);
  $d=$r->validate(['title'=>'sometimes|required|string|max:240','project_id'=>['nullable',Rule::exists('projects','id')->where('user_id',$r->user()->id)->whereNull('archived_at')],'description'=>'nullable|string|max:20000','status'=>['sometimes',Rule::in(['todo','doing','done'])],'priority'=>['sometimes',Rule::in(['normal','high'])],'due_date'=>'nullable|date_format:Y-m-d','planned_date'=>'nullable|date_format:Y-m-d','checklist'=>'sometimes|array|max:100','checklist.*'=>'required|array:text,done','checklist.*.text'=>'required|string|max:500','checklist.*.done'=>'required|boolean']);
  return app(TaskOrder::class)->update($r->user()->id,$task->id,$d);
 });
 Route::delete('/tasks/{task}',function(Request $r,Task $task){abort_unless($task->user_id===$r->user()->id,404);app(TaskOrder::class)->delete($r->user()->id,$task->id);return response()->noContent();});
});

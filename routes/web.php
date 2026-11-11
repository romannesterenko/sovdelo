<?php
use App\Models\{User,Project,Task};
use Illuminate\Http\Request;
use Illuminate\Support\Facades\{Auth,Route};
use Illuminate\Validation\{Rule,ValidationException};

Route::view('/', 'app');
Route::get('/session',fn(Request $r)=>['user'=>$r->user(),'csrf'=>csrf_token()]);
Route::post('/register',function(Request $r){
 $r->merge(['email'=>strtolower((string)$r->input('email'))]);
 $data=$r->validate(['name'=>'required|string|max:120','email'=>'required|email|max:254|unique:users,email','password'=>'required|string|min:10|max:128|confirmed']);
 $data['email']=strtolower($data['email']);
 $u=User::create($data);Auth::login($u);$r->session()->regenerate();
 return response()->json(['user'=>$u,'csrf'=>csrf_token()],201);
})->middleware('throttle:6,1');
Route::post('/login',function(Request $r){
 $r->merge(['email'=>strtolower((string)$r->input('email'))]);
 $d=$r->validate(['email'=>'required|email|max:254','password'=>'required|string|max:128']);
 if(!Auth::attempt($d,true))throw ValidationException::withMessages(['email'=>'Неверный email или пароль.']);
 $r->session()->regenerate();return ['user'=>$r->user(),'csrf'=>csrf_token()];
})->middleware('throttle:6,1');
Route::post('/logout',function(Request $r){Auth::logout();$r->session()->invalidate();$r->session()->regenerateToken();return ['csrf'=>csrf_token()];})->middleware('auth');
Route::middleware('auth')->group(function(){
 Route::get('/data',fn(Request $r)=>['projects'=>Project::where('user_id',$r->user()->id)->orderBy('id')->get(),'tasks'=>Task::where('user_id',$r->user()->id)->orderBy('id')->get()]);
 Route::post('/projects',function(Request $r){$d=$r->validate(['name'=>'required|string|max:120']);return Project::create($d+['user_id'=>$r->user()->id]);});
 Route::post('/tasks',function(Request $r){
  $d=$r->validate(['title'=>'required|string|max:240','project_id'=>['nullable',Rule::exists('projects','id')->where('user_id',$r->user()->id)],'due_date'=>'nullable|date_format:Y-m-d']);
  return response()->json(Task::create($d+['user_id'=>$r->user()->id,'checklist'=>[]])->fresh(),201);
 });
 Route::patch('/tasks/{task}',function(Request $r,Task $task){
  abort_unless($task->user_id===$r->user()->id,404);
  $d=$r->validate(['title'=>'sometimes|required|string|max:240','project_id'=>['nullable',Rule::exists('projects','id')->where('user_id',$r->user()->id)],'description'=>'nullable|string|max:20000','status'=>['sometimes',Rule::in(['todo','doing','done'])],'priority'=>['sometimes',Rule::in(['normal','high'])],'due_date'=>'nullable|date_format:Y-m-d','checklist'=>'sometimes|array|max:100','checklist.*'=>'required|array:text,done','checklist.*.text'=>'required|string|max:500','checklist.*.done'=>'required|boolean']);
  $task->update($d);return $task->fresh();
 });
 Route::delete('/tasks/{task}',function(Request $r,Task $task){abort_unless($task->user_id===$r->user()->id,404);$task->delete();return response()->noContent();});
});

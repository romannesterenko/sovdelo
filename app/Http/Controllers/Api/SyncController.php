<?php
namespace App\Http\Controllers\Api;

use App\Models\{Task,TaskComment,Label};
use App\Services\{ApiData,RecurringTasks,TaskOrder};
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;

class SyncController
{
    private function data(Task $task): array
    {
        $task->loadMissing('project');
        return ApiData::task($task) + ['active' => !$task->deleted_at && !$task->archived_at && !$task->project?->archived_at];
    }

    public function tasks(Request $r)
    {
        $d = $r->validate(['after_id' => 'sometimes|integer|min:0', 'through_id' => 'sometimes|integer|min:0']);
        $uid = $r->user()->id;
        $through = $d['through_id'] ?? (int) Task::withTrashed()->where('user_id', $uid)->max('id');
        $after = (int) ($d['after_id'] ?? 0);
        $rows = Task::withTrashed()->with('project')->where('user_id', $uid)
            ->where('id', '>', $after)->where('id', '<=', $through)->orderBy('id')->limit(21)->get();
        $more = $rows->count() > 20;
        $rows = $rows->take(20);
        return response()->json(['data' => $rows->map(fn($t) => $this->data($t))->values(),
            'meta' => ['api_version' => '1', 'through_id' => $through,
                'after_id' => $rows->last()?->id ?? $after, 'has_more' => $more]]);
    }

    private function commentData(TaskComment $comment): array
    {
        return ['id'=>(int)$comment->id, 'uuid'=>$comment->client_uuid, 'task_id'=>(int)$comment->task_id,
            'body'=>$comment->body, 'author'=>(string)($comment->author_name ?? $comment->user_id),
            'created_at'=>$comment->created_at?->toIso8601String()??'', 'updated_at'=>$comment->updated_at?->toIso8601String()??''];
    }

    public function comments(Request $r, int $task)
    {
        Task::where('user_id',$r->user()->id)->findOrFail($task);
        $d=$r->validate(['after_id'=>'sometimes|integer|min:0','through_id'=>'sometimes|integer|min:0']);
        $through=$d['through_id']??(int)TaskComment::where('task_id',$task)->max('id');
        $after=(int)($d['after_id']??0);
        $rows=TaskComment::query()->join('users','users.id','=','task_comments.user_id')
            ->where('task_comments.task_id',$task)->where('task_comments.id','>',$after)
            ->where('task_comments.id','<=',$through)->orderBy('task_comments.id')->limit(51)
            ->get(['task_comments.*','users.name as author_name']);
        $more=$rows->count()>50;$rows=$rows->take(50);
        return response()->json(['data'=>$rows->map(fn($c)=>$this->commentData($c))->values(),
            'meta'=>['api_version'=>'1','through_id'=>$through,'after_id'=>$rows->last()?->id??$after,'has_more'=>$more]]);
    }

    public function labels(Request $r)
    {
        $d=$r->validate(['after_id'=>'sometimes|integer|min:0','through_id'=>'sometimes|integer|min:0']);
        $uid=$r->user()->id;$after=(int)($d['after_id']??0);
        $through=$d['through_id']??(int)Label::where('user_id',$uid)->max('id');
        $rows=Label::where('user_id',$uid)->where('id','>',$after)->where('id','<=',$through)->orderBy('id')->limit(101)->get();
        $more=$rows->count()>100;$rows=$rows->take(100);
        return response()->json(['data'=>$rows->map(fn($l)=>['id'=>(int)$l->id,'name'=>$l->name,'color'=>$l->color])->values(),
            'meta'=>['api_version'=>'1','through_id'=>$through,'after_id'=>$rows->last()?->id??$after,'has_more'=>$more]]);
    }

    public function operation(Request $r)
    {
        $d = $r->validate([
            'operation_uuid' => 'required|uuid',
            'kind' => ['required', Rule::in(['create', 'status', 'edit', 'comment', 'label'])],
            'title' => 'required_if:kind,create|prohibited_unless:kind,create|string|max:240',
            'task_id' => 'required_if:kind,status,edit,comment|prohibited_unless:kind,status,edit,comment|integer|min:1',
            'expected_version' => 'required_if:kind,status,edit|prohibited_unless:kind,status,edit|integer|min:1',
            'label_name' => 'required_if:kind,label|prohibited_unless:kind,label|string|max:40',
            'label_color' => ['required_if:kind,label','prohibited_unless:kind,label',Rule::in(['green','blue','purple','orange','red','gray'])],
            'comment_body' => 'required_if:kind,comment|prohibited_unless:kind,comment|string|max:10000',
            'status' => ['required_if:kind,status', 'prohibited_unless:kind,status', Rule::in(['todo', 'doing', 'done'])],
            'fields' => 'required_if:kind,edit|prohibited_unless:kind,edit|array:title,description,due_date,priority,project_id,checklist,label_ids|min:1',
            'fields.title' => 'sometimes|required|string|max:240',
            'fields.description' => 'sometimes|nullable|string|max:20000',
            'fields.due_date' => 'sometimes|nullable|date_format:Y-m-d',
            'fields.priority' => ['sometimes', Rule::in(['normal', 'high'])],
            'fields.project_id' => 'sometimes|nullable|integer|min:1',
            'fields.label_ids' => 'sometimes|array|list|max:20',
            'fields.label_ids.*' => 'required|integer|min:1|distinct',
            'fields.checklist' => 'sometimes|array|list|max:100',
            'fields.checklist.*' => 'required|array:text,done',
            'fields.checklist.*.text' => 'required|string|max:500',
            'fields.checklist.*.done' => 'required|boolean',
        ]);
        if (isset($d['fields']['checklist'])) {
            foreach ($d['fields']['checklist'] as &$item) ksort($item);
            unset($item);
        }
        if (isset($d['fields'])) ksort($d['fields']);
        ksort($d);
        $hash = hash('sha256', 'sync-operation-v1:'.json_encode($d, JSON_THROW_ON_ERROR));
        return app(RecurringTasks::class)->locked($r->user()->id, function () use ($r, $d, $hash) {
            $uid = $r->user()->id;
            $old = DB::table('api_requests')->where('user_id', $uid)->where('request_key', $d['operation_uuid'])->first();
            if ($old) {
                abort_unless(hash_equals($old->fingerprint, $hash), 409, 'UUID операции уже использован для другого содержимого.');
                return ApiData::response(json_decode($old->result, true), $old->status);
            }
            if ($d['kind'] === 'label') {
                $label=Label::where('user_id',$uid)->where('name',$d['label_name'])->first();
                if (!$label) $label=Label::create(['user_id'=>$uid,'name'=>$d['label_name'],'color'=>$d['label_color']]);
            } elseif ($d['kind'] === 'comment') {
                $task=Task::where('user_id',$uid)->findOrFail($d['task_id']);
                $comment=new TaskComment(['task_id'=>$task->id,'user_id'=>$uid,'body'=>$d['comment_body']]);
                $comment->client_uuid=$d['operation_uuid'];$comment->save();
                $comment->author_name=$r->user()->name;
            } elseif ($d['kind'] === 'create') {
                abort_if(Task::withTrashed()->where('user_id', $uid)->where('transfer_uuid', $d['operation_uuid'])->exists(), 409, 'UUID задачи уже существует.');
                $task = app(TaskOrder::class)->create($uid, ['title' => $d['title']]);
                $task->transfer_uuid = $d['operation_uuid'];
                $task->save();
            } else {
                $task = Task::where('user_id', $uid)->findOrFail($d['task_id']);
                abort_unless((int) $task->version === (int) $d['expected_version'], 409, 'Задача изменилась на другом устройстве.');
                abort_unless(Task::whereKey($task->id)->activeBoard()->exists(), 422, 'Сначала восстановите задачу или проект на сайте.');
                $fields=$d['kind'] === 'edit' ? $d['fields'] : ['status'=>$d['status']];
                $labelIds=$fields['label_ids']??null;unset($fields['label_ids']);
                if ($labelIds !== null) {
                    abort_unless(Label::where('user_id',$uid)->whereIn('id',$labelIds)->count()===count($labelIds),422,'Одна из меток недоступна.');
                }
                $before=(int)$task->version;
                $task = app(TaskOrder::class)->update($uid, $task->id, $fields);
                if ($labelIds !== null) {
                    $changed=$task->labels()->sync($labelIds);
                    if (($changed['attached']||$changed['detached']||$changed['updated']) && (int)$task->version===$before) Task::whereKey($task->id)->increment('version');
                }
            }
            $result = ['operation_uuid'=>$d['operation_uuid']];
            if ($d['kind']==='label') $result['label']=['id'=>(int)$label->id,'name'=>$label->name,'color'=>$label->color];
            else $result['task']=$this->data($task->fresh());
            if ($d['kind'] === 'comment') $result['comment']=$this->commentData($comment);
            $status = in_array($d['kind'], ['create','comment','label'], true) ? 201 : 200;
            DB::table('api_requests')->insert(['user_id' => $uid, 'request_key' => $d['operation_uuid'],
                'fingerprint' => $hash, 'result' => json_encode($result, JSON_THROW_ON_ERROR),
                'status' => $status, 'created_at' => now(), 'updated_at' => now()]);
            return ApiData::response($result, $status);
        });
    }
}

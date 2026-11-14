<?php
namespace App\Http\Controllers\Api;

use App\Models\Task;
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

    public function operation(Request $r)
    {
        $d = $r->validate([
            'operation_uuid' => 'required|uuid',
            'kind' => ['required', Rule::in(['create', 'status'])],
            'title' => 'required_if:kind,create|prohibited_unless:kind,create|string|max:240',
            'task_id' => 'required_if:kind,status|prohibited_unless:kind,status|integer|min:1',
            'expected_version' => 'required_if:kind,status|prohibited_unless:kind,status|integer|min:1',
            'status' => ['required_if:kind,status', 'prohibited_unless:kind,status', Rule::in(['todo', 'doing', 'done'])],
        ]);
        ksort($d);
        $hash = hash('sha256', 'sync-operation-v1:'.json_encode($d, JSON_THROW_ON_ERROR));
        return app(RecurringTasks::class)->locked($r->user()->id, function () use ($r, $d, $hash) {
            $uid = $r->user()->id;
            $old = DB::table('api_requests')->where('user_id', $uid)->where('request_key', $d['operation_uuid'])->first();
            if ($old) {
                abort_unless(hash_equals($old->fingerprint, $hash), 409, 'UUID операции уже использован для другого содержимого.');
                return ApiData::response(json_decode($old->result, true), $old->status);
            }
            if ($d['kind'] === 'create') {
                abort_if(Task::withTrashed()->where('user_id', $uid)->where('transfer_uuid', $d['operation_uuid'])->exists(), 409, 'UUID задачи уже существует.');
                $task = app(TaskOrder::class)->create($uid, ['title' => $d['title']]);
                $task->transfer_uuid = $d['operation_uuid'];
                $task->save();
            } else {
                $task = Task::where('user_id', $uid)->findOrFail($d['task_id']);
                abort_unless((int) $task->version === (int) $d['expected_version'], 409, 'Задача изменилась на другом устройстве.');
                abort_unless(Task::whereKey($task->id)->activeBoard()->exists(), 422, 'Сначала восстановите задачу или проект на сайте.');
                $task = app(TaskOrder::class)->update($uid, $task->id, ['status' => $d['status']]);
            }
            $result = ['operation_uuid' => $d['operation_uuid'], 'task' => $this->data($task->fresh())];
            $status = $d['kind'] === 'create' ? 201 : 200;
            DB::table('api_requests')->insert(['user_id' => $uid, 'request_key' => $d['operation_uuid'],
                'fingerprint' => $hash, 'result' => json_encode($result, JSON_THROW_ON_ERROR),
                'status' => $status, 'created_at' => now(), 'updated_at' => now()]);
            return ApiData::response($result, $status);
        });
    }
}

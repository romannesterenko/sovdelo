<?php
namespace App\Jobs;
use App\Services\TaskReminders;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Queue\Queueable;
class GenerateTaskReminders implements ShouldQueue {
 use Queueable;
 public int $tries=3;
 public int $timeout=60;
 public function __construct(public int $userId){}
 public function handle(TaskReminders $service):void {$service->generate($this->userId);}
}

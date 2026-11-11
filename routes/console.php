<?php
use Illuminate\Support\Facades\{Artisan,Schedule};
Artisan::command('sovdelo:recurring',function(){
 $count=0;\App\Models\User::select('id')->orderBy('id')->chunkById(100,function($users)use(&$count){foreach($users as $u)$count+=app(\App\Services\RecurringTasks::class)->generate($u->id);});
 $this->info("Создано повторяющихся задач: {$count}");
})->purpose('Создать наступившие повторяющиеся задачи');
Schedule::command('sovdelo:recurring')->everyMinute()->withoutOverlapping();

Artisan::command('sovdelo:reminders {--queue : Отправить обработку в очередь}',function(){
 $queued=(bool)$this->option('queue');$count=0;
 \App\Models\User::select('id')->orderBy('id')->chunkById(100,function($users)use($queued,&$count){foreach($users as $u){if($queued)\App\Jobs\GenerateTaskReminders::dispatch($u->id);else $count+=app(\App\Services\TaskReminders::class)->generate($u->id);}});
 $this->info($queued?'Обработка напоминаний поставлена в очередь.':"Создано уведомлений: {$count}");
})->purpose('Обработать напоминания задач');
Schedule::command('sovdelo:reminders')->everyMinute()->withoutOverlapping()->appendOutputTo(storage_path('logs/reminders.log'));

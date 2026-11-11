<?php
use Illuminate\Support\Facades\{Artisan,Schedule};
Artisan::command('sovdelo:recurring',function(){
 $count=0;\App\Models\User::select('id')->orderBy('id')->chunkById(100,function($users)use(&$count){foreach($users as $u)$count+=app(\App\Services\RecurringTasks::class)->generate($u->id);});
 $this->info("Создано повторяющихся задач: {$count}");
})->purpose('Создать наступившие повторяющиеся задачи');
Schedule::command('sovdelo:recurring')->everyMinute()->withoutOverlapping();

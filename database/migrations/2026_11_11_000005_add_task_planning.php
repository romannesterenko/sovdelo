<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\{DB,Schema};
return new class extends Migration {
 public function up():void {
  Schema::table('tasks',fn(Blueprint $t)=>$t->date('planned_date')->nullable()->index());
  Schema::table('users',fn(Blueprint $t)=>$t->string('timezone',64)->default('Europe/Moscow'));
  DB::table('tasks')->whereNotNull('due_date')->update(['planned_date'=>DB::raw('due_date')]);
 }
 public function down():void {
  Schema::table('tasks',function(Blueprint $t){$t->dropIndex(['planned_date']);$t->dropColumn('planned_date');});
  Schema::table('users',fn(Blueprint $t)=>$t->dropColumn('timezone'));
 }
};

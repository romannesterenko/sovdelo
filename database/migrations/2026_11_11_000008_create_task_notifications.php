<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;
return new class extends Migration {
 public function up():void {
  Schema::table('users',function(Blueprint $t){$t->boolean('notifications_enabled')->default(true);$t->boolean('deadline_notifications')->default(true);$t->string('notification_time',5)->default('09:00');});
  Schema::table('tasks',fn(Blueprint $t)=>$t->timestampTz('remind_at')->nullable()->index());
  Schema::create('task_notifications',function(Blueprint $t){$t->id();$t->foreignId('user_id')->constrained()->cascadeOnDelete();$t->foreignId('task_id')->nullable()->constrained()->nullOnDelete();$t->string('event_key',150);$t->string('kind',20);$t->string('title',240);$t->timestampTz('scheduled_at');$t->timestampTz('read_at')->nullable();$t->timestamps();$t->unique(['user_id','event_key']);$t->index(['user_id','read_at']);});
 }
 public function down():void {Schema::dropIfExists('task_notifications');Schema::table('tasks',function(Blueprint $t){$t->dropIndex(['remind_at']);$t->dropColumn('remind_at');});Schema::table('users',fn(Blueprint $t)=>$t->dropColumn(['notifications_enabled','deadline_notifications','notification_time']));}
};

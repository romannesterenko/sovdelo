<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\{Schema,DB};
return new class extends Migration {
 public function up():void {
  Schema::create('time_sessions',function(Blueprint $t){$t->id();$t->foreignId('user_id')->constrained()->cascadeOnDelete();$t->foreignId('task_id')->constrained()->cascadeOnDelete();$t->uuid('request_key');$t->timestampTz('started_at');$t->timestampTz('ended_at')->nullable();$t->unsignedBigInteger('duration_seconds')->default(0);$t->string('end_reason',24)->nullable();$t->timestamps();$t->unique(['user_id','request_key']);$t->index(['task_id','started_at']);});
  DB::statement('CREATE UNIQUE INDEX time_sessions_one_active ON time_sessions (user_id) WHERE ended_at IS NULL');
  Schema::create('timer_start_requests',function(Blueprint $t){$t->id();$t->foreignId('user_id')->constrained()->cascadeOnDelete();$t->foreignId('task_id')->constrained()->cascadeOnDelete();$t->uuid('request_key');$t->unique(['user_id','request_key']);$t->timestamps();});
  Schema::create('time_adjustments',function(Blueprint $t){$t->id();$t->foreignId('time_session_id')->constrained()->cascadeOnDelete();$t->foreignId('user_id')->constrained()->cascadeOnDelete();$t->unsignedBigInteger('previous_seconds');$t->unsignedBigInteger('new_seconds');$t->string('reason',500);$t->timestamps();});
 }
 public function down():void {Schema::dropIfExists('time_adjustments');Schema::dropIfExists('timer_start_requests');Schema::dropIfExists('time_sessions');}
};

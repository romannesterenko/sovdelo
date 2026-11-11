<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;
return new class extends Migration {
 public function up():void {
  Schema::create('task_series',function(Blueprint $t){$t->id();$t->uuid('request_key');$t->foreignId('user_id')->constrained()->cascadeOnDelete();$t->foreignId('project_id')->nullable()->constrained()->nullOnDelete();$t->string('title',240);$t->text('description')->nullable();$t->string('priority')->default('normal');$t->json('checklist');$t->json('label_ids');$t->string('frequency');$t->unsignedSmallInteger('anchor_day');$t->date('next_date');$t->boolean('active')->default(true);$t->timestamps();$t->unique(['user_id','request_key']);});
  Schema::table('tasks',function(Blueprint $t){$t->foreignId('task_series_id')->nullable()->constrained('task_series')->nullOnDelete();$t->date('occurrence_date')->nullable();$t->unique(['task_series_id','occurrence_date']);});
 }
 public function down():void {Schema::table('tasks',function(Blueprint $t){$t->dropUnique(['task_series_id','occurrence_date']);$t->dropConstrainedForeignId('task_series_id');$t->dropColumn('occurrence_date');});Schema::dropIfExists('task_series');}
};

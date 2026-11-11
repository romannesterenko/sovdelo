<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;
return new class extends Migration {
 public function up(): void {
  Schema::create('projects',function(Blueprint $t){$t->id();$t->foreignId('user_id')->constrained()->cascadeOnDelete();$t->string('name',120);$t->timestamps();});
  Schema::create('tasks',function(Blueprint $t){$t->id();$t->foreignId('user_id')->constrained()->cascadeOnDelete();$t->foreignId('project_id')->nullable()->constrained()->nullOnDelete();$t->string('title',240);$t->text('description')->nullable();$t->string('status',20)->default('todo');$t->string('priority',20)->default('normal');$t->date('due_date')->nullable();$t->json('checklist')->nullable();$t->timestamps();$t->index(['user_id','due_date']);});
 }
 public function down():void {Schema::dropIfExists('tasks');Schema::dropIfExists('projects');}
};

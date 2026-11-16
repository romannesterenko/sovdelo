<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;
return new class extends Migration {
 public function up():void {
  Schema::create('project_agents',function(Blueprint $t){
   $t->id();$t->foreignId('user_id')->constrained()->cascadeOnDelete();$t->foreignId('project_id')->constrained()->cascadeOnDelete();
   $t->foreignId('token_id')->nullable()->constrained('personal_access_tokens')->nullOnDelete();
   $t->string('name',80);$t->timestamp('revoked_at')->nullable();$t->timestamps();$t->unique('token_id');
  });
  Schema::create('task_responsibilities',function(Blueprint $t){
   $t->id();$t->foreignId('task_id')->unique()->constrained()->cascadeOnDelete();
   $t->foreignId('agent_id')->nullable()->constrained('project_agents')->nullOnDelete();
   $t->string('state',20)->default('todo');$t->text('report')->nullable();$t->timestamps();
  });
  Schema::create('project_activity',function(Blueprint $t){
   $t->id();$t->foreignId('user_id')->constrained()->cascadeOnDelete();$t->foreignId('project_id')->constrained()->cascadeOnDelete();
   $t->foreignId('task_id')->nullable()->constrained()->nullOnDelete();$t->foreignId('agent_id')->nullable()->constrained('project_agents')->nullOnDelete();
   $t->string('actor',100);$t->string('action',40);$t->json('details');$t->timestamps();$t->index(['project_id','id']);
  });
  Schema::create('agent_receipts',function(Blueprint $t){
   $t->id();$t->foreignId('agent_id')->constrained('project_agents')->cascadeOnDelete();$t->uuid('request_key');
   $t->string('fingerprint',64);$t->json('response');$t->timestamps();$t->unique(['agent_id','request_key']);
  });
 }
 public function down():void {foreach(['agent_receipts','project_activity','task_responsibilities','project_agents'] as $table)Schema::dropIfExists($table);}
};

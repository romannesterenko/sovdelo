<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;
return new class extends Migration {
 public function up():void {
  Schema::create('labels',function(Blueprint $t){$t->id();$t->foreignId('user_id')->constrained()->cascadeOnDelete();$t->string('name',40);$t->string('color',16);$t->timestamps();$t->unique(['user_id','name']);});
  Schema::create('task_label',function(Blueprint $t){$t->foreignId('task_id')->constrained()->cascadeOnDelete();$t->foreignId('label_id')->constrained()->cascadeOnDelete();$t->primary(['task_id','label_id']);});
  Schema::create('task_comments',function(Blueprint $t){$t->id();$t->foreignId('task_id')->constrained()->cascadeOnDelete();$t->foreignId('user_id')->constrained()->cascadeOnDelete();$t->text('body');$t->timestamps();});
  Schema::create('task_attachments',function(Blueprint $t){$t->id();$t->foreignId('task_id')->constrained()->cascadeOnDelete();$t->string('name',240);$t->string('path');$t->unsignedBigInteger('bytes');$t->timestamps();});
 }
 public function down():void {Schema::dropIfExists('task_attachments');Schema::dropIfExists('task_comments');Schema::dropIfExists('task_label');Schema::dropIfExists('labels');}
};

<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;
return new class extends Migration {
 public function up():void {
  Schema::table('projects',function(Blueprint $t){$t->text('description')->nullable();$t->unsignedBigInteger('cover_attachment_id')->nullable();$t->boolean('cover_disabled')->default(false);});
  Schema::create('project_attachments',function(Blueprint $t){$t->id();$t->foreignId('project_id')->constrained()->cascadeOnDelete();$t->string('name',240);$t->string('path');$t->unsignedBigInteger('bytes');$t->string('image_mime')->nullable();$t->timestamps();});
  Schema::create('project_credentials',function(Blueprint $t){$t->id();$t->foreignId('project_id')->constrained()->cascadeOnDelete();$t->string('name',120);$t->string('kind',20);$t->string('address',500)->nullable();$t->string('username',240)->nullable();$t->text('secret')->nullable();$t->text('notes')->nullable();$t->timestamps();});
 }
 public function down():void {Schema::dropIfExists('project_credentials');Schema::dropIfExists('project_attachments');Schema::table('projects',fn(Blueprint $t)=>$t->dropColumn(['description','cover_attachment_id','cover_disabled']));}
};

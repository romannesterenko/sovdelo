<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;
return new class extends Migration {
 public function up():void {
  Schema::table('task_attachments',function(Blueprint $t){$t->string('mime_type',100)->nullable();$t->unsignedInteger('image_width')->nullable();$t->unsignedInteger('image_height')->nullable();});
  Schema::table('tasks',function(Blueprint $t){$t->foreignId('cover_attachment_id')->nullable()->constrained('task_attachments')->nullOnDelete();$t->boolean('cover_disabled')->default(false);});
 }
 public function down():void {
  Schema::table('tasks',function(Blueprint $t){$t->dropConstrainedForeignId('cover_attachment_id');$t->dropColumn('cover_disabled');});
  Schema::table('task_attachments',fn(Blueprint $t)=>$t->dropColumn(['mime_type','image_width','image_height']));
 }
};

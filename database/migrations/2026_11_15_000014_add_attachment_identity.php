<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;
return new class extends Migration {
 public function up():void {Schema::table('task_attachments',function(Blueprint $t){$t->uuid('client_uuid')->nullable();$t->string('sha256',64)->nullable();$t->unique(['task_id','client_uuid']);});}
 public function down():void {Schema::table('task_attachments',function(Blueprint $t){$t->dropUnique(['task_id','client_uuid']);$t->dropColumn(['client_uuid','sha256']);});}
};

<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;
return new class extends Migration {
 public function up():void {Schema::table('task_comments',function(Blueprint $t){$t->uuid('client_uuid')->nullable();$t->unique(['user_id','client_uuid']);});}
 public function down():void {Schema::table('task_comments',function(Blueprint $t){$t->dropUnique(['user_id','client_uuid']);$t->dropColumn('client_uuid');});}
};

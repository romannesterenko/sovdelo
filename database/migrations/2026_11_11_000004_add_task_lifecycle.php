<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;
return new class extends Migration {
 public function up():void {
  Schema::table('tasks',function(Blueprint $t){$t->timestamp('archived_at')->nullable()->index();$t->softDeletes();});
  Schema::table('projects',fn(Blueprint $t)=>$t->timestamp('archived_at')->nullable()->index());
 }
 public function down():void {
  Schema::table('tasks',function(Blueprint $t){$t->dropIndex(['archived_at']);$t->dropColumn('archived_at');$t->dropSoftDeletes();});
  Schema::table('projects',function(Blueprint $t){$t->dropIndex(['archived_at']);$t->dropColumn('archived_at');});
 }
};

<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\{DB,Schema};
return new class extends Migration {
 public function up():void {
  Schema::table('tasks',function(Blueprint $t){$t->bigInteger('sort_order')->default(0);$t->index(['user_id','project_id','status','sort_order'],'tasks_board_order_index');});
  DB::table('tasks')->update(['sort_order'=>DB::raw('id * 1024')]);
 }
 public function down():void {Schema::table('tasks',function(Blueprint $t){$t->dropIndex('tasks_board_order_index');$t->dropColumn('sort_order');});}
};

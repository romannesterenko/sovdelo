<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\{DB,Schema};
return new class extends Migration {
 public function up():void {
  Schema::create('board_columns',function(Blueprint $t){$t->id();$t->foreignId('user_id')->constrained()->cascadeOnDelete();$t->string('key',40);$t->string('name',80);$t->string('kind',10);$t->integer('sort_order');$t->timestamps();$t->unique(['user_id','key']);});
  Schema::table('tasks',fn(Blueprint $t)=>$t->string('board_column',40)->default('todo')->index());
  DB::table('tasks')->update(['board_column'=>DB::raw('status')]);
  DB::table('users')->orderBy('id')->chunkById(200,function($users){foreach($users as $u)foreach(['todo'=>'К выполнению','doing'=>'В работе','done'=>'Готово'] as $key=>$name)DB::table('board_columns')->insert(['user_id'=>$u->id,'key'=>$key,'name'=>$name,'kind'=>$key,'sort_order'=>array_search($key,['todo','doing','done'])*1024,'created_at'=>now(),'updated_at'=>now()]);});
 }
 public function down():void {Schema::table('tasks',function(Blueprint $t){$t->dropIndex(['board_column']);$t->dropColumn('board_column');});Schema::dropIfExists('board_columns');}
};

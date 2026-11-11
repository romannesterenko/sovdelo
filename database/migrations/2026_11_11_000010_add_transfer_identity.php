<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\{DB,Schema};
use Illuminate\Support\Str;
return new class extends Migration {
 public function up():void {
  foreach(['projects','tasks'] as $table){Schema::table($table,function(Blueprint $t){$t->uuid('transfer_uuid')->nullable();$t->unique(['user_id','transfer_uuid']);});DB::table($table)->orderBy('id')->chunkById(200,function($rows)use($table){foreach($rows as $r)DB::table($table)->where('id',$r->id)->update(['transfer_uuid'=>(string)Str::uuid()]);});}
  Schema::create('import_batches',function(Blueprint $t){$t->id();$t->foreignId('user_id')->constrained()->cascadeOnDelete();$t->uuid('request_key');$t->string('fingerprint',64);$t->string('strategy',10);$t->json('result');$t->timestamps();$t->unique(['user_id','request_key']);});
 }
 public function down():void {Schema::dropIfExists('import_batches');foreach(['tasks','projects'] as $table)Schema::table($table,function(Blueprint $t){$t->dropUnique(['user_id','transfer_uuid']);$t->dropColumn('transfer_uuid');});}
};

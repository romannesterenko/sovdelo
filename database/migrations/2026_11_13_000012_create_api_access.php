<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;
return new class extends Migration {
 public function up():void {
  Schema::create('personal_access_tokens',function(Blueprint $t){$t->id();$t->morphs('tokenable');$t->string('name',80);$t->string('token',64)->unique();$t->text('abilities')->nullable();$t->timestamp('last_used_at')->nullable();$t->timestamp('expires_at')->nullable()->index();$t->unsignedInteger('auth_version')->default(0);$t->timestamps();});
  Schema::create('api_requests',function(Blueprint $t){$t->id();$t->foreignId('user_id')->constrained()->cascadeOnDelete();$t->uuid('request_key');$t->string('fingerprint',64);$t->json('result');$t->unsignedSmallInteger('status');$t->timestamps();$t->unique(['user_id','request_key']);});
  foreach(['projects','tasks'] as $table)Schema::table($table,fn(Blueprint $t)=>$t->unsignedBigInteger('version')->default(1));
 }
 public function down():void {foreach(['tasks','projects'] as $table)Schema::table($table,fn(Blueprint $t)=>$t->dropColumn('version'));Schema::dropIfExists('api_requests');Schema::dropIfExists('personal_access_tokens');}
};

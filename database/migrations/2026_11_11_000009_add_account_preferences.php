<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;
return new class extends Migration {
 public function up():void {Schema::table('users',function(Blueprint $t){$t->string('theme',10)->default('dark');$t->unsignedInteger('auth_version')->default(0);});}
 public function down():void {Schema::table('users',fn(Blueprint $t)=>$t->dropColumn(['theme','auth_version']));}
};

<?php
namespace App\Http\Controllers;
use App\Services\DevelopmentPlan;
use Illuminate\Http\Request;
class DevelopmentPlanController {
 public function preview(Request $r,DevelopmentPlan $plan){return $plan->preview($r->user()->id);}
 public function import(Request $r,DevelopmentPlan $plan){$d=$r->validate(['fingerprint'=>'required|string|size:64']);return $plan->import($r->user()->id,$d['fingerprint']);}
}

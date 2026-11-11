<?php
namespace App\Http\Controllers;
use App\Services\DataTransfer;
use Illuminate\Http\Request;
use Illuminate\Validation\{Rule,ValidationException};
class DataTransferController {
 public function export(Request $r,DataTransfer $service){$d=$service->export($r->user()->id);return response()->json($d,200,['Content-Disposition'=>'attachment; filename="sovdelo-export-'.now()->format('Y-m-d-His').'.json"','Cache-Control'=>'no-store'],JSON_UNESCAPED_UNICODE);}
 private function input(Request $r):array {return $r->validate(['payload'=>'required|string','strategy'=>['required',Rule::in(['skip','copy'])]]);}
 public function preview(Request $r,DataTransfer $service){$v=$this->input($r);$d=$service->parse($v['payload']);return ['fingerprint'=>hash('sha256',$v['payload']),'summary'=>$service->preview($r->user()->id,$d,$v['strategy'])];}
 public function import(Request $r,DataTransfer $service){$v=$this->input($r);$r->validate(['fingerprint'=>'required|string|size:64','request_key'=>'required|uuid']);$hash=hash('sha256',$v['payload']);if(!hash_equals($hash,$r->input('fingerprint')))throw ValidationException::withMessages(['fingerprint'=>'Файл изменился. Повторите предварительный просмотр.']);$d=$service->parse($v['payload']);return $service->import($r->user()->id,$d,$v['strategy'],$hash,$r->input('request_key'));}
}

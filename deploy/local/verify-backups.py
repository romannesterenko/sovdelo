#!/usr/bin/env python3
"""Verify downloaded snapshots without reading or printing environment contents."""
import argparse,hashlib,json,pathlib,re,tarfile,datetime,sys
FILES={'.env','database.dump','files.tar.gz'}
def digest(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  while b:=f.read(1024*1024):h.update(b)
 return h.hexdigest()
def verify(folder,force=False):
 manifest=folder/'SHA256SUMS'
 if folder.is_symlink() or manifest.is_symlink():raise ValueError('Символическая ссылка вместо копии')
 if not manifest.is_file():return 'incomplete'
 expected={}
 for line in manifest.read_text().splitlines():
  m=re.fullmatch(r'([a-f0-9]{64}) [ *](\.env|database\.dump|files\.tar\.gz)',line)
  if not m or m[2] in expected:raise ValueError('Неверный список контрольных сумм')
  expected[m[2]]=m[1]
 if set(expected)!=FILES:raise ValueError('Неполный список контрольных сумм')
 stamp={'manifest':digest(manifest),'files':{}}
 for name in FILES:
  p=folder/name
  if p.is_symlink() or not p.is_file():raise ValueError('Не найден обычный файл '+name)
  stat=p.stat();stamp['files'][name]=[stat.st_size,stat.st_mtime_ns]
 cache=folder/'.verified.json'
 if not force and cache.is_file() and not cache.is_symlink():
  try:
   if json.loads(cache.read_text())==stamp:return 'cached'
  except (ValueError,OSError):pass
 for name,wanted in expected.items():
  if digest(folder/name)!=wanted:raise ValueError('Не совпала контрольная сумма '+name)
 with tarfile.open(folder/'files.tar.gz','r:gz') as archive:
  for m in archive:
   p=pathlib.PurePosixPath(m.name)
   if p.is_absolute() or '..' in p.parts or not p.parts or p.parts[0]!='app' or not(m.isfile() or m.isdir()):raise ValueError('Небезопасный путь/тип в архиве файлов')
 if cache.is_symlink():raise ValueError('Небезопасный файл проверки')
 temp=folder/'.verified.tmp'
 if temp.is_symlink():raise ValueError('Небезопасный временный файл')
 temp.write_text(json.dumps(stamp));temp.chmod(0o600);temp.replace(cache)
 return 'verified'
def main():
 parser=argparse.ArgumentParser();parser.add_argument('directory',type=pathlib.Path);parser.add_argument('--force',action='store_true');a=parser.parse_args()
 counts={'verified':0,'cached':0,'incomplete':0,'failed':0};ready=[]
 for folder in sorted(a.directory.iterdir()):
  if not folder.is_dir() or folder.name.startswith('.'):continue
  try:
   result=verify(folder,a.force);counts[result]+=1
   if result in ('verified','cached'):ready.append(folder.name)
  except (ValueError,OSError,tarfile.TarError) as e:counts['failed']+=1;print(folder.name+': '+str(e),file=sys.stderr)
 report={'checked_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'counts':counts,'newest_ready':max(ready) if ready else None}
 (a.directory/'.last-sync.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
 print(json.dumps(report,ensure_ascii=False))
 return 0 if ready and not counts['failed'] else 1
if __name__=='__main__':raise SystemExit(main())

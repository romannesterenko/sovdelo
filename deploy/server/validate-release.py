import sys,tarfile,json,re,pathlib
with tarfile.open(sys.argv[1]) as t:
 members=t.getmembers();total=0;metadata=None
 if len(members)>100000:raise SystemExit('Слишком много файлов')
 for m in members:
  p=pathlib.PurePosixPath(m.name)
  if p.is_absolute() or '..' in p.parts or not(m.isfile() or m.isdir()):raise SystemExit('Небезопасный элемент архива')
  if any(x in ['vendor','node_modules','backups','.git'] or x=='.env' or (x.startswith('.env.') and x!='.env.example') for x in p.parts):raise SystemExit('В архиве данные или секреты')
  total+=m.size
  if p.parts==('.sovdelo-release.json',):metadata=json.load(t.extractfile(m))
 if total>1024**3:raise SystemExit('Архив слишком большой')
 names={str(pathlib.PurePosixPath(m.name)) for m in members}
 if not {'composer.lock','artisan','public/build/manifest.json'}.issubset(names):raise SystemExit('Нет исходников или готовой сборки')
 if not metadata or not re.fullmatch('[0-9a-f]{40}',metadata.get('commit','')):raise SystemExit('Нет метаданных Git-коммита')
 print(metadata['commit'])

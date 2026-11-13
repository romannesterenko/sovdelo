#!/usr/bin/env python3
"""Pack committed source and the already tested frontend build, never local env/data."""
import pathlib,subprocess,sys,tempfile,tarfile,shutil,json,datetime
root=pathlib.Path(__file__).resolve().parents[1]
output=pathlib.Path(sys.argv[1]).resolve()
sha=subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip()
if len(sys.argv)>2 and sys.argv[2]!=sha:raise SystemExit('Commit mismatch')
build=root/'public/build'
if not (build/'manifest.json').is_file():raise SystemExit('Run npm run build first')
with tempfile.TemporaryDirectory() as temp:
 stage=pathlib.Path(temp)/'source';stage.mkdir()
 data=subprocess.check_output(['git','archive','HEAD'],cwd=root)
 source=pathlib.Path(temp)/'source.tar';source.write_bytes(data)
 with tarfile.open(source) as t:t.extractall(stage,filter='data')
 for name in ['storage','bootstrap/cache','public/hot','public/build']:
  p=stage/name
  if p.is_symlink() or p.is_file():p.unlink()
  elif p.is_dir():shutil.rmtree(p)
 (stage/'storage').mkdir();(stage/'bootstrap/cache').mkdir(parents=True,exist_ok=True)
 shutil.copytree(build,stage/'public/build')
 (stage/'.sovdelo-release.json').write_text(json.dumps({'commit':sha,'built_at':datetime.datetime.now(datetime.timezone.utc).isoformat()}))
 output.parent.mkdir(parents=True,exist_ok=True)
 with tarfile.open(output,'w:gz') as t:
  for p in sorted(stage.iterdir()):t.add(p,arcname='./'+p.name)
 subprocess.run([sys.executable,str(root/'deploy/server/validate-release.py'),str(output)],check=True)
 print(output)

import io,json,pathlib,subprocess,sys,tarfile,tempfile,unittest
VALIDATOR=pathlib.Path(__file__).resolve().parents[1]/'server/validate-release.py'
class ReleaseTest(unittest.TestCase):
 def check(self,extra=None,omit=None):
  with tempfile.TemporaryDirectory() as temp:
   archive=pathlib.Path(temp)/'release.tar.gz'
   data={'.sovdelo-release.json':json.dumps({'commit':'a'*40}),'composer.lock':'{}','artisan':'<?php','public/build/manifest.json':'{}'}
   if omit:data.pop(omit)
   with tarfile.open(archive,'w:gz') as t:
    for name,value in data.items():
     b=value.encode();m=tarfile.TarInfo('./'+name);m.size=len(b);t.addfile(m,io.BytesIO(b))
    if extra:
     name,kind=extra;m=tarfile.TarInfo(name)
     if kind=='symlink':m.type=tarfile.SYMTYPE;m.linkname='/etc/passwd'
     t.addfile(m)
   return subprocess.run([sys.executable,str(VALIDATOR),str(archive)],capture_output=True,text=True)
 def test_valid(self):
  r=self.check();self.assertEqual(r.returncode,0,r.stderr);self.assertEqual(r.stdout.strip(),'a'*40)
 def test_missing_build(self):self.assertNotEqual(self.check(omit='public/build/manifest.json').returncode,0)
 def test_missing_metadata(self):self.assertNotEqual(self.check(omit='.sovdelo-release.json').returncode,0)
 def test_parent_path(self):self.assertNotEqual(self.check(('../escape','file')).returncode,0)
 def test_absolute_path(self):self.assertNotEqual(self.check(('/etc/escape','file')).returncode,0)
 def test_symlink(self):self.assertNotEqual(self.check(('public/storage','symlink')).returncode,0)
 def test_environment(self):self.assertNotEqual(self.check(('./.env','file')).returncode,0)
 def test_dependencies(self):self.assertNotEqual(self.check(('./node_modules/file','file')).returncode,0)
if __name__=='__main__':unittest.main()

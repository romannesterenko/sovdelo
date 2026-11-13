import pathlib,subprocess,sys,tempfile,shutil,tarfile,json,os,unittest
DEPLOY=pathlib.Path(__file__).resolve().parents[1]
class ActionsTest(unittest.TestCase):
 def test_forced_command_rejects_shell_and_malformed_protocol(self):
  for command in ['id','bash','deploy '+'a'*40+' 1; id','deploy HEAD 1','deploy '+'a'*40+' 0']:
   with self.subTest(command=command):
    r=subprocess.run(['bash',str(DEPLOY/'server/ssh-deploy.sh')],env={**os.environ,'SSH_ORIGINAL_COMMAND':command},capture_output=True)
    self.assertEqual(r.returncode,64)
 def fixture(self,p):
  (p/'deploy/server').mkdir(parents=True);(p/'public/build').mkdir(parents=True)
  shutil.copy(DEPLOY/'build-artifact.py',p/'deploy/build-artifact.py');shutil.copy(DEPLOY/'server/validate-release.py',p/'deploy/server/validate-release.py')
  (p/'.gitignore').write_text('/.env\n/public/build/\n/storage/\n');(p/'composer.lock').write_text('{}');(p/'artisan').write_text('<?php');(p/'README.md').write_text('committed')
  for args in [['init','-q'],['config','user.email','test@example.com'],['config','user.name','Test'],['add','.'],['commit','-qm','fixture']]:subprocess.run(['git',*args],cwd=p,check=True)
  (p/'public/build/manifest.json').write_text('{}');(p/'public/build/app.js').write_text('built asset');(p/'.env').write_text('SECRET=private');(p/'storage').mkdir();(p/'storage/test.txt').write_text('runtime')
 def test_artifact_uses_commit_and_excludes_local_secrets_and_runtime(self):
  with tempfile.TemporaryDirectory() as d:
   p=pathlib.Path(d);self.fixture(p);(p/'README.md').write_text('uncommitted');out=p/'out.tar.gz'
   r=subprocess.run([sys.executable,str(p/'deploy/build-artifact.py'),str(out)],capture_output=True,text=True);self.assertEqual(r.returncode,0,r.stderr)
   with tarfile.open(out) as t:
    self.assertEqual(t.extractfile('./README.md').read(),b'committed');self.assertEqual(t.extractfile('./public/build/app.js').read(),b'built asset');names=[m.name for m in t.getmembers()];self.assertNotIn('./.env',names);self.assertNotIn('./storage/test.txt',names)
 def test_wrong_commit_is_rejected(self):
  with tempfile.TemporaryDirectory() as d:
   p=pathlib.Path(d);self.fixture(p)
   r=subprocess.run([sys.executable,str(p/'deploy/build-artifact.py'),str(p/'out.tar.gz'),'b'*40],capture_output=True);self.assertNotEqual(r.returncode,0)
 def test_receiver_rejects_empty_stream(self):
  with tempfile.TemporaryDirectory() as d:
   r=subprocess.run([sys.executable,str(DEPLOY/'server/receive-release.py'),str(pathlib.Path(d)/'file')],input=b'',capture_output=True);self.assertNotEqual(r.returncode,0)
 def test_receiver_preserves_bytes(self):
  with tempfile.TemporaryDirectory() as d:
   p=pathlib.Path(d)/'file';r=subprocess.run([sys.executable,str(DEPLOY/'server/receive-release.py'),str(p)],input=b'abc\x00\xff',capture_output=True);self.assertEqual(r.returncode,0);self.assertEqual(p.read_bytes(),b'abc\x00\xff')
if __name__=='__main__':unittest.main()

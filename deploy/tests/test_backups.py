import pathlib,tempfile,tarfile,hashlib,io,importlib.util,unittest
P=pathlib.Path(__file__).resolve().parents[1]/'local/verify-backups.py'
spec=importlib.util.spec_from_file_location('verify_backups',P);v=importlib.util.module_from_spec(spec);spec.loader.exec_module(v)
class BackupTest(unittest.TestCase):
 def fixture(self,p,name='app/private/file.txt'):
  (p/'.env').write_text('private environment');(p/'database.dump').write_bytes(b'dump')
  with tarfile.open(p/'files.tar.gz','w:gz') as t:
   m=tarfile.TarInfo(name);m.size=4;t.addfile(m,io.BytesIO(b'data'))
  (p/'SHA256SUMS').write_text(''.join(hashlib.sha256((p/n).read_bytes()).hexdigest()+'  '+n+'\n' for n in sorted(v.FILES)))
 def test_verified_and_cached(self):
  with tempfile.TemporaryDirectory() as d:
   p=pathlib.Path(d);self.fixture(p);self.assertEqual(v.verify(p),'verified');self.assertEqual(v.verify(p),'cached');self.assertEqual(v.verify(p,True),'verified')
 def test_changed_data_rejected(self):
  with tempfile.TemporaryDirectory() as d:
   p=pathlib.Path(d);self.fixture(p);v.verify(p);(p/'database.dump').write_bytes(b'changed')
   with self.assertRaises(ValueError):v.verify(p)
 def test_incomplete_copy_not_verified(self):
  with tempfile.TemporaryDirectory() as d:self.assertEqual(v.verify(pathlib.Path(d)),'incomplete')
 def test_manifest_cannot_reference_local_private_files(self):
  with tempfile.TemporaryDirectory() as d:
   p=pathlib.Path(d);self.fixture(p);(p/'SHA256SUMS').write_text('a'*64+'  /etc/passwd\n')
   with self.assertRaises(ValueError):v.verify(p)
 def test_archive_path_traversal_rejected(self):
  with tempfile.TemporaryDirectory() as d:
   p=pathlib.Path(d);self.fixture(p,'../escape')
   with self.assertRaises(ValueError):v.verify(p)
 def test_symlink_rejected(self):
  with tempfile.TemporaryDirectory() as d:
   p=pathlib.Path(d);self.fixture(p);(p/'database.dump').unlink();(p/'database.dump').symlink_to('/etc/passwd')
   with self.assertRaises(ValueError):v.verify(p)
 def test_missing_file_rejected(self):
  with tempfile.TemporaryDirectory() as d:
   p=pathlib.Path(d);self.fixture(p);(p/'.env').unlink()
   with self.assertRaises(ValueError):v.verify(p)

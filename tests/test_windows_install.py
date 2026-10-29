"""Exercise the real offline installer against disposable fake profiles."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]

@unittest.skipUnless(os.name=='nt' and shutil.which('powershell.exe'),'Windows PowerShell required')
class WindowsInstallation(unittest.TestCase):
    def test_install_noop_backup_and_foreign_file(self):
        bundle=(ROOT/'plugins/chimera_autoexp/init.lua').read_bytes()
        version=json.loads((ROOT/'manifest.json').read_text('utf-8'))['version']
        with tempfile.TemporaryDirectory(prefix='chimeraxp-install-') as temp:
            profile=Path(temp)
            target=profile/'chimera_wtyczki/chimera_autoexp/init.lua'
            def install():
                return subprocess.run(['powershell.exe','-NoProfile','-ExecutionPolicy','Bypass',
                    '-File',str(ROOT/'installer/ChimeraXP.ps1'),'-Source','Local','-ProfileDir',str(profile)],
                    capture_output=True,timeout=30)
            result=install();self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            self.assertEqual(target.read_bytes(),bundle)
            stamp=target.stat().st_mtime_ns
            result=install();self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            self.assertEqual(target.stat().st_mtime_ns,stamp,'no-op must not replace the file')
            old=bundle.replace(version.encode(),b'0.6.0-beta.2')
            target.write_bytes(old)
            result=install();self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            self.assertEqual(target.read_bytes(),bundle)
            self.assertTrue(any(p.read_bytes()==old for p in (profile/'ChimeraXP/backups').glob('*.lua')))
            foreign=b'-- unrelated addon'
            target.write_bytes(foreign)
            result=install();self.assertNotEqual(result.returncode,0)
            self.assertEqual(target.read_bytes(),foreign,'unknown code must remain untouched')

if __name__=='__main__':
    unittest.main()

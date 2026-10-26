"""Release checks for the public Mudlet bootstrap and source manifest."""
import hashlib
import json
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class ReleaseIntegrity(unittest.TestCase):
    def test_manifest_schema_and_plugin(self):
        manifest = json.loads((ROOT / 'manifest.json').read_text('utf-8'))
        self.assertEqual(manifest['name'], 'ChimeraXP')
        self.assertEqual(manifest['schema'], 1)
        self.assertEqual(len(manifest['files']), 1)
        item = manifest['files'][0]
        self.assertEqual(item['path'], 'plugins/chimera_autoexp/init.lua')
        src = (ROOT / item['path']).read_bytes()
        self.assertEqual(hashlib.sha256(src).hexdigest(), item['sha256'])
        self.assertIn(f'version = "{manifest["version"]}"'.encode(), src)

    def test_installer_is_lightweight_and_matches_source(self):
        src = (ROOT / 'installer/mudlet_updater.lua').read_text('utf-8')
        xml = (ROOT / 'packages/ChimeraXP.xml').read_text('utf-8')
        root = ET.fromstring(xml)
        self.assertEqual(root.tag, 'MudletPackage')
        scripts = root.findall('.//Script')
        self.assertEqual(len(scripts), 1)
        self.assertEqual(scripts[0].findtext('script').strip(), src.strip())
        self.assertLess(len(xml), 15000)
        self.assertIn('sysDownloadDone', src)
        self.assertIn('sysDownloadError', src)

    def test_windows_installer_still_has_offline_support(self):
        if not (ROOT / 'installer/ChimeraXP.ps1').exists():
            self.skipTest('legacy Windows installer not staged locally')
        powershell = (ROOT / 'installer/ChimeraXP.ps1').read_text('utf-8')
        self.assertIn('Sha256 $data', powershell)
        self.assertIn('gh auth status', powershell)  # legacy CLI update path
        self.assertIn('-Source Local', (ROOT / 'install.cmd').read_text('utf-8'))


if __name__ == '__main__':
    unittest.main()

"""Bootstrap/manifest consistency: stdlib only, no network needed."""
from pathlib import Path
import hashlib
import json
import re
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


class OnlineInstallerTests(unittest.TestCase):
    def test_manifest_matches_plugin(self):
        m = json.loads((ROOT / 'manifest.json').read_text('utf8'))
        self.assertEqual(m['name'], 'ChimeraXP')
        self.assertEqual(m['schema'], 1)
        self.assertEqual(len(m['files']), 1)
        item = m['files'][0]
        self.assertEqual(item['path'], 'plugins/chimera_autoexp/init.lua')
        source = (ROOT / item['path']).read_bytes()
        self.assertEqual(hashlib.sha256(source).hexdigest(), item['sha256'])
        self.assertIn(f'version = "{m["version"]}"'.encode(), source)
        self.assertIn(f'{{"Wersja", "{m["version"]}"}}'.encode(), source)
        self.assertIn(b'command("aktualizuj", nil,', source)

    def test_package_embeds_exact_updater(self):
        xml = (ROOT / 'packages/ChimeraXP.xml').read_text('utf8')
        root = ET.fromstring(xml)
        self.assertEqual(root.tag, 'MudletPackage')
        scripts = root.findall('.//Script')
        self.assertEqual(len(scripts), 1)
        code = scripts[0].findtext('script')
        self.assertIsNotNone(code)
        self.assertEqual(code.strip(), (ROOT / 'installer/mudlet_updater.lua').read_text('utf8').strip())
        self.assertLess(len(xml), 15000)  # stable lightweight bootstrap, no embedded game code
        self.assertNotIn('local payload = [==[', code)
        self.assertIn('sysDownloadDone', code)
        self.assertIn('sysDownloadError', code)
        self.assertIn('os.rename', code)
        self.assertIn('loadstring', code)

    def test_no_tokens_embedded(self):
        src = (ROOT / 'installer/mudlet_updater.lua').read_text('utf8')
        self.assertNotIn('Authorization: token', src)
        self.assertNotIn('gh auth', src)
        self.assertIn('https://raw.githubusercontent.com/gnomidlo/ChimeraXP/main/', src)


if __name__ == '__main__':
    unittest.main()

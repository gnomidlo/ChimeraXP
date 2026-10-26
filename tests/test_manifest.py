"""Local integrity checks: python tests/test_manifest.py"""
import hashlib
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ReleaseIntegrity(unittest.TestCase):
    def test_manifest_schema_and_only_owned_plugin(self):
        manifest = json.loads((ROOT / "manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(manifest["name"], "ChimeraXP")
        self.assertEqual(manifest["schema"], 1)
        self.assertEqual(manifest["channel"], "beta")
        self.assertEqual(len(manifest["files"]), 1)
        entry = manifest["files"][0]
        self.assertEqual(entry["path"], "plugins/chimera_autoexp/init.lua")
        file = ROOT / entry["path"]
        self.assertTrue(file.is_file())
        self.assertEqual(hashlib.sha256(file.read_bytes()).hexdigest(), entry["sha256"])
        self.assertTrue(file.read_text(encoding="utf-8").startswith(
            "-- Chimera AutoExp 5 / standalone plugin"))
        self.assertIn(f'version = "{manifest["version"]}"', file.read_text(encoding="utf-8"))

    def test_windows_installer_uses_auth_not_shared_tokens(self):
        installer = (ROOT / "installer" / "ChimeraXP.ps1").read_text(encoding="utf-8")
        self.assertIn("gh auth status", installer)
        self.assertIn("gh api", installer)
        self.assertIn("-Source GitHub", (ROOT / "update.cmd").read_text(encoding="utf-8"))
        self.assertIn("-Source Local", (ROOT / "install.cmd").read_text(encoding="utf-8"))
        self.assertIn("Sha256 $data", installer)
        self.assertIn("$onlyPluginFile = 'plugins/chimera_autoexp/init.lua'", installer)


if __name__ == "__main__":
    unittest.main()
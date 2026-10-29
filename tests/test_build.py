"""The installed single-file bundle must exactly match reviewed modules."""
import importlib.util
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[1]

class GeneratedPlugin(unittest.TestCase):
    def test_reproducible_bundle(self):
        spec=importlib.util.spec_from_file_location('chimeraxp_build',ROOT/'build.py')
        module=importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        module.build(check=True)

if __name__=='__main__':
    unittest.main()

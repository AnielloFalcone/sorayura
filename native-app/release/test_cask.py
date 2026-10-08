"""Exercise Cask generation using synthetic manifests, never a distributable app."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

GENERATOR = Path(__file__).with_name('write-cask.py')


def fixture(folder):
    artifact = folder / 'Sorayura-0.5.1-arm64.dmg'
    artifact.write_bytes(b'SYNTHETIC TEST DATA - NOT A MACOS APP')
    return dict(version='0.5.1', build='4', mode='release', state='prepared',
                signing='Developer ID + notarized', architecture='arm64', minimum_macos='14.0',
                artifact=artifact.name, sha256=hashlib.sha256(artifact.read_bytes()).hexdigest(),
                app_notarization={'status': 'Accepted'}, dmg_notarization={'status': 'Accepted'})


class CaskTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.folder = Path(self.temporary.name)
        self.manifest = self.folder / 'manifest.json'
        self.output = self.folder / 'Casks/sorayura.rb'
        self.data = fixture(self.folder)

    def generate(self):
        self.manifest.write_text(json.dumps(self.data))
        return subprocess.run([sys.executable, str(GENERATOR), str(self.manifest),
                               '--repository', 'AnielloFalcone/sorayura', '--tag', 'v0.5.1-beta.1',
                               '--output', str(self.output)], capture_output=True, text=True)

    def rejected(self):
        result = self.generate()
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertFalse(self.output.exists())

    def test_valid_release_and_ruby_syntax(self):
        result = self.generate()
        self.assertEqual(result.returncode, 0, result.stderr)
        cask = self.output.read_text()
        self.assertIn('version "0.5.1,4"', cask)
        self.assertIn('/releases/download/v0.5.1-beta.1/Sorayura-0.5.1-arm64.dmg', cask)
        self.assertIn('uninstall quit: "dev.aniello.macsystemwallpaper.native"', cask)
        syntax = subprocess.run(['ruby', '-c', str(self.output)], capture_output=True, text=True)
        self.assertEqual(syntax.returncode, 0, syntax.stderr)
        original = self.output.read_bytes()
        self.assertNotEqual(self.generate().returncode, 0)
        self.assertEqual(self.output.read_bytes(), original)

    def test_candidate_rejected(self):
        self.data['mode'] = 'candidate'
        self.rejected()

    def test_notarization_rejected(self):
        self.data['dmg_notarization']['status'] = 'Invalid'
        self.rejected()

    def test_adhoc_signature_rejected(self):
        self.data['signing'] = 'ad hoc + hardened runtime'
        self.rejected()

    def test_changed_checksum_rejected(self):
        (self.folder / self.data['artifact']).write_bytes(b'changed')
        self.rejected()

    def test_traversal_rejected(self):
        self.data['artifact'] = '../Sorayura-0.5.1-arm64.dmg'
        self.rejected()

    def test_ruby_injection_rejected(self):
        self.data['version'] = '0.5.1"; abort "bad'
        self.rejected()

    def test_unverified_architecture_rejected(self):
        self.data['architecture'] = 'x86_64'
        self.rejected()


if __name__ == '__main__':
    unittest.main()

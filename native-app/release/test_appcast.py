"""Test feed generation boundaries without accessing a signing key."""
import contextlib
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET

spec = importlib.util.spec_from_file_location('appcast', Path(__file__).with_name('write-appcast.py'))
appcast = importlib.util.module_from_spec(spec)
spec.loader.exec_module(appcast)


class AppcastTests(unittest.TestCase):
    def setUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        self.root = Path(folder.name)
        self.artifact = self.root / 'Sorayura-0.5.1-arm64-ADHOC.dmg'
        self.artifact.write_bytes(b'SYNTHETIC TEST DATA - NOT A MACOS APP')
        self.data = dict(version='0.5.1', build='35', mode='adhoc-release', state='prepared',
                         artifact=self.artifact.name, sha256=hashlib.sha256(self.artifact.read_bytes()).hexdigest(),
                         update_public_key='test-public-key', minimum_macos='14.0')
        self.output = self.root / 'appcast.xml'

    def generate(self, tag='v0.5.1-beta.3', public_key='test-public-key'):
        manifest = self.root / 'manifest.json'
        manifest.write_text(json.dumps(self.data))
        def tool(args, **kwargs):
            return public_key if Path(args[0]).name == 'generate_keys' else 'test-signature'
        with patch.object(appcast.subprocess, 'check_output', side_effect=tool), contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            appcast.main([str(manifest), '--tag', tag, '--output', str(self.output)])

    def test_valid_feed(self):
        self.generate()
        item = ET.parse(self.output).find('channel/item')
        self.assertEqual(item.find(f'{{{appcast.SPARKLE}}}version').text, '35')
        enclosure = item.find('enclosure')
        self.assertEqual(enclosure.get('url'), f'https://github.com/AnielloFalcone/sorayura/releases/download/v0.5.1-beta.3/{self.artifact.name}')
        self.assertEqual(enclosure.get('length'), str(self.artifact.stat().st_size))
        self.assertEqual(enclosure.get(f'{{{appcast.SPARKLE}}}edSignature'), 'test-signature')

    def test_refuses_candidate(self):
        self.data['mode'] = 'candidate'
        with self.assertRaises(SystemExit): self.generate()
        self.assertFalse(self.output.exists())

    def test_self_signed_feed_explains_certificate_changes(self):
        self.data['mode'] = 'self-signed-release'
        self.generate()
        item = ET.parse(self.output).find('channel/item')
        self.assertIn('not notarized', item.findtext('description'))
        self.assertIn('signing certificate change', item.findtext('description'))

    def test_refuses_modified_package(self):
        self.artifact.write_bytes(b'MODIFIED')
        with self.assertRaises(SystemExit): self.generate()
        self.assertFalse(self.output.exists())

    def test_refuses_wrong_signing_key(self):
        with self.assertRaises(SystemExit): self.generate(public_key='other-key')
        self.assertFalse(self.output.exists())

    def test_refuses_mismatched_tag(self):
        with self.assertRaises(SystemExit): self.generate(tag='v0.5.2-beta.3')
        self.assertFalse(self.output.exists())

    def test_stable_release_requires_a_stable_tag(self):
        self.data.update(channel='stable', mode='self-signed-release', build='71')
        with self.assertRaises(SystemExit): self.generate()
        self.generate(tag='v0.5.1')
        item = ET.parse(self.output).find('channel/item')
        self.assertEqual(item.findtext(f'{{{appcast.SPARKLE}}}shortVersionString'), '0.5.1')
        self.assertEqual(item.findtext(f'{{{appcast.SPARKLE}}}version'), '71')

    def test_refuses_path_outside_package_folder(self):
        self.data['artifact'] = '../other.dmg'
        with self.assertRaises(SystemExit): self.generate()
        self.assertFalse(self.output.exists())


if __name__ == '__main__':
    unittest.main()

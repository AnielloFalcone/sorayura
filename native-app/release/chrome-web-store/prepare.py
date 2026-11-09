#!/usr/bin/env python3
"""Create an upload-only Chrome Web Store ZIP; never publish or change Chrome."""
import hashlib
import json
import re
import shutil
from pathlib import Path
import struct
import zipfile

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'Resources/SpotifyWebExtension'
FILES = ['page.js', 'content.js', 'worker.js']


def main():
    manifest = json.loads((SOURCE / 'manifest.json').read_text())
    assert re.fullmatch(r'\d+(?:\.\d+){0,3}', manifest['version'])
    assert set(manifest['icons'].values()) == {f'icons/icon{size}.png' for size in [16, 32, 48, 128]}
    assert manifest['manifest_version'] == 3
    assert manifest['permissions'] == ['nativeMessaging']
    assert manifest['host_permissions'] == ['https://open.spotify.com/*']
    # The Store assigns its own identity. Keep the local-development key out.
    manifest.pop('key', None)
    names = FILES + sorted(set(manifest['icons'].values()))
    for size, name in manifest['icons'].items():
        image = (SOURCE / name).read_bytes()
        assert image[:8] == b'\x89PNG\r\n\x1a\n'
        assert struct.unpack('>II', image[16:24]) == (int(size), int(size))
    destination = ROOT / 'releases/chrome-web-store' / manifest['version']
    destination.mkdir(parents=True, exist_ok=True)
    output = destination / f"sorayura-spotify-web-{manifest['version']}.zip"
    with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as archive:
        content = {'manifest.json': (json.dumps(manifest, indent=2) + '\n').encode()}
        content.update({name: (SOURCE / name).read_bytes() for name in names})
        for name, data in sorted(content.items()):
            entry = zipfile.ZipInfo(name, (2026, 11, 2, 0, 0, 0))
            entry.compress_type = zipfile.ZIP_DEFLATED
            entry.external_attr = 0o100644 << 16
            archive.writestr(entry, data)
    with zipfile.ZipFile(output) as archive:
        assert archive.testzip() is None
        assert set(archive.namelist()) == set(names + ['manifest.json'])
        assert 'key' not in json.loads(archive.read('manifest.json'))
    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    (destination / 'SHA256SUMS').write_text(f'{digest}  {output.name}\n')
    for name in ['LISTING.md', 'PRIVACY.md', 'REVIEW.md']:
        shutil.copyfile(Path(__file__).parent / name, destination / name)
    shutil.copyfile(SOURCE / 'icons/icon128.png', destination / 'store-icon128.png')
    print(output)
    print('Verified ZIP, icon dimensions, permissions and SHA-256. Store identity not assigned yet.')


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Generate a draft Cask from an accepted, signed release manifest; never publish."""
import argparse
import hashlib
import json
import re
from pathlib import Path
from urllib.parse import quote

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('manifest', type=Path)
p.add_argument('--repository', required=True, help='owner/repository hosting the release')
p.add_argument('--tag', required=True)
p.add_argument('--output', type=Path, required=True)
a = p.parse_args()
m = json.loads(a.manifest.read_text())
if not isinstance(m, dict):
    p.error('Expected a release manifest object')
if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', a.repository):
    p.error('Expected GitHub owner/repository')
if not re.fullmatch(r'[A-Za-z0-9_.-]+', a.tag):
    p.error('Expected a simple release tag')
if m.get('mode') != 'release' or m.get('state') != 'prepared' or m.get('signing') != 'Developer ID + notarized' or any(
        m.get(key, {}).get('status') != 'Accepted' for key in ['app_notarization', 'dmg_notarization']):
    p.error('Only a Developer ID notarized release can produce a Cask')
if m.get('architecture') != 'arm64' or m.get('minimum_macos') != '14.0':
    p.error('The current Cask supports only the verified arm64 / macOS 14+ release matrix')
if not isinstance(m.get('version'), str) or not re.fullmatch(r'\d+\.\d+\.\d+', m['version']):
    p.error('Expected a numeric x.y.z version')
if not isinstance(m.get('build'), str) or not re.fullmatch(r'\d+', m['build']):
    p.error('Expected a numeric build number')
if not isinstance(m.get('sha256'), str) or not re.fullmatch(r'[0-9a-f]{64}', m['sha256']):
    p.error('Expected a SHA-256 checksum')
if not isinstance(m.get('artifact'), str) or not re.fullmatch(r'Sorayura-[A-Za-z0-9_.-]+\.dmg', m['artifact']) or 'CANDIDATE' in m['artifact']:
    p.error('Expected a Sorayura release DMG filename')
artifact = a.manifest.parent / m['artifact']
if not artifact.is_file():
    p.error('Release artifact does not exist')
if artifact.parent.resolve() != a.manifest.parent.resolve() or hashlib.sha256(artifact.read_bytes()).hexdigest() != m['sha256']:
    p.error('Artifact is missing, outside the release folder or its checksum changed')
if a.output.exists():
    p.error('Output exists; refusing to overwrite')
url = f'https://github.com/{a.repository}/releases/download/{quote(a.tag)}/{quote(artifact.name)}'
a.output.parent.mkdir(parents=True, exist_ok=True)
a.output.write_text(f'''cask "sorayura" do
  version "{m['version']},{m['build']}"
  sha256 "{m['sha256']}"

  url "{url}"
  name "Sorayura"
  desc "System widgets and animated desktop backgrounds"
  homepage "https://github.com/{a.repository}"

  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "Sorayura.app"

  uninstall quit: "dev.aniello.macsystemwallpaper.native"

  caveats <<~EOS
    Before uninstalling, disable Open at Login and any Claude hooks from the app.
    Layouts and preferences are preserved when uninstalling.
  EOS
end
''')
print(a.output)

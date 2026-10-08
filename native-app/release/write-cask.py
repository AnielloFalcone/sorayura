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
if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', a.repository):
    p.error('Expected GitHub owner/repository')
if not re.fullmatch(r'[A-Za-z0-9_.-]+', a.tag):
    p.error('Expected a simple release tag')
if m.get('mode') != 'release' or m.get('state') != 'prepared' or any(
        m.get(key, {}).get('status') != 'Accepted' for key in ['app_notarization', 'dmg_notarization']):
    p.error('Only a Developer ID notarized release can produce a Cask')
artifact = a.manifest.parent / m['artifact']
if artifact.parent.resolve() != a.manifest.parent.resolve() or hashlib.sha256(artifact.read_bytes()).hexdigest() != m['sha256']:
    p.error('Artifact is missing, outside the release folder or its checksum changed')
if a.output.exists():
    p.error('Output exists; refusing to overwrite')
url = f'https://github.com/{a.repository}/releases/download/{quote(a.tag)}/{quote(artifact.name)}'
a.output.parent.mkdir(parents=True, exist_ok=True)
a.output.write_text(f'''cask "sorayura" do
  version "{m['version']}"
  sha256 "{m['sha256']}"

  url "{url}"
  name "Sorayura"
  desc "System widgets and animated desktop for macOS"
  homepage "https://github.com/{a.repository}"

  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "Sorayura.app"

  caveats <<~EOS
    Before uninstalling, disable Open at Login and any Claude hooks from the app.
    Layouts and preferences are preserved when uninstalling.
  EOS
end
''')
print(a.output)

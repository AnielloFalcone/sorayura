#!/usr/bin/env python3
"""Sign a prepared public update and its feed using Sorayura's Keychain key.
Run before publication; upload the DMG first, then publish the signed feed unchanged.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
SPARKLE = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', SPARKLE)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('manifest', type=Path)
    parser.add_argument('--tag', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args(argv)
    manifest = json.loads(args.manifest.read_text())
    if manifest['state'] != 'prepared' or manifest['mode'] not in ('adhoc-release', 'self-signed-release', 'release'):
        parser.error('Only prepared public artifacts can enter the update feed')
    if not re.fullmatch('v' + re.escape(manifest['version']) + r'(?:-beta\.\d+)?', args.tag):
        parser.error('Tag must match the prepared version')
    artifact = args.manifest.parent / manifest['artifact']
    if artifact.name != manifest['artifact'] or not artifact.name.endswith('.dmg'):
        parser.error('Expected a DMG filename')
    if hashlib.sha256(artifact.read_bytes()).hexdigest() != manifest['sha256']:
        parser.error('Artifact changed after preparation')
    tools = ROOT / '.build/artifacts/sparkle/Sparkle/bin'
    def run(tool, *arguments):
        return subprocess.check_output([str(tools / tool), '--account', 'sorayura', *map(str, arguments)], text=True).strip()
    if run('generate_keys', '-p') != manifest['update_public_key']:
        parser.error('Signing key does not match the key embedded in the app')
    signature = run('sign_update', '-p', artifact)
    run('sign_update', '--verify', artifact, signature)
    rss = ET.Element('rss', version='2.0')
    channel = ET.SubElement(rss, 'channel')
    ET.SubElement(channel, 'title').text = 'Sorayura updates'
    item = ET.SubElement(channel, 'item')
    ET.SubElement(item, 'title').text = f"Sorayura {args.tag.removeprefix('v')} (build {manifest['build']})"
    ET.SubElement(item, f'{{{SPARKLE}}}version').text = manifest['build']
    ET.SubElement(item, f'{{{SPARKLE}}}shortVersionString').text = args.tag.removeprefix('v')
    ET.SubElement(item, f'{{{SPARKLE}}}minimumSystemVersion').text = manifest['minimum_macos']
    description = 'Update Sorayura while keeping your settings.'
    if manifest['mode'] != 'release':
        description += ' This beta is not notarized by Apple.'
    if manifest['mode'] == 'self-signed-release':
        description += ' After a signing certificate change, macOS may ask you to grant access again.'
    ET.SubElement(item, 'description').text = description
    ET.SubElement(item, 'enclosure', {
        'url': f"https://github.com/AnielloFalcone/sorayura/releases/download/{args.tag}/{artifact.name}",
        'length': str(artifact.stat().st_size), 'type': 'application/octet-stream',
        f'{{{SPARKLE}}}edSignature': signature,
    })
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=args.output.parent) as tmp:
        feed = Path(tmp) / 'appcast.xml'
        ET.indent(rss)
        ET.ElementTree(rss).write(feed, encoding='utf-8', xml_declaration=True)
        run('sign_update', feed)
        run('sign_update', '--verify', feed)
        feed.replace(args.output)
    print(args.output)


if __name__ == '__main__':
    main()

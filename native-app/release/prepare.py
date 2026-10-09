#!/usr/bin/env python3
"""Build/check/package a local candidate or Developer ID notarized beta.

Never publishes to GitHub or alters login items, hooks or user preferences.
Credentials stay in an existing Keychain profile. No passwords are arguments.
"""
import argparse
import hashlib
import json
import os
import plistlib
import re
import shutil
import subprocess
import tempfile
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CHECKS = ['--check-m1', '--check-m2', '--check-observation', '--check-resources',
          '--check-sampling', '--check-agent-performance', '--check-localization']


def run(args, log, **kwargs):
    result = subprocess.run([str(a) for a in args], text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, **kwargs)
    with log.open('a') as stream:
        stream.write('$ ' + ' '.join(str(a) for a in args) + '\n' + result.stdout + '\n')
    if result.returncode:
        raise RuntimeError(f'{args[0]} failed ({result.returncode}); see {log}')
    return result.stdout


def notarize(path, profile, log):
    result = json.loads(run(['xcrun', 'notarytool', 'submit', path, '--keychain-profile',
                             profile, '--wait', '--output-format', 'json'], log, timeout=1800))
    if result.get('status') != 'Accepted':
        raise RuntimeError(f'Notarization was not accepted: {result.get("id")}')
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['candidate', 'release'])
    parser.add_argument('--version', default='0.5.1')
    parser.add_argument('--build', default='12')
    parser.add_argument('--identity', help='Exact Developer ID Application identity')
    parser.add_argument('--notary-profile', help='Existing notarytool Keychain profile name')
    args = parser.parse_args()
    if not re.fullmatch(r'\d+\.\d+\.\d+', args.version) or not re.fullmatch(r'\d+', args.build):
        parser.error('Version must be x.y.z and build must be numeric')
    public = args.mode == 'release'
    if public and (not args.identity or not args.identity.startswith('Developer ID Application:') or not args.notary_profile):
        parser.error('Release requires --identity "Developer ID Application: …" and --notary-profile')
    if not public and (args.identity or args.notary_profile):
        parser.error('Candidate mode uses a local signature; signing credentials belong to release mode')
    destination = ROOT / 'releases' / f'{args.version}-{args.build}-{args.mode}'
    destination.mkdir(parents=True, exist_ok=False)
    log = destination / 'preparation.log'
    manifest = {'version': args.version, 'build': args.build, 'channel': 'beta',
                'mode': args.mode, 'state': 'preparing', 'public_distribution_ready': False,
                'created': datetime.now(timezone.utc).isoformat(), 'checks': {}}
    try:
        with tempfile.TemporaryDirectory(prefix='wallpaper-release-', dir=destination) as temporary:
            staging = Path(temporary)
            env = os.environ.copy()
            env.update(WALLPAPER_VERSION=args.version, WALLPAPER_BUILD=args.build,
                       WALLPAPER_OUTPUT_ROOT=str(staging / 'build'), WALLPAPER_HARDENED='1',
                       WALLPAPER_SIGN_ID=args.identity if public else '-')
            run([ROOT / 'build-native.sh'], log, cwd=ROOT, env=env, timeout=300)
            app = staging / 'build' / 'Sorayura.app'
            binary = app / 'Contents/MacOS/Sorayura'
            info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
            if info['CFBundleShortVersionString'] != args.version or info['CFBundleVersion'] != args.build:
                raise RuntimeError('Bundle version mismatch')
            architecture = run(['lipo', '-archs', binary], log).strip()
            if architecture != 'arm64':
                raise RuntimeError(f'Candidate matrix only verified for arm64, got {architecture}')
            dependencies = run(['otool', '-L', binary], log)
            for line in dependencies.splitlines()[1:]:
                dependency = line.strip().split(' (')[0]
                if not dependency.startswith(('/System/Library/', '/usr/lib/')):
                    raise RuntimeError(f'Unexpected non-system dependency: {dependency}')
            for check in CHECKS:
                run([binary, check], log, cwd=staging, timeout=180)
                manifest['checks'][check] = 'passed'
            run(['codesign', '--verify', '--deep', '--strict', app], log)
            signature = run(['codesign', '-dvv', app], log)
            if 'runtime' not in signature:
                raise RuntimeError('Hardened runtime missing')
            if public and ('Authority=Developer ID Application:' not in signature or 'Timestamp=' not in signature):
                raise RuntimeError('Developer ID signature or secure timestamp missing')
            manifest.update(architecture=architecture, minimum_macos=info['LSMinimumSystemVersion'],
                            tested_macos=run(['sw_vers', '-productVersion'], log).strip(),
                            binary_sha256=hashlib.sha256(binary.read_bytes()).hexdigest())
            if public:
                upload = staging / 'notarize-app.zip'
                run(['ditto', '-c', '-k', '--keepParent', app, upload], log)
                manifest['app_notarization'] = notarize(upload, args.notary_profile, log)
                run(['xcrun', 'stapler', 'staple', app], log)
                run(['xcrun', 'stapler', 'validate', app], log)
                run(['spctl', '--assess', '--type', 'execute', '--verbose=2', app], log)
            contents = staging / 'image'
            contents.mkdir()
            shutil.copytree(app, contents / app.name)
            (contents / 'Applications').symlink_to('/Applications')
            for name in ['READ-ME.txt', 'PRIVACY.md', 'RELEASE-NOTES.md']:
                shutil.copy2(ROOT / 'release' / name, contents / name)
            shutil.copy2(ROOT.parent / 'LICENSE', contents / 'LICENSE')
            suffix = '' if public else '-CANDIDATE-NON-DISTRIBUIRE'
            dmg = destination / f'Sorayura-{args.version}-arm64{suffix}.dmg'
            run(['hdiutil', 'create', '-volname', f'Sorayura {args.version}',
                 '-srcfolder', contents, '-format', 'UDZO', '-ov', dmg], log, timeout=180)
            if public:
                run(['codesign', '--sign', args.identity, '--timestamp', dmg], log)
                manifest['dmg_notarization'] = notarize(dmg, args.notary_profile, log)
                run(['xcrun', 'stapler', 'staple', dmg], log)
                run(['xcrun', 'stapler', 'validate', dmg], log)
                run(['spctl', '--assess', '--type', 'open', '--context', 'context:primary-signature', '--verbose=2', dmg], log)
            run(['hdiutil', 'verify', dmg], log, timeout=120)
            sha = hashlib.sha256(dmg.read_bytes()).hexdigest()
            (destination / 'SHA256SUMS').write_text(f'{sha}  {dmg.name}\n')
            manifest.update(state='prepared', artifact=dmg.name, sha256=sha,
                            signing='Developer ID + notarized' if public else 'ad hoc + hardened runtime',
                            public_distribution_ready=False,
                            remaining_gate=('Physical QA for this exact artifact, downloaded artifact on another Mac, and approval of release destination/materials'
                                            if public else 'Developer ID signing/notarization, physical QA, downloaded final artifact on another Mac, and approval of release destination/materials'))
            print(str(dmg))
    except Exception as error:
        manifest.update(state='failed', error=str(error))
        raise
    finally:
        (destination / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')


if __name__ == '__main__':
    main()

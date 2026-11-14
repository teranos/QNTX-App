#!/usr/bin/env python3
"""The archive, exported as an IPA that carries the island.

The Tauri CLI exports with the app's profile alone. The island is its own
bundle with its own profile, so the archive is exported here with the options
ios-project.py wrote, which name both.

The Tauri CLI signs the archive from a keychain of its own and takes that
keychain away when it is done, so the export finds no certificate. It is given
one here, from IOS_CERTIFICATE and IOS_CERTIFICATE_PASSWORD, in a keychain
made for the export and removed after it.
"""
import base64
import os
from pathlib import Path
import secrets
import subprocess
import tempfile

root = Path('gen/apple')
archives = list(root.rglob('*.xcarchive'))
if len(archives) != 1:
    raise SystemExit(f'expected one iOS archive, found {len(archives)}')
archive = archives[0]
islands = list((archive / 'Products/Applications').glob('*.app/PlugIns/IslandWidget.appex'))
if len(islands) != 1:
    raise SystemExit('the archive does not carry the island: no IslandWidget.appex in the app')
metadata = list((archive / 'Products/Applications').glob('*.app/Metadata.appintents'))
if len(metadata) != 1:
    for app in (archive / 'Products/Applications').glob('*.app'):
        print('in', app.name + ':', sorted(held.name for held in app.iterdir()))
    raise SystemExit('the app carries no Metadata.appintents: the system would find no press to run in it')


# 「[Fable 5.2, Opus 5.5] What the island needs of the app itself, read from what was built: where the」
# 「[Fable 5.2, Opus 5.5] node is, for a press to ask it, and that the app may have Live Activities.」
import plistlib

for app in (archive / 'Products/Applications').glob('*.app'):
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    print('the app says:', {key: info.get(key) for key in ('QNTXNode', 'NSSupportsLiveActivities', 'CFBundleVersion')})
    if not str(info.get('QNTXNode', '')).startswith(('https://', 'http://')):
        raise SystemExit('the app names no node in QNTXNode: a press on the island would ask nobody')
    if info.get('NSSupportsLiveActivities') is not True:
        raise SystemExit('the app does not say NSSupportsLiveActivities: the system starts no Live Activity for it')
    widget = plistlib.loads((app / 'PlugIns/IslandWidget.appex/Info.plist').read_bytes())
    print('the island says:', {key: widget.get(key) for key in ('CFBundleIdentifier', 'MinimumOSVersion', 'NSExtension')})


def security(*args, **kwargs):
    return subprocess.run(['security', *args], check=True, **kwargs)


certificate = os.environ.get('IOS_CERTIFICATE', '')
if not certificate:
    raise SystemExit('IOS_CERTIFICATE is empty: the export has no certificate to sign with')

with tempfile.TemporaryDirectory() as held:
    keychain = str(Path(held) / 'island-export.keychain-db')
    opens = secrets.token_hex(16)
    p12 = Path(held) / 'certificate.p12'
    p12.write_bytes(base64.b64decode(certificate))
    before = [line.strip().strip('"') for line in
              security('list-keychains', '-d', 'user', capture_output=True, text=True).stdout.splitlines() if line.strip()]
    security('create-keychain', '-p', opens, keychain)
    try:
        security('set-keychain-settings', '-lut', '3600', keychain)
        security('unlock-keychain', '-p', opens, keychain)
        security('import', str(p12), '-k', keychain, '-P', os.environ.get('IOS_CERTIFICATE_PASSWORD', ''),
                 '-T', '/usr/bin/codesign', '-T', '/usr/bin/security', stdout=subprocess.DEVNULL)
        security('set-key-partition-list', '-S', 'apple-tool:,apple:', '-s', '-k', opens, keychain,
                 stdout=subprocess.DEVNULL)
        security('list-keychains', '-d', 'user', '-s', keychain, *before)
        subprocess.run(['xcodebuild', '-exportArchive', '-archivePath', str(archive),
                        '-exportOptionsPlist', str(root / 'IslandExportOptions.plist'),
                        '-exportPath', str(root / 'build/island-export')], check=True)
    finally:
        security('list-keychains', '-d', 'user', '-s', *before)
        security('delete-keychain', keychain)

# 「[Fable 5.2, Opus 5.5] What the app that was exported is signed as being allowed: read back from」
# 「[Fable 5.2, Opus 5.5] the IPA itself, for what was written into the project is not what Apple」
# 「[Fable 5.2, Opus 5.5] reads. Without aps-environment Apple gives the app no token of any kind.」
import zipfile

ipas = list((root / 'build/island-export').glob('*.ipa'))
if len(ipas) != 1:
    raise SystemExit(f'expected one exported IPA, found {len(ipas)}')
with tempfile.TemporaryDirectory() as unpacked:
    with zipfile.ZipFile(ipas[0]) as ipa:
        ipa.extractall(unpacked)
    for app in Path(unpacked).glob('Payload/*.app'):
        for signed in [app, app / 'PlugIns/IslandWidget.appex']:
            read = subprocess.run(['codesign', '-d', '--entitlements', '-', '--xml', str(signed)],
                                  capture_output=True, check=True)
            allowed = plistlib.loads(read.stdout) if read.stdout.strip() else {}
            print(signed.name, 'is signed with:', {key: allowed[key] for key in sorted(allowed)})
        of_the_app = plistlib.loads(subprocess.run(
            ['codesign', '-d', '--entitlements', '-', '--xml', str(app)], capture_output=True, check=True).stdout)
        if 'aps-environment' not in of_the_app:
            raise SystemExit('the exported app is signed without aps-environment: Apple gives it no token to be reached by')

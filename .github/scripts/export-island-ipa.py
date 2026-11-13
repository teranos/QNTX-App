#!/usr/bin/env python3
"""The archive, exported as an IPA that carries the island.

The Tauri CLI exports with the app's profile alone. The island is its own
bundle with its own profile, so the archive is exported here with the options
ios-project.py wrote, which name both.
"""
from pathlib import Path
import subprocess

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
subprocess.run(['xcodebuild', '-exportArchive', '-archivePath', str(archive),
                '-exportOptionsPlist', str(root / 'IslandExportOptions.plist'),
                '-exportPath', str(root / 'build/island-export')], check=True)

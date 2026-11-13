#!/usr/bin/env python3
"""Tauri 2.11.4 exports only the host profile; export both targets explicitly."""
from pathlib import Path
import subprocess

root = Path('gen/apple')
archives = list(root.rglob('*.xcarchive'))
if len(archives) != 1:
    raise RuntimeError(f'Expected one iOS archive, found {len(archives)}')
archive = archives[0]
extensions = list((archive / 'Products/Applications').glob('*.app/PlugIns/QNTXShare.appex'))
if len(extensions) != 1:
    raise RuntimeError('Archive does not embed the screenshot share extension')
subprocess.run(['xcodebuild', '-exportArchive', '-archivePath', str(archive),
                '-exportOptionsPlist', str(root / 'ShareExportOptions.plist'),
                '-exportPath', str(root / 'build/share-export')], check=True)

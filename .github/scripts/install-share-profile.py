#!/usr/bin/env python3
"""Install and validate the share extension profile without printing its contents."""
import base64
import datetime
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile

with tempfile.TemporaryDirectory() as temp:
    profile = Path(temp) / 'share.mobileprovision'
    profile.write_bytes(base64.b64decode(os.environ['IOS_SHARE_MOBILE_PROVISION'], validate=True))
    value = plistlib.loads(subprocess.check_output(['security', 'cms', '-D', '-i', str(profile)]))
    team = os.environ['APPLE_DEVELOPMENT_TEAM']
    assert value['Name'] == os.environ['SHARE_PROVISIONING_PROFILE'], 'Extension profile name mismatch'
    assert team in value['TeamIdentifier'], 'Extension profile team mismatch'
    assert value['ExpirationDate'] > datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None), 'Extension profile expired'
    entitlements = value['Entitlements']
    assert entitlements['application-identifier'].endswith('.nl.sbvh.qntx.share'), 'Wrong extension bundle identifier'
    assert 'group.nl.sbvh.qntx' in entitlements['com.apple.security.application-groups'], 'Missing App Group entitlement'
    destination = Path.home() / 'Library/MobileDevice/Provisioning Profiles'
    destination.mkdir(parents=True, exist_ok=True)
    (destination / (value['UUID'] + '.mobileprovision')).write_bytes(profile.read_bytes())
print('Share extension provisioning profile installed')

"""The newest crash report of QNTX, as its crashing thread says it: each frame's image and symbol.

python3 ci/app-idle/crash.py ~/Library/Logs/DiagnosticReports
"""
import glob
import json
import os
import sys

reports = sorted(glob.glob(os.path.join(sys.argv[1], 'QNTX*.ips')), key=os.path.getmtime)
if not reports:
    sys.exit('no crash report of QNTX')
with open(reports[-1]) as f:
    head = json.loads(f.readline())
    body = json.loads(f.read())
print(reports[-1], head.get('timestamp'))
print('exception', json.dumps(body.get('exception')))
print('termination', json.dumps(body.get('termination')))
for key in ('asi', 'crashInfo', 'lastExceptionBacktrace'):
    if key in body:
        print(key, json.dumps(body[key])[:3000])
images = body.get('usedImages', [])
thread = body['threads'][body.get('faultingThread', 0)]
for i, frame in enumerate(thread.get('frames', [])[:60]):
    image = images[frame['imageIndex']] if frame.get('imageIndex', -1) < len(images) else {}
    name = image.get('name') or os.path.basename(image.get('path', '?'))
    print(f"{i:3} {name:30} {frame.get('symbol', hex(frame.get('imageOffset', 0)))}+{frame.get('symbolLocation', '')}")

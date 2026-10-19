#!/usr/bin/env python3
"""What the app costs when nobody touches it, as WebKit counts it.

"WebKit's own guidance suggests aiming for less than 3% average CPU usage
during an idle session, with a recording of at least 15 seconds"

The app runs in the iPhone Simulator, so the app and the web view's processes are
processes of the runner, and `ps` reads them. CPU use is the change in their CPU
time over the change in clock time, in percent of one core: what WebKit's
CPUTime::percentageCPUUsageSince counts. Memory is the resident size.

  sample.py <udid> <name> <windows> <seconds>

Reads <windows> windows of <seconds> each, one after the other, and says each one
and the average over all. Exits 1 when the average of everything the app runs is
3% or more, 2 when the processes could not be told apart or one was replaced
while it was read.
"""
import json
import os
import shutil
import subprocess
import sys
import time

# WebKit: idle pages should strive for a Low rating, less than 3% average CPU.
THRESHOLD = 3.0

# What is told apart by its command. The app is the shell; the others are the
# processes the web view does its work in.
KINDS = [
    ('app', '/QNTX.app/'),
    ('WebContent', 'com.apple.WebKit.WebContent'),
    ('GPU', 'com.apple.WebKit.GPU'),
    ('Networking', 'com.apple.WebKit.Networking'),
]


def seconds(cputime):
    """ps prints CPU time as [[h:]m:]s.cc, from the right."""
    return sum(float(part) * 60 ** i for i, part in enumerate(reversed(cputime.split(':'))))


def processes():
    out = subprocess.run(
        ['ps', '-axo', 'pid=,ppid=,cputime=,rss=,command='],
        capture_output=True, text=True, check=True,
    ).stdout
    rows = []
    for line in out.splitlines():
        parts = line.split(None, 4)
        if len(parts) < 5:
            continue
        pid, ppid, cputime, rss, command = parts
        rows.append({'pid': int(pid), 'ppid': int(ppid), 'cpu': seconds(cputime), 'rss': int(rss), 'command': command})
    return rows


def under(udid, rows):
    """The processes this simulator started: its launchd_sim and everything below it."""
    roots = [r['pid'] for r in rows if 'launchd_sim' in r['command'] and udid in r['command']]
    found = set(roots)
    grew = True
    while grew:
        grew = False
        for r in rows:
            if r['ppid'] in found and r['pid'] not in found:
                found.add(r['pid'])
                grew = True
    return [r for r in rows if r['pid'] in found and r['pid'] not in roots]


def snapshot(udid):
    rows = under(udid, processes())
    kinds = {}
    for name, mark in KINDS:
        mine = [r for r in rows if mark in r['command']]
        kinds[name] = {
            'cpu': sum(r['cpu'] for r in mine),
            'rss_kb': sum(r['rss'] for r in mine),
            'pids': sorted(r['pid'] for r in mine),
        }
    return {'at': time.monotonic(), 'kinds': kinds, 'seen': len(rows)}


def diagnose(name, kinds):
    """Where the CPU is, kept beside the numbers: what each busy process is
    doing (`sample`, a call graph over ten seconds) and how often it is woken
    (`top`, whose `idlew` is idle wakeups and `power` its energy impact).
    A run that cannot take them says so and goes on."""
    if shutil.which('sample') is None or shutil.which('top') is None:
        print('no sample or top here, so what the processes were doing is not kept')
        return
    os.makedirs('idle-samples', exist_ok=True)
    for kind in ('app', 'WebContent', 'GPU'):
        for pid in kinds[kind]['pids']:
            base = 'idle-samples/%s-%s-%d' % (name, kind, pid)
            for command, path, wait in (
                (['top', '-l', '2', '-s', '10', '-pid', str(pid), '-stats', 'pid,command,cpu,idlew,power,mem,threads'], base + '.top.txt', 60),
                (['sample', str(pid), '10', '-file', base + '.sample.txt'], base + '.sample.log', 60),
            ):
                try:
                    done = subprocess.run(command, capture_output=True, text=True, timeout=wait)
                    with open(path, 'w') as out:
                        out.write(done.stdout + done.stderr)
                except (OSError, subprocess.SubprocessError) as why:
                    print('%s did not run: %s' % (command[0], why), file=sys.stderr)


def main():
    udid, name, windows, window = sys.argv[1], sys.argv[2], int(sys.argv[3]), float(sys.argv[4])

    first = snapshot(udid)
    if not first['kinds']['app']['pids']:
        # Nothing to measure. Say what is there, so the next run can be corrected.
        print('no process of the app was found under simulator ' + udid, file=sys.stderr)
        for r in processes():
            if any(word in r['command'] for word in ('launchd_sim', 'QNTX', 'WebKit', udid)):
                print('  %6d %6d %s' % (r['pid'], r['ppid'], r['command'][:160]), file=sys.stderr)
        sys.exit(2)

    taken = []
    before = first
    for n in range(windows):
        time.sleep(window)
        after = snapshot(udid)
        wall = after['at'] - before['at']
        row = {'window': n + 1, 'wall_seconds': round(wall, 2), 'kinds': {}}
        for kind, _ in KINDS:
            then, now = before['kinds'][kind], after['kinds'][kind]
            row['kinds'][kind] = {
                'cpu_percent': round((now['cpu'] - then['cpu']) * 100.0 / wall, 2),
                'rss_mb': round(now['rss_kb'] / 1024.0, 1),
                'replaced': then['pids'] != now['pids'],
            }
        row['total_cpu_percent'] = round(sum(k['cpu_percent'] for k in row['kinds'].values()), 2)
        taken.append(row)
        before = after

    wall_all = sum(r['wall_seconds'] for r in taken)
    average = {
        kind: round(sum(r['kinds'][kind]['cpu_percent'] * r['wall_seconds'] for r in taken) / wall_all, 2)
        for kind, _ in KINDS
    }
    total = round(sum(average.values()), 2)
    memory = {kind: max(r['kinds'][kind]['rss_mb'] for r in taken) for kind, _ in KINDS}
    replaced = [(r['window'], kind) for r in taken for kind, k in r['kinds'].items() if k['replaced']]

    result = {
        'name': name,
        'windows': taken,
        'average_cpu_percent': average,
        'total_cpu_percent': total,
        'max_rss_mb': memory,
        'threshold_percent': THRESHOLD,
        'replaced': replaced,
    }
    os.makedirs('idle-samples', exist_ok=True)
    with open('idle-samples/%s.json' % name, 'w') as out:
        json.dump(result, out, indent=1)
    diagnose(name, before['kinds'])

    print('%s: %d windows of %gs, CPU in percent of one core, memory resident in MB' % (name, windows, window))
    print('%-11s %s %8s %10s' % ('', ' '.join('%7s' % ('w%d' % (i + 1)) for i in range(windows)), 'average', 'max MB'))
    for kind, _ in KINDS:
        print('%-11s %s %8.2f %10.1f' % (
            kind, ' '.join('%7.2f' % r['kinds'][kind]['cpu_percent'] for r in taken), average[kind], memory[kind]))
    print('%-11s %s %8.2f' % ('everything', ' '.join('%7.2f' % r['total_cpu_percent'] for r in taken), total))

    if replaced:
        print('a process was replaced while it was read, so the CPU of these is not one process: %s' % replaced, file=sys.stderr)
        sys.exit(2)
    if total >= THRESHOLD:
        print('%s: %.2f%% average CPU is not under the %.0f%% WebKit asks of an idle page' % (name, total, THRESHOLD))
        sys.exit(1)
    print('%s: %.2f%% average CPU, under the %.0f%% WebKit asks of an idle page' % (name, total, THRESHOLD))


if __name__ == "__main__":
    main()

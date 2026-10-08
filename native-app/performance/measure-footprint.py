#!/usr/bin/env python3
"""Observe only one existing macOS process, including its physical footprint.

No process launch, app interaction, settings change or child-process accounting.
libproc's V0 structure is defined in the macOS SDK's sys/resource.h.
"""
import argparse
import csv
import ctypes
import hashlib
import json
import statistics
import subprocess
import time
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo


class UsageV0(ctypes.Structure):
    _fields_ = [('uuid', ctypes.c_uint8 * 16)] + [
        (name, ctypes.c_uint64) for name in (
            'user_time', 'system_time', 'pkg_idle_wkups', 'interrupt_wkups',
            'pageins', 'wired_size', 'resident_size', 'phys_footprint',
            'proc_start_abstime', 'proc_exit_abstime')]


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('pid', type=int)
parser.add_argument('--seconds', type=int, default=300)
parser.add_argument('--interval', type=int, default=15)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--render-health', type=Path,
                    help='Optional passive renderer snapshot to preserve alongside process samples')
args = parser.parse_args()
if args.pid <= 0 or args.seconds < 0 or args.interval <= 0:
    parser.error('PID/interval must be positive and duration nonnegative')

libproc = ctypes.CDLL('/usr/lib/libproc.dylib', use_errno=True)
libproc.proc_pid_rusage.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_void_p]
libproc.proc_pid_rusage.restype = ctypes.c_int
zone = ZoneInfo('Europe/Rome')
prefs = Path.home() / 'Library/Application Support/dev.aniello.macsystemwallpaper/native-settings.json'


def observe():
    usage = UsageV0()
    if libproc.proc_pid_rusage(args.pid, 0, ctypes.byref(usage)) != 0:
        raise OSError(ctypes.get_errno(), 'Cannot observe target process')
    # ps cumulative CPU time is used to match the earlier interval CPU method.
    output = subprocess.check_output(
        ['ps', '-p', str(args.pid), '-o', 'time='], text=True,
        stderr=subprocess.DEVNULL).strip()
    if not output:
        raise RuntimeError('Target process stopped')
    parts = list(map(float, output.split(':')))
    cpu_seconds = sum(value * 60 ** index for index, value in enumerate(reversed(parts)))
    # Compare values, ignoring JSON key order and whitespace on future runs.
    configuration = json.loads(prefs.read_text()) if prefs.exists() else None
    digest = (hashlib.sha256(json.dumps(configuration, sort_keys=True).encode()).hexdigest()
              if configuration is not None else None)
    return {'timestamp': datetime.now(zone).isoformat(timespec='seconds'),
            'monotonic': time.monotonic(), 'process_start': usage.proc_start_abstime,
            'rss_bytes': usage.resident_size, 'footprint_bytes': usage.phys_footprint,
            'cpu_seconds': cpu_seconds, 'configuration_sha256': digest}


args.output.mkdir(parents=True, exist_ok=True)
rows = []
error = None
state = 'running'
last_render_timestamp = None


def preserve_render_snapshot():
    global last_render_timestamp
    if args.render_health is None or not args.render_health.exists():
        return
    record = json.loads(args.render_health.read_text())
    if record.get('pid') != args.pid or record.get('timestamp') == last_render_timestamp:
        return
    with (args.output / 'render-snapshots.jsonl').open('a') as stream:
        stream.write(json.dumps(record, sort_keys=True) + '\n')
    last_render_timestamp = record.get('timestamp')


def summarize():
    summary = {'state': state, 'pid': args.pid, 'samples': len(rows),
               'scope': 'Only target process RSS, physical footprint and interval CPU; no GPU/energy measurement',
               'error': error}
    if rows:
        summary.update(started=rows[0]['timestamp'], ended=rows[-1]['timestamp'],
                       elapsed_seconds=rows[-1]['elapsed_seconds'],
                       process_start_abstime=rows[0]['process_start'],
                       configuration_changes=sum(a['configuration_sha256'] != b['configuration_sha256']
                                                 for a, b in zip(rows, rows[1:])))
        for key in ('rss_bytes', 'footprint_bytes'):
            values = [row[key] for row in rows]
            summary[key] = {'start': values[0], 'end': values[-1], 'min': min(values),
                            'max': max(values), 'median': statistics.median(values),
                            'delta': values[-1] - values[0]}
        cpu = [row['interval_cpu_percent'] for row in rows[1:]]
        if cpu:
            summary['interval_cpu_percent'] = {'median': statistics.median(cpu), 'max': max(cpu),
                                              'mean': statistics.mean(cpu)}
    path = args.output / 'status.json'
    temporary = path.with_suffix('.json.new')
    temporary.write_text(json.dumps(summary, indent=2) + '\n')
    temporary.replace(path)
    return summary


fields = ['timestamp', 'elapsed_seconds', 'rss_bytes', 'footprint_bytes',
          'interval_cpu_percent', 'process_start', 'configuration_sha256']
with (args.output / 'samples.csv').open('w', newline='') as stream:
    writer = csv.DictWriter(stream, fieldnames=fields, extrasaction='ignore')
    writer.writeheader()
    try:
        first = observe()
        previous = first
        while True:
            current = first if not rows else observe()
            if current['process_start'] != first['process_start']:
                raise RuntimeError('Target process restarted or PID was reused')
            elapsed = current['monotonic'] - first['monotonic']
            current['elapsed_seconds'] = round(elapsed, 3)
            current['interval_cpu_percent'] = (max(0, (current['cpu_seconds'] - previous['cpu_seconds']) /
                                                      (current['monotonic'] - previous['monotonic']) * 100)
                                               if rows else None)
            rows.append(current)
            writer.writerow(current)
            stream.flush()
            preserve_render_snapshot()
            summarize()
            if elapsed >= args.seconds:
                state = 'completed'
                break
            previous = current
            deadline = first['monotonic'] + min(args.seconds, elapsed + args.interval)
            time.sleep(max(0, deadline - time.monotonic()))
    except (Exception, KeyboardInterrupt) as exc:
        state = 'interrupted'
        error = str(exc) or type(exc).__name__
print(json.dumps(summarize(), indent=2))
if state != 'completed':
    raise SystemExit(1)

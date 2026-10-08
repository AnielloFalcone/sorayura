#!/usr/bin/env python3
"""Bounded, read-only stability test of one macOS process; no app/settings changes."""
import argparse
import csv
import hashlib
import json
import statistics
import subprocess
import time
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

parser = argparse.ArgumentParser()
parser.add_argument('pid', type=int)
parser.add_argument('--seconds', type=int, default=3600)
parser.add_argument('--interval', type=int, default=15)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
if args.seconds < 1 or args.interval < 1:
    parser.error('duration and interval must be positive')
args.output.mkdir(parents=True, exist_ok=True)
zone = ZoneInfo('Europe/Rome')
prefs = Path.home() / 'Library/Application Support/dev.aniello.macsystemwallpaper/native-settings.json'

def stamp():
    return datetime.now(zone).isoformat(timespec='seconds')

def ps(field):
    return subprocess.check_output(['ps', '-p', str(args.pid), '-o', field + '='], text=True, stderr=subprocess.DEVNULL).strip()

def observe():
    fields = subprocess.check_output(['ps', '-p', str(args.pid), '-o', 'rss=', '-o', 'time='], text=True, stderr=subprocess.DEVNULL).split()
    if len(fields) != 2:
        raise RuntimeError('Monitored process stopped')
    values = list(map(float, fields[1].split(':')))
    cpu = sum(value * 60 ** index for index, value in enumerate(reversed(values)))
    return time.monotonic(), int(fields[0]), cpu

def config_digest():
    try:
        return hashlib.sha256(prefs.read_bytes()).hexdigest()
    except OSError:
        return None

def save_status(value):
    temporary = args.output / 'status.json.new'
    temporary.write_text(json.dumps(value, indent=2) + '\n')
    temporary.replace(args.output / 'status.json')

started = stamp()
identity = ps('lstart')
if not identity:
    raise RuntimeError('Process not found')
first = observe()
previous = first
initial_config = config_digest()
rows = [(0.0, first[1], None)]
config_changes = 0
last_config = initial_config
high_memory_since = None
high_cpu_since = None
alerts = []
status = {'state': 'running', 'pid': args.pid, 'process_started': identity,
          'started': started, 'duration_seconds': args.seconds,
          'interval_seconds': args.interval,
          'configuration_sha256': initial_config,
          'thresholds': {'memory_growth_KiB': 65536, 'rss_ceiling_KiB': 524288, 'cpu_percent_of_one_core': 80, 'persistence_seconds': 300},
          'scope': 'Process CPU/RSS during existing configuration; no sleep/wake, hotplug or GPU/energy measurement'}

def update(state, error=None):
    rss = [row[1] for row in rows]
    cpu = [row[2] for row in rows if row[2] is not None]
    summary = dict(status, state=state, updated=stamp(), samples=len(rows),
                   elapsed_seconds=round(rows[-1][0], 1),
                   rss_start_KiB=rss[0], rss_end_KiB=rss[-1],
                   rss_min_KiB=min(rss), rss_max_KiB=max(rss),
                   rss_delta_KiB=rss[-1] - rss[0],
                   interval_cpu_median_percent=round(statistics.median(cpu), 2) if cpu else None,
                   interval_cpu_max_percent=round(max(cpu), 2) if cpu else None,
                   configuration_changes=config_changes, alerts=alerts)
    if error:
        summary['error'] = error
    if state == 'completed':
        summary['outcome'] = 'review_required' if alerts or config_changes else 'no_threshold_alerts_in_measured_window'
        summary['limitations'] = 'RSS stability does not prove absence of leaks or UI responsiveness; CPU is percent of one core and excludes WindowServer/other processes.'
    save_status(summary)

with (args.output / 'samples.csv').open('w', newline='') as stream:
    writer = csv.writer(stream)
    writer.writerow(['timestamp_Europe_Rome', 'elapsed_seconds', 'rss_KiB', 'interval_cpu_percent'])
    writer.writerow([started, 0, first[1], ''])
    stream.flush()
    update('running')
    try:
        while rows[-1][0] < args.seconds:
            target = min(args.seconds, rows[-1][0] + args.interval)
            time.sleep(max(0, first[0] + target - time.monotonic()))
            if ps('lstart') != identity:
                raise RuntimeError('Process stopped or PID was reused; this test does not follow a restarted app')
            current = observe()
            elapsed = current[0] - first[0]
            cpu = max(0, (current[2] - previous[2]) / (current[0] - previous[0]) * 100)
            rows.append((elapsed, current[1], cpu))
            writer.writerow([stamp(), round(elapsed, 1), current[1], round(cpu, 2)])
            stream.flush()
            digest = config_digest()
            if digest != last_config:
                config_changes += 1
                last_config = digest
            memory_high = current[1] > first[1] + 65_536 or current[1] > 524_288
            high_memory_since = (high_memory_since or elapsed) if memory_high else None
            high_cpu_since = (high_cpu_since or elapsed) if cpu > 80 else None
            for name, since in [('persistent_high_memory', high_memory_since), ('persistent_high_cpu', high_cpu_since)]:
                if since is not None and elapsed - since >= 300 and name not in alerts:
                    alerts.append(name)
            previous = current
            update('running')
        update('completed')
    except Exception as error:
        update('failed', str(error))
        raise
print(json.dumps(json.loads((args.output / 'status.json').read_text()), indent=2))

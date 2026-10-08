#!/usr/bin/env python3
"""Read-only CPU/RSS sampling. Usage: python3 measure-process.py PID [seconds]."""
import subprocess
import sys
import time

pid = str(int(sys.argv[1]))
seconds = max(1, min(60, int(sys.argv[2]) if len(sys.argv) > 2 else 30))

def measure():
    fields = subprocess.check_output(['ps', '-p', pid, '-o', 'rss=', '-o', 'time='], text=True).split()
    if len(fields) != 2:
        raise RuntimeError('Process is no longer running')
    parts = list(map(float, fields[1].split(':')))
    cpu_seconds = sum(value * 60 ** index for index, value in enumerate(reversed(parts)))
    return time.monotonic(), int(fields[0]), cpu_seconds

start = measure()
print('elapsed_seconds,rss_KiB,interval_cpu_percent', flush=True)
print(f'0,{start[1]},', flush=True)
previous = start
for point in sorted(set([seconds // 3, seconds * 2 // 3, seconds])):
    if point == 0:
        continue
    time.sleep(max(0, start[0] + point - time.monotonic()))
    current = measure()
    cpu = (current[2] - previous[2]) / (current[0] - previous[0]) * 100
    print(f'{current[0] - start[0]:.1f},{current[1]},{cpu:.1f}', flush=True)
    previous = current

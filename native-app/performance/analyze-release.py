#!/usr/bin/env python3
"""Summarize a completed installed-candidate trial without controlling the app."""
import argparse
import csv
import json
import statistics
from datetime import datetime
from pathlib import Path


def stats(values):
    if not values:
        return None
    return dict(samples=len(values), min=min(values), max=max(values),
                median=statistics.median(values), mean=statistics.mean(values),
                first=values[0], last=values[-1], delta=values[-1] - values[0])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    args = parser.parse_args()
    root = args.directory
    read = lambda name: json.loads((root / name).read_text())
    status = read('status.json')
    if status['state'] != 'completed':
        parser.error('The trial must be completed before final analysis')
    with (root / 'samples.csv').open() as stream:
        rows = list(csv.DictReader(stream))
    for row in rows:
        for key in ['elapsed_seconds', 'rss_bytes', 'footprint_bytes']:
            row[key] = float(row[key])
    snapshots = [json.loads(line) for line in (root / 'render-snapshots.jsonl').read_text().splitlines()]
    segments = {}
    for name, start, end in [('whole_trial_includes_startup_and_actions', 0, 601),
                              ('final_three_minutes', 420, 601)]:
        memory = [r for r in rows if start <= r['elapsed_seconds'] <= end]
        intervals = [(a, b) for a, b in zip(rows, rows[1:])
                     if a['elapsed_seconds'] >= start and b['elapsed_seconds'] <= end]
        cpu = [float(b['interval_cpu_percent']) for a, b in intervals]
        health = [h for h in snapshots if start <= h['elapsed_seconds'] <= end]
        fps = {}
        reset_intervals = []
        for a, b in zip(health, health[1:]):
            seconds = b['elapsed_seconds'] - a['elapsed_seconds']
            old = {v['display']: v for v in a['views']}
            old_screens = {s['id'] for s in a['app_state']['screens']}
            new_screens = {s['id'] for s in b['app_state']['screens']}
            for v in b['views']:
                previous = old.get(v['display'])
                if (previous is None or old_screens != new_screens or
                        v['submitted_frames'] < previous['submitted_frames'] or
                        (v['drawable_width'], v['drawable_height']) !=
                        (previous['drawable_width'], previous['drawable_height'])):
                    reset_intervals.append({'display': v['display'], 'elapsed': b['elapsed_seconds']})
                    continue
                fps.setdefault(v['display'], []).append((v['submitted_frames'] - previous['submitted_frames']) / seconds)
        gpu_start, gpu_end = health[0]['gpu'], health[-1]['gpu']
        commands = gpu_end['timed_commands'] - gpu_start['timed_commands']
        gpu_ms = gpu_end['total_gpu_ms'] - gpu_start['total_gpu_ms']
        segments[name] = {
            'requested_window_seconds': [start, min(end, status['elapsed_seconds'])],
            'observed_memory_window_seconds': [memory[0]['elapsed_seconds'], memory[-1]['elapsed_seconds']],
            'cpu_one_core_percent': stats(cpu),
            'cpu_time_weighted_mean_percent': sum(float(b['interval_cpu_percent']) * (b['elapsed_seconds'] - a['elapsed_seconds']) for a, b in intervals) / sum(b['elapsed_seconds'] - a['elapsed_seconds'] for a, b in intervals),
            'rss_mib': stats([r['rss_bytes'] / 1048576 for r in memory]),
            'footprint_mib': stats([r['footprint_bytes'] / 1048576 for r in memory]),
            'render_window_seconds': [health[0]['elapsed_seconds'], health[-1]['elapsed_seconds']],
            'submitted_fps_by_display': {k: stats(v) for k, v in fps.items()},
            'skipped_view_reset_or_topology_intervals': reset_intervals,
            'gpu': {'timed_commands_in_render_window': commands,
                    'mean_command_gpu_ms_in_render_window': gpu_ms / commands if commands else None,
                    'command_errors_in_render_window': gpu_end['command_errors'] - gpu_start['command_errors'],
                    'missing_timestamps_in_render_window': gpu_end['missing_timestamps'] - gpu_start['missing_timestamps'],
                    'last_recent_p95_gpu_ms': gpu_end['recent_p95_gpu_ms'],
                    'last_recent_p95_sample_count': gpu_end['recent_sample_count']},
            'rendering_attached_and_unpaused_in_all_snapshots': all(
                v['metal_available'] and v['metal_window_attached'] and v['delegate_present'] and not v['paused']
                for h in health for v in h['views']),
        }
    gaps = [b['elapsed_seconds'] - a['elapsed_seconds'] for a, b in zip(rows, rows[1:])]
    wall_gaps = [(datetime.fromisoformat(b['timestamp']) - datetime.fromisoformat(a['timestamp'])).total_seconds()
                 for a, b in zip(rows, rows[1:])]
    final = snapshots[-1]
    output = {
        'state': 'completed', 'metadata': read('metadata.json'),
        'duration_seconds': status['elapsed_seconds'], 'samples': len(rows),
        'cpu_intervals': len(rows) - 1, 'max_monotonic_sample_gap_seconds': max(gaps),
        'max_wall_clock_sample_gap_seconds': max(wall_gaps),
        'intervals_above_ten_seconds': sum(gap > 10 for gap in gaps),
        'process_identity_constant': len({r['process_start'] for r in rows}) == 1,
        'configuration_changes': status['configuration_changes'],
        'configuration_hashes': sorted({r['configuration_sha256'] for r in rows}),
        'segments': segments,
        'screen_counts_observed': sorted({len(h['app_state']['screens']) for h in snapshots}),
        'final_app_state': final['app_state'], 'gpu_cumulative_last_snapshot': final['gpu'],
        'lifecycle_events': final['lifecycle_events'], 'user_verification': read('user-verification.json'),
        'power_profiler': {**read('profiler.json'), 'result': 'Unsupported on macOS; no energy measurement'},
        'limits': [
            'CPU is percent of one core. RSS and footprint are separate measures and are not summed.',
            'Full-trial figures include startup, user actions and a failed profiler attempt. Final window is descriptive, not a matched comparison.',
            'Final render snapshot is about ten seconds before monitor completion; per-view counters reset on display reconfiguration.',
            'GPU elapsed command-buffer time is not utilization, energy, WindowServer cost, queue latency or visible FPS.',
            'User confirmed physical sleep/wake visually, but no corresponding sleep/wake notifications were recorded; renderer suspension during sleep is not verified.',
            'Ten minutes cannot establish absence of memory leaks, long-term stability or compatibility with other Macs/macOS versions.',
            'Installation from a local ad hoc signed DMG does not verify Gatekeeper on an Internet download.',
        ],
    }
    (root / 'analysis.json').write_text(json.dumps(output, indent=2) + '\n')
    print(json.dumps({k: output[k] for k in ['state', 'duration_seconds', 'samples', 'max_monotonic_sample_gap_seconds', 'max_wall_clock_sample_gap_seconds', 'process_identity_constant', 'configuration_changes']}, indent=2))
    print(json.dumps(segments['final_three_minutes'], indent=2))


if __name__ == '__main__':
    main()

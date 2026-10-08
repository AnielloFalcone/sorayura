#!/usr/bin/env python3
"""Analyze an opt-in visual trial of the wallpaper process, not whole-PC costs."""
import argparse,csv,json,statistics
from datetime import datetime
from pathlib import Path
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('directory',type=Path)
args=parser.parse_args(); directory=args.directory
profile=json.loads((directory/'component-profile.json').read_text())
status=json.loads((directory/'status.json').read_text())
rows=list(csv.DictReader((directory/'samples.csv').open()))
health=[json.loads(line) for line in (directory/'render-snapshots.jsonl').read_text().splitlines()]
expected_displays={view['display'] for view in health[0]['views']} if health else set()
def stamp(value): return datetime.fromisoformat(value.replace('Z','+00:00')).timestamp()
def stats(values):
    if not values: return None
    return {'median':statistics.median(values),'mean':statistics.mean(values),'min':min(values),'max':max(values),'start':values[0],'end':values[-1],'samples':len(values)}
phases=[]
for phase in profile['phases']:
    if not phase.get('ended'): continue
    start,end=stamp(phase['started']),stamp(phase['ended'])
    # Exclude first 30 seconds and last five of EVERY phase, and intervals crossing them.
    eligible=[r for r in rows if start+30 <= stamp(r['timestamp']) <= end-5]
    cpu=[float(r['interval_cpu_percent']) for prev,r in zip(rows,rows[1:])
         if start+30<=stamp(prev['timestamp']) and stamp(r['timestamp'])<=end-5 and r['interval_cpu_percent']]
    snapshots=[h for h in health if start+30<=stamp(h['timestamp'])<=end-5]
    per_display={}
    for previous,current in zip(snapshots,snapshots[1:]):
        delta=stamp(current['timestamp'])-stamp(previous['timestamp'])
        older={v['display']:v for v in previous['views']}
        for view in current['views']:
            old=older.get(view['display'])
            if old is None or delta<=0: continue
            result=per_display.setdefault(view['display'],{'fps':[],'requested_pause':[],'paused':[],'occluded':[],'preferred_fps':[]})
            result['fps'].append((view['submitted_frames']-old['submitted_frames'])/delta)
            result['requested_pause'].append(view['requested_pause']); result['paused'].append(view['paused'])
            result['occluded'].append(view['window_occluded']); result['preferred_fps'].append(view['preferred_fps'])
    expected_pause=phase['variant'] in ('animationPaused','backgroundOnly')
    for result in per_display.values():
        result['fps']=stats(result['fps'])
        for key in ('requested_pause','paused','occluded','preferred_fps'): result[key]=sorted(set(result[key]))
    valid_render=bool(expected_displays) and set(per_display)==expected_displays and all(
        {view['display'] for view in snapshot['views']}==expected_displays
        and all(view['metal_available'] and view['delegate_present'] and view['window_attached']
                and view['metal_window_attached'] for view in snapshot['views'])
        for snapshot in snapshots) and all(
        result['requested_pause']==[expected_pause] and result['paused']==[expected_pause]
        and (result['fps']['max']==0 if expected_pause else result['fps']['min']>0)
        for result in per_display.values())
    phases.append({'name':phase['name'],'variant':phase['variant'],'started':phase['started'],'ended':phase['ended'],
        'phase_seconds':end-start,'stable_window_seconds':end-start-35,
        'cpu_one_core_percent':stats(cpu),
        'rss_mib':stats([int(r['rss_bytes'])/1048576 for r in eligible]),
        'footprint_mib':stats([int(r['footprint_bytes'])/1048576 for r in eligible]),
        'renderer':per_display,'renderer_expected_state_verified':valid_render})
by_name={phase['name']:phase for phase in phases}
comparisons={}
if all(x in by_name for x in ('full-start','full-end')):
    first=by_name['full-start']['cpu_one_core_percent']['median']; last=by_name['full-end']['cpu_one_core_percent']['median']
    baseline=(first+last)/2
    comparisons['full_start_end_cpu_drift_percentage_points']=last-first
    comparisons['reference_cpu_percent_mean_of_two_phase_medians']=baseline
    comparisons['phase_cpu_differences']={
        p['name']:{'difference_vs_reference_percentage_points':p['cpu_one_core_percent']['median']-baseline,
                   'reduction_vs_reference_percent':(baseline-p['cpu_one_core_percent']['median'])/baseline*100,
                   'difference_vs_first_percentage_points':p['cpu_one_core_percent']['median']-first,
                   'difference_vs_last_percentage_points':p['cpu_one_core_percent']['median']-last}
        for p in phases if p['name'] not in ('full-start','full-end') and p['cpu_one_core_percent']}
intervals=[float(b['elapsed_seconds'])-float(a['elapsed_seconds']) for a,b in zip(rows,rows[1:])]
result={'scope':'Only target process; short sequential phases, not causal whole-system/GPU/energy accounting',
        'pid':profile['pid'],'profile_state':profile['state'],'monitor_state':status['state'],
        'elapsed_seconds':status['elapsed_seconds'],'samples':len(rows),'configuration_changes':status['configuration_changes'],
        'max_sample_interval_seconds':max(intervals) if intervals else None,
        'intervals_above_10_seconds':sum(value>10 for value in intervals),
        'process_identity_constant':len({r['process_start'] for r in rows})==1,
        'phase_exclusions':{'initial_seconds':30,'final_seconds':5,'cpu_intervals_must_fit_entirely':True},
        'phases':phases,'comparisons':comparisons,
        'renderer_displays':sorted(expected_displays),
        'limits':['One fixed sequential pass, 90 seconds each; cache/order/carryover and baseline drift prevent exact independent cost attribution.',
                  'First phase follows process restart; 30-second exclusion does not prove all caches have stabilized.',
                  'Animation pause retains Metal resources, readout layers and sampled metrics; widgets hidden retains integration readers and transparent hit windows.',
                  'Glass CPU difference excludes WindowServer and GPU compositor costs. Memory per phase reflects previous phases and caches; do not add independent component memory estimates.',
                  'Renderer submissions verify drawing activity, not pixel quality, perceived fluidity or GPU/energy cost.',
                  'Some wallpaper windows may report occlusion despite nonzero frame submission; assess counter/state consistency per display.',
                  'This short test does not assess leak absence, sleep/wake, hotplug or distribution readiness.']}
(directory/'analysis.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({'profile_state':result['profile_state'],'phases':[{k:p[k] for k in ('name','cpu_one_core_percent','footprint_mib','renderer_expected_state_verified')} for p in phases],'comparisons':comparisons},indent=2))

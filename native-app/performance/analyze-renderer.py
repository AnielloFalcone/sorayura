#!/usr/bin/env python3
"""Compare independent/shared drawing with renderer activity and FPS gates."""
import argparse,csv,json,statistics
from pathlib import Path
parser=argparse.ArgumentParser(description=__doc__); parser.add_argument('directory',type=Path)
args=parser.parse_args(); root=args.directory

def stats(values):
    if not values: return None
    return {'median':statistics.median(values),'mean':statistics.mean(values),'min':min(values),'max':max(values),'start':values[0],'end':values[-1],'samples':len(values)}
results={}
for mode in ['independent','shared']:
    path=root/mode
    if not (path/'status.json').exists(): continue
    metadata=json.loads((path/'metadata.json').read_text()); status=json.loads((path/'status.json').read_text())
    rows=list(csv.DictReader((path/'samples.csv').open()))
    end=min(175,float(rows[-1]['elapsed_seconds']))
    stable=[r for r in rows if 60<=float(r['elapsed_seconds'])<=end]
    cpu=[float(r['interval_cpu_percent']) for a,r in zip(rows,rows[1:]) if float(a['elapsed_seconds'])>=60 and float(r['elapsed_seconds'])<=end]
    snapshots=[json.loads(line) for line in (path/'render-snapshots.jsonl').read_text().splitlines()]
    stable_health=[h for h in snapshots if 60<=h['elapsed_seconds']<=175]
    expected={v['display'] for v in snapshots[0]['views']} if snapshots else set()
    per_display={}; command_rates=[]; max_gap=0
    for a,b in zip(stable_health,stable_health[1:]):
        delta=b['elapsed_seconds']-a['elapsed_seconds']; max_gap=max(max_gap,delta)
        if delta<=0: continue
        old={v['display']:v for v in a['views']}
        command_rates.append((b['shared_command_submissions']-a['shared_command_submissions'])/delta)
        for v in b['views']:
            if v['display'] not in old: continue
            result=per_display.setdefault(v['display'],{'fps':[],'preferred_fps':set(),'occluded':set(),'paused':set(),'clock_mode':set(),'drawable':set()})
            result['fps'].append((v['submitted_frames']-old[v['display']]['submitted_frames'])/delta)
            result['preferred_fps'].add(v['preferred_fps']); result['occluded'].add(v['window_occluded']); result['paused'].add(v['paused']); result['clock_mode'].add(v['frame_clock']); result['drawable'].add((v['drawable_width'],v['drawable_height']))
    valid=bool(expected) and set(per_display)==expected and all({v['display'] for v in h['views']}==expected and all(v['metal_available'] and v['delegate_present'] and v['window_attached'] and not v['paused'] for v in h['views']) for h in stable_health)
    for v in per_display.values():
        v['fps']=stats(v['fps']); valid=valid and v['fps']['min']>0
        for key in ['preferred_fps','occluded','paused','clock_mode','drawable']: v[key]=sorted(v[key])
    gaps=[float(b['elapsed_seconds'])-float(a['elapsed_seconds']) for a,b in zip(rows,rows[1:])]
    results[mode]={'metadata':metadata,'state':status['state'],'samples':len(rows),'cpu_one_core_percent':stats(cpu),'footprint_mib':stats([int(r['footprint_bytes'])/1048576 for r in stable]),'rss_mib':stats([int(r['rss_bytes'])/1048576 for r in stable]),'renderer':per_display,'renderer_active_on_all_displays':bool(valid),'shared_submissions_per_second':stats(command_rates),'max_health_gap_seconds':max_gap,'max_sample_interval_seconds':max(gaps) if gaps else None,'configuration_changes':status['configuration_changes'],'process_identity_constant':len({r['process_start'] for r in rows})==1}
comparison={}; valid=False
if set(results)=={'independent','shared'}:
    a,b=results['independent'],results['shared']; ma,mb=a['metadata'],b['metadata']
    settings=ma['configuration_sha256']==mb['configuration_sha256']==ma.get('final_configuration_sha256')==mb.get('final_configuration_sha256')
    rates={k:b['renderer'][k]['fps']['mean']/a['renderer'][k]['fps']['mean'] for k in a['renderer'] if k in b['renderer']}
    same_state=set(a['renderer'])==set(b['renderer']) and all(a['renderer'][k]['preferred_fps']==b['renderer'][k]['preferred_fps'] and a['renderer'][k]['drawable']==b['renderer'][k]['drawable'] and a['renderer'][k]['occluded']==b['renderer'][k]['occluded'] for k in rates)
    valid=(all(r['state']=='completed' and r['renderer_active_on_all_displays'] and r['configuration_changes']==0 and r['process_identity_constant'] for r in [a,b]) and settings and ma['binary_sha256']==mb['binary_sha256'] and same_state and len(rates)==len(a['renderer']) and all(.95<=rate<=1.05 for rate in rates.values()))
    comparison={'valid_under_short_trial_gates':bool(valid),'configuration_identical':settings,'same_presentation_and_preferred_rates':same_state,'shared_to_independent_fps_ratio':rates,'observed_cpu_median_difference_percentage_points':b['cpu_one_core_percent']['median']-a['cpu_one_core_percent']['median'],'observed_cpu_relative_reduction_percent':(a['cpu_one_core_percent']['median']-b['cpu_one_core_percent']['median'])/a['cpu_one_core_percent']['median']*100}
output={'results':results,'comparison':comparison,'stable_window':'60–175 s; CPU intervals wholly within window, first minute and final five seconds excluded','limits':['Fixed sequential order with process restart; no randomized/repeated or matched long-term baseline.','Counters establish draw submission, not visual quality, GPU/energy or WindowServer costs.','Memory includes startup/caches and can depend on previous activity; do not infer leak absence.','No hotplug, physical sleep/wake or screen-lock certification.']}
(root/'analysis.json').write_text(json.dumps(output,indent=2)+'\n')
print(json.dumps({'modes':{k:{'state':v['state'],'cpu':v['cpu_one_core_percent'],'footprint':v['footprint_mib'],'renderer':v['renderer'],'shared_submissions':v['shared_submissions_per_second']} for k,v in results.items()},'comparison':comparison},indent=2))

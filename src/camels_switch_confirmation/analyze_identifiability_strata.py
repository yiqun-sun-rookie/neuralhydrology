import sys, numpy as np, pandas as pd
sys.path.insert(0, r'G:\wt\camels-rising\src')
from pathlib import Path
from camels_switch_confirmation.run_online_noise_pilot import ROOT_03C, ROOT_03D, RESULTS
from camels_switch_confirmation.run_online_noise_design90 import (
    OUTPUT_ROOT, design90_identities, PILOT_BASINS)

pc = pd.read_csv(RESULTS/'g1_precheck_v01'/'g1_precheck.csv', dtype={'basin_id':str})
pc['basin_id'] = pc.basin_id.str.zfill(8)
ident = dict(zip(pc.basin_id, pc.predicted_identifiable.astype(bool)))
rmin  = dict(zip(pc.basin_id, pc.r_min.astype(float)))

# degeneracy from frozen candidate vectors (no outcome peeking)
deg = {}
for b,s in design90_identities():
    with np.load(ROOT_03C/'arms'/'C'/'probs'/f'{b}_s{s}.npz') as a:
        names=[str(x) for x in a['candidate_parameter_names']]; j=names.index('parFC')
        v=a['candidate_parameter_vectors']
        deg[(b,s)] = bool(v[2,j]/v[0,j] < 1.05)

rows=[]
for src,label in ((OUTPUT_ROOT/'verification'/'task_metrics.csv','A2f99'),
                  (ROOT_03D/'verification'/'task_metrics.csv','03D_oracle')):
    t=pd.read_csv(src, dtype={'basin_id':str})
    if 'estimator' in t.columns: t=t[t.estimator=='A2f99']
    t['config']=label; rows.append(t)
df=pd.concat(rows, ignore_index=True)
df['identifiable']=df.basin_id.map(ident)
df['degenerate']=[deg[(b,s)] for b,s in zip(df.basin_id, df.seed)]
df['generalization']=~df.basin_id.isin(PILOT_BASINS)

ev30=[f'event{i}_w30_pass' for i in range(6)]; ev90=[f'event{i}_w90_pass' for i in range(6)]
def rate(g, cols):
    v=g[cols].values.astype(bool); per=v.mean(axis=0)
    return per.min(), per.mean(), len(g)

print('=== 90-basin design composition (pre-registered G1 labels) ===')
comp=df[(df.config=='A2f99')&(df.arm_id=='C')]
print(' identities:', len(comp), '| predicted_identifiable=False:', int((~comp.identifiable).sum()),
      '| candidate-degenerate:', int(comp.degenerate.sum()))
print(' overlap deg & not-identifiable:', int((comp.degenerate & ~comp.identifiable).sum()))
print()
for subset,mask_fn in (('generalization', lambda d: d.generalization), ('full', lambda d: d.index==d.index)):
    print(f'=== subset: {subset} ===')
    print(f'{"config":11s} {"arm":3s} {"stratum":22s} {"n":>4s} {"w90_min":>8s} {"w90_mean":>9s} {"w30_min":>8s} {"med_NLL":>9s}')
    for cfg in ('03D_oracle','A2f99'):
        for arm in ('C','P'):
            base=df[(df.config==cfg)&(df.arm_id==arm)&mask_fn(df)]
            for name,g in (('ALL',base),
                           ('identifiable=True', base[base.identifiable]),
                           ('identifiable=False',base[~base.identifiable]),
                           ('non-degenerate',    base[~base.degenerate]),
                           ('degenerate',        base[base.degenerate])):
                if not len(g): continue
                m90,a90,n=rate(g,ev90); m30,_,_=rate(g,ev30)
                print(f'{cfg:11s} {arm:3s} {name:22s} {n:4d} {m90:8.3f} {a90:9.3f} {m30:8.3f} '
                      f'{g.mean_true_negative_log_probability.median():9.4f}')
    print()

# --- appended: durable artifact writer (post-hoc stratified re-analysis) ---
# The stratifying variables are NOT outcome-derived: predicted_identifiable and
# r_min come from the frozen G1 precheck (computed before any filter ran), and
# the degeneracy flag comes from the frozen candidate vectors.  This is a
# re-analysis of frozen outputs; no gate was changed and no filter was re-run.
def _write_artifact():
    import json
    out = RESULTS / 'online_noise_a2f99_design90_01_20260817_local' / 'verification'
    recs = []
    for subset, mask in (('generalization', df.generalization), ('full', df.index == df.index)):
        for cfg in ('03D_oracle', 'A2f99'):
            for arm in ('C', 'P'):
                base = df[(df.config == cfg) & (df.arm_id == arm) & mask]
                for name, g in (('ALL', base),
                                ('identifiable_true', base[base.identifiable]),
                                ('identifiable_false', base[~base.identifiable]),
                                ('identifiable_true_nondegenerate',
                                 base[base.identifiable & ~base.degenerate]),
                                ('identifiable_false_nondegenerate',
                                 base[~base.identifiable & ~base.degenerate]),
                                ('degenerate', base[base.degenerate])):
                    if not len(g):
                        continue
                    p90 = g[ev90].values.astype(bool).mean(axis=0)
                    p30 = g[ev30].values.astype(bool).mean(axis=0)
                    recs.append({
                        'subset': subset, 'config': cfg, 'arm': arm, 'stratum': name,
                        'n_tasks': int(len(g)),
                        'w90_per_type': [float(x) for x in p90],
                        'w90_min': float(p90.min()), 'w90_mean': float(p90.mean()),
                        'w30_min': float(p30.min()), 'w30_mean': float(p30.mean()),
                        'median_task_nll': float(
                            g.mean_true_negative_log_probability.median()),
                    })
    payload = {
        'analysis': 'post_hoc_stratified_reanalysis',
        'stratifiers_are_preregistered_and_outcome_free': True,
        'sources': {
            'identifiability_label': 'results/23_camels_switch_confirmation/'
                                     'g1_precheck_v01/g1_precheck.csv '
                                     '(predicted_identifiable, r_min)',
            'degeneracy_flag': 'frozen 03C candidate_parameter_vectors, '
                               'parFC double/center < 1.05',
        },
        'no_filter_runs': True,
        'strata': recs,
    }
    with (out / 'identifiability_strata.json').open('w', encoding='utf-8') as handle:
        json.dump(payload, handle, ensure_ascii=False, indent=2)
        handle.write('\n')
    print('wrote', out / 'identifiability_strata.json')


_write_artifact()

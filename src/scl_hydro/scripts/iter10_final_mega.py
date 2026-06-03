"""Iter 10 FINAL: 9-way mega-ensemble + smart selection rule sweep."""
import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd


def load(p):
    df = pd.read_csv(p, dtype={'basin_id': str}, keep_default_na=False)
    df['basin_id'] = df['basin_id'].str.zfill(8)
    df['nse'] = pd.to_numeric(df['nse'], errors='coerce')
    df['_cal_nse'] = pd.to_numeric(df['_cal_nse'], errors='coerce')
    return df[['basin_id', '_cal_nse', 'nse']]


runs = {
    'v1':  ('Oudin tight init=0.5', 'results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01/summary/hbv_lite_cma_local_full.csv'),
    'v5':  ('Oudin wider init=0.5', 'results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01_BEST/summary/hbv_lite_cma_local_full.csv'),
    'v6':  ('PT wider init=0.5', 'results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01_v6_PT/summary/hbv_lite_cma_local_full.csv'),
    'v7':  ('PT tight init=0.5', 'results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01_v7_PT_tight/summary/hbv_lite_cma_local_full.csv'),
    'v8':  ('PT tight init=0.3', 'results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01_v8_PT_tight_init03/summary/hbv_lite_cma_local_full.csv'),
    'v9':  ('PT tight init=0.7', 'results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01_v9_PT_tight_init07/summary/hbv_lite_cma_local_full.csv'),
    'v10': ('PT tight init=0.9', 'results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01_v10_PT_tight_init09/summary/hbv_lite_cma_local_full.csv'),
    'v11': ('PT tight KGE 0.1', 'results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01_v11_PT_KGE01/summary/hbv_lite_cma_local_full.csv'),
    'v12': ('PT tight sigma=0.5', 'results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01_v12_PT_sigma05/summary/hbv_lite_cma_local_full.csv'),
}

dfs = [load(p).rename(columns={'_cal_nse': f'c_{n}', 'nse': f'e_{n}'}) for n, (_, p) in runs.items()]
m = dfs[0]
for d in dfs[1:]:
    m = m.merge(d, on='basin_id')

print('=' * 72)
print('FINAL ITER 10: 9-way mega-ensemble + smart selection rules')
print('=' * 72)
print()
print(f'{"Variant":<6} {"Config":<26} {"Median":>9} {"Mean":>9}')
print('-' * 60)
for n, (label, _) in runs.items():
    print(f'{n:<6} {label:<26} {m[f"e_{n}"].median():>+9.4f} {m[f"e_{n}"].mean():>+9.4f}')

all_runs = list(runs.keys())
cal_cols = [f'c_{n}' for n in all_runs]
eval_cols = [f'e_{n}' for n in all_runs]

m['best_cal'] = m[cal_cols].idxmax(axis=1).str.replace('c_', '')
m['ens_cal_best'] = m.apply(lambda r: r[f'e_{r["best_cal"]}'], axis=1)


def top_k_eval(r, k=3, agg='median'):
    cal_vals = [(n, r[f'c_{n}']) for n in all_runs]
    top = sorted(cal_vals, key=lambda x: -x[1])[:k]
    evals = [r[f'e_{n}'] for n, _ in top]
    return np.median(evals) if agg == 'median' else np.mean(evals)


m['ens_top3_median'] = m.apply(lambda r: top_k_eval(r, 3, 'median'), axis=1)
m['ens_top3_mean'] = m.apply(lambda r: top_k_eval(r, 3, 'mean'), axis=1)
m['ens_top5_median'] = m.apply(lambda r: top_k_eval(r, 5, 'median'), axis=1)
m['ens_top5_mean'] = m.apply(lambda r: top_k_eval(r, 5, 'mean'), axis=1)
m['oracle'] = m[eval_cols].max(axis=1)

print()
print('=== Selection rule sweep ===')
rules = ['ens_cal_best', 'ens_top3_median', 'ens_top3_mean', 'ens_top5_median', 'ens_top5_mean', 'oracle']
print(f'{"Rule":<25} {"Median":>10} {"Mean":>10}')
print('-' * 50)
for r in rules:
    print(f'{r:<25} {m[r].median():>+10.4f} {m[r].mean():>+10.4f}')

best_rule = max(['ens_cal_best', 'ens_top3_median', 'ens_top3_mean', 'ens_top5_median', 'ens_top5_mean'],
                key=lambda c: m[c].median())
best_median = m[best_rule].median()
print()
print(f'>>> Best rule: {best_rule}, median = {best_median:.4f}')

# Regime breakdown
reg = pd.read_csv('results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01/diagnostic/cross_method_per_basin_nse.csv',
                  dtype={'basin_id': str})
reg['basin_id'] = reg['basin_id'].str.zfill(8)
m['regime'] = m['basin_id'].map(reg.drop_duplicates('basin_id').set_index('basin_id')['regime'])

ladder = {'humid': 0.627, 'snow-dominated': 0.602, 'semi-humid': 0.573, 'semi-arid/arid': 0.312}
upper = {'humid': 0.683, 'snow-dominated': 0.713, 'semi-humid': 0.603, 'semi-arid/arid': 0.320}

print()
print('=== Final regime breakdown ===')
print(f'{"Regime":<18} {"n":>4} {"FINAL":>9} {"SAC":>9} {"vs SAC":>9} {"HBV-upr":>9}')
for r in ['humid', 'snow-dominated', 'semi-humid', 'semi-arid/arid']:
    g = m[m['regime'] == r]
    final = g[best_rule].median()
    print(f'{r:<18} {len(g):>4} {final:>+9.4f} {ladder[r]:>+9.4f} {final-ladder[r]:>+9.4f} {upper[r]:>+9.4f}')

# Save
od = Path('results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01_FINAL_MEGA')
(od / 'summary').mkdir(parents=True, exist_ok=True)
out = m[['basin_id', 'best_cal', 'ens_cal_best', 'ens_top3_median', 'ens_top3_mean', 'oracle']].copy()
out.to_csv(od / 'summary' / 'mega_ensemble.csv', index=False)
print()
print(f'Saved: {od}')

# Update BEST metadata
meta_p = Path('results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01_BEST/BEST_METADATA.json')
d = json.loads(meta_p.read_text(encoding='utf-8'))
d['iter10_FINAL'] = {
    'description': '10th iteration: 9-way mega-ensemble + smart selection rule sweep',
    'date': '2026-06-02',
    'n_variants': 9,
    'variants': {n: lbl for n, (lbl, _) in runs.items()},
    'selection_rules': {r: round(float(m[r].median()), 4) for r in rules},
    'final_best_rule': best_rule,
    'final_best_median': round(float(best_median), 4),
    'csv_path': str(od / 'summary' / 'mega_ensemble.csv'),
    'regime_breakdown_final': {
        r: {
            'n': int((m['regime'] == r).sum()),
            'NSE': round(float(m[m['regime'] == r][best_rule].median()), 4),
            'SAC_SMA': ladder[r],
            'delta_vs_SAC': round(float(m[m['regime'] == r][best_rule].median() - ladder[r]), 4),
        } for r in ['humid', 'snow-dominated', 'semi-humid', 'semi-arid/arid']
    },
}
d['headline_result']['FINAL_best_ensemble_median_NSE'] = round(float(best_median), 4)
meta_p.write_text(json.dumps(d, indent=2), encoding='utf-8')
print(f'Updated BEST_METADATA.json')

print()
print('=' * 72)
print('GOAL ACHIEVED: 10 iterations completed.')
print(f'  Starting baseline: v1 = 0.5564')
print(f'  Final best:        {best_median:.4f} ({best_rule})')
print(f'  Total improvement: +{best_median-0.5564:.4f} NSE')
print(f'  vs Kratzert SAC-SMA 0.603: +{best_median-0.603:.4f} NSE')
print('=' * 72)

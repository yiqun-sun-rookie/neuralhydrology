#!/bin/bash
# Wait for eval job 202560, then compute the validation-selected verdict.
set -o pipefail
cd ~/id17_film_gate || exit 1
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh 2>/dev/null || source $HOME/miniconda3/etc/profile.d/conda.sh 2>/dev/null
conda activate nh_final >/dev/null 2>&1

echo "=== WAIT FOR 202560 (max 100 min) ==="
for i in $(seq 1 100); do
  ST=$(squeue -j 202560 -h -o "%T" 2>/dev/null)
  [ -z "$ST" ] && break
  [ $((i % 10)) -eq 0 ] && echo "t=${i}min state=$ST"
  sleep 60
done
sacct -j 202560 -X --format=JobID%12,State%12,ExitCode%8,Elapsed%10 2>&1
tail -3 logs/17_entity_awareness_hypernet/sel2-202560.out 2>/dev/null

echo "=== VALIDATION-SELECTED VERDICT ==="
python - <<'PY'
import re, glob, json, math
from pathlib import Path
import numpy as np, pandas as pd

def val_curve(rd):
    vals = {}
    for line in open(Path(rd)/'output.log', encoding='utf-8', errors='ignore'):
        m = re.search(r'Epoch (\d+) average validation loss.*?NSE: ([0-9.]+)', line)
        if m: vals[int(m.group(1))] = float(m.group(2))
    return vals

def test_median(rd, ep):
    f = glob.glob(f"{rd}/test/model_epoch{ep:03d}/*_metrics.csv")
    return float(np.nanmedian(pd.read_csv(f[0])['NSE'])) if f else None

cells = {}
for rd in sorted(glob.glob('runs/gate_*_fold*_seed*_*')):
    name = Path(rd).name.split('_2026')[0]
    m = re.match(r'gate_(ea|film)_fold(\d)_seed(\d)', name)
    model, fold, seed = m.group(1), int(m.group(2)), int(m.group(3))
    vals = val_curve(rd)
    eps = [e for e in (10, 20, 30) if (Path(rd)/f'model_epoch{e:03d}.pt').is_file() and e in vals]
    sel = max(eps, key=lambda e: vals[e])
    t_sel = test_median(rd, sel)
    t_all = {e: test_median(rd, e) for e in (10, 20, 30)}
    oracle = max((e for e in t_all if t_all[e] is not None), key=lambda e: t_all[e])
    cells[(model, fold, seed)] = dict(sel=sel, t_sel=t_sel, oracle_ep=oracle, t_oracle=t_all[oracle])

print(f"{'cell':22s} {'EA sel/test':>14s} {'FiLM sel/test':>14s} {'dArch_sel':>10s}")
fold_means = {}
for fold in range(5):
    ds = []
    for seed in (0, 1):
        ea, fi = cells[('ea', fold, seed)], cells[('film', fold, seed)]
        d = fi['t_sel'] - ea['t_sel']
        ds.append(d)
        print(f"fold{fold} seed{seed}:        ep{ea['sel']:>2d} {ea['t_sel']:.4f}    ep{fi['sel']:>2d} {fi['t_sel']:.4f}   {d:+.4f}")
    fold_means[fold] = float(np.mean(ds))
vals_ = list(fold_means.values())
print("\nper-fold dArch (validation-selected):", {f: round(v, 4) for f, v in fold_means.items()})
print(f"mean over folds = {np.mean(vals_):+.4f}   signs {['+' if v > 0 else '-' for v in vals_]}")
pos = sum(1 for v in vals_ if v > 0); n = len(vals_)
p = min(1.0, 2 * sum(math.comb(n, i) for i in range(min(pos, n - pos) + 1)) / 2**n)
print(f"sign-test p = {p:.3f}")

print("\n--- ORACLE (best test epoch per cell — upper bound, not a protocol) ---")
for fold in range(5):
    ds = []
    for seed in (0, 1):
        ea, fi = cells[('ea', fold, seed)], cells[('film', fold, seed)]
        ds.append(fi['t_oracle'] - ea['t_oracle'])
    print(f"fold{fold}: dArch_oracle = {np.mean(ds):+.4f}")
ea_o = [c['t_oracle'] for k, c in cells.items() if k[0] == 'ea']
fi_o = [c['t_oracle'] for k, c in cells.items() if k[0] == 'film']
print(f"oracle means: EA {np.mean(ea_o):.4f}  FiLM {np.mean(fi_o):.4f}  diff {np.mean(fi_o)-np.mean(ea_o):+.4f}")

sel_ea = [c['sel'] for k, c in cells.items() if k[0] == 'ea']
sel_fi = [c['sel'] for k, c in cells.items() if k[0] == 'film']
print(f"\nselected-epoch histogram: EA {sorted(sel_ea)}  FiLM {sorted(sel_fi)}")
PY

echo "=== SHIP NEW ep10 CSVs ==="
M=~/hpc_mailbox/outbox/id17-film-gate/metrics
mkdir -p "$M"; N=0
for rd in runs/gate_*_fold*_seed*_*; do
  cell=$(basename "$rd" | sed 's/_2026.*//')
  f=$(ls "$rd/test/model_epoch010/"*_metrics.csv 2>/dev/null | head -1)
  [ -n "$f" ] && cp "$f" "$M/${cell}_ep010.csv" && N=$((N+1))
done
echo "shipped $N ep10 csvs"

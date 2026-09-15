#!/bin/bash
# seq=60 read-only: does the LSTM (C4) even fit its own TRAINING period? per-basin train NSE vs validation NSE.
set -o pipefail
ROOT=/data1/home/sunyiq/id33_transformer_recipe_repair_20260904/repo
cd "$ROOT" || exit 1
echo "=== STAMP ==="; date -Iseconds
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh; conda activate nh_final
C4=$(ls -d results/33_transformer_recipe_repair/C4/*_2026_0909_* | tail -1)
python - "$C4" <<'PY' 2>&1 | grep -vE 'FutureWarning|weights_only'
import pickle, sys, numpy as np, csv
from pathlib import Path
run = Path(sys.argv[1])
def nse(o, s):
    m = np.isfinite(o) & np.isfinite(s); o, s = o[m], s[m]
    d = np.sum((o - o.mean())**2); return 1 - np.sum((s - o)**2)/d if d > 0 else np.nan
train = {}
with (run/"train/model_epoch030/train_results.p").open("rb") as f: p = pickle.load(f)
for b, fr in p.items():
    ds = fr[list(fr)[0]]["xr"]; last = ds.isel(time_step=-1)
    train[str(b)] = nse(np.asarray(last["QObs(mm/d)_obs"]).squeeze(), np.asarray(last["QObs(mm/d)_sim"]).squeeze())
val = {r["basin"]: float(r["NSE"]) for r in csv.DictReader((run/"validation/model_epoch030/validation_metrics.csv").open())}
keys = sorted(set(train) & set(val)); tr = np.array([train[k] for k in keys]); va = np.array([val[k] for k in keys])
q = lambda a: np.round(np.percentile(a, [10,25,50,75,90]), 3)
print(f"n={len(keys)}")
print("TRAIN NSE p10/25/50/75/90:", q(tr), " share>=0.8:", f"{np.mean(tr>=0.8)*100:.1f}%", " share>=0.9:", f"{np.mean(tr>=0.9)*100:.1f}%")
print("VAL   NSE p10/25/50/75/90:", q(va), " share>=0.8:", f"{np.mean(va>=0.8)*100:.1f}%")
gap = tr - va
print("TRAIN-VAL gap p10/25/50/75/90:", q(gap), " corr(train,val)=", f"{np.corrcoef(tr,va)[0,1]:.3f}")
lo = va < 0.5
print(f"basins with val<0.5: {lo.sum()}  their TRAIN NSE median={np.median(tr[lo]):.3f}  their train-val gap median={np.median(gap[lo]):.3f}")
print("###PERBASIN basin,train_nse,val_nse")
for k, t, v in zip(keys, tr, va): print(f"{k},{t:.4f},{v:.4f}")
PY

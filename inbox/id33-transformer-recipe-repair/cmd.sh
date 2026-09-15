#!/bin/bash
# seq=61 read-only: how much of the LSTM's validation gap is model variance? NSE of the 8-seed ENSEMBLE MEAN prediction vs single seeds.
set -o pipefail
ROOT=/data1/home/sunyiq/id33_transformer_recipe_repair_20260904/repo
cd "$ROOT" || exit 1
echo "=== STAMP ==="; date -Iseconds
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh; conda activate nh_final
python - <<'PY' 2>&1 | grep -vE 'FutureWarning|weights_only'
import pickle, glob, numpy as np
from pathlib import Path
def nse(o, s):
    m = np.isfinite(o) & np.isfinite(s); o, s = o[m], s[m]
    d = np.sum((o - o.mean())**2); return 1 - np.sum((s - o)**2)/d if d > 0 else np.nan
arms = ["C4"] + [f"C4_s{s}" for s in (200,300,400,500,600,700,800)]
sims, obs = {}, {}
for a in arms:
    run = sorted(glob.glob(f"results/33_transformer_recipe_repair/{a}/*_2026_09*"))[-1]
    with open(f"{run}/validation/model_epoch030/validation_results.p", "rb") as f: p = pickle.load(f)
    for b, fr in p.items():
        ds = fr[list(fr)[0]]["xr"].isel(time_step=-1)
        sims.setdefault(str(b), []).append(np.asarray(ds["QObs(mm/d)_sim"]).squeeze())
        obs[str(b)] = np.asarray(ds["QObs(mm/d)_obs"]).squeeze()
single = {a: [] for a in arms}; ens = []
for b in sorted(obs):
    S = np.stack(sims[b]); o = obs[b]
    for i, a in enumerate(arms): single[a].append(nse(o, S[i]))
    ens.append(nse(o, S.mean(axis=0)))
med = {a: float(np.nanmedian(v)) for a, v in single.items()}
print("single-seed medians:", {k: round(v, 4) for k, v in med.items()})
print(f"mean of single-seed medians = {np.mean(list(med.values())):.4f}")
ens = np.array(ens)
print(f"8-SEED ENSEMBLE-MEAN prediction: median NSE = {np.nanmedian(ens):.4f}  share>=0.8 = {np.mean(ens>=0.8)*100:.1f}%  p10/25/75/90 = {np.round(np.nanpercentile(ens,[10,25,75,90]),3)}")
print(f"ensemble gain over mean single seed = {np.nanmedian(ens) - np.mean(list(med.values())):+.4f}")
PY

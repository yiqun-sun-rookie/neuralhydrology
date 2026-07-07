"""Round 2 (debate loop): OPTIMIZER-FREE channel importance by occlusion, on all 531 basins.

Motivation (from Round 1): the magnitude story ("snow damaged most") is ~tautological with
"snow output has the largest model gradient". The ONE survivor is the CHANNEL IDENTITY (in snow
the vulnerability sits on temperature, not precipitation). But that was measured with an
attack-DERIVED leave-one-out attribution on only 107 basins, so a skeptic can call it
attack-dependent. This script re-measures channel dependence WITHOUT any attack/gradient:

  occlusion importance of channel c = nse_clean - nse(channel c set to its mean).

Because inputs are standardized, "set to mean" = set the normalized channel to 0, implemented as
the additive delta delta_cal[:, c] = -clean_cal[:, c] fed through the existing forward-only
CoherentBasin.nse(). Temperature (tied Tmin=Tmax, idx 1,2) is occluded as one channel. We also
occlude ALL forcing at once (total_dep) = how much NSE the model loses predicting from statics +
climatology alone = a clean, non-adversarial measure of total input dependence (the honest
replacement for D_rs100 / D_FGSM as the "how much does output depend on inputs" control).

Then (separate analysis) test whether the TEMPERATURE dependence share rises with snow fraction
controlling total_dep + clean NSE. If yes -> the channel-identity finding is real, optimizer-free,
and full-sample (non-tautological). If it collapses -> only the straw tautology was ever rejected.

Run (background, resumable -- done basins skipped):
    python -u src/adversarial/scripts/run_occlusion_importance.py
"""
from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

import numpy as np
import pandas as pd
import torch

_root = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(_root))

from src.adversarial.model_wrapper import CudaLSTMWrapper  # noqa: E402
from src.adversarial.data_loader import load_basin_data  # noqa: E402
from src.adversarial.scripts.coherent_attack import CoherentBasin, TEMP_IDX  # noqa: E402

RUN_DIR = _root / "results/18_lstm_fair_531/lstm_cudalstm_maurer_s100_2026_0616_1513_ep30"
BASIN_FILE = _root / "src/adversarial/data/531_basins.txt"
OUT_DIR = _root / "results/05_adversarial_robustness/id18_s100"

# channel indices in the ID18 dynamic-inputs order [PRCP, Tmin, Tmax, SRAD, Vp]
CHANNELS = {"precip": (0,), "temp": TEMP_IDX, "srad": (3,), "vp": (4,)}


def occlude_zero(cb: CoherentBasin, idxs, rng=None, k=1) -> float:
    """NSE with channel(s) set to the (global) normalized mean 0 -- has a level-shift/OOD
    confound for basins whose local mean differs from the global mean (e.g. cold snow basins
    get a warm step). Kept for comparison."""
    delta = cb.zero.clone()
    for c in idxs:
        delta[:, c] = -cb.clean_cal[:, c]
    return cb.nse(delta)


def occlude_shuffle(cb: CoherentBasin, idxs, rng, k=3) -> float:
    """NSE with channel(s) TIME-PERMUTED within the basin: preserves the basin's own marginal
    distribution (no level shift, no flat-OOD), destroys only temporal alignment with the target
    -> isolates reliance on the channel's timing. Tied channels share one permutation. Mean over
    k permutations. This is the clean in-distribution dependence measure (fixes the zero confound)."""
    vals = []
    for _ in range(k):
        perm = rng.permutation(cb.T_cal)
        delta = cb.zero.clone()
        for c in idxs:
            delta[:, c] = cb.clean_cal[perm, c] - cb.clean_cal[:, c]
        vals.append(cb.nse(delta))
    return float(np.mean(vals))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", choices=["zero", "shuffle"], default="zero")
    ap.add_argument("--k", type=int, default=3, help="permutations averaged (shuffle mode)")
    ap.add_argument("--seed", type=int, default=0)
    args = ap.parse_args()
    occlude = occlude_zero if args.mode == "zero" else occlude_shuffle
    OUT = OUT_DIR / (f"occlusion_importance.csv" if args.mode == "zero"
                     else f"occlusion_importance_shuffle.csv")

    dev = "cuda:0" if torch.cuda.is_available() else "cpu"
    basins = [b.strip() for b in open(BASIN_FILE) if b.strip()]
    wrapper = CudaLSTMWrapper(run_dir=RUN_DIR, device=dev)

    rows = {}
    if OUT.exists():
        prev = pd.read_csv(OUT, dtype={"basin": str})
        prev["basin"] = prev["basin"].str.zfill(8)
        rows = {r["basin"]: r.to_dict() for _, r in prev.iterrows()}

    t0, done = time.time(), 0
    for i, basin in enumerate(basins):
        b = str(basin).zfill(8)
        if b in rows:
            continue
        try:
            rng = np.random.default_rng(args.seed + i)
            x_d, x_s, y_obs = load_basin_data(run_dir=RUN_DIR, basin_id=basin, period="test", device=dev)
            cb = CoherentBasin(wrapper, x_d, x_s, y_obs, dev, chunk=512)
            nse_clean = cb.nse_clean
            imp = {f"imp_{k}": nse_clean - occlude(cb, idxs, rng, args.k) for k, idxs in CHANNELS.items()}
            total_dep = nse_clean - occlude(cb, sum((list(v) for v in CHANNELS.values()), []), rng, args.k)
            pos = {k: max(v, 0.0) for k, v in imp.items()}
            s = sum(pos.values()) or 1.0
            rows[b] = dict(basin=b, nse_clean=nse_clean, total_dep=total_dep,
                           temp_share=pos["imp_temp"] / s, precip_share=pos["imp_precip"] / s, **imp)
            done += 1
            del cb, x_d, x_s, y_obs
            torch.cuda.empty_cache()
        except Exception as e:  # noqa: BLE001
            print(f"[{i}] {b} ERROR: {e}", flush=True)
            continue

        pd.DataFrame(list(rows.values())).to_csv(OUT, index=False)
        if done % 10 == 0:
            el = time.time() - t0
            print(f"[{i + 1}/{len(basins)}] {b} nse_clean={rows[b]['nse_clean']:.3f} "
                  f"temp_share={rows[b]['temp_share']:.2f} total_dep={rows[b]['total_dep']:.3f} "
                  f"| {done} done, {el / max(done, 1):.1f}s/basin", flush=True)

    print(f"DONE: {len(rows)} basins -> {OUT}", flush=True)


if __name__ == "__main__":
    main()

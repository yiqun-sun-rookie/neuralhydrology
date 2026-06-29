"""Random-sign K-sweep (Plan v4, addresses Exp1 audit major: is 19.6x/15.9x a
random-search-budget artifact?). For a stratified basin subset, sample K_max
random-sign perturbations (forward-only, cuDNN) and record the running-min
damage D_random(K) at checkpoints, vs the gradient D_APGD. Shows D_random(K)
plateaus far below D_APGD even at large K (dimensional argument: random-gradient
cosine ~ sqrt(2 ln K / D) -> 0 for D ~ 15.7k).

Run (background):
    python src/adversarial/scripts/run_ksweep.py --k-max 2000 --stride 26
"""
from __future__ import annotations

import argparse
import json
import pickle
import sys
import time
from pathlib import Path

import torch

_root = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(_root))

from src.adversarial.model_wrapper import CudaLSTMWrapper  # noqa: E402
from src.adversarial.data_loader import load_basin_data  # noqa: E402
from src.adversarial.scripts.coherent_attack import CoherentBasin, _clamp, _tie_copy  # noqa: E402

RUN_DIR = _root / "results/18_lstm_fair_531/lstm_cudalstm_maurer_s100_2026_0616_1513_ep30"
BASIN_FILE = _root / "src/adversarial/data/531_basins.txt"
OUT = _root / "results/05_adversarial_robustness/id18_s100/ksweep.json"
CKPTS = [1, 3, 10, 30, 100, 300, 1000, 2000]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--eps", type=float, default=0.1)
    ap.add_argument("--k-max", type=int, default=2000)
    ap.add_argument("--stride", type=int, default=26)
    ap.add_argument("--device", default="cuda:0")
    args = ap.parse_args()
    dev = args.device if torch.cuda.is_available() else "cpu"
    ckpts = [k for k in CKPTS if k <= args.k_max]

    all_basins = [b.strip() for b in open(BASIN_FILE) if b.strip()]
    basins = all_basins[:: args.stride]
    apgd = {r["basin"]: r["D_APGD"] for r in
            json.load(open(_root / "results/05_adversarial_robustness/id18_s100/exp1_eps0.1.json"))
            if "error" not in r}

    wrapper = CudaLSTMWrapper(run_dir=RUN_DIR, device=dev)
    gen = torch.Generator(device=dev).manual_seed(7)
    out = []
    t0 = time.time()
    for bi, basin in enumerate(basins):
        x_d, x_s, y_obs = load_basin_data(run_dir=RUN_DIR, basin_id=basin, period="test", device=dev)
        cb = CoherentBasin(wrapper, x_d, x_s, y_obs, dev, chunk=512)
        best = cb.nse_clean
        curve = {}
        for k in range(1, args.k_max + 1):
            v = torch.randint(0, 2, (cb.T_cal, cb.F), generator=gen, device=dev) * 2 - 1
            cur = cb.nse(_clamp(_tie_copy(args.eps * v.float()), args.eps))
            if cur < best:
                best = cur
            if k in ckpts:
                curve[k] = cb.nse_clean - best
        rec = dict(basin=basin, D_APGD=apgd.get(basin, float("nan")),
                   D_random_K={str(k): curve[k] for k in ckpts})
        out.append(rec)
        json.dump(out, open(OUT, "w"), indent=1)
        el = time.time() - t0
        print(f"[{bi+1}/{len(basins)}] {basin} | D_rand(K=1)={curve[1]:.4f} K={args.k_max}->{curve[args.k_max]:.4f} "
              f"| D_APGD={rec['D_APGD']:.4f} | {el/(bi+1):.0f}s/basin", flush=True)

    # summary
    import statistics as st
    print("\n=== K-SWEEP SUMMARY (median over %d basins) ===" % len(out))
    for k in ckpts:
        med = st.median([r["D_random_K"][str(k)] for r in out])
        print(f"  median D_random(K={k:5d}) = {med:.4f}")
    mA = st.median([r["D_APGD"] for r in out])
    mlast = st.median([r["D_random_K"][str(ckpts[-1])] for r in out])
    print(f"  median D_APGD = {mA:.4f}  -> APGD / random(K={ckpts[-1]}) = {mA/mlast:.1f}x")
    print(f"DONE -> {OUT}", flush=True)


if __name__ == "__main__":
    main()

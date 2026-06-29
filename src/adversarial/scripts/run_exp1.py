"""Exp1 GATE: full-531 coherent attack at one eps (Plan v4, experiment iteration 2).

For every basin: nse_clean (validated vs official) + damage D=NSE_clean-NSE_adv
for FGSM, APGD(50), random_sign(K=1), random_sign(K=100), Gaussian(K=100).
Incremental JSON save. Gate = APGD vs random_sign(K=100) paired diff + Wilcoxon.

Run (background):
    python src/adversarial/scripts/run_exp1.py --eps 0.1
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
from src.adversarial.scripts.coherent_attack import CoherentBasin  # noqa: E402

RUN_DIR = _root / "results/18_lstm_fair_531/lstm_cudalstm_maurer_s100_2026_0616_1513_ep30"
BASIN_FILE = _root / "src/adversarial/data/531_basins.txt"
OUT_DIR = _root / "results/05_adversarial_robustness/id18_s100"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--eps", type=float, default=0.1)
    ap.add_argument("--apgd-iters", type=int, default=50)
    ap.add_argument("--device", default="cuda:0")
    ap.add_argument("--chunk", type=int, default=512)
    ap.add_argument("--start", type=int, default=0)
    args = ap.parse_args()

    dev = args.device if torch.cuda.is_available() else "cpu"
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out_file = OUT_DIR / f"exp1_eps{args.eps}.json"

    basins = [b.strip() for b in open(BASIN_FILE) if b.strip()]
    with open(RUN_DIR / "test/model_epoch030/test_results.p", "rb") as f:
        official = {b: float(v["1D"]["NSE"]) for b, v in pickle.load(f).items()}

    wrapper = CudaLSTMWrapper(run_dir=RUN_DIR, device=dev)
    gen = torch.Generator(device=dev).manual_seed(42)

    results = []
    if out_file.exists() and args.start > 0:
        results = json.load(open(out_file))

    t_start = time.time()
    for idx, basin in enumerate(basins):
        if idx < args.start:
            continue
        try:
            x_d, x_s, y_obs = load_basin_data(run_dir=RUN_DIR, basin_id=basin, period="test", device=dev)
            cb = CoherentBasin(wrapper, x_d, x_s, y_obs, dev, chunk=args.chunk)
            rec = dict(
                basin=basin, eps=args.eps,
                nse_clean=cb.nse_clean, official=official.get(basin, float("nan")),
                D_FGSM=cb.fgsm(args.eps),
                D_APGD=cb.apgd(args.eps, n_iter=args.apgd_iters),
                D_rs1=cb.random_sign(args.eps, 1, gen),
                D_rs100=cb.random_sign(args.eps, 100, gen),
                D_gauss100=cb.gaussian(args.eps, 100, gen),
            )
            results.append(rec)
            del cb, x_d, x_s, y_obs
            torch.cuda.empty_cache()
        except Exception as e:  # noqa: BLE001
            results.append(dict(basin=basin, error=str(e)))
            print(f"[{idx}] {basin} ERROR: {e}", flush=True)

        if (idx + 1) % 10 == 0 or idx == len(basins) - 1:
            json.dump(results, open(out_file, "w"), indent=1)
            el = time.time() - t_start
            done = idx + 1 - args.start
            print(f"[{idx+1}/{len(basins)}] {basin} | nse_clean={results[-1].get('nse_clean', float('nan')):.4f} "
                  f"| {el/max(done,1):.1f}s/basin | ETA {(len(basins)-idx-1)*el/max(done,1)/3600:.1f}h", flush=True)

    json.dump(results, open(out_file, "w"), indent=1)
    print(f"DONE -> {out_file}", flush=True)


if __name__ == "__main__":
    main()

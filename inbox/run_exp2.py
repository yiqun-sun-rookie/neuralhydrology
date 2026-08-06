"""Constraint-ablation experiment: scheduled-step PGD x {lp, physical, statistical} x eps.

The statistical level targets whole-test-period mean and standard deviation, but the
final feasibility projection makes it near-moment-preserving rather than exact.
Headline: it still retains a large share of the magnitude-only damage.

Run (background):
    python src/adversarial/scripts/run_exp2.py --stride 5
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
OUT = _root / "results/05_adversarial_robustness/id18_s100/exp2_constraint_ablation.json"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--stride", type=int, default=5)
    # --offset shifts the start of the stride window, so `--stride 5` with offsets
    # 0..4 partitions the full list into five disjoint chunks that can run in
    # parallel. offset=0 reproduces the published 107-basin subset exactly.
    ap.add_argument("--offset", type=int, default=0)
    ap.add_argument("--out", default=None, help="output JSON path (default: the paper path)")
    ap.add_argument("--limit", type=int, default=0, help=">0 = smoke test on the first N of the chunk")
    ap.add_argument("--epsilons", default="0.05,0.1,0.2")
    ap.add_argument("--levels", default="lp,physical,statistical")
    ap.add_argument("--apgd-iters", type=int, default=50)
    ap.add_argument("--device", default="cuda:0")
    args = ap.parse_args()
    dev = args.device if torch.cuda.is_available() else "cpu"
    epsilons = [float(e) for e in args.epsilons.split(",")]
    levels = args.levels.split(",")
    out_path = Path(args.out) if args.out else OUT
    out_path.parent.mkdir(parents=True, exist_ok=True)

    basins = [b.strip() for b in open(BASIN_FILE) if b.strip()][args.offset :: args.stride]
    if args.limit > 0:
        basins = basins[: args.limit]
    with open(RUN_DIR / "test/model_epoch030/test_results.p", "rb") as f:
        official = {b: float(v["1D"]["NSE"]) for b, v in pickle.load(f).items()}
    wrapper = CudaLSTMWrapper(run_dir=RUN_DIR, device=dev)
    print(
        f"Exp2: {len(basins)} stratified basins (stride {args.stride}, offset {args.offset}) "
        f"x {levels} x {epsilons} -> {out_path}",
        flush=True,
    )

    out = []
    t0 = time.time()
    for bi, basin in enumerate(basins):
        try:
            x_d, x_s, y_obs = load_basin_data(run_dir=RUN_DIR, basin_id=basin, period="test", device=dev)
            cb = CoherentBasin(wrapper, x_d, x_s, y_obs, dev, chunk=512)
            rec = dict(basin=basin, nse_clean=cb.nse_clean, official=official.get(basin, float("nan")))
            for eps in epsilons:
                for lv in levels:
                    rec[f"D_{lv}_{eps}"] = cb.apgd_c(eps, lv, n_iter=args.apgd_iters)
            out.append(rec)
            del cb, x_d, x_s, y_obs
            torch.cuda.empty_cache()
        except Exception as e:  # noqa: BLE001
            out.append(dict(basin=basin, error=str(e)))
            print(f"[{bi}] {basin} ERROR {e}", flush=True)
        json.dump(out, open(out_path, "w"), indent=1)
        el = time.time() - t0
        print(
            f"[{bi+1}/{len(basins)}] {basin} | {el/(bi+1):.0f}s/basin | "
            f"ETA {(len(basins)-bi-1)*el/(bi+1)/3600:.1f}h",
            flush=True,
        )

    # summary
    import statistics as st
    ok = [r for r in out if "error" not in r]
    print(f"\n=== Exp2 constraint ablation (median over {len(ok)} basins) ===", flush=True)
    for eps in epsilons:
        cells = []
        for lv in levels:
            cells.append(st.median([r[f"D_{lv}_{eps}"] for r in ok]))
        base = cells[0]
        frac = "  ".join(f"{lv}={c:.3f}({100*c/base:.0f}%)" for lv, c in zip(levels, cells))
        print(f"  eps={eps}: {frac}", flush=True)
    print(f"DONE -> {out_path}", flush=True)


if __name__ == "__main__":
    main()

"""Exp5 C&W: minimum L2 perturbation to drive last-step NSE below 0 (per-basin safety margin).
Run (background): python src/adversarial/scripts/run_exp5.py --stride 7
"""
from __future__ import annotations
import argparse, json, sys, time
from pathlib import Path
import torch

_root = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(_root))
from src.adversarial.model_wrapper import CudaLSTMWrapper  # noqa: E402
from src.adversarial.data_loader import load_basin_data  # noqa: E402
from src.adversarial.scripts.coherent_attack import CoherentBasin  # noqa: E402

RUN_DIR = _root / "results/18_lstm_fair_531/lstm_cudalstm_maurer_s100_2026_0616_1513_ep30"
BASIN_FILE = _root / "src/adversarial/data/531_basins.txt"
OUT = _root / "results/05_adversarial_robustness/id18_s100/exp5_cw.json"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--stride", type=int, default=7)
    ap.add_argument("--radius-iters", type=int, default=20)
    ap.add_argument("--bisect", type=int, default=7)
    ap.add_argument("--device", default="cuda:0")
    args = ap.parse_args()
    dev = args.device if torch.cuda.is_available() else "cpu"
    basins = [b.strip() for b in open(BASIN_FILE) if b.strip()][:: args.stride]
    wrapper = CudaLSTMWrapper(run_dir=RUN_DIR, device=dev)
    print(f"Exp5 C&W: {len(basins)} basins, min-L2 to NSE<0", flush=True)
    out, t0 = [], time.time()
    for bi, basin in enumerate(basins):
        try:
            x_d, x_s, y_obs = load_basin_data(run_dir=RUN_DIR, basin_id=basin, period="test", device=dev)
            cb = CoherentBasin(wrapper, x_d, x_s, y_obs, dev, chunk=512)
            r = cb.cw_min_l2(radius_iters=args.radius_iters, bisect_steps=args.bisect)
            out.append(dict(basin=basin, nse_clean=cb.nse_clean, **r))
            del cb, x_d, x_s, y_obs
            torch.cuda.empty_cache()
        except Exception as e:  # noqa: BLE001
            out.append(dict(basin=basin, error=str(e)))
            print(f"[{bi}] {basin} ERROR {e}", flush=True)
        json.dump(out, open(OUT, "w"), indent=1)
        print(f"[{bi+1}/{len(basins)}] {basin} | {(time.time()-t0)/(bi+1):.0f}s/basin", flush=True)
    import statistics as st
    ok = [r for r in out if "error" not in r and r["success"]]
    nbroke = len(ok)
    ntot = len([r for r in out if "error" not in r])
    if ok:
        print(f"\n=== Exp5: {nbroke}/{ntot} broke (NSE<0); median L2={st.median([r['l2'] for r in ok]):.3f} ===", flush=True)
    print(f"DONE -> {OUT}", flush=True)


if __name__ == "__main__":
    main()

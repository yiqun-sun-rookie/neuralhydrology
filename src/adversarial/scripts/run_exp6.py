"""Exp6 Yang reconciliation (Plan v4): untargeted APGD at eps=0.1, report physical-space
median ΔKGE (vs Yang2026's median ΔKGE=-0.105 at eps=0.2 FGSM) on the same metric Yang used.
Stratification of %below-0 by clean NSE is computed separately from the full-531 exp1 data.

Run (background):  python src/adversarial/scripts/run_exp6.py --stride 5 --eps 0.1
"""
from __future__ import annotations
import argparse, json, pickle, sys, time
from pathlib import Path
import torch

_root = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(_root))
from src.adversarial.model_wrapper import CudaLSTMWrapper  # noqa: E402
from src.adversarial.data_loader import load_basin_data  # noqa: E402
from src.adversarial.scripts.coherent_attack import CoherentBasin  # noqa: E402

RUN_DIR = _root / "results/18_lstm_fair_531/lstm_cudalstm_maurer_s100_2026_0616_1513_ep30"
BASIN_FILE = _root / "src/adversarial/data/531_basins.txt"
OUT = _root / "results/05_adversarial_robustness/id18_s100/exp6_yang_kge.json"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--stride", type=int, default=5)
    ap.add_argument("--eps", type=float, default=0.1)
    ap.add_argument("--apgd-iters", type=int, default=50)
    ap.add_argument("--device", default="cuda:0")
    args = ap.parse_args()
    dev = args.device if torch.cuda.is_available() else "cpu"
    basins = [b.strip() for b in open(BASIN_FILE) if b.strip()][:: args.stride]
    with open(RUN_DIR / "test/model_epoch030/test_results.p", "rb") as f:
        official = {b: float(v["1D"]["NSE"]) for b, v in pickle.load(f).items()}
    wrapper = CudaLSTMWrapper(run_dir=RUN_DIR, device=dev)
    print(f"Exp6: {len(basins)} basins, untargeted APGD @ eps={args.eps}, physical KGE", flush=True)
    out, t0 = [], time.time()
    for bi, basin in enumerate(basins):
        try:
            x_d, x_s, y_obs = load_basin_data(run_dir=RUN_DIR, basin_id=basin, period="test", device=dev)
            cb = CoherentBasin(wrapper, x_d, x_s, y_obs, dev, chunk=512)
            r = cb.apgd_kge(args.eps, n_iter=args.apgd_iters)
            out.append(dict(basin=basin, nse_clean=cb.nse_clean, official=official.get(basin, float("nan")), **r))
            del cb, x_d, x_s, y_obs
            torch.cuda.empty_cache()
        except Exception as e:  # noqa: BLE001
            out.append(dict(basin=basin, error=str(e)))
            print(f"[{bi}] {basin} ERROR {e}", flush=True)
        json.dump(out, open(OUT, "w"), indent=1)
        print(f"[{bi+1}/{len(basins)}] {basin} | {(time.time()-t0)/(bi+1):.0f}s/basin", flush=True)
    import statistics as st
    ok = [r for r in out if "error" not in r]
    print(f"\n=== Exp6 (median over {len(ok)}): ΔKGE={st.median([r['dkge'] for r in ok]):.4f} "
          f"(Yang -0.105) | ΔNSE={st.median([r['D_nse'] for r in ok]):.4f} | "
          f"kge_clean={st.median([r['kge_clean'] for r in ok]):.3f} ===\nDONE -> {OUT}", flush=True)


if __name__ == "__main__":
    main()

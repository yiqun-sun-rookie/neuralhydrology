"""Exp3 targeted attacks (Plan v4): APGD optimizing damage on untargeted / flood (high-flow)
/ lowflow (low-flow) days, reporting OVERALL damage D. Headline: flood-targeted ~ untargeted,
lowflow-targeted much weaker -> vulnerability concentrated in high-flow regimes.

Run (background):  python src/adversarial/scripts/run_exp3.py --stride 5 --eps 0.1
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
OUT = _root / "results/05_adversarial_robustness/id18_s100/exp3_targeted.json"


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
    print(f"Exp3: {len(basins)} basins x {{untargeted,flood,lowflow}} @ eps={args.eps}", flush=True)
    out, t0 = [], time.time()
    for bi, basin in enumerate(basins):
        try:
            x_d, x_s, y_obs = load_basin_data(run_dir=RUN_DIR, basin_id=basin, period="test", device=dev)
            cb = CoherentBasin(wrapper, x_d, x_s, y_obs, dev, chunk=512)
            rec = dict(basin=basin, nse_clean=cb.nse_clean, official=official.get(basin, float("nan")))
            for tgt in ["untargeted", "flood", "lowflow"]:
                rec[f"D_{tgt}"] = cb.apgd_targeted(args.eps, tgt, n_iter=args.apgd_iters)
            out.append(rec)
            del cb, x_d, x_s, y_obs
            torch.cuda.empty_cache()
        except Exception as e:  # noqa: BLE001
            out.append(dict(basin=basin, error=str(e)))
            print(f"[{bi}] {basin} ERROR {e}", flush=True)
        json.dump(out, open(OUT, "w"), indent=1)
        print(f"[{bi+1}/{len(basins)}] {basin} | {(time.time()-t0)/(bi+1):.0f}s/basin", flush=True)
    import statistics as st
    ok = [r for r in out if "error" not in r]
    mu, mf, ml = (st.median([r[f"D_{t}"] for r in ok]) for t in ["untargeted", "flood", "lowflow"])
    print(f"\n=== Exp3 (median over {len(ok)}): untargeted={mu:.4f} flood={mf:.4f} lowflow={ml:.4f} "
          f"| flood/lowflow={mf/max(ml,1e-6):.1f}x ===\nDONE -> {OUT}", flush=True)


if __name__ == "__main__":
    main()

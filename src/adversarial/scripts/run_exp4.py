"""Exp4 causal-trigger: pre-event-only APGD damaging flood-peak predictions.
Reports D_peak (peak-only ΔNSE, operational) and D_overall (share of total vulnerability)
for pre-event windows {1,3,7,14} days. Run (background):
    python src/adversarial/scripts/run_exp4.py --stride 5 --eps 0.1
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
OUT = _root / "results/05_adversarial_robustness/id18_s100/exp4_causal.json"
WINDOWS = [1, 3, 7, 14]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--stride", type=int, default=5)
    ap.add_argument("--eps", type=float, default=0.1)
    ap.add_argument("--apgd-iters", type=int, default=50)
    ap.add_argument("--device", default="cuda:0")
    args = ap.parse_args()
    dev = args.device if torch.cuda.is_available() else "cpu"
    basins = [b.strip() for b in open(BASIN_FILE) if b.strip()][:: args.stride]
    wrapper = CudaLSTMWrapper(run_dir=RUN_DIR, device=dev)
    print(f"Exp4: {len(basins)} basins x pre-windows {WINDOWS} @ eps={args.eps}", flush=True)
    out, t0 = [], time.time()
    for bi, basin in enumerate(basins):
        try:
            x_d, x_s, y_obs = load_basin_data(run_dir=RUN_DIR, basin_id=basin, period="test", device=dev)
            cb = CoherentBasin(wrapper, x_d, x_s, y_obs, dev, chunk=512)
            rec = dict(basin=basin, nse_clean=cb.nse_clean)
            for w in WINDOWS:
                r = cb.apgd_causal(args.eps, pre_window=w, n_iter=args.apgd_iters)
                rec[f"D_peak_{w}"] = r["D_peak"]
                rec[f"D_overall_{w}"] = r["D_overall"]
                rec["n_peaks"] = r["n_peaks"]
            out.append(rec)
            del cb, x_d, x_s, y_obs
            torch.cuda.empty_cache()
        except Exception as e:  # noqa: BLE001
            out.append(dict(basin=basin, error=str(e)))
            print(f"[{bi}] {basin} ERROR {e}", flush=True)
        json.dump(out, open(OUT, "w"), indent=1)
        print(f"[{bi+1}/{len(basins)}] {basin} | {(time.time()-t0)/(bi+1):.0f}s/basin", flush=True)
    import statistics as st
    ok = [r for r in out if "error" not in r and r.get("n_peaks", 0) > 0]
    if ok:
        med = {w: st.median([r[f"D_overall_{w}"] for r in ok]) for w in WINDOWS}
        mp = {w: st.median([r[f"D_peak_{w}"] for r in ok]) for w in WINDOWS}
        print("\n=== Exp4 medians (over %d) ===" % len(ok), flush=True)
        print(" D_overall: " + " ".join(f"{w}d={med[w]:.4f}" for w in WINDOWS), flush=True)
        print(" D_peak:    " + " ".join(f"{w}d={mp[w]:.4f}" for w in WINDOWS), flush=True)
    print(f"DONE -> {OUT}", flush=True)


if __name__ == "__main__":
    main()

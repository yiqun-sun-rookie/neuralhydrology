"""Record statistical-constraint APGD perturbations for structure diagnostics.

This reruns the same constrained attack as run_exp2.py for the 107-basin paper subset
by default, but saves the best perturbation and clean standardized forcing series.

Run:
    python src/adversarial/scripts/run_statistical_structure_probe.py --eps 0.1

Smoke:
    python src/adversarial/scripts/run_statistical_structure_probe.py --eps 0.1 --limit 3
"""
from __future__ import annotations

import argparse
import json
import pickle
import sys
import time
from pathlib import Path

import numpy as np
import torch

_root = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(_root))

from src.adversarial.data_loader import load_basin_data  # noqa: E402
from src.adversarial.model_wrapper import CudaLSTMWrapper  # noqa: E402
from src.adversarial.scripts.coherent_attack import CoherentBasin  # noqa: E402

RUN_DIR = _root / "results/18_lstm_fair_531/lstm_cudalstm_maurer_s100_2026_0616_1513_ep30"
BASIN_FILE = _root / "src/adversarial/data/531_basins.txt"
OUT_DIR = _root / "results/05_adversarial_robustness/id18_s100"


def get_dates(res, basin):
    """Test-period dates for a basin from the official results xarray, as datetime64[D]."""
    try:
        xr = res[basin]["1D"]["xr"]
        for key in ("date", "datetime", "time"):
            if key in xr.coords:
                return np.asarray(xr[key].values, dtype="datetime64[D]")
    except Exception:  # noqa: BLE001
        pass
    return np.array([], dtype="datetime64[D]")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--eps", type=float, default=0.1)
    ap.add_argument("--level", default="statistical", choices=["lp", "physical", "statistical"])
    ap.add_argument("--apgd-iters", type=int, default=50)
    ap.add_argument("--device", default="cuda:0")
    ap.add_argument("--chunk", type=int, default=256)
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--stride", type=int, default=5)
    ap.add_argument("--offset", type=int, default=0)
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--basins", default="", help="Comma-separated basin IDs. Overrides stride/limit when set.")
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()

    dev = args.device if torch.cuda.is_available() else "cpu"
    rec_dir = OUT_DIR / f"{args.level}_constraint_records_eps{args.eps:g}"
    rec_dir.mkdir(parents=True, exist_ok=True)
    summary_file = OUT_DIR / f"{args.level}_structure_probe_eps{args.eps:g}.json"

    if args.basins:
        basins = [b.strip().zfill(8) for b in args.basins.split(",") if b.strip()]
    else:
        basins = [b.strip() for b in open(BASIN_FILE) if b.strip()]
        basins = basins[args.offset::args.stride]
        if args.limit > 0:
            basins = basins[:args.limit]

    with open(RUN_DIR / "test/model_epoch030/test_results.p", "rb") as f:
        res = pickle.load(f)

    wrapper = CudaLSTMWrapper(run_dir=RUN_DIR, device=dev)
    summary = json.load(open(summary_file)) if summary_file.exists() and not args.force else {}

    t_start, done = time.time(), 0
    for idx, basin in enumerate(basins):
        rec_path = rec_dir / f"{basin}.npz"
        if rec_path.exists() and basin in summary and not args.force:
            continue
        try:
            x_d, x_s, y_obs = load_basin_data(run_dir=RUN_DIR, basin_id=basin, period="test", device=dev)
            cb = CoherentBasin(wrapper, x_d, x_s, y_obs, dev, chunk=args.chunk)
            record = cb.apgd_c_record(args.eps, args.level, n_iter=args.apgd_iters, seed=args.seed)
            dates = get_dates(res, basin)
            np.savez_compressed(
                rec_path,
                clean_cal=record["clean_cal"],
                delta=record["delta"],
                dates=dates,
                feat=np.array(record["feat"]),
                D_nse=record["D_nse"],
                nse_clean=record["nse_clean"],
                nse_adv=record["nse_adv"],
            )
            summary[basin] = dict(
                D_nse=record["D_nse"],
                nse_clean=record["nse_clean"],
                nse_adv=record["nse_adv"],
                n_cal=int(record["delta"].shape[0]),
                n_feat=int(record["delta"].shape[1]),
                has_dates=bool(dates.size),
            )
            done += 1
            del cb, x_d, x_s, y_obs, record
            torch.cuda.empty_cache()
        except Exception as exc:  # noqa: BLE001
            summary[basin] = dict(error=str(exc))
            print(f"[{idx + 1}/{len(basins)}] {basin} ERROR {exc}", flush=True)
            continue

        json.dump(summary, open(summary_file, "w"), indent=1)
        elapsed = time.time() - t_start
        print(
            f"[{idx + 1}/{len(basins)}] {basin} | D={summary[basin]['D_nse']:.4f} "
            f"| {elapsed / max(done, 1):.1f}s/basin | ETA "
            f"{(len(basins) - idx - 1) * elapsed / max(done, 1) / 3600:.2f}h",
            flush=True,
        )

    json.dump(summary, open(summary_file, "w"), indent=1)
    print(f"DONE {len(summary)}/{len(basins)} -> {summary_file}", flush=True)


if __name__ == "__main__":
    main()

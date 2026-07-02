"""L1+L2 instrumented re-run: untargeted APGD at one eps on all 531 basins, RECORDING
the best perturbation + denormalized daily hydrographs (no change to the attack).

Feeds two analyses (post-hoc, separate scripts):
  L1 process attribution  -> which forcing channel the attack spends its budget on,
                             by regime (temp in snow basins? precip in rain basins?)
  L2 hydrological outcome  -> peak timing/magnitude, seasonal water balance, mass-balance
                             violation (adversarial runoff coeff > 1 vs clean baseline).

Per-basin .npz (resumable) in l1l2_records/ + an incremental summary json with the
per-variable perturbation-energy fractions (the L1 headline).

Run (background):
    python src/adversarial/scripts/run_exp_l1l2.py --eps 0.1
Resume after a crash: just re-run the same command (done basins are skipped).
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

from src.adversarial.model_wrapper import CudaLSTMWrapper  # noqa: E402
from src.adversarial.data_loader import load_basin_data  # noqa: E402
from src.adversarial.scripts.coherent_attack import CoherentBasin, TEMP_IDX  # noqa: E402

RUN_DIR = _root / "results/18_lstm_fair_531/lstm_cudalstm_maurer_s100_2026_0616_1513_ep30"
BASIN_FILE = _root / "src/adversarial/data/531_basins.txt"
OUT_DIR = _root / "results/05_adversarial_robustness/id18_s100"
REC_DIR = OUT_DIR / "l1l2_records"


def get_dates(res, basin):
    """Test-period dates for a basin from the official results xarray, as datetime64[D]."""
    try:
        xr = res[basin]["1D"]["xr"]
        for k in ("date", "datetime", "time"):
            if k in xr.coords:
                return np.asarray(xr[k].values, dtype="datetime64[D]")
    except Exception:  # noqa: BLE001
        pass
    return None


# (per-variable ENERGY fractions were dropped: an L-inf attack saturates every channel to
#  +/-eps, so energy is ~uniform and uninformative. L1 attribution uses the leave-one-out
#  damage drop computed inside CoherentBasin.apgd_record instead.)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--eps", type=float, default=0.1)
    ap.add_argument("--apgd-iters", type=int, default=50)
    ap.add_argument("--device", default="cuda:0")
    ap.add_argument("--chunk", type=int, default=256)   # smaller than exp1 (extra tensors held)
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--stride", type=int, default=5)    # 5 => 107-basin subset (paper convention)
    ap.add_argument("--limit", type=int, default=0)     # >0 = smoke test on first N of the subset
    args = ap.parse_args()

    dev = args.device if torch.cuda.is_available() else "cpu"
    REC_DIR.mkdir(parents=True, exist_ok=True)
    summary_file = OUT_DIR / f"exp_l1l2_summary_eps{args.eps}.json"

    basins = [b.strip() for b in open(BASIN_FILE) if b.strip()]
    basins = basins[::args.stride]                      # 107-basin subset (every 5th), paper convention
    if args.limit > 0:
        basins = basins[:args.limit]
    with open(RUN_DIR / "test/model_epoch030/test_results.p", "rb") as f:
        res = pickle.load(f)

    wrapper = CudaLSTMWrapper(run_dir=RUN_DIR, device=dev)
    summary = json.load(open(summary_file)) if summary_file.exists() else {}

    t_start, done = time.time(), 0
    for idx, basin in enumerate(basins):
        rec_path = REC_DIR / f"{basin}.npz"
        if rec_path.exists() and basin in summary:
            continue
        try:
            x_d, x_s, y_obs = load_basin_data(run_dir=RUN_DIR, basin_id=basin, period="test", device=dev)
            cb = CoherentBasin(wrapper, x_d, x_s, y_obs, dev, chunk=args.chunk)
            r = cb.apgd_record(args.eps, n_iter=args.apgd_iters, seed=args.seed)

            dates = get_dates(res, basin)
            N = r["q_obs"].shape[0]
            if dates is not None and len(dates) != N:
                L = min(len(dates), N)                 # align at the (shared) test-period end
                dates = dates[-L:]
                for k in ("q_obs", "q_clean", "q_adv", "p_clean", "mask"):
                    r[k] = r[k][-L:]
            np.savez_compressed(
                rec_path, delta=r["delta"], q_obs=r["q_obs"], q_clean=r["q_clean"],
                q_adv=r["q_adv"], p_clean=r["p_clean"], mask=r["mask"],
                dates=(dates if dates is not None else np.array([])),
                feat=np.array(r["feat"]),
                D_nse=r["D_nse"], nse_clean=r["nse_clean"], nse_adv=r["nse_adv"])

            att = r["attrib"]
            summary[basin] = dict(D_nse=r["D_nse"], nse_clean=r["nse_clean"],
                                  n_days=int(N), has_dates=bool(dates is not None),
                                  precip_att=att["precip"], temp_att=att["temp"],
                                  srad_att=att["srad"], vp_att=att["vp"])
            done += 1
            del cb, x_d, x_s, y_obs, r
            torch.cuda.empty_cache()
        except Exception as e:  # noqa: BLE001
            print(f"[{idx}] {basin} ERROR: {e}", flush=True)
            continue

        json.dump(summary, open(summary_file, "w"), indent=1)
        el = time.time() - t_start
        s = summary[basin]
        tot = (s['precip_att'] + s['temp_att'] + s['srad_att'] + s['vp_att']) or 1.0
        print(f"[{idx+1}/{len(basins)}] {basin} | D={s['D_nse']:.3f} "
              f"temp_share={s['temp_att']/tot:.2f} precip_share={s['precip_att']/tot:.2f} "
              f"| {el/max(done,1):.1f}s/basin | ETA {(len(basins)-idx-1)*el/max(done,1)/3600:.2f}h", flush=True)

    json.dump(summary, open(summary_file, "w"), indent=1)
    print(f"DONE {len(summary)}/{len(basins)} -> {summary_file}", flush=True)


if __name__ == "__main__":
    main()

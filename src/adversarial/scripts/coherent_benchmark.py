"""Single-basin coherent last-step NSE benchmark (Plan v4, experiment phase step 1).

Validates F2's core claim: reconstructing per-basin test-period NSE from the
last step (predict_last_n=1) of every stride-1 window, concatenated, reproduces
the official RegressionTester per-basin NSE stored in test_results.p. Also times
the clean forward pass per basin to calibrate the F2b wall-clock contingency.

This is a no-attack validation: only the metric-correction (F2 eval prong) is
exercised here. cuDNN stays enabled (no grad), so this is the cheap regime.

Run:
    python src/adversarial/scripts/coherent_benchmark.py --basin 01022500
"""
from __future__ import annotations

import argparse
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

RUN_DIR = _root / "results/18_lstm_fair_531/lstm_cudalstm_maurer_s100_2026_0616_1513_ep30"


def coherent_last_step_nse(wrapper, x_d, x_s, y_obs, chunk=512):
    """Forward all windows in chunks, take last step, concat, compute NSE (normalized space)."""
    n = x_d.shape[0]
    preds_last = []
    with torch.no_grad():
        for i in range(0, n, chunk):
            y_hat = wrapper.forward(x_d[i:i + chunk], x_s[i:i + chunk])  # [b,270,1]
            preds_last.append(y_hat[:, -1, 0].detach().cpu())
    y_pred = torch.cat(preds_last)                      # [n]
    y_true = y_obs[:, -1, 0].detach().cpu()             # [n]
    mask = ~torch.isnan(y_true) & ~torch.isnan(y_pred)
    yt, yp = y_true[mask], y_pred[mask]
    ss_res = ((yt - yp) ** 2).sum()
    ss_tot = ((yt - yt.mean()) ** 2).sum()
    nse = 1.0 - ss_res / ss_tot
    return float(nse), int(mask.sum()), int(n)


def official_nse(basin):
    p = RUN_DIR / "test/model_epoch030/test_results.p"
    with open(p, "rb") as f:
        res = pickle.load(f)
    return float(res[basin]["1D"]["NSE"])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--basin", default="01022500")
    ap.add_argument("--device", default="cuda:0")
    ap.add_argument("--chunk", type=int, default=512)
    args = ap.parse_args()

    dev = args.device if torch.cuda.is_available() else "cpu"
    print(f"device={dev} (cuda_available={torch.cuda.is_available()})")

    t0 = time.time()
    wrapper = CudaLSTMWrapper(run_dir=RUN_DIR, device=dev)
    print(f"loaded victim in {time.time()-t0:.1f}s | weight={wrapper.weight_file.name} "
          f"| n_dynamic={wrapper.n_dynamic} n_static={wrapper.n_static} "
          f"| dyn={wrapper.dynamic_features}")

    t1 = time.time()
    x_d, x_s, y_obs = load_basin_data(run_dir=RUN_DIR, basin_id=args.basin,
                                      period="test", device=dev)
    print(f"loaded basin {args.basin} in {time.time()-t1:.1f}s | x_d={tuple(x_d.shape)} "
          f"x_s={tuple(x_s.shape)} y_obs={tuple(y_obs.shape)}")

    t2 = time.time()
    nse, n_valid, n_win = coherent_last_step_nse(wrapper, x_d, x_s, y_obs, chunk=args.chunk)
    dt = time.time() - t2

    off = official_nse(args.basin)
    print(f"\n=== {args.basin} ===")
    print(f"  windows={n_win}  valid_last_step={n_valid}")
    print(f"  coherent_nse_clean = {nse:.6f}")
    print(f"  official  [1D][NSE] = {off:.6f}")
    print(f"  |diff| = {abs(nse-off):.2e}  -> {'PASS' if abs(nse-off) < 1e-3 else 'FAIL'}")
    print(f"  clean forward time = {dt:.2f}s for {n_win} windows "
          f"({1000*dt/n_win:.2f} ms/window, chunk={args.chunk})")


if __name__ == "__main__":
    main()

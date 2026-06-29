"""Coherent attack smoke (Plan v4, experiment iteration 1).

Runs the coherent driver on a few basins at one eps and reports per-basin
nse_clean (must match official) + damage D = NSE_clean - NSE_adv for each
attack, plus wall-clock to calibrate F2b. This is the first real experiment
iteration; results are audited before scaling to Exp1 (531 basins).

Run:
    python src/adversarial/scripts/run_coherent_smoke.py --n-basins 3 --eps 0.1 --apgd-iters 20
"""
from __future__ import annotations

import argparse
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


def official_nse(basin):
    with open(RUN_DIR / "test/model_epoch030/test_results.p", "rb") as f:
        res = pickle.load(f)
    return float(res[basin]["1D"]["NSE"])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--n-basins", type=int, default=3)
    ap.add_argument("--eps", type=float, default=0.1)
    ap.add_argument("--apgd-iters", type=int, default=20)
    ap.add_argument("--device", default="cuda:0")
    ap.add_argument("--chunk", type=int, default=512)
    args = ap.parse_args()

    dev = args.device if torch.cuda.is_available() else "cpu"
    basins = [b.strip() for b in open(BASIN_FILE) if b.strip()][: args.n_basins]
    print(f"device={dev} | eps={args.eps} | apgd_iters={args.apgd_iters} | basins={basins}")

    wrapper = CudaLSTMWrapper(run_dir=RUN_DIR, device=dev)
    gen = torch.Generator(device=dev).manual_seed(42)

    rows = []
    for basin in basins:
        x_d, x_s, y_obs = load_basin_data(run_dir=RUN_DIR, basin_id=basin, period="test", device=dev)
        cb = CoherentBasin(wrapper, x_d, x_s, y_obs, dev, chunk=args.chunk)
        off = official_nse(basin)
        ok = abs(cb.nse_clean - off) < 1e-3
        print(f"\n=== {basin} | nse_clean={cb.nse_clean:.6f} official={off:.6f} "
              f"{'PASS' if ok else 'FAIL'} | N={cb.N} T_cal={cb.T_cal} ===")

        t = time.time(); d_fgsm = cb.fgsm(args.eps); t_fgsm = time.time() - t
        t = time.time(); d_apgd = cb.apgd(args.eps, n_iter=args.apgd_iters); t_apgd = time.time() - t
        t = time.time(); d_rs1 = cb.random_sign(args.eps, 1, gen); t_rs1 = time.time() - t
        t = time.time(); d_rs100 = cb.random_sign(args.eps, 100, gen); t_rs100 = time.time() - t
        t = time.time(); d_gauss = cb.gaussian(args.eps, 100, gen); t_gauss = time.time() - t

        print(f"  D_FGSM        = {d_fgsm:.4f}  ({t_fgsm:.1f}s)")
        print(f"  D_APGD({args.apgd_iters})    = {d_apgd:.4f}  ({t_apgd:.1f}s)  -> {t_apgd/max(args.apgd_iters,1):.2f}s/iter")
        print(f"  D_randsign_K1 = {d_rs1:.4f}  ({t_rs1:.1f}s)")
        print(f"  D_randsign_K100= {d_rs100:.4f} ({t_rs100:.1f}s)")
        print(f"  D_gauss_K100  = {d_gauss:.4f}  ({t_gauss:.1f}s)")
        rows.append(dict(basin=basin, nse_clean=cb.nse_clean, official=off,
                         D_FGSM=d_fgsm, D_APGD=d_apgd, D_rs1=d_rs1, D_rs100=d_rs100, D_gauss=d_gauss))

    print("\n=== SMOKE SUMMARY ===")
    import statistics as st
    for k in ["D_FGSM", "D_APGD", "D_rs1", "D_rs100", "D_gauss"]:
        vals = [r[k] for r in rows]
        print(f"  median {k:12s} = {st.median(vals):+.4f}   (per-basin: {[round(v,3) for v in vals]})")
    print("  gate preview: APGD vs random_sign(K=100), FGSM vs random_sign(K=1)")
    print(f"    median D_APGD - D_rs100 = {st.median([r['D_APGD']-r['D_rs100'] for r in rows]):+.4f}")
    print(f"    median D_FGSM - D_rs1   = {st.median([r['D_FGSM']-r['D_rs1'] for r in rows]):+.4f}")


if __name__ == "__main__":
    main()

"""Exact-moment comparison probe for the statistical-constraint claim.

This is a diagnostic counterfactual, not a replacement for Exp2. It runs APGD with a
projection that ends by exactly matching each feature's whole-period mean and standard
deviation to the clean forcing. Because that final exact moment step can move points
outside the epsilon or physical bounds, the script audits those violations explicitly.

Run on the already recorded 13-basin probe set:
    python src/adversarial/scripts/run_exact_moment_probe.py --from-records
"""
from __future__ import annotations

import argparse
import json
import pickle
import sys
import time
from pathlib import Path

import numpy as np
import pandas as pd
import torch

_root = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(_root))

from src.adversarial.constraints.physical import _PHYSICAL_BOUNDS_CF  # noqa: E402
from src.adversarial.data_loader import load_basin_data  # noqa: E402
from src.adversarial.model_wrapper import CudaLSTMWrapper  # noqa: E402
from src.adversarial.scripts.coherent_attack import CoherentBasin, _tie_copy, _tie_grad  # noqa: E402

RUN_DIR = _root / "results/18_lstm_fair_531/lstm_cudalstm_maurer_s100_2026_0616_1513_ep30"
BASIN_FILE = _root / "src/adversarial/data/531_basins.txt"
OUT_DIR = _root / "results/05_adversarial_robustness/id18_s100"


def exact_moment_project(cb: CoherentBasin, delta: torch.Tensor, eps: float) -> torch.Tensor:
    """Apply physical/Linf projection, then force exact whole-period mean/std matching.

    The final moment step is exact for mean/std but may relax the epsilon/physical bounds.
    Those relaxations are measured by audit_delta().
    """
    physical = cb._constraint("physical", eps)
    delta = cb._proj_c(_tie_copy(delta), physical)
    adv = cb.clean_cal + delta
    channels = []
    for f in range(adv.shape[-1]):
        orig = cb.clean_cal[:, f]
        cur = adv[:, f]
        cur_std = cur.std(unbiased=True).clamp(min=1e-8)
        matched = (cur - cur.mean()) / cur_std * orig.std(unbiased=True) + orig.mean()
        channels.append(matched[:, None])
    out = torch.cat(channels, dim=-1)
    return _tie_copy(out - cb.clean_cal)


def audit_delta(cb: CoherentBasin, delta: torch.Tensor, eps: float) -> dict:
    clean = cb.clean_cal.detach()
    adv = clean + delta.detach()
    mean_shift = (adv.mean(dim=0) - clean.mean(dim=0)).abs()
    std_rel = ((adv.std(dim=0, unbiased=True) - clean.std(dim=0, unbiased=True)) /
               clean.std(dim=0, unbiased=True).clamp(min=1e-12)).abs()
    abs_delta = delta.detach().abs()
    eps_excess = (abs_delta - eps).clamp(min=0)

    real = adv * cb.scale + cb.center
    physical_excess = []
    physical_frac = []
    for i, feat in enumerate(cb.feat):
        bounds = _PHYSICAL_BOUNDS_CF.get(feat.casefold())
        if bounds is None:
            physical_excess.append(0.0)
            physical_frac.append(0.0)
            continue
        lo, hi = bounds
        low = (lo - real[:, i]).clamp(min=0)
        high = (real[:, i] - hi).clamp(min=0)
        v = torch.maximum(low, high)
        physical_excess.append(float(v.max()))
        physical_frac.append(float((v > 0).float().mean()))

    return {
        "whole_mean_abs_max": float(mean_shift.max()),
        "whole_std_rel_max": float(std_rel.max()),
        "max_abs_delta": float(abs_delta.max()),
        "eps_excess_max": float(eps_excess.max()),
        "eps_excess_frac": float((eps_excess > 1e-7).float().mean()),
        "physical_excess_max": float(max(physical_excess)),
        "physical_excess_frac_max": float(max(physical_frac)),
    }


def run_one(wrapper, basin: str, args, exp2: dict) -> dict:
    dev = args.device if torch.cuda.is_available() else "cpu"
    x_d, x_s, y_obs = load_basin_data(run_dir=RUN_DIR, basin_id=basin, period="test", device=dev)
    cb = CoherentBasin(wrapper, x_d, x_s, y_obs, dev, chunk=args.chunk)
    g0 = torch.Generator(device=dev).manual_seed(args.seed)
    init = torch.empty(cb.T_cal, cb.F, device=dev).uniform_(-args.eps, args.eps, generator=g0)
    delta = exact_moment_project(cb, init, args.eps)
    best, best_delta = cb.nse(delta), delta
    alpha = 2 * args.eps
    for t in range(args.apgd_iters):
        g = _tie_grad(cb.grad(delta))
        delta = exact_moment_project(cb, delta + alpha * g.sign(), args.eps)
        cur = cb.nse(delta)
        if cur < best:
            best, best_delta = cur, delta
        if t in (int(args.apgd_iters * 0.22), int(args.apgd_iters * 0.5), int(args.apgd_iters * 0.75)):
            alpha *= 0.5
    out = {
        "basin": basin,
        "D_exact_moment": cb.nse_clean - best,
        "nse_clean": cb.nse_clean,
        "nse_adv": best,
        "D_lp_exp2": exp2.get(basin, {}).get("lp", np.nan),
        "D_stat_exp2": exp2.get(basin, {}).get("statistical", np.nan),
    }
    out.update(audit_delta(cb, best_delta, args.eps))
    del cb, x_d, x_s, y_obs
    torch.cuda.empty_cache()
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--eps", type=float, default=0.1)
    ap.add_argument("--apgd-iters", type=int, default=50)
    ap.add_argument("--device", default="cuda:0")
    ap.add_argument("--chunk", type=int, default=256)
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--stride", type=int, default=5)
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--basins", default="")
    ap.add_argument("--from-records", action="store_true")
    ap.add_argument("--n-chunks", type=int, default=1, help="Split --from-records basins into N chunks (1 = no split).")
    ap.add_argument("--offset", type=int, default=0, help="Which chunk to run when --n-chunks > 1.")
    args = ap.parse_args()

    if args.from_records:
        rec_dir = OUT_DIR / f"statistical_constraint_records_eps{args.eps:g}"
        basins = sorted(p.stem for p in rec_dir.glob("*.npz"))
        if args.n_chunks > 1:
            basins = basins[args.offset::args.n_chunks]
    elif args.basins:
        basins = [b.strip().zfill(8) for b in args.basins.split(",") if b.strip()]
    else:
        basins = [b.strip() for b in open(BASIN_FILE) if b.strip()][::args.stride]
        if args.limit > 0:
            basins = basins[:args.limit]

    exp2 = {}
    exp2_path = OUT_DIR / "exp2_constraint_ablation.json"
    if exp2_path.exists():
        for row in json.load(open(exp2_path)):
            exp2[row["basin"]] = {
                "lp": float(row[f"D_lp_{args.eps:g}"]),
                "statistical": float(row[f"D_statistical_{args.eps:g}"]),
            }

    dev = args.device if torch.cuda.is_available() else "cpu"
    with open(RUN_DIR / "test/model_epoch030/test_results.p", "rb"):
        pass
    wrapper = CudaLSTMWrapper(run_dir=RUN_DIR, device=dev)

    rows = []
    t0 = time.time()
    for i, basin in enumerate(basins):
        try:
            row = run_one(wrapper, basin, args, exp2)
            rows.append(row)
            print(
                f"[{i + 1}/{len(basins)}] {basin} | D_exact={row['D_exact_moment']:.4f} "
                f"| eps_excess={row['eps_excess_max']:.4g} | phys_excess={row['physical_excess_max']:.4g}",
                flush=True,
            )
        except Exception as exc:  # noqa: BLE001
            rows.append({"basin": basin, "error": str(exc)})
            print(f"[{i + 1}/{len(basins)}] {basin} ERROR {exc}", flush=True)
        elapsed = time.time() - t0
        print(f"  avg {elapsed / (i + 1):.1f}s/basin | ETA {(len(basins) - i - 1) * elapsed / (i + 1) / 3600:.2f}h",
              flush=True)

    df = pd.DataFrame(rows)
    part = f"_part{args.offset}of{args.n_chunks}" if args.n_chunks > 1 else ""
    out_csv = OUT_DIR / f"exact_moment_probe_eps{args.eps:g}{part}.csv"
    out_json = OUT_DIR / f"exact_moment_probe_eps{args.eps:g}{part}.json"
    df.to_csv(out_csv, index=False)
    json.dump(rows, open(out_json, "w"), indent=1)

    ok = df[df.get("error").isna()] if "error" in df else df
    print(f"\nDONE {len(ok)}/{len(df)} -> {out_csv}")
    if len(ok):
        print(f"median D_exact={ok.D_exact_moment.median():.4f}")
        print(f"median D_stat_exp2={ok.D_stat_exp2.median():.4f}")
        print(f"median D_lp_exp2={ok.D_lp_exp2.median():.4f}")
        print(f"median exact/stat={float((ok.D_exact_moment / ok.D_stat_exp2).median()):.3f}")
        print(f"median exact/lp={float((ok.D_exact_moment / ok.D_lp_exp2).median()):.3f}")
        print(f"max whole mean shift={ok.whole_mean_abs_max.max():.3e}")
        print(f"max whole std rel shift={ok.whole_std_rel_max.max():.3e}")
        print(f"median eps excess max={ok.eps_excess_max.median():.4g}; max={ok.eps_excess_max.max():.4g}")
        print(f"median eps excess frac={ok.eps_excess_frac.median():.4g}")
        print(f"max physical excess={ok.physical_excess_max.max():.4g}")


if __name__ == "__main__":
    main()

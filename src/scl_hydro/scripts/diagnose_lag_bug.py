"""Lag bug diagnostic: NumPy vs PyTorch HBV-lite implementation discrepancy.

Re-calibrates a random sample of basins with the NumPy lag (matching the
9-way ensemble protocol), then evaluates the same calibrated parameters
with BOTH NumPy and PyTorch lag implementations on the test period.

Outputs in ``--output-dir``:

    per_basin_diag.csv   per-basin metrics (NSE_np, NSE_pt, dNSE, |dQraw|, ...)
    summary.csv          aggregated stats (median, P5, P95)
    lag_time_hist.png    distribution of calibrated lag_time over the sample
    hydrograph.png       hydrograph for the basin with the largest lag_time
    verdict.txt          SAFE / MILD / SEVERE decision + numerical evidence
    verdict.json         machine-readable verdict + config metadata

Usage::

    python -X utf8 -m scl_hydro.scripts.diagnose_lag_bug --limit 20 --workers 6

Defaults match the ``v7_PT_tight`` variant of the 9-way ensemble
(HBV_BOUNDS=v1, PT PET, init=0.5+/-0.3, NSE loss).
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
from concurrent.futures import ProcessPoolExecutor, as_completed
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd

_HERE = Path(__file__).resolve()
_REPO_ROOT = _HERE.parents[3]
for _p in (_REPO_ROOT / "src", _REPO_ROOT):
    if str(_p) not in sys.path:
        sys.path.insert(0, str(_p))


# ---------------------------------------------------------------------------
# Forward implementations (NumPy + PyTorch) returning (q_sim, q_raw)
# ---------------------------------------------------------------------------

def _pt_simulate(params: dict, rain, pet, temp, init_state: dict):
    """PyTorch HBV-lite forward; returns (q_sim, q_raw) as float64 numpy."""
    import torch

    from scl_hydro.hbv_lite import DifferentiableHBVLite, PARAM_NAMES

    model = DifferentiableHBVLite()
    forcing = torch.tensor(
        np.stack([rain, pet, temp], axis=-1),
        dtype=torch.float32,
    ).unsqueeze(0)
    params_t = {
        k: torch.tensor([[float(params[k])]], dtype=torch.float32)
        for k in PARAM_NAMES
    }
    state_init = torch.tensor([[
        float(init_state["SNOWPACK"]),
        float(init_state["MELTWATER"]),
        float(init_state["SM"]),
        float(init_state["SUZ"]),
        float(init_state["SLZ"]),
    ]], dtype=torch.float32)
    with torch.no_grad():
        q_sim, q_raw, _ = model(forcing, params_t, state_init=state_init)
    return (
        q_sim.squeeze().cpu().numpy().astype(np.float64),
        q_raw.squeeze().cpu().numpy().astype(np.float64),
    )


def _np_simulate_with_qraw(params: dict, rain, pet, temp, init_state: dict):
    """NumPy HBV-lite forward via inner-loop access; returns (q_sim, q_raw)."""
    from scl_hydro.hbv_lite_numpy import _half_triangular_lag, _simulate_loop

    q_raw, *_ = _simulate_loop(
        rain, pet, temp,
        float(init_state["SNOWPACK"]), float(init_state["MELTWATER"]),
        float(init_state["SM"]), float(init_state["SUZ"]), float(init_state["SLZ"]),
        float(params["parTT"]), float(params["parCFMAX"]),
        float(params["parCFR"]), float(params["parCWH"]),
        float(params["parFC"]), float(params["parBETA"]), float(params["parLP"]),
        float(params["parK0"]), float(params["parK1"]),
        float(params["parUZL"]), float(params["parPERC"]),
        float(params["parK2"]),
    )
    q_sim = _half_triangular_lag(q_raw, float(params["lag_time"]))
    q_sim = np.maximum(q_sim, 0.0)
    return q_sim, q_raw


def _nse(obs, sim) -> float:
    mask = np.isfinite(obs) & np.isfinite(sim)
    if mask.sum() < 10:
        return float("nan")
    o, s = obs[mask], sim[mask]
    denom = np.sum((o - o.mean()) ** 2)
    if denom <= 0:
        return float("nan")
    return float(1.0 - np.sum((s - o) ** 2) / denom)


# ---------------------------------------------------------------------------
# Worker: calibrate (NumPy) + dual-evaluate (NumPy & PyTorch) on one basin
# ---------------------------------------------------------------------------

def diagnose_one_basin(args_tuple) -> dict:
    (basin_id, data_root, forcing_name, pet_method, cal_period, eval_period,
     n_trials, n_restarts, init_mean, init_sigma, bounds_preset) = args_tuple

    # Must set BEFORE first scl_hydro import: hbv_lite_numpy reads at module load.
    os.environ["HBV_BOUNDS"] = bounds_preset
    os.environ.setdefault("OMP_NUM_THREADS", "1")
    os.environ.setdefault("MKL_NUM_THREADS", "1")
    os.environ.setdefault("OPENBLAS_NUM_THREADS", "1")

    if str(_REPO_ROOT / "src") not in sys.path:
        sys.path.insert(0, str(_REPO_ROOT / "src"))

    from hydroagent.data_loading import load_camels_basin
    from scl_hydro.hbv_lite_cma_calibrate import calibrate_hbv_lite_cma

    t0 = time.time()
    try:
        f_cal, o_cal, _ = load_camels_basin(
            basin_id, data_root=data_root,
            start_date=cal_period[0], end_date=cal_period[1],
            forcing=forcing_name, pet_method=pet_method,
        )
        rain_cal = f_cal["prcp"].values.astype(np.float64)
        pet_col = "ep" if "ep" in f_cal.columns else "pet"
        pet_cal = f_cal[pet_col].values.astype(np.float64)
        temp_cal = f_cal["tmean"].values.astype(np.float64)
        obs_cal = o_cal.values.astype(np.float64)

        cal_result = calibrate_hbv_lite_cma(
            rain_cal, pet_cal, temp_cal, obs_cal,
            n_trials=n_trials, n_restarts=n_restarts,
            loss="nse",
            init_mean_norm=init_mean, init_sigma=init_sigma,
        )
        params = cal_result["optimized_params"]
        init_state = cal_result["final_state"]

        f_ev, o_ev, _ = load_camels_basin(
            basin_id, data_root=data_root,
            start_date=eval_period[0], end_date=eval_period[1],
            forcing=forcing_name, pet_method=pet_method,
        )
        rain_ev = f_ev["prcp"].values.astype(np.float64)
        pet_ev = f_ev[pet_col].values.astype(np.float64)
        temp_ev = f_ev["tmean"].values.astype(np.float64)
        obs_ev = o_ev.values.astype(np.float64)

        q_np, q_raw_np = _np_simulate_with_qraw(params, rain_ev, pet_ev, temp_ev, init_state)
        q_pt, q_raw_pt = _pt_simulate(params, rain_ev, pet_ev, temp_ev, init_state)

        nse_np = _nse(obs_ev, q_np)
        nse_pt = _nse(obs_ev, q_pt)
        d_qraw = np.abs(q_raw_np - q_raw_pt)
        d_qsim = np.abs(q_np - q_pt)

        out: dict[str, Any] = {
            "basin_id": basin_id,
            "status": "success",
            "elapsed_s": round(time.time() - t0, 1),
            "lag_time": float(params["lag_time"]),
            "n_lag": max(int(np.ceil(float(params["lag_time"]))), 1),
            "cal_nse": float(cal_result["nse"]),
            "nse_np": nse_np,
            "nse_pt": nse_pt,
            "dnse": nse_pt - nse_np,
            "max_abs_qraw_diff": float(d_qraw.max()),
            "median_abs_qraw_diff": float(np.median(d_qraw)),
            "max_abs_qsim_diff": float(d_qsim.max()),
            "median_abs_qsim_diff": float(np.median(d_qsim)),
            "p95_abs_qsim_diff": float(np.quantile(d_qsim, 0.95)),
            "obs_mean": float(np.nanmean(obs_ev)),
        }
        for k, v in params.items():
            out[f"p_{k}"] = float(v)
        out["_dates"] = pd.to_datetime(f_ev.index).strftime("%Y-%m-%d").tolist()
        out["_q_np"] = q_np.tolist()
        out["_q_pt"] = q_pt.tolist()
        out["_obs"] = obs_ev.tolist()
        return out
    except Exception as exc:  # noqa: BLE001
        return {
            "basin_id": basin_id,
            "status": "failed",
            "elapsed_s": round(time.time() - t0, 1),
            "error": f"{type(exc).__name__}: {exc}",
        }


# ---------------------------------------------------------------------------
# Verdict logic + plots
# ---------------------------------------------------------------------------

def make_verdict(df: pd.DataFrame) -> dict:
    ok = df[df["status"] == "success"].copy()
    if len(ok) == 0:
        return {"verdict": "INDETERMINATE", "reason": "No successful diagnoses."}

    qraw_diff_med = float(ok["median_abs_qraw_diff"].median())
    base = {
        "qraw_diff_median": qraw_diff_med,
        "lag_t_median": float(ok["lag_time"].median()),
        "lag_t_p95": float(ok["lag_time"].quantile(0.95)),
        "dnse_median": float(ok["dnse"].median()),
        "dnse_p5": float(ok["dnse"].quantile(0.05)),
        "n_basins": int(len(ok)),
        "n_severe": int((ok["dnse"] < -0.02).sum()),
    }

    if qraw_diff_med > 1e-3:
        base["verdict"] = "FATAL"
        base["reason"] = (
            f"Inner HBV loop differs (median |dQraw| = {qraw_diff_med:.2e}). "
            f"Fix inner-loop discrepancy BEFORE characterizing lag bug."
        )
        return base

    dnse_med = base["dnse_median"]
    dnse_p5 = base["dnse_p5"]
    if dnse_p5 > -0.005 and abs(dnse_med) < 0.002:
        base["verdict"] = "SAFE"
        base["reason"] = (
            f"Two implementations effectively equivalent under calibrated params "
            f"(dNSE median {dnse_med:+.4f}, P5 {dnse_p5:+.4f}). "
            f"CMA-ES presumably drives lag_time to the lower bound. "
            f"Recommend: pick canonical (either), document equivalence, no re-run."
        )
    elif dnse_p5 > -0.02:
        base["verdict"] = "MILD"
        base["reason"] = (
            f"Limited impact: {base['n_severe']}/{base['n_basins']} basins "
            f"lose >0.02 NSE (dNSE median {dnse_med:+.4f}, P5 {dnse_p5:+.4f}; "
            f"lag_time median {base['lag_t_median']:.2f}, P95 {base['lag_t_p95']:.2f}). "
            f"Recommend: keep NumPy canonical (zero cost), document discrepancy, "
            f"OR re-calibrate lag_time only (~1.5h)."
        )
    else:
        base["verdict"] = "SEVERE"
        base["reason"] = (
            f"Significant impact: {base['n_severe']}/{base['n_basins']} basins "
            f"lose >0.02 NSE (dNSE median {dnse_med:+.4f}, P5 {dnse_p5:+.4f}; "
            f"lag_time median {base['lag_t_median']:.2f}, P95 {base['lag_t_p95']:.2f}). "
            f"Recommend: pick canonical AND re-calibrate at least "
            f"lag_time + K0/K1/K2 (~1.5h on 6 workers)."
        )
    return base


def make_plots(df: pd.DataFrame, output_dir: Path) -> None:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    ok = df[df["status"] == "success"].copy().reset_index(drop=True)
    if len(ok) == 0:
        return

    fig, ax = plt.subplots(figsize=(6, 4))
    ax.hist(ok["lag_time"], bins=20, edgecolor="black", color="C0", alpha=0.85)
    ax.axvline(1.0, color="red", linestyle="--", linewidth=1,
               label="lag=1 -> bug invisible (n=1 reduces both impls to identity)")
    ax.set_xlabel("Calibrated lag_time [days]")
    ax.set_ylabel("Number of basins")
    ax.set_title(f"Calibrated lag_time distribution (n={len(ok)})")
    ax.legend(fontsize=8)
    fig.tight_layout()
    fig.savefig(output_dir / "lag_time_hist.png", dpi=120)
    plt.close(fig)

    idx = int(ok["lag_time"].idxmax())
    row = ok.iloc[idx]
    q_np = np.array(row["_q_np"])
    q_pt = np.array(row["_q_pt"])
    obs = np.array(row["_obs"])
    dates = pd.to_datetime(row["_dates"])

    if len(obs) > 120:
        rolling_std = pd.Series(obs).rolling(60, min_periods=10).std()
        peak = int(rolling_std.fillna(0).idxmax())
        start = max(0, min(peak - 60, len(obs) - 120))
    else:
        start = 0
    sl = slice(start, start + 120)

    fig, ax = plt.subplots(figsize=(11, 4))
    ax.plot(dates[sl], obs[sl], "k-", label="Observed", linewidth=1.3)
    ax.plot(dates[sl], q_np[sl], "r-",
            label=f"NumPy lag (NSE={row['nse_np']:+.3f})", alpha=0.85)
    ax.plot(dates[sl], q_pt[sl], "b-",
            label=f"PyTorch lag (NSE={row['nse_pt']:+.3f})", alpha=0.85)
    ax.set_xlabel("Date")
    ax.set_ylabel("Discharge [mm/d]")
    ax.set_title(
        f"Basin {row['basin_id']} - lag_time={row['lag_time']:.2f}, "
        f"dNSE={row['dnse']:+.4f} (basin with largest lag_time in sample)"
    )
    ax.legend(loc="upper right", fontsize=8)
    fig.autofmt_xdate()
    fig.tight_layout()
    fig.savefig(output_dir / "hydrograph_largest_lag.png", dpi=120)
    plt.close(fig)


# ---------------------------------------------------------------------------
# CLI driver
# ---------------------------------------------------------------------------

def _build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument(
        "--manifest",
        default=str(_REPO_ROOT / "src" / "xaj_global_pilot" / "configs"
                    / "conceptual_benchmark_camels_us_531_repro.txt"),
    )
    p.add_argument("--data-root", default="data/camels_us")
    p.add_argument("--workers", type=int, default=6)
    p.add_argument("--limit", type=int, default=20,
                   help="Random sample size from manifest (0 = all)")
    p.add_argument("--seed", type=int, default=42)
    p.add_argument("--trials", type=int, default=5000)
    p.add_argument("--restarts", type=int, default=3)
    p.add_argument("--forcing", default="maurer")
    p.add_argument("--pet-method", default="priestley_taylor",
                   choices=["oudin", "priestley_taylor"])
    p.add_argument("--init-mean", type=float, default=0.5)
    p.add_argument("--init-sigma", type=float, default=0.3)
    p.add_argument("--bounds", default="v1",
                   help="HBV bounds preset (v1=tight Feng 2022 defaults, v5=wider)")
    p.add_argument(
        "--output-dir",
        default="results/10_global_conceptual_model_benchmark/lag_diagnostic",
    )
    return p


def main(argv=None) -> int:
    args = _build_parser().parse_args(argv)

    from xaj_global_pilot.config import repro_split_periods
    periods = repro_split_periods()
    cal_period = periods["calibration"]
    eval_period = periods["evaluation"]

    manifest = Path(args.manifest)
    if not manifest.exists():
        raise FileNotFoundError(f"Manifest not found: {manifest}")
    basins_all = [
        line.strip().zfill(8)
        for line in manifest.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    rng = np.random.default_rng(args.seed)
    if 0 < args.limit < len(basins_all):
        idx = rng.choice(len(basins_all), args.limit, replace=False)
        basins = sorted(basins_all[int(i)] for i in idx)
    else:
        basins = basins_all

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    print(f"[{time.strftime('%H:%M:%S')}] lag diagnostic")
    print(f"  basins         : {len(basins)} (seed={args.seed})")
    print(f"  HBV_BOUNDS     : {args.bounds}")
    print(f"  forcing/pet    : {args.forcing} / {args.pet_method}")
    print(f"  init(mean/sig) : {args.init_mean} / {args.init_sigma}")
    print(f"  cal period     : {cal_period}")
    print(f"  eval period    : {eval_period}")
    print(f"  workers        : {args.workers}")
    print(f"  output         : {output_dir}")
    print()

    work = [
        (b, args.data_root, args.forcing, args.pet_method, cal_period, eval_period,
         args.trials, args.restarts, args.init_mean, args.init_sigma, args.bounds)
        for b in basins
    ]

    rows: list[dict] = []
    t0 = time.time()
    with ProcessPoolExecutor(max_workers=args.workers) as pool:
        futures = {pool.submit(diagnose_one_basin, w): w[0] for w in work}
        for i, fut in enumerate(as_completed(futures), 1):
            r = fut.result()
            rows.append(r)
            elapsed = time.time() - t0
            eta = elapsed / i * (len(work) - i)
            if r["status"] == "success":
                print(
                    f"[{time.strftime('%H:%M:%S')}] {i:3d}/{len(work)} "
                    f"{r['basin_id']} lag={r['lag_time']:5.2f} "
                    f"NSE_np={r['nse_np']:+.3f} NSE_pt={r['nse_pt']:+.3f} "
                    f"dNSE={r['dnse']:+.4f} "
                    f"|dQraw|max={r['max_abs_qraw_diff']:.2e} "
                    f"t={r['elapsed_s']:.0f}s wall={elapsed/60:.1f}m "
                    f"ETA={eta/60:.0f}m",
                    flush=True,
                )
            else:
                print(
                    f"[{time.strftime('%H:%M:%S')}] {i:3d}/{len(work)} "
                    f"{r['basin_id']} FAILED: {str(r.get('error', '?'))[:100]}",
                    flush=True,
                )

    df = pd.DataFrame(rows)
    df_csv = df[[c for c in df.columns if not c.startswith("_")]]
    df_csv.to_csv(output_dir / "per_basin_diag.csv", index=False)

    ok = df[df["status"] == "success"].copy()
    summary_rows: dict[str, Any] = {
        "n_total": len(df),
        "n_success": len(ok),
        "n_failed": len(df) - len(ok),
        "config_bounds": args.bounds,
        "config_forcing": args.forcing,
        "config_pet_method": args.pet_method,
    }
    if len(ok) > 0:
        for col in ["lag_time", "nse_np", "nse_pt", "dnse",
                    "max_abs_qraw_diff", "median_abs_qraw_diff",
                    "max_abs_qsim_diff", "median_abs_qsim_diff",
                    "p95_abs_qsim_diff"]:
            summary_rows[f"{col}_median"] = float(ok[col].median())
            summary_rows[f"{col}_p5"] = float(ok[col].quantile(0.05))
            summary_rows[f"{col}_p95"] = float(ok[col].quantile(0.95))
    pd.Series(summary_rows).to_csv(output_dir / "summary.csv", header=False)

    make_plots(df, output_dir)

    v = make_verdict(df)
    lines = [
        "=" * 64,
        "LAG BUG DIAGNOSTIC",
        "=" * 64,
        f"Sample size  : {v.get('n_basins', 0)} successful / {len(df)} attempted",
        f"Config       : HBV_BOUNDS={args.bounds}, forcing={args.forcing}, "
        f"pet={args.pet_method}",
        f"Cal period   : {cal_period[0]} -> {cal_period[1]}",
        f"Eval period  : {eval_period[0]} -> {eval_period[1]}",
        "",
        f"VERDICT      : {v['verdict']}",
        "",
        f"Reason       : {v['reason']}",
        "",
        "Statistics:",
    ]
    if "lag_t_median" in v:
        lines.append(
            f"  lag_time      median = {v['lag_t_median']:.3f}, "
            f"P95 = {v.get('lag_t_p95', float('nan')):.3f}"
        )
    if "dnse_median" in v:
        lines.append(
            f"  dNSE          median = {v['dnse_median']:+.4f}, "
            f"P5  = {v.get('dnse_p5', float('nan')):+.4f}"
        )
    if "qraw_diff_median" in v:
        lines.append(
            f"  |dQraw|       median = {v['qraw_diff_median']:.2e}  "
            f"(< 1e-3 -> inner loop OK)"
        )
    if "n_severe" in v:
        lines.append(
            f"  Basins with dNSE < -0.02: "
            f"{v['n_severe']} / {v.get('n_basins', '?')}"
        )
    lines.append("")
    lines.append(f"Wall time    : {(time.time() - t0)/60:.1f} min")
    lines.append("")
    lines.append(f"Artifacts in: {output_dir}")

    verdict_text = "\n".join(lines) + "\n"
    (output_dir / "verdict.txt").write_text(verdict_text, encoding="utf-8")
    print()
    print(verdict_text)

    meta = {
        "verdict_summary": v,
        "config": {
            "bounds_preset": args.bounds,
            "forcing": args.forcing,
            "pet_method": args.pet_method,
            "init_mean": args.init_mean,
            "init_sigma": args.init_sigma,
            "trials": args.trials,
            "restarts": args.restarts,
            "calibration_period": list(cal_period),
            "evaluation_period": list(eval_period),
        },
        "wall_clock_min": round((time.time() - t0) / 60, 2),
        "sample_size": len(basins),
    }
    (output_dir / "verdict.json").write_text(
        json.dumps(meta, indent=2), encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

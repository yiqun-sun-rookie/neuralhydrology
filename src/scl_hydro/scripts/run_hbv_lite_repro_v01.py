"""Local multiprocessing driver: HBV-lite full-531 under repro_v01 protocol.

Mirrors ``run_hbv96_p1_repro_v01.py`` but uses ``DifferentiableHBVLite``
(5-state HBV-light, 14 params including parCFR / parCWH / parLP) — the
hydroDL2 port that achieved 4-basin sanity median NSE = 0.659.

Why local-only is OK:
- HBV-lite step (dt=1, no sub-step) is ~30% faster per epoch than P1.
- 200 epoch × 3 restart × ~2.5s = ~1500s per basin.
- 531 basins × 6 workers ≈ 37 hours wall-clock.

Usage::

    python -X utf8 -m src.scl_hydro.scripts.run_hbv_lite_repro_v01 --workers 6
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
from concurrent.futures import ProcessPoolExecutor, as_completed
from pathlib import Path

# Single-thread BLAS / OMP per worker — must be set BEFORE numpy/torch imports
for _var in ("OMP_NUM_THREADS", "MKL_NUM_THREADS", "OPENBLAS_NUM_THREADS",
             "NUMEXPR_NUM_THREADS", "VECLIB_MAXIMUM_THREADS"):
    os.environ.setdefault(_var, "1")

import numpy as np
import pandas as pd

_HERE = Path(__file__).resolve()
_REPO_ROOT = _HERE.parents[3]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from src.xaj_global_pilot.config import (  # noqa: E402
    REPRO_FORCING,
    REPRO_VERSION,
    benchmark_results_dir,
    repro_split_periods,
)


CAL_KEY = "calibration"
EVAL_KEY = "evaluation"
MODEL_NAME = "hbv_lite"
FAMILY = "hbv"
SOLVER_NAME = "explicit_euler_dt1"


def _run_one(args_tuple):
    """Worker entrypoint."""
    (basin_id, data_root, n_epochs, n_restarts, lr, forcing,
     cal_period, eval_period) = args_tuple

    import torch
    torch.set_num_threads(1)
    from src.hydroagent.data_loading import load_camels_basin
    from src.scl_hydro.hbv_lite_calibrate import calibrate_hbv_lite, simulate_hbv_lite
    from src.xaj_global_pilot.metrics import compute_metrics
    from src.scl_hydro.hbv_lite import N_PARAMS

    t0 = time.time()
    cal_start, cal_end = cal_period
    eval_start, eval_end = eval_period

    try:
        forcing_cal, obs_cal, _ = load_camels_basin(
            basin_id, data_root=data_root,
            start_date=cal_start, end_date=cal_end, forcing=forcing,
        )
        rain_cal = forcing_cal["prcp"].values.astype(np.float64)
        pet_col = "ep" if "ep" in forcing_cal.columns else (
            "pet" if "pet" in forcing_cal.columns else None)
        if pet_col is None:
            raise RuntimeError(f"No PET column for {basin_id}")
        pet_cal = forcing_cal[pet_col].values.astype(np.float64)
        temp_cal = (forcing_cal["tmean"].values.astype(np.float64)
                    if "tmean" in forcing_cal.columns
                    else np.zeros_like(rain_cal))
        obs_cal_arr = obs_cal.values.astype(np.float64)

        cal_result = calibrate_hbv_lite(
            rain_cal, pet_cal, temp_cal, obs_cal_arr,
            n_epochs=n_epochs, lr=lr, n_restarts=n_restarts,
        )

        forcing_eval, obs_eval, _ = load_camels_basin(
            basin_id, data_root=data_root,
            start_date=eval_start, end_date=eval_end, forcing=forcing,
        )
        rain_eval = forcing_eval["prcp"].values.astype(np.float64)
        pet_eval = forcing_eval[pet_col].values.astype(np.float64)
        temp_eval = (forcing_eval["tmean"].values.astype(np.float64)
                     if "tmean" in forcing_eval.columns
                     else np.zeros_like(rain_eval))

        q_eval_np, _ = simulate_hbv_lite(
            rain_eval, pet_eval, temp_eval,
            cal_result["optimized_params"],
            state_init=cal_result["final_state"],
        )
        sim_series = pd.Series(q_eval_np, index=obs_eval.index, name="qsim")
        metrics = compute_metrics(obs_eval, sim_series)

        return {
            "basin_id": basin_id,
            "model": MODEL_NAME,
            "period": EVAL_KEY,
            **metrics,
            "parameter_count": N_PARAMS,
            "solver_name": SOLVER_NAME,
            "family": FAMILY,
            "run_status": "success",
            "error_message": "",
            "_elapsed_s": round(time.time() - t0, 2),
            "_cal_nse": round(cal_result["nse"], 4),
        }

    except Exception as exc:  # noqa: BLE001
        return {
            "basin_id": basin_id,
            "model": MODEL_NAME,
            "period": EVAL_KEY,
            "nse": None, "kge": None, "bias": None,
            "peak_bias": None, "lowflow_bias": None,
            "parameter_count": 14,
            "solver_name": SOLVER_NAME,
            "family": FAMILY,
            "run_status": "failed",
            "error_message": str(exc),
            "_elapsed_s": round(time.time() - t0, 2),
            "_cal_nse": None,
        }


def _read_basin_ids(manifest: Path) -> list[str]:
    return [line.strip().zfill(8)
            for line in manifest.read_text(encoding="utf-8").splitlines()
            if line.strip()]


def _build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--manifest",
                   default=str(_REPO_ROOT / "src" / "xaj_global_pilot" / "configs"
                               / "conceptual_benchmark_camels_us_531_repro.txt"))
    p.add_argument("--data-root", default="data/camels_us")
    p.add_argument("--workers", type=int, default=6,
                   help="Parallel worker count. Default 6 leaves ~26/32 logical "
                        "cores free on i9-13900K for concurrent foreground work.")
    p.add_argument("--epochs", type=int, default=200)
    p.add_argument("--restarts", type=int, default=3)
    p.add_argument("--lr", type=float, default=0.02)
    p.add_argument("--forcing", default=REPRO_FORCING)
    p.add_argument("--output-root", default=None)
    p.add_argument("--skip-existing", dest="skip_existing", action="store_true", default=True)
    p.add_argument("--no-skip-existing", dest="skip_existing", action="store_false")
    p.add_argument("--limit", type=int, default=None)
    return p


def main(argv=None) -> int:
    args = _build_parser().parse_args(argv)
    periods = repro_split_periods()
    cal_period = periods[CAL_KEY]
    eval_period = periods[EVAL_KEY]

    manifest = Path(args.manifest)
    basins = _read_basin_ids(manifest)
    if args.limit is not None:
        basins = basins[: args.limit]

    output_root = Path(args.output_root) if args.output_root else benchmark_results_dir(REPRO_VERSION)
    model_dir = output_root / MODEL_NAME
    summary_dir = output_root / "summary"
    model_dir.mkdir(parents=True, exist_ok=True)
    summary_dir.mkdir(parents=True, exist_ok=True)

    if args.skip_existing:
        todo = [b for b in basins if not (model_dir / f"{b}.csv").exists()]
        skipped = len(basins) - len(todo)
    else:
        todo = list(basins)
        skipped = 0

    print(f"[{time.strftime('%H:%M:%S')}] {MODEL_NAME} 531 full run")
    print(f"  protocol      = repro_v01 (Adam-calibrated)")
    print(f"  forcing       = {args.forcing}")
    print(f"  periods       = cal {cal_period[0]}..{cal_period[1]}, "
          f"eval {eval_period[0]}..{eval_period[1]}")
    print(f"  epochs/restarts/lr = {args.epochs} / {args.restarts} / {args.lr}")
    print(f"  workers       = {args.workers} (host has {os.cpu_count()} logical cores)")
    print(f"  output_root   = {output_root}")
    print(f"  basins total  = {len(basins)}, skipped = {skipped}, todo = {len(todo)}")

    if not todo:
        print("[INFO] Nothing to do.")
        return 0

    work = [
        (b, args.data_root, args.epochs, args.restarts, args.lr,
         args.forcing, cal_period, eval_period)
        for b in todo
    ]

    rows: list[dict] = []
    t_start = time.time()

    with ProcessPoolExecutor(max_workers=args.workers) as pool:
        futures = {pool.submit(_run_one, w): w[0] for w in work}
        for i, fut in enumerate(as_completed(futures), start=1):
            try:
                result = fut.result()
            except Exception as exc:  # noqa: BLE001
                basin_id = futures[fut]
                result = {
                    "basin_id": basin_id, "model": MODEL_NAME, "period": EVAL_KEY,
                    "nse": None, "kge": None, "bias": None,
                    "peak_bias": None, "lowflow_bias": None,
                    "parameter_count": None, "solver_name": SOLVER_NAME, "family": FAMILY,
                    "run_status": "failed", "error_message": f"worker exception: {exc}",
                    "_elapsed_s": None, "_cal_nse": None,
                }

            basin_id = result["basin_id"]
            pd.DataFrame([result]).to_csv(model_dir / f"{basin_id}.csv", index=False)
            rows.append(result)

            elapsed = time.time() - t_start
            eta_s = elapsed / i * (len(todo) - i) if i else 0.0
            nse_val = result.get("nse")
            nse_str = f"{nse_val:.3f}" if isinstance(nse_val, (int, float)) and nse_val is not None else "NA"
            print(f"[{time.strftime('%H:%M:%S')}] {i:4d}/{len(todo)} {basin_id} "
                  f"NSE={nse_str:>7} {result['run_status']:<7} "
                  f"t={result.get('_elapsed_s', 0):.0f}s "
                  f"wall={elapsed/3600:.2f}h ETA={eta_s/3600:.1f}h",
                  flush=True)

    # Final summary
    all_files = sorted(model_dir.glob("*.csv"))
    if all_files:
        df = pd.concat(
            [pd.read_csv(f, dtype={"basin_id": str}, keep_default_na=False) for f in all_files],
            ignore_index=True,
        )
        df["basin_id"] = df["basin_id"].astype(str).str.zfill(8)
        df = df.sort_values("basin_id").reset_index(drop=True)
    else:
        df = pd.DataFrame(rows)

    summary_csv = summary_dir / f"{MODEL_NAME}_local_full.csv"
    df.to_csv(summary_csv, index=False)

    metadata = {
        "protocol": "repro_v01",
        "protocol_version": REPRO_VERSION,
        "model": MODEL_NAME,
        "forcing": args.forcing,
        "calibration_start": cal_period[0],
        "calibration_end": cal_period[1],
        "evaluation_start": eval_period[0],
        "evaluation_end": eval_period[1],
        "calibrator": "Adam multi-restart",
        "epochs": args.epochs,
        "restarts": args.restarts,
        "lr": args.lr,
        "workers": args.workers,
        "n_basins_total": len(basins),
        "n_skipped_existing": skipped,
        "n_executed": len(todo),
        "n_in_summary": len(df),
        "wall_clock_s": round(time.time() - t_start, 1),
        "data_root": args.data_root,
        "manifest": str(manifest),
        "host_cpu_count": os.cpu_count(),
        "model_source": "ported from mhpi/hydroDL2 (Feng et al. 2022 WRR)",
    }
    (summary_dir / f"{MODEL_NAME}_local_full.metadata.json").write_text(
        json.dumps(metadata, indent=2), encoding="utf-8",
    )

    success = df[df["run_status"] == "success"] if not df.empty else pd.DataFrame()
    failed = df[df["run_status"] == "failed"] if not df.empty else pd.DataFrame()
    print()
    print(f"=== DONE - this batch executed {len(todo)} basins ===")
    print(f"Wall (this batch): {(time.time() - t_start)/3600:.2f} h")
    print(f"Summary spans     : {len(df)} basin rows ({len(success)} success / {len(failed)} failed)")
    if not success.empty and pd.notna(success["nse"]).any():
        s = pd.to_numeric(success["nse"], errors="coerce").dropna()
        print(f"NSE (all in summary) median={s.median():.4f}  mean={s.mean():.4f}  n={len(s)}")
        print(f"  NSE>=0.6: {(s>=0.6).sum()}, NSE>=0.5: {(s>=0.5).sum()}, NSE<0: {(s<0).sum()}, NSE<-1: {(s<-1).sum()}")
    print(f"Summary CSV : {summary_csv}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

"""Local multiprocessing driver: PDD+XAJ CMA-ES full-531 under repro_v01.

This is the *playbook* runner for PDD+XAJ — a byte-for-byte protocol clone of
``src/scl_hydro/scripts/run_hbv_lite_cma_repro_v01.py`` so that XAJ is calibrated
and evaluated under EXACTLY the same conditions as the successful HBV-lite
ensemble (same repro_v01 cal/eval split, same PET options, same Kratzert-style
warmup-year init, same per-basin param+state dump, same ``compute_metrics``).

The only model-specific swaps vs the HBV runner:
- forward model      : ``simulate_pdd_xaj_fast`` (20 params, state (1,11))
- calibrator         : ``calibrate_pdd_xaj`` (CMA-ES multi-restart, playbook knobs)
- parameter ordering : ``PDD_XAJ_PARAM_NAMES`` (6 PDD + 14 XAJ)
- state vector       : [snow, ice, last_temp, W, WU, WL, WD, S, QS, QI, QG]

Why this exists: the original ``run_local_xaj_pdd_full.py`` predates the HBV
playbook. It used Oudin PET, cal-final (2008) state as the 1989 eval init
(time-reversed), a single variant, and no bounds audit — landing at a 531
median NSE of 0.4458. This runner adds the playbook levers so XAJ gets a fair,
same-conditions shot.

Per-basin CSV schema mirrors the HBV runner:
- metric/metadata: basin_id, model, period, nse, kge, bias, peak_bias,
  lowflow_bias, parameter_count, solver_name, family, run_status,
  error_message, _elapsed_s, _cal_nse
- 20 ``p_*`` parameter columns
- 11 ``state_*`` columns (eval-period init state)
- 1 ``state_init_mode`` column

Usage::

    python -X utf8 -m src.xaj_global_pilot.scripts.run_xaj_pdd_cma_repro_v01 \\
        --workers 12 --pet-method priestley_taylor --warmup-year \\
        --manifest src/xaj_global_pilot/configs/xaj_playbook_iter_subset_40.txt \\
        --output-subdir xaj_pdd_cma_iterN --trials 1500 --restarts 2
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
from concurrent.futures import ProcessPoolExecutor, as_completed
from pathlib import Path

for _v in ("OMP_NUM_THREADS", "MKL_NUM_THREADS", "OPENBLAS_NUM_THREADS",
           "NUMEXPR_NUM_THREADS", "VECLIB_MAXIMUM_THREADS"):
    os.environ.setdefault(_v, "1")

import numpy as np
import pandas as pd

_HERE = Path(__file__).resolve()
_REPO_ROOT = _HERE.parents[3]
if str(_REPO_ROOT / "src") not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT / "src"))
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from xaj_global_pilot.config import (  # noqa: E402
    REPRO_FORCING,
    REPRO_VERSION,
    benchmark_results_dir,
    repro_split_periods,
)

CAL_KEY = "calibration"
EVAL_KEY = "evaluation"
MODEL_NAME = "xaj_pdd_cma"
FAMILY = "xaj"
SOLVER_NAME = "explicit_euler_dt1"
STATE_NAMES = ["snow", "ice", "last_temp", "W", "WU", "WL", "WD", "S", "QS", "QI", "QG"]


def _run_one(args_tuple):
    (basin_id, data_root, n_trials, n_restarts, forcing,
     cal_period, eval_period, loss, kge_weight, pet_method,
     init_mean, init_sigma, warmup_year, bounds_preset) = args_tuple

    import sys as _sys
    if str(_REPO_ROOT / "src") not in _sys.path:
        _sys.path.insert(0, str(_REPO_ROOT / "src"))
    from hydroagent.data_loading import load_camels_basin
    from xaj_global_pilot.xaj_model import (
        calibrate_pdd_xaj, simulate_pdd_xaj, PDD_XAJ_PARAM_NAMES,
        PDD_PARAM_BOUNDS, PARAM_BOUNDS,
    )
    from xaj_global_pilot.bounds_presets import resolve_xaj_bounds
    from xaj_global_pilot.metrics import compute_metrics

    t0 = time.time()
    cal_start, cal_end = cal_period
    eval_start, eval_end = eval_period

    def _extract(forcing_df):
        rain = forcing_df["prcp"].values.astype(np.float64)
        pet_col = "ep" if "ep" in forcing_df.columns else (
            "pet" if "pet" in forcing_df.columns else None)
        if pet_col is None:
            raise RuntimeError(f"No PET column for {basin_id}")
        pet = forcing_df[pet_col].values.astype(np.float64)
        temp = (forcing_df["tmean"].values.astype(np.float64)
                if "tmean" in forcing_df.columns else np.zeros_like(rain))
        return np.nan_to_num(rain, nan=0.0), np.nan_to_num(pet, nan=0.0), np.nan_to_num(temp, nan=0.0)

    try:
        bounds = resolve_xaj_bounds(bounds_preset, PDD_PARAM_BOUNDS, PARAM_BOUNDS)

        # keep_obs_nan_days=True keeps the forcing series CONTIGUOUS even when
        # obs has missing days. Without it, the loader drops obs-NaN rows, which
        # would make the forcing non-contiguous and cause the state to telescope
        # across multi-day gaps. (Verified 0/531 impact in the repro_v01 windows,
        # but kept as a defensive correctness guarantee for other periods/datasets.)
        # Calibration tolerates NaN obs: the CMA-ES objective masks non-finite obs.
        forcing_cal, obs_cal, _ = load_camels_basin(
            basin_id, data_root=data_root,
            start_date=cal_start, end_date=cal_end, forcing=forcing,
            pet_method=pet_method, keep_obs_nan_days=True,
        )
        rain_cal, pet_cal, temp_cal = _extract(forcing_cal)
        obs_cal_arr = obs_cal.values.astype(np.float64)

        cal_result = calibrate_pdd_xaj(
            rain_cal, pet_cal, temp_cal, obs_cal_arr,
            n_trials=n_trials, n_restarts=n_restarts,
            loss=loss, kge_weight=kge_weight,
            init_mean=init_mean, init_sigma=init_sigma,
            param_bounds=bounds,
        )
        best_params = cal_result["optimized_params"]

        # Eval-period init state. warmup_year matches the Kratzert protocol used
        # in the HBV runner: run the year PRECEDING eval_start forward from the
        # default (param-dependent) init, use the end-of-warmup state as eval init.
        if warmup_year:
            warmup_start = (pd.Timestamp(eval_start) - pd.DateOffset(years=1)).strftime("%Y-%m-%d")
            warmup_end = (pd.Timestamp(eval_start) - pd.DateOffset(days=1)).strftime("%Y-%m-%d")
            forcing_w, _, _ = load_camels_basin(
                basin_id, data_root=data_root,
                start_date=warmup_start, end_date=warmup_end, forcing=forcing,
                pet_method=pet_method, keep_obs_nan_days=True,
            )
            rain_w, pet_w, temp_w = _extract(forcing_w)
            _, eval_init_state = simulate_pdd_xaj(
                rain_w, pet_w, temp_w, best_params, initial_state=None)
        else:
            eval_init_state = cal_result["final_state"]

        # keep_obs_nan_days=True: contiguous eval forcing (see cal-load note).
        # compute_metrics drops NaN-obs days, so the score is unaffected.
        forcing_eval, obs_eval, _ = load_camels_basin(
            basin_id, data_root=data_root,
            start_date=eval_start, end_date=eval_end, forcing=forcing,
            pet_method=pet_method, keep_obs_nan_days=True,
        )
        rain_eval, pet_eval, temp_eval = _extract(forcing_eval)

        q_eval_np, _ = simulate_pdd_xaj(
            rain_eval, pet_eval, temp_eval, best_params, initial_state=eval_init_state)
        sim_series = pd.Series(q_eval_np, index=obs_eval.index, name="qsim")
        metrics = compute_metrics(obs_eval, sim_series)

        out = {
            "basin_id": basin_id, "model": MODEL_NAME, "period": EVAL_KEY,
            **metrics,
            "parameter_count": len(PDD_XAJ_PARAM_NAMES),
            "solver_name": SOLVER_NAME, "family": FAMILY,
            "run_status": "success", "error_message": "",
            "_elapsed_s": round(time.time() - t0, 2),
            "_cal_nse": round(cal_result["nse"], 4),
        }
        for pname in PDD_XAJ_PARAM_NAMES:
            out[f"p_{pname}"] = float(best_params.get(pname, np.nan))
        state_arr = np.asarray(eval_init_state).reshape(-1)
        for i, sname in enumerate(STATE_NAMES):
            out[f"state_{sname}"] = float(state_arr[i]) if i < state_arr.size else 0.0
        out["state_init_mode"] = ("warmup_year_end" if warmup_year else "cal_final")
        return out
    except Exception as exc:  # noqa: BLE001
        return {
            "basin_id": basin_id, "model": MODEL_NAME, "period": EVAL_KEY,
            "nse": None, "kge": None, "bias": None,
            "peak_bias": None, "lowflow_bias": None,
            "parameter_count": 20, "solver_name": SOLVER_NAME, "family": FAMILY,
            "run_status": "failed", "error_message": f"{type(exc).__name__}: {exc}",
            "_elapsed_s": round(time.time() - t0, 2), "_cal_nse": None,
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
    p.add_argument("--workers", type=int, default=12)
    p.add_argument("--trials", type=int, default=5000)
    p.add_argument("--restarts", type=int, default=3)
    p.add_argument("--loss", choices=["nse", "kge", "hybrid"], default="nse")
    p.add_argument("--kge-weight", type=float, default=0.5)
    p.add_argument("--forcing", default=REPRO_FORCING)
    p.add_argument("--pet-method", choices=["oudin", "priestley_taylor"], default="oudin")
    p.add_argument("--init-mean", type=float, default=0.5)
    p.add_argument("--init-sigma", type=float, default=0.3)
    p.add_argument("--bounds-preset", default="v1",
                   help="XAJ bounds preset key (see bounds_presets.py). v1 = current defaults.")
    p.add_argument("--output-subdir", default=MODEL_NAME,
                   help="Subdir under the repro_v01 results root to write per-basin csvs.")
    p.add_argument("--output-root", default=None)
    p.add_argument("--skip-existing", dest="skip_existing", action="store_true", default=True)
    p.add_argument("--no-skip-existing", dest="skip_existing", action="store_false")
    p.add_argument("--limit", type=int, default=None)
    p.add_argument("--warmup-year", dest="warmup_year", action="store_true", default=False)
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
    model_dir = output_root / args.output_subdir
    summary_dir = output_root / "summary"
    model_dir.mkdir(parents=True, exist_ok=True)
    summary_dir.mkdir(parents=True, exist_ok=True)

    if args.skip_existing:
        todo = [b for b in basins if not (model_dir / f"{b}.csv").exists()]
        skipped = len(basins) - len(todo)
    else:
        todo = list(basins)
        skipped = 0

    print(f"[{time.strftime('%H:%M:%S')}] {MODEL_NAME} run (CMA-ES playbook)")
    print(f"  protocol     = repro_v01 ({args.trials} trials x {args.restarts} restarts)")
    print(f"  forcing      = {args.forcing}  pet = {args.pet_method}  bounds = {args.bounds_preset}")
    print(f"  loss         = {args.loss} (kge_w={args.kge_weight})  init_mean={args.init_mean} sigma={args.init_sigma}")
    print(f"  warmup_year  = {args.warmup_year}")
    print(f"  out subdir   = {model_dir}")
    print(f"  basins total = {len(basins)}, skipped = {skipped}, todo = {len(todo)}")

    if not todo:
        print("[INFO] Nothing to do.")
        return 0

    work = [
        (b, args.data_root, args.trials, args.restarts,
         args.forcing, cal_period, eval_period,
         args.loss, args.kge_weight, args.pet_method,
         args.init_mean, args.init_sigma, args.warmup_year, args.bounds_preset)
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
                    "parameter_count": 20, "solver_name": SOLVER_NAME, "family": FAMILY,
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
                  f"wall={elapsed/60:.1f}min ETA={eta_s/60:.0f}min", flush=True)

    all_files = sorted(model_dir.glob("*.csv"))
    df = pd.concat(
        [pd.read_csv(f, dtype={"basin_id": str}, keep_default_na=False) for f in all_files],
        ignore_index=True,
    )
    df["basin_id"] = df["basin_id"].astype(str).str.zfill(8)
    df = df.sort_values("basin_id").reset_index(drop=True)

    summary_csv = summary_dir / f"{args.output_subdir}_local_full.csv"
    df.to_csv(summary_csv, index=False)

    metadata = {
        "protocol": "repro_v01", "protocol_version": REPRO_VERSION,
        "model": MODEL_NAME, "output_subdir": args.output_subdir,
        "forcing": args.forcing, "pet_method": args.pet_method,
        "bounds_preset": args.bounds_preset, "loss": args.loss,
        "kge_weight": args.kge_weight, "init_mean": args.init_mean,
        "init_sigma": args.init_sigma, "warmup_year": args.warmup_year,
        "calibration_start": cal_period[0], "calibration_end": cal_period[1],
        "evaluation_start": eval_period[0], "evaluation_end": eval_period[1],
        "trials": args.trials, "restarts": args.restarts, "workers": args.workers,
        "n_basins_total": len(basins), "n_skipped_existing": skipped,
        "n_executed": len(todo), "n_in_summary": len(df),
        "wall_clock_s": round(time.time() - t_start, 1),
        "data_root": args.data_root, "manifest": str(manifest),
        "host_cpu_count": os.cpu_count(),
    }
    (summary_dir / f"{args.output_subdir}_local_full.metadata.json").write_text(
        json.dumps(metadata, indent=2), encoding="utf-8")

    success = df[df["run_status"] == "success"] if not df.empty else pd.DataFrame()
    failed = df[df["run_status"] == "failed"] if not df.empty else pd.DataFrame()
    print()
    print(f"=== DONE - executed {len(todo)} basins ===")
    print(f"Wall (this batch): {(time.time() - t_start)/60:.2f} min")
    print(f"Summary spans: {len(df)} basins ({len(success)} success / {len(failed)} failed)")
    if not success.empty and pd.notna(success["nse"]).any():
        s = pd.to_numeric(success["nse"], errors="coerce").dropna()
        print(f"NSE median={s.median():.4f}  mean={s.mean():.4f}  n={len(s)}")
        print(f"  >=0.6: {(s>=0.6).sum()}, >=0.5: {(s>=0.5).sum()}, "
              f">=0.3: {(s>=0.3).sum()}, <0: {(s<0).sum()}, <-1: {(s<-1).sum()}")
    print(f"Summary CSV: {summary_csv}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

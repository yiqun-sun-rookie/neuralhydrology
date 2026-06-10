"""Local multiprocessing driver: HBV-lite CMA-ES full-531 under repro_v01 protocol.

Uses NumPy + Numba HBV-lite (33 s/basin with 5000 × 3 evals) and pycma
for derivative-free calibration. Total expected wall time: ~1-2 hours
with 6 workers on i9-13900K (vs ~30h for the failed Adam version).

Per-basin CSV schema (post-lockdown):
- 15 metric/metadata columns: basin_id, model, period, nse, kge, bias,
  peak_bias, lowflow_bias, parameter_count, solver_name, family,
  run_status, error_message, _elapsed_s, _cal_nse
- 13 ``p_*`` parameter columns dumped from CMA-ES optimum
- 5 ``state_*`` columns holding eval-period init state (see state_init_mode)
- 1 ``state_init_mode`` column with values
    "cal_final_2008-09-30"  (no warmup)
    "warmup_year_end_1989-09-30"  (with --warmup-year)

Eval init state has two modes:
- DEFAULT (no flag): ``cal_result["final_state"]`` (2008-09-30) is used as
  eval init. Fast but time-reversed because eval (1989-1999) precedes cal
  (1999-2008); biases NSE down 0.005-0.015 on slow-SLZ basins.
- ``--warmup-year``: Load 1988-10-01..1989-09-30 forcing via
  ``load_camels_basin(..., keep_obs_nan_days=True)``, run forward from
  default init, use end-of-warmup state to init eval. Matches Kratzert
  2019 CAMELS-US benchmark convention. Lifts headline median NSE from
  0.6227 → 0.6276 across the 9-variant ensemble.

Usage::

    python -X utf8 -m src.scl_hydro.scripts.run_hbv_lite_cma_repro_v01 --workers 6
    python -X utf8 -m src.scl_hydro.scripts.run_hbv_lite_cma_repro_v01 --workers 6 --warmup-year
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
# Both src/ AND project root on path: workers must use the SAME import path
# the modules were first registered under (otherwise Numba @njit(cache=True)
# cache lookups fail because cached function __module__ doesn't match).
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
MODEL_NAME = "hbv_lite_cma"
FAMILY = "hbv"
SOLVER_NAME = "explicit_euler_dt1"


def _run_one(args_tuple):
    (basin_id, data_root, n_trials, n_restarts, forcing,
     cal_period, eval_period, loss, kge_weight, pet_method,
     init_mean, init_sigma, warmup_year, bounds_preset) = args_tuple

    # Worker must use same import path as Numba cache (no `src.` prefix).
    import sys as _sys
    if str(_REPO_ROOT / "src") not in _sys.path:
        _sys.path.insert(0, str(_REPO_ROOT / "src"))
    from hydroagent.data_loading import load_camels_basin
    from scl_hydro.hbv_lite_cma_calibrate import calibrate_hbv_lite_cma
    from scl_hydro.hbv_lite_numpy import resolve_hbv_bounds, simulate_hbv_lite
    from xaj_global_pilot.metrics import compute_metrics

    t0 = time.time()
    cal_start, cal_end = cal_period
    eval_start, eval_end = eval_period

    try:
        # keep_obs_nan_days=True keeps the forcing series CONTIGUOUS even when
        # obs has missing days, matching the GR4J/XAJ runners exactly (the
        # calibrator masks NaN obs in its objective). Verified 0/531 missing
        # days in the repro_v01 cal/eval windows so this is bit-identical to the
        # historical default-False path here, but removes a cross-model code-
        # path asymmetry (2026-06-08 fairness audit) and a latent footgun for
        # other windows/datasets.
        forcing_cal, obs_cal, _ = load_camels_basin(
            basin_id, data_root=data_root,
            start_date=cal_start, end_date=cal_end, forcing=forcing,
            pet_method=pet_method, keep_obs_nan_days=True,
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

        cal_result = calibrate_hbv_lite_cma(
            rain_cal, pet_cal, temp_cal, obs_cal_arr,
            n_trials=n_trials, n_restarts=n_restarts,
            loss=loss, kge_weight=kge_weight,
            init_mean_norm=init_mean, init_sigma=init_sigma,
            param_bounds=resolve_hbv_bounds(bounds_preset),
        )

        # Determine eval-period init state. Two conventions:
        # (a) cal_result["final_state"] — fast, but uses 2008 end-state for
        #     1989 init (time-reversed: NSE penalty 0.005-0.015 from SLZ
        #     mismatch in slow basins).
        # (b) Kratzert-style 1988-89 warmup: run forward over the year
        #     PRECEDING eval_start from default init, use end-of-warmup state
        #     as eval init. Matches the published CAMELS benchmark protocol.
        if warmup_year:
            warmup_start = (pd.Timestamp(eval_start)
                            - pd.DateOffset(years=1)).strftime("%Y-%m-%d")
            warmup_end = (pd.Timestamp(eval_start)
                          - pd.DateOffset(days=1)).strftime("%Y-%m-%d")
            forcing_w, _, _ = load_camels_basin(
                basin_id, data_root=data_root,
                start_date=warmup_start, end_date=warmup_end, forcing=forcing,
                pet_method=pet_method,
                # Warmup needs CONTIGUOUS forcing through every day regardless
                # of obs availability — some basins' streamflow records do not
                # extend back to the 1988-89 warmup window (e.g., 09484600),
                # which previously silently produced a 0-day warmup → default
                # init → catastrophic eval NSE.
                keep_obs_nan_days=True,
            )
            rain_w = forcing_w["prcp"].values.astype(np.float64)
            pet_w = forcing_w[pet_col].values.astype(np.float64)
            temp_w = (forcing_w["tmean"].values.astype(np.float64)
                      if "tmean" in forcing_w.columns
                      else np.zeros_like(rain_w))
            _, eval_init_state = simulate_hbv_lite(
                rain_w, pet_w, temp_w,
                cal_result["optimized_params"],
                initial_state=None,  # default init at start of warmup
            )
        else:
            eval_init_state = cal_result["final_state"]

        # keep_obs_nan_days=True for contiguous eval forcing (see cal-load note);
        # compute_metrics drops NaN-obs days so the score is unaffected. Matches
        # GR4J/XAJ runners.
        forcing_eval, obs_eval, _ = load_camels_basin(
            basin_id, data_root=data_root,
            start_date=eval_start, end_date=eval_end, forcing=forcing,
            pet_method=pet_method, keep_obs_nan_days=True,
        )
        rain_eval = forcing_eval["prcp"].values.astype(np.float64)
        pet_eval = forcing_eval[pet_col].values.astype(np.float64)
        temp_eval = (forcing_eval["tmean"].values.astype(np.float64)
                     if "tmean" in forcing_eval.columns
                     else np.zeros_like(rain_eval))

        q_eval_np, _ = simulate_hbv_lite(
            rain_eval, pet_eval, temp_eval,
            cal_result["optimized_params"],
            initial_state=eval_init_state,
        )
        sim_series = pd.Series(q_eval_np, index=obs_eval.index, name="qsim")
        metrics = compute_metrics(obs_eval, sim_series)

        out = {
            "basin_id": basin_id, "model": MODEL_NAME, "period": EVAL_KEY,
            **metrics,
            "parameter_count": 13, "solver_name": SOLVER_NAME, "family": FAMILY,
            "run_status": "success", "error_message": "",
            "_elapsed_s": round(time.time() - t0, 2),
            "_cal_nse": round(cal_result["nse"], 4),
        }
        # Persist optimized HBV-light parameters into the per-basin row so
        # downstream consumers (DA, paper reproducibility) can replay
        # without re-running CMA-ES.
        for pname, pval in cal_result["optimized_params"].items():
            out[f"p_{pname}"] = float(pval)
        # Persist the state actually used to initialize the eval period —
        # required for reproducible replay. Semantics depend on warmup_year:
        #   warmup_year=True  -> state at end of 1988-10-01..1989-09-30
        #                        warmup (Kratzert-style)
        #   warmup_year=False -> state at end of calibration period (2008-09-30)
        # The state_init_mode column makes the semantics self-documenting
        # so downstream consumers do not have to infer from output dir name.
        final_state_for_dump = eval_init_state or {}
        for sname in ("SNOWPACK", "MELTWATER", "SM", "SUZ", "SLZ"):
            out[f"state_{sname}"] = float(final_state_for_dump.get(sname, 0.0))
        out["state_init_mode"] = ("warmup_year_end_1989-09-30"
                                  if warmup_year
                                  else "cal_final_2008-09-30")
        return out
    except Exception as exc:  # noqa: BLE001
        return {
            "basin_id": basin_id, "model": MODEL_NAME, "period": EVAL_KEY,
            "nse": None, "kge": None, "bias": None,
            "peak_bias": None, "lowflow_bias": None,
            "parameter_count": 13, "solver_name": SOLVER_NAME, "family": FAMILY,
            "run_status": "failed", "error_message": str(exc),
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
    p.add_argument("--workers", type=int, default=6)
    p.add_argument("--trials", type=int, default=5000)
    p.add_argument("--restarts", type=int, default=3)
    p.add_argument("--loss", choices=["nse", "kge", "hybrid"], default="nse")
    p.add_argument("--kge-weight", type=float, default=0.5,
                   help="weight on KGE in hybrid loss (0=pure NSE, 1=pure KGE)")
    p.add_argument("--forcing", default=REPRO_FORCING)
    p.add_argument("--pet-method", choices=["oudin", "priestley_taylor"], default="oudin")
    p.add_argument("--init-mean", type=float, default=0.5)
    p.add_argument("--init-sigma", type=float, default=0.3)
    p.add_argument("--bounds-preset", default="v1",
                   help="HBV bounds preset key (see hbv_lite_numpy.BOUNDS_PRESETS). "
                        "v1 = hydroDL2 literature-tight (repro_v01 headline); v5 = wide. "
                        "Authoritative — overrides the import-time HBV_BOUNDS env var.")
    p.add_argument("--output-subdir", default=MODEL_NAME,
                   help="Subdir under the repro_v01 results root to write per-basin csvs "
                        "(and the summary filename prefix). Defaults to the model name so "
                        "existing behaviour is unchanged.")
    p.add_argument("--output-root", default=None)
    p.add_argument("--skip-existing", dest="skip_existing", action="store_true", default=True)
    p.add_argument("--no-skip-existing", dest="skip_existing", action="store_false")
    p.add_argument("--limit", type=int, default=None)
    p.add_argument("--warmup-year", dest="warmup_year", action="store_true",
                   default=False,
                   help="Use 1-year warmup before eval period (Kratzert-style). "
                        "Default uses cal final state as eval init.")
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

    print(f"[{time.strftime('%H:%M:%S')}] {MODEL_NAME} 531 full (CMA-ES)")
    print(f"  protocol      = repro_v01 ({args.trials} trials × {args.restarts} restarts)")
    print(f"  forcing       = {args.forcing}  pet = {args.pet_method}  bounds = {args.bounds_preset}")
    print(f"  loss          = {args.loss} (kge_w={args.kge_weight})  init_mean={args.init_mean} sigma={args.init_sigma}")
    print(f"  warmup_year   = {args.warmup_year}")
    print(f"  out subdir    = {model_dir}")
    print(f"  workers       = {args.workers}")
    print(f"  basins total  = {len(basins)}, skipped = {skipped}, todo = {len(todo)}")

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
                  f"wall={elapsed/60:.1f}min ETA={eta_s/60:.0f}min",
                  flush=True)

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

    summary_csv = summary_dir / f"{args.output_subdir}_local_full.csv"
    df.to_csv(summary_csv, index=False)

    metadata = {
        "protocol": "repro_v01",
        "protocol_version": REPRO_VERSION,
        "model": MODEL_NAME,
        "output_subdir": args.output_subdir,
        "forcing": args.forcing,
        # 2026-06-08 audit (Finding C/E): record PET/warmup/init/loss + the
        # bounds preset so a run is reproducible from metadata alone. As of S2
        # the bounds are selected at RUNTIME via --bounds-preset (threaded into
        # calibrate_hbv_lite_cma) and recorded below as "bounds_preset"; this is
        # authoritative and overrides the legacy import-time HBV_BOUNDS env var.
        "pet_method": args.pet_method,
        "warmup_year": args.warmup_year,
        "init_mean": args.init_mean,
        "init_sigma": args.init_sigma,
        "loss": args.loss,
        "kge_weight": args.kge_weight,
        "bounds_preset": args.bounds_preset,
        "calibration_start": cal_period[0],
        "calibration_end": cal_period[1],
        "evaluation_start": eval_period[0],
        "evaluation_end": eval_period[1],
        "calibrator": "CMA-ES (pycma) multi-restart",
        "trials": args.trials,
        "restarts": args.restarts,
        "workers": args.workers,
        "n_basins_total": len(basins),
        "n_skipped_existing": skipped,
        "n_executed": len(todo),
        "n_in_summary": len(df),
        "wall_clock_s": round(time.time() - t_start, 1),
        "data_root": args.data_root,
        "manifest": str(manifest),
        "host_cpu_count": os.cpu_count(),
        "model_source": "ported from mhpi/hydroDL2 (Feng et al. 2022 WRR), NumPy+Numba",
    }
    (summary_dir / f"{args.output_subdir}_local_full.metadata.json").write_text(
        json.dumps(metadata, indent=2), encoding="utf-8",
    )

    success = df[df["run_status"] == "success"] if not df.empty else pd.DataFrame()
    failed = df[df["run_status"] == "failed"] if not df.empty else pd.DataFrame()
    print()
    print(f"=== DONE - this batch executed {len(todo)} basins ===")
    print(f"Wall (this batch): {(time.time() - t_start)/60:.2f} min")
    print(f"Summary spans: {len(df)} basins ({len(success)} success / {len(failed)} failed)")
    if not success.empty and pd.notna(success["nse"]).any():
        s = pd.to_numeric(success["nse"], errors="coerce").dropna()
        print(f"NSE (all in summary) median={s.median():.4f}  mean={s.mean():.4f}  n={len(s)}")
        print(f"  NSE>=0.6: {(s>=0.6).sum()}, NSE>=0.5: {(s>=0.5).sum()}, "
              f"NSE>=0.3: {(s>=0.3).sum()}, NSE<0: {(s<0).sum()}, NSE<-1: {(s<-1).sum()}")
    print(f"Summary CSV: {summary_csv}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

"""Local multiprocessing driver: xaj_pdd full-531 under repro_v01 protocol.

Why this script exists:
- HBV / GR4J need superflexpy (HPC only on this project).
- xaj_pdd is pure NumPy + Numba and runs anywhere.
- Single-basin production (5000 trials × 3 restarts) ≈ 13 min on this box.
  531 basins on 12 workers ≈ 10 h wall-clock.

This is NOT a substitute for the HPC sbatch — HPC must still run all three
models. This is just a local sanity check that produces real xaj_pdd
numbers ahead of HPC.

Usage:
    python -m src.xaj_global_pilot.scripts.run_local_xaj_pdd_full \\
        --workers 12

Resume support:
    Re-running with the default --skip-existing will skip basins whose
    per-basin csv already lives under
    results/.../camels_us_531_repro_v01/xaj_pdd/<basin>.csv.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
from concurrent.futures import ProcessPoolExecutor, as_completed
from pathlib import Path

import pandas as pd

_HERE = Path(__file__).resolve()
_REPO_ROOT = _HERE.parents[3]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from src.xaj_global_pilot.config import (  # noqa: E402
    DEFAULT_CALIBRATION_TRIALS,
    DEFAULT_RESTARTS,
    REPRO_FORCING,
    REPRO_VERSION,
    V02_FORCING,
    benchmark_results_dir,
    repro_split_periods,
    split_periods,
)


_PROTOCOL_DEFAULTS = {
    "v02": (V02_FORCING, split_periods, "test"),
    "repro_v01": (REPRO_FORCING, repro_split_periods, "evaluation"),
}


def _run_one(args_tuple):
    """Worker entrypoint — must be picklable, so it lives at module top level
    and re-imports its dependencies inside (Numba JIT will warm up per worker).
    """
    (basin_id, data_root, calibration_trials, n_restarts, protocol, forcing) = args_tuple
    # Per-worker import: avoids the parent process holding heavy state during fork
    from src.xaj_global_pilot.runner import run_single_model_basin

    t0 = time.time()
    result = run_single_model_basin(
        basin_id, "xaj_pdd",
        data_root=data_root,
        calibration_trials=calibration_trials,
        n_restarts=n_restarts,
        protocol=protocol,
        forcing=forcing,
    )
    result["_elapsed_s"] = round(time.time() - t0, 2)
    return result


def _read_basin_ids(manifest: Path) -> list[str]:
    return [line.strip().zfill(8) for line in manifest.read_text(encoding="utf-8").splitlines() if line.strip()]


def _build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--manifest",
                   default=str(_REPO_ROOT / "src" / "xaj_global_pilot" / "configs"
                               / "conceptual_benchmark_camels_us_531_repro.txt"))
    p.add_argument("--protocol", choices=tuple(_PROTOCOL_DEFAULTS), default="repro_v01")
    p.add_argument("--data-root", default="data/camels_us")
    p.add_argument("--workers", type=int, default=12,
                   help="Number of parallel processes. Defaults to 12 (8P+ a few HT/E threads on i9-13900K).")
    p.add_argument("--trials", type=int, default=DEFAULT_CALIBRATION_TRIALS)
    p.add_argument("--restarts", type=int, default=DEFAULT_RESTARTS)
    p.add_argument("--forcing", default=None,
                   help="Override forcing (default: derived from --protocol).")
    p.add_argument("--output-root", default=None,
                   help="Override results dir (default: results/.../camels_us_531_repro_v01).")
    p.add_argument("--skip-existing", dest="skip_existing", action="store_true", default=True)
    p.add_argument("--no-skip-existing", dest="skip_existing", action="store_false")
    p.add_argument("--limit", type=int, default=None,
                   help="Process only the first N basins (for quick subset runs).")
    return p


def main(argv=None) -> int:
    args = _build_parser().parse_args(argv)

    default_forcing, periods_fn, _ = _PROTOCOL_DEFAULTS[args.protocol]
    forcing = args.forcing or default_forcing
    periods = periods_fn()
    cal_key = "calibration" if args.protocol == "repro_v01" else "train"
    eval_key = "evaluation" if args.protocol == "repro_v01" else "test"

    manifest = Path(args.manifest)
    basins = _read_basin_ids(manifest)
    if args.limit is not None:
        basins = basins[: args.limit]

    output_root = Path(args.output_root) if args.output_root else benchmark_results_dir(REPRO_VERSION)
    model_dir = output_root / "xaj_pdd"
    summary_dir = output_root / "summary"
    model_dir.mkdir(parents=True, exist_ok=True)
    summary_dir.mkdir(parents=True, exist_ok=True)

    if args.skip_existing:
        todo = [b for b in basins if not (model_dir / f"{b}.csv").exists()]
        skipped = len(basins) - len(todo)
    else:
        todo = list(basins)
        skipped = 0

    print(f"[{time.strftime('%H:%M:%S')}] xaj_pdd local full run")
    print(f"  protocol      = {args.protocol}")
    print(f"  forcing       = {forcing}")
    print(f"  periods       = cal {periods[cal_key][0]}..{periods[cal_key][1]}, "
          f"eval {periods[eval_key][0]}..{periods[eval_key][1]}")
    print(f"  trials/restarts = {args.trials} / {args.restarts}")
    print(f"  workers       = {args.workers} (host has {os.cpu_count()} logical cores)")
    print(f"  manifest      = {manifest}")
    print(f"  output_root   = {output_root}")
    print(f"  basins total  = {len(basins)}, skipped (already done) = {skipped}, todo = {len(todo)}")

    if not todo:
        print("[INFO] Nothing to do — all basins already have a per-basin csv.")
        return 0

    work = [
        (b, args.data_root, args.trials, args.restarts, args.protocol, forcing)
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
                    "basin_id": basin_id, "model": "xaj_pdd", "period": eval_key,
                    "nse": None, "kge": None, "bias": None,
                    "peak_bias": None, "lowflow_bias": None,
                    "parameter_count": None, "solver_name": None, "family": "xaj",
                    "run_status": "failed", "error_message": f"worker exception: {exc}",
                    "_elapsed_s": None,
                }

            basin_id = result["basin_id"]
            pd.DataFrame([result]).to_csv(model_dir / f"{basin_id}.csv", index=False)
            rows.append(result)

            elapsed = time.time() - t_start
            eta_s = elapsed / i * (len(todo) - i) if i else 0.0
            nse_val = result.get("nse")
            nse_str = f"{nse_val:.3f}" if isinstance(nse_val, (int, float)) and nse_val is not None else "NA"
            print(f"[{time.strftime('%H:%M:%S')}] {i:4d}/{len(todo)} {basin_id} "
                  f"NSE={nse_str:>7} status={result['run_status']:<7} "
                  f"t={result.get('_elapsed_s', 0):.0f}s "
                  f"wall={elapsed/60:.1f}m ETA={eta_s/60:.0f}m",
                  flush=True)

    # Final summary — union everything that lives under model_dir, not just
    # this batch. Otherwise a resume / repair run with --skip-existing would
    # truncate the summary csv to just the few basins it executed.
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
    summary_csv = summary_dir / "xaj_pdd_local_full.csv"
    df.to_csv(summary_csv, index=False)

    metadata = {
        "protocol": args.protocol,
        "protocol_version": REPRO_VERSION,
        "model": "xaj_pdd",
        "forcing": forcing,
        "calibration_start": periods[cal_key][0],
        "calibration_end": periods[cal_key][1],
        "evaluation_start": periods[eval_key][0],
        "evaluation_end": periods[eval_key][1],
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
    }
    (summary_dir / "xaj_pdd_local_full.metadata.json").write_text(
        json.dumps(metadata, indent=2), encoding="utf-8",
    )

    success = df[df["run_status"] == "success"] if not df.empty else pd.DataFrame()
    failed = df[df["run_status"] == "failed"] if not df.empty else pd.DataFrame()
    print()
    print(f"=== DONE - this batch executed {len(todo)} basins ===")
    print(f"Wall (this batch): {(time.time() - t_start)/3600:.2f} h")
    print(f"Summary spans     : {len(df)} basin rows ({len(success)} success / {len(failed)} failed total)")
    if not success.empty and pd.notna(success["nse"]).any():
        s = pd.to_numeric(success["nse"], errors="coerce").dropna()
        print(f"NSE (all in summary) median={s.median():.4f}  mean={s.mean():.4f}  n={len(s)}")
    print(f"Summary CSV : {summary_csv}")
    print(f"Metadata    : {summary_dir / 'xaj_pdd_local_full.metadata.json'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

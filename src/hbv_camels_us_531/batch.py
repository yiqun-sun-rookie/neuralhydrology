import json
import statistics
import time
from concurrent.futures import ProcessPoolExecutor, as_completed
from pathlib import Path

import pandas as pd

from src.hbv_camels_us_531.config import (
    SUPERFLEXPY_COMMIT,
    SUPERFLEXPY_COMMIT_FULL,
    SUPERFLEXPY_DECLARED_VERSION,
    SUPERFLEXPY_DESCRIBE,
)
from src.hbv_camels_us_531.runner import run_single_basin


def summarize_results(results) -> dict:
    successful = [result for result in results if result.status == "ok" and result.test_nse is not None]
    test_nses = [result.test_nse for result in successful]

    return {
        "n_basins": len(results),
        "n_success": len(successful),
        "n_failed": len(results) - len(successful),
        "mean_test_nse": statistics.fmean(test_nses) if test_nses else None,
        "median_test_nse": statistics.median(test_nses) if test_nses else None,
        "n_test_ge_05": sum(1 for value in test_nses if value >= 0.5),
        "n_test_ge_06": sum(1 for value in test_nses if value >= 0.6),
        "n_primary": sum(1 for result in successful if result.bounds_profile == "primary"),
        "n_fallback": sum(1 for result in successful if result.bounds_profile == "fallback"),
    }


def _result_to_row(result) -> dict:
    return {
        "basin_id": result.basin_id,
        "train_nse": result.train_nse,
        "validation_nse": result.validation_nse,
        "test_nse": result.test_nse,
        "bounds_profile": result.bounds_profile,
        "status": result.status,
        "error": result.error,
        "best_params": json.dumps(result.best_params, sort_keys=True),
    }


def write_results(results, output_dir) -> None:
    output_path = Path(output_dir)
    output_path.mkdir(parents=True, exist_ok=True)

    basin_rows = [_result_to_row(result) for result in results]
    pd.DataFrame(basin_rows).to_csv(output_path / "basin_results.csv", index=False)

    summary = summarize_results(results)
    summary.update({
        "superflexpy_commit": SUPERFLEXPY_COMMIT,
        "superflexpy_commit_full": SUPERFLEXPY_COMMIT_FULL,
        "superflexpy_describe": SUPERFLEXPY_DESCRIBE,
        "superflexpy_declared_version": SUPERFLEXPY_DECLARED_VERSION,
    })
    pd.DataFrame([summary]).to_csv(output_path / "summary.csv", index=False)

    failed_rows = [row for row in basin_rows if row["status"] != "ok"]
    pd.DataFrame(failed_rows, columns=["basin_id", "status", "error"]).to_csv(
        output_path / "failed_basins.csv", index=False
    )


def load_basin_ids(basin_file) -> list[str]:
    path = Path(basin_file)
    return [line.strip() for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def _run_one(args):
    """Top-level wrapper for ProcessPoolExecutor (must be picklable)."""
    basin_id, data_root = args
    return run_single_basin(basin_id, data_root=data_root)


def run_basin_file(basin_file, data_root=None, output_dir=None, workers=1):
    basin_ids = load_basin_ids(basin_file)
    n = len(basin_ids)
    t0 = time.time()

    if workers <= 1:
        results = []
        for i, bid in enumerate(basin_ids):
            r = run_single_basin(bid, data_root=data_root)
            nse_str = f"{r.test_nse:.3f}" if r.test_nse is not None else "N/A"
            elapsed = time.time() - t0
            eta = elapsed / (i + 1) * (n - i - 1) / 60
            print(f"  [{i+1}/{n}] {bid}  test_nse={nse_str}  {r.status}  (ETA {eta:.0f}min)")
            results.append(r)
    else:
        results = [None] * n
        id_to_idx = {bid: i for i, bid in enumerate(basin_ids)}
        done = 0
        with ProcessPoolExecutor(max_workers=workers) as pool:
            futures = {pool.submit(_run_one, (bid, data_root)): bid for bid in basin_ids}
            for future in as_completed(futures):
                bid = futures[future]
                r = future.result()
                results[id_to_idx[bid]] = r
                done += 1
                nse_str = f"{r.test_nse:.3f}" if r.test_nse is not None else "N/A"
                elapsed = time.time() - t0
                eta = elapsed / done * (n - done) / 60
                print(f"  [{done}/{n}] {bid}  test_nse={nse_str}  {r.status}  (ETA {eta:.0f}min)")

    elapsed_total = (time.time() - t0) / 60
    print(f"\n[DONE] {n} basins in {elapsed_total:.1f} min ({elapsed_total/n:.1f} min/basin)")

    if output_dir is not None:
        write_results(results, output_dir)
    return results

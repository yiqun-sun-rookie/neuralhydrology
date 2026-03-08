import statistics
from pathlib import Path

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
    }


def load_basin_ids(basin_file) -> list[str]:
    path = Path(basin_file)
    return [line.strip() for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def run_basin_file(basin_file, data_root=None):
    basin_ids = load_basin_ids(basin_file)
    return [run_single_basin(basin_id, data_root=data_root) for basin_id in basin_ids]

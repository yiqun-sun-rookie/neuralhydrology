"""Merge chunk results from HPC array job into a single summary."""
import argparse
import statistics
from pathlib import Path

import pandas as pd


def merge(result_dir: str) -> None:
    root = Path(result_dir)
    chunk_dirs = sorted(root.glob("chunk_*"))
    if not chunk_dirs:
        print(f"[ERROR] No chunk_* directories found in {root}")
        return

    all_rows = []
    for d in chunk_dirs:
        csv = d / "basin_results.csv"
        if csv.exists():
            df = pd.read_csv(csv)
            all_rows.append(df)
            print(f"  {d.name}: {len(df)} basins")
        else:
            print(f"  {d.name}: MISSING basin_results.csv")

    if not all_rows:
        print("[ERROR] No basin_results.csv found in any chunk")
        return

    merged = pd.concat(all_rows, ignore_index=True)
    merged.to_csv(root / "basin_results.csv", index=False)

    ok = merged[merged["status"] == "ok"]
    nses = ok["test_nse"].dropna().tolist()
    summary = {
        "n_basins": len(merged),
        "n_success": len(ok),
        "n_failed": len(merged) - len(ok),
        "mean_test_nse": statistics.fmean(nses) if nses else None,
        "median_test_nse": statistics.median(nses) if nses else None,
        "n_test_ge_05": sum(1 for v in nses if v >= 0.5),
        "n_test_ge_06": sum(1 for v in nses if v >= 0.6),
        "n_test_ge_07": sum(1 for v in nses if v >= 0.7),
    }
    pd.DataFrame([summary]).to_csv(root / "summary.csv", index=False)

    failed = merged[merged["status"] != "ok"][["basin_id", "status", "error"]]
    failed.to_csv(root / "failed_basins.csv", index=False)

    print(f"\n[RESULT] {summary['n_success']}/{summary['n_basins']} succeeded")
    print(f"  Median test NSE: {summary['median_test_nse']:.3f}" if summary["median_test_nse"] else "  No valid results")
    print(f"  NSE >= 0.5: {summary['n_test_ge_05']}")
    print(f"  NSE >= 0.6: {summary['n_test_ge_06']}")
    print(f"  NSE >= 0.7: {summary['n_test_ge_07']}")
    print(f"\nOutput: {root / 'basin_results.csv'}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Merge HBV chunk results.")
    parser.add_argument("--result-dir", default="results/08_hbv_camels_us_531", help="Results root directory.")
    args = parser.parse_args()
    merge(args.result_dir)

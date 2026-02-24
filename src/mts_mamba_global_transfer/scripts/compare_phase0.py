"""Phase 0 结果提取与对比脚本.

Usage:
    python src/mts_mamba_global_transfer/scripts/compare_phase0.py \
        --lstm-dir results/41_mts_mamba_global_transfer/<lstm_run_dir> \
        --mamba-dir results/41_mts_mamba_global_transfer/<mamba_run_dir>
"""
import argparse
import pickle
import sys
from pathlib import Path


def load_test_results(run_dir: Path) -> dict:
    """Load test_results.p from the latest epoch directory."""
    test_dir = run_dir / "test"
    if not test_dir.exists():
        raise FileNotFoundError(f"No test/ directory in {run_dir}")
    epoch_dirs = sorted(test_dir.glob("model_epoch*"))
    if not epoch_dirs:
        raise FileNotFoundError(f"No model_epoch* directories in {test_dir}")
    results_file = epoch_dirs[-1] / "test_results.p"
    with open(results_file, "rb") as f:
        return pickle.load(f)


def extract_metrics(results: dict, freq: str = "1h") -> dict:
    """Extract per-basin metrics for a given frequency, return {basin: {metric: value}}."""
    metrics = {}
    for basin, freq_data in results.items():
        if freq in freq_data:
            xr_ds = freq_data[freq]["xr"]
            basin_metrics = {}
            for attr in ["NSE", "KGE", "Alpha-NSE", "Beta-NSE"]:
                val = xr_ds.attrs.get(attr)
                if val is not None:
                    basin_metrics[attr] = float(val)
            metrics[basin] = basin_metrics
    return metrics


def mean_metric(per_basin: dict, metric: str) -> float:
    """Compute mean of a metric across basins."""
    vals = [b[metric] for b in per_basin.values() if metric in b]
    return sum(vals) / len(vals) if vals else float("nan")


def main():
    parser = argparse.ArgumentParser(description="Phase 0: MTS-Mamba vs MTS-LSTM comparison")
    parser.add_argument("--lstm-dir", type=Path, required=True, help="MTS-LSTM run directory")
    parser.add_argument("--mamba-dir", type=Path, required=True, help="MTS-Mamba run directory")
    parser.add_argument("--threshold", type=float, default=0.95, help="Pass threshold (default: 0.95)")
    args = parser.parse_args()

    print("=" * 60)
    print("Phase 0: MTS-Mamba vs MTS-LSTM Comparison")
    print("=" * 60)

    lstm_results = load_test_results(args.lstm_dir)
    mamba_results = load_test_results(args.mamba_dir)

    lstm_hourly = extract_metrics(lstm_results, "1h")
    mamba_hourly = extract_metrics(mamba_results, "1h")

    print(f"\n{'Basin':<12} {'LSTM NSE':>10} {'Mamba NSE':>10} {'Ratio':>8}")
    print("-" * 44)
    for basin in sorted(lstm_hourly.keys()):
        lstm_nse = lstm_hourly[basin].get("NSE", float("nan"))
        mamba_nse = mamba_hourly.get(basin, {}).get("NSE", float("nan"))
        ratio = mamba_nse / lstm_nse if lstm_nse != 0 else float("nan")
        print(f"{basin:<12} {lstm_nse:>10.4f} {mamba_nse:>10.4f} {ratio:>8.4f}")

    lstm_mean = mean_metric(lstm_hourly, "NSE")
    mamba_mean = mean_metric(mamba_hourly, "NSE")
    ratio = mamba_mean / lstm_mean if lstm_mean != 0 else float("nan")

    print("-" * 44)
    print(f"{'Mean':<12} {lstm_mean:>10.4f} {mamba_mean:>10.4f} {ratio:>8.4f}")

    print(f"\nThreshold: {args.threshold}")
    passed = ratio >= args.threshold
    status = "PASSED" if passed else "FAILED"
    print(f"Result: {status} (ratio={ratio:.4f}, target>={args.threshold})")

    # KGE summary
    lstm_kge = mean_metric(lstm_hourly, "KGE")
    mamba_kge = mean_metric(mamba_hourly, "KGE")
    print(f"\nKGE: LSTM={lstm_kge:.4f}, Mamba={mamba_kge:.4f}")

    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())

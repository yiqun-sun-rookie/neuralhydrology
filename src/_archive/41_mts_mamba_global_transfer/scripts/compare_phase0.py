"""Phase 0 结果提取与对比脚本.

Usage (从项目根目录运行):
    python src/mts_mamba_global_transfer/scripts/compare_phase0.py \
        --lstm-dir results/41_mts_mamba_global_transfer/<lstm_run_dir> \
        --mamba-dir results/41_mts_mamba_global_transfer/<mamba_run_dir>

NeuralHydrology 结果文件结构 (pickle):
    results[basin][freq]['xr']         -- xarray.Dataset，含 obs/sim 时间序列
    results[basin][freq][metric_key]   -- float，指标值（顶层，不在 xr.attrs 中）
    当 use_frequencies 含多个频率时，键名带后缀：'NSE_1h'、'KGE_1h' 等。
    当只有单频率时，键名无后缀：'NSE'、'KGE' 等。
"""
import argparse
import pickle
import sys
from pathlib import Path


def load_test_results(run_dir: Path, period: str = "test") -> dict:
    """Load {period}_results.p from the latest epoch directory.

    Parameters
    ----------
    run_dir : Path
        Path to the run directory (e.g. results/41_.../41_mtslstm_...).
    period : str, optional
        Evaluation period, by default 'test'.

    Returns
    -------
    dict
        Nested dict: results[basin][freq][key].

    Raises
    ------
    FileNotFoundError
        If the period directory, epoch directories, or results file do not exist.
    """
    period_dir = run_dir / period
    if not period_dir.exists():
        raise FileNotFoundError(
            f"No {period}/ directory found in {run_dir}.\n"
            f"Available contents: {[p.name for p in run_dir.iterdir()] if run_dir.exists() else '(run_dir does not exist)'}"
        )

    epoch_dirs = sorted(period_dir.glob("model_epoch*"))
    if not epoch_dirs:
        raise FileNotFoundError(
            f"No model_epoch* directories found in {period_dir}.\n"
            f"Available contents: {[p.name for p in period_dir.iterdir()]}"
        )

    results_file = epoch_dirs[-1] / f"{period}_results.p"
    if not results_file.exists():
        available = [p.name for p in epoch_dirs[-1].iterdir()]
        raise FileNotFoundError(
            f"Results file not found: {results_file}\n"
            f"Available files in {epoch_dirs[-1]}: {available}"
        )

    with open(results_file, "rb") as f:
        return pickle.load(f)


def extract_metrics(results: dict, freq: str = "1h") -> dict:
    """Extract per-basin metrics for a given frequency.

    NeuralHydrology 将指标存储在 results[basin][freq][metric_key] 顶层。
    当 use_frequencies 包含多个频率时（如 [1D, 1h]），键名带频率后缀：
    'NSE_1h'、'KGE_1h'、'Alpha-NSE_1h'、'Beta-NSE_1h'。
    当只有单一频率时，键名无后缀：'NSE'、'KGE' 等。

    Parameters
    ----------
    results : dict
        Loaded results dict: results[basin][freq][key].
    freq : str, optional
        Frequency key to extract (e.g. '1h', '1D'), by default '1h'.

    Returns
    -------
    dict
        {basin: {'NSE': float, 'KGE': float, 'Alpha-NSE': float, 'Beta-NSE': float}}
    """
    base_metrics = ["NSE", "KGE", "Alpha-NSE", "Beta-NSE"]

    # Detect key naming convention from the first basin that has the target frequency
    use_suffix = None  # True = 'NSE_1h' style, False = 'NSE' style
    for basin, freq_data in results.items():
        if freq not in freq_data:
            continue
        available_keys = [k for k in freq_data[freq].keys() if k != "xr"]
        for base in base_metrics:
            if f"{base}_{freq}" in available_keys:
                use_suffix = True
                break
            if base in available_keys:
                use_suffix = False
                break
        if use_suffix is not None:
            break

    if use_suffix is None:
        # Could not detect — fall back to suffix style
        use_suffix = True

    metrics = {}
    for basin, freq_data in results.items():
        if freq not in freq_data:
            continue

        freq_entry = freq_data[freq]
        available_keys = [k for k in freq_entry.keys() if k != "xr"]

        basin_metrics = {}
        for base in base_metrics:
            key = f"{base}_{freq}" if use_suffix else base
            if key in freq_entry:
                basin_metrics[base] = float(freq_entry[key])

        if not basin_metrics:
            print(f"WARNING: Basin {basin}: no metrics found for freq='{freq}'. "
                  f"Available keys (excl. 'xr'): {available_keys}")

        metrics[basin] = basin_metrics

    return metrics


def mean_metric(per_basin: dict, metric: str) -> float:
    """Compute mean of a metric across basins, ignoring NaN."""
    vals = [b[metric] for b in per_basin.values() if metric in b and b[metric] == b[metric]]
    return sum(vals) / len(vals) if vals else float("nan")


def main():
    parser = argparse.ArgumentParser(description="Phase 0: MTS-Mamba vs MTS-LSTM comparison")
    parser.add_argument("--lstm-dir", type=Path, required=True, help="MTS-LSTM run directory")
    parser.add_argument("--mamba-dir", type=Path, required=True, help="MTS-Mamba run directory")
    parser.add_argument("--threshold", type=float, default=0.95, help="Pass threshold (default: 0.95)")
    parser.add_argument("--freq", type=str, default="1h", help="Frequency to compare (default: '1h')")
    parser.add_argument("--period", type=str, default="test", help="Evaluation period (default: 'test')")
    args = parser.parse_args()

    print("=" * 60)
    print("Phase 0: MTS-Mamba vs MTS-LSTM Comparison")
    print("=" * 60)

    lstm_results = load_test_results(args.lstm_dir, period=args.period)
    mamba_results = load_test_results(args.mamba_dir, period=args.period)

    # C2 mitigation: check basin set consistency
    lstm_basins = set(lstm_results.keys())
    mamba_basins = set(mamba_results.keys())
    if lstm_basins != mamba_basins:
        only_lstm = lstm_basins - mamba_basins
        only_mamba = mamba_basins - lstm_basins
        print(f"\nWARNING: Basin sets are inconsistent between the two models.")
        if only_lstm:
            print(f"  Basins only in LSTM  ({len(only_lstm)}): {sorted(only_lstm)}")
        if only_mamba:
            print(f"  Basins only in Mamba ({len(only_mamba)}): {sorted(only_mamba)}")
        print("  Missing basins will appear as NaN in the comparison.\n")

    lstm_hourly = extract_metrics(lstm_results, args.freq)
    mamba_hourly = extract_metrics(mamba_results, args.freq)

    print(f"\n{'Basin':<12} {'LSTM NSE':>10} {'Mamba NSE':>10} {'Ratio':>8}")
    print("-" * 44)
    for basin in sorted(lstm_hourly.keys()):
        lstm_nse = lstm_hourly[basin].get("NSE", float("nan"))
        mamba_nse = mamba_hourly.get(basin, {}).get("NSE", float("nan"))
        if lstm_nse != 0 and lstm_nse == lstm_nse:
            ratio = mamba_nse / lstm_nse
        else:
            ratio = float("nan")
        print(f"{basin:<12} {lstm_nse:>10.4f} {mamba_nse:>10.4f} {ratio:>8.4f}")

    lstm_mean = mean_metric(lstm_hourly, "NSE")
    mamba_mean = mean_metric(mamba_hourly, "NSE")

    if lstm_mean != 0 and lstm_mean == lstm_mean:
        ratio = mamba_mean / lstm_mean
    else:
        ratio = float("nan")

    print("-" * 44)

    # I1 mitigation: flag non-positive NSE
    nse_flag = ""
    if lstm_mean <= 0:
        nse_flag = "  (NSE<=0)"
    print(f"{'Mean':<12} {lstm_mean:>10.4f} {mamba_mean:>10.4f} {ratio:>8.4f}{nse_flag}")

    print(f"\nThreshold: {args.threshold}")
    passed = ratio >= args.threshold
    status = "PASSED" if passed else "FAILED"
    print(f"Result: {status} (ratio={ratio:.4f}, target>={args.threshold})")

    if lstm_mean <= 0:
        print("WARNING: NSE mean is non-positive, ratio interpretation may be misleading")

    # KGE summary
    lstm_kge = mean_metric(lstm_hourly, "KGE")
    mamba_kge = mean_metric(mamba_hourly, "KGE")
    print(f"\nKGE: LSTM={lstm_kge:.4f}, Mamba={mamba_kge:.4f}")

    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())

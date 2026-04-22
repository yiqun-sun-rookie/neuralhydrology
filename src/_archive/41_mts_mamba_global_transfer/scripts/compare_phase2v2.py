"""Phase 2v2 多模型对比脚本.

用法 (从项目根目录运行):
    python src/mts_mamba_global_transfer/scripts/compare_phase2v2.py \
        --run-dirs results/41_.../41_phase2v2_cudalstm_... \
                   results/41_.../41_phase2v2_ealstm_... \
                   results/41_.../41_phase2v2_mtslstm_...

支持单频率模型 (CudaLSTM, EALSTM — 键名无后缀: 'NSE') 和
多频率模型 (MTSLSTM, MTSMamba — 键名带后缀: 'NSE_1h')。
"""
import argparse
import pickle
import sys
from pathlib import Path


def load_test_results(run_dir: Path, period: str = "test") -> dict:
    """Load {period}_results.p from the latest epoch directory."""
    period_dir = run_dir / period
    if not period_dir.exists():
        raise FileNotFoundError(
            f"No {period}/ directory found in {run_dir}.\n"
            f"Available contents: {[p.name for p in run_dir.iterdir()] if run_dir.exists() else '(run_dir does not exist)'}"
        )

    epoch_dirs = sorted(period_dir.glob("model_epoch*"))
    if not epoch_dirs:
        raise FileNotFoundError(f"No model_epoch* directories found in {period_dir}.")

    results_file = epoch_dirs[-1] / f"{period}_results.p"
    if not results_file.exists():
        raise FileNotFoundError(f"Results file not found: {results_file}")

    with open(results_file, "rb") as f:
        return pickle.load(f)


def extract_metrics(results: dict, freq: str = "1h") -> dict:
    """Extract per-basin metrics for a given frequency.

    Handles both single-freq key naming ('NSE') and multi-freq ('NSE_1h').
    """
    base_metrics = ["NSE", "KGE", "Alpha-NSE", "Beta-NSE"]

    # Detect key naming convention from first basin with target frequency
    use_suffix = None
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
        use_suffix = True

    metrics = {}
    for basin, freq_data in results.items():
        if freq not in freq_data:
            continue
        freq_entry = freq_data[freq]
        basin_metrics = {}
        for base in base_metrics:
            key = f"{base}_{freq}" if use_suffix else base
            if key in freq_entry:
                basin_metrics[base] = float(freq_entry[key])
        metrics[basin] = basin_metrics

    return metrics


def mean_metric(per_basin: dict, metric: str) -> float:
    """Compute mean of a metric across basins, ignoring NaN."""
    vals = [b[metric] for b in per_basin.values() if metric in b and b[metric] == b[metric]]
    return sum(vals) / len(vals) if vals else float("nan")


def detect_model_name(run_dir: Path) -> str:
    """Infer model name from run directory name."""
    name = run_dir.name.lower()
    for model in ["cudalstm", "ealstm", "mtslstm", "mtsmamba"]:
        if model in name:
            return model.upper()
    return run_dir.name


def main():
    parser = argparse.ArgumentParser(description="Phase 2v2: Multi-model comparison (full forcing)")
    parser.add_argument("--run-dirs", type=Path, nargs="+", required=True, help="Run directories to compare")
    parser.add_argument("--freq", type=str, default="1h", help="Frequency to compare (default: '1h')")
    parser.add_argument("--period", type=str, default="test", help="Evaluation period (default: 'test')")
    args = parser.parse_args()

    models = {}
    for run_dir in args.run_dirs:
        model_name = detect_model_name(run_dir)
        results = load_test_results(run_dir, period=args.period)
        models[model_name] = extract_metrics(results, args.freq)

    model_names = list(models.keys())

    # --- Per-basin NSE table ---
    print("=" * 70)
    print(f"Phase 2v2 Multi-Model Comparison (freq={args.freq}, period={args.period})")
    print("=" * 70)

    header = f"{'Basin':<12}" + "".join(f" {m:>12}" for m in model_names)
    print(f"\n{header}")
    print("-" * len(header))

    all_basins = sorted(set().union(*(m.keys() for m in models.values())))
    for basin in all_basins:
        row = f"{basin:<12}"
        for m_name in model_names:
            nse = models[m_name].get(basin, {}).get("NSE", float("nan"))
            row += f" {nse:>12.4f}"
        print(row)

    # --- Mean summary ---
    print("-" * len(header))
    row = f"{'Mean':<12}"
    means_nse = {}
    for m_name in model_names:
        m = mean_metric(models[m_name], "NSE")
        means_nse[m_name] = m
        row += f" {m:>12.4f}"
    print(row)

    # --- KGE table ---
    print(f"\n{'Basin':<12}" + "".join(f" {m+' KGE':>12}" for m in model_names))
    print("-" * len(header))
    for basin in all_basins:
        row = f"{basin:<12}"
        for m_name in model_names:
            kge = models[m_name].get(basin, {}).get("KGE", float("nan"))
            row += f" {kge:>12.4f}"
        print(row)

    row = f"{'Mean':<12}"
    means_kge = {}
    for m_name in model_names:
        m = mean_metric(models[m_name], "KGE")
        means_kge[m_name] = m
        row += f" {m:>12.4f}"
    print("-" * len(header))
    print(row)

    # --- Compact summary ---
    print("\n" + "=" * 70)
    print("Summary (mean across basins)")
    print("=" * 70)
    print(f"{'Model':<12} {'NSE':>8} {'KGE':>8} {'Alpha-NSE':>10} {'Beta-NSE':>10}")
    print("-" * 52)
    for m_name in model_names:
        nse = means_nse[m_name]
        kge = means_kge[m_name]
        alpha = mean_metric(models[m_name], "Alpha-NSE")
        beta = mean_metric(models[m_name], "Beta-NSE")
        print(f"{m_name:<12} {nse:>8.4f} {kge:>8.4f} {alpha:>10.4f} {beta:>10.4f}")

    # --- Research questions ---
    print("\n" + "=" * 70)
    print("Research Questions")
    print("=" * 70)

    if "CUDALSTM" in means_nse and "EALSTM" in means_nse:
        diff = means_nse["EALSTM"] - means_nse["CUDALSTM"]
        winner = "EALSTM" if diff > 0 else "CUDALSTM"
        print(f"Q1 Static attributes: EALSTM - CudaLSTM = {diff:+.4f} NSE → {winner}")

    if "CUDALSTM" in means_nse and "MTSLSTM" in means_nse:
        diff = means_nse["MTSLSTM"] - means_nse["CUDALSTM"]
        winner = "MTSLSTM" if diff > 0 else "CUDALSTM"
        print(f"Q2 Multi-timescale:   MTSLSTM - CudaLSTM = {diff:+.4f} NSE → {winner}")

    if "MTSLSTM" in means_nse and "MTSMAMBA" in means_nse:
        diff = means_nse["MTSMAMBA"] - means_nse["MTSLSTM"]
        winner = "MTSMAMBA" if diff > 0 else "MTSLSTM"
        print(f"Q3 Mamba vs LSTM:     MTSMamba - MTSLSTM = {diff:+.4f} NSE → {winner}")

    return 0


if __name__ == "__main__":
    sys.exit(main())

"""Phase 2v3: Sequence Length Scaling — CudaLSTM vs Mamba.

用法 (从项目根目录运行):
    python src/mts_mamba_global_transfer/scripts/compare_seqscale.py

自动扫描 results/41_mts_mamba_global_transfer/ 下的 seqscale run dirs。
"""
import csv
import sys
from pathlib import Path

RESULTS_BASE = Path("results/41_mts_mamba_global_transfer")
MODELS = ["cudalstm", "mamba"]
SEQ_LENGTHS = [336, 720, 1440, 2160, 4320]


def find_run_dir(model: str, seq: int) -> Path | None:
    """Find the latest run dir matching the naming pattern."""
    pattern = f"41_seqscale_{model}_{seq}h_*"
    matches = sorted(RESULTS_BASE.glob(pattern))
    return matches[-1] if matches else None


def load_csv_metrics(run_dir: Path) -> dict[str, dict[str, float]]:
    """Load test_metrics.csv from the latest epoch."""
    test_dir = run_dir / "test"
    if not test_dir.exists():
        return {}
    epoch_dirs = sorted(test_dir.glob("model_epoch*"))
    if not epoch_dirs:
        return {}
    csv_path = epoch_dirs[-1] / "test_metrics.csv"
    if not csv_path.exists():
        return {}

    metrics = {}
    with open(csv_path) as f:
        reader = csv.DictReader(f)
        for row in reader:
            basin = row["basin"]
            # Handle both suffixed (NSE_1h) and plain (NSE) column names
            nse = float(row.get("NSE", row.get("NSE_1h", "nan")))
            kge = float(row.get("KGE", row.get("KGE_1h", "nan")))
            metrics[basin] = {"NSE": nse, "KGE": kge}
    return metrics


def mean_val(metrics: dict[str, dict[str, float]], key: str) -> float:
    vals = [m[key] for m in metrics.values() if key in m and m[key] == m[key]]
    return sum(vals) / len(vals) if vals else float("nan")


def main():
    # Collect results
    results = {}  # (model, seq) -> {"NSE": float, "KGE": float}
    missing = []

    for model in MODELS:
        for seq in SEQ_LENGTHS:
            run_dir = find_run_dir(model, seq)
            if run_dir is None:
                missing.append(f"{model}_{seq}h")
                continue
            metrics = load_csv_metrics(run_dir)
            if not metrics:
                missing.append(f"{model}_{seq}h (no metrics)")
                continue
            results[(model, seq)] = {
                "NSE": mean_val(metrics, "NSE"),
                "KGE": mean_val(metrics, "KGE"),
            }

    if missing:
        print(f"[WARN] Missing results: {', '.join(missing)}\n")

    # --- NSE Table ---
    print("=" * 60)
    print("Phase 2v3: Sequence Length Scaling — NSE (mean, 10 basins)")
    print("=" * 60)
    print(f"{'seq_length':>12} {'days':>6} {'CudaLSTM':>10} {'Mamba':>10} {'diff':>10}")
    print("-" * 52)

    for seq in SEQ_LENGTHS:
        days = seq // 24
        nse_lstm = results.get(("cudalstm", seq), {}).get("NSE", float("nan"))
        nse_mamba = results.get(("mamba", seq), {}).get("NSE", float("nan"))
        diff = nse_mamba - nse_lstm if nse_lstm == nse_lstm and nse_mamba == nse_mamba else float("nan")
        marker = " <-- Mamba wins" if diff == diff and diff > 0.01 else ""
        print(f"{seq:>10}h {days:>5}d {nse_lstm:>10.4f} {nse_mamba:>10.4f} {diff:>+10.4f}{marker}")

    # --- KGE Table ---
    print()
    print(f"{'seq_length':>12} {'days':>6} {'CudaLSTM':>10} {'Mamba':>10} {'diff':>10}")
    print("-" * 52)
    print("KGE:")

    for seq in SEQ_LENGTHS:
        days = seq // 24
        kge_lstm = results.get(("cudalstm", seq), {}).get("KGE", float("nan"))
        kge_mamba = results.get(("mamba", seq), {}).get("KGE", float("nan"))
        diff = kge_mamba - kge_lstm if kge_lstm == kge_lstm and kge_mamba == kge_mamba else float("nan")
        print(f"{seq:>10}h {days:>5}d {kge_lstm:>10.4f} {kge_mamba:>10.4f} {diff:>+10.4f}")

    # --- Crossover analysis ---
    print()
    print("=" * 60)
    print("Crossover Analysis")
    print("=" * 60)

    crossover_found = False
    prev_diff = None
    for seq in SEQ_LENGTHS:
        nse_lstm = results.get(("cudalstm", seq), {}).get("NSE", float("nan"))
        nse_mamba = results.get(("mamba", seq), {}).get("NSE", float("nan"))
        if nse_lstm != nse_lstm or nse_mamba != nse_mamba:
            continue
        diff = nse_mamba - nse_lstm
        if prev_diff is not None and prev_diff <= 0 < diff:
            print(f"Crossover detected between {prev_seq}h and {seq}h!")
            crossover_found = True
        prev_diff = diff
        prev_seq = seq

    if not crossover_found:
        if prev_diff is not None and prev_diff > 0:
            print("Mamba leads across all tested sequence lengths.")
        elif prev_diff is not None:
            print("No crossover found — LSTM leads across all tested lengths.")
            print("Consider extending to longer sequences (e.g., 8760h = 1 year).")
        else:
            print("Insufficient data for crossover analysis.")

    return 0


if __name__ == "__main__":
    sys.exit(main())

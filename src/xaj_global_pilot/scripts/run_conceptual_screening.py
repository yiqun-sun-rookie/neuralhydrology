import argparse
from pathlib import Path

import pandas as pd

from src.xaj_global_pilot.batch import run_pilot_batch
from src.xaj_global_pilot.config import SCREENING_VERSION
from src.xaj_global_pilot.reporting import summarize_ablation_deltas, summarize_win_counts


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Run the conceptual benchmark screening workflow.")
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--output-dir", default="results/10_global_conceptual_model_benchmark")
    parser.add_argument("--output-version", default=SCREENING_VERSION)
    parser.add_argument("--data-root", default=None)
    parser.add_argument("--trials", type=int, default=5000)
    parser.add_argument("--primary-only", action="store_true")
    parser.add_argument("--include-ablations", action="store_true")
    return parser


def main(argv=None) -> int:
    args = build_parser().parse_args(argv)
    include_ablations = args.include_ablations or not args.primary_only

    output_dir = Path(args.output_dir) / args.output_version
    all_metrics, by_regime = run_pilot_batch(
        selected_basins_csv=args.manifest,
        output_dir=output_dir,
        data_root=args.data_root,
        calibration_trials=args.trials,
        include_ablations=include_ablations,
    )

    summary_dir = output_dir / "summary"
    summary_dir.mkdir(parents=True, exist_ok=True)
    all_metrics.to_csv(summary_dir / "all_basins_metrics.csv", index=False)
    by_regime.to_csv(summary_dir / "by_regime_metrics.csv", index=False)

    summarize_win_counts(all_metrics).to_csv(summary_dir / "win_counts.csv", index=False)
    summarize_ablation_deltas(all_metrics).to_csv(summary_dir / "ablation_deltas.csv", index=False)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

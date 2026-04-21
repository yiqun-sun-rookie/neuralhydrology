import argparse
import json
from pathlib import Path

import pandas as pd

from src.xaj_global_pilot.config import SCREENING_VERSION, benchmark_summary_dir
from src.xaj_global_pilot.reporting import summarize_best_model_by_basin, summarize_by_regime, summarize_overall_metrics


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Export paper-facing summary tables from conceptual benchmark raw outputs.")
    parser.add_argument("--summary-dir", default=str(benchmark_summary_dir(SCREENING_VERSION)))
    parser.add_argument("--output-dir", required=True)
    return parser


def main(argv=None) -> int:
    args = build_parser().parse_args(argv)
    summary_dir = Path(args.summary_dir)
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    all_metrics = pd.read_csv(summary_dir / "all_basins_metrics.csv", dtype={"basin_id": str})
    overall = summarize_overall_metrics(all_metrics)
    by_regime = summarize_by_regime(all_metrics)
    best_by_basin = summarize_best_model_by_basin(all_metrics)

    efficiency = overall.copy(deep=True)
    counts = pd.to_numeric(efficiency["parameter_count"], errors="coerce")
    efficiency["median_nse_per_parameter"] = (pd.to_numeric(efficiency["median_nse"], errors="coerce") / counts).round(6)
    efficiency["median_kge_per_parameter"] = (pd.to_numeric(efficiency["median_kge"], errors="coerce") / counts).round(6)

    overall.to_csv(output_dir / "table_overall_metrics.csv", index=False)
    by_regime.to_csv(output_dir / "table_by_regime_metrics.csv", index=False)
    efficiency.to_csv(output_dir / "table_parameter_efficiency.csv", index=False)
    best_by_basin.to_csv(output_dir / "table_best_model_by_basin.csv", index=False)

    manifest = {
        "table_overall_metrics": "table_overall_metrics.csv",
        "table_by_regime_metrics": "table_by_regime_metrics.csv",
        "table_parameter_efficiency": "table_parameter_efficiency.csv",
        "table_best_model_by_basin": "table_best_model_by_basin.csv",
    }
    (output_dir / "figure_manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

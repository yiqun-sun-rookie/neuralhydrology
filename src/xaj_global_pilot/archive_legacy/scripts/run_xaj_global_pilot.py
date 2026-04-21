import argparse

import pandas as pd

from src.xaj_global_pilot.batch import run_pilot_batch
from src.xaj_global_pilot.metadata_sources import load_caravan_candidate_metadata
from src.xaj_global_pilot.reporting import summarize_by_regime
from src.xaj_global_pilot.registry import build_basin_registry
from src.xaj_global_pilot.selection import select_pilot_basins


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Run XAJ global pilot metadata workflows.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    build_registry = subparsers.add_parser("build-registry", help="Build basin_registry.csv from candidate metadata.")
    build_registry_inputs = build_registry.add_mutually_exclusive_group(required=True)
    build_registry_inputs.add_argument("--input-csv")
    build_registry_inputs.add_argument("--caravan-root")
    build_registry.add_argument("--output-csv", required=True)
    build_registry.set_defaults(handler=_handle_build_registry)

    select_basins = subparsers.add_parser("select-basins", help="Select the final pilot basin list.")
    select_basins.add_argument("--registry-csv", required=True)
    select_basins.add_argument("--output-csv", required=True)
    select_basins.set_defaults(handler=_handle_select_basins)

    summarize_metrics = subparsers.add_parser("summarize-metrics", help="Summarize per-basin metrics by regime.")
    summarize_metrics.add_argument("--metrics-csv", required=True)
    summarize_metrics.add_argument("--output-csv", required=True)
    summarize_metrics.set_defaults(handler=_handle_summarize_metrics)

    run_pilot = subparsers.add_parser("run-pilot", help="Run the three-model pilot batch.")
    run_pilot.add_argument("--selected-basins-csv", required=True)
    run_pilot.add_argument("--output-dir", required=True)
    run_pilot.add_argument("--data-root", default=None)
    run_pilot.add_argument("--calibration-trials", type=int, default=200)
    run_pilot.set_defaults(handler=_handle_run_pilot)

    return parser


def main(argv=None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.handler(args)


def _handle_build_registry(args: argparse.Namespace) -> int:
    if args.input_csv:
        candidates = pd.read_csv(args.input_csv)
    else:
        candidates = load_caravan_candidate_metadata(args.caravan_root)
    registry = build_basin_registry(candidates)
    registry.to_csv(args.output_csv, index=False)
    return 0


def _handle_select_basins(args: argparse.Namespace) -> int:
    registry = pd.read_csv(args.registry_csv)
    selected = select_pilot_basins(registry)
    selected.to_csv(args.output_csv, index=False)
    return 0


def _handle_summarize_metrics(args: argparse.Namespace) -> int:
    metrics = pd.read_csv(args.metrics_csv)
    summary = summarize_by_regime(metrics)
    summary.to_csv(args.output_csv, index=False)
    return 0


def _handle_run_pilot(args: argparse.Namespace) -> int:
    run_pilot_batch(
        selected_basins_csv=args.selected_basins_csv,
        output_dir=args.output_dir,
        data_root=args.data_root,
        calibration_trials=args.calibration_trials,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

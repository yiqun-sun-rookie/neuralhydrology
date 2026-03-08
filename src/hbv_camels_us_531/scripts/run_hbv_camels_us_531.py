import argparse

from src.hbv_camels_us_531.batch import run_basin_file
from src.hbv_camels_us_531.runner import run_single_basin


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Run fixed-structure HBV baseline on CAMELS-US basins.")
    parser.add_argument("--basin-id", type=str, default=None, help="Single CAMELS-US basin id.")
    parser.add_argument("--basin-file", type=str, default=None, help="File with one basin id per line.")
    parser.add_argument("--data-root", type=str, default=None, help="Override CAMELS-US data root.")
    parser.add_argument("--output-dir", type=str, default="results/07_hbv_camels_us_531", help="Output directory.")
    return parser


def run_from_args(args):
    if args.basin_id:
        return run_single_basin(args.basin_id, data_root=args.data_root)
    if args.basin_file:
        return run_basin_file(args.basin_file, data_root=args.data_root)
    raise ValueError("Either --basin-id or --basin-file must be provided.")


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()
    run_from_args(args)


if __name__ == "__main__":
    main()

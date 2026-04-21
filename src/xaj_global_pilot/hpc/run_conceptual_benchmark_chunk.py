import argparse
import json
from pathlib import Path

import pandas as pd

from src.xaj_global_pilot.config import DEFAULT_CALIBRATION_TRIALS, DEFAULT_RESTARTS, FULL_VERSION, benchmark_results_dir
from src.xaj_global_pilot.model_catalog import get_model_specs
from src.xaj_global_pilot.runner import run_single_model_basin


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Run one model on one CAMELS-US chunk manifest.")
    parser.add_argument("--model", choices=tuple(get_model_specs()["primary"].keys()), required=True)
    parser.add_argument("--chunk-file", required=True)
    parser.add_argument("--output-dir", default=str(benchmark_results_dir(FULL_VERSION)))
    parser.add_argument("--data-root", default="data/camels_us")
    parser.add_argument("--trials", type=int, default=DEFAULT_CALIBRATION_TRIALS)
    parser.add_argument("--restarts", type=int, default=DEFAULT_RESTARTS)
    parser.add_argument("--skip-existing", action="store_true")
    return parser


def read_chunk_file(path: str | Path) -> list[str]:
    return [line.strip().zfill(8) for line in Path(path).read_text(encoding="utf-8").splitlines() if line.strip()]


def main(argv=None) -> int:
    args = build_parser().parse_args(argv)

    basin_ids = read_chunk_file(args.chunk_file)
    output_dir = Path(args.output_dir)
    summary_dir = output_dir / "summary"
    model_dir = output_dir / args.model
    summary_dir.mkdir(parents=True, exist_ok=True)
    model_dir.mkdir(parents=True, exist_ok=True)

    rows = []
    n_skipped_existing = 0
    n_executed = 0
    for basin_id in basin_ids:
        basin_output_path = model_dir / f"{basin_id}.csv"
        if args.skip_existing and basin_output_path.exists():
            result = pd.read_csv(basin_output_path, dtype={"basin_id": str}, keep_default_na=False).iloc[0].to_dict()
            n_skipped_existing += 1
        else:
            result = run_single_model_basin(
                basin_id,
                args.model,
                data_root=args.data_root,
                calibration_trials=args.trials,
            )
            n_executed += 1
        rows.append(result)
        pd.DataFrame([result]).to_csv(basin_output_path, index=False)

    rows_df = pd.DataFrame(rows)
    if not rows_df.empty:
        rows_df["basin_id"] = rows_df["basin_id"].astype(str).str.zfill(8)
        rows_df = rows_df.sort_values(["basin_id", "model"]).reset_index(drop=True)

    chunk_stem = Path(args.chunk_file).stem
    rows_df.to_csv(summary_dir / f"{args.model}_{chunk_stem}.csv", index=False)
    metadata = {
        "model": args.model,
        "chunk_file": str(Path(args.chunk_file)),
        "trials": args.trials,
        "restarts": args.restarts,
        "n_basins": len(basin_ids),
        "n_skipped_existing": n_skipped_existing,
        "n_executed": n_executed,
        "data_root": args.data_root,
        "output_dir": str(output_dir),
        "skip_existing": args.skip_existing,
    }
    (summary_dir / f"{args.model}_{chunk_stem}.metadata.json").write_text(
        json.dumps(metadata, indent=2),
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

import argparse
import json
from pathlib import Path

import pandas as pd

from src.xaj_global_pilot.config import FULL_VERSION, benchmark_results_dir, benchmark_configs_dir
from src.xaj_global_pilot.hpc.build_conceptual_benchmark_chunks import read_basin_ids
from src.xaj_global_pilot.model_catalog import get_model_specs


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Validate chunk manifests before launching the CAMELS-US 531 benchmark.")
    parser.add_argument(
        "--manifest",
        default=str(benchmark_configs_dir() / "conceptual_benchmark_camels_us_531.txt"),
    )
    parser.add_argument(
        "--output-dir",
        default=str(benchmark_results_dir(FULL_VERSION)),
    )
    return parser


def main(argv=None) -> int:
    args = build_parser().parse_args(argv)
    manifest_ids = read_basin_ids(args.manifest)
    output_dir = Path(args.output_dir)
    chunks_dir = output_dir / "chunks"
    chunk_index_path = output_dir / "chunk_index.csv"
    if chunk_index_path.exists():
        chunk_index = pd.read_csv(chunk_index_path)
        chunk_files = [chunks_dir / name for name in chunk_index["chunk_file"].tolist()]
    else:
        chunk_files = sorted(chunks_dir.glob("chunk_*.txt"))
    chunk_ids = []
    for chunk_file in chunk_files:
        chunk_ids.extend(read_basin_ids(chunk_file))

    manifest_set = set(manifest_ids)
    chunk_set = set(chunk_ids)
    duplicates = len(chunk_ids) - len(chunk_set)
    missing = sorted(manifest_set - chunk_set)
    unexpected = sorted(chunk_set - manifest_set)

    report = {
        "n_manifest_basins": len(manifest_ids),
        "n_chunk_files": len(chunk_files),
        "n_chunk_entries": len(chunk_ids),
        "n_unique_chunk_basins": len(chunk_set),
        "n_missing_basins": len(missing),
        "n_unexpected_basins": len(unexpected),
        "n_duplicate_basins": duplicates,
        "missing_basins_preview": missing[:10],
        "unexpected_basins_preview": unexpected[:10],
        "primary_models": list(get_model_specs()["primary"].keys()),
    }
    (output_dir / "preflight_report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")

    if missing or unexpected or duplicates:
        raise SystemExit("Preflight failed: chunk manifests do not match the canonical basin list.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

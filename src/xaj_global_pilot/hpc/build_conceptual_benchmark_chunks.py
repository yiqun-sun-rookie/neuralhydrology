import argparse
from pathlib import Path

import pandas as pd

from src.xaj_global_pilot.config import FULL_VERSION, benchmark_results_dir, benchmark_summary_dir, benchmark_configs_dir
from src.xaj_global_pilot.model_catalog import get_model_specs


DEFAULT_CHUNK_SIZE = 50


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Build deterministic chunk manifests for the CAMELS-US 531 benchmark.")
    parser.add_argument(
        "--manifest",
        default=str(benchmark_configs_dir() / "conceptual_benchmark_camels_us_531.txt"),
    )
    parser.add_argument(
        "--output-dir",
        default=str(benchmark_results_dir(FULL_VERSION)),
    )
    parser.add_argument("--chunk-size", type=int, default=DEFAULT_CHUNK_SIZE)
    parser.add_argument("--allow-scale-up", action="store_true")
    parser.add_argument(
        "--verdict-file",
        default=str(benchmark_summary_dir() / "go_no_go_summary.md"),
    )
    return parser


def read_basin_ids(manifest_path: str | Path) -> list[str]:
    path = Path(manifest_path)
    basin_ids = [line.strip() for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
    return sorted({basin_id.zfill(8) for basin_id in basin_ids})


def has_positive_screening_verdict(verdict_path: str | Path) -> bool:
    path = Path(verdict_path)
    if not path.exists():
        return False
    text = path.read_text(encoding="utf-8")
    return "Conditional Go" in text or "Go" in text


def write_chunk_files(basin_ids: list[str], chunk_size: int, output_dir: str | Path) -> pd.DataFrame:
    if chunk_size <= 0:
        raise ValueError("chunk_size must be positive")

    root = Path(output_dir)
    chunks_dir = root / "chunks"
    chunks_dir.mkdir(parents=True, exist_ok=True)

    chunk_rows = []
    for index, start in enumerate(range(0, len(basin_ids), chunk_size), start=1):
        chunk_ids = basin_ids[start:start + chunk_size]
        chunk_name = f"chunk_{index:03d}.txt"
        (chunks_dir / chunk_name).write_text("".join(f"{basin_id}\n" for basin_id in chunk_ids), encoding="utf-8")
        chunk_rows.append(
            {
                "chunk_id": index,
                "chunk_file": chunk_name,
                "n_basins": len(chunk_ids),
                "models": ",".join(get_model_specs()["primary"].keys()),
            }
        )

    index_df = pd.DataFrame(chunk_rows)
    index_df.to_csv(root / "chunk_index.csv", index=False)
    return index_df


def main(argv=None) -> int:
    args = build_parser().parse_args(argv)
    if not args.allow_scale_up and not has_positive_screening_verdict(args.verdict_file):
        raise SystemExit(
            "Scale-up is disabled until screening is Go/Conditional Go. "
            "Pass --allow-scale-up to build chunks explicitly."
        )

    basin_ids = read_basin_ids(args.manifest)
    write_chunk_files(basin_ids, args.chunk_size, args.output_dir)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())


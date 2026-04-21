import argparse
from pathlib import Path

import pandas as pd

from src.xaj_global_pilot.config import FULL_VERSION, benchmark_results_dir, benchmark_configs_dir
from src.xaj_global_pilot.model_catalog import get_model_specs
from src.xaj_global_pilot.reporting import summarize_by_regime, summarize_win_counts


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Aggregate per-basin 531-benchmark outputs into paper-ready summary tables.")
    parser.add_argument(
        "--manifest",
        default=str(benchmark_configs_dir() / "conceptual_benchmark_camels_us_531.txt"),
    )
    parser.add_argument(
        "--output-dir",
        default=str(benchmark_results_dir(FULL_VERSION)),
    )
    return parser


def read_manifest(path: str | Path) -> pd.DataFrame:
    manifest_path = Path(path)
    if manifest_path.suffix.lower() == ".csv":
        manifest = pd.read_csv(manifest_path, dtype={"basin_id": str})
        if "regime" not in manifest.columns:
            manifest["regime"] = "unknown"
        return manifest[["basin_id", "regime"]].assign(basin_id=lambda df: df["basin_id"].astype(str).str.zfill(8))

    basin_ids = [line.strip().zfill(8) for line in manifest_path.read_text(encoding="utf-8").splitlines() if line.strip()]
    return pd.DataFrame({"basin_id": sorted(set(basin_ids)), "regime": "unknown"})


def build_completeness_table(manifest: pd.DataFrame, all_metrics: pd.DataFrame) -> pd.DataFrame:
    expected = manifest.assign(key=1).merge(
        pd.DataFrame({"model": list(get_model_specs()["primary"].keys()), "key": 1}),
        on="key",
    ).drop(columns=["key"])
    observed = all_metrics[["basin_id", "model"]].drop_duplicates()
    merged = expected.merge(observed.assign(found=True), on=["basin_id", "model"], how="left")
    completeness = (
        merged.groupby("model", as_index=False)["found"]
        .agg(
            n_expected="size",
            n_found=lambda s: int(s.fillna(False).sum()),
            n_missing=lambda s: int((~s.fillna(False)).sum()),
        )
        .sort_values("model")
        .reset_index(drop=True)
    )
    return completeness


def main(argv=None) -> int:
    args = build_parser().parse_args(argv)
    output_dir = Path(args.output_dir)
    summary_dir = output_dir / "summary"
    summary_dir.mkdir(parents=True, exist_ok=True)

    manifest = read_manifest(args.manifest)
    rows = []
    for model in get_model_specs()["primary"].keys():
        model_dir = output_dir / model
        for basin_id in manifest["basin_id"].tolist():
            basin_path = model_dir / f"{basin_id}.csv"
            if basin_path.exists():
                rows.append(pd.read_csv(basin_path, dtype={"basin_id": str}, keep_default_na=False))

    all_metrics = pd.concat(rows, ignore_index=True) if rows else pd.DataFrame(columns=["basin_id", "model"])
    if not all_metrics.empty:
        all_metrics["basin_id"] = all_metrics["basin_id"].astype(str).str.zfill(8)
        all_metrics = manifest.merge(all_metrics, on="basin_id", how="left")
        all_metrics = all_metrics.sort_values(["basin_id", "model"]).reset_index(drop=True)
    else:
        all_metrics = manifest.assign(model=pd.NA)

    all_metrics.to_csv(summary_dir / "all_basins_metrics.csv", index=False)
    summarize_by_regime(all_metrics).to_csv(summary_dir / "by_regime_metrics.csv", index=False)
    summarize_win_counts(all_metrics).to_csv(summary_dir / "win_counts.csv", index=False)
    build_completeness_table(manifest, all_metrics).to_csv(summary_dir / "completeness_check.csv", index=False)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

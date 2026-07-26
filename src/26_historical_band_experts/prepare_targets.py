"""Trusted one-way preparation of supervised targets for the v02 pilot."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
from typing import Callable, Sequence

import numpy as np
import pandas as pd


TRAIN_START = pd.Timestamp("1999-10-01")
VALIDATION_END = pd.Timestamp("2008-09-30")
FORMAL_START = pd.Timestamp("1989-10-01")
FORMAL_END = pd.Timestamp("1999-09-30")


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _atomic_frame(path: Path, frame: pd.DataFrame) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    frame.to_csv(temporary, index=False)
    os.replace(temporary, path)


def _atomic_text(path: Path, text: str) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(text, encoding="utf-8")
    os.replace(temporary, path)


def prepare_target_bundle(
    basins: Sequence[str],
    basin_file: str | Path,
    output_path: str | Path,
    load_one: Callable[[str], pd.Series],
) -> dict:
    """Write only allowed target dates; never return or print protected observations."""
    output_path = Path(output_path)
    manifest_path = output_path.with_suffix(".manifest.json")
    if output_path.exists() or manifest_path.exists():
        raise FileExistsError(f"target bundle or manifest already exists: {output_path}")
    basin_ids = tuple(str(basin).zfill(8) for basin in basins)
    if not basin_ids or len(set(basin_ids)) != len(basin_ids):
        raise ValueError("basin identifiers must be nonempty and unique")
    allowed_dates = pd.date_range(TRAIN_START, VALIDATION_END, freq="D")
    frames = []
    for basin in basin_ids:
        series = load_one(basin)
        if not isinstance(series, pd.Series):
            raise TypeError("load_one must return a pandas Series")
        series = series.copy()
        series.index = pd.to_datetime(series.index)
        selected = pd.to_numeric(series.reindex(allowed_dates), errors="coerce")
        values = selected.to_numpy(dtype=np.float64)
        if not np.isfinite(values).all() or np.any(values < 0):
            raise ValueError(f"allowed target window is incomplete for basin {basin}")
        frames.append(pd.DataFrame({
            "basin": basin,
            "date": allowed_dates.strftime("%Y-%m-%d"),
            "qobs": values,
        }))

    targets = pd.concat(frames, ignore_index=True)
    targets = targets.sort_values(["basin", "date"]).reset_index(drop=True)
    output_path = Path(output_path)
    basin_file = Path(basin_file)
    _atomic_frame(output_path, targets)
    emitted_dates = pd.to_datetime(targets["date"])
    manifest = {
        "status": "complete",
        "basin_count": len(basin_ids),
        "row_count": len(targets),
        "minimum_date": str(emitted_dates.min().date()),
        "maximum_date": str(emitted_dates.max().date()),
        "basin_file_sha256": _sha256(basin_file),
        "target_bundle_sha256": _sha256(output_path),
        "formal_evaluation_rows_emitted": int(
            ((emitted_dates >= FORMAL_START) & (emitted_dates <= FORMAL_END)).sum()
        ),
        "trusted_raw_streamflow_files_read": len(basin_ids),
        "candidate_raw_streamflow_files_read": 0,
    }
    manifest_path = output_path.with_suffix(".manifest.json")
    _atomic_text(manifest_path, json.dumps(manifest, indent=2, sort_keys=True))
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--data-dir", type=Path, required=True)
    parser.add_argument("--basin-file", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()

    from neuralhydrology.datasetzoo.camelsus import (
        load_camels_us_discharge,
        load_camels_us_forcings,
    )

    basins = tuple(
        line.strip().zfill(8)
        for line in args.basin_file.read_text(encoding="utf-8").splitlines()
        if line.strip()
    )

    def load_one(basin: str) -> pd.Series:
        _forcing, area = load_camels_us_forcings(args.data_dir, basin, "maurer")
        return load_camels_us_discharge(args.data_dir, basin, area)

    manifest = prepare_target_bundle(
        basins=basins,
        basin_file=args.basin_file,
        output_path=args.out,
        load_one=load_one,
    )
    print(json.dumps(manifest, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()

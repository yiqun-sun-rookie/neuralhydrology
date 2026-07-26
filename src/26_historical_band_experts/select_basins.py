"""Deterministically freeze a static-attribute coverage sample of basins."""
from __future__ import annotations

import argparse
from pathlib import Path
from typing import Sequence

import numpy as np
import pandas as pd

from data import DEFAULT_STATICS_FILE, STATIC_COLUMNS


_REPO = Path(__file__).resolve().parents[2]
DEFAULT_BASINS_FILE = _REPO / "src/fair_benchmark/frozen/track0_forcing_only_basins.txt"


def farthest_point_basin_selection(
    frame: pd.DataFrame,
    count: int,
    feature_columns: Sequence[str],
) -> list[str]:
    """Select deterministic static-space coverage without observed discharge."""
    if count <= 0 or count > len(frame):
        raise ValueError("count must be between one and the number of rows")
    work = frame.loc[:, ["gauge_id", *feature_columns]].copy()
    work["gauge_id"] = work["gauge_id"].astype(str).str.zfill(8)
    work = work.sort_values("gauge_id").reset_index(drop=True)
    features = work.loc[:, feature_columns].to_numpy(dtype=np.float64)
    medians = np.nanmedian(features, axis=0)
    missing = np.where(np.isnan(features))
    features[missing] = medians[missing[1]]
    center = features.mean(axis=0)
    scale = features.std(axis=0)
    scale[scale < 1e-12] = 1.0
    normalized = (features - center) / scale

    centroid_distance = np.square(normalized).sum(axis=1)
    selected = [int(np.argmin(centroid_distance))]
    minimum_distance = np.square(normalized - normalized[selected[0]]).sum(axis=1)
    minimum_distance[selected[0]] = -np.inf
    while len(selected) < count:
        next_index = int(np.argmax(minimum_distance))
        selected.append(next_index)
        distance = np.square(normalized - normalized[next_index]).sum(axis=1)
        minimum_distance = np.minimum(minimum_distance, distance)
        minimum_distance[selected] = -np.inf
    return work.loc[selected, "gauge_id"].tolist()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--count", type=int, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--statics-file", type=Path, default=DEFAULT_STATICS_FILE)
    parser.add_argument("--basins-file", type=Path, default=DEFAULT_BASINS_FILE)
    args = parser.parse_args()

    allowed = {
        line.strip().zfill(8)
        for line in args.basins_file.read_text(encoding="utf-8").splitlines()
        if line.strip()
    }
    frame = pd.read_csv(args.statics_file, dtype={"gauge_id": str})
    frame["gauge_id"] = frame["gauge_id"].str.zfill(8)
    frame = frame[frame["gauge_id"].isin(allowed)].copy()
    selected = farthest_point_basin_selection(frame, args.count, STATIC_COLUMNS)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text("\n".join(selected) + "\n", encoding="utf-8")
    print(f"selected={len(selected)} out={args.out}")


if __name__ == "__main__":
    main()

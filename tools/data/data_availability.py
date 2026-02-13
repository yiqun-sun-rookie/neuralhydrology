"""Quick data availability audit for CAMELS-US basins.

Scans discharge (QObs(mm/d)) for each basin in a provided basin list (or all in list files),
computes:
  - total points in requested date window
  - valid (non-NaN) count
  - NaN ratio
  - zero variance flag (std == 0 or valid_count < 2)
  - start/end date of valid data (within window)
  - mean / std
Outputs a CSV + pretty table + summary stats.

Usage (examples):
  python data_availability.py --data-dir data/CAMELS_US \
      --basin-file examples/01-Introduction/full_674_basins_train_basins.txt \
      --start 1999-10-01 --end 2008-09-30 --out report_train.csv

  # Merge train/val/test
  python data_availability.py --data-dir data/CAMELS_US \
      --basin-file examples/01-Introduction/full_674_basins_train_basins.txt \
      --basin-file examples/01-Introduction/full_674_basins_val_basins.txt \
      --basin-file examples/01-Introduction/full_674_basins_test_basins.txt \
      --start 1999-10-01 --end 2008-09-30 --out report_all.csv

Interpretation:
  - Basins with zero_variance == True 或者 nan_ratio 高 -> NSE 分母为 0 或近 0，NSE 会是 NaN。
  - 可直接过滤这些流域，或调整时间窗/数据处理策略。
"""
from __future__ import annotations

import argparse
import csv
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional, Dict

import pandas as pd

TARGET_COL = "QObs(mm/d)"
RAW_VALUE_COL = "qobs_raw"


@dataclass
class BasinStats:
    basin: str
    points_total: int
    valid_count: int
    nan_ratio: float
    zero_variance: bool
    mean: Optional[float]
    std: Optional[float]
    window_start: str
    window_end: str
    first_valid: Optional[str]
    last_valid: Optional[str]

    def to_row(self):
        return [
            self.basin,
            self.points_total,
            self.valid_count,
            f"{self.nan_ratio:.3f}",
            int(self.zero_variance),
            f"{self.mean:.4f}" if self.mean is not None else "",
            f"{self.std:.4f}" if self.std is not None else "",
            self.window_start,
            self.window_end,
            self.first_valid or "",
            self.last_valid or "",
        ]


def read_basin_list(path: Path) -> List[str]:
    basins = []
    with path.open() as f:
        for line in f:
            line = line.strip()
            if line:
                basins.append(line)
    return basins


def build_streamflow_index(data_dir: Path) -> Dict[str, Path]:
    base = data_dir / "usgs_streamflow"
    mapping: Dict[str, Path] = {}
    for p in base.rglob("*_streamflow_qc.txt"):
        name = p.name
        gauge = name.split('_')[0]
        mapping[gauge] = p
    return mapping


def load_discharge_file(index: Dict[str, Path], basin: str) -> pd.DataFrame:
    """Load discharge for a basin using pre-built index."""
    path = index.get(basin)
    if path is None:
        raise FileNotFoundError(f"No indexed file for basin {basin}")
    raw = pd.read_csv(path, sep="\s+", header=None)
    if raw.shape[1] < 6:
        raise RuntimeError(f"Unexpected column count {raw.shape[1]} in {path}")
    raw.columns = ["gauge", "year", "month", "day", RAW_VALUE_COL, "flag"] + [f"extra{i}" for i in range(raw.shape[1]-6)]
    raw['date'] = pd.to_datetime(dict(year=raw.year, month=raw.month, day=raw.day))
    df = raw.set_index('date').sort_index()
    df[TARGET_COL] = df[RAW_VALUE_COL]
    return df[[TARGET_COL]]


def iter_basins(basin_files: List[Path]) -> List[str]:
    all_basins: List[str] = []
    for bf in basin_files:
        all_basins.extend(read_basin_list(bf))
    # deduplicate but keep order of first occurrence
    seen = set()
    ordered = []
    for b in all_basins:
        if b not in seen:
            ordered.append(b)
            seen.add(b)
    return ordered


def compute_stats(df: pd.DataFrame, start: pd.Timestamp, end: pd.Timestamp) -> BasinStats:
    window = df.loc[(df.index >= start) & (df.index <= end)]
    points_total = len(window)
    series = window[TARGET_COL]
    valid = series.dropna()
    valid_count = len(valid)
    nan_ratio = 1.0 - (valid_count / points_total) if points_total > 0 else 1.0
    std = float(valid.std()) if valid_count >= 2 else None
    mean = float(valid.mean()) if valid_count >= 1 else None
    zero_variance = (valid_count < 2) or (std is not None and std == 0.0)
    first_valid = valid.index[0].strftime("%Y-%m-%d") if valid_count else None
    last_valid = valid.index[-1].strftime("%Y-%m-%d") if valid_count else None
    return BasinStats(
        basin="",
        points_total=points_total,
        valid_count=valid_count,
        nan_ratio=nan_ratio,
        zero_variance=zero_variance,
        mean=mean,
        std=std,
        window_start=start.strftime("%Y-%m-%d"),
        window_end=end.strftime("%Y-%m-%d"),
        first_valid=first_valid,
        last_valid=last_valid,
    )


def main():
    p = argparse.ArgumentParser(description="Audit CAMELS-US discharge data availability per basin.")
    p.add_argument("--data-dir", required=True, type=Path, help="Path to CAMELS_US root directory")
    p.add_argument("--basin-file", action="append", type=Path, help="Path(s) to basin list text file(s)")
    p.add_argument("--start", required=True, help="Start date YYYY-MM-DD")
    p.add_argument("--end", required=True, help="End date YYYY-MM-DD")
    p.add_argument("--out", default="data_availability_report.csv", type=Path, help="Output CSV report path")
    p.add_argument("--top", type=int, default=20, help="Print top-N problematic basins")
    args = p.parse_args()

    start = pd.to_datetime(args.start)
    end = pd.to_datetime(args.end)

    if not args.basin_file:
        raise SystemExit("Provide at least one --basin-file")

    basins = iter_basins(args.basin_file)
    index = build_streamflow_index(args.data_dir)
    print(f"[INFO] Indexed {len(index)} streamflow files.")
    # Pre-compute difference
    missing_in_index = [b for b in basins if b not in index]
    if missing_in_index:
        print(f"[WARN] {len(missing_in_index)} basins from list have no corresponding streamflow file (will be marked missing). Example: {missing_in_index[:10]}")
        diff_path = args.out.parent / "missing_in_index.txt"
        diff_path.parent.mkdir(parents=True, exist_ok=True)
        diff_path.write_text("\n".join(missing_in_index), encoding="utf-8")
        print(f"[INFO] Missing basin list written: {diff_path}")

    rows: List[List[str]] = []
    stats_objects: List[BasinStats] = []

    for basin in basins:
        try:
            df = load_discharge_file(index, basin)
            stat = compute_stats(df, start, end)
            stat.basin = basin
        except Exception as e:
            stat = BasinStats(
                basin=basin,
                points_total=0,
                valid_count=0,
                nan_ratio=1.0,
                zero_variance=True,
                mean=None,
                std=None,
                window_start=start.strftime("%Y-%m-%d"),
                window_end=end.strftime("%Y-%m-%d"),
                first_valid=None,
                last_valid=None,
            )
            print(f"[WARN] Basin {basin} failed: {e}")
        stats_objects.append(stat)
        rows.append(stat.to_row())

    # Write CSV
    header = [
        "basin",
        "points_total",
        "valid_count",
        "nan_ratio",
        "zero_variance",
        "mean",
        "std",
        "window_start",
        "window_end",
        "first_valid",
        "last_valid",
    ]
    args.out.parent.mkdir(parents=True, exist_ok=True)
    with args.out.open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(header)
        writer.writerows(rows)
    print(f"Report written: {args.out}")

    # Summary
    total = len(stats_objects)
    zero_var = sum(s.zero_variance for s in stats_objects)
    high_nan = [s for s in stats_objects if s.nan_ratio > 0.5]
    print(f"Total basins: {total}")
    print(f"Zero-variance / insufficient (N<2) basins: {zero_var}")
    print(f"Basins with nan_ratio>0.5: {len(high_nan)}")

    # Sort problematic basins (zero_variance first, then highest nan_ratio)
    problematic = sorted(stats_objects, key=lambda s: (not s.zero_variance, -s.nan_ratio))
    print("\nTop problematic basins:")
    print("basin | zero_var | nan_ratio | valid_count | std")
    for s in problematic[:args.top]:
        print(f"{s.basin} | {int(s.zero_variance)} | {s.nan_ratio:.3f} | {s.valid_count} | {s.std if s.std is not None else ''}")

    # Suggest removal list
    removal = [s.basin for s in stats_objects if s.zero_variance or s.nan_ratio > 0.9]
    if removal:
        removal_path = args.out.parent / "basins_to_exclude.txt"
        removal_path.write_text("\n".join(removal), encoding="utf-8")
        print(f"Suggested exclusion list written: {removal_path} (count={len(removal)})")


if __name__ == "__main__":
    main()

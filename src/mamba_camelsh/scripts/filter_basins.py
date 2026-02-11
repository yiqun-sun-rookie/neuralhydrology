#!/usr/bin/env python3
"""
Filter CAMELS-H basins based on hourly data completeness for training.

Rule (default):
- Require each year in 2010-2020 to have >= 95% of expected hours
  (8760 or 8784 for leap years).
- Basin must appear in available_basins.txt
- Basin must have a time series file in data/camelsh/{timeseries,time_series,hourly2/Hourly2}

Outputs:
- data/camelsh/filtered/filtered_basins_2010_2020_95pct.txt
- data/camelsh/filtered/train_basins_2010_2020_95pct.txt
- data/camelsh/filtered/val_basins_2010_2020_95pct.txt
- data/camelsh/filtered/test_basins_2010_2020_95pct.txt
- data/camelsh/filtered/summary_2010_2020_95pct.md
- src/mamba_camelsh/data/test_50_basins.txt (sample from filtered train basins)
"""

from __future__ import annotations

import argparse
import csv
import random
import re
from pathlib import Path


YEAR_START = 2010
YEAR_END = 2020
DEFAULT_MIN_RATIO = 0.95


def is_leap_year(year: int) -> bool:
    return year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)


def expected_hours(year: int) -> int:
    return 8784 if is_leap_year(year) else 8760


def read_basin_list(path: Path) -> list[str]:
    if not path.exists():
        return []
    with path.open("r", encoding="utf-8") as f:
        return [line.strip() for line in f if line.strip()]


def write_basin_list(path: Path, basins: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        for basin in basins:
            f.write(f"{basin}\n")


def extract_basin_id(filename: str) -> str | None:
    match = re.search(r"(\d{8})", filename)
    return match.group(1) if match else None


def collect_basin_ids_from_files(dirs: list[Path]) -> set[str]:
    basin_ids: set[str] = set()
    for d in dirs:
        if not d.exists():
            continue
        for path in d.glob("*.nc"):
            basin_id = extract_basin_id(path.name)
            if basin_id:
                basin_ids.add(basin_id)
    return basin_ids


def load_info_csv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        return list(reader)


def filter_by_completeness(
    records: list[dict[str, str]],
    years: list[int],
    min_ratio: float,
    valid_basins: set[str],
) -> list[str]:
    keep: list[str] = []
    for row in records:
        basin_id = row.get("STAID", "").strip()
        if not basin_id or basin_id not in valid_basins:
            continue

        ok = True
        for year in years:
            year_str = str(year)
            value = row.get(year_str, "")
            try:
                hours = float(value)
            except ValueError:
                ok = False
                break

            threshold = expected_hours(year) * min_ratio
            if hours < threshold:
                ok = False
                break

        if ok:
            keep.append(basin_id)
    return sorted(set(keep))


def sample_basins(basins: list[str], count: int, seed: int = 42) -> list[str]:
    if len(basins) <= count:
        return basins
    rng = random.Random(seed)
    basins_copy = list(basins)
    rng.shuffle(basins_copy)
    return sorted(basins_copy[:count])


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Filter CAMELS-H basins by hourly data completeness."
    )
    parser.add_argument("--info", default="data/camelsh/info.csv")
    parser.add_argument("--available", default="data/camelsh/available_basins.txt")
    parser.add_argument("--good", default="data/camelsh/good_basins.txt")
    parser.add_argument("--train", default="data/camelsh/train_basins.txt")
    parser.add_argument("--val", default="data/camelsh/val_basins.txt")
    parser.add_argument("--test", default="data/camelsh/test_basins.txt")
    parser.add_argument("--out_dir", default="data/camelsh/filtered")
    parser.add_argument("--min_ratio", type=float, default=DEFAULT_MIN_RATIO)
    parser.add_argument("--year_start", type=int, default=YEAR_START)
    parser.add_argument("--year_end", type=int, default=YEAR_END)
    parser.add_argument("--sample_50_out", default="src/mamba_camelsh/data/test_50_basins.txt")
    parser.add_argument("--sample_seed", type=int, default=42)
    args = parser.parse_args()

    info_path = Path(args.info)
    available_path = Path(args.available)
    good_path = Path(args.good)
    train_path = Path(args.train)
    val_path = Path(args.val)
    test_path = Path(args.test)
    out_dir = Path(args.out_dir)

    years = list(range(args.year_start, args.year_end + 1))

    available_basins = set(read_basin_list(available_path))
    good_basins = set(read_basin_list(good_path))

    data_dirs = [
        Path("data/camelsh/timeseries"),
        Path("data/camelsh/time_series"),
        Path("data/camelsh/hourly2/Hourly2"),
    ]
    basins_with_files = collect_basin_ids_from_files(data_dirs)

    valid_basins = available_basins.intersection(basins_with_files)

    info_records = load_info_csv(info_path)
    filtered_basins = filter_by_completeness(
        info_records, years, args.min_ratio, valid_basins
    )

    out_main = out_dir / f"filtered_basins_{args.year_start}_{args.year_end}_{int(args.min_ratio*100)}pct.txt"
    write_basin_list(out_main, filtered_basins)

    # Optional: intersection with good basins
    if good_basins:
        filtered_good = sorted(set(filtered_basins).intersection(good_basins))
        out_good = out_dir / f"filtered_basins_{args.year_start}_{args.year_end}_{int(args.min_ratio*100)}pct_good.txt"
        write_basin_list(out_good, filtered_good)
    else:
        filtered_good = []
        out_good = None

    # Filter train/val/test lists if provided
    train_filtered = [b for b in read_basin_list(train_path) if b in filtered_basins]
    val_filtered = [b for b in read_basin_list(val_path) if b in filtered_basins]
    test_filtered = [b for b in read_basin_list(test_path) if b in filtered_basins]

    if train_filtered:
        write_basin_list(
            out_dir / f"train_basins_{args.year_start}_{args.year_end}_{int(args.min_ratio*100)}pct.txt",
            train_filtered,
        )
    if val_filtered:
        write_basin_list(
            out_dir / f"val_basins_{args.year_start}_{args.year_end}_{int(args.min_ratio*100)}pct.txt",
            val_filtered,
        )
    if test_filtered:
        write_basin_list(
            out_dir / f"test_basins_{args.year_start}_{args.year_end}_{int(args.min_ratio*100)}pct.txt",
            test_filtered,
        )

    # Create a 50-basin sample (prefer train basins)
    sample_source = train_filtered if train_filtered else filtered_basins
    sample_50 = sample_basins(sample_source, 50, seed=args.sample_seed)
    write_basin_list(Path(args.sample_50_out), sample_50)

    # Summary
    summary_path = out_dir / f"summary_{args.year_start}_{args.year_end}_{int(args.min_ratio*100)}pct.md"
    out_dir.mkdir(parents=True, exist_ok=True)
    with summary_path.open("w", encoding="utf-8") as f:
        f.write("# CAMELS-H Basin Filtering Summary\n\n")
        f.write(f"**Years**: {args.year_start}-{args.year_end}\n")
        f.write(f"**Min ratio per year**: {args.min_ratio:.2f}\n\n")
        f.write("## Counts\n\n")
        f.write(f"- Available basins: {len(available_basins)}\n")
        f.write(f"- Basins with data files: {len(basins_with_files)}\n")
        f.write(f"- Valid basins (available ∩ files): {len(valid_basins)}\n")
        f.write(f"- Filtered basins (completeness): {len(filtered_basins)}\n")
        if out_good is not None:
            f.write(f"- Filtered ∩ good_basins: {len(filtered_good)}\n")
        if train_filtered:
            f.write(f"- Train basins (filtered): {len(train_filtered)}\n")
        if val_filtered:
            f.write(f"- Val basins (filtered): {len(val_filtered)}\n")
        if test_filtered:
            f.write(f"- Test basins (filtered): {len(test_filtered)}\n")
        f.write("\n## Outputs\n\n")
        f.write(f"- {out_main.as_posix()}\n")
        if out_good is not None:
            f.write(f"- {out_good.as_posix()}\n")
        if train_filtered:
            f.write(f"- {(out_dir / f'train_basins_{args.year_start}_{args.year_end}_{int(args.min_ratio*100)}pct.txt').as_posix()}\n")
        if val_filtered:
            f.write(f"- {(out_dir / f'val_basins_{args.year_start}_{args.year_end}_{int(args.min_ratio*100)}pct.txt').as_posix()}\n")
        if test_filtered:
            f.write(f"- {(out_dir / f'test_basins_{args.year_start}_{args.year_end}_{int(args.min_ratio*100)}pct.txt').as_posix()}\n")
        f.write(f"- {Path(args.sample_50_out).as_posix()}\n")

    print("Filtering complete.")
    print(f"Filtered basins: {len(filtered_basins)}")
    print(f"Summary: {summary_path}")


if __name__ == "__main__":
    main()

#!/usr/bin/env python
"""Quick check for NamOu/Kuwei site data structure.

Usage:
    python src/namou_kuwei/scripts/check_site_data.py data/namou_kuwei/hourly
"""

from pathlib import Path
import sys

import pandas as pd


def check_site(data_dir: str) -> bool:
    """Validate required files and basic csv schema."""
    root = Path(data_dir)
    errors: list[str] = []
    warnings: list[str] = []

    required = [
        "time_series",
        "attributes",
        "train_basins.txt",
        "validation_basins.txt",
        "test_basins.txt",
    ]
    for item in required:
        if not (root / item).exists():
            errors.append(f"Missing: {item}")

    ts_dir = root / "time_series"
    if ts_dir.exists():
        csv_files = list(ts_dir.glob("*.csv"))
        if not csv_files:
            errors.append("No CSV found under time_series/")
        else:
            for csv_file in csv_files:
                try:
                    frame = pd.read_csv(csv_file, nrows=10)
                    if "date" not in frame.columns:
                        errors.append(f"{csv_file.name}: missing `date` column")
                    if "qobs" not in frame.columns:
                        warnings.append(f"{csv_file.name}: missing `qobs` column (ok for forcing-only site)")
                except Exception as exc:
                    errors.append(f"{csv_file.name}: read failed - {exc}")

    attr_file = root / "attributes" / "attributes.csv"
    if attr_file.exists():
        try:
            frame = pd.read_csv(attr_file)
            print(f"attributes: {len(frame.columns) - 1} features, {len(frame)} basins")
        except Exception as exc:
            errors.append(f"attributes.csv: {exc}")

    print("\n" + "=" * 50)
    print(f"site dir: {data_dir}")
    print("=" * 50)

    if errors:
        print("\n[errors]")
        for err in errors:
            print(f"  - {err}")

    if warnings:
        print("\n[warnings]")
        for warn in warnings:
            print(f"  - {warn}")

    if not errors:
        print("\nOK: data structure check passed")
        return True
    return False


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python src/namou_kuwei/scripts/check_site_data.py <data_dir>")
        print("Example: python src/namou_kuwei/scripts/check_site_data.py data/namou_kuwei/hourly")
        sys.exit(1)

    is_ok = check_site(sys.argv[1])
    sys.exit(0 if is_ok else 1)





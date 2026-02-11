"""Generate QC summaries for GloFAS outlets and time series."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import geopandas as gpd
import pandas as pd


def generate_qc(outputs_dir: Path) -> None:
    outputs_dir = outputs_dir.resolve()
    outlet_path = outputs_dir / "subbasin_outlets.geojson"
    if not outlet_path.exists():
        raise FileNotFoundError(f"Outlet file not found: {outlet_path}")

    qc_dir = outputs_dir / "qc"
    qc_dir.mkdir(parents=True, exist_ok=True)

    outlets = gpd.read_file(outlet_path)

    summary: dict[str, object] = {
        "total_outlets": int(len(outlets)),
        "threshold_passed": int(outlets["threshold_passed"].sum()),
        "threshold_failed": int((~outlets["threshold_passed"]).sum()),
        "candidate_count_min": float(outlets["candidate_count"].min()),
        "candidate_count_mean": float(outlets["candidate_count"].mean()),
        "candidate_count_max": float(outlets["candidate_count"].max()),
        "threshold_count_min": float(outlets["threshold_count"].min()),
        "threshold_count_mean": float(outlets["threshold_count"].mean()),
        "threshold_count_max": float(outlets["threshold_count"].max()),
    }

    quantiles = outlets[["ua_km2", "mean_dis"]].quantile(
        [0.05, 0.1, 0.25, 0.5, 0.75, 0.9, 0.95]
    )
    summary["ua_km2_quantiles"] = {
        str(idx): float(val) for idx, val in quantiles["ua_km2"].round(3).items()
    }
    summary["mean_dis_quantiles"] = {
        str(idx): float(val) for idx, val in quantiles["mean_dis"].round(3).items()
    }

    outlets[
        [
            "SUB_ID",
            "lon",
            "lat",
            "ua_km2",
            "mean_dis",
            "threshold_passed",
            "candidate_count",
            "threshold_count",
        ]
    ].to_csv(qc_dir / "subbasin_outlets_checks.csv", index=False)

    ts_dir = outputs_dir / "timeseries"
    records = []
    for csv_file in sorted(ts_dir.glob("sub_*_discharge.csv")):
        sub_id = csv_file.stem.replace("sub_", "").replace("_discharge", "")
        df = pd.read_csv(csv_file, parse_dates=["time"])
        total = len(df)
        count = int(df["discharge_m3s"].count())
        nan_count = total - count

        records.append(
            {
                "SUB_ID": sub_id,
                "count": count,
                "total": total,
                "nan_count": nan_count,
                "nan_ratio": float(nan_count / total) if total else 0.0,
                "mean": float(df["discharge_m3s"].mean(skipna=True)),
                "std": float(df["discharge_m3s"].std(skipna=True)),
                "min": float(df["discharge_m3s"].min(skipna=True)),
                "max": float(df["discharge_m3s"].max(skipna=True)),
                "p10": float(df["discharge_m3s"].quantile(0.1)),
                "p90": float(df["discharge_m3s"].quantile(0.9)),
            }
        )

    ts_df = pd.DataFrame(records)
    ts_df.to_csv(qc_dir / "timeseries_stats.csv", index=False)

    summary["timeseries_expected_length"] = int(ts_df["total"].max())
    summary["timeseries_min_count"] = int(ts_df["count"].min())
    summary["timeseries_max_count"] = int(ts_df["count"].max())
    summary["timeseries_nan_ratio_max"] = float(ts_df["nan_ratio"].max())
    summary["timeseries_mean_flow_mean"] = float(ts_df["mean"].mean())
    summary["timeseries_mean_flow_median"] = float(ts_df["mean"].median())

    (qc_dir / "summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate QC summaries for GloFAS outlet products."
    )
    parser.add_argument(
        "--outputs-dir",
        type=Path,
        default=Path("data/haihe/glofas/outputs"),
        help="Directory that contains subbasin_outlets.* and timeseries/",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    generate_qc(args.outputs_dir)


if __name__ == "__main__":
    main()


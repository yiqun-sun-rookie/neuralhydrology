"""Create QC visualisations for GloFAS outlet products."""

from __future__ import annotations

import argparse
import math
from pathlib import Path

import geopandas as gpd
import matplotlib.pyplot as plt
import pandas as pd


def setup_dirs(outputs_dir: Path) -> tuple[Path, Path, Path]:
    base = outputs_dir.resolve()
    qc_dir = base / "qc"
    fig_dir = qc_dir / "figures"
    fig_dir.mkdir(parents=True, exist_ok=True)
    return base, qc_dir, fig_dir


def plot_outlet_map(outlets: gpd.GeoDataFrame, subbasins: gpd.GeoDataFrame, fig_dir: Path) -> None:
    fig, ax = plt.subplots(figsize=(10, 8))

    subbasins.boundary.plot(ax=ax, linewidth=0.2, color="grey")

    sizes = 20 + 10 * outlets["ua_km2"].apply(lambda x: math.log10(max(x, 1.0)))
    colors = outlets["threshold_passed"].map({True: "#1b9e77", False: "#d95f02"})

    outlets.plot(
        ax=ax,
        marker="o",
        color=colors,
        markersize=sizes,
        alpha=0.7,
        edgecolor="black",
        linewidth=0.1,
    )

    ax.set_xlabel("Longitude")
    ax.set_ylabel("Latitude")
    ax.set_title("GloFAS Haihe Subbasin Outlets\nColor: threshold passed, Size: upstream area")
    ax.set_aspect("equal")
    ax.grid(True, linestyle=":", linewidth=0.3, alpha=0.6)

    handles = [
        plt.Line2D([0], [0], marker="o", color="w", label="Threshold passed",
                   markerfacecolor="#1b9e77", markersize=8),
        plt.Line2D([0], [0], marker="o", color="w", label="Threshold fallback",
                   markerfacecolor="#d95f02", markersize=8),
    ]
    ax.legend(handles=handles, loc="lower left", frameon=True, fontsize=8)

    fig.tight_layout()
    fig.savefig(fig_dir / "outlets_map.png", dpi=200)
    plt.close(fig)


def plot_distributions(outlets: gpd.GeoDataFrame, fig_dir: Path) -> None:
    fig, axes = plt.subplots(1, 2, figsize=(12, 5))

    axes[0].hist(outlets["ua_km2"], bins=40, color="#3182bd", alpha=0.8)
    axes[0].set_title("Upstream Area (km²)")
    axes[0].set_xlabel("ua_km2")
    axes[0].set_ylabel("Count")
    axes[0].set_yscale("log")
    axes[0].grid(True, linestyle=":", linewidth=0.3, alpha=0.6)

    axes[1].hist(outlets["mean_dis"], bins=40, color="#e6550d", alpha=0.8)
    axes[1].set_title("Mean Discharge (m³/s)")
    axes[1].set_xlabel("mean_dis")
    axes[1].set_ylabel("Count")
    axes[1].set_yscale("log")
    axes[1].grid(True, linestyle=":", linewidth=0.3, alpha=0.6)

    fig.tight_layout()
    fig.savefig(fig_dir / "distributions_hist.png", dpi=200)
    plt.close(fig)


def plot_ecdf(series: pd.Series, ax: plt.Axes, label: str, color: str) -> None:
    data = series.sort_values().reset_index(drop=True)
    ecdf = (pd.Series(range(1, len(data) + 1)) / len(data)).values
    ax.plot(data, ecdf, label=label, color=color)


def plot_ecdf_fig(outlets: gpd.GeoDataFrame, fig_dir: Path) -> None:
    fig, axes = plt.subplots(1, 2, figsize=(12, 5))

    plot_ecdf(outlets["ua_km2"], axes[0], "ua_km2", "#3182bd")
    axes[0].set_xscale("log")
    axes[0].set_title("ECDF of Upstream Area")
    axes[0].set_xlabel("ua_km2 (log)")
    axes[0].set_ylabel("F(x)")
    axes[0].grid(True, linestyle=":", linewidth=0.3, alpha=0.6)

    plot_ecdf(outlets["mean_dis"], axes[1], "mean_dis", "#e6550d")
    axes[1].set_xscale("log")
    axes[1].set_title("ECDF of Mean Discharge")
    axes[1].set_xlabel("mean_dis (log)")
    axes[1].set_ylabel("F(x)")
    axes[1].grid(True, linestyle=":", linewidth=0.3, alpha=0.6)

    for ax in axes:
        ax.legend()

    fig.tight_layout()
    fig.savefig(fig_dir / "distributions_ecdf.png", dpi=200)
    plt.close(fig)


def plot_timeseries_samples(ts_dir: Path, stats: pd.DataFrame, fig_dir: Path) -> None:
    sample_ids = list(
        pd.concat(
            [
                stats.nsmallest(2, "mean")["SUB_ID"],
                stats.nlargest(2, "mean")["SUB_ID"],
                stats.nlargest(2, "std")["SUB_ID"],
            ]
        ).unique()
    )[:6]

    for sub_id in sample_ids:
        csv_file = ts_dir / f"sub_{sub_id}_discharge.csv"
        df = pd.read_csv(csv_file, parse_dates=["time"])
        fig, ax = plt.subplots(figsize=(10, 4))
        ax.plot(df["time"], df["discharge_m3s"], color="#636363", linewidth=0.8)
        ax.set_title(f"Subbasin {sub_id} discharge (m³/s)")
        ax.set_xlabel("Date")
        ax.set_ylabel("Discharge (m³/s)")
        ax.grid(True, linestyle=":", linewidth=0.3, alpha=0.6)
        fig.tight_layout()
        fig.savefig(fig_dir / f"timeseries_{sub_id}.png", dpi=180)
        plt.close(fig)


def generate_figures(outputs_dir: Path, subbasin_file: Path) -> None:
    base, qc_dir, fig_dir = setup_dirs(outputs_dir)

    outlets = gpd.read_file(base / "subbasin_outlets.geojson")
    subbasins = gpd.read_file(subbasin_file)
    stats_path = qc_dir / "timeseries_stats.csv"
    if not stats_path.exists():
        raise FileNotFoundError(
            f"Time-series stats not found: {stats_path} (run qc_summary first)"
        )
    stats = pd.read_csv(stats_path)

    plot_outlet_map(outlets, subbasins, fig_dir)
    plot_distributions(outlets, fig_dir)
    plot_ecdf_fig(outlets, fig_dir)
    plot_timeseries_samples(base / "timeseries", stats, fig_dir)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Create QC visualisations for GloFAS outlet products."
    )
    parser.add_argument(
        "--outputs-dir",
        type=Path,
        default=Path("data/haihe/glofas/outputs"),
        help="Directory containing subbasin_outlets.* and timeseries/",
    )
    parser.add_argument(
        "--subbasin-file",
        type=Path,
        default=Path("data/haihe/hydrobasins/lev9/haihe_hydrobasins_lev9.gpkg"),
        help="HydroBASINS/FAO subbasin vector file for plotting boundaries.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    generate_figures(args.outputs_dir, args.subbasin_file)


if __name__ == "__main__":
    main()


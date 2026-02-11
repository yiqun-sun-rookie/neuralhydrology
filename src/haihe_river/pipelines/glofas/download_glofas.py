"""Download GloFAS data for a target basin using CDS API.

This script reads a YAML configuration file containing download parameters,
computes the basin bounding box (with optional buffer), and downloads yearly
NetCDF files for the requested variables.

Example usage:
    python pipelines/glofas/download_glofas.py \
        --config configs/glofas/haihe_download.yaml
"""

from __future__ import annotations

import argparse
import datetime as dt
import logging
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable, List, Optional

import yaml

try:
    import geopandas as gpd
except ImportError as exc:
    raise ImportError(
        "geopandas is required. Install via `pip install geopandas`."
    ) from exc

try:
    import cdsapi  # type: ignore
except ImportError as exc:
    raise ImportError(
        "cdsapi is required. Install via `pip install cdsapi` and "
        "configure your ~/.cdsapirc credentials."
    ) from exc


LOG_FORMAT = "%(asctime)s | %(levelname)s | %(message)s"


@dataclass
class DownloadConfig:
    dataset: str
    product_type: str
    variables: List[str]
    years: List[int]
    time_range: List[str]
    area_buffer_deg: float = 0.25
    basin_boundary: Path = field(default_factory=Path)
    output_dir: Path = field(default_factory=Path)
    logs_dir: Optional[Path] = None
    intermediate_dir: Optional[Path] = None
    leadtimes: Optional[List[str]] = None
    dry_run: bool = False

    @property
    def start_date(self) -> dt.date:
        return dt.date.fromisoformat(self.time_range[0])

    @property
    def end_date(self) -> dt.date:
        return dt.date.fromisoformat(self.time_range[1])

    @property
    def years_span(self) -> List[int]:
        if self.years:
            return self.years
        return list(range(self.start_date.year, self.end_date.year + 1))


def load_config(path: Path) -> DownloadConfig:
    with path.open("r", encoding="utf-8") as fp:
        raw = yaml.safe_load(fp)

    # Normalise scalar values to lists
    dataset = raw["dataset"]
    product_type = raw["product_type"]
    variables = raw.get("variables") or [raw.get("variable")]
    if not variables or any(v is None for v in variables):
        raise ValueError("`variables` (or `variable`) must be defined in config.")

    years = raw.get("years", [])
    time_range = raw.get("time_range")
    if not isinstance(time_range, list) or len(time_range) != 2:
        raise ValueError("`time_range` must be a list: [start_date, end_date].")

    basin_boundary = Path(raw["basin_boundary"])
    output_dir = Path(raw["output_dir"])
    logs_dir = Path(raw["logs_dir"]) if raw.get("logs_dir") else None

    return DownloadConfig(
        dataset=dataset,
        product_type=product_type,
        variables=variables,
        years=years,
        time_range=time_range,
        area_buffer_deg=float(raw.get("area_buffer_deg", 0.25)),
        basin_boundary=basin_boundary,
        output_dir=output_dir,
        logs_dir=logs_dir,
        intermediate_dir=Path(raw["intermediate_dir"])
        if raw.get("intermediate_dir")
        else None,
        leadtimes=raw.get("leadtimes"),
        dry_run=bool(raw.get("dry_run", False)),
    )


def configure_logging(logs_dir: Optional[Path] = None) -> None:
    handlers = [logging.StreamHandler(sys.stdout)]
    if logs_dir:
        logs_dir.mkdir(parents=True, exist_ok=True)
        timestamp = dt.datetime.utcnow().strftime("%Y%m%d_%H%M%S")
        log_file = logs_dir / f"download_{timestamp}.log"
        handlers.append(logging.FileHandler(log_file, encoding="utf-8"))

    logging.basicConfig(level=logging.INFO, handlers=handlers, format=LOG_FORMAT)


def compute_bbox(shapefile: Path, buffer_deg: float) -> List[float]:
    gdf = gpd.read_file(shapefile)
    if gdf.empty:
        raise ValueError(f"Basin boundary file {shapefile} is empty.")
    geometry = gdf.to_crs("EPSG:4326").unary_union
    minx, miny, maxx, maxy = geometry.bounds
    minx -= buffer_deg
    miny -= buffer_deg
    maxx += buffer_deg
    maxy += buffer_deg
    # CDS API expects North/West/South/East order
    bbox = [maxy, minx, miny, maxx]
    logging.info("Computed bbox (N/W/S/E): %s", bbox)
    return bbox


def request_payload(
    config: DownloadConfig,
    year: int,
    variable: str,
    bbox: List[float],
) -> dict:
    start_date = max(config.start_date, dt.date(year, 1, 1))
    end_date = min(config.end_date, dt.date(year, 12, 31))

    if start_date > end_date:
        raise ValueError(f"Year {year} is outside requested time range.")

    date_range = f"{start_date:%Y-%m-%d}/{end_date:%Y-%m-%d}"

    payload = {
        "dataset": config.dataset,
        "product_type": config.product_type,
        "variable": variable,
        "area": bbox,
        "date": date_range,
        "format": "netcdf",
    }
    if config.leadtimes:
        payload["leadtime_hour"] = config.leadtimes
    return payload


def download_file(
    client: cdsapi.Client,
    payload: dict,
    target: Path,
    dry_run: bool = False,
) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)

    if target.exists():
        logging.info("Skip existing file: %s", target)
        return

    logging.info("Requesting %s -> %s", payload["variable"], target)
    if dry_run:
        logging.info("Dry-run enabled; no download performed.")
        return

    client.retrieve(
        name=payload.pop("dataset"),
        request=payload,
        target=str(target),
    )


def iterate_variables(vars_: Iterable[str]) -> Iterable[str]:
    for var in vars_:
        if not var:
            continue
        yield var


def run_download(config: DownloadConfig) -> None:
    configure_logging(config.logs_dir)
    bbox = compute_bbox(config.basin_boundary, config.area_buffer_deg)

    client = cdsapi.Client()

    for variable in iterate_variables(config.variables):
        for year in config.years_span:
            payload = request_payload(config, year, variable, bbox)
            filename = f"{variable}_{year}.nc"
            target = config.output_dir / filename
            download_file(client, payload, target, dry_run=config.dry_run)

    logging.info("Download routine completed.")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Download GloFAS data by basin.")
    parser.add_argument(
        "--config",
        type=Path,
        required=True,
        help="Path to YAML configuration file.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    config = load_config(args.config)
    run_download(config)


if __name__ == "__main__":
    main()


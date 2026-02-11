"""Download GloFAS historical data for a specific region.

This helper script targets the EWDS dataset `cems-glofas-historical`.
It loops over variables and years and saves NetCDF files to the
`data/haihe/glofas/raw/` directory (relative to project root).
"""

from __future__ import annotations

import logging
from pathlib import Path
from typing import Iterable

import cdsapi

ROOT = Path(__file__).resolve().parents[2]
RAW_DIR = ROOT / "artifacts" / "glofas" / "haihe" / "raw"

LOGGER = logging.getLogger(__name__)


def iter_months() -> Iterable[str]:
    for month in range(1, 13):
        yield f"{month:02d}"


def iter_days() -> Iterable[str]:
    for day in range(1, 32):
        yield f"{day:02d}"


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s | %(levelname)s | %(message)s")

    client = cdsapi.Client()
    dataset = "cems-glofas-historical"

    area = [42.975, 111.701, 34.761, 120.089]  # N, W, S, E (Haihe + 0.25° buffer)
    variables = [
        "river_discharge_in_the_last_24_hours",
    ]
    years = ["2024", "2025"]
    product_type = "consolidated"

    RAW_DIR.mkdir(parents=True, exist_ok=True)

    request_base = {
        "system_version": ["version_4_0"],
        "hydrological_model": ["lisflood"],
        "product_type": [product_type],
        "hmonth": list(iter_months()),
        "hday": list(iter_days()),
        "data_format": "netcdf",
        "download_format": "unarchived",
        "area": area,
    }

    for variable in variables:
        for year in years:
            target = RAW_DIR / f"{variable}_{year}.nc"
            if target.exists():
                LOGGER.info("Skip existing %s", target)
                continue

            request = dict(request_base)
            request["variable"] = [variable]
            request["hyear"] = [year]

            LOGGER.info("Requesting %s %s -> %s", variable, year, target)
            client.retrieve(dataset, request, str(target))
            LOGGER.info("Finished %s", target)

    # Download ancillary upstream area (static) file directly from Confluence.
    upstream_target = RAW_DIR / "upstream_area_static.nc"
    if upstream_target.exists():
        LOGGER.info("Skip existing %s", upstream_target)
    else:
        import requests  # Imported lazily to avoid dependency when not needed.

        upstream_url = (
            "https://confluence.ecmwf.int/download/attachments/242067380/"
            "uparea_glofas_v4_0.nc?version=2&modificationDate=1668604690076&api=v2"
        )
        LOGGER.info("Downloading upstream area ancillary -> %s", upstream_target)
        response = requests.get(upstream_url, timeout=120)
        response.raise_for_status()
        upstream_target.write_bytes(response.content)
        LOGGER.info("Finished %s", upstream_target)


if __name__ == "__main__":
    main()


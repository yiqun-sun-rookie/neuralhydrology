"""Download daily precipitation and evapotranspiration from KNMI."""
import logging
import time
from pathlib import Path
from typing import Optional

import pandas as pd
import requests

from src.gwl_global.config import KNMI_DAG_URL, KNMI_STATIONS, KNMI_REQUEST_DELAY, data_dir

logger = logging.getLogger(__name__)


def download_knmi_station(
    stn: int,
    start: str = "19900101",
    end: str = "20261231",
) -> Optional[pd.DataFrame]:
    """Download daily P and ET for one KNMI station.

    Args:
        stn: KNMI station number (e.g. 260 for De Bilt)
        start: YYYYMMDD
        end: YYYYMMDD

    Returns:
        DataFrame with DatetimeIndex and columns [P_mm, ET_mm], or None on failure.
    """
    payload = {
        "stns": str(stn),
        "vars": "RH:EV24",
        "start": start,
        "end": end,
        "fmt": "json",
    }

    try:
        resp = requests.post(KNMI_DAG_URL, data=payload, timeout=120)
        resp.raise_for_status()
        records = resp.json()
    except Exception as exc:
        logger.warning("KNMI download failed for station %d: %s", stn, exc)
        return None

    if not records:
        logger.warning("KNMI returned empty data for station %d", stn)
        return None

    df = pd.DataFrame(records)

    # Parse date
    df["date"] = pd.to_datetime(df["date"]).dt.date
    df["date"] = pd.to_datetime(df["date"])

    # Convert RH: 0.1mm -> mm, -1 -> 0.025 (trace)
    # In 0.1mm units: -1 means < 0.05mm, i.e. < 0.5 in raw units -> use 0.25 raw = 0.025 mm
    rh = pd.to_numeric(df.get("RH"), errors="coerce")
    rh = rh.where(rh != -1, 0.25)  # 0.25 in 0.1mm units = 0.025 mm
    df["P_mm"] = rh / 10.0

    # Convert EV24: 0.1mm -> mm
    df["ET_mm"] = pd.to_numeric(df.get("EV24"), errors="coerce") / 10.0

    result = df[["date", "P_mm", "ET_mm"]].copy()
    result = result.set_index("date").sort_index()

    return result


def run_knmi_download(
    stations: Optional[list[int]] = None,
    output_dir: Optional[Path] = None,
    start: str = "19900101",
    end: str = "20261231",
) -> int:
    """Download KNMI data for all required stations.

    Args:
        stations: list of station numbers. If None, use all KNMI_STATIONS.
        output_dir: where to save CSVs.

    Returns:
        Number of successfully downloaded stations.
    """
    output_dir = output_dir or data_dir()
    meteo_dir = output_dir / "meteo"
    meteo_dir.mkdir(parents=True, exist_ok=True)

    if stations is None:
        stations = [s["stn"] for s in KNMI_STATIONS]

    n_success = 0
    for stn in stations:
        out_path = meteo_dir / f"knmi_{stn}_daily.csv"
        if out_path.exists():
            logger.info("Station %d already downloaded, skipping.", stn)
            n_success += 1
            continue

        logger.info("Downloading KNMI station %d ...", stn)
        df = download_knmi_station(stn, start=start, end=end)
        if df is not None and len(df) > 0:
            df.to_csv(out_path)
            n_success += 1
            logger.info("Saved %d rows for station %d.", len(df), stn)
        else:
            logger.warning("No data for station %d.", stn)

        time.sleep(KNMI_REQUEST_DELAY)

    logger.info("KNMI download: %d/%d stations OK.", n_success, len(stations))
    return n_success

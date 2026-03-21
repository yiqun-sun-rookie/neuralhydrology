"""Download groundwater level time series from BRO GLD as CSV."""
import io
import json
import logging
import time
from pathlib import Path
from typing import Optional

import pandas as pd
import requests
from tqdm import tqdm

from src.gwl_global.config import BRO_GLD_CSV_URL, BRO_REQUEST_DELAY, data_dir

logger = logging.getLogger(__name__)

PROGRESS_FILE = ".gwl_download_progress.json"
CHECKPOINT_INTERVAL = 50  # save progress every N wells


def _load_progress(output_dir: Path) -> set[str]:
    """Load set of already-downloaded GLD BRO IDs."""
    path = output_dir / PROGRESS_FILE
    if path.exists():
        with open(path) as f:
            return set(json.load(f).get("completed", []))
    return set()


def _save_progress(output_dir: Path, completed: set[str]):
    """Save download progress."""
    path = output_dir / PROGRESS_FILE
    with open(path, "w") as f:
        json.dump({"completed": sorted(completed)}, f)


def download_single_gwl(gld_bro_id: str, csv_url: str, output_dir: Path) -> Optional[Path]:
    """Download a single GLD time series as CSV.

    Tries the pre-built CSV URL first; falls back to the standard seriesAsCsv endpoint.

    Returns:
        Path to saved CSV, or None on failure.
    """
    ts_dir = output_dir / "timeseries"
    ts_dir.mkdir(parents=True, exist_ok=True)
    out_path = ts_dir / f"{gld_bro_id}_gwl.csv"

    # Prefer seriesAsCsv (returns all obs types in columns), then fall back to
    # the PDOK-provided assessed/preliminary CSV URL
    urls_to_try = [BRO_GLD_CSV_URL.format(bro_id=gld_bro_id)]
    if csv_url:
        urls_to_try.append(csv_url)

    for url in urls_to_try:
        try:
            resp = requests.get(url, timeout=120)
            if resp.status_code == 200 and len(resp.text.strip()) > 50:
                df = _parse_bro_csv(resp.text)
                if df is not None and len(df) > 0:
                    df.to_csv(out_path, index=True)
                    return out_path
        except Exception as exc:
            logger.warning("Failed to download %s from %s: %s", gld_bro_id, url, exc)

    logger.warning("No data retrieved for %s", gld_bro_id)
    return None


def _parse_bro_csv(text: str) -> Optional[pd.DataFrame]:
    """Parse BRO GLD CSV format.

    The seriesAsCsv endpoint returns comma-separated data with columns:
    Tijdstip, Voorlopige Waarde [m], Voorlopige Opmerking,
    Beoordeelde Waarde [m], Beoordeelde Opmerking,
    Controle Waarde [m], Controle Opmerking,
    Onbekend Waarde [m], Onbekend Opmerking

    The objectsAsCsv endpoint may use semicolons.

    We coalesce value columns: prefer Beoordeelde > Voorlopige > Controle > Onbekend.

    Returns DataFrame with DatetimeIndex and column: gwl_m_nap
    """
    try:
        # Skip comment lines (start with #)
        lines = [line for line in text.strip().split("\n") if not line.startswith("#")]
        if len(lines) < 2:
            return None

        # Auto-detect separator
        header = lines[0]
        sep = ";" if header.count(";") > header.count(",") else ","

        df = pd.read_csv(io.StringIO("\n".join(lines)), sep=sep, skipinitialspace=True)

        # Find the timestamp column
        time_col = None
        for c in df.columns:
            if "tijdstip" in c.lower() or "time" in c.lower():
                time_col = c
                break
        if time_col is None:
            time_col = df.columns[0]

        # Find value columns in priority order and coalesce
        value_cols = []
        for pattern in ["beoordeelde waarde", "voorlopige waarde", "controle waarde", "onbekend waarde"]:
            for c in df.columns:
                if pattern in c.lower():
                    value_cols.append(c)
                    break

        if not value_cols:
            # Fallback: use second column
            if len(df.columns) >= 2:
                value_cols = [df.columns[1]]
            else:
                return None

        # Coalesce: take first non-NaN value across priority columns
        gwl_values = pd.to_numeric(df[value_cols[0]], errors="coerce")
        for vc in value_cols[1:]:
            fallback = pd.to_numeric(df[vc], errors="coerce")
            gwl_values = gwl_values.fillna(fallback)

        result = pd.DataFrame()
        result["date"] = pd.to_datetime(df[time_col], utc=True, format="mixed", errors="coerce")
        result["gwl_m_nap"] = gwl_values
        result = result.dropna(subset=["date"])
        result = result.set_index("date").sort_index()

        # Convert to CET then drop timezone
        result.index = result.index.tz_convert("Europe/Amsterdam").tz_localize(None)

        return result

    except Exception as exc:
        logger.warning("CSV parse error: %s", exc)
        return None


def run_gwl_download(
    gld_index_path: Optional[Path] = None,
    output_dir: Optional[Path] = None,
) -> int:
    """Download all GLD time series listed in gld_index.csv.

    Returns:
        Number of successfully downloaded series.
    """
    output_dir = output_dir or data_dir()
    if gld_index_path is None:
        # Prefer pre-filtered index (date span >= 10yr) if available
        filtered = output_dir / "gld_index_filtered.csv"
        gld_index_path = filtered if filtered.exists() else (output_dir / "gld_index.csv")

    gld_df = pd.read_csv(gld_index_path)
    completed = _load_progress(output_dir)

    # Count existing CSV files (not just "completed" attempts, which include failures)
    ts_dir = output_dir / "timeseries"
    n_success = len(list(ts_dir.glob("*_gwl.csv"))) if ts_dir.exists() else 0

    pending = gld_df[~gld_df["gld_bro_id"].isin(completed)]
    logger.info(
        "GWL download: %d total, %d already done, %d pending.",
        len(gld_df),
        len(completed),
        len(pending),
    )

    for i, row in tqdm(pending.iterrows(), total=len(pending), desc="Downloading GWL"):
        gld_id = row["gld_bro_id"]
        csv_url = row.get("csv_url_assessed", "") or ""

        path = download_single_gwl(gld_id, csv_url, output_dir)
        if path:
            n_success += 1
        completed.add(gld_id)

        if len(completed) % CHECKPOINT_INTERVAL == 0:
            _save_progress(output_dir, completed)

        time.sleep(BRO_REQUEST_DELAY)

    _save_progress(output_dir, completed)
    logger.info("Download complete: %d/%d successful.", n_success, len(gld_df))
    return n_success

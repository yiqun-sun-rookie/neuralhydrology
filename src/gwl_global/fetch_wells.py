"""Discover BRO groundwater wells and GLD dossiers via PDOK OGC API Features."""
import logging
import time
from pathlib import Path
from typing import Optional

import pandas as pd
import requests
from tqdm import tqdm

from src.gwl_global.config import PDOK_OGC_BASE, NL_BBOX, BRO_REQUEST_DELAY, data_dir

logger = logging.getLogger(__name__)

ITEMS_PER_PAGE = 500


def fetch_collection_items(
    collection: str,
    bbox: tuple[float, float, float, float] = NL_BBOX,
    limit: int = ITEMS_PER_PAGE,
    max_pages: int = 0,
) -> list[dict]:
    """Fetch all features from a PDOK OGC collection with cursor pagination.

    Args:
        collection: e.g. "gm_gmw" or "gm_gld"
        bbox: (min_lon, min_lat, max_lon, max_lat)
        limit: items per page
        max_pages: stop after N pages (0 = unlimited)

    Returns:
        List of GeoJSON feature dicts.
    """
    url = f"{PDOK_OGC_BASE}/collections/{collection}/items"
    params = {
        "f": "json",
        "limit": limit,
        "bbox": f"{bbox[0]},{bbox[1]},{bbox[2]},{bbox[3]}",
        "crs": "http://www.opengis.net/def/crs/OGC/1.3/CRS84",
    }

    all_features = []
    page = 0

    with tqdm(desc=f"Fetching {collection}", unit=" features") as pbar:
        while True:
            resp = requests.get(url, params=params, timeout=60)
            resp.raise_for_status()
            data = resp.json()

            features = data.get("features", [])
            all_features.extend(features)
            pbar.update(len(features))

            page += 1
            if max_pages and page >= max_pages:
                logger.info("Reached max_pages=%d, stopping.", max_pages)
                break

            # Find next cursor
            next_link = None
            for link in data.get("links", []):
                if link.get("rel") == "next":
                    next_link = link["href"]
                    break

            if not next_link or not features:
                break

            # Use the full next URL (contains cursor param)
            url = next_link
            params = {}  # params are embedded in next_link
            time.sleep(BRO_REQUEST_DELAY)

    logger.info("Fetched %d features from %s.", len(all_features), collection)
    return all_features


def extract_well_metadata(features: list[dict]) -> pd.DataFrame:
    """Extract well metadata from gm_gmw GeoJSON features."""
    rows = []
    for f in features:
        props = f.get("properties", {})
        geom = f.get("geometry", {})
        coords = geom.get("coordinates", [None, None]) if geom else [None, None]

        rows.append({
            "bro_id": props.get("bro_id", ""),
            "lon": coords[0] if coords else None,
            "lat": coords[1] if coords else None,
            "well_code": props.get("well_code", ""),
            "owner": props.get("bronhouder", ""),
            "quality_regime": props.get("quality_regime", ""),
            "n_tubes": props.get("number_of_monitoringtubes", None),
            "ground_level_m_nap": props.get("ground_level_position", None),
        })
    return pd.DataFrame(rows)


def extract_gld_index(features: list[dict]) -> pd.DataFrame:
    """Extract GLD dossier index from gm_gld GeoJSON features."""
    rows = []
    for f in features:
        props = f.get("properties", {})
        geom = f.get("geometry", {})
        coords = geom.get("coordinates", [None, None]) if geom else [None, None]

        rows.append({
            "gld_bro_id": props.get("bro_id", ""),
            "gmw_bro_id": props.get("gm_gmw_bro_id", ""),
            "tube_number": props.get("tube_number", None),
            "lon": coords[0] if coords else None,
            "lat": coords[1] if coords else None,
            "csv_url_assessed": props.get("series_fully_assessed_csv_url", ""),
            "csv_url_preliminary": props.get("series_preliminary_csv_url", ""),
            "first_date": props.get("first_date", ""),
            "last_date": props.get("last_date", ""),
        })
    return pd.DataFrame(rows)


def run_well_discovery(
    output_dir: Optional[Path] = None,
    bbox: tuple[float, float, float, float] = NL_BBOX,
    max_pages: int = 0,
) -> tuple[pd.DataFrame, pd.DataFrame]:
    """Discover all wells and GLD dossiers, save to CSV.

    Returns:
        (wells_df, gld_index_df)
    """
    output_dir = output_dir or data_dir()
    output_dir.mkdir(parents=True, exist_ok=True)

    # Step 1: Fetch wells
    logger.info("Discovering wells in bbox %s ...", bbox)
    well_features = fetch_collection_items("gm_gmw", bbox=bbox, max_pages=max_pages)
    wells_df = extract_well_metadata(well_features)
    wells_path = output_dir / "wells.csv"
    wells_df.to_csv(wells_path, index=False)
    logger.info("Saved %d wells to %s", len(wells_df), wells_path)

    # Step 2: Fetch GLD index
    logger.info("Discovering GLD dossiers in bbox %s ...", bbox)
    gld_features = fetch_collection_items("gm_gld", bbox=bbox, max_pages=max_pages)
    gld_df = extract_gld_index(gld_features)
    gld_path = output_dir / "gld_index.csv"
    gld_df.to_csv(gld_path, index=False)
    logger.info("Saved %d GLD records to %s", len(gld_df), gld_path)

    return wells_df, gld_df

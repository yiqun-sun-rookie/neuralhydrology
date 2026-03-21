"""Discover BRO groundwater wells and GLD dossiers via PDOK OGC API Features."""
import logging
import time
from pathlib import Path
from typing import Optional

import pandas as pd
import requests
from tqdm import tqdm

from src.gwl_global.config import PDOK_OGC_BASE, NL_BBOX, BRO_REQUEST_DELAY, TILE_SIZE_DEG, data_dir

logger = logging.getLogger(__name__)

ITEMS_PER_PAGE = 75  # PDOK API max page size


def _generate_tiles(
    bbox: tuple[float, float, float, float],
    tile_size: float = TILE_SIZE_DEG,
) -> list[tuple[float, float, float, float]]:
    """Split a large bbox into tiles of at most tile_size degrees."""
    min_lon, min_lat, max_lon, max_lat = bbox
    tiles = []
    lat = min_lat
    while lat < max_lat:
        lon = min_lon
        while lon < max_lon:
            tiles.append((
                lon,
                lat,
                min(lon + tile_size, max_lon),
                min(lat + tile_size, max_lat),
            ))
            lon += tile_size
        lat += tile_size
    return tiles


def _fetch_single_bbox(
    collection: str,
    bbox: tuple[float, float, float, float],
    limit: int = ITEMS_PER_PAGE,
    max_pages: int = 0,
) -> list[dict]:
    """Fetch all features from one bbox with cursor pagination."""
    url = f"{PDOK_OGC_BASE}/collections/{collection}/items"
    params = {
        "f": "json",
        "limit": limit,
        "bbox": f"{bbox[0]},{bbox[1]},{bbox[2]},{bbox[3]}",
        "crs": "http://www.opengis.net/def/crs/OGC/1.3/CRS84",
    }

    features = []
    page = 0
    while True:
        resp = requests.get(url, params=params, timeout=60)
        resp.raise_for_status()
        data = resp.json()

        batch = data.get("features", [])
        features.extend(batch)

        page += 1
        if max_pages and page >= max_pages:
            break

        next_link = None
        for link in data.get("links", []):
            if link.get("rel") == "next":
                next_link = link["href"]
                break

        if not next_link or not batch:
            break

        url = next_link
        params = {}
        time.sleep(BRO_REQUEST_DELAY)

    return features


def fetch_collection_items(
    collection: str,
    bbox: tuple[float, float, float, float] = NL_BBOX,
    limit: int = ITEMS_PER_PAGE,
    max_pages: int = 0,
) -> list[dict]:
    """Fetch all features from a PDOK OGC collection, tiling large bboxes.

    The PDOK API rejects bboxes wider than ~0.5 degrees, so we split
    large areas into tiles and deduplicate by feature id.

    Args:
        collection: e.g. "gm_gmw" or "gm_gld"
        bbox: (min_lon, min_lat, max_lon, max_lat)
        limit: items per page (max 75)
        max_pages: stop after N pages per tile (0 = unlimited)

    Returns:
        List of GeoJSON feature dicts (deduplicated).
    """
    tiles = _generate_tiles(bbox)
    all_features = []
    seen_ids = set()

    with tqdm(total=len(tiles), desc=f"Fetching {collection}", unit=" tiles") as pbar:
        for tile in tiles:
            batch = _fetch_single_bbox(collection, tile, limit=limit, max_pages=max_pages)
            for f in batch:
                fid = f.get("id") or f.get("properties", {}).get("bro_id", "")
                if fid and fid not in seen_ids:
                    seen_ids.add(fid)
                    all_features.append(f)
            pbar.update(1)

    logger.info("Fetched %d unique features from %s across %d tiles.",
                len(all_features), collection, len(tiles))
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
            "owner": props.get("owner", ""),
            "quality_regime": props.get("quality_regime", ""),
            "n_tubes": props.get("number_of_monitoring_tubes", None),
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

        # Get GMW bro_id from monitoringtube href (e.g. .../gm_gmw_monitoringtube/229)
        tube_href = props.get("gm_gmw_monitoringtube.href", "")

        rows.append({
            "gld_bro_id": props.get("bro_id", ""),
            "tube_href": tube_href,
            "lon": coords[0] if coords else None,
            "lat": coords[1] if coords else None,
            "csv_url_assessed": props.get("series_fully_assessed_csv_url", ""),
            "csv_url_preliminary": props.get("series_preliminary_csv_url", ""),
            "research_first_date": props.get("research_first_date", ""),
            "research_last_date": props.get("research_last_date", ""),
        })
    return pd.DataFrame(rows)


def prefilter_gld_by_date(
    gld_df: pd.DataFrame,
    min_years: float = 10.0,
) -> pd.DataFrame:
    """Pre-filter GLD index by date span to avoid downloading short series.

    Args:
        gld_df: GLD index with research_first_date and research_last_date columns.
        min_years: minimum span in years.

    Returns:
        Filtered DataFrame.
    """
    df = gld_df.copy()
    df["research_first_date"] = pd.to_datetime(df["research_first_date"], errors="coerce")
    df["research_last_date"] = pd.to_datetime(df["research_last_date"], errors="coerce")

    span_days = (df["research_last_date"] - df["research_first_date"]).dt.days
    mask = span_days >= min_years * 365.25
    filtered = df[mask].copy()

    logger.info("Pre-filter: %d / %d GLD records have >= %.0f years span.",
                len(filtered), len(df), min_years)
    return filtered


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

    # Step 3: Pre-filter by date span
    gld_filtered = prefilter_gld_by_date(gld_df)
    filtered_path = output_dir / "gld_index_filtered.csv"
    gld_filtered.to_csv(filtered_path, index=False)
    logger.info("Saved %d pre-filtered GLD records to %s", len(gld_filtered), filtered_path)

    return wells_df, gld_df

# GWL Global Phase 0: Netherlands Data Acquisition

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fetch Dutch groundwater levels (BRO) and weather data (KNMI), quality-filter, merge, and output training-ready CSVs.

**Architecture:** Six focused modules under `src/gwl_global/`: config (constants), fetch_wells (PDOK OGC API discovery), fetch_gwl (BRO GLD CSV download with checkpoint/resume), fetch_knmi (KNMI daily P+ET), quality (QC filtering), merge (align+join). A single orchestrator script `run_phase0.py` chains them.

**Tech Stack:** Python 3.11, requests, pandas, numpy, tqdm, lxml (XML fallback). No auth needed for any API.

---

## API Reference (verified 2026-03-19)

### PDOK OGC API Features (well discovery)
- Base: `https://api.pdok.nl/bzk/bro-gminsamenhang-karakteristieken/ogc/v1`
- Collections: `gm_gmw` (wells), `gm_gld` (GLD dossiers with CSV URLs)
- Bbox filter: `?bbox=minLon,minLat,maxLon,maxLat&f=json`
- Pagination: cursor-based (`next` link in response)
- Output CRS: CRS84 (WGS84 lon/lat) by default
- GLD features include `series_fully_assessed_csv_url` field → direct CSV download

### BRO Dispatch (time series download)
- GLD CSV: `https://publiek.broservices.nl/gm/gld/v1/seriesAsCsv/{broId}?asISO8601=JA`
- GMW detail: `https://publiek.broservices.nl/gm/gmw/v1/objects/{broId}` (XML)
- No auth, no documented rate limit

### KNMI Daggegevens
- URL: `https://www.daggegevens.knmi.nl/klimatologie/daggegevens` (POST)
- Params: `stns`, `vars`, `start`, `end`, `fmt=json`
- Units: 0.1 mm for RH and EV24 (divide by 10)
- Special: RH = -1 means trace (< 0.05 mm) → convert to 0.025

---

## File Structure

```
src/gwl_global/
├── __init__.py              # Package marker
├── config.py                # API URLs, bbox, KNMI station list, path helpers
├── fetch_wells.py           # PDOK OGC: paginated well+GLD discovery
├── fetch_gwl.py             # BRO GLD: download CSV time series w/ checkpoint
├── fetch_knmi.py            # KNMI: download daily P+ET per station
├── quality.py               # QC: length, gap rate, jump detection, frequency
├── merge.py                 # Align GWL + KNMI by date, output merged CSV
├── scripts/
│   ├── __init__.py
│   └── run_phase0.py        # CLI orchestrator: chain all steps

data/nl/                     # Output (gitignored)
├── wells.csv                # Well metadata
├── gld_index.csv            # GLD→well mapping with CSV URLs
├── quality_check.csv        # QC results per well
├── summary.json             # Aggregate stats
├── timeseries/              # {bro_id}_gwl.csv
├── meteo/                   # knmi_{stn}_daily.csv
└── merged/                  # {bro_id}_merged.csv

test/
├── test_gwl_global_config.py
├── test_gwl_global_quality.py
└── test_gwl_global_merge.py
```

---

## Task 1: Project Scaffold + Config

**Files:**
- Create: `src/gwl_global/__init__.py`
- Create: `src/gwl_global/config.py`
- Create: `src/gwl_global/scripts/__init__.py`
- Create: `test/test_gwl_global_config.py`
- Modify: `draft/RESEARCH_INDEX.md` (add ID 08)
- Create: `draft/ideas/08_gwl_global.md`

- [ ] **Step 1: Register idea in RESEARCH_INDEX.md**

Add row to 任务总表:
```
| 08 | gwl_global | dev | `draft/ideas/08_gwl_global.md` | `src/gwl_global/` | `results/08_gwl_global/` | `logs/08_gwl_global/` |
```

- [ ] **Step 2: Create idea doc**

Create `draft/ideas/08_gwl_global.md` with project overview (copy the core spec: dual-scale LSTM, MoE, 5-phase plan).

- [ ] **Step 3: Write config test**

```python
# test/test_gwl_global_config.py
import pytest
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "src"))

from gwl_global.config import (
    PDOK_OGC_BASE, BRO_GLD_CSV_URL, KNMI_DAG_URL,
    NL_BBOX, KNMI_STATIONS, data_dir, knmi_station_for_coord,
)


def test_api_urls_are_strings():
    assert isinstance(PDOK_OGC_BASE, str)
    assert "api.pdok.nl" in PDOK_OGC_BASE
    assert isinstance(BRO_GLD_CSV_URL, str)
    assert isinstance(KNMI_DAG_URL, str)


def test_nl_bbox_has_four_floats():
    assert len(NL_BBOX) == 4
    min_lon, min_lat, max_lon, max_lat = NL_BBOX
    assert min_lon < max_lon
    assert min_lat < max_lat


def test_knmi_stations_have_required_fields():
    assert len(KNMI_STATIONS) >= 30
    for stn in KNMI_STATIONS:
        assert "stn" in stn
        assert "lat" in stn
        assert "lon" in stn
        assert "name" in stn


def test_knmi_station_for_coord():
    # De Bilt is at (52.10, 5.18), should match station 260
    stn = knmi_station_for_coord(52.10, 5.18)
    assert stn == 260


def test_data_dir_returns_path(tmp_path, monkeypatch):
    monkeypatch.setenv("GWL_DATA_DIR", str(tmp_path))
    d = data_dir()
    assert isinstance(d, Path)
```

- [ ] **Step 4: Run test to verify it fails**

Run: `pytest test/test_gwl_global_config.py -v`
Expected: FAIL (module not found)

- [ ] **Step 5: Write config.py**

```python
# src/gwl_global/config.py
"""Constants and helpers for GWL Global Phase 0 data acquisition."""
from pathlib import Path
import math
import os

# --- API endpoints (verified 2026-03-19) ---
PDOK_OGC_BASE = "https://api.pdok.nl/bzk/bro-gminsamenhang-karakteristieken/ogc/v1"
BRO_GLD_CSV_URL = "https://publiek.broservices.nl/gm/gld/v1/seriesAsCsv/{bro_id}?asISO8601=JA"
BRO_GMW_URL = "https://publiek.broservices.nl/gm/gmw/v1/objects/{bro_id}"
KNMI_DAG_URL = "https://www.daggegevens.knmi.nl/klimatologie/daggegevens"

# Netherlands bounding box (WGS84: min_lon, min_lat, max_lon, max_lat)
NL_BBOX = (3.3, 50.7, 7.3, 53.6)

# Request pacing (seconds)
BRO_REQUEST_DELAY = 0.2
KNMI_REQUEST_DELAY = 1.0

# QC thresholds
MIN_SERIES_YEARS = 10
MAX_GAP_FRACTION = 0.20
MAX_JUMP_FRACTION = 0.01
MIN_OBS_FREQUENCY_DAYS = 7  # exclude stations with median interval > 7 days

# KNMI stations: stn, lon, lat, name (52 stations, subset with RH+EV24)
KNMI_STATIONS = [
    {"stn": 209, "lon": 4.518, "lat": 52.465, "name": "IJmond"},
    {"stn": 210, "lon": 4.430, "lat": 52.171, "name": "Valkenburg Zh"},
    {"stn": 215, "lon": 4.437, "lat": 52.141, "name": "Voorschoten"},
    {"stn": 225, "lon": 4.555, "lat": 52.463, "name": "IJmuiden"},
    {"stn": 235, "lon": 4.781, "lat": 52.928, "name": "De Kooy"},
    {"stn": 240, "lon": 4.790, "lat": 52.318, "name": "Schiphol"},
    {"stn": 242, "lon": 4.921, "lat": 53.241, "name": "Vlieland"},
    {"stn": 248, "lon": 5.174, "lat": 52.634, "name": "Wijdenes"},
    {"stn": 249, "lon": 4.979, "lat": 52.644, "name": "Berkhout"},
    {"stn": 251, "lon": 5.346, "lat": 53.392, "name": "Hoorn Terschelling"},
    {"stn": 257, "lon": 4.603, "lat": 52.506, "name": "Wijk aan Zee"},
    {"stn": 258, "lon": 5.401, "lat": 52.649, "name": "Houtribdijk"},
    {"stn": 260, "lon": 5.180, "lat": 52.100, "name": "De Bilt"},
    {"stn": 265, "lon": 5.274, "lat": 52.130, "name": "Soesterberg"},
    {"stn": 267, "lon": 5.384, "lat": 52.898, "name": "Stavoren"},
    {"stn": 269, "lon": 5.520, "lat": 52.458, "name": "Lelystad"},
    {"stn": 270, "lon": 5.752, "lat": 53.224, "name": "Leeuwarden"},
    {"stn": 273, "lon": 5.888, "lat": 52.703, "name": "Marknesse"},
    {"stn": 275, "lon": 5.873, "lat": 52.056, "name": "Deelen"},
    {"stn": 277, "lon": 6.200, "lat": 53.413, "name": "Lauwersoog"},
    {"stn": 278, "lon": 6.259, "lat": 52.435, "name": "Heino"},
    {"stn": 279, "lon": 6.574, "lat": 52.750, "name": "Hoogeveen"},
    {"stn": 280, "lon": 6.585, "lat": 53.125, "name": "Eelde"},
    {"stn": 283, "lon": 6.657, "lat": 52.069, "name": "Hupsel"},
    {"stn": 285, "lon": 6.399, "lat": 53.575, "name": "Huibertgat"},
    {"stn": 286, "lon": 7.150, "lat": 53.196, "name": "Nieuw Beerta"},
    {"stn": 290, "lon": 6.891, "lat": 52.274, "name": "Twenthe"},
    {"stn": 308, "lon": 3.379, "lat": 51.381, "name": "Cadzand"},
    {"stn": 310, "lon": 3.596, "lat": 51.442, "name": "Vlissingen"},
    {"stn": 311, "lon": 3.672, "lat": 51.379, "name": "Hoofdplaat"},
    {"stn": 312, "lon": 3.622, "lat": 51.768, "name": "Oosterschelde"},
    {"stn": 313, "lon": 3.242, "lat": 51.505, "name": "Vlakte van De Raan"},
    {"stn": 315, "lon": 3.998, "lat": 51.447, "name": "Hansweert"},
    {"stn": 316, "lon": 3.694, "lat": 51.657, "name": "Schaar"},
    {"stn": 319, "lon": 3.861, "lat": 51.226, "name": "Westdorpe"},
    {"stn": 323, "lon": 3.884, "lat": 51.527, "name": "Wilhelminadorp"},
    {"stn": 324, "lon": 4.006, "lat": 51.596, "name": "Stavenisse"},
    {"stn": 330, "lon": 4.122, "lat": 51.992, "name": "Hoek van Holland"},
    {"stn": 331, "lon": 4.193, "lat": 51.480, "name": "Tholen"},
    {"stn": 340, "lon": 4.342, "lat": 51.449, "name": "Woensdrecht"},
    {"stn": 343, "lon": 4.313, "lat": 51.893, "name": "Rotterdam Geulhaven"},
    {"stn": 344, "lon": 4.447, "lat": 51.962, "name": "Rotterdam"},
    {"stn": 348, "lon": 4.926, "lat": 51.970, "name": "Cabauw Mast"},
    {"stn": 350, "lon": 4.936, "lat": 51.566, "name": "Gilze-Rijen"},
    {"stn": 356, "lon": 5.146, "lat": 51.859, "name": "Herwijnen"},
    {"stn": 370, "lon": 5.377, "lat": 51.451, "name": "Eindhoven"},
    {"stn": 375, "lon": 5.707, "lat": 51.659, "name": "Volkel"},
    {"stn": 377, "lon": 5.763, "lat": 51.198, "name": "Ell"},
    {"stn": 380, "lon": 5.762, "lat": 50.906, "name": "Maastricht"},
    {"stn": 391, "lon": 6.197, "lat": 51.498, "name": "Arcen"},
    {"stn": 392, "lon": 6.056, "lat": 51.487, "name": "Horst"},
]


def data_dir() -> Path:
    """Return data output directory. Override with GWL_DATA_DIR env var."""
    env = os.environ.get("GWL_DATA_DIR")
    if env:
        return Path(env)
    return Path(__file__).resolve().parent.parent.parent / "data" / "nl"


def knmi_station_for_coord(lat: float, lon: float) -> int:
    """Return nearest KNMI station number for a given WGS84 coordinate."""
    best_stn = KNMI_STATIONS[0]["stn"]
    best_dist = float("inf")
    for s in KNMI_STATIONS:
        d = math.hypot(lat - s["lat"], lon - s["lon"])
        if d < best_dist:
            best_dist = d
            best_stn = s["stn"]
    return best_stn
```

- [ ] **Step 6: Create `__init__.py` files**

```python
# src/gwl_global/__init__.py
# src/gwl_global/scripts/__init__.py
# (empty files)
```

- [ ] **Step 7: Run test to verify it passes**

Run: `pytest test/test_gwl_global_config.py -v`
Expected: PASS (all 5 tests)

- [ ] **Step 8: Commit**

```bash
git add src/gwl_global/__init__.py src/gwl_global/config.py \
        src/gwl_global/scripts/__init__.py \
        test/test_gwl_global_config.py \
        draft/RESEARCH_INDEX.md draft/ideas/08_gwl_global.md
git commit -m "feat(gwl_global): scaffold project + config with API endpoints and KNMI stations"
```

---

## Task 2: Well Discovery (PDOK OGC API)

**Files:**
- Create: `src/gwl_global/fetch_wells.py`
- Test: manual smoke test (live API)

- [ ] **Step 1: Write fetch_wells.py**

```python
# src/gwl_global/fetch_wells.py
"""Discover BRO groundwater wells and GLD dossiers via PDOK OGC API Features."""
import json
import logging
import time
from pathlib import Path
from typing import Optional

import pandas as pd
import requests
from tqdm import tqdm

from gwl_global.config import PDOK_OGC_BASE, NL_BBOX, BRO_REQUEST_DELAY, data_dir

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
        coords = geom.get("coordinates", [None, None])

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
        coords = geom.get("coordinates", [None, None])

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
```

- [ ] **Step 2: Smoke test with small bbox (Utrecht)**

Run manually:
```bash
cd G:/github/pycharm/projects/neuralhydrology
python -c "
import sys; sys.path.insert(0, 'src')
from gwl_global.fetch_wells import run_well_discovery
from pathlib import Path
w, g = run_well_discovery(Path('data/nl'), bbox=(5.0,52.0,5.3,52.2), max_pages=2)
print(f'Wells: {len(w)}, GLD: {len(g)}')
print(w.head())
print(g.head())
"
```

Verify: wells.csv and gld_index.csv created with >0 rows. If API returns different property names, adjust `extract_well_metadata` / `extract_gld_index` accordingly.

- [ ] **Step 3: Commit**

```bash
git add src/gwl_global/fetch_wells.py
git commit -m "feat(gwl_global): well discovery via PDOK OGC API with cursor pagination"
```

---

## Task 3: GWL Time Series Download (with checkpoint/resume)

**Files:**
- Create: `src/gwl_global/fetch_gwl.py`
- Test: manual smoke test

- [ ] **Step 1: Write fetch_gwl.py**

```python
# src/gwl_global/fetch_gwl.py
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

from gwl_global.config import BRO_GLD_CSV_URL, BRO_REQUEST_DELAY, data_dir

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

    # Try the direct CSV URL from PDOK index
    urls_to_try = []
    if csv_url:
        urls_to_try.append(csv_url)
    urls_to_try.append(BRO_GLD_CSV_URL.format(bro_id=gld_bro_id))

    for url in urls_to_try:
        try:
            resp = requests.get(url, timeout=120)
            if resp.status_code == 200 and len(resp.text.strip()) > 50:
                # Parse the BRO CSV format
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

    Expected columns (Dutch):
    Tijdstip | Voorlopige Waarde [m] | ... | Beoordeelde Waarde [m] | ...

    Returns DataFrame with columns: date, gwl_m_nap
    """
    try:
        # Skip comment lines (start with #)
        lines = [l for l in text.strip().split("\n") if not l.startswith("#")]
        if len(lines) < 2:
            return None

        df = pd.read_csv(io.StringIO("\n".join(lines)), sep=";", skipinitialspace=True)

        # Find the timestamp column
        time_col = None
        for c in df.columns:
            if "tijdstip" in c.lower() or "time" in c.lower():
                time_col = c
                break
        if time_col is None:
            time_col = df.columns[0]

        # Find the best value column (prefer assessed > preliminary > unknown)
        val_col = None
        for pattern in ["beoordeelde waarde", "assessed", "voorlopige waarde", "preliminary", "waarde"]:
            for c in df.columns:
                if pattern in c.lower():
                    val_col = c
                    break
            if val_col:
                break
        if val_col is None and len(df.columns) >= 2:
            val_col = df.columns[1]

        if val_col is None:
            return None

        result = pd.DataFrame()
        result["date"] = pd.to_datetime(df[time_col], utc=True, errors="coerce")
        result["gwl_m_nap"] = pd.to_numeric(df[val_col], errors="coerce")
        result = result.dropna(subset=["date"])
        result = result.set_index("date").sort_index()

        # Localize to CET then drop timezone for simplicity
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
    gld_index_path = gld_index_path or (output_dir / "gld_index.csv")

    gld_df = pd.read_csv(gld_index_path)
    completed = _load_progress(output_dir)
    n_success = len(completed)

    pending = gld_df[~gld_df["gld_bro_id"].isin(completed)]
    logger.info(
        "GWL download: %d total, %d already done, %d pending.",
        len(gld_df), len(completed), len(pending),
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
```

- [ ] **Step 2: Smoke test with a known GLD ID**

```bash
cd G:/github/pycharm/projects/neuralhydrology
python -c "
import sys; sys.path.insert(0, 'src')
from gwl_global.fetch_gwl import download_single_gwl
from pathlib import Path
p = download_single_gwl('GLD000000012345', '', Path('data/nl'))
print(f'Result: {p}')
"
```

Adjust the GLD BRO ID based on actual IDs found in gld_index.csv from Task 2. The actual ID format may differ.

- [ ] **Step 3: Commit**

```bash
git add src/gwl_global/fetch_gwl.py
git commit -m "feat(gwl_global): GWL time series download with checkpoint/resume"
```

---

## Task 4: Quality Filtering

**Files:**
- Create: `src/gwl_global/quality.py`
- Create: `test/test_gwl_global_quality.py`

- [ ] **Step 1: Write quality test**

```python
# test/test_gwl_global_quality.py
import sys
from pathlib import Path

import numpy as np
import pandas as pd
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "src"))

from gwl_global.quality import check_series_quality


def _make_daily_series(n_days: int, gap_indices=None, jump_index=None):
    """Helper: create a synthetic daily GWL series."""
    dates = pd.date_range("2000-01-01", periods=n_days, freq="D")
    values = np.sin(np.arange(n_days) * 2 * np.pi / 365) * 0.5 - 2.0  # seasonal cycle
    if gap_indices:
        values[gap_indices] = np.nan
    if jump_index:
        values[jump_index:] += 5.0  # step change
    return pd.DataFrame({"gwl_m_nap": values}, index=dates)


def test_good_series_passes():
    df = _make_daily_series(365 * 12)
    result = check_series_quality(df)
    assert result["passed"]
    assert result["n_years"] >= 10
    assert result["gap_fraction"] < 0.01


def test_short_series_fails():
    df = _make_daily_series(365 * 5)
    result = check_series_quality(df)
    assert not result["passed"]
    assert "too_short" in result["fail_reasons"]


def test_gappy_series_fails():
    gaps = list(range(0, 365 * 12, 3))  # 33% missing
    df = _make_daily_series(365 * 12, gap_indices=gaps)
    result = check_series_quality(df)
    assert not result["passed"]
    assert "too_many_gaps" in result["fail_reasons"]


def test_jumpy_series_fails():
    df = _make_daily_series(365 * 12, jump_index=365 * 6)
    result = check_series_quality(df)
    assert not result["passed"]
    assert "too_many_jumps" in result["fail_reasons"]


def test_low_frequency_series_fails():
    # Monthly observations
    dates = pd.date_range("2000-01-01", periods=12 * 12, freq="MS")
    values = np.random.randn(len(dates))
    df = pd.DataFrame({"gwl_m_nap": values}, index=dates)
    result = check_series_quality(df)
    assert not result["passed"]
    assert "low_frequency" in result["fail_reasons"]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest test/test_gwl_global_quality.py -v`
Expected: FAIL (module not found)

- [ ] **Step 3: Write quality.py**

```python
# src/gwl_global/quality.py
"""Quality checks for groundwater level time series."""
import numpy as np
import pandas as pd

from gwl_global.config import (
    MIN_SERIES_YEARS, MAX_GAP_FRACTION, MAX_JUMP_FRACTION, MIN_OBS_FREQUENCY_DAYS,
)


def check_series_quality(df: pd.DataFrame) -> dict:
    """Run QC checks on a GWL time series DataFrame.

    Args:
        df: DataFrame with DatetimeIndex and column 'gwl_m_nap'.

    Returns:
        Dict with keys: passed, n_years, gap_fraction, jump_fraction,
        median_interval_days, fail_reasons.
    """
    result = {
        "passed": True,
        "n_years": 0.0,
        "gap_fraction": 0.0,
        "jump_fraction": 0.0,
        "median_interval_days": 0.0,
        "fail_reasons": [],
    }

    gwl = df["gwl_m_nap"].dropna()

    if len(gwl) < 2:
        result["passed"] = False
        result["fail_reasons"].append("too_short")
        return result

    # Span in years
    span_days = (gwl.index[-1] - gwl.index[0]).days
    result["n_years"] = span_days / 365.25

    if result["n_years"] < MIN_SERIES_YEARS:
        result["passed"] = False
        result["fail_reasons"].append("too_short")

    # Observation frequency (median interval between consecutive obs)
    intervals = pd.Series(gwl.index).diff().dt.days.dropna()
    result["median_interval_days"] = float(intervals.median()) if len(intervals) > 0 else 999.0

    if result["median_interval_days"] > MIN_OBS_FREQUENCY_DAYS:
        result["passed"] = False
        result["fail_reasons"].append("low_frequency")

    # Gap fraction: resample to daily, count NaN days
    daily = df["gwl_m_nap"].resample("D").mean()
    n_expected = len(daily)
    n_missing = daily.isna().sum()
    result["gap_fraction"] = float(n_missing / n_expected) if n_expected > 0 else 1.0

    if result["gap_fraction"] > MAX_GAP_FRACTION:
        result["passed"] = False
        result["fail_reasons"].append("too_many_gaps")

    # Jump detection: diff > 3 * IQR
    diff = gwl.diff().abs().dropna()
    if len(diff) > 10:
        q25, q75 = diff.quantile(0.25), diff.quantile(0.75)
        iqr = q75 - q25
        threshold = q75 + 3 * iqr if iqr > 0 else diff.median() * 10
        n_jumps = (diff > threshold).sum()
        result["jump_fraction"] = float(n_jumps / len(diff))

        if result["jump_fraction"] > MAX_JUMP_FRACTION:
            result["passed"] = False
            result["fail_reasons"].append("too_many_jumps")

    return result
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest test/test_gwl_global_quality.py -v`
Expected: PASS (all 5 tests)

- [ ] **Step 5: Commit**

```bash
git add src/gwl_global/quality.py test/test_gwl_global_quality.py
git commit -m "feat(gwl_global): quality filtering with length, gap, jump, frequency checks"
```

---

## Task 5: KNMI Weather Data Fetch

**Files:**
- Create: `src/gwl_global/fetch_knmi.py`

- [ ] **Step 1: Write fetch_knmi.py**

```python
# src/gwl_global/fetch_knmi.py
"""Download daily precipitation and evapotranspiration from KNMI."""
import logging
import time
from pathlib import Path
from typing import Optional

import pandas as pd
import requests

from gwl_global.config import KNMI_DAG_URL, KNMI_STATIONS, KNMI_REQUEST_DELAY, data_dir

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
        DataFrame with columns [date, P_mm, ET_mm] or None on failure.
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

    # Convert RH: 0.1mm → mm, -1 → 0.025 (trace), null → NaN
    rh = pd.to_numeric(df.get("RH"), errors="coerce")
    rh = rh.where(rh != -1, 0.25)  # -1 = trace < 0.05 mm, in 0.1mm units = 0.25
    df["P_mm"] = rh / 10.0

    # Convert EV24: 0.1mm → mm
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
```

- [ ] **Step 2: Smoke test**

```bash
cd G:/github/pycharm/projects/neuralhydrology
python -c "
import sys; sys.path.insert(0, 'src')
from gwl_global.fetch_knmi import download_knmi_station
df = download_knmi_station(260, '20200101', '20200110')
print(df)
print(f'Dtypes: {df.dtypes}')
"
```

Expected: 10 rows with P_mm and ET_mm as float64.

- [ ] **Step 3: Commit**

```bash
git add src/gwl_global/fetch_knmi.py
git commit -m "feat(gwl_global): KNMI daily P+ET download with unit conversion"
```

---

## Task 6: Merge + Summary

**Files:**
- Create: `src/gwl_global/merge.py`
- Create: `test/test_gwl_global_merge.py`

- [ ] **Step 1: Write merge test**

```python
# test/test_gwl_global_merge.py
import sys
from pathlib import Path

import numpy as np
import pandas as pd
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "src"))

from gwl_global.merge import merge_single_well, interpolate_short_gaps


def test_interpolate_short_gaps():
    s = pd.Series([1.0, np.nan, np.nan, 4.0, np.nan, np.nan, np.nan, np.nan, np.nan, np.nan, 10.0])
    result = interpolate_short_gaps(s, max_gap=5)
    # 2-day gap filled, 6-day gap NOT filled
    assert not np.isnan(result.iloc[1])
    assert not np.isnan(result.iloc[2])
    assert np.isnan(result.iloc[4])


def test_merge_single_well(tmp_path):
    # Create fake GWL
    dates_gwl = pd.date_range("2020-01-01", "2020-12-31", freq="D")
    gwl = pd.DataFrame({"gwl_m_nap": np.sin(np.arange(len(dates_gwl)) * 0.01) - 2.0}, index=dates_gwl)
    gwl_path = tmp_path / "timeseries" / "TEST001_gwl.csv"
    gwl_path.parent.mkdir(parents=True)
    gwl.to_csv(gwl_path, index_label="date")

    # Create fake KNMI
    dates_knmi = pd.date_range("2020-01-01", "2020-12-31", freq="D")
    knmi = pd.DataFrame({"P_mm": np.random.rand(len(dates_knmi)) * 5, "ET_mm": np.random.rand(len(dates_knmi)) * 3}, index=dates_knmi)
    knmi_path = tmp_path / "meteo" / "knmi_260_daily.csv"
    knmi_path.parent.mkdir(parents=True)
    knmi.to_csv(knmi_path, index_label="date")

    result = merge_single_well("TEST001", 260, tmp_path)
    assert result is not None
    assert "gwl_m_nap" in result.columns
    assert "P_mm" in result.columns
    assert "ET_mm" in result.columns
    assert len(result) == 366  # 2020 is leap year


def test_merge_saves_csv(tmp_path):
    # Same setup, check file output
    dates = pd.date_range("2020-01-01", "2020-06-30", freq="D")
    gwl = pd.DataFrame({"gwl_m_nap": np.ones(len(dates)) * -1.5}, index=dates)
    gwl_path = tmp_path / "timeseries" / "W001_gwl.csv"
    gwl_path.parent.mkdir(parents=True)
    gwl.to_csv(gwl_path, index_label="date")

    knmi = pd.DataFrame({"P_mm": np.ones(len(dates)) * 2.0, "ET_mm": np.ones(len(dates)) * 1.0}, index=dates)
    knmi_path = tmp_path / "meteo" / "knmi_260_daily.csv"
    knmi_path.parent.mkdir(parents=True)
    knmi.to_csv(knmi_path, index_label="date")

    result = merge_single_well("W001", 260, tmp_path, save=True)
    merged_path = tmp_path / "merged" / "W001_merged.csv"
    assert merged_path.exists()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest test/test_gwl_global_merge.py -v`
Expected: FAIL (module not found)

- [ ] **Step 3: Write merge.py**

```python
# src/gwl_global/merge.py
"""Merge GWL time series with KNMI weather data."""
import json
import logging
from pathlib import Path
from typing import Optional

import numpy as np
import pandas as pd

from gwl_global.config import data_dir, knmi_station_for_coord

logger = logging.getLogger(__name__)


def interpolate_short_gaps(series: pd.Series, max_gap: int = 5) -> pd.Series:
    """Linearly interpolate NaN gaps of <= max_gap consecutive days."""
    result = series.copy()
    mask = result.isna()
    if not mask.any():
        return result

    # Find gap lengths
    groups = (~mask).cumsum()
    gap_sizes = mask.groupby(groups).transform("sum")

    # Only interpolate short gaps
    short_gap_mask = mask & (gap_sizes <= max_gap)
    result = result.interpolate(method="linear")
    # Restore long gaps
    long_gap_mask = mask & (gap_sizes > max_gap)
    result[long_gap_mask] = np.nan

    return result


def merge_single_well(
    bro_id: str,
    knmi_stn: int,
    base_dir: Path,
    save: bool = False,
) -> Optional[pd.DataFrame]:
    """Merge a single well's GWL with KNMI weather data.

    Args:
        bro_id: BRO well/GLD identifier
        knmi_stn: KNMI station number
        base_dir: directory containing timeseries/ and meteo/
        save: if True, write merged CSV

    Returns:
        Merged DataFrame or None if insufficient overlap.
    """
    gwl_path = base_dir / "timeseries" / f"{bro_id}_gwl.csv"
    knmi_path = base_dir / "meteo" / f"knmi_{knmi_stn}_daily.csv"

    if not gwl_path.exists() or not knmi_path.exists():
        logger.warning("Missing files for %s (knmi %d)", bro_id, knmi_stn)
        return None

    gwl = pd.read_csv(gwl_path, parse_dates=["date"], index_col="date")
    knmi = pd.read_csv(knmi_path, parse_dates=["date"], index_col="date")

    # Resample GWL to daily (in case of sub-daily observations)
    gwl_daily = gwl["gwl_m_nap"].resample("D").mean()

    # Interpolate short gaps
    gwl_daily = interpolate_short_gaps(gwl_daily, max_gap=5)

    # Inner join
    merged = pd.DataFrame({"gwl_m_nap": gwl_daily})
    merged = merged.join(knmi[["P_mm", "ET_mm"]], how="inner")

    # Require at least 365 days of overlap
    if len(merged) < 365:
        logger.warning("%s: only %d overlapping days, skipping.", bro_id, len(merged))
        return None

    if save:
        out_dir = base_dir / "merged"
        out_dir.mkdir(parents=True, exist_ok=True)
        merged.to_csv(out_dir / f"{bro_id}_merged.csv", index_label="date")

    return merged


def run_merge(
    output_dir: Optional[Path] = None,
) -> dict:
    """Merge all QC-passed wells with their nearest KNMI station.

    Reads wells.csv for coordinates, quality_check.csv for QC pass list.

    Returns:
        Summary dict.
    """
    output_dir = output_dir or data_dir()

    wells = pd.read_csv(output_dir / "wells.csv")
    qc = pd.read_csv(output_dir / "quality_check.csv")
    gld_index = pd.read_csv(output_dir / "gld_index.csv")

    passed = qc[qc["passed"]]["bro_id"].tolist()
    logger.info("%d wells passed QC.", len(passed))

    n_merged = 0
    for bro_id in passed:
        # Find coordinates from gld_index or wells
        row = gld_index[gld_index["gld_bro_id"] == bro_id]
        if row.empty:
            row = wells[wells["bro_id"] == bro_id]
        if row.empty:
            continue

        lat = row.iloc[0].get("lat", None)
        lon = row.iloc[0].get("lon", None)
        if lat is None or lon is None:
            continue

        stn = knmi_station_for_coord(lat, lon)
        result = merge_single_well(bro_id, stn, output_dir, save=True)
        if result is not None:
            n_merged += 1

    # Write summary
    summary = {
        "total_wells_found": len(wells),
        "total_gld_records": len(gld_index),
        "wells_passed_qc": len(passed),
        "wells_with_merged_data": n_merged,
    }
    with open(output_dir / "summary.json", "w") as f:
        json.dump(summary, f, indent=2)

    logger.info("Merge complete: %s", summary)
    return summary
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest test/test_gwl_global_merge.py -v`
Expected: PASS (all 3 tests)

- [ ] **Step 5: Commit**

```bash
git add src/gwl_global/merge.py test/test_gwl_global_merge.py
git commit -m "feat(gwl_global): merge GWL+KNMI with short-gap interpolation"
```

---

## Task 7: Orchestrator Script + QC Runner

**Files:**
- Create: `src/gwl_global/scripts/run_phase0.py`

- [ ] **Step 1: Write run_phase0.py**

```python
# src/gwl_global/scripts/run_phase0.py
"""Phase 0 orchestrator: discover → download → QC → KNMI → merge."""
import argparse
import logging
import sys
from pathlib import Path

# Ensure src/ is on path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent))

import pandas as pd
from tqdm import tqdm

from gwl_global.config import data_dir, knmi_station_for_coord, NL_BBOX
from gwl_global.fetch_wells import run_well_discovery
from gwl_global.fetch_gwl import run_gwl_download
from gwl_global.fetch_knmi import run_knmi_download
from gwl_global.quality import check_series_quality
from gwl_global.merge import run_merge

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger(__name__)


def run_quality_check(output_dir: Path) -> pd.DataFrame:
    """Run QC on all downloaded GWL time series."""
    ts_dir = output_dir / "timeseries"
    if not ts_dir.exists():
        logger.error("No timeseries directory found at %s", ts_dir)
        return pd.DataFrame()

    files = sorted(ts_dir.glob("*_gwl.csv"))
    logger.info("Running QC on %d time series ...", len(files))

    rows = []
    for f in tqdm(files, desc="QC"):
        bro_id = f.stem.replace("_gwl", "")
        try:
            df = pd.read_csv(f, parse_dates=["date"], index_col="date")
            result = check_series_quality(df)
            result["bro_id"] = bro_id
            rows.append(result)
        except Exception as exc:
            rows.append({
                "bro_id": bro_id,
                "passed": False,
                "fail_reasons": [f"read_error: {exc}"],
            })

    qc_df = pd.DataFrame(rows)
    qc_path = output_dir / "quality_check.csv"
    qc_df.to_csv(qc_path, index=False)
    logger.info("QC: %d passed / %d total.", qc_df["passed"].sum(), len(qc_df))
    return qc_df


def main():
    parser = argparse.ArgumentParser(description="GWL Global Phase 0: NL data acquisition")
    parser.add_argument("--output-dir", type=str, default=None, help="Output directory")
    parser.add_argument("--bbox", type=float, nargs=4, default=list(NL_BBOX),
                        metavar=("MIN_LON", "MIN_LAT", "MAX_LON", "MAX_LAT"),
                        help="Bounding box (default: all Netherlands)")
    parser.add_argument("--max-pages", type=int, default=0,
                        help="Max pages for well discovery (0=unlimited)")
    parser.add_argument("--step", type=str, default="all",
                        choices=["discover", "download", "qc", "knmi", "merge", "all"],
                        help="Run a specific step or all")
    args = parser.parse_args()

    out = Path(args.output_dir) if args.output_dir else data_dir()
    bbox = tuple(args.bbox)

    steps = {
        "discover": lambda: run_well_discovery(out, bbox=bbox, max_pages=args.max_pages),
        "download": lambda: run_gwl_download(output_dir=out),
        "qc": lambda: run_quality_check(out),
        "knmi": lambda: run_knmi_download(output_dir=out),
        "merge": lambda: run_merge(output_dir=out),
    }

    if args.step == "all":
        for name, fn in steps.items():
            logger.info("=== Step: %s ===", name)
            fn()
    else:
        steps[args.step]()

    logger.info("Done.")


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Verify CLI help works**

```bash
cd G:/github/pycharm/projects/neuralhydrology
python src/gwl_global/scripts/run_phase0.py --help
```

Expected: help text with --output-dir, --bbox, --max-pages, --step options.

- [ ] **Step 3: Run small-bbox end-to-end smoke test**

```bash
python src/gwl_global/scripts/run_phase0.py \
    --bbox 5.0 52.0 5.3 52.2 \
    --max-pages 1 \
    --step all
```

This will test all steps with a minimal data subset (~50-100 wells).

- [ ] **Step 4: Commit**

```bash
git add src/gwl_global/scripts/run_phase0.py
git commit -m "feat(gwl_global): Phase 0 CLI orchestrator with per-step execution"
```

---

## Task 8: Add .gitignore for data + final cleanup

**Files:**
- Create: `data/nl/.gitignore`

- [ ] **Step 1: Create data gitignore**

```gitignore
# data/nl/.gitignore
# Downloaded data — too large for git
*.csv
*.json
timeseries/
meteo/
merged/
.gwl_download_progress.json
```

- [ ] **Step 2: Run full test suite**

```bash
pytest test/test_gwl_global_config.py test/test_gwl_global_quality.py test/test_gwl_global_merge.py -v
```

Expected: All tests pass.

- [ ] **Step 3: Final commit**

```bash
git add data/nl/.gitignore
git commit -m "chore(gwl_global): gitignore for downloaded data"
```

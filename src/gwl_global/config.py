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

# PDOK API tile size (degrees) — API rejects bbox wider than ~0.5°
TILE_SIZE_DEG = 0.5

# Request pacing (seconds)
BRO_REQUEST_DELAY = 0.2
KNMI_REQUEST_DELAY = 1.0

# QC thresholds
MIN_SERIES_YEARS = 10
MIN_OBS_COUNT = 200  # at least ~14 years of biweekly data
MIN_OBS_PER_YEAR = 50  # density filter: at least ~weekly frequency
MAX_GAP_DAYS = 730  # longest allowed data gap (2 years)
MAX_JUMP_FRACTION = 0.01
JUMP_ABS_THRESHOLD_M = 1.0  # absolute threshold for single-step GWL change (meters)

# KNMI stations: stn, lon, lat, name (52 stations)
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

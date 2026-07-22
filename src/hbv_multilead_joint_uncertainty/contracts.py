"""Human-readable and machine-verifiable input and parameter contracts."""

from __future__ import annotations

import json
import csv
import hashlib
from pathlib import Path

from hbv_joint_uncertainty.hbv_adapter import HYDRO_STATE_NAMES, PARAMETER_NAMES, V1_PARAMETER_BOUNDS


TRAINING_PROJECTION_COLUMNS = (
    "basin_id",
    "run_status",
    *(f"p_{name}" for name in PARAMETER_NAMES),
    *(f"state_{name}" for name in HYDRO_STATE_NAMES),
)


def csv_projection_sha256(path: Path, columns=TRAINING_PROJECTION_COLUMNS) -> str:
    """Hash only the named raw CSV fields so excluded performance fields cannot affect the contract."""
    selected = tuple(columns)
    digest = hashlib.sha256()
    with Path(path).open("r", encoding="utf-8", newline="") as handle:
        reader = csv.reader(handle)
        header = next(reader)
        if len(header) != len(set(header)):
            raise ValueError("CSV header contains duplicate columns")
        missing = set(selected) - set(header)
        if missing:
            raise ValueError(f"CSV projection is missing columns: {sorted(missing)}")
        indices = [header.index(column) for column in selected]
        digest.update((json.dumps(selected, separators=(",", ":")) + "\n").encode("utf-8"))
        for row in reader:
            if len(row) != len(header):
                raise ValueError("CSV row length does not match its header")
            values = [row[index] for index in indices]
            digest.update((json.dumps(values, separators=(",", ":")) + "\n").encode("utf-8"))
    return digest.hexdigest()


INPUT_CONTRACT = (
    {
        "variable_id": "precipitation",
        "raw_field": "PRCP(mm/day)",
        "raw_unit": "mm/day",
        "model_unit": "mm/day",
        "derivation": "identity",
        "future_availability": "historical_hindsight_only",
    },
    {
        "variable_id": "mean_temperature",
        "raw_field": "Tmax(C), Tmin(C)",
        "raw_unit": "degree_Celsius",
        "model_unit": "degree_Celsius",
        "derivation": "(Tmax + Tmin) / 2",
        "future_availability": "historical_hindsight_only",
    },
    {
        "variable_id": "potential_evapotranspiration",
        "raw_field": "SRAD(W/m2), Dayl(s), Tmax(C), Tmin(C), Vp(Pa)",
        "raw_unit": "mixed",
        "model_unit": "mm/day",
        "derivation": "Priestley-Taylor",
        "future_availability": "historical_hindsight_only",
    },
    {
        "variable_id": "streamflow",
        "raw_field": "discharge_cfs, area_gages2",
        "raw_unit": "cubic_feet_per_second",
        "model_unit": "mm/day",
        "derivation": "cubic_feet_per_second * 2.4466 / basin_area_km2",
        "future_availability": "forbidden_after_origin",
    },
)


PARAMETER_CONTRACT = {
    "parTT": {"meaning": "rain-snow threshold temperature", "unit": "degree_Celsius"},
    "parCFMAX": {"meaning": "degree-day snowmelt factor", "unit": "mm/degree_Celsius/day"},
    "parCFR": {"meaning": "refreezing fraction", "unit": "dimensionless"},
    "parCWH": {"meaning": "snow liquid-water holding fraction", "unit": "dimensionless"},
    "parFC": {"meaning": "soil field capacity", "unit": "mm"},
    "parBETA": {"meaning": "soil recharge curve exponent", "unit": "dimensionless"},
    "parLP": {"meaning": "soil wetness fraction for maximum evaporation", "unit": "dimensionless"},
    "parK0": {"meaning": "upper-zone fast recession coefficient", "unit": "1/day"},
    "parK1": {"meaning": "upper-zone recession coefficient", "unit": "1/day"},
    "parUZL": {"meaning": "upper-zone fast-flow threshold", "unit": "mm"},
    "parPERC": {"meaning": "upper-to-lower percolation rate", "unit": "mm/day"},
    "parK2": {"meaning": "lower-zone recession coefficient", "unit": "1/day"},
    "lag_time": {"meaning": "half-triangular routing memory", "unit": "day"},
}
for _name, _row in PARAMETER_CONTRACT.items():
    _row["bounds"] = list(V1_PARAMETER_BOUNDS[_name])


DEFAULT_CONFIG_PATH = Path("src/hbv_multilead_joint_uncertainty/configs/base_v02.json")


def load_base_config(repo_root: Path, config_path: Path | None = None) -> dict:
    root = Path(repo_root).resolve()
    relative = config_path or DEFAULT_CONFIG_PATH
    path = relative if Path(relative).is_absolute() else root / relative
    with Path(path).open("r", encoding="utf-8") as handle:
        config = json.load(handle)
    config["_loaded_config_path"] = Path(path).resolve().relative_to(root).as_posix()
    return config

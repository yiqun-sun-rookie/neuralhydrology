"""Static-only basin selection and independent meteorological quality gates."""

from __future__ import annotations

import hashlib
from collections.abc import Iterable, Sequence
from pathlib import Path

import numpy as np
import pandas as pd

from hbv_joint_uncertainty.candidates import sha256_file
from hbv_joint_uncertainty.hbv_adapter import HYDRO_STATE_NAMES, PARAMETER_NAMES, V1_PARAMETER_BOUNDS

from .contracts import TRAINING_PROJECTION_COLUMNS, csv_projection_sha256


SELECTION_SALT = "hbv-joint-uncertainty-frozen-v1"
CLIMATE_ORDER = ("snow", "humid", "semihumid", "arid")
CLIMATE_HASH_LABELS = {
    "snow": "snow-dominated",
    "humid": "humid",
    "semihumid": "semi-humid",
    "arid": "semi-arid/arid",
}
CELL_ORDER = (
    ("storage_infiltration", "small"),
    ("storage_infiltration", "large"),
    ("fast_response", "small"),
    ("fast_response", "large"),
)
EXPECTED_FORMAL_BASINS = (
    "12143600",
    "04127918",
    "09066000",
    "06431500",
    "03479000",
    "02296500",
    "02015700",
    "06892000",
    "05507600",
    "06477500",
    "08158700",
    "11148900",
    "06404000",
    "08189500",
    "09505350",
    "09447800",
)
EXPECTED_PARAMETER_TABLE_SHA256 = "9ef206779d94ffa1f11ab72b4528fd633861486f0a3b49b0ee1b40f52b3010a4"
EXPECTED_PARAMETER_CONTENT_SHA256 = "6c98022953bc28c705d81e973deea09005650daa27517765f33e8f496bd3891a"
STATIC_ATTRIBUTE_FILES = (
    "camels_clim.txt",
    "camels_topo.txt",
    "camels_soil.txt",
    "camels_vege.txt",
    "camels_name.txt",
)


def _normalized_ids(values: Iterable[str]) -> set[str]:
    return {str(value).strip().zfill(8) for value in values}


def selection_list_sha256(basin_ids: Sequence[str]) -> str:
    normalized = [str(value).strip().zfill(8) for value in basin_ids]
    if len(normalized) != len(set(normalized)) or not normalized:
        raise ValueError("basin_ids must be nonempty and unique")
    return hashlib.sha256(("\n".join(normalized) + "\n").encode("utf-8")).hexdigest()


def assign_static_strata(attributes: pd.DataFrame) -> pd.DataFrame:
    """Assign climate, response-proxy, and area strata within each climate group."""
    required = {
        "gauge_id",
        "aridity",
        "frac_snow",
        "slope_mean",
        "clay_frac",
        "high_prec_freq",
        "soil_depth_pelletier",
        "soil_porosity",
        "frac_forest",
        "area_gages2",
    }
    missing = required - set(attributes.columns)
    if missing:
        raise ValueError(f"static attribute table is missing columns: {sorted(missing)}")
    table = attributes.copy()
    table["gauge_id"] = table["gauge_id"].astype(str).str.zfill(8)
    if table["gauge_id"].duplicated().any():
        raise ValueError("static attribute table contains duplicate basin identifiers")
    numeric = sorted(required - {"gauge_id"})
    if not np.all(np.isfinite(table[numeric].to_numpy(dtype=np.float64))):
        raise ValueError("static selection attributes must be finite")
    table["climate_stratum"] = np.select(
        [
            table["frac_snow"] >= 0.20,
            table["aridity"] < 1.0,
            table["aridity"] < 1.5,
        ],
        ["snow", "humid", "semihumid"],
        default="arid",
    )
    table["response_score"] = np.nan
    table["response_stratum"] = ""
    table["area_stratum"] = ""
    positive_fields = ("slope_mean", "clay_frac", "high_prec_freq")
    inverse_fields = ("soil_depth_pelletier", "soil_porosity", "frac_forest")
    for climate in CLIMATE_ORDER:
        indices = table.index[table["climate_stratum"] == climate]
        if len(indices) < 4:
            raise ValueError(f"climate stratum {climate} has fewer than four candidates")
        group = table.loc[indices]
        ranks = [group[field].rank(method="average", pct=True) for field in positive_fields]
        ranks.extend(1.0 - group[field].rank(method="average", pct=True) for field in inverse_fields)
        score = pd.concat(ranks, axis=1).mean(axis=1)
        response_median = float(score.median())
        area_median = float(group["area_gages2"].median())
        table.loc[indices, "response_score"] = score
        table.loc[indices, "response_stratum"] = np.where(
            score <= response_median, "storage_infiltration", "fast_response"
        )
        table.loc[indices, "area_stratum"] = np.where(
            group["area_gages2"] <= area_median, "small", "large"
        )
    return table


def _read_semicolon_table(path: Path) -> pd.DataFrame:
    table = pd.read_csv(path, sep=";", dtype={"gauge_id": str, "huc_02": str})
    table["gauge_id"] = table["gauge_id"].astype(str).str.zfill(8)
    if "huc_02" in table:
        table["huc_02"] = table["huc_02"].astype(str).str.zfill(2)
    return table


def _forcing_area_map(data_root: Path) -> dict[str, float]:
    paths = sorted((data_root / "basin_mean_forcing" / "maurer").rglob("*_lump_maurer_forcing_leap.txt"))
    result = {}
    for path in paths:
        basin_id = path.name[:8]
        with path.open("r", encoding="utf-8") as handle:
            handle.readline()
            handle.readline()
            line = handle.readline().strip()
        try:
            area = float(line) / 1_000_000.0
        except ValueError as error:
            raise ValueError(f"forcing area line is invalid: {path}") from error
        if basin_id in result:
            raise ValueError(f"duplicate Maurer forcing file for basin {basin_id}")
        result[basin_id] = area
    return result


def build_eligible_attribute_table(repo_root: Path) -> pd.DataFrame:
    """Build the 480-basin static pool without reading evaluation performance."""
    root = Path(repo_root).resolve()
    data_root = root / "data" / "camels_us"
    attribute_root = data_root / "camels_attributes_v2.0"
    attributes = None
    for filename in STATIC_ATTRIBUTE_FILES:
        current = _read_semicolon_table(attribute_root / filename)
        attributes = current if attributes is None else attributes.merge(current, on="gauge_id", how="inner")

    fixed_list_path = root / "src" / "xaj_global_pilot" / "configs" / "conceptual_benchmark_camels_us_531_repro.txt"
    fixed_ids = _normalized_ids(fixed_list_path.read_text(encoding="utf-8").splitlines())
    historical_path = root / "src" / "xaj_global_pilot" / "configs" / "conceptual_benchmark_15_basins.csv"
    historical = pd.read_csv(historical_path, dtype={"basin_id": str})
    excluded = _normalized_ids(historical["basin_id"]) | {"04213075"}

    parameter_path = (
        root
        / "src"
        / "hbv_multilead_joint_uncertainty"
        / "configs"
        / "trained_parameter_projection_531_v01.csv"
    )
    if sha256_file(parameter_path) != EXPECTED_PARAMETER_TABLE_SHA256:
        raise ValueError("frozen trained parameter table checksum does not match")
    if csv_projection_sha256(parameter_path) != EXPECTED_PARAMETER_CONTENT_SHA256:
        raise ValueError("trained parameter projection checksum does not match the frozen source")
    required_training = [*(f"p_{name}" for name in PARAMETER_NAMES), *(f"state_{name}" for name in HYDRO_STATE_NAMES)]
    trained = pd.read_csv(
        parameter_path,
        dtype={"basin_id": str},
        usecols=list(TRAINING_PROJECTION_COLUMNS),
    )
    trained["basin_id"] = trained["basin_id"].str.zfill(8)
    if set(trained["run_status"]) != {"success"} or len(trained) != 531:
        raise ValueError("trained parameter table must contain 531 successful rows")
    if not np.all(np.isfinite(trained[required_training].to_numpy(dtype=np.float64))):
        raise ValueError("trained parameters or states contain non-finite values")
    for name in PARAMETER_NAMES:
        lower, upper = V1_PARAMETER_BOUNDS[name]
        values = trained[f"p_{name}"].to_numpy(dtype=np.float64)
        if np.any(values < lower) or np.any(values > upper):
            raise ValueError(f"trained parameter {name} is outside the frozen bounds")

    forcing_areas = _forcing_area_map(data_root)
    table = attributes.loc[attributes["gauge_id"].isin(fixed_ids - excluded)].copy()
    table = table.merge(trained[["basin_id", "run_status"]], left_on="gauge_id", right_on="basin_id", how="inner")
    table["forcing_area_km2"] = table["gauge_id"].map(forcing_areas)
    table["area_relative_difference"] = (
        np.abs(table["area_gages2"] - table["forcing_area_km2"]) / table["area_gages2"]
    )
    table = table.loc[table["area_relative_difference"] <= 0.05].copy()
    table = assign_static_strata(table)
    if len(table) != 480:
        raise ValueError(f"static eligibility rule produced {len(table)} basins; expected 480")
    return table.reset_index(drop=True)


def _selection_digest(climate: str, basin_id: str, salt: str) -> str:
    payload = f"{salt}|{CLIMATE_HASH_LABELS[climate]}|{str(basin_id).zfill(8)}"
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def freeze_formal_selection(
    repo_root: Path,
    salt: str = SELECTION_SALT,
    additional_development_ids: Sequence[str] = (),
) -> pd.DataFrame:
    """Select one basin per frozen static cell using a salted, performance-blind hash."""
    if not salt or not isinstance(salt, str):
        raise ValueError("salt must be a nonempty string")
    table = build_eligible_attribute_table(repo_root)
    selected_rows = []
    for climate in CLIMATE_ORDER:
        used_regions: set[str] = set()
        for response, area in CELL_ORDER:
            cell = table.loc[
                (table["climate_stratum"] == climate)
                & (table["response_stratum"] == response)
                & (table["area_stratum"] == area)
            ].copy()
            if cell.empty:
                raise ValueError(f"static selection cell is empty: {climate}, {response}, {area}")
            cell["selection_sha256"] = [
                _selection_digest(climate, basin_id, salt) for basin_id in cell["gauge_id"]
            ]
            cell = cell.sort_values(["selection_sha256", "gauge_id"], kind="stable")
            unused = cell.loc[~cell["huc_02"].astype(str).str.zfill(2).isin(used_regions)]
            chosen = (unused if not unused.empty else cell).iloc[0].copy()
            chosen["selection_salt"] = salt
            selected_rows.append(chosen)
            used_regions.add(str(chosen["huc_02"]).zfill(2))
    selected = pd.DataFrame(selected_rows).reset_index(drop=True)
    overlap = set(selected["gauge_id"]) & _normalized_ids(additional_development_ids)
    if overlap:
        raise ValueError(f"formal and development basin overlap: {sorted(overlap)}")
    return selected


def audit_temperature_pair(maurer_tmean, daymet_tmean, thresholds: dict | None = None) -> dict:
    """Apply frozen physical and cross-product daily-temperature checks."""
    maurer = np.asarray(maurer_tmean, dtype=np.float64)
    daymet = np.asarray(daymet_tmean, dtype=np.float64)
    if maurer.ndim != 1 or maurer.shape != daymet.shape or len(maurer) == 0:
        raise ValueError("temperature products must be nonempty one-dimensional arrays with equal shape")
    if not np.all(np.isfinite(maurer)) or not np.all(np.isfinite(daymet)):
        raise ValueError("temperature products must be finite")
    absolute_difference = np.abs(maurer - daymet)
    limits = {
        "minimum_maurer_temperature_c": -55.0,
        "maximum_maurer_temperature_c": 50.0,
        "minimum_mean_maurer_temperature_c": -20.0,
        "maximum_mean_maurer_temperature_c": 30.0,
        "maximum_absolute_mean_maurer_daymet_bias_c": 5.0,
        "maximum_median_absolute_maurer_daymet_difference_c": 5.0,
        "maximum_p95_absolute_maurer_daymet_difference_c": 12.0,
        "maximum_fraction_absolute_difference_above_15_c": 0.01,
    }
    if thresholds is not None:
        unknown = set(thresholds) - set(limits) - {"maximum_area_relative_difference"}
        if unknown:
            raise ValueError(f"unknown temperature quality thresholds: {sorted(unknown)}")
        limits.update({key: float(value) for key, value in thresholds.items() if key in limits})
    metrics = {
        "minimum_maurer_temperature_c": float(np.min(maurer)),
        "maximum_maurer_temperature_c": float(np.max(maurer)),
        "mean_maurer_temperature_c": float(np.mean(maurer)),
        "mean_product_bias_c": float(np.mean(maurer - daymet)),
        "median_absolute_product_difference_c": float(np.median(absolute_difference)),
        "p95_absolute_product_difference_c": float(np.quantile(absolute_difference, 0.95)),
        "fraction_absolute_product_difference_above_15_c": float(np.mean(absolute_difference > 15.0)),
    }
    checks = {
        "minimum_maurer_temperature": metrics["minimum_maurer_temperature_c"]
        >= limits["minimum_maurer_temperature_c"],
        "maximum_maurer_temperature": metrics["maximum_maurer_temperature_c"]
        <= limits["maximum_maurer_temperature_c"],
        "mean_maurer_temperature": limits["minimum_mean_maurer_temperature_c"]
        <= metrics["mean_maurer_temperature_c"]
        <= limits["maximum_mean_maurer_temperature_c"],
        "mean_product_bias": abs(metrics["mean_product_bias_c"])
        <= limits["maximum_absolute_mean_maurer_daymet_bias_c"],
        "median_product_difference": metrics["median_absolute_product_difference_c"]
        <= limits["maximum_median_absolute_maurer_daymet_difference_c"],
        "p95_product_difference": metrics["p95_absolute_product_difference_c"]
        <= limits["maximum_p95_absolute_maurer_daymet_difference_c"],
        "extreme_product_difference_fraction": metrics["fraction_absolute_product_difference_above_15_c"]
        <= limits["maximum_fraction_absolute_difference_above_15_c"],
    }
    failed = [name for name, passed in checks.items() if not passed]
    return {**metrics, "passed": not failed, "failed_checks": failed}

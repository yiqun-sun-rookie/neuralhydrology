"""Exact raw-input provenance, availability, and quality checks."""

from __future__ import annotations

from pathlib import Path
import hashlib
import json

import numpy as np
import pandas as pd

from hbv_joint_uncertainty.candidates import sha256_file
from .basins import audit_temperature_pair
from .contracts import INPUT_CONTRACT


def _one_match(root: Path, pattern: str) -> Path:
    matches = list(root.rglob(pattern))
    if len(matches) != 1:
        raise ValueError(f"expected one file matching {pattern}, found {len(matches)}")
    return matches[0].resolve()


def _raw_forcing(path: Path) -> pd.DataFrame:
    table = pd.read_csv(path, skiprows=3, sep=r"\s+")
    if "Year" not in table.columns:
        table = pd.read_csv(path, skiprows=4, sep=r"\s+", header=None)
        with path.open("r", encoding="utf-8") as handle:
            for _ in range(3):
                handle.readline()
            fields = handle.readline().strip().split()
        table.columns = ["Year", "Mnth", "Day", "Hr", *fields]
    table["date"] = pd.to_datetime(
        table[["Year", "Mnth", "Day"]].rename(columns={"Year": "year", "Mnth": "month", "Day": "day"})
    )
    return table.set_index("date")


def _field(table: pd.DataFrame, prefix: str) -> str:
    matches = [column for column in table.columns if str(column).lower().startswith(prefix.lower())]
    if len(matches) != 1:
        raise ValueError(f"expected one raw field beginning with {prefix}, found {matches}")
    return str(matches[0])


def _period_length(start: str, end: str) -> int:
    return len(pd.date_range(start, end, freq="D"))


def _priestley_taylor_pet_mm(
    radiation_w_m2: np.ndarray,
    day_length_seconds: np.ndarray,
    temperature_c: np.ndarray,
    vapor_pressure_pa: np.ndarray | None,
) -> np.ndarray:
    saturation_pressure = 0.6108 * np.exp(17.27 * temperature_c / (temperature_c + 237.3))
    slope = 4098.0 * saturation_pressure / (temperature_c + 237.3) ** 2
    radiation_mj = radiation_w_m2 * day_length_seconds / 1.0e6
    net_shortwave = 0.77 * radiation_mj
    kelvin = temperature_c + 273.15
    if vapor_pressure_pa is None:
        humidity_term = 0.20
    else:
        humidity_term = 0.34 - 0.14 * np.sqrt(np.clip(vapor_pressure_pa / 1000.0, 0.0, None))
    net_longwave = 4.903e-9 * kelvin**4 * humidity_term
    net_longwave = np.minimum(net_longwave, 0.85 * net_shortwave)
    net_radiation = np.clip(net_shortwave - net_longwave, 0.0, None)
    return np.clip(1.26 * (slope / (slope + 0.067)) * net_radiation / 2.45, 0.0, None)


def _oudin_pet_mm(
    radiation_w_m2: np.ndarray,
    day_length_seconds: np.ndarray,
    temperature_c: np.ndarray,
) -> np.ndarray:
    radiation_mj = radiation_w_m2 * day_length_seconds / 1.0e6
    return np.where(temperature_c > -5.0, radiation_mj * (temperature_c + 5.0) / 245.0, 0.0)


def _data_root(repo_root: Path, config: dict) -> Path:
    data_root = Path(config["data_root"])
    return data_root.resolve() if data_root.is_absolute() else (repo_root / data_root).resolve()


def _basin_area(data_root: Path, basin_id: str) -> tuple[float, Path]:
    path = (data_root / "camels_attributes_v2.0" / "camels_topo.txt").resolve()
    table = pd.read_csv(path, sep=";", dtype={"gauge_id": str})
    table["gauge_id"] = table["gauge_id"].str.zfill(8)
    rows = table.loc[table["gauge_id"] == basin_id, "area_gages2"]
    if len(rows) != 1 or not np.isfinite(float(rows.iloc[0])) or float(rows.iloc[0]) <= 0.0:
        raise ValueError(f"basin {basin_id} has no unique positive drainage area")
    return float(rows.iloc[0]), path


def load_forcing_period(
    repo_root: Path,
    basin_id: str,
    config: dict,
    start: str,
    end: str,
    forcing: str | None = None,
) -> tuple[pd.DataFrame, Path]:
    """Load meteorology without opening the streamflow file."""
    root = Path(repo_root).resolve()
    identifier = str(basin_id).zfill(8)
    data_root = _data_root(root, config)
    forcing_name = forcing or config["parameter_source"]["forcing"]
    locations = {
        "maurer": ("maurer", "maurer"),
        "daymet": ("daymet", "cida"),
    }
    if forcing_name not in locations:
        raise ValueError(f"unsupported forcing for isolated audit: {forcing_name}")
    subdirectory, marker = locations[forcing_name]
    path = _one_match(
        data_root / "basin_mean_forcing" / subdirectory,
        f"{identifier}_lump_{marker}_forcing_leap.txt",
    )
    raw = _raw_forcing(path).loc[start:end]
    expected = pd.date_range(start, end, freq="D")
    if not raw.index.equals(expected):
        raise ValueError(f"basin {identifier} {forcing_name} forcing is not continuous from {start} through {end}")
    precipitation = raw[_field(raw, "prcp")].to_numpy(dtype=np.float64)
    tmax = raw[_field(raw, "tmax")].to_numpy(dtype=np.float64)
    tmin = raw[_field(raw, "tmin")].to_numpy(dtype=np.float64)
    radiation = raw[_field(raw, "srad")].to_numpy(dtype=np.float64)
    day_length = raw[_field(raw, "dayl")].to_numpy(dtype=np.float64)
    temperature = (tmax + tmin) / 2.0
    method = config["parameter_source"]["pet_method"]
    if method == "priestley_taylor":
        try:
            vapor_pressure = raw[_field(raw, "vp")].to_numpy(dtype=np.float64)
        except ValueError:
            vapor_pressure = None
        potential_evapotranspiration = _priestley_taylor_pet_mm(
            radiation,
            day_length,
            temperature,
            vapor_pressure_pa=vapor_pressure,
        )
    elif method == "oudin":
        potential_evapotranspiration = _oudin_pet_mm(radiation, day_length, temperature)
    else:
        raise ValueError(f"unsupported potential evapotranspiration method: {method}")
    frame = pd.DataFrame(
        {
            "prcp": precipitation,
            "ep": np.maximum(potential_evapotranspiration, 0.0),
            "tmean": temperature,
        },
        index=expected,
    )
    return frame, path


def load_discharge_period(
    repo_root: Path,
    basin_id: str,
    config: dict,
    start: str,
    end: str,
) -> tuple[pd.Series, pd.Series, dict]:
    """Parse discharge values only for the requested closed date interval."""
    root = Path(repo_root).resolve()
    identifier = str(basin_id).zfill(8)
    data_root = _data_root(root, config)
    streamflow_path = _one_match(data_root / "usgs_streamflow", f"{identifier}_streamflow_qc.txt")
    area_km2, topo_path = _basin_area(data_root, identifier)
    first = pd.Timestamp(start)
    last = pd.Timestamp(end)
    values: dict[pd.Timestamp, float] = {}
    flags: dict[pd.Timestamp, str] = {}
    selected_lines = hashlib.sha256()
    with streamflow_path.open("rb") as handle:
        for raw_line in handle:
            fields = raw_line.split()
            if len(fields) < 6:
                continue
            year = int(fields[1])
            if year < first.year:
                continue
            if year > last.year:
                break
            date = pd.Timestamp(year=year, month=int(fields[2]), day=int(fields[3]))
            if date < first or date > last:
                continue
            selected_lines.update(raw_line)
            discharge_cfs = float(fields[4])
            values[date] = np.nan if discharge_cfs < 0.0 else discharge_cfs * 2.4466 / area_km2
            flags[date] = fields[5].decode("utf-8")
    expected = pd.date_range(start, end, freq="D")
    observations = pd.Series(values, index=expected, dtype=np.float64, name="streamflow_mm_day")
    quality_flags = pd.Series(flags, index=expected, dtype="object", name="quality_flag")
    provenance = {
        "source_path": streamflow_path.relative_to(root).as_posix(),
        "selected_date_start": start,
        "selected_date_end": end,
        "selected_source_lines_sha256": selected_lines.hexdigest(),
        "selected_line_count": int(len(values)),
        "area_source_path": topo_path.relative_to(root).as_posix(),
        "area_source_sha256": sha256_file(topo_path),
        "area_gages2_km2": area_km2,
        "conversion": "discharge_cfs * 2.4466 / area_gages2_km2",
    }
    return observations, quality_flags, provenance


def load_frozen_calibration_discharge(
    repo_root: Path,
    basin_id: str,
    config: dict,
) -> tuple[pd.Series, pd.Series, dict]:
    """Load the pre-extracted calibration-only table without opening raw evaluation streamflow."""
    root = Path(repo_root).resolve()
    identifier = str(basin_id).zfill(8)
    source = config["calibration_discharge_source"]
    table_path = (root / source["table_path"]).resolve()
    metadata_path = (root / source["metadata_path"]).resolve()
    if sha256_file(table_path) != source["table_sha256"]:
        raise ValueError("frozen calibration discharge table checksum mismatch")
    if sha256_file(metadata_path) != source["metadata_sha256"]:
        raise ValueError("frozen calibration discharge metadata checksum mismatch")
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    if (
        metadata.get("artifact_type") != "calibration_only_discharge_source"
        or metadata.get("evaluation_discharge_values_parsed") is not False
        or metadata.get("date_start") != source["date_start"]
        or metadata.get("date_end") != source["date_end"]
    ):
        raise ValueError("frozen calibration discharge metadata is invalid")
    expected_columns = ["basin_id", "date", "streamflow_mm_day", "quality_flag"]
    table = pd.read_csv(
        table_path,
        dtype={"basin_id": str, "quality_flag": str},
        usecols=expected_columns,
        float_precision="round_trip",
    )
    if set(table.columns) != set(expected_columns):
        raise ValueError("frozen calibration discharge columns are invalid")
    table["basin_id"] = table["basin_id"].str.zfill(8)
    rows = table.loc[table["basin_id"] == identifier].copy()
    rows["date"] = pd.to_datetime(rows["date"])
    rows = rows.sort_values("date", kind="stable").set_index("date")
    expected = pd.date_range(source["date_start"], source["date_end"], freq="D")
    if not rows.index.equals(expected) or len(rows) != len(expected):
        raise ValueError(f"basin {identifier} frozen calibration discharge is incomplete")
    observations = rows["streamflow_mm_day"].astype(np.float64)
    flags = rows["quality_flag"].astype(str)
    if not np.all(np.isfinite(observations.to_numpy())):
        raise ValueError(f"basin {identifier} frozen calibration discharge is non-finite")
    raw_source = metadata.get("sources", {}).get(identifier)
    if not isinstance(raw_source, dict):
        raise ValueError(f"basin {identifier} frozen calibration source provenance is missing")
    provenance = {
        "source_path": table_path.relative_to(root).as_posix(),
        "source_sha256": source["table_sha256"],
        "metadata_path": metadata_path.relative_to(root).as_posix(),
        "metadata_sha256": source["metadata_sha256"],
        "selected_date_start": source["date_start"],
        "selected_date_end": source["date_end"],
        "selected_line_count": int(len(rows)),
        "raw_source": raw_source,
    }
    return observations, flags, provenance


def load_model_period(repo_root: Path, basin_id: str, config: dict, start: str, end: str):
    forcing, _ = load_forcing_period(repo_root, basin_id, config, start, end)
    if start == config["calibration_selection_start"] and end == config["calibration_selection_end"]:
        observations, _, _ = load_frozen_calibration_discharge(repo_root, basin_id, config)
    else:
        observations, _, _ = load_discharge_period(repo_root, basin_id, config, start, end)
    return forcing, observations


def audit_basin_inputs(repo_root: Path, basin_id: str, config: dict) -> dict:
    root = Path(repo_root).resolve()
    identifier = str(basin_id).zfill(8)
    data_root = _data_root(root, config)
    maurer_path = _one_match(
        data_root / "basin_mean_forcing" / "maurer", f"{identifier}_lump_maurer_forcing_leap.txt"
    )
    daymet_path = _one_match(
        data_root / "basin_mean_forcing" / "daymet", f"{identifier}_lump_cida_forcing_leap.txt"
    )
    union_start = min(config["evaluation_warmup_start"], config["calibration_warmup_start"])
    union_end = max(config["evaluation_end"], config["calibration_selection_end"])
    maurer, _ = load_forcing_period(root, identifier, config, union_start, union_end, forcing="maurer")
    daymet, _ = load_forcing_period(root, identifier, config, union_start, union_end, forcing="daymet")
    selection_observations, selection_flags, discharge_provenance = load_frozen_calibration_discharge(
        root,
        identifier,
        config,
    )
    raw_discharge_provenance = discharge_provenance["raw_source"]
    area_km2 = float(raw_discharge_provenance["area_gages2_km2"])
    topo_path = root / raw_discharge_provenance["area_source_path"]
    expected_union = pd.date_range(union_start, union_end, freq="D")
    raw_maurer = _raw_forcing(maurer_path).loc[union_start:union_end]
    tmax = raw_maurer[_field(raw_maurer, "tmax")].to_numpy(dtype=np.float64)
    tmin = raw_maurer[_field(raw_maurer, "tmin")].to_numpy(dtype=np.float64)
    temperature_quality = audit_temperature_pair(
        maurer["tmean"].to_numpy(dtype=np.float64),
        daymet["tmean"].to_numpy(dtype=np.float64),
        thresholds=config.get("input_quality"),
    )

    with maurer_path.open("r", encoding="utf-8") as handle:
        handle.readline()
        handle.readline()
        forcing_area_km2 = float(handle.readline().strip()) / 1_000_000.0
    area_relative_difference = abs(forcing_area_km2 - area_km2) / area_km2
    contiguous = maurer.index.equals(expected_union) and daymet.index.equals(expected_union)
    forcing_finite = np.all(np.isfinite(maurer[["prcp", "ep", "tmean"]].to_numpy(dtype=np.float64)))
    forcing_nonnegative = bool(np.all(maurer[["prcp", "ep"]].to_numpy(dtype=np.float64) >= 0.0))
    selection_complete = (
        len(selection_observations)
        == _period_length(config["calibration_selection_start"], config["calibration_selection_end"])
        and np.all(np.isfinite(selection_observations.to_numpy(dtype=np.float64)))
    )
    checks = {
        "continuous_calendar": contiguous,
        "finite_forcing": bool(forcing_finite),
        "nonnegative_precipitation_and_pet": forcing_nonnegative,
        "complete_calibration_selection_discharge": bool(selection_complete),
        "area_consistency": area_relative_difference
        <= float(config.get("input_quality", {}).get("maximum_area_relative_difference", 0.05)),
        "temperature_quality": bool(temperature_quality["passed"]),
    }
    failed = [name for name, passed in checks.items() if not passed]
    maurer_relative = maurer_path.relative_to(root).as_posix()
    topo_relative = topo_path.relative_to(root).as_posix()
    input_contract = {row["variable_id"]: row for row in INPUT_CONTRACT}
    variables = []
    modeled_columns = {
        "precipitation": "prcp",
        "mean_temperature": "tmean",
        "potential_evapotranspiration": "ep",
    }
    for variable_id in ("precipitation", "mean_temperature", "potential_evapotranspiration"):
        variables.append(
            {
                **input_contract[variable_id],
                "source_path": maurer_relative,
                "source_sha256": sha256_file(maurer_path),
                "modeled_date_start": union_start,
                "modeled_date_end": union_end,
                "missing_days": int(maurer[modeled_columns[variable_id]].isna().sum()),
            }
        )
    variables.append(
        {
            **input_contract["streamflow"],
            "source_path": discharge_provenance["source_path"],
            "source_sha256": discharge_provenance["source_sha256"],
            "source_sha256_scope": "entire frozen calibration-only twenty-two-basin table",
            "raw_source_path": raw_discharge_provenance["source_path"],
            "raw_selected_source_lines_sha256": raw_discharge_provenance[
                "selected_source_lines_sha256"
            ],
            "area_source_path": topo_relative,
            "area_source_sha256": sha256_file(topo_path),
            "modeled_date_start": config["calibration_selection_start"],
            "modeled_date_end": config["calibration_selection_end"],
            "missing_calibration_selection_days": int(selection_observations.isna().sum()),
        }
    )
    return {
        "basin_id": identifier,
        "passed": not failed,
        "failed_checks": failed,
        "checks": checks,
        "variables": variables,
        "daymet_audit_path": daymet_path.relative_to(root).as_posix(),
        "daymet_audit_sha256": sha256_file(daymet_path),
        "temperature_quality": temperature_quality,
        "maurer_tmax_equals_tmin_fraction": float(np.mean(tmax == tmin)),
        "area_gages2_km2": float(area_km2),
        "forcing_area_km2": float(forcing_area_km2),
        "area_relative_difference": float(area_relative_difference),
        "evaluation_discharge_values_parsed": False,
        "calibration_discharge_qc_flag_counts": {
            str(key): int(value) for key, value in selection_flags.value_counts().items()
        },
        "calibration_discharge_records": [
            {
                "date": date.strftime("%Y-%m-%d"),
                "streamflow_mm_day": float(value),
                "quality_flag": str(selection_flags.loc[date]),
            }
            for date, value in selection_observations.items()
        ],
        "periods": {
            "calibration_warmup_days": _period_length(
                config["calibration_warmup_start"], config["calibration_warmup_end"]
            ),
            "calibration_selection_days": _period_length(
                config["calibration_selection_start"], config["calibration_selection_end"]
            ),
            "evaluation_warmup_days": _period_length(
                config["evaluation_warmup_start"], config["evaluation_warmup_end"]
            ),
            "evaluation_days": _period_length(config["evaluation_start"], config["evaluation_end"]),
            "common_forecast_origins": _period_length(config["evaluation_start"], config["evaluation_end"])
            - max(config["lead_days"]),
        },
    }


def audit_evaluation_discharge(
    repo_root: Path,
    basin_id: str,
    contract_directory: Path,
) -> dict:
    """Audit evaluation discharge only after the calibration contract has been verified."""
    from .experiment import verify_contract_package

    contract_path = Path(contract_directory).resolve()
    verification = verify_contract_package(contract_path)
    config = json.loads((contract_path / "config_snapshot.json").read_text(encoding="utf-8"))
    identifier = str(basin_id).zfill(8)
    observations, flags, provenance = load_discharge_period(
        repo_root,
        identifier,
        config,
        config["evaluation_start"],
        config["evaluation_end"],
    )
    expected_days = _period_length(config["evaluation_start"], config["evaluation_end"])
    complete = len(observations) == expected_days and np.all(np.isfinite(observations.to_numpy()))
    return {
        "basin_id": identifier,
        "performed_after_verified_contract": True,
        "verified_contract_id": verification["contract_id"],
        "verified_contract_checksums_sha256": sha256_file(contract_path / "checksums.json"),
        "passed": bool(complete),
        "failed_checks": [] if complete else ["complete_evaluation_discharge"],
        "checks": {"complete_evaluation_discharge": bool(complete)},
        "source": provenance,
        "missing_evaluation_days": int(observations.isna().sum()),
        "evaluation_qc_flag_counts": {str(key): int(value) for key, value in flags.value_counts().items()},
    }

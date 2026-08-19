"""Registered-input gate for exploratory CAMELS-US parameter-switch runs.

This module validates identity and inputs only. It never creates an output
directory or starts a worker process. A hash-registered exploratory design is
still explicitly not a validation-frozen experiment.
"""

from __future__ import annotations

import hashlib
import json
from collections.abc import Mapping
from dataclasses import dataclass
from pathlib import Path

import pandas as pd


REGISTERED_EXPLORATORY_STATUS = (
    "registered_exploratory_design_not_validation_frozen"
)
EXPECTED_WINDOW_START = "1989-10-01"
EXPECTED_WINDOW_END = "1993-03-13"
EXPECTED_WINDOW_DAYS = 1260
EXPECTED_TRUTH_CONTRACT = {
    "window_start": EXPECTED_WINDOW_START,
    "window_end": EXPECTED_WINDOW_END,
    "window_days": EXPECTED_WINDOW_DAYS,
    "stage_days": 180,
    "rotation": [0, 1, 2, 0, 2, 1, 0],
    "slz_lognormal_sigma": 0.02,
    "seed_entropy": 20260807,
}
EXPECTED_CANDIDATE_CONTRACT = {
    "parameter": "parFC",
    "factors": [1.0, 0.5, 2.0],
    "bounds_preset": "v5",
}
EXPECTED_FILTER_CONTRACT = {
    "q_scale": 3e-8,
    "q_structure": "lower_groundwater_state_only",
    "q_mode": "fixed",
    "q_state_multiplier": 1.0,
    "observation_variance_multiplier": 1.0,
    "transition_diagonal": 0.98,
    "initial_covariance_fraction": 0.001,
}
EXPECTED_EVENT_CONTRACT = {
    "response_window_days": 30,
    "consecutive_days": 5,
    "probability_threshold_exclusive": 0.5,
    "margin_inclusive": 0.1,
}
EXPECTED_ARMS = (
    {
        "arm_id": "A",
        "interaction_mode": "parameter_grouped",
        "parameter_state_mapping": "legacy_projection",
    },
    {
        "arm_id": "B",
        "interaction_mode": "full",
        "parameter_state_mapping": "legacy_projection",
    },
    {
        "arm_id": "C",
        "interaction_mode": "full",
        "parameter_state_mapping": "conservative_parfc",
    },
)

_MANIFEST_COLUMNS = {"category", "basin_id", "relative_path", "bytes", "sha256"}
_BASIN_INPUT_CATEGORIES = {"maurer_forcing", "usgs_streamflow"}
_SHARED_INPUT_CATEGORIES = {
    "camels_topography",
    "forcing_loader_source",
    "parameter_table",
    "g1_precheck_table",
}
_COVERAGE_COLUMNS = {
    "basin_id",
    "n_days",
    "first_date",
    "last_date",
    "finite_prcp",
    "finite_ep",
    "finite_tmean",
    "all_required_forcing_finite",
}


@dataclass(frozen=True)
class VerifiedParameterRun:
    """Resolved identity returned after every registered check succeeds."""

    experiment_id: str
    configuration_status: str
    config_path: Path
    config_sha256: str
    basin_ids: tuple[str, ...]
    data_root: Path
    output_root: Path
    arms: tuple[dict, ...]
    registered_hashes: dict[str, str | int]
    configuration: dict
    repo_root: Path


def sha256_file(path: str | Path) -> str:
    """Return the lowercase SHA-256 digest of one file."""
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _registered_relative_path(value: object, label: str) -> Path:
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"registered {label} must be a nonempty repository-relative path")
    relative = Path(value)
    if relative.is_absolute() or relative.drive or ".." in relative.parts:
        raise ValueError(f"registered {label} must be a repository-relative path without parent traversal")
    return relative


def _registered_file(repo_root: Path, value: object, label: str) -> tuple[Path, Path]:
    relative = _registered_relative_path(value, label)
    path = repo_root / relative
    if not path.is_file():
        raise FileNotFoundError(f"registered {label} is missing: {path}")
    return path, relative


def _registered_directory(repo_root: Path, value: object, label: str) -> Path:
    relative = _registered_relative_path(value, label)
    path = repo_root / relative
    if not path.is_dir():
        raise FileNotFoundError(f"registered {label} directory is missing: {path}")
    return path.resolve()


def _verify_hash(path: Path, expected: object, label: str) -> str:
    observed = sha256_file(path)
    if observed != str(expected):
        raise ValueError(
            f"{label} SHA-256 changed: expected {expected}, observed {observed}"
        )
    return observed


def _normalize_basin_id(value: object, label: str) -> str:
    text = str(value).strip()
    normalized = text.zfill(8)
    if not normalized.isdigit() or len(normalized) != 8:
        raise ValueError(f"{label} contains an invalid basin identifier: {value}")
    return normalized


def _true_flag(value: object) -> bool:
    return value is True or str(value).strip().lower() == "true"


def _read_basin_list(path: Path, expected_hash: object, expected_count: object) -> tuple[tuple[str, ...], str]:
    observed_hash = _verify_hash(path, expected_hash, "basin list")
    frame = pd.read_csv(path, dtype={"basin_id": str}, keep_default_na=False)
    if "basin_id" not in frame.columns:
        raise ValueError("basin list missing required column: basin_id")
    basin_ids = tuple(
        _normalize_basin_id(value, "basin list") for value in frame["basin_id"]
    )
    if not basin_ids:
        raise ValueError("basin list must not be empty")
    if len(set(basin_ids)) != len(basin_ids):
        raise ValueError("basin list contains duplicates")
    try:
        registered_count = int(expected_count)
    except (TypeError, ValueError) as error:
        raise ValueError("registered basin count must be an integer") from error
    if registered_count != len(basin_ids):
        raise ValueError(
            f"registered basin count changed: expected {registered_count}, observed {len(basin_ids)}"
        )
    return basin_ids, observed_hash


def _verify_coverage(path: Path, expected_hash: object, basin_ids: tuple[str, ...]) -> str:
    observed_hash = _verify_hash(path, expected_hash, "forcing coverage table")
    frame = pd.read_csv(path, dtype={"basin_id": str}, keep_default_na=False)
    missing = sorted(_COVERAGE_COLUMNS.difference(frame.columns))
    if missing:
        raise ValueError(
            "forcing coverage table missing required columns: " + ", ".join(missing)
        )
    normalized = [
        _normalize_basin_id(value, "forcing coverage table")
        for value in frame["basin_id"]
    ]
    if len(set(normalized)) != len(normalized):
        raise ValueError("forcing coverage table contains duplicate basins")
    if tuple(normalized) != basin_ids:
        raise ValueError("forcing coverage basin order or membership differs from basin list")
    days = pd.to_numeric(frame["n_days"], errors="coerce")
    finite_columns = (
        "finite_prcp",
        "finite_ep",
        "finite_tmean",
        "all_required_forcing_finite",
    )
    valid = (
        (days == EXPECTED_WINDOW_DAYS).all()
        and (frame["first_date"].astype(str) == EXPECTED_WINDOW_START).all()
        and (frame["last_date"].astype(str) == EXPECTED_WINDOW_END).all()
        and all(frame[column].map(_true_flag).all() for column in finite_columns)
    )
    if not valid:
        raise ValueError(
            "forcing coverage contract failed: require exactly 1260 finite days "
            "from 1989-10-01 through 1993-03-13"
        )
    return observed_hash


def _verify_raw_manifest(
    repo_root: Path,
    path: Path,
    expected_hash: object,
    basin_ids: tuple[str, ...],
    parameter_relative: Path,
    precheck_relative: Path,
) -> tuple[str, int]:
    manifest_hash = _verify_hash(path, expected_hash, "raw-input manifest")
    frame = pd.read_csv(path, dtype={"basin_id": str}, keep_default_na=False)
    missing = sorted(_MANIFEST_COLUMNS.difference(frame.columns))
    if missing:
        raise ValueError(
            "raw-input manifest missing required columns: " + ", ".join(missing)
        )
    if frame["relative_path"].duplicated().any():
        raise ValueError("raw-input manifest contains duplicate paths")

    allowed_categories = _BASIN_INPUT_CATEGORIES | _SHARED_INPUT_CATEGORIES
    categories = set(frame["category"].astype(str))
    if not categories.issubset(allowed_categories):
        unexpected = sorted(categories.difference(allowed_categories))
        raise ValueError(
            "raw-input manifest contains unexpected categories: " + ", ".join(unexpected)
        )

    basin_rows = frame[frame["category"].isin(_BASIN_INPUT_CATEGORIES)].copy()
    basin_rows["normalized_basin_id"] = [
        _normalize_basin_id(value, "raw-input manifest")
        for value in basin_rows["basin_id"]
    ]
    observed_pairs = list(
        zip(basin_rows["normalized_basin_id"], basin_rows["category"])
    )
    expected_pairs = {
        (basin_id, category)
        for basin_id in basin_ids
        for category in _BASIN_INPUT_CATEGORIES
    }
    if len(observed_pairs) != len(expected_pairs) or set(observed_pairs) != expected_pairs:
        raise ValueError(
            "raw-input manifest must contain one Maurer forcing and one United States "
            "Geological Survey streamflow file per selected basin"
        )

    for category in _SHARED_INPUT_CATEGORIES:
        rows = frame[frame["category"] == category]
        if len(rows) != 1 or str(rows.iloc[0]["basin_id"]).strip():
            raise ValueError(
                f"raw-input manifest must contain one basin-independent {category} file"
            )
    expected_rows = 2 * len(basin_ids) + len(_SHARED_INPUT_CATEGORIES)
    if len(frame) != expected_rows:
        raise ValueError(
            f"raw-input manifest row count changed: expected {expected_rows}, observed {len(frame)}"
        )

    registered_category_paths: dict[str, Path] = {}
    for row in frame.itertuples(index=False):
        input_path, relative = _registered_file(
            repo_root,
            row.relative_path,
            "input file",
        )
        observed_hash = sha256_file(input_path)
        if observed_hash != str(row.sha256):
            raise ValueError(
                f"input file SHA-256 changed for {row.relative_path}: "
                f"expected {row.sha256}, observed {observed_hash}"
            )
        try:
            expected_bytes = int(row.bytes)
        except (TypeError, ValueError) as error:
            raise ValueError(
                f"raw-input manifest has invalid byte count for {row.relative_path}"
            ) from error
        observed_bytes = input_path.stat().st_size
        if observed_bytes != expected_bytes:
            raise ValueError(
                f"input file byte count changed for {row.relative_path}: "
                f"expected {expected_bytes}, observed {observed_bytes}"
            )
        registered_category_paths[str(row.category)] = relative

    if registered_category_paths["parameter_table"] != parameter_relative:
        raise ValueError("raw-input manifest parameter table path differs from configuration")
    if registered_category_paths["g1_precheck_table"] != precheck_relative:
        raise ValueError("raw-input manifest precheck table path differs from configuration")
    return manifest_hash, int(len(frame))


def _verify_implementation_files(repo_root: Path, config: Mapping) -> tuple[dict[str, str], int]:
    registered = config.get("implementation")
    if not isinstance(registered, Mapping) or not registered:
        raise ValueError("configuration must register at least one implementation file")
    hashes: dict[str, str] = {}
    relative_paths: set[Path] = set()
    for label, entry in registered.items():
        if not isinstance(label, str) or not label or not isinstance(entry, Mapping):
            raise ValueError("implementation entries must be named mappings")
        path, relative = _registered_file(
            repo_root,
            entry.get("path"),
            f"implementation file {label}",
        )
        if relative in relative_paths:
            raise ValueError("configuration contains duplicate implementation paths")
        relative_paths.add(relative)
        observed = sha256_file(path)
        expected = entry.get("sha256")
        if observed != str(expected):
            raise ValueError(
                f"implementation file SHA-256 changed for {label}: "
                f"expected {expected}, observed {observed}"
            )
        hashes[f"implementation:{label}"] = observed
    return hashes, len(relative_paths)


def verify_parameter_run_config(
    repo_root: str | Path,
    config_path: str | Path,
    expected_config_sha256: str,
) -> VerifiedParameterRun:
    """Verify a registered exploratory parameter run without creating output.

    All registered paths inside the JSON configuration are lexical paths
    relative to ``repo_root``. Relative paths may traverse an existing data
    junction, but absolute paths and explicit parent traversal are rejected.
    """
    root = Path(repo_root).resolve()
    configuration = Path(config_path).resolve()
    if not configuration.is_file():
        raise FileNotFoundError(f"registered configuration is missing: {configuration}")
    try:
        configuration.relative_to(root)
    except ValueError as error:
        raise ValueError("configuration path must be inside the repository root") from error

    config_hash = sha256_file(configuration)
    if config_hash != str(expected_config_sha256):
        raise ValueError(
            "configuration SHA-256 changed: "
            f"expected {expected_config_sha256}, observed {config_hash}"
        )
    with configuration.open("r", encoding="utf-8") as handle:
        config = json.load(handle)
    if not isinstance(config, Mapping):
        raise ValueError("configuration root must be a JSON object")

    experiment_id = config.get("experiment_id")
    if not isinstance(experiment_id, str) or not experiment_id.strip():
        raise ValueError("experiment_id must be a nonempty string")
    status = config.get("configuration_status")
    if status != REGISTERED_EXPLORATORY_STATUS:
        raise ValueError(
            "configuration status must be " + REGISTERED_EXPLORATORY_STATUS
        )

    seeds = config.get("seeds", {})
    if not isinstance(seeds, Mapping) or seeds.get("design") != [0, 1]:
        raise ValueError("design seeds must be exactly [0, 1]")
    if seeds.get("reserved_validation_not_authorized") != [2, 3]:
        raise ValueError("reserved validation seeds must be exactly [2, 3]")

    truth = config.get("truth", {})
    if not isinstance(truth, Mapping) or dict(truth) != EXPECTED_TRUTH_CONTRACT:
        raise ValueError(
            "registered truth contract changed"
        )
    if config.get("candidates") != EXPECTED_CANDIDATE_CONTRACT:
        raise ValueError("registered candidate contract changed")
    if config.get("filter") != EXPECTED_FILTER_CONTRACT:
        raise ValueError("registered filter contract changed")
    if config.get("event_rule") != EXPECTED_EVENT_CONTRACT:
        raise ValueError("registered event contract changed")

    arms_value = config.get("arms")
    if not isinstance(arms_value, list) or tuple(arms_value) != EXPECTED_ARMS:
        raise ValueError("registered arms must be exactly A, B, and C in the approved order")

    inputs = config.get("inputs", {})
    selection = config.get("design_selection", {})
    outputs = config.get("outputs", {})
    if not all(isinstance(section, Mapping) for section in (inputs, selection, outputs)):
        raise ValueError("inputs, design_selection, and outputs must be mappings")
    if inputs.get("forcing") != "maurer" or inputs.get("pet_method") != "oudin":
        raise ValueError("registered forcing contract changed")

    parameter_path, parameter_relative = _registered_file(
        root,
        inputs.get("parameter_table"),
        "parameter table",
    )
    parameter_hash = _verify_hash(
        parameter_path,
        inputs.get("parameter_table_sha256"),
        "parameter table",
    )
    precheck_path, precheck_relative = _registered_file(
        root,
        inputs.get("g1_precheck_table"),
        "first-stage precheck table",
    )
    precheck_hash = _verify_hash(
        precheck_path,
        inputs.get("g1_precheck_table_sha256"),
        "first-stage precheck table",
    )
    basin_path, _ = _registered_file(root, selection.get("basin_list"), "basin list")
    basin_ids, basin_hash = _read_basin_list(
        basin_path,
        selection.get("basin_list_sha256"),
        selection.get("basin_count"),
    )
    coverage_path, _ = _registered_file(
        root,
        inputs.get("forcing_coverage_table"),
        "forcing coverage table",
    )
    coverage_hash = _verify_coverage(
        coverage_path,
        inputs.get("forcing_coverage_table_sha256"),
        basin_ids,
    )
    manifest_path, _ = _registered_file(
        root,
        inputs.get("raw_input_manifest"),
        "raw-input manifest",
    )
    manifest_hash, manifest_rows = _verify_raw_manifest(
        root,
        manifest_path,
        inputs.get("raw_input_manifest_sha256"),
        basin_ids,
        parameter_relative,
        precheck_relative,
    )
    implementation_hashes, implementation_count = _verify_implementation_files(
        root,
        config,
    )

    data_root = _registered_directory(root, inputs.get("data_root"), "data root")
    output_relative = _registered_relative_path(outputs.get("root"), "output root")
    output_root = (root / output_relative).resolve()
    if output_root.exists():
        raise FileExistsError(f"output root already exists: {output_root}")

    registered_hashes: dict[str, str | int] = {
        "config_sha256": config_hash,
        "parameter_table_sha256": parameter_hash,
        "g1_precheck_table_sha256": precheck_hash,
        "basin_list_sha256": basin_hash,
        "forcing_coverage_table_sha256": coverage_hash,
        "raw_input_manifest_sha256": manifest_hash,
        "raw_input_manifest_rows": manifest_rows,
        "implementation_file_count": implementation_count,
    }
    registered_hashes.update(implementation_hashes)
    return VerifiedParameterRun(
        experiment_id=experiment_id,
        configuration_status=status,
        config_path=configuration,
        config_sha256=config_hash,
        basin_ids=basin_ids,
        data_root=data_root,
        output_root=output_root,
        arms=tuple(dict(arm) for arm in arms_value),
        registered_hashes=registered_hashes,
        configuration=json.loads(json.dumps(config)),
        repo_root=root,
    )

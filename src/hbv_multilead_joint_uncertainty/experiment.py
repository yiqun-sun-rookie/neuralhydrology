"""Immutable contract and evaluation artifacts with independent verification."""

from __future__ import annotations

import json
import io
import os
import re
import shutil
import tempfile
from dataclasses import dataclass
from pathlib import Path, PureWindowsPath
from typing import Mapping, Sequence

import numpy as np
import pandas as pd

from hbv_joint_uncertainty.candidates import sha256_file
from hbv_joint_uncertainty.hbv_adapter import PARAMETER_NAMES, STATE_NAMES, V1_PARAMETER_BOUNDS

from .contracts import PARAMETER_CONTRACT
from .methods import (
    LEGACY_PARAMETER_ORDER,
    METHOD_ORDER,
    PARAMETER_ORDER,
    parameter_order_from_identifiers,
)
from .resource_monitor import verify_resource_history_rows
from .runner import MethodRunResult
from .selection import (
    generate_local_parameter_pool,
    generate_multiscale_parameter_pool,
    select_equifinal_parameters,
)


EXPECTED_CANDIDATE_COUNTS = {
    "open_loop": 1,
    "fixed_filter": 1,
    "parameter_only": 3,
    "noise_only": 3,
    "joint": 9,
}

CONTRACT_TABLE_FILES = (
    "basins.csv",
    "parameter_vectors.csv",
    "parameter_dictionary.csv",
    "process_noise_covariances.csv",
    "observation_noise.csv",
    "input_variables.csv",
    "interaction_audit.json",
    "config_snapshot.json",
)

# Legacy contracts do not contain a reconstructable parameter-candidate audit.  They
# are accepted only by an identity anchored outside the artifact being verified;
# every other contract must use the current reconstructable selection schemas.
LEGACY_CONTRACT_CHECKSUM_ALLOWLIST = {
    "smoke_contract_04015330_v03": (
        "df07899b18ffc1283135e3c576f6094cd878221d965b93138bc38ad884ea6692"
    ),
}


def _expected_candidate_ids(basin_contract: Mapping) -> dict[str, tuple[str, ...]]:
    parameter_ids = parameter_order_from_identifiers(
        basin_contract.get("parameter_vectors", {})
    )
    process_rows = basin_contract.get("process_noise", {}).get("candidates", [])
    process_ids = tuple(str(row.get("process_id")) for row in process_rows)
    if len(process_ids) != 3 or len(set(process_ids)) != 3:
        raise ValueError("basin contract process identifiers are invalid")
    selected = str(basin_contract.get("process_noise", {}).get("selected_process_id"))
    if selected not in process_ids:
        raise ValueError("basin contract selected process identifier is invalid")
    return {
        "open_loop": ("trained_center_open_loop",),
        "fixed_filter": (f"trained_center__{selected}",),
        "parameter_only": tuple(f"{parameter_id}__{selected}" for parameter_id in parameter_ids),
        "noise_only": tuple(f"trained_center__{process_id}" for process_id in process_ids),
        "joint": tuple(
            f"{parameter_id}__{process_id}"
            for parameter_id in parameter_ids
            for process_id in process_ids
        ),
    }


def _validate_result_method_arrays(
    method_name: str,
    predictions,
    candidate_ids,
    candidate_predictions,
    probabilities,
    candidate_covariance_diagonals,
    combined_covariance_diagonals,
    target_shape: tuple[int, int],
    basin_id: str,
    expected_candidate_ids: Sequence[str] | None = None,
) -> None:
    if method_name not in EXPECTED_CANDIDATE_COUNTS:
        raise ValueError(f"basin {basin_id} has unknown method {method_name}")
    candidate_count = EXPECTED_CANDIDATE_COUNTS[method_name]
    predicted = np.asarray(predictions, dtype=np.float64)
    members = np.asarray(candidate_predictions, dtype=np.float64)
    weights = np.asarray(probabilities, dtype=np.float64)
    identifiers = tuple(str(value) for value in candidate_ids)
    if predicted.shape != target_shape or not np.all(np.isfinite(predicted)):
        raise ValueError(f"basin {basin_id} method {method_name} predictions are invalid")
    if len(identifiers) != candidate_count or len(set(identifiers)) != candidate_count:
        raise ValueError(f"basin {basin_id} method {method_name} candidate count or identifiers are invalid")
    if expected_candidate_ids is not None and identifiers != tuple(expected_candidate_ids):
        raise ValueError(f"basin {basin_id} method {method_name} candidate identifiers do not match the contract")
    expected_member_shape = (*target_shape, candidate_count)
    if members.shape != expected_member_shape or not np.all(np.isfinite(members)):
        raise ValueError(f"basin {basin_id} method {method_name} candidate predictions are invalid")
    if weights.shape != expected_member_shape or not np.all(np.isfinite(weights)):
        raise ValueError(f"basin {basin_id} method {method_name} probabilities are invalid")
    if np.any(weights < 0.0):
        raise ValueError(f"basin {basin_id} method {method_name} probabilities must be nonnegative")
    if np.max(np.abs(weights.sum(axis=2) - 1.0), initial=0.0) > 1e-12:
        raise ValueError(f"basin {basin_id} method {method_name} probabilities do not sum to one")
    weighted = np.sum(weights * members, axis=2)
    if not np.allclose(predicted, weighted, rtol=1e-11, atol=1e-12):
        raise ValueError(f"basin {basin_id} method {method_name} combined predictions are inconsistent")
    if method_name == "open_loop":
        if candidate_covariance_diagonals is not None or combined_covariance_diagonals is not None:
            raise ValueError(f"basin {basin_id} open loop must not contain filter covariance diagnostics")
        return
    candidate_covariance = np.asarray(candidate_covariance_diagonals, dtype=np.float64)
    combined_covariance = np.asarray(combined_covariance_diagonals, dtype=np.float64)
    if candidate_covariance.shape != (*target_shape, candidate_count, 15):
        raise ValueError(f"basin {basin_id} method {method_name} candidate covariance shape is invalid")
    if combined_covariance.shape != (*target_shape, 15):
        raise ValueError(f"basin {basin_id} method {method_name} combined covariance shape is invalid")
    if not np.all(np.isfinite(candidate_covariance)) or not np.all(np.isfinite(combined_covariance)):
        raise ValueError(f"basin {basin_id} method {method_name} covariance diagnostics are not finite")
    if np.any(candidate_covariance < -1e-10) or np.any(combined_covariance < -1e-10):
        raise ValueError(f"basin {basin_id} method {method_name} covariance diagonal is negative")


def _json_ready(value):
    if isinstance(value, Mapping):
        return {str(key): _json_ready(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [_json_ready(item) for item in value]
    if isinstance(value, Path):
        return str(value)
    if isinstance(value, np.ndarray):
        return value.tolist()
    if isinstance(value, np.generic):
        return value.item()
    return value


def _write_json(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(_json_ready(value), indent=2, sort_keys=True, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


def _safe_identifier(value: str) -> str:
    identifier = str(value)
    if re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,127}", identifier) is None:
        raise ValueError("identifier must use 1-128 letters, digits, dots, underscores, or hyphens")
    return identifier


def _artifact_checksums(directory: Path) -> dict[str, str]:
    return {
        path.relative_to(directory).as_posix(): sha256_file(path)
        for path in sorted(directory.rglob("*"))
        if path.is_file() and path.name != "checksums.json"
    }


def _snapshot_files(
    temporary_output: Path,
    repo_root: Path,
    category: str,
    files: Sequence[Path],
) -> list[dict]:
    entries = []
    seen = set()
    for supplied in files:
        path = Path(supplied).resolve()
        if not path.is_file():
            raise ValueError(f"{category} snapshot file is missing: {path}")
        try:
            relative = path.relative_to(repo_root)
        except ValueError as error:
            raise ValueError(f"{category} snapshot file is outside repo_root: {path}") from error
        key = relative.as_posix()
        if key in seen:
            continue
        seen.add(key)
        source_hash = sha256_file(path)
        destination = temporary_output / f"{category}_snapshot" / relative
        if len(str(destination)) >= 240:
            destination = temporary_output / f"{category}_snapshot" / "_long_paths" / source_hash
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, destination)
        entries.append(
            {
                "original_path": key,
                "snapshot_path": destination.relative_to(temporary_output).as_posix(),
                "sha256": source_hash,
            }
        )
    return entries


def _copy_contract_tables(contract_directory: Path, result_directory: Path) -> None:
    contract = Path(contract_directory).resolve()
    checksums = json.loads((contract / "checksums.json").read_text(encoding="utf-8"))
    destination = Path(result_directory) / "contract_tables"
    destination.mkdir()
    for name in CONTRACT_TABLE_FILES:
        source = contract / name
        if not source.is_file() or checksums.get(name) != sha256_file(source):
            raise ValueError(f"contract table is missing or changed: {name}")
        shutil.copy2(source, destination / name)


def write_contract_package(
    results_root: Path,
    contract_id: str,
    config: Mapping,
    basin_table: pd.DataFrame,
    basin_contracts: Mapping[str, Mapping],
    input_audits: Mapping[str, Mapping],
    resource_history: Sequence[Mapping],
    interaction_audit: Mapping,
    source_files: Sequence[Path],
    input_files: Sequence[Path],
    repo_root: Path,
    execution_signature: Mapping | None = None,
) -> Path:
    identifier = _safe_identifier(contract_id)
    root = Path(results_root).resolve()
    repository = Path(repo_root).resolve()
    output = root / identifier
    temporary = root / f".{identifier}.incomplete"
    if output.exists() or temporary.exists():
        raise FileExistsError(f"refusing to overwrite contract path: {output}")
    ids = [str(value).zfill(8) for value in basin_table["gauge_id"]]
    if not ids or len(ids) != len(set(ids)):
        raise ValueError("basin_table must contain unique basin identifiers")
    if set(ids) != set(basin_contracts) or set(ids) != set(input_audits):
        raise ValueError("basin table, contracts, and input audits must contain the same identifiers")
    root.mkdir(parents=True, exist_ok=True)
    temporary.mkdir()
    try:
        _write_json(temporary / "config_snapshot.json", dict(config))
        table = basin_table.copy()
        table["gauge_id"] = table["gauge_id"].astype(str).str.zfill(8)
        table.to_csv(temporary / "basins.csv", index=False)
        for basin_id in ids:
            _write_json(temporary / "basin_contracts" / f"{basin_id}.json", basin_contracts[basin_id])
            _write_json(temporary / "input_audits" / f"{basin_id}.json", input_audits[basin_id])
        parameter_rows = []
        process_rows = []
        observation_rows = []
        input_rows = []
        for basin_id in ids:
            contract = basin_contracts[basin_id]
            parameter_order = parameter_order_from_identifiers(contract["parameter_vectors"])
            for parameter_id, row in contract["parameter_vectors"].items():
                distance_fields = {}
                if parameter_order == PARAMETER_ORDER:
                    distance_fields = {
                        "normalized_distance_to_center": row.get(
                            "normalized_distance_to_center"
                        ),
                        "selected_pair_distance": row.get("selected_pair_distance"),
                        "selected_pair_minimum_distance": row.get(
                            "selected_pair_minimum_distance"
                        ),
                    }
                parameter_rows.append(
                    {
                        "basin_id": basin_id,
                        "parameter_id": parameter_id,
                        "candidate_index": row.get("candidate_index"),
                        "development_nse": row.get("development_nse"),
                        "development_mean_discharge_mm_day": row.get("development_mean_discharge"),
                        "selection_reason": row.get("selection_reason"),
                        "source_path": contract["parameter_source"]["path"],
                        "source_sha256": contract["parameter_source"]["sha256"],
                        "source_sha256_scope": contract["parameter_source"].get("sha256_scope"),
                        **distance_fields,
                        **{name: row["parameters"][name] for name in PARAMETER_NAMES},
                    }
                )
            selected_process = contract["process_noise"]["selected_process_id"]
            for row in contract["process_noise"]["candidates"]:
                process_rows.append(
                    {
                        "basin_id": basin_id,
                        "process_id": row["process_id"],
                        "selected_for_fixed_filter": row["process_id"] == selected_process,
                        "variance_scale": row["variance_scale"],
                        **{
                            f"variance_{state_name}": row["covariance_diagonal"][index]
                            for index, state_name in enumerate(STATE_NAMES)
                        },
                    }
                )
            observation = contract["observation_noise"]
            observation_rows.append(
                {
                    "basin_id": basin_id,
                    "standard_deviation_mm_day": observation["selected_standard_deviation_mm_day"],
                    "variance_mm2_day2": observation["selected_variance_mm2_day2"],
                    "candidate_standard_deviations_mm_day": json.dumps(
                        observation.get("candidate_standard_deviations_mm_day", [])
                    ),
                    "meaning": observation.get("meaning"),
                }
            )
            for row in input_audits[basin_id].get("variables", []):
                input_rows.append({"basin_id": basin_id, **row})
        pd.DataFrame(parameter_rows).to_csv(temporary / "parameter_vectors.csv", index=False)
        pd.DataFrame(process_rows).to_csv(temporary / "process_noise_covariances.csv", index=False)
        pd.DataFrame(observation_rows).to_csv(temporary / "observation_noise.csv", index=False)
        pd.DataFrame(input_rows).to_csv(temporary / "input_variables.csv", index=False)
        pd.DataFrame(
            [
                {
                    "parameter_name": name,
                    "meaning": PARAMETER_CONTRACT[name]["meaning"],
                    "unit": PARAMETER_CONTRACT[name]["unit"],
                    "lower_bound": PARAMETER_CONTRACT[name]["bounds"][0],
                    "upper_bound": PARAMETER_CONTRACT[name]["bounds"][1],
                }
                for name in PARAMETER_NAMES
            ]
        ).to_csv(temporary / "parameter_dictionary.csv", index=False)
        _write_json(temporary / "interaction_audit.json", interaction_audit)
        _write_json(temporary / "resource_history.json", list(resource_history))
        if execution_signature is not None:
            _write_json(temporary / "execution_signature.json", execution_signature)
        snapshot_manifest = {
            "source_files": _snapshot_files(temporary, repository, "source", source_files),
            "input_files": _snapshot_files(temporary, repository, "input", input_files),
        }
        _write_json(temporary / "snapshot_manifest.json", snapshot_manifest)
        _write_json(
            temporary / "contract_manifest.json",
            {
                "artifact_type": "calibration_only_uncertainty_contract",
                "contract_id": identifier,
                "basin_count": len(ids),
                "basins": ids,
                "uses_evaluation_discharge_for_selection": False,
                "evaluation_discharge_parsed_before_freeze": False,
                "selected_interaction_mode": interaction_audit.get("selected_mode"),
                "has_verified_execution_signature": execution_signature is not None,
            },
        )
        _write_json(temporary / "checksums.json", _artifact_checksums(temporary))
        verify_contract_package(temporary)
        os.replace(temporary, output)
    except Exception:
        if temporary.exists():
            shutil.rmtree(temporary)
        raise
    return output


def _verify_checksums(directory: Path) -> None:
    checksum_path = directory / "checksums.json"
    if not checksum_path.is_file():
        raise ValueError("artifact checksum file is missing")
    expected = json.loads(checksum_path.read_text(encoding="utf-8"))
    actual = _artifact_checksums(directory)
    if expected != actual:
        differing = sorted(set(expected) | set(actual))
        differing = [key for key in differing if expected.get(key) != actual.get(key)]
        raise ValueError(f"artifact checksum mismatch: {differing[:10]}")


def _verify_snapshot_manifest(directory: Path) -> None:
    manifest = json.loads((directory / "snapshot_manifest.json").read_text(encoding="utf-8"))
    for category in ("source_files", "input_files"):
        for row in manifest.get(category, []):
            path = directory / row["snapshot_path"]
            if not path.is_file() or sha256_file(path) != row["sha256"]:
                raise ValueError(f"snapshot checksum mismatch: {row.get('snapshot_path')}")


def _verify_execution_signature_snapshot(directory: Path, signature: Mapping) -> None:
    freshness = signature.get("source_process_freshness", {})
    process = signature.get("environment", {}).get("process", {})
    if (
        freshness.get("passed") is not True
        or freshness.get("process_create_time_unix_seconds")
        != process.get("create_time_unix_seconds")
        or float(freshness.get("latest_source_mtime_unix_seconds", float("inf")))
        > float(freshness.get("process_create_time_unix_seconds", float("-inf")))
        + float(freshness.get("maximum_clock_tolerance_seconds", 0.0))
    ):
        raise ValueError("execution signature does not prove a fresh source process")
    snapshot_manifest = json.loads((directory / "snapshot_manifest.json").read_text(encoding="utf-8"))
    snapshot_hashes = {}
    for category in ("source_files", "input_files"):
        for row in snapshot_manifest.get(category, []):
            original_path = row["original_path"]
            if original_path in snapshot_hashes and snapshot_hashes[original_path] != row["sha256"]:
                raise ValueError(f"execution source appears twice with conflicting hashes: {original_path}")
            snapshot_hashes[original_path] = row["sha256"]
    expected = dict(signature.get("files_sha256", {}))
    if snapshot_hashes != expected:
        differing = sorted(set(snapshot_hashes) | set(expected))
        differing = [key for key in differing if snapshot_hashes.get(key) != expected.get(key)]
        raise ValueError(f"execution signature and frozen snapshots differ: {differing[:10]}")


def _verify_resource_history(directory: Path, config: Mapping, run_kind: str) -> None:
    if "resource" not in config:
        return
    history = json.loads((directory / "resource_history.json").read_text(encoding="utf-8"))
    verify_resource_history_rows(
        history,
        config["resource"],
        require_finish=False,
        run_kind=run_kind,
    )


def _expected_flat_contract_tables(directory: Path, basin_ids: Sequence[str]) -> dict[str, pd.DataFrame]:
    parameter_rows = []
    process_rows = []
    observation_rows = []
    input_rows = []
    for basin_id in basin_ids:
        contract = json.loads(
            (directory / "basin_contracts" / f"{basin_id}.json").read_text(encoding="utf-8")
        )
        audit = json.loads(
            (directory / "input_audits" / f"{basin_id}.json").read_text(encoding="utf-8")
        )
        source = contract["parameter_source"]
        parameter_order = parameter_order_from_identifiers(contract["parameter_vectors"])
        for parameter_id in parameter_order:
            row = contract["parameter_vectors"][parameter_id]
            distance_fields = {}
            if parameter_order == PARAMETER_ORDER:
                distance_fields = {
                    "normalized_distance_to_center": row.get(
                        "normalized_distance_to_center"
                    ),
                    "selected_pair_distance": row.get("selected_pair_distance"),
                    "selected_pair_minimum_distance": row.get(
                        "selected_pair_minimum_distance"
                    ),
                }
            parameter_rows.append(
                {
                    "basin_id": basin_id,
                    "parameter_id": parameter_id,
                    "candidate_index": row.get("candidate_index"),
                    "development_nse": row.get("development_nse"),
                    "development_mean_discharge_mm_day": row.get("development_mean_discharge"),
                    "selection_reason": row.get("selection_reason"),
                    "source_path": source["path"],
                    "source_sha256": source["sha256"],
                    "source_sha256_scope": source.get("sha256_scope"),
                    **distance_fields,
                    **{name: row["parameters"][name] for name in PARAMETER_NAMES},
                }
            )
        selected_process = contract["process_noise"]["selected_process_id"]
        for row in contract["process_noise"]["candidates"]:
            process_rows.append(
                {
                    "basin_id": basin_id,
                    "process_id": row["process_id"],
                    "selected_for_fixed_filter": row["process_id"] == selected_process,
                    "variance_scale": row["variance_scale"],
                    **{
                        f"variance_{state_name}": row["covariance_diagonal"][index]
                        for index, state_name in enumerate(STATE_NAMES)
                    },
                }
            )
        observation = contract["observation_noise"]
        observation_rows.append(
            {
                "basin_id": basin_id,
                "standard_deviation_mm_day": observation["selected_standard_deviation_mm_day"],
                "variance_mm2_day2": observation["selected_variance_mm2_day2"],
                "candidate_standard_deviations_mm_day": json.dumps(
                    observation.get("candidate_standard_deviations_mm_day", [])
                ),
                "meaning": observation.get("meaning"),
            }
        )
        input_rows.extend({"basin_id": basin_id, **row} for row in audit.get("variables", []))
    parameter_dictionary = pd.DataFrame(
        [
            {
                "parameter_name": name,
                "meaning": PARAMETER_CONTRACT[name]["meaning"],
                "unit": PARAMETER_CONTRACT[name]["unit"],
                "lower_bound": PARAMETER_CONTRACT[name]["bounds"][0],
                "upper_bound": PARAMETER_CONTRACT[name]["bounds"][1],
            }
            for name in PARAMETER_NAMES
        ]
    )
    return {
        "parameter_vectors.csv": pd.DataFrame(parameter_rows),
        "process_noise_covariances.csv": pd.DataFrame(process_rows),
        "observation_noise.csv": pd.DataFrame(observation_rows),
        "input_variables.csv": pd.DataFrame(input_rows),
        "parameter_dictionary.csv": parameter_dictionary,
    }


def _csv_roundtrip_frame(frame: pd.DataFrame) -> pd.DataFrame:
    if len(frame.columns) == 0:
        return frame.copy()
    buffer = io.StringIO(newline="")
    frame.to_csv(buffer, index=False, lineterminator="\n")
    buffer.seek(0)
    dtype = {"basin_id": str} if "basin_id" in frame.columns else None
    return pd.read_csv(buffer, dtype=dtype)


def _verify_flat_contract_tables(directory: Path, basin_ids: Sequence[str]) -> None:
    expected_tables = _expected_flat_contract_tables(directory, basin_ids)
    for name, raw_expected in expected_tables.items():
        expected = _csv_roundtrip_frame(raw_expected)
        try:
            dtype = {"basin_id": str} if "basin_id" in expected.columns else None
            actual = pd.read_csv(directory / name, dtype=dtype)
        except pd.errors.EmptyDataError:
            actual = pd.DataFrame()
        if set(actual.columns) != set(expected.columns):
            raise ValueError(f"flat contract table does not match canonical records: {name}")
        actual = actual.loc[:, expected.columns]
        if not _dataframe_values_equal(
            expected,
            actual,
            list(expected.columns),
        ):
            raise ValueError(f"flat contract table does not match canonical records: {name}")


def _recompute_parameter_pool_from_snapshot(
    directory: Path,
    basin_id: str,
    config: Mapping,
    center_parameters: Mapping,
    candidates: Sequence[Mapping],
) -> dict:
    """Recalculate all parameter diagnostics from the immutable input snapshot."""
    from .preparation import (
        _center_parameters,
        _load_complete_period,
        _load_forcing_only_period,
        evaluate_parameter_pool,
    )

    snapshot_root = (Path(directory).resolve() / "input_snapshot").resolve()
    if not snapshot_root.is_dir():
        raise ValueError(f"basin {basin_id} frozen input snapshot is missing")
    snapshot_center, _, _ = _center_parameters(snapshot_root, basin_id, config)
    contract_center = np.asarray(
        [center_parameters[name] for name in PARAMETER_NAMES], dtype=np.float64
    )
    frozen_center = np.asarray(
        [snapshot_center[name] for name in PARAMETER_NAMES], dtype=np.float64
    )
    if not np.array_equal(contract_center, frozen_center):
        raise ValueError(
            f"basin {basin_id} trained center does not match the frozen parameter input"
        )
    warmup = _load_forcing_only_period(
        snapshot_root,
        basin_id,
        config,
        config["calibration_warmup_start"],
        config["calibration_warmup_end"],
    )
    development, observations = _load_complete_period(
        snapshot_root,
        basin_id,
        config,
        config["calibration_selection_start"],
        config["calibration_selection_end"],
    )
    return evaluate_parameter_pool(
        center_parameters=snapshot_center,
        candidates=candidates,
        warmup_forcing=warmup,
        development_forcing=development,
        development_observations=observations,
    )


def _verify_current_parameter_selection(
    directory: Path,
    basin_id: str,
    contract: Mapping,
    config: Mapping,
) -> None:
    """Reconstruct the current calibration-only maximin parameter selection."""
    selection_config = config.get("parameter_selection", {})
    schema_version = selection_config.get("schema_version")
    common_config = {
        "maximum_nse_drop": 0.03,
        "normalization": "frozen_physical_bound_span",
        "distance": "euclidean",
        "objective": "maximize_the_minimum_of_both_center_distances_and_the_pair_distance",
        "tie_break": "candidate_index_ascending_lexicographic",
    }
    if schema_version == 2:
        required_config = {
            "schema_version": 2,
            "strategy": "global_maximin_normalized_parameter_distance",
            "pool_generator": "scrambled_sobol",
            "pool_size": 256,
            "local_fraction": 0.1,
            **common_config,
        }
        pool_size = 256
    elif schema_version == 3:
        required_config = {
            "schema_version": 3,
            "strategy": "multiscale_global_maximin_normalized_parameter_distance",
            "pool_generator": "scrambled_sobol_restarted_per_scale",
            "pool_size": 1024,
            "candidates_per_scale": 256,
            "local_fractions": [0.1, 0.05, 0.025, 0.0125],
            "candidate_order": "local_fraction_config_order_then_scale_candidate_index",
            **common_config,
        }
        pool_size = 1024
    else:
        raise ValueError(f"basin {basin_id} parameter selection schema is unsupported")
    for key, expected in required_config.items():
        if selection_config.get(key) != expected:
            raise ValueError(
                f"basin {basin_id} current parameter selection config {key} is not frozen"
            )
    if config.get("random_seed") != 1:
        raise ValueError(f"basin {basin_id} current parameter selection seed is not frozen")

    vectors = contract["parameter_vectors"]
    center_row = vectors["trained_center"]
    center_parameters = center_row["parameters"]
    center_nse = float(center_row.get("development_nse", np.nan))
    center_mean = float(center_row.get("development_mean_discharge", np.nan))
    stored_center_nse = float(contract.get("center_development_nse", np.nan))
    if (
        not np.all(np.isfinite([center_nse, center_mean, stored_center_nse]))
        or stored_center_nse != center_nse
    ):
        raise ValueError(f"basin {basin_id} center development diagnostics are invalid")

    pool_rows = contract.get("parameter_pool_audit")
    if not isinstance(pool_rows, list) or len(pool_rows) != pool_size:
        raise ValueError(
            f"basin {basin_id} parameter pool must contain exactly {pool_size} candidates"
        )
    if [row.get("candidate_index") for row in pool_rows] != list(range(pool_size)):
        raise ValueError(f"basin {basin_id} parameter pool indices are not frozen")

    if schema_version == 2:
        expected_pool = generate_local_parameter_pool(
            center_parameters,
            count=256,
            fraction=0.1,
            seed=int(config.get("random_seed", -1)),
        )
        expected_provenance = [
            {"candidate_index": candidate_index}
            for candidate_index in range(pool_size)
        ]
    else:
        expected_pool, expected_provenance = generate_multiscale_parameter_pool(
            center_parameters,
            fractions=(0.1, 0.05, 0.025, 0.0125),
            count_per_scale=256,
            seed=int(config.get("random_seed", -1)),
        )
    candidate_parameters = []
    candidate_nse = np.empty(pool_size, dtype=np.float64)
    candidate_means = np.empty(pool_size, dtype=np.float64)
    for index, (row, expected_parameters, expected_source) in enumerate(
        zip(pool_rows, expected_pool, expected_provenance)
    ):
        for field, expected_value in expected_source.items():
            if row.get(field) != expected_value:
                raise ValueError(
                    f"basin {basin_id} parameter pool candidate {index} provenance is inconsistent"
                )
        parameters = row.get("parameters", {})
        if set(parameters) != set(PARAMETER_NAMES):
            raise ValueError(f"basin {basin_id} parameter pool candidate {index} is incomplete")
        actual_values = np.asarray(
            [parameters[name] for name in PARAMETER_NAMES], dtype=np.float64
        )
        expected_values = np.asarray(
            [expected_parameters[name] for name in PARAMETER_NAMES], dtype=np.float64
        )
        if not np.array_equal(actual_values, expected_values):
            raise ValueError(
                f"basin {basin_id} parameter pool candidate {index} does not match the frozen generator"
            )
        candidate_parameters.append({name: float(parameters[name]) for name in PARAMETER_NAMES})
        candidate_nse[index] = float(row.get("development_nse", np.nan))
        candidate_means[index] = float(row.get("development_mean_discharge", np.nan))
    if not np.all(np.isfinite(candidate_nse)) or not np.all(np.isfinite(candidate_means)):
        raise ValueError(f"basin {basin_id} parameter pool diagnostics are not finite")
    recalculated = _recompute_parameter_pool_from_snapshot(
        directory=directory,
        basin_id=basin_id,
        config=config,
        center_parameters=center_parameters,
        candidates=candidate_parameters,
    )
    recalculated_center_nse = float(recalculated.get("center_nse", np.nan))
    recalculated_center_mean = float(
        recalculated.get("center_mean_discharge", np.nan)
    )
    recalculated_nse = np.asarray(recalculated.get("candidate_nse"), dtype=np.float64)
    recalculated_means = np.asarray(
        recalculated.get("candidate_mean_discharge"), dtype=np.float64
    )
    tolerance = 1e-12
    if (
        recalculated_nse.shape != (pool_size,)
        or recalculated_means.shape != (pool_size,)
        or not np.all(np.isfinite(recalculated_nse))
        or not np.all(np.isfinite(recalculated_means))
        or not np.all(np.isfinite([recalculated_center_nse, recalculated_center_mean]))
    ):
        raise ValueError(f"basin {basin_id} frozen-input recalculation is invalid")
    if (
        abs(center_nse - recalculated_center_nse) > tolerance
        or abs(center_mean - recalculated_center_mean) > tolerance
        or float(np.max(np.abs(candidate_nse - recalculated_nse))) > tolerance
        or float(np.max(np.abs(candidate_means - recalculated_means))) > tolerance
    ):
        raise ValueError(
            f"basin {basin_id} saved development diagnostics differ from recomputed frozen-input values"
        )

    center_nse = recalculated_center_nse
    center_mean = recalculated_center_mean
    candidate_nse = recalculated_nse
    candidate_means = recalculated_means
    eligibility = candidate_nse >= center_nse - 0.03
    if any(bool(row.get("eligible")) != bool(eligibility[index]) for index, row in enumerate(pool_rows)):
        raise ValueError(f"basin {basin_id} parameter pool eligibility flags are inconsistent")

    reconstructed = select_equifinal_parameters(
        center=center_parameters,
        candidates=candidate_parameters,
        center_nse=center_nse,
        center_mean_discharge=center_mean,
        candidate_nse=candidate_nse,
        candidate_mean_discharge=candidate_means,
        maximum_nse_drop=0.03,
    )
    for parameter_id in PARAMETER_ORDER:
        actual = vectors[parameter_id]
        expected = reconstructed[parameter_id]
        if actual.get("candidate_index") != expected.get("candidate_index"):
            raise ValueError(
                f"basin {basin_id} parameter pair is not the globally maximizing eligible pair"
            )
        actual_parameters = np.asarray(
            [actual["parameters"][name] for name in PARAMETER_NAMES], dtype=np.float64
        )
        expected_parameters = np.asarray(
            [expected["parameters"][name] for name in PARAMETER_NAMES], dtype=np.float64
        )
        if not np.array_equal(actual_parameters, expected_parameters):
            raise ValueError(
                f"basin {basin_id} selected parameter values do not match their pool candidates"
            )
        for field in ("development_nse", "development_mean_discharge"):
            if abs(float(actual.get(field, np.nan)) - float(expected[field])) > tolerance:
                raise ValueError(
                    f"basin {basin_id} selected parameter development diagnostics are inconsistent"
                )
        if parameter_id != "trained_center":
            if schema_version == 3:
                expected_source = expected_provenance[int(expected["candidate_index"])]
                for field in (
                    "scale_index",
                    "local_fraction",
                    "scale_candidate_index",
                ):
                    if actual.get(field) != expected_source[field]:
                        raise ValueError(
                            f"basin {basin_id} selected parameter provenance {field} is inconsistent"
                        )
            for field in (
                "normalized_distance_to_center",
                "selected_pair_distance",
                "selected_pair_minimum_distance",
            ):
                if not np.isclose(
                    float(actual.get(field, np.nan)),
                    float(expected[field]),
                    rtol=0.0,
                    atol=1e-15,
                ):
                    raise ValueError(
                        f"basin {basin_id} selected parameter distance diagnostics are inconsistent"
                    )
            if center_nse - float(actual["development_nse"]) > 0.03 + 1e-15:
                raise ValueError(
                    f"basin {basin_id} selected parameter exceeds the frozen development tolerance"
                )

    unique_eligible = set()
    center_key = tuple(float(center_parameters[name]) for name in PARAMETER_NAMES)
    for index in np.flatnonzero(eligibility):
        key = tuple(candidate_parameters[int(index)][name] for name in PARAMETER_NAMES)
        if key != center_key:
            unique_eligible.add(key)
    selection = contract.get("parameter_selection", {})
    required_metadata = {
        "schema_version": schema_version,
        "strategy": required_config["strategy"],
        "pool_generator": required_config["pool_generator"],
        "pool_seed": 1,
        "pool_size": pool_size,
        "maximum_nse_drop": 0.03,
        "normalization": "frozen_physical_bound_span",
        "distance": "euclidean",
        "objective": "maximize_the_minimum_of_both_center_distances_and_the_pair_distance",
        "tie_break": "candidate_index_ascending_lexicographic",
        "mean_discharge_role": "diagnostic_only_not_a_selection_constraint",
        "eligible_distinct_candidate_count": len(unique_eligible),
        "selected_candidate_indices": [
            reconstructed["equifinal_diverse_1"]["candidate_index"],
            reconstructed["equifinal_diverse_2"]["candidate_index"],
        ],
    }
    if schema_version == 2:
        required_metadata["local_fraction"] = 0.1
    else:
        required_metadata.update(
            {
                "candidates_per_scale": 256,
                "local_fractions": [0.1, 0.05, 0.025, 0.0125],
                "scale_count": 4,
                "candidate_order": "local_fraction_config_order_then_scale_candidate_index",
            }
        )
    for key, expected in required_metadata.items():
        if selection.get(key) != expected:
            raise ValueError(f"basin {basin_id} parameter selection metadata {key} is inconsistent")
    if not np.isclose(
        float(selection.get("selected_pair_minimum_distance", np.nan)),
        float(reconstructed["equifinal_diverse_1"]["selected_pair_minimum_distance"]),
        rtol=0.0,
        atol=1e-15,
    ):
        raise ValueError(f"basin {basin_id} parameter selection objective is inconsistent")


def verify_contract_package(contract_directory: Path) -> dict:
    directory = Path(contract_directory).resolve()
    if directory.name.endswith(".failed") or (directory / "failure.json").exists():
        raise ValueError("failed contract artifact cannot be verified as successful")
    _verify_checksums(directory)
    _verify_snapshot_manifest(directory)
    manifest = json.loads((directory / "contract_manifest.json").read_text(encoding="utf-8"))
    config = json.loads((directory / "config_snapshot.json").read_text(encoding="utf-8"))
    legacy_identity_allowed = LEGACY_CONTRACT_CHECKSUM_ALLOWLIST.get(
        manifest.get("contract_id")
    ) == sha256_file(directory / "checksums.json")
    _verify_resource_history(directory, config, run_kind="contract")
    if manifest.get("artifact_type") != "calibration_only_uncertainty_contract":
        raise ValueError("contract artifact type is invalid")
    if manifest.get("uses_evaluation_discharge_for_selection") is not False:
        raise ValueError("contract manifest allows evaluation discharge selection")
    if manifest.get("evaluation_discharge_parsed_before_freeze") is not False:
        raise ValueError("contract manifest does not enforce evaluation-discharge blindness")
    if manifest.get("has_verified_execution_signature"):
        signature = json.loads((directory / "execution_signature.json").read_text(encoding="utf-8"))
        if signature.get("verified_unchanged_from_start_to_finish") is not True:
            raise ValueError("contract execution signature was not verified across the run")
        _verify_execution_signature_snapshot(directory, signature)
        parameter_source = config.get("parameter_source", {})
        if signature.get("parameter_table_sha256") != parameter_source.get("table_sha256"):
            raise ValueError("contract parameter table signature is inconsistent")
        if signature.get("parameter_projection_content_sha256") != parameter_source.get(
            "projection_content_sha256"
        ):
            raise ValueError("contract parameter projection content signature is inconsistent")
        signed_files = signature.get("files_sha256", {})
        if signed_files.get(parameter_source.get("table_path")) != parameter_source.get("table_sha256"):
            raise ValueError("contract parameter table snapshot is inconsistent")
        if signed_files.get(parameter_source.get("metadata_path")) != parameter_source.get("metadata_sha256"):
            raise ValueError("contract parameter metadata snapshot is inconsistent")
        calibration_source = config.get("calibration_discharge_source", {})
        if signed_files.get(calibration_source.get("table_path")) != calibration_source.get("table_sha256"):
            raise ValueError("contract calibration discharge snapshot is inconsistent")
        if signed_files.get(calibration_source.get("metadata_path")) != calibration_source.get(
            "metadata_sha256"
        ):
            raise ValueError("contract calibration discharge metadata snapshot is inconsistent")
    interaction = json.loads((directory / "interaction_audit.json").read_text(encoding="utf-8"))
    if interaction.get("uses_evaluation_discharge") is not False:
        raise ValueError("interaction selection must exclude evaluation discharge")
    mode = interaction.get("selected_mode")
    if mode not in {"full", "parameter_grouped", "none"}:
        raise ValueError("selected interaction mode is invalid")
    manifest_mode = manifest.get("selected_interaction_mode")
    if manifest_mode != mode:
        raise ValueError("contract interaction mode is inconsistent with its manifest")
    configured_mode = config.get("formal_interaction_mode")
    if configured_mode is not None and configured_mode != mode:
        raise ValueError("contract interaction mode is inconsistent with its config")
    basin_table = pd.read_csv(directory / "basins.csv", dtype={"gauge_id": str})
    basin_ids = basin_table["gauge_id"].str.zfill(8).tolist()
    if basin_ids != manifest.get("basins") or len(basin_ids) != manifest.get("basin_count"):
        raise ValueError("contract basin manifest is inconsistent")
    for basin_id in basin_ids:
        contract = json.loads((directory / "basin_contracts" / f"{basin_id}.json").read_text(encoding="utf-8"))
        audit = json.loads((directory / "input_audits" / f"{basin_id}.json").read_text(encoding="utf-8"))
        if contract.get("basin_id") != basin_id or audit.get("passed") is not True:
            raise ValueError(f"basin {basin_id} contract identity or input audit is invalid")
        if audit.get("evaluation_discharge_values_parsed") is not False:
            raise ValueError(f"basin {basin_id} input audit parsed evaluation discharge before freeze")
        if manifest.get("has_verified_execution_signature"):
            discharge_hashes = signature.get("calibration_discharge_slice_sha256", {})
            streamflow_rows = [
                row for row in audit.get("variables", []) if row.get("variable_id") == "streamflow"
            ]
            if (
                len(streamflow_rows) != 1
                or streamflow_rows[0].get("source_sha256") != calibration_source.get("table_sha256")
                or streamflow_rows[0].get("raw_selected_source_lines_sha256")
                != discharge_hashes.get(basin_id)
            ):
                raise ValueError(f"basin {basin_id} calibration discharge signature is inconsistent")
        if contract.get("preparation_data_boundary", {}).get("uses_evaluation_discharge") is not False:
            raise ValueError(f"basin {basin_id} parameter/noise selection used evaluation discharge")
        if manifest.get("has_verified_execution_signature"):
            contract_parameter_source = contract.get("parameter_source", {})
            if contract_parameter_source.get("sha256") != signature.get("parameter_table_sha256"):
                raise ValueError(f"basin {basin_id} parameter table signature is inconsistent")
            if contract_parameter_source.get("metadata_path") != parameter_source.get("metadata_path"):
                raise ValueError(f"basin {basin_id} parameter metadata path is inconsistent")
            if contract_parameter_source.get("metadata_sha256") != parameter_source.get("metadata_sha256"):
                raise ValueError(f"basin {basin_id} parameter metadata signature is inconsistent")
            expected_projection_columns = (
                "basin_id",
                "run_status",
                *(f"p_{name}" for name in PARAMETER_NAMES),
                *(f"state_{name}" for name in STATE_NAMES[:5]),
            )
            if tuple(contract_parameter_source.get("projection_columns", [])) != expected_projection_columns:
                raise ValueError(f"basin {basin_id} parameter projection columns are inconsistent")
        vectors = contract.get("parameter_vectors", {})
        try:
            parameter_order = parameter_order_from_identifiers(vectors)
        except ValueError as error:
            raise ValueError(
                f"basin {basin_id} does not contain one supported set of three parameter vectors"
            ) from error
        configured_selection_schema = config.get("parameter_selection", {}).get(
            "schema_version"
        )
        contract_selection_schema = contract.get("parameter_selection", {}).get(
            "schema_version"
        )
        if parameter_order == LEGACY_PARAMETER_ORDER:
            if not legacy_identity_allowed:
                raise ValueError(
                    f"basin {basin_id} legacy parameter identifiers are not in the external identity allowlist"
                )
        elif (
            configured_selection_schema not in (2, 3)
            or contract_selection_schema != configured_selection_schema
            or not isinstance(contract.get("parameter_pool_audit"), list)
        ):
            raise ValueError(
                f"basin {basin_id} current parameter identifiers lack one consistent reconstructable schema"
            )
        for row in vectors.values():
            parameters = row.get("parameters", {})
            if set(parameters) != set(PARAMETER_NAMES):
                raise ValueError(f"basin {basin_id} parameter names are incomplete")
            values = np.asarray([parameters[name] for name in PARAMETER_NAMES], dtype=np.float64)
            if values.shape != (13,) or not np.all(np.isfinite(values)):
                raise ValueError(f"basin {basin_id} parameter vector is incomplete")
            for name, value in zip(PARAMETER_NAMES, values):
                lower, upper = V1_PARAMETER_BOUNDS[name]
                if value < lower or value > upper:
                    raise ValueError(f"basin {basin_id} parameter {name} is outside its frozen bounds")
        vector_keys = {
            tuple(vectors[parameter_id]["parameters"][name] for name in PARAMETER_NAMES)
            for parameter_id in parameter_order
        }
        if len(vector_keys) != 3:
            raise ValueError(f"basin {basin_id} parameter vectors are not distinct")
        if parameter_order == LEGACY_PARAMETER_ORDER:
            low_mean = float(
                vectors["equifinal_low_flow"].get("development_mean_discharge", np.nan)
            )
            center_mean = float(
                vectors["trained_center"].get("development_mean_discharge", np.nan)
            )
            high_mean = float(
                vectors["equifinal_high_flow"].get("development_mean_discharge", np.nan)
            )
            if (
                not np.all(np.isfinite([low_mean, center_mean, high_mean]))
                or not low_mean < center_mean < high_mean
            ):
                raise ValueError(
                    f"basin {basin_id} legacy parameter vectors do not bracket center mean discharge"
                )
        else:
            if mode != "full" or manifest_mode != "full" or configured_mode != "full":
                raise ValueError(
                    "current parameter-selection contracts require full interaction"
                )
            _verify_current_parameter_selection(directory, basin_id, contract, config)
        process_rows = contract.get("process_noise", {}).get("candidates", [])
        if len(process_rows) != 3:
            raise ValueError(f"basin {basin_id} does not contain three process covariances")
        process_ids = [str(row.get("process_id")) for row in process_rows]
        if len(set(process_ids)) != 3:
            raise ValueError(f"basin {basin_id} process identifiers are not unique")
        if contract.get("process_noise", {}).get("selected_process_id") not in process_ids:
            raise ValueError(f"basin {basin_id} selected process identifier is invalid")
        process_scales = np.asarray(
            [row.get("variance_scale", np.nan) for row in process_rows], dtype=np.float64
        )
        if (
            not np.all(np.isfinite(process_scales))
            or np.any(process_scales <= 0.0)
            or np.any(np.diff(process_scales) <= 0.0)
        ):
            raise ValueError(f"basin {basin_id} process scales are invalid")
        for row in process_rows:
            diagonal = np.asarray(row.get("covariance_diagonal"), dtype=np.float64)
            matrix = np.asarray(row.get("covariance_matrix"), dtype=np.float64)
            if diagonal.shape != (15,) or matrix.shape != (15, 15):
                raise ValueError(f"basin {basin_id} process covariance is incomplete")
            if (
                not np.all(np.isfinite(diagonal))
                or np.any(diagonal < 0.0)
                or np.any(diagonal[:5] <= 0.0)
                or np.count_nonzero(diagonal[5:]) != 0
                or not np.array_equal(matrix, np.diag(diagonal))
            ):
                raise ValueError(f"basin {basin_id} process covariance matrix and diagonal disagree")
        observation = contract.get("observation_noise", {})
        std = float(observation.get("selected_standard_deviation_mm_day", np.nan))
        variance = float(observation.get("selected_variance_mm2_day2", np.nan))
        if not np.isfinite(std) or std <= 0.0 or not np.isclose(variance, std**2, rtol=1e-12, atol=1e-15):
            raise ValueError(f"basin {basin_id} observation variance is invalid")
    _verify_flat_contract_tables(directory, basin_ids)
    return {
        "status": "verified",
        "contract_id": manifest["contract_id"],
        "basin_count": len(basin_ids),
        "interaction_mode": mode,
    }


def calculate_metrics(observations, predictions) -> dict[str, float]:
    observed = np.asarray(observations, dtype=np.float64)
    predicted = np.asarray(predictions, dtype=np.float64)
    if observed.ndim != 1 or observed.shape != predicted.shape or len(observed) == 0:
        raise ValueError("metric inputs must be equal nonempty vectors")
    if not np.all(np.isfinite(observed)) or not np.all(np.isfinite(predicted)):
        raise ValueError("metric inputs must be finite")
    residual = predicted - observed
    denominator = float(np.sum((observed - np.mean(observed)) ** 2))
    if denominator <= 0.0:
        raise ValueError("Nash-Sutcliffe efficiency requires nonconstant observations")
    return {
        "rmse": float(np.sqrt(np.mean(residual**2))),
        "mae": float(np.mean(np.abs(residual))),
        "nse": float(1.0 - np.sum(residual**2) / denominator),
    }


@dataclass(frozen=True)
class BasinEvaluation:
    basin_id: str
    dates: np.ndarray
    observations: np.ndarray
    methods: Mapping[str, MethodRunResult]


def _basin_metric_rows(result: BasinEvaluation) -> list[dict]:
    if tuple(result.methods) != METHOD_ORDER:
        raise ValueError("basin evaluation methods are incomplete or out of order")
    reference = result.methods["fixed_filter"]
    rows = []
    for lead_index, lead in enumerate(reference.lead_days):
        observed = reference.target_observations[:, lead_index]
        fixed = calculate_metrics(observed, reference.predictions[:, lead_index])
        for method_name, method in result.methods.items():
            if not np.array_equal(method.origin_indices, reference.origin_indices) or not np.array_equal(
                method.target_indices, reference.target_indices
            ):
                raise ValueError(f"basin {result.basin_id} methods do not share origin and target indices")
            if not np.array_equal(method.target_observations, reference.target_observations):
                raise ValueError(f"basin {result.basin_id} methods do not share target observations")
            metrics = calculate_metrics(observed, method.predictions[:, lead_index])
            rows.append(
                {
                    "basin_id": result.basin_id,
                    "method": method_name,
                    "lead_days": int(lead),
                    "n_origins": len(reference.origin_indices),
                    **metrics,
                    "rmse_change_percent_vs_fixed_filter": 100.0 * (metrics["rmse"] - fixed["rmse"])
                    / fixed["rmse"],
                    "mae_change_percent_vs_fixed_filter": 100.0 * (metrics["mae"] - fixed["mae"])
                    / fixed["mae"],
                    "nse_change_vs_fixed_filter": metrics["nse"] - fixed["nse"],
                    "strict_rmse_win_vs_fixed_filter": bool(metrics["rmse"] < fixed["rmse"]),
                }
            )
    return rows


def summarize_metrics(metrics: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for (method, lead), group in metrics.groupby(["method", "lead_days"], sort=False):
        rows.append(
            {
                "method": method,
                "lead_days": int(lead),
                "basin_count": len(group),
                "median_rmse": float(group["rmse"].median()),
                "median_mae": float(group["mae"].median()),
                "median_nse": float(group["nse"].median()),
                "median_rmse_change_percent_vs_fixed_filter": float(
                    group["rmse_change_percent_vs_fixed_filter"].median()
                ),
                "median_mae_change_percent_vs_fixed_filter": float(
                    group["mae_change_percent_vs_fixed_filter"].median()
                ),
                "median_nse_change_vs_fixed_filter": float(group["nse_change_vs_fixed_filter"].median()),
                "strict_rmse_win_count_vs_fixed_filter": int(group["strict_rmse_win_vs_fixed_filter"].sum()),
            }
        )
    return pd.DataFrame(rows)


class ResultPackageWriter:
    """Write each basin immediately, then atomically publish the completed result package."""

    def __init__(
        self,
        results_root: Path,
        experiment_id: str,
        contract_directory: Path,
        config: Mapping,
        verified_contract: Mapping | None = None,
    ):
        self.experiment_id = _safe_identifier(experiment_id)
        self.results_root = Path(results_root).resolve()
        self.contract_directory = Path(contract_directory).resolve()
        self.config = dict(config)
        contract_verification = (
            verify_contract_package(self.contract_directory)
            if verified_contract is None
            else dict(verified_contract)
        )
        if contract_verification.get("status") != "verified":
            raise ValueError("preverified contract status is invalid")
        self.contract_id = contract_verification["contract_id"]
        self.contract_checksums_sha256 = sha256_file(self.contract_directory / "checksums.json")
        contract_manifest = json.loads(
            (self.contract_directory / "contract_manifest.json").read_text(encoding="utf-8")
        )
        if (
            self.contract_id != contract_manifest.get("contract_id")
            or contract_verification.get("basin_count") != contract_manifest.get("basin_count")
        ):
            raise ValueError("preverified contract identity is inconsistent")
        self.expected_basin_ids = tuple(contract_manifest["basins"])
        self.output = self.results_root / self.experiment_id
        self.temporary = self.results_root / f".{self.experiment_id}.incomplete"
        if self.output.exists() or self.temporary.exists():
            raise FileExistsError(f"refusing to overwrite result path: {self.output}")
        self.results_root.mkdir(parents=True, exist_ok=True)
        self.temporary.mkdir()
        (self.temporary / "basins").mkdir()
        self.metric_rows: list[dict] = []
        self.basin_ids: list[str] = []
        self.evaluation_audit_ids: list[str] = []

    def write_basin(self, result: BasinEvaluation, evaluation_input_audit: Mapping | None = None) -> Path:
        basin_id = str(result.basin_id).zfill(8)
        if basin_id in self.basin_ids:
            raise ValueError(f"basin {basin_id} was already written")
        expected_next = self.expected_basin_ids[len(self.basin_ids)] if len(self.basin_ids) < len(
            self.expected_basin_ids
        ) else None
        if basin_id != expected_next:
            raise ValueError(f"basin {basin_id} is absent or out of order in the frozen contract")
        if tuple(result.methods) != METHOD_ORDER:
            raise ValueError(f"basin {basin_id} methods are incomplete or out of order")
        dates = np.asarray(result.dates, dtype="U10")
        observations = np.asarray(result.observations, dtype=np.float64)
        if dates.shape != observations.shape or len(dates) == 0 or not np.all(np.isfinite(observations)):
            raise ValueError(f"basin {basin_id} dates and observations are invalid")
        parsed_dates = pd.to_datetime(dates, format="%Y-%m-%d", errors="raise")
        if not parsed_dates.equals(pd.date_range(parsed_dates[0], periods=len(parsed_dates), freq="D")):
            raise ValueError(f"basin {basin_id} dates are not one continuous daily series")
        if "evaluation_start" in self.config and "evaluation_end" in self.config:
            configured_dates = pd.date_range(
                self.config["evaluation_start"], self.config["evaluation_end"], freq="D"
            )
            if not parsed_dates.equals(configured_dates):
                raise ValueError(f"basin {basin_id} dates do not equal the frozen evaluation period")
        reference = result.methods["fixed_filter"]
        expected_origins = len(dates) - int(np.max(reference.lead_days))
        if not np.array_equal(reference.origin_indices, np.arange(expected_origins, dtype=np.int64)):
            raise ValueError(f"basin {basin_id} common origin count is invalid")
        expected_targets = reference.origin_indices[:, None] + reference.lead_days[None, :]
        if not np.array_equal(reference.target_indices, expected_targets):
            raise ValueError(f"basin {basin_id} target indices do not match lead days")
        arrays = {
            "dates": dates,
            "observations": observations,
            "lead_days": reference.lead_days,
            "origin_indices": reference.origin_indices,
            "target_indices": reference.target_indices,
            "origin_dates": dates[reference.origin_indices],
            "target_dates": dates[reference.target_indices],
            "target_observations": reference.target_observations,
        }
        basin_contract = json.loads(
            (self.contract_directory / "basin_contracts" / f"{basin_id}.json").read_text(encoding="utf-8")
        )
        expected_candidate_ids = _expected_candidate_ids(basin_contract)
        for method_name, method in result.methods.items():
            if not np.array_equal(method.lead_days, reference.lead_days):
                raise ValueError(f"basin {basin_id} method {method_name} lead days differ")
            if not np.array_equal(method.origin_indices, reference.origin_indices):
                raise ValueError(f"basin {basin_id} method {method_name} origins differ")
            if not np.array_equal(method.target_indices, reference.target_indices):
                raise ValueError(f"basin {basin_id} method {method_name} targets differ")
            _validate_result_method_arrays(
                method_name=method_name,
                predictions=method.predictions,
                candidate_ids=method.candidate_ids,
                candidate_predictions=method.candidate_predictions,
                probabilities=method.probabilities,
                candidate_covariance_diagonals=method.candidate_covariance_diagonals,
                combined_covariance_diagonals=method.combined_covariance_diagonals,
                target_shape=reference.target_indices.shape,
                basin_id=basin_id,
                expected_candidate_ids=expected_candidate_ids[method_name],
            )
            arrays[f"{method_name}__predictions"] = method.predictions
            arrays[f"{method_name}__candidate_ids"] = np.asarray(method.candidate_ids, dtype="U128")
            arrays[f"{method_name}__candidate_predictions"] = method.candidate_predictions
            arrays[f"{method_name}__probabilities"] = method.probabilities
            if method.candidate_covariance_diagonals is not None:
                arrays[f"{method_name}__candidate_covariance_diagonals"] = method.candidate_covariance_diagonals
                arrays[f"{method_name}__combined_covariance_diagonals"] = method.combined_covariance_diagonals
        destination = self.temporary / "basins" / f"{basin_id}.npz"
        np.savez_compressed(destination, **arrays)
        if evaluation_input_audit is not None:
            audit = dict(evaluation_input_audit)
            if (
                audit.get("basin_id") != basin_id
                or audit.get("passed") is not True
                or audit.get("performed_after_verified_contract") is not True
                or audit.get("verified_contract_id") != self.contract_id
                or audit.get("verified_contract_checksums_sha256") != self.contract_checksums_sha256
            ):
                raise ValueError(f"basin {basin_id} evaluation input audit is invalid")
            _write_json(self.temporary / "evaluation_input_audits" / f"{basin_id}.json", audit)
            self.evaluation_audit_ids.append(basin_id)
        self.metric_rows.extend(_basin_metric_rows(result))
        self.basin_ids.append(basin_id)
        return destination

    def finalize(
        self,
        resource_history: Sequence[Mapping],
        source_files: Sequence[Path],
        repo_root: Path,
        input_files: Sequence[Path] = (),
        execution_signature: Mapping | None = None,
    ) -> Path:
        if not self.basin_ids:
            raise ValueError("cannot finalize an empty result package")
        if tuple(self.basin_ids) != self.expected_basin_ids:
            raise ValueError("result package does not contain every frozen contract basin in order")
        if execution_signature is not None and self.evaluation_audit_ids != self.basin_ids:
            raise ValueError("verified runs require one post-contract evaluation input audit per basin")
        metrics = pd.DataFrame(self.metric_rows)
        metrics.to_csv(self.temporary / "metrics.csv", index=False)
        cross_basin_summary = summarize_metrics(metrics)
        cross_basin_summary.to_csv(self.temporary / "cross_basin_summary.csv", index=False)
        _copy_contract_tables(self.contract_directory, self.temporary)
        from .reporting import write_result_diagnostics

        write_result_diagnostics(
            self.temporary,
            metrics,
            cross_basin_summary,
            self.basin_ids,
        )
        _write_json(self.temporary / "config_snapshot.json", self.config)
        _write_json(self.temporary / "resource_history.json", list(resource_history))
        contract_checksums_path = self.contract_directory / "checksums.json"
        _write_json(
            self.temporary / "contract_reference.json",
            {
                "contract_directory": Path(
                    os.path.relpath(self.contract_directory, start=self.output)
                ).as_posix(),
                "contract_id": self.contract_directory.name,
                "contract_checksums_sha256": sha256_file(contract_checksums_path),
            },
        )
        source_entries = _snapshot_files(
            self.temporary, Path(repo_root).resolve(), "source", source_files
        )
        input_entries = _snapshot_files(
            self.temporary, Path(repo_root).resolve(), "input", input_files
        )
        _write_json(
            self.temporary / "snapshot_manifest.json",
            {"source_files": source_entries, "input_files": input_entries},
        )
        if execution_signature is not None:
            _write_json(self.temporary / "execution_signature.json", execution_signature)
        _write_json(
            self.temporary / "result_manifest.json",
            {
                "artifact_type": "diagnostic_hindcast_result",
                "experiment_id": self.experiment_id,
                "contract_id": self.contract_directory.name,
                "basin_count": len(self.basin_ids),
                "basins": self.basin_ids,
                "evaluation_input_audit_count": len(self.evaluation_audit_ids),
                "methods": list(METHOD_ORDER),
                "future_meteorology": "observed hindsight meteorology; not an operational forecast",
                "has_verified_execution_signature": execution_signature is not None,
            },
        )
        _write_json(self.temporary / "checksums.json", _artifact_checksums(self.temporary))
        verify_result_package(self.temporary)
        os.replace(self.temporary, self.output)
        return self.output

    def preserve_failure(self, error: Exception) -> Path | None:
        if not self.temporary.exists():
            return None
        _write_json(
            self.temporary / "failure.json",
            {"status": "failed", "error_type": type(error).__name__, "message": str(error)},
        )
        failed = self.results_root / f"{self.experiment_id}.failed"
        if failed.exists():
            raise FileExistsError(f"failed result path already exists: {failed}")
        os.replace(self.temporary, failed)
        return failed


def _dataframe_values_equal(expected: pd.DataFrame, actual: pd.DataFrame, columns: Sequence[str]) -> bool:
    if len(expected) != len(actual):
        return False
    for column in columns:
        left = expected[column].to_numpy()
        right = actual[column].to_numpy()
        if np.issubdtype(left.dtype, np.number) and np.issubdtype(right.dtype, np.number):
            if not np.allclose(left.astype(float), right.astype(float), rtol=1e-11, atol=1e-12, equal_nan=True):
                return False
        elif not np.array_equal(left.astype(str), right.astype(str)):
            return False
    return True


def verify_result_package(result_directory: Path) -> dict:
    directory = Path(result_directory).resolve()
    if directory.name.endswith(".failed") or (directory / "failure.json").exists():
        raise ValueError("failed result artifact cannot be verified as successful")
    _verify_checksums(directory)
    _verify_snapshot_manifest(directory)
    manifest = json.loads((directory / "result_manifest.json").read_text(encoding="utf-8"))
    config = json.loads((directory / "config_snapshot.json").read_text(encoding="utf-8"))
    _verify_resource_history(directory, config, run_kind="evaluation")
    if (
        manifest.get("artifact_type") != "diagnostic_hindcast_result"
        or tuple(manifest.get("methods", [])) != METHOD_ORDER
    ):
        raise ValueError("result manifest is invalid")
    if manifest.get("has_verified_execution_signature"):
        signature = json.loads((directory / "execution_signature.json").read_text(encoding="utf-8"))
        if signature.get("verified_unchanged_from_start_to_finish") is not True:
            raise ValueError("result execution signature was not verified across the run")
        _verify_execution_signature_snapshot(directory, signature)
    contract_reference = json.loads((directory / "contract_reference.json").read_text(encoding="utf-8"))
    contract_reference_path = str(contract_reference["contract_directory"])
    if (
        Path(contract_reference_path).is_absolute()
        or bool(PureWindowsPath(contract_reference_path).anchor)
    ):
        raise ValueError("result contract reference must be a relocatable relative path")
    contract_directory = (directory / contract_reference_path).resolve()
    contract_verification = verify_contract_package(contract_directory)
    if sha256_file(contract_directory / "checksums.json") != contract_reference["contract_checksums_sha256"]:
        raise ValueError("referenced contract checksum changed")
    contract_manifest = json.loads((contract_directory / "contract_manifest.json").read_text(encoding="utf-8"))
    if (
        manifest.get("basins") != contract_manifest.get("basins")
        or manifest.get("basin_count") != contract_manifest.get("basin_count")
    ):
        raise ValueError("result basin list does not equal the frozen contract basin list")
    contract_checksums = json.loads((contract_directory / "checksums.json").read_text(encoding="utf-8"))
    copied_directory = directory / "contract_tables"
    copied_names = {
        path.relative_to(copied_directory).as_posix()
        for path in copied_directory.rglob("*")
        if path.is_file()
    }
    if copied_names != set(CONTRACT_TABLE_FILES):
        raise ValueError("result contract table set is incomplete or contains unexpected files")
    for name in CONTRACT_TABLE_FILES:
        if sha256_file(copied_directory / name) != contract_checksums.get(name):
            raise ValueError(f"result contract table does not equal the verified contract: {name}")
    loaded_metrics = pd.read_csv(directory / "metrics.csv", dtype={"basin_id": str})
    evaluation_audit_count = int(manifest.get("evaluation_input_audit_count", 0))
    if evaluation_audit_count not in {0, len(manifest["basins"])}:
        raise ValueError("result evaluation input audit count is invalid")
    if manifest.get("has_verified_execution_signature") and evaluation_audit_count != len(manifest["basins"]):
        raise ValueError("verified result lacks post-contract evaluation input audits")
    for basin_id in manifest["basins"][:evaluation_audit_count]:
        audit = json.loads(
            (directory / "evaluation_input_audits" / f"{basin_id}.json").read_text(encoding="utf-8")
        )
        if (
            audit.get("basin_id") != basin_id
            or audit.get("passed") is not True
            or audit.get("performed_after_verified_contract") is not True
            or audit.get("verified_contract_id") != contract_reference["contract_id"]
            or audit.get("verified_contract_checksums_sha256")
            != contract_reference["contract_checksums_sha256"]
        ):
            raise ValueError(f"basin {basin_id} evaluation input audit is invalid")
    recomputed_rows = []
    for basin_id in manifest["basins"]:
        basin_contract = json.loads(
            (contract_directory / "basin_contracts" / f"{basin_id}.json").read_text(encoding="utf-8")
        )
        expected_candidate_ids = _expected_candidate_ids(basin_contract)
        with np.load(directory / "basins" / f"{basin_id}.npz") as arrays:
            dates = arrays["dates"]
            observations = arrays["observations"]
            leads = arrays["lead_days"]
            origins = arrays["origin_indices"]
            targets = arrays["target_indices"]
            target_observations = arrays["target_observations"]
            if observations.shape != dates.shape or not np.all(np.isfinite(observations)):
                raise ValueError(f"basin {basin_id} observations are invalid")
            if tuple(leads.tolist()) != (1, 3, 7) or not np.array_equal(
                origins, np.arange(len(dates) - 7, dtype=np.int64)
            ):
                raise ValueError(f"basin {basin_id} lead or origin count is invalid")
            parsed_dates = pd.to_datetime(dates.astype(str), format="%Y-%m-%d", errors="raise")
            if not parsed_dates.equals(pd.date_range(parsed_dates[0], periods=len(parsed_dates), freq="D")):
                raise ValueError(f"basin {basin_id} dates are not one continuous daily series")
            if "evaluation_start" in config and "evaluation_end" in config:
                configured_dates = pd.date_range(config["evaluation_start"], config["evaluation_end"], freq="D")
                if not parsed_dates.equals(configured_dates):
                    raise ValueError(f"basin {basin_id} dates do not equal the frozen evaluation period")
            if not np.array_equal(targets, origins[:, None] + leads[None, :]):
                raise ValueError(f"basin {basin_id} target chronology is invalid")
            if not np.array_equal(arrays["origin_dates"], dates[origins]):
                raise ValueError(f"basin {basin_id} origin dates are misaligned")
            if not np.array_equal(arrays["target_dates"], dates[targets]):
                raise ValueError(f"basin {basin_id} target dates are misaligned")
            if not np.array_equal(target_observations, observations[targets]):
                raise ValueError(f"basin {basin_id} target observations are misaligned")
            fixed_predictions = arrays["fixed_filter__predictions"]
            for method in METHOD_ORDER:
                candidate_covariance_key = f"{method}__candidate_covariance_diagonals"
                combined_covariance_key = f"{method}__combined_covariance_diagonals"
                _validate_result_method_arrays(
                    method_name=method,
                    predictions=arrays[f"{method}__predictions"],
                    candidate_ids=arrays[f"{method}__candidate_ids"].tolist(),
                    candidate_predictions=arrays[f"{method}__candidate_predictions"],
                    probabilities=arrays[f"{method}__probabilities"],
                    candidate_covariance_diagonals=(
                        arrays[candidate_covariance_key] if candidate_covariance_key in arrays.files else None
                    ),
                    combined_covariance_diagonals=(
                        arrays[combined_covariance_key] if combined_covariance_key in arrays.files else None
                    ),
                    target_shape=targets.shape,
                    basin_id=basin_id,
                    expected_candidate_ids=expected_candidate_ids[method],
                )
            for lead_index, lead in enumerate(leads):
                fixed = calculate_metrics(target_observations[:, lead_index], fixed_predictions[:, lead_index])
                for method in METHOD_ORDER:
                    predictions = arrays[f"{method}__predictions"]
                    metrics = calculate_metrics(target_observations[:, lead_index], predictions[:, lead_index])
                    recomputed_rows.append(
                        {
                            "basin_id": basin_id,
                            "method": method,
                            "lead_days": int(lead),
                            "n_origins": len(origins),
                            **metrics,
                            "rmse_change_percent_vs_fixed_filter": 100.0
                            * (metrics["rmse"] - fixed["rmse"])
                            / fixed["rmse"],
                            "mae_change_percent_vs_fixed_filter": 100.0
                            * (metrics["mae"] - fixed["mae"])
                            / fixed["mae"],
                            "nse_change_vs_fixed_filter": metrics["nse"] - fixed["nse"],
                            "strict_rmse_win_vs_fixed_filter": bool(metrics["rmse"] < fixed["rmse"]),
                        }
                    )
    recomputed = pd.DataFrame(recomputed_rows)
    sort_columns = ["basin_id", "method", "lead_days"]
    loaded_sorted = loaded_metrics.sort_values(sort_columns).reset_index(drop=True)
    recomputed_sorted = recomputed.sort_values(sort_columns).reset_index(drop=True)
    if not _dataframe_values_equal(recomputed_sorted, loaded_sorted, list(recomputed_sorted.columns)):
        raise ValueError("saved metrics do not match independently recomputed values")
    loaded_summary = pd.read_csv(directory / "cross_basin_summary.csv")
    recomputed_summary = summarize_metrics(recomputed)
    summary_sort = ["method", "lead_days"]
    if not _dataframe_values_equal(
        recomputed_summary.sort_values(summary_sort).reset_index(drop=True),
        loaded_summary.sort_values(summary_sort).reset_index(drop=True),
        list(recomputed_summary.columns),
    ):
        raise ValueError("saved cross-basin summary does not match independently recomputed values")
    from .reporting import (
        _candidate_probability_tables,
        _lead_time_plot,
        build_study_report,
        paired_method_comparisons,
    )

    loaded_comparisons = pd.read_csv(directory / "paired_method_comparisons.csv")
    recomputed_comparisons = paired_method_comparisons(recomputed)
    comparison_sort = ["comparison_id", "lead_days"]
    if not _dataframe_values_equal(
        recomputed_comparisons.sort_values(comparison_sort).reset_index(drop=True),
        loaded_comparisons.sort_values(comparison_sort).reset_index(drop=True),
        list(recomputed_comparisons.columns),
    ):
        raise ValueError("saved paired method comparisons do not match recomputed values")
    recomputed_candidates, recomputed_factors = _candidate_probability_tables(
        directory, list(manifest["basins"])
    )
    loaded_candidates = pd.read_csv(
        directory / "candidate_probability_summary.csv", dtype={"basin_id": str}
    )
    loaded_factors = pd.read_csv(
        directory / "joint_factor_probability_summary.csv", dtype={"basin_id": str}
    )
    candidate_sort = ["basin_id", "method", "lead_days", "candidate_id"]
    factor_sort = ["basin_id", "lead_days", "factor_type", "factor_id"]
    if not _dataframe_values_equal(
        recomputed_candidates.sort_values(candidate_sort).reset_index(drop=True),
        loaded_candidates.sort_values(candidate_sort).reset_index(drop=True),
        list(recomputed_candidates.columns),
    ):
        raise ValueError("saved candidate probability summary does not match recomputed values")
    if not _dataframe_values_equal(
        recomputed_factors.sort_values(factor_sort).reset_index(drop=True),
        loaded_factors.sort_values(factor_sort).reset_index(drop=True),
        list(recomputed_factors.columns),
    ):
        raise ValueError("saved joint-factor probability summary does not match recomputed values")
    figure_path = directory / "lead_time_effects.png"
    try:
        from PIL import Image

        with Image.open(figure_path) as figure:
            figure_format = figure.format
            figure_size = figure.size
            figure.verify()
    except Exception as error:
        raise ValueError("lead-time figure is not a valid image") from error
    if figure_format != "PNG" or figure_size[0] < 1000 or figure_size[1] < 500:
        raise ValueError("lead-time figure has the wrong format or insufficient resolution")
    with tempfile.TemporaryDirectory(prefix="verify-lead-time-figure-") as temporary_figure_directory:
        expected_figure_path = Path(temporary_figure_directory) / "expected.png"
        _lead_time_plot(recomputed_comparisons, expected_figure_path)
        with Image.open(figure_path) as actual_figure, Image.open(expected_figure_path) as expected_figure:
            actual_pixels = np.asarray(actual_figure.convert("RGBA"))
            expected_pixels = np.asarray(expected_figure.convert("RGBA"))
    if not np.array_equal(actual_pixels, expected_pixels):
        raise ValueError("lead-time figure does not match the recomputed paired comparisons")
    expected_report = build_study_report(recomputed_comparisons, recomputed_summary, recomputed)
    actual_report = (directory / "study_report.md").read_text(encoding="utf-8")
    if actual_report != expected_report:
        raise ValueError("study report does not match independently recomputed results")
    return {
        "status": "verified",
        "experiment_id": manifest["experiment_id"],
        "basin_count": len(manifest["basins"]),
        "method_count": len(METHOD_ORDER),
        "lead_days": [1, 3, 7],
        "contract_id": contract_verification["contract_id"],
    }

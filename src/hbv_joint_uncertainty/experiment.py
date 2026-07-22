"""Immutable experiment artifacts and independent verification."""

from __future__ import annotations

import json
import os
import re
import shutil
from dataclasses import asdict
from datetime import datetime
from pathlib import Path
from typing import Mapping, Sequence

import numpy as np
import pandas as pd

from .candidates import sha256_file
from .hbv_adapter import PARAMETER_NAMES, V1_PARAMETER_BOUNDS
from .preflight import BasinPreflightResult, build_transition_matrix


FROZEN_PREFLIGHT_CONFIG_SHA256 = "8e423312822c86138590bef118e4accf1519271b4ed534333ffb1ff3e8e2f538"


def calculate_metrics(observations, predictions) -> dict[str, float]:
    observed = np.asarray(observations, dtype=np.float64)
    predicted = np.asarray(predictions, dtype=np.float64)
    if observed.ndim != 1 or observed.shape != predicted.shape or len(observed) == 0:
        raise ValueError("observations and predictions must be nonempty one-dimensional arrays with equal shape")
    if not np.all(np.isfinite(observed)) or not np.all(np.isfinite(predicted)):
        raise ValueError("metric inputs must contain only finite values")
    residual = predicted - observed
    denominator = float(np.sum((observed - np.mean(observed))**2))
    if denominator <= 0.0:
        raise ValueError("Nash-Sutcliffe efficiency requires nonconstant observations")
    return {
        "rmse": float(np.sqrt(np.mean(residual**2))),
        "mae": float(np.mean(np.abs(residual))),
        "nse": float(1.0 - np.sum(residual**2) / denominator),
    }


def _json_ready(value):
    if isinstance(value, Mapping):
        return {str(key): _json_ready(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [_json_ready(item) for item in value]
    if isinstance(value, Path):
        return str(value)
    if isinstance(value, np.generic):
        return value.item()
    return value


def _write_json(path: Path, value) -> None:
    path.write_text(
        json.dumps(_json_ready(value), indent=2, sort_keys=True, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


def _resolve_root(repo_root: Path, configured: str) -> Path:
    path = Path(configured)
    return path if path.is_absolute() else repo_root / path


def _validate_experiment_id(experiment_id: str) -> str:
    value = str(experiment_id)
    if re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,127}", value) is None:
        raise ValueError("experiment_id must use 1-128 letters, digits, dots, underscores, or hyphens")
    return value


def _validate_basin_result(result: BasinPreflightResult) -> None:
    n_days = len(result.observations)
    n_candidates = len(result.definitions)
    assimilation = result.assimilation
    if len(result.dates) != n_days or n_days == 0:
        raise ValueError(f"basin {result.basin_id} dates and observations must have equal nonzero length")
    expected_shapes = {
        "prior_discharge": (n_days,),
        "candidate_prior_discharge": (n_days, n_candidates),
        "prior_probabilities": (n_days, n_candidates),
        "posterior_probabilities": (n_days, n_candidates),
        "combined_states": (n_days, 15),
    }
    for name, shape in expected_shapes.items():
        values = np.asarray(getattr(assimilation, name))
        if values.shape != shape or not np.all(np.isfinite(values)):
            raise ValueError(f"basin {result.basin_id} {name} must be finite with shape {shape}")
    probabilities = assimilation.posterior_probabilities
    if np.any(probabilities < 0.0) or np.max(np.abs(probabilities.sum(axis=1) - 1.0)) > 1e-12:
        raise ValueError(f"basin {result.basin_id} posterior probabilities are invalid")
    if np.any(assimilation.combined_states < 0.0):
        raise ValueError(f"basin {result.basin_id} combined states contain negative values")
    prior_probabilities = assimilation.prior_probabilities
    reconstructed = np.sum(prior_probabilities * assimilation.candidate_prior_discharge, axis=1)
    if (
        np.any(prior_probabilities < 0.0)
        or np.max(np.abs(prior_probabilities.sum(axis=1) - 1.0)) > 1e-12
        or not np.allclose(assimilation.prior_discharge, reconstructed, rtol=1e-12, atol=1e-12)
    ):
        raise ValueError(f"basin {result.basin_id} forecast-before-update arrays are inconsistent")


def _artifact_checksums(directory: Path) -> dict[str, str]:
    return {
        path.relative_to(directory).as_posix(): sha256_file(path)
        for path in sorted(directory.rglob("*"))
        if path.is_file() and path.name != "checksums.json"
    }


def write_experiment(
    repo_root: Path,
    experiment_id: str,
    config: Mapping,
    basin_results: Sequence[BasinPreflightResult],
    resource_history: Sequence[Mapping],
    provenance: Mapping,
    source_files: Sequence[Path] = (),
    input_files: Sequence[Path] = (),
    expected_snapshot_hashes: Mapping[str, str] | None = None,
) -> Path:
    """Write one non-overwriting experiment directory, log, and registry row."""
    root = Path(repo_root).resolve()
    identifier = _validate_experiment_id(experiment_id)
    results = tuple(basin_results)
    if not results:
        raise ValueError("basin_results must be nonempty")
    if len({result.basin_id for result in results}) != len(results):
        raise ValueError("basin_results must have unique basin identifiers")
    for result in results:
        _validate_basin_result(result)

    results_root = _resolve_root(root, str(config["results_root"])).resolve()
    logs_root = _resolve_root(root, str(config["logs_root"])).resolve()
    output = results_root / identifier
    temporary_output = results_root / f".{identifier}.incomplete"
    log_output = logs_root / identifier
    temporary_log = logs_root / f".{identifier}.incomplete"
    registry_path = results_root / "experiment_registry.csv"
    temporary_registry = results_root / f".experiment_registry.{identifier}.incomplete.csv"
    for path in (output, temporary_output, log_output, temporary_log, temporary_registry):
        if path.exists():
            raise FileExistsError(f"refusing to overwrite existing experiment path: {path}")
    if registry_path.exists():
        registry = pd.read_csv(registry_path, dtype={"experiment_id": str})
        if identifier in set(registry["experiment_id"]):
            raise FileExistsError(f"experiment identifier is already registered: {identifier}")
    else:
        registry = pd.DataFrame()

    results_root.mkdir(parents=True, exist_ok=True)
    logs_root.mkdir(parents=True, exist_ok=True)
    created_at = datetime.now().astimezone().isoformat()
    temporary_output.mkdir()
    temporary_log.mkdir()
    try:
        (temporary_output / "basins").mkdir()
        reproducibility_manifest = {"source_files": [], "input_files": []}
        expected_hashes = dict(expected_snapshot_hashes or {})
        for category, paths in (("source", source_files), ("input", input_files)):
            snapshot_root = temporary_output / f"{category}_snapshot"
            for supplied_path in paths:
                path = Path(supplied_path).resolve()
                try:
                    relative = path.relative_to(root)
                except ValueError as error:
                    raise ValueError(f"{category} snapshot file is outside repo_root: {path}") from error
                if not path.is_file():
                    raise ValueError(f"{category} snapshot file is missing: {path}")
                current_hash = sha256_file(path)
                relative_key = relative.as_posix()
                if relative_key in expected_hashes and expected_hashes[relative_key] != current_hash:
                    raise ValueError(f"{category} snapshot file changed during execution: {relative_key}")
                entry_index = len(reproducibility_manifest[f"{category}_files"])
                destination = snapshot_root / f"{entry_index:03d}_{path.name}"
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(path, destination)
                reproducibility_manifest[f"{category}_files"].append(
                    {
                        "original_path": relative_key,
                        "snapshot_path": destination.relative_to(temporary_output).as_posix(),
                        "sha256": current_hash,
                    }
                )
        _write_json(temporary_output / "reproducibility_manifest.json", reproducibility_manifest)
        snapshot = dict(config)
        snapshot["experiment_id"] = identifier
        execution = dict(snapshot.get("execution", {}))
        execution["selected_basins"] = [result.basin_id for result in results]
        execution["actual_evaluation_windows"] = {
            result.basin_id: {
                "start": str(result.dates[0]),
                "end": str(result.dates[-1]),
                "n_days": len(result.dates),
            }
            for result in results
        }
        snapshot["execution"] = execution
        _write_json(temporary_output / "config_snapshot.json", snapshot)
        _write_json(temporary_output / "resource_history.json", list(resource_history))
        _write_json(
            temporary_output / "manifest.json",
            {
                "experiment_id": identifier,
                "experiment_family": config.get("experiment_family"),
                "created_at": created_at,
                "basin_count": len(results),
                "provenance": provenance,
                "log_path": str(log_output / "run.log"),
            },
        )

        metric_rows = []
        candidate_rows = []
        warmup_rows = []
        for result in results:
            assimilation = result.assimilation
            candidate_ids = np.array([definition.candidate_id for definition in result.definitions])
            np.savez_compressed(
                temporary_output / "basins" / f"{result.basin_id}.npz",
                dates=np.asarray(result.dates, dtype="U10"),
                observations=np.asarray(result.observations, dtype=np.float64),
                prior_discharge=assimilation.prior_discharge,
                candidate_prior_discharge=assimilation.candidate_prior_discharge,
                prior_probabilities=assimilation.prior_probabilities,
                posterior_probabilities=assimilation.posterior_probabilities,
                combined_states=assimilation.combined_states,
                candidate_ids=candidate_ids,
            )
            metric_rows.append(
                {
                    "basin_id": result.basin_id,
                    "n_days": len(result.observations),
                    **calculate_metrics(result.observations, assimilation.prior_discharge),
                }
            )
            for definition in result.definitions:
                candidate_rows.append(
                    {
                        "basin_id": result.basin_id,
                        "candidate_id": definition.candidate_id,
                        "parameter_id": definition.parameter_id,
                        "noise_variance_scale": definition.noise_variance_scale,
                        **{f"p_{key}": value for key, value in definition.parameters.items()},
                    }
                )
            for audit in result.warmup_audits:
                warmup_rows.append({"basin_id": result.basin_id, **asdict(audit)})

        pd.DataFrame(metric_rows).to_csv(temporary_output / "metrics.csv", index=False)
        pd.DataFrame(candidate_rows).to_csv(temporary_output / "candidates.csv", index=False)
        pd.DataFrame(warmup_rows).to_csv(temporary_output / "warmup_equivalence.csv", index=False)
        _write_json(temporary_output / "checksums.json", _artifact_checksums(temporary_output))
        (temporary_log / "run.log").write_text(
            f"{created_at} experiment_id={identifier} status=complete basin_count={len(results)}\n",
            encoding="utf-8",
        )
        registry_row = pd.DataFrame(
            [
                {
                    "experiment_id": identifier,
                    "experiment_family": config.get("experiment_family"),
                    "created_at": created_at,
                    "output_dir": str(output),
                    "basin_count": len(results),
                    "status": "verified",
                }
            ]
        )
        pd.concat([registry, registry_row], ignore_index=True).to_csv(temporary_registry, index=False)
        os.replace(temporary_output, output)
        os.replace(temporary_log, log_output)
        verify_experiment(output)
        os.replace(temporary_registry, registry_path)
    except Exception:
        for path in (temporary_output, temporary_log):
            if path.exists() and path.parent in (results_root, logs_root):
                shutil.rmtree(path)
        if temporary_registry.exists() and temporary_registry.parent == results_root:
            temporary_registry.unlink()
        for path in (output, log_output):
            if path.exists() and path.parent in (results_root, logs_root):
                shutil.rmtree(path)
        raise
    return output


def verify_experiment(output_dir: Path) -> dict:
    """Recompute hashes, metrics, state constraints, and probability constraints."""
    output = Path(output_dir).resolve()
    checksums_path = output / "checksums.json"
    if not checksums_path.is_file():
        raise ValueError("checksums.json is missing")
    recorded_checksums = json.loads(checksums_path.read_text(encoding="utf-8"))
    actual_checksums = _artifact_checksums(output)
    if recorded_checksums != actual_checksums:
        differing = sorted(set(recorded_checksums) | set(actual_checksums))
        differing = [key for key in differing if recorded_checksums.get(key) != actual_checksums.get(key)]
        raise ValueError(f"artifact checksum verification failed: {differing}")

    metrics = pd.read_csv(output / "metrics.csv", dtype={"basin_id": str})
    basin_files = sorted((output / "basins").glob("*.npz"))
    if len(metrics) != len(basin_files) or len(basin_files) == 0:
        raise ValueError("metrics rows and basin artifact count must match and be nonzero")
    basin_ids = [path.stem for path in basin_files]
    config_snapshot = json.loads((output / "config_snapshot.json").read_text(encoding="utf-8"))
    reproducibility_manifest = json.loads(
        (output / "reproducibility_manifest.json").read_text(encoding="utf-8")
    )
    for category in ("source", "input"):
        entries = reproducibility_manifest.get(f"{category}_files")
        if not isinstance(entries, list):
            raise ValueError(f"reproducibility manifest is missing {category} files")
        original_paths = []
        for entry in entries:
            if set(entry) != {"original_path", "snapshot_path", "sha256"}:
                raise ValueError(f"reproducibility manifest has an invalid {category} entry")
            snapshot_path = (output / entry["snapshot_path"]).resolve()
            expected_root = (output / f"{category}_snapshot").resolve()
            if not snapshot_path.is_relative_to(expected_root) or not snapshot_path.is_file():
                raise ValueError(f"reproducibility manifest {category} snapshot path is invalid")
            if sha256_file(snapshot_path) != entry["sha256"]:
                raise ValueError(f"reproducibility manifest {category} snapshot hash failed")
            original_paths.append(entry["original_path"])
        if len(original_paths) != len(set(original_paths)):
            raise ValueError(f"reproducibility manifest contains duplicate {category} paths")

    frozen_config_entries = [
        entry
        for entry in reproducibility_manifest["source_files"]
        if entry["original_path"] == "src/hbv_joint_uncertainty/configs/preflight_v01.json"
    ]
    frozen_config_path = (
        output / frozen_config_entries[0]["snapshot_path"]
        if len(frozen_config_entries) == 1
        else output / "missing_frozen_config.json"
    )
    official_package = (
        config_snapshot.get("experiment_family") == "2026-07-14-hbv-joint-uncertainty-preflight-v1"
        or frozen_config_path.is_file()
    )
    if official_package:
        if not frozen_config_path.is_file():
            raise ValueError("official reproducibility package is missing the frozen configuration source")
        if sha256_file(frozen_config_path) != FROZEN_PREFLIGHT_CONFIG_SHA256:
            raise ValueError("official frozen configuration source hash is not recognized")
        frozen_config = json.loads(frozen_config_path.read_text(encoding="utf-8"))
        for key, expected_value in frozen_config.items():
            if config_snapshot.get(key) != expected_value:
                raise ValueError(f"official frozen configuration mismatch for key {key!r}")
    execution = config_snapshot.get("execution", {})
    selected_basins = [str(value).zfill(8) for value in execution.get("selected_basins", [])]
    actual_windows = execution.get("actual_evaluation_windows", {})
    if (
        len(selected_basins) != len(set(selected_basins))
        or set(selected_basins) != set(basin_ids)
        or set(actual_windows) != set(basin_ids)
    ):
        raise ValueError("execution snapshot does not match basin artifacts")
    if official_package:
        source_paths = {
            entry["original_path"] for entry in reproducibility_manifest["source_files"]
        }
        required_sources = {
            "src/hbv_joint_uncertainty/preflight.py",
            "src/hbv_joint_uncertainty/experiment.py",
            "src/hbv_joint_uncertainty/orchestrator.py",
            "src/hbv_joint_uncertainty/scripts/run_preflight.py",
            "src/hbv_joint_uncertainty/configs/preflight_v01.json",
            "src/hbv_joint_uncertainty/configs/preflight_v01_basins.csv",
            "src/scl_hydro/hbv_lite_numpy.py",
            "src/hydroagent/data_loading.py",
            "test/test_hbv_joint_uncertainty_experiment.py",
        }
        if not required_sources <= source_paths:
            raise ValueError("official reproducibility package is missing required source snapshots")
        input_paths = {entry["original_path"] for entry in reproducibility_manifest["input_files"]}
        if len(input_paths) != 2 * len(basin_ids) + 3:
            raise ValueError("official reproducibility package has an incomplete input snapshot")
        for basin_id in basin_ids:
            if sum(basin_id in path for path in input_paths) != 2:
                raise ValueError(f"official input snapshot is incomplete for basin {basin_id}")
        required_inputs = {
            "data/camels_us/camels_attributes_v2.0/camels_topo.txt",
            config_snapshot["parameter_source"]["table_path"],
            config_snapshot["parameter_source"]["metadata_path"],
        }
        if not required_inputs <= input_paths:
            raise ValueError("official reproducibility package is missing trained or area inputs")
        current_repo_root = Path(__file__).resolve().parents[2]
        for category in ("source", "input"):
            for entry in reproducibility_manifest[f"{category}_files"]:
                current_path = current_repo_root / entry["original_path"]
                if not current_path.is_file() or sha256_file(current_path) != entry["sha256"]:
                    raise ValueError(
                        f"official {category} snapshot does not match the external workspace anchor: "
                        f"{entry['original_path']}"
                    )
    manifest = json.loads((output / "manifest.json").read_text(encoding="utf-8"))
    if (
        int(manifest.get("basin_count", -1)) != len(basin_ids)
        or manifest.get("experiment_id") != config_snapshot.get("experiment_id")
        or manifest.get("experiment_family") != config_snapshot.get("experiment_family")
    ):
        raise ValueError("execution snapshot manifest basin count is inconsistent")
    candidate_table = pd.read_csv(output / "candidates.csv", dtype={"basin_id": str, "candidate_id": str})
    if official_package:
        input_entries = {
            entry["original_path"]: entry for entry in reproducibility_manifest["input_files"]
        }
        source = config_snapshot["parameter_source"]
        if (
            input_entries[source["table_path"]]["sha256"] != source["table_sha256"]
            or input_entries[source["metadata_path"]]["sha256"] != source["metadata_sha256"]
        ):
            raise ValueError("trained parameter source snapshot hash does not match frozen configuration")
        trained_table = pd.read_csv(
            output / input_entries[source["table_path"]]["snapshot_path"], dtype={"basin_id": str}
        )
    warmup_table = pd.read_csv(
        output / "warmup_equivalence.csv", dtype={"basin_id": str, "parameter_id": str}
    )
    required_warmup_columns = {
        "basin_id",
        "parameter_id",
        "maximum_discharge_error",
        "maximum_final_store_error",
        "maximum_saved_state_error",
    }
    if not required_warmup_columns <= set(warmup_table.columns):
        raise ValueError("warmup equivalence table is missing required columns")
    for basin_id in basin_ids:
        rows = warmup_table.loc[warmup_table["basin_id"].str.zfill(8) == basin_id]
        if len(rows) == 0:
            raise ValueError(f"warmup equivalence is missing for basin {basin_id}")
        core_errors = rows[["maximum_discharge_error", "maximum_final_store_error"]].to_numpy(
            dtype=np.float64
        )
        center_rows = rows.loc[rows["parameter_id"] == "trained_center"]
        if (
            not np.all(np.isfinite(core_errors))
            or np.any(core_errors < 0.0)
            or np.max(core_errors) > 1e-8
            or len(center_rows) != 1
            or not np.isfinite(float(center_rows.iloc[0]["maximum_saved_state_error"]))
            or float(center_rows.iloc[0]["maximum_saved_state_error"]) < 0.0
            or float(center_rows.iloc[0]["maximum_saved_state_error"]) > 1e-8
        ):
            raise ValueError(f"warmup equivalence threshold failed for basin {basin_id}")
        if "parameter_source" in config_snapshot and set(rows["parameter_id"]) != {
            "toward_lower_10pct",
            "trained_center",
            "toward_upper_10pct",
        }:
            raise ValueError(f"warmup equivalence parameter rows are incomplete for basin {basin_id}")
    resource_config = config_snapshot.get("resource")
    if resource_config is not None:
        resource_history = json.loads((output / "resource_history.json").read_text(encoding="utf-8"))
        required_resource_fields = {
            "event",
            "timestamp",
            "available_memory_fraction",
            "available_memory_gib",
            "process_rss_gib",
            "process_peak_working_set_gib",
            "cpu_load_percent",
            "logical_processors",
            "disk_free_gib",
            "gpu_name",
            "gpu_memory_total_mib",
            "gpu_memory_free_mib",
            "gpu_utilization_percent",
        }
        if not resource_history or any(
            not required_resource_fields <= set(snapshot) for snapshot in resource_history
        ):
            raise ValueError("resource history is missing required snapshots or fields")
        output_gib = sum(path.stat().st_size for path in output.rglob("*") if path.is_file()) / 1024.0**3
        minimum_disk = max(
            float(resource_config["minimum_free_disk_gib"]),
            float(resource_config["minimum_output_space_multiplier"]) * output_gib,
        )
        parsed_resource_times = []
        for snapshot in resource_history:
            timestamp = pd.Timestamp(snapshot["timestamp"])
            numeric = np.asarray(
                [
                    snapshot["available_memory_fraction"],
                    snapshot["available_memory_gib"],
                    snapshot["process_rss_gib"],
                    snapshot["cpu_load_percent"],
                    snapshot["logical_processors"],
                    snapshot["disk_free_gib"],
                ],
                dtype=np.float64,
            )
            if pd.isna(timestamp) or not np.all(np.isfinite(numeric)):
                raise ValueError("resource history contains invalid timestamps or numeric values")
            parsed_resource_times.append(timestamp)
            if float(snapshot["available_memory_fraction"]) < float(
                resource_config["minimum_available_fraction_of_total"]
            ):
                raise ValueError("resource history violates the minimum available-memory fraction")
            observed_peak = snapshot["process_peak_working_set_gib"]
            if observed_peak is None:
                observed_peak = snapshot["process_rss_gib"]
            if (
                not np.isfinite(float(observed_peak))
                or float(observed_peak)
                > float(resource_config["maximum_peak_fraction_of_available"])
                * float(snapshot["available_memory_gib"])
            ):
                raise ValueError("resource history violates the process peak-memory limit")
            if float(snapshot["disk_free_gib"]) < minimum_disk:
                raise ValueError("resource history violates the free-disk limit")
            if int(snapshot["logical_processors"]) <= int(resource_config["reserved_logical_processors"]):
                raise ValueError("resource history does not preserve one usable logical processor")
            if not 0.0 <= float(snapshot["cpu_load_percent"]) <= 100.0:
                raise ValueError("resource history contains an invalid processor load")
        if parsed_resource_times != sorted(parsed_resource_times):
            raise ValueError("resource history timestamps are not monotonic")
        events = [snapshot["event"] for snapshot in resource_history]
        if events.count("before_experiment") != 1 or events.count("after_experiment") != 1:
            raise ValueError("resource history must contain one before and one after snapshot")
        interval = float(resource_config["monitor_interval_seconds"])
        for basin_id in basin_ids:
            monitor_rows = [
                snapshot
                for snapshot in resource_history
                if snapshot["event"] == "assimilation_monitor"
                and str(snapshot.get("basin_id", "")).zfill(8) == basin_id
            ]
            expected_days = int(actual_windows[basin_id]["n_days"])
            if (
                len(monitor_rows) < 2
                or int(monitor_rows[0].get("completed_days", -1)) != 0
                or int(monitor_rows[-1].get("completed_days", -1)) != expected_days
                or any(int(row.get("total_days", -1)) != expected_days for row in monitor_rows)
            ):
                raise ValueError(f"resource history does not bracket assimilation for basin {basin_id}")
            monitor_times = [pd.Timestamp(row["timestamp"]) for row in monitor_rows]
            gaps = [
                (later - earlier).total_seconds()
                for earlier, later in zip(monitor_times[:-1], monitor_times[1:])
            ]
            if any(gap > interval + 5.0 for gap in gaps):
                raise ValueError(f"resource history exceeds the monitoring interval for basin {basin_id}")
    maximum_probability_error = 0.0
    for basin_path in basin_files:
        basin_id = basin_path.stem
        rows = metrics.loc[metrics["basin_id"].str.zfill(8) == basin_id]
        if len(rows) != 1:
            raise ValueError(f"expected one metric row for basin {basin_id}")
        with np.load(basin_path, allow_pickle=False) as artifact:
            required_arrays = {
                "dates",
                "observations",
                "prior_discharge",
                "candidate_prior_discharge",
                "prior_probabilities",
                "posterior_probabilities",
                "combined_states",
                "candidate_ids",
            }
            if set(artifact.files) != required_arrays:
                raise ValueError(f"basin {basin_id} artifact structure has unexpected arrays")
            dates = artifact["dates"]
            observations = artifact["observations"]
            predictions = artifact["prior_discharge"]
            probabilities = artifact["posterior_probabilities"]
            prior_probabilities = artifact["prior_probabilities"]
            states = artifact["combined_states"]
            candidate_discharge = artifact["candidate_prior_discharge"]
            candidate_ids = artifact["candidate_ids"]
            n_days = len(observations) if observations.ndim == 1 else -1
            n_candidates = len(candidate_ids) if candidate_ids.ndim == 1 else -1
            valid_structure = (
                n_days > 0
                and n_candidates > 0
                and dates.shape == (n_days,)
                and predictions.shape == (n_days,)
                and candidate_discharge.shape == (n_days, n_candidates)
                and prior_probabilities.shape == (n_days, n_candidates)
                and probabilities.shape == (n_days, n_candidates)
                and states.shape == (n_days, 15)
                and len(set(candidate_ids.tolist())) == n_candidates
            )
            if not valid_structure:
                raise ValueError(f"basin {basin_id} artifact structure has inconsistent dimensions")
            parsed_dates = pd.to_datetime(dates, errors="coerce")
            expected_dates = pd.date_range(parsed_dates[0], periods=n_days, freq="D")
            if parsed_dates.isna().any() or not parsed_dates.equals(expected_dates):
                raise ValueError(f"basin {basin_id} artifact structure has invalid daily dates")
            window = actual_windows[basin_id]
            expected_window = {
                "start": str(dates[0]),
                "end": str(dates[-1]),
                "n_days": n_days,
            }
            if window != expected_window:
                raise ValueError(f"execution snapshot window does not match basin {basin_id}")
            table_candidate_ids = candidate_table.loc[
                candidate_table["basin_id"].str.zfill(8) == basin_id, "candidate_id"
            ].tolist()
            if table_candidate_ids != candidate_ids.tolist():
                raise ValueError(f"candidate correspondence failed for basin {basin_id}")
            if official_package:
                candidate_rows = candidate_table.loc[
                    candidate_table["basin_id"].str.zfill(8) == basin_id
                ]
                expected_parameter_ids = {
                    "toward_lower_10pct",
                    "trained_center",
                    "toward_upper_10pct",
                }
                expected_noise_scales = set(float(value) for value in config_snapshot["noise_variance_scales"])
                observed_pairs = set(
                    zip(
                        candidate_rows["parameter_id"],
                        candidate_rows["noise_variance_scale"].astype(float),
                    )
                )
                expected_pairs = {
                    (parameter_id, noise_scale)
                    for parameter_id in expected_parameter_ids
                    for noise_scale in expected_noise_scales
                }
                if len(candidate_rows) != 9 or observed_pairs != expected_pairs:
                    raise ValueError(f"candidate bank contract failed for basin {basin_id}")
                vectors = {}
                for parameter_id in expected_parameter_ids:
                    rows_for_vector = candidate_rows.loc[candidate_rows["parameter_id"] == parameter_id]
                    vector = rows_for_vector.iloc[0]
                    if any(
                        not np.allclose(
                            rows_for_vector[f"p_{name}"].astype(float),
                            float(vector[f"p_{name}"]),
                            rtol=0.0,
                            atol=0.0,
                        )
                        for name in PARAMETER_NAMES
                    ):
                        raise ValueError(f"candidate parameter vector varies across noise levels for basin {basin_id}")
                    vectors[parameter_id] = {name: float(vector[f"p_{name}"]) for name in PARAMETER_NAMES}
                trained_row = trained_table.loc[trained_table["basin_id"].str.zfill(8) == basin_id]
                if len(trained_row) != 1:
                    raise ValueError(f"trained center source row is missing for basin {basin_id}")
                for name in PARAMETER_NAMES:
                    lower, upper = V1_PARAMETER_BOUNDS[name]
                    center = float(trained_row.iloc[0][f"p_{name}"])
                    expected_lower = center - 0.1 * (center - lower)
                    expected_upper = center + 0.1 * (upper - center)
                    if (
                        abs(vectors["trained_center"][name] - center) > 1e-12
                        or abs(vectors["toward_lower_10pct"][name] - expected_lower) > 1e-12
                        or abs(vectors["toward_upper_10pct"][name] - expected_upper) > 1e-12
                    ):
                        raise ValueError(f"candidate parameter stress contract failed for basin {basin_id}")
            if not all(
                np.all(np.isfinite(values))
                for values in (
                    observations,
                    predictions,
                    prior_probabilities,
                    probabilities,
                    states,
                    candidate_discharge,
                )
            ):
                raise ValueError(f"basin {basin_id} contains non-finite arrays")
            if np.any(probabilities < 0.0) or np.any(states < 0.0):
                raise ValueError(f"basin {basin_id} contains negative probability or state values")
            prior_probability_error = float(np.max(np.abs(prior_probabilities.sum(axis=1) - 1.0)))
            reconstructed_prior = np.sum(prior_probabilities * candidate_discharge, axis=1)
            if (
                np.any(prior_probabilities < 0.0)
                or prior_probability_error > 1e-12
                or not np.allclose(predictions, reconstructed_prior, rtol=1e-12, atol=1e-12)
            ):
                raise ValueError(f"forecast-before-update verification failed for basin {basin_id}")
            if "transition_diagonal" in config_snapshot:
                transition_matrix = build_transition_matrix(
                    n_candidates, float(config_snapshot["transition_diagonal"])
                )
                uniform = np.full(n_candidates, 1.0 / n_candidates, dtype=np.float64)
                expected_prior_probabilities = np.empty_like(prior_probabilities)
                expected_prior_probabilities[0] = transition_matrix.T @ uniform
                expected_prior_probabilities[1:] = probabilities[:-1] @ transition_matrix
                if not np.allclose(
                    prior_probabilities,
                    expected_prior_probabilities,
                    rtol=0.0,
                    atol=1e-12,
                ):
                    raise ValueError(f"prior probability chronology failed for basin {basin_id}")
            probability_error = float(np.max(np.abs(probabilities.sum(axis=1) - 1.0)))
            maximum_probability_error = max(maximum_probability_error, probability_error)
            if probability_error > 1e-12:
                raise ValueError(f"basin {basin_id} probability sum error exceeds 1e-12")
            recomputed = calculate_metrics(observations, predictions)
        row = rows.iloc[0]
        if int(row["n_days"]) != len(observations) or any(
            not np.isclose(float(row[name]), value, rtol=1e-12, atol=1e-12)
            for name, value in recomputed.items()
        ):
            raise ValueError(f"metric recomputation failed for basin {basin_id}")
    return {
        "verified": True,
        "basin_count": len(basin_files),
        "maximum_probability_sum_error": maximum_probability_error,
        "verified_file_count": len(actual_checksums),
    }

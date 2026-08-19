"""Build the frozen preparation artifacts for the 03B Design90 C/P study.

The command creates configuration and evidence only.  It never invokes the
360-task runner or the independent result verifier.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import sys
from collections.abc import Mapping, Sequence
from pathlib import Path
from types import SimpleNamespace

import numpy as np
import pandas as pd

from camels_switch_confirmation import run_parameter_path_design90 as design_runner
from camels_switch_confirmation import run_parameter_path_mechanism as mechanism_runner
from camels_switch_confirmation import verify_parameter_path_design90 as design_verifier
from camels_switch_confirmation.bank import build_bank
from camels_switch_confirmation.g1_precheck import PARAM_KEYS, STATE_NAMES
from camels_switch_confirmation.g2_switch_confirmation import _build_bank
from hbv_joint_uncertainty.hbv_adapter import STATE_NAMES as FULL_STATE_NAMES
from scl_hydro.hbv_lite_numpy import resolve_hbv_bounds


_REPO_ROOT = Path(__file__).resolve().parents[2]

MECHANISM_ROOT = Path(
    "results/23_camels_switch_confirmation/"
    "camels_parfc_transition_path_03b_mechanism10_s01_20260811_local"
)
SOURCE_DESIGN90_ROOT = Path(
    "results/23_camels_switch_confirmation/"
    "camels_parfc_state_interaction_01b_design90_s01_20260810_local"
)
HISTORICAL_STOPPED_RUNS = {
    "version_03": {
        "root": Path(
            "results/23_camels_switch_confirmation/"
            "camels_parfc_transition_path_03_mechanism10_s01_20260810_local"
        ),
        "count": 13,
        "bytes": 895677,
        "sha256": "495184901b82fb3ce8dad8d8b490b4831f599142ea9dbcf93429ee07f780b85b",
    },
    "version_03a": {
        "root": Path(
            "results/23_camels_switch_confirmation/"
            "camels_parfc_transition_path_03a_mechanism10_s01_20260810_local"
        ),
        "count": 13,
        "bytes": 896011,
        "sha256": "bfcfc14f178369e46d1cb934191b91d16f548465ec931690b525a91b93e01309",
    },
}
MECHANISM_CONFIG = Path(
    "src/camels_switch_confirmation/configs/"
    "camels_parfc_transition_path_03b_mechanism10.json"
)
MECHANISM_EVIDENCE = Path(
    "docs/plans/2026-08-11-camels-parfc-transition-path-"
    "mechanism10-03b-evidence-v01.json"
)
BASIN_LIST = Path(
    "docs/plans/2026-08-10-camels-parfc-state-interaction-"
    "design90-basins-v01.csv"
)
COVERAGE_TABLE = Path(
    "docs/plans/2026-08-10-camels-parfc-state-interaction-"
    "design90-coverage-v01.csv"
)
RAW_INPUT_MANIFEST = Path(
    "docs/plans/2026-08-10-camels-parfc-state-interaction-"
    "design90-input-manifest-v01.csv"
)
SOURCE_DESIGN90_EVIDENCE = Path(
    "docs/plans/2026-08-10-camels-parfc-state-interaction-"
    "design90-01b-evidence.json"
)
TASK_TABLE = Path(
    "docs/plans/2026-08-11-camels-parfc-transition-path-"
    "03b-design90-tasks-v01.csv"
)
INITIAL_MOMENT_MANIFEST = Path(
    "docs/plans/2026-08-11-camels-parfc-transition-path-"
    "03b-design90-initial-moment-manifest-v01.npz"
)
PREREGISTRATION = Path(
    "docs/plans/2026-08-11-camels-parfc-transition-path-"
    "03b-design90-prereg-v01.md"
)
IMPLEMENTATION_PLAN = Path(
    "docs/superpowers/plans/"
    "2026-08-11-camels-parfc-path-postcollapse-design90-03b.md"
)
CONFIGURATION = Path(
    "src/camels_switch_confirmation/configs/"
    "camels_parfc_transition_path_03b_design90.json"
)
RUN_MANIFEST = Path(
    "docs/plans/2026-08-11-camels-parfc-transition-path-"
    "03b-design90-run-manifest-v01.json"
)
PREFLIGHT_EVIDENCE = Path(
    "docs/plans/2026-08-11-camels-parfc-transition-path-"
    "03b-design90-preflight-evidence-v01.json"
)
OUTPUT_ROOT = Path(
    "results/23_camels_switch_confirmation/"
    "camels_parfc_transition_path_03b_design90_s01_20260811_local"
)
RUN_STDOUT = Path("tmp/camels_parfc_transition_path_03b_design90.stdout.log")
RUN_STDERR = Path("tmp/camels_parfc_transition_path_03b_design90.stderr.log")
VERIFY_STDOUT = Path(
    "tmp/camels_parfc_transition_path_03b_design90_verify.stdout.log"
)
VERIFY_STDERR = Path(
    "tmp/camels_parfc_transition_path_03b_design90_verify.stderr.log"
)
TEST_STDOUT = Path(
    "tmp/camels_parfc_transition_path_03b_design90_prepare_tests.stdout.log"
)
TEST_STDERR = Path(
    "tmp/camels_parfc_transition_path_03b_design90_prepare_tests.stderr.log"
)
PARAMETER_TABLE = Path(
    "results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01/"
    "summary/hbv_lite_cma_rising_local_full.csv"
)
G1_TABLE = Path("results/23_camels_switch_confirmation/g1_precheck_v01/g1_precheck.csv")
DATA_ROOT = Path("data/camels_us")

EXPECTED_MECHANISM_CONFIG_SHA256 = (
    "90f2a19e6f45a78fca08debe697166faac6046029ea4f6d677358de58b07132e"
)
EXPECTED_MECHANISM_COLLECTION_SHA256 = (
    "6d1e275c3d9d8f8b3a338311c8b7f734162b16d98343eacc3fbda1c253fd6327"
)
EXPECTED_MECHANISM_SUMMARY_SHA256 = (
    "8ad2ea45a1b2a6c2178d17e324b16e9e64bd12d521669958ab4f0d6e80d35d03"
)


def sha256_file(path: str | Path) -> str:
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def collection_fingerprint(root: str | Path) -> dict:
    directory = Path(root)
    if not directory.is_dir():
        raise FileNotFoundError(f"collection root is missing: {directory}")
    entries = []
    total_bytes = 0
    for path in sorted(value for value in directory.rglob("*") if value.is_file()):
        relative = path.relative_to(directory).as_posix()
        size = path.stat().st_size
        total_bytes += size
        entries.append(f"{relative},{size},{sha256_file(path)}")
    joined = "\n".join(entries).encode("utf-8")
    return {
        "entry_format": "relative_path,bytes,sha256",
        "count": len(entries),
        "bytes": total_bytes,
        "sha256_of_newline_joined_sorted_entries": hashlib.sha256(joined).hexdigest(),
        "entries": entries,
    }


def build_historical_stopped_run_evidence(
    observed_collections: Mapping[str, Mapping],
) -> dict:
    """Validate immutable version-03 and version-03A diagnostic collections."""
    if set(observed_collections) != set(HISTORICAL_STOPPED_RUNS):
        raise ValueError("historical stopped-run collection set changed")
    evidence = {}
    for version, expected in HISTORICAL_STOPPED_RUNS.items():
        observed = observed_collections[version]
        if (
            int(observed.get("count", -1)) != int(expected["count"])
            or int(observed.get("bytes", -1)) != int(expected["bytes"])
            or observed.get("sha256_of_newline_joined_sorted_entries")
            != expected["sha256"]
        ):
            raise ValueError(f"historical stopped-run collection changed for {version}")
        evidence[version] = {
            "root": expected["root"].as_posix(),
            "status": "stopped_before_scientific_summary_not_method_evidence",
            "result_collection": {
                "entry_format": observed.get("entry_format"),
                "count": int(observed["count"]),
                "bytes": int(observed["bytes"]),
                "sha256_of_newline_joined_sorted_entries": observed[
                    "sha256_of_newline_joined_sorted_entries"
                ],
            },
        }
    return evidence


def _historical_stopped_run_evidence() -> dict:
    observed = {
        version: collection_fingerprint(_REPO_ROOT / expected["root"])
        for version, expected in HISTORICAL_STOPPED_RUNS.items()
    }
    return build_historical_stopped_run_evidence(observed)


def build_task_identities(basin_ids: Sequence[object]) -> list[tuple[str, int]]:
    basins = [mechanism_runner._normalize_basin_id(value) for value in basin_ids]
    if len(basins) != 90 or len(set(basins)) != 90:
        raise ValueError("Design90 requires exactly 90 unique basin identifiers")
    return [(basin_id, seed) for basin_id in basins for seed in (0, 1)]


def _paired_directions(task_metrics: pd.DataFrame) -> dict:
    required = {
        "arm_id",
        "basin_id",
        "seed",
        "severe_negative_log_probability_days",
        "mean_true_negative_log_probability",
        "multiclass_brier",
    }
    if not required.issubset(task_metrics.columns) or len(task_metrics) != 20:
        raise ValueError("mechanism task metrics are incomplete")
    result = {}
    metrics = (
        ("severe_negative_log_probability_days", False),
        ("mean_true_negative_log_probability", False),
        ("multiclass_brier", False),
    )
    for name, higher_is_better in metrics:
        counts = {"improved": 0, "equal": 0, "worse": 0}
        for _, group in task_metrics.groupby(["basin_id", "seed"], sort=False):
            if set(group["arm_id"]) != {"C", "P"} or len(group) != 2:
                raise ValueError("mechanism task metrics are not paired")
            c_value = float(group.loc[group["arm_id"] == "C", name].iloc[0])
            p_value = float(group.loc[group["arm_id"] == "P", name].iloc[0])
            if p_value == c_value:
                counts["equal"] += 1
            elif (p_value > c_value) == higher_is_better:
                counts["improved"] += 1
            else:
                counts["worse"] += 1
        result[name] = counts
    return result


def build_mechanism_evidence(
    *,
    summary: Mapping,
    result_collection: Mapping,
    logs: Sequence[Mapping],
    config_sha256: str,
    paired_directions: Mapping,
) -> dict:
    if summary.get("verification_status") != "passed":
        raise ValueError("parent mechanism verification did not pass")
    if summary.get("mechanism_gate_status") != "GO":
        raise ValueError("parent mechanism gate is not GO")
    if summary.get("task_count") != 20 or summary.get("source_task_count") != 10:
        raise ValueError("parent mechanism task counts changed")
    if not summary.get("severe_day_count_strictly_improved") or not summary.get(
        "mean_negative_log_probability_strictly_improved"
    ):
        raise ValueError("parent mechanism continuation indicators changed")
    if config_sha256 != EXPECTED_MECHANISM_CONFIG_SHA256:
        raise ValueError("parent mechanism configuration hash changed")
    if (
        int(result_collection.get("count", -1)) != 25
        or result_collection.get("sha256_of_newline_joined_sorted_entries")
        != EXPECTED_MECHANISM_COLLECTION_SHA256
    ):
        raise ValueError("parent mechanism result collection changed")
    if len(logs) != 4:
        raise ValueError("parent mechanism must register four logs")
    error_logs = [value for value in logs if "stderr" in str(value.get("path"))]
    if len(error_logs) != 2 or any(int(value.get("bytes", -1)) != 0 for value in error_logs):
        raise ValueError("parent mechanism error logs must both be empty")
    expected_paired = {
        "severe_negative_log_probability_days": {
            "improved": 9,
            "equal": 1,
            "worse": 0,
        },
        "mean_true_negative_log_probability": {
            "improved": 7,
            "equal": 0,
            "worse": 3,
        },
        "multiclass_brier": {"improved": 6, "equal": 0, "worse": 4},
    }
    if dict(paired_directions) != expected_paired:
        raise ValueError("parent mechanism paired task directions changed")
    return {
        "experiment_id": "CAMELS_PARFC_TRANSITION_PATH_03B_MECHANISM10",
        "evidence_status": "complete_independently_verified_mechanism_gate_go",
        "completed_date": "2026-08-11",
        "scope": "ten_failure_selected_tasks_design_seeds_only",
        "configuration_sha256": config_sha256,
        "verification_summary_sha256": EXPECTED_MECHANISM_SUMMARY_SHA256,
        "verification_status": summary["verification_status"],
        "mechanism_gate_status": summary["mechanism_gate_status"],
        "arm_summary": summary["arm_summary"],
        "paired_task_directions": expected_paired,
        "path_reconstruction_diagnostics": summary[
            "path_reconstruction_maximum_absolute_differences"
        ],
        "result_collection": dict(result_collection),
        "logs": [dict(value) for value in logs],
        "authorization_boundary": {
            "design_seeds_used": [0, 1],
            "reserved_seeds_used": False,
            "ninety_basin_run_performed": False,
            "full_531_basin_run_performed": False,
            "validation_configuration_frozen": False,
        },
        "claim_boundary": (
            "The gate permits preparation of a separate Design90 configuration; "
            "it is not parameter-identification validation, state accuracy, forecast "
            "value, noise identification, or real-observation assimilation evidence."
        ),
    }


def _project_common_state(
    initial_hydrologic: np.ndarray,
    parameters: Mapping[str, float],
) -> np.ndarray:
    state = np.zeros(len(FULL_STATE_NAMES), dtype=np.float64)
    state[:5] = np.asarray(initial_hydrologic, dtype=np.float64)
    capacity = float(parameters["parFC"])
    liquid_fraction = float(parameters["parCWH"])
    excess = max(float(state[2]) - capacity, 0.0)
    if excess > 0.0:
        state[2] -= excess
        state[3] += excess
    snow = max(float(state[0]), 0.0)
    state[0] = snow
    state[1] = np.clip(state[1], 0.0, liquid_fraction * snow)
    state[2] = np.clip(state[2], 1e-5, capacity)
    state[3:] = np.maximum(state[3:], 0.0)
    return state


def _independent_sigma_points(mean: np.ndarray, covariance: np.ndarray):
    n_state = len(mean)
    alpha = 0.6874
    beta = 2.0
    kappa = -2.0
    lambda_value = alpha**2 * (n_state + kappa) - n_state
    scale = n_state + lambda_value
    mean_weights = np.full(2 * n_state + 1, 1.0 / (2.0 * scale))
    covariance_weights = mean_weights.copy()
    mean_weights[0] = lambda_value / scale
    covariance_weights[0] = mean_weights[0] + 1.0 - alpha**2 + beta
    symmetric = 0.5 * (covariance + covariance.T)
    symmetric = 0.5 * (symmetric + symmetric.T)
    root = np.linalg.cholesky(scale * symmetric)
    sigmas = np.empty((2 * n_state + 1, n_state), dtype=np.float64)
    sigmas[0] = mean
    for index in range(n_state):
        offset = root[:, index]
        sigmas[index + 1] = mean + offset
        sigmas[n_state + index + 1] = mean - offset
    return sigmas, mean_weights, covariance_weights


def _independent_remap_moments(
    mean: np.ndarray,
    covariance: np.ndarray,
    source_parameters: Mapping[str, float],
    destination_parameters: Mapping[str, float],
) -> tuple[np.ndarray, np.ndarray]:
    source_capacity = float(source_parameters["parFC"])
    destination_capacity = float(destination_parameters["parFC"])
    if destination_capacity >= source_capacity:
        return mean.copy(), covariance.copy()
    sigmas, mean_weights, covariance_weights = _independent_sigma_points(
        mean, covariance
    )
    mapped = sigmas.copy()
    for point in mapped:
        excess = max(float(point[2]) - destination_capacity, 0.0)
        if excess > 0.0:
            point[2] = destination_capacity
            point[3] += excess
    if np.array_equal(mapped, sigmas):
        return mean.copy(), covariance.copy()
    mapped_mean = mean_weights @ mapped
    deviations = mapped - mapped_mean
    mapped_covariance = np.einsum(
        "i,ij,ik->jk", covariance_weights, deviations, deviations
    )
    mapped_covariance = 0.5 * (mapped_covariance + mapped_covariance.T)
    mapped_covariance = 0.5 * (mapped_covariance + mapped_covariance.T)
    return mapped_mean.copy(), mapped_covariance.copy()


def independent_initial_moments(
    members: Sequence[Mapping[str, float]],
    initial_hydrologic: Sequence[float],
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    if len(members) != 3:
        raise ValueError("initial moments require exactly three candidates")
    initial = np.asarray(initial_hydrologic, dtype=np.float64)
    if initial.shape != (5,) or not np.all(np.isfinite(initial)):
        raise ValueError("initial hydrologic state must be a finite five-vector")
    common_state = _project_common_state(initial, members[0])
    scales = np.maximum(np.abs(common_state), 1.0)
    common_covariance = np.diag((0.001 * scales) ** 2)
    states = []
    covariances = []
    for member in members:
        state, covariance = _independent_remap_moments(
            common_state,
            common_covariance,
            members[0],
            member,
        )
        states.append(state)
        covariances.append(covariance)
    return (
        np.full(3, 1.0 / 3.0, dtype=np.float64),
        np.asarray(states, dtype=np.float64),
        np.asarray(covariances, dtype=np.float64),
    )


def _write_json_exclusive(path: Path, value: Mapping) -> None:
    with path.open("x", encoding="utf-8", newline="\n") as handle:
        json.dump(dict(value), handle, indent=2, sort_keys=False)
        handle.write("\n")


def _registered_entry(path: Path) -> dict:
    resolved = _REPO_ROOT / path
    if not resolved.is_file():
        raise FileNotFoundError(f"registered file is missing: {resolved}")
    return {
        "path": path.as_posix(),
        "bytes": resolved.stat().st_size,
        "sha256": sha256_file(resolved),
    }


def _load_basins() -> list[str]:
    frame = pd.read_csv(_REPO_ROOT / BASIN_LIST, dtype={"basin_id": str})
    if "basin_id" not in frame:
        raise ValueError("basin list lacks basin_id")
    return [basin_id for basin_id, _ in build_task_identities(frame["basin_id"])[::2]]


def _build_source_task_table(basins: Sequence[str]) -> pd.DataFrame:
    metrics_path = _REPO_ROOT / SOURCE_DESIGN90_ROOT / "verification/task_metrics.csv"
    metrics = pd.read_csv(metrics_path, dtype={"basin_id": str})
    metrics = metrics[metrics["arm_id"] == "C"].copy()
    metrics["basin_id"] = [
        mechanism_runner._normalize_basin_id(value) for value in metrics["basin_id"]
    ]
    metric_lookup = {
        (str(row.basin_id), int(row.seed)): row for row in metrics.itertuples(index=False)
    }
    rows = []
    for order, (basin_id, seed) in enumerate(build_task_identities(basins), start=1):
        key = (basin_id, seed)
        if key not in metric_lookup:
            raise ValueError(f"source Design90 metrics lack {key}")
        source_relative = (
            SOURCE_DESIGN90_ROOT / "arms" / "C" / "probs" / f"{basin_id}_s{seed}.npz"
        )
        source = _REPO_ROOT / source_relative
        if not source.is_file():
            raise FileNotFoundError(f"source Design90 probability is missing: {source}")
        mechanism_runner._verify_source_probability_content(
            source,
            SimpleNamespace(basin_id=basin_id, seed=seed),
        )
        metric = metric_lookup[key]
        rows.append(
            {
                "order": order,
                "basin_id": basin_id,
                "seed": seed,
                "arm_id": "C",
                "events_passed": int(metric.events_passed),
                "multiclass_brier": float(metric.multiclass_brier),
                "stable_true_negative_log_probability": float(
                    metric.true_negative_log_probability
                ),
                "source_probability_path": source_relative.as_posix(),
                "source_probability_bytes": source.stat().st_size,
                "source_probability_sha256": sha256_file(source),
            }
        )
    frame = pd.DataFrame(rows)
    return design_runner.validate_design90_task_frame(frame, basins)


def _build_initial_manifest_arrays(
    identities: Sequence[tuple[str, int]],
) -> dict[str, np.ndarray]:
    parameter_frame = pd.read_csv(
        _REPO_ROOT / PARAMETER_TABLE, dtype={"basin_id": str}
    )
    parameter_frame["basin_id"] = [
        mechanism_runner._normalize_basin_id(value)
        for value in parameter_frame["basin_id"]
    ]
    parameter_lookup = {
        str(row.basin_id): row for row in parameter_frame.itertuples(index=False)
    }
    bounds = resolve_hbv_bounds("v5")
    probabilities = []
    states = []
    covariances = []
    for basin_id, _ in identities:
        if basin_id not in parameter_lookup:
            raise ValueError(f"parameter table lacks basin {basin_id}")
        row = parameter_lookup[basin_id]
        params = {name: float(getattr(row, f"p_{name}")) for name in PARAM_KEYS}
        params["lag_time"] = min(params["lag_time"], 10.0)
        initial_hydrologic = np.asarray(
            [float(getattr(row, f"state_{name}")) for name in STATE_NAMES],
            dtype=np.float64,
        )
        members, _ = build_bank(params, bounds["parFC"])
        independent = independent_initial_moments(members, initial_hydrologic)
        estimator, _ = _build_bank(
            members,
            initial_hydrologic,
            sigma_obs=1.0,
            bounds=bounds,
            q_scale=3e-8,
            q_structure="lower_groundwater_state_only",
            q_mode="fixed",
            q_state_multiplier=1.0,
            filter_r_multiplier=1.0,
            interaction_mode="pairwise_path_postcollapse",
            parameter_state_mapping="conservative_parfc",
        )
        production = (
            estimator.probabilities,
            np.asarray([item.state for item in estimator.filters]),
            np.asarray([item.covariance for item in estimator.filters]),
        )
        if any(not np.array_equal(left, right) for left, right in zip(independent, production)):
            raise ValueError(f"independent initial moments differ for basin {basin_id}")
        probabilities.append(independent[0])
        states.append(independent[1])
        covariances.append(independent[2])
    return {
        "basin_id": np.asarray([key[0] for key in identities], dtype="<U8"),
        "seed": np.asarray([key[1] for key in identities], dtype=np.int64),
        "initial_probabilities": np.asarray(probabilities, dtype=np.float64),
        "initial_states": np.asarray(states, dtype=np.float64),
        "initial_covariances": np.asarray(covariances, dtype=np.float64),
        "initial_probability_axis_order": np.asarray(["task", "candidate"]),
        "initial_state_axis_order": np.asarray(["task", "candidate", "state"]),
        "initial_covariance_axis_order": np.asarray(
            ["task", "candidate", "state_row", "state_column"]
        ),
    }


def _mechanism_evidence() -> dict:
    summary_path = _REPO_ROOT / MECHANISM_ROOT / "verification/verification_summary.json"
    summary = json.loads(summary_path.read_text(encoding="utf-8"))
    if sha256_file(summary_path) != EXPECTED_MECHANISM_SUMMARY_SHA256:
        raise ValueError("mechanism verification summary hash changed")
    task_metrics = pd.read_csv(
        _REPO_ROOT / MECHANISM_ROOT / "verification/task_metrics.csv",
        dtype={"basin_id": str},
    )
    log_paths = (
        Path("tmp/camels_parfc_transition_path_03b_mechanism10.stdout.log"),
        Path("tmp/camels_parfc_transition_path_03b_mechanism10.stderr.log"),
        Path("tmp/camels_parfc_transition_path_03b_mechanism10_verify.stdout.log"),
        Path("tmp/camels_parfc_transition_path_03b_mechanism10_verify.stderr.log"),
    )
    logs = [_registered_entry(path) for path in log_paths]
    return build_mechanism_evidence(
        summary=summary,
        result_collection=collection_fingerprint(_REPO_ROOT / MECHANISM_ROOT),
        logs=logs,
        config_sha256=sha256_file(_REPO_ROOT / MECHANISM_CONFIG),
        paired_directions=_paired_directions(task_metrics),
    )


def _implementation_entries() -> dict:
    paths = {
        "g2_switch_confirmation": Path(
            "src/camels_switch_confirmation/g2_switch_confirmation.py"
        ),
        "imm": Path("src/hbv_joint_uncertainty/imm.py"),
        "hbv_state_mapping": Path("src/hbv_joint_uncertainty/hbv_state_mapping.py"),
        "preflight": Path("src/hbv_joint_uncertainty/preflight.py"),
        "hbv_adapter": Path("src/hbv_joint_uncertainty/hbv_adapter.py"),
        "sigma_filter": Path("src/hbv_joint_uncertainty/sigma_filter.py"),
        "bank": Path("src/camels_switch_confirmation/bank.py"),
        "g1_precheck": Path("src/camels_switch_confirmation/g1_precheck.py"),
        "data_loader": Path("src/hydroagent/data_loading.py"),
        "hbv_model_and_bounds": Path("src/scl_hydro/hbv_lite_numpy.py"),
        "batch_control": Path("src/camels_switch_confirmation/batch_control.py"),
        "mechanism_runner": Path(
            "src/camels_switch_confirmation/run_parameter_path_mechanism.py"
        ),
        "mechanism_tests": Path("test/test_camels_parameter_path_mechanism.py"),
        "mechanism_verifier": Path(
            "src/camels_switch_confirmation/verify_parameter_path_mechanism.py"
        ),
        "mechanism_verifier_tests": Path(
            "test/test_camels_parameter_path_mechanism_verifier.py"
        ),
        "preregistration": PREREGISTRATION,
        "mechanism_plan": IMPLEMENTATION_PLAN,
        "design90_runner": Path(
            "src/camels_switch_confirmation/run_parameter_path_design90.py"
        ),
        "design90_runner_tests": Path(
            "test/test_camels_parameter_path_design90.py"
        ),
        "design90_verifier": Path(
            "src/camels_switch_confirmation/verify_parameter_path_design90.py"
        ),
        "design90_verifier_tests": Path(
            "test/test_camels_parameter_path_design90_verifier.py"
        ),
        "design90_registration": Path(
            "src/camels_switch_confirmation/register_parameter_path_design90.py"
        ),
        "design90_registration_tests": Path(
            "test/test_camels_parameter_path_design90_registration.py"
        ),
    }
    return {
        role: {"path": path.as_posix(), "sha256": sha256_file(_REPO_ROOT / path)}
        for role, path in paths.items()
    }


def _test_evidence() -> dict:
    stdout = _REPO_ROOT / TEST_STDOUT
    stderr = _REPO_ROOT / TEST_STDERR
    if not stdout.is_file() or not stderr.is_file():
        raise FileNotFoundError("registered preparation test logs are missing")
    text = stdout.read_text(encoding="utf-8", errors="replace")
    matches = re.findall(r"(\d+) passed", text)
    if not matches:
        raise ValueError("preparation test log does not contain a passed count")
    if " failed" in text or " error" in text.lower():
        raise ValueError("preparation test log contains a failure or error")
    if stderr.stat().st_size != 0:
        raise ValueError("preparation test standard error must be empty")
    return {
        "passed": int(matches[-1]),
        "failed": 0,
        "stdout": _registered_entry(TEST_STDOUT),
        "stderr": _registered_entry(TEST_STDERR),
    }


def _build_configuration(
    *,
    task_hash: str,
    initial_hash: str,
    mechanism_evidence_hash: str,
    historical_stopped_runs: Mapping,
    test_evidence: Mapping,
) -> dict:
    runtime = mechanism_runner._observed_runtime_contract()
    source_summary = _REPO_ROOT / SOURCE_DESIGN90_ROOT / "verification/task_metrics.csv"
    parent_summary = _REPO_ROOT / MECHANISM_ROOT / "verification/verification_summary.json"
    return {
        "experiment_id": "CAMELS_PARFC_TRANSITION_PATH_03B_DESIGN90",
        "configuration_status": design_runner.CONFIGURATION_STATUS,
        "registered_date": "2026-08-11",
        "source_revision": "61e938b3a89f648e460a20e6f03e005bdc9fca4a",
        "authorization_boundary": {
            "scope": "ninety_basin_design_seed_configuration_preparation_only",
            "configuration_preparation_authorized": True,
            "requires_separate_360_task_execution_go": True,
            "ninety_basin_execution_authorized_at_freeze": False,
            "design_seeds": [0, 1],
            "reserved_validation_seeds_authorized": False,
            "full_531_basin_run_authorized": False,
            "configuration_freeze_version_02_authorized": False,
        },
        "parent_mechanism": {
            "experiment_id": "CAMELS_PARFC_TRANSITION_PATH_03B_MECHANISM10",
            "mechanism_gate_status": "GO",
            "evidence_path": MECHANISM_EVIDENCE.as_posix(),
            "evidence_sha256": mechanism_evidence_hash,
            "verification_summary_path": (
                MECHANISM_ROOT / "verification/verification_summary.json"
            ).as_posix(),
            "verification_summary_sha256": sha256_file(parent_summary),
        },
        "historical_stopped_runs": dict(historical_stopped_runs),
        "source_design90": {
            "experiment_id": "CAMELS_PARFC_STATE_INTERACTION_01B_DESIGN90",
            "evidence_path": SOURCE_DESIGN90_EVIDENCE.as_posix(),
            "evidence_sha256": sha256_file(_REPO_ROOT / SOURCE_DESIGN90_EVIDENCE),
            "source_arm": "C",
            "source_root": SOURCE_DESIGN90_ROOT.as_posix(),
            "source_task_metrics": (
                SOURCE_DESIGN90_ROOT / "verification/task_metrics.csv"
            ).as_posix(),
            "source_task_metrics_sha256": sha256_file(source_summary),
            "expected_c_events_passed": 706,
        },
        "inputs": {
            "parameter_table": PARAMETER_TABLE.as_posix(),
            "parameter_table_sha256": sha256_file(_REPO_ROOT / PARAMETER_TABLE),
            "g1_precheck_table": G1_TABLE.as_posix(),
            "g1_precheck_table_sha256": sha256_file(_REPO_ROOT / G1_TABLE),
            "data_root": DATA_ROOT.as_posix(),
            "raw_input_manifest": RAW_INPUT_MANIFEST.as_posix(),
            "raw_input_manifest_sha256": sha256_file(_REPO_ROOT / RAW_INPUT_MANIFEST),
            "task_table": TASK_TABLE.as_posix(),
            "task_table_sha256": task_hash,
            "initial_moment_manifest": INITIAL_MOMENT_MANIFEST.as_posix(),
            "initial_moment_manifest_sha256": initial_hash,
        },
        "design_selection": {
            "basin_count": 90,
            "basin_list": BASIN_LIST.as_posix(),
            "basin_list_sha256": sha256_file(_REPO_ROOT / BASIN_LIST),
            "forcing_coverage_table": COVERAGE_TABLE.as_posix(),
            "forcing_coverage_table_sha256": sha256_file(
                _REPO_ROOT / COVERAGE_TABLE
            ),
            "selection_uses_prior_path_method_outcomes": False,
            "selection_source": "completed state-interaction Design90 basin list",
        },
        "initial_moment_contract": {
            "task_count": 180,
            "candidate_count": 3,
            "state_count": 15,
            "probability_shape": [180, 3],
            "state_shape": [180, 3, 15],
            "covariance_shape": [180, 3, 15, 15],
            "independent_generation_bitwise_matches_production_initializer": True,
        },
        "filter": dict(mechanism_runner.EXPECTED_FILTER),
        "arms": [dict(value) for value in mechanism_runner.EXPECTED_ARMS],
        "implementation": _implementation_entries(),
        "runtime": runtime,
        "preflight_test_evidence": dict(test_evidence),
        "outputs": {"root": OUTPUT_ROOT.as_posix()},
        "decision_gates": dict(design_verifier.EXPECTED_GATE_CONTRACT),
        "claim_boundary": {
            "parameter_candidate_identification": "exploratory_design90_only",
            "noise_candidate_identification": "not_tested",
            "complete_state_accuracy": "not_tested",
            "forecast_value": "not_tested",
            "real_observation_assimilation_value": "not_tested",
        },
    }


def _build_run_manifest(config_hash: str, config_bytes: int, test_evidence: Mapping) -> dict:
    run_command = (
        "C:\\Users\\yiqun\\anaconda3\\python.exe -m "
        "camels_switch_confirmation.run_parameter_path_design90 "
        "--config src/camels_switch_confirmation/configs/"
        "camels_parfc_transition_path_03b_design90.json "
        f"--expected-config-sha256 {config_hash} --workers 4"
    )
    verify_command = (
        "C:\\Users\\yiqun\\anaconda3\\python.exe -m "
        "camels_switch_confirmation.verify_parameter_path_design90 "
        "--config src/camels_switch_confirmation/configs/"
        "camels_parfc_transition_path_03b_design90.json "
        f"--expected-config-sha256 {config_hash}"
    )
    return {
        "experiment_id": "CAMELS_PARFC_TRANSITION_PATH_03B_DESIGN90",
        "registered_date": "2026-08-11",
        "status": "registered_not_run_awaiting_separate_user_go",
        "configuration": {
            "path": CONFIGURATION.as_posix(),
            "bytes": config_bytes,
            "sha256": config_hash,
        },
        "task_contract": {
            "basins": 90,
            "design_seeds": [0, 1],
            "source_tasks": 180,
            "arms": ["C", "P"],
            "planned_tasks": 360,
            "events_per_arm": 1080,
        },
        "execution": {
            "authorization_status": "not_authorized_until_separate_user_go",
            "working_directory": str(_REPO_ROOT),
            "python": sys.executable,
            "python_sha256": sha256_file(sys.executable),
            "pythonpath": str(_REPO_ROOT / "src"),
            "workers": 4,
            "command": run_command,
            "stdout": RUN_STDOUT.as_posix(),
            "stderr": RUN_STDERR.as_posix(),
            "output_root": OUTPUT_ROOT.as_posix(),
        },
        "independent_verification": {
            "authorization_status": "not_authorized_until_execution_completes",
            "command": verify_command,
            "stdout": VERIFY_STDOUT.as_posix(),
            "stderr": VERIFY_STDERR.as_posix(),
            "expected_output": (
                OUTPUT_ROOT / "verification/verification_summary.json"
            ).as_posix(),
        },
        "preflight_test_evidence": dict(test_evidence),
        "authorization_boundary": {
            "seeds_2_and_3_authorized": False,
            "ninety_basin_execution_authorized": False,
            "full_531_basin_run_authorized": False,
            "configuration_version_02_freeze_authorized": False,
            "commit_push_delete_or_old_evidence_modification_authorized": False,
        },
        "stop_conditions": {
            "before_run": (
                "Stop on any hash, runtime, task, initial-moment, output, log, "
                "source-evidence, or authorization mismatch."
            ),
            "during_run": (
                "Stop new submissions after the first failure and preserve all "
                "completed or in-flight evidence."
            ),
            "after_run": (
                "Hold unless 360 tasks and all independent checks pass; never "
                "change a registered scientific or numerical gate after results."
            ),
        },
        "decision_gates": dict(design_verifier.EXPECTED_GATE_CONTRACT),
    }


def _build_preflight_evidence(
    *,
    config_hash: str,
    run_manifest_hash: str,
    historical_stopped_runs: Mapping,
    test_evidence: Mapping,
) -> dict:
    formal_destinations = [
        OUTPUT_ROOT,
        RUN_STDOUT,
        RUN_STDERR,
        VERIFY_STDOUT,
        VERIFY_STDERR,
    ]
    if any((_REPO_ROOT / path).exists() for path in formal_destinations):
        raise FileExistsError("a registered Design90 output or formal log already exists")
    return {
        "experiment_id": "CAMELS_PARFC_TRANSITION_PATH_03B_DESIGN90",
        "evidence_date": "2026-08-11",
        "status": "configuration_preflight_passed_execution_not_authorized",
        "configuration": {
            "path": CONFIGURATION.as_posix(),
            "sha256": config_hash,
            "read_only_runner_preflight": "passed",
        },
        "run_manifest": {
            "path": RUN_MANIFEST.as_posix(),
            "sha256": run_manifest_hash,
            "status": "registered_not_run_awaiting_separate_user_go",
        },
        "task_contract": {
            "basins": 90,
            "source_tasks": 180,
            "planned_tasks": 360,
            "design_seeds": [0, 1],
            "reserved_seed_present": False,
        },
        "initial_moment_manifest": {
            "path": INITIAL_MOMENT_MANIFEST.as_posix(),
            "sha256": sha256_file(_REPO_ROOT / INITIAL_MOMENT_MANIFEST),
            "probability_shape": [180, 3],
            "state_shape": [180, 3, 15],
            "covariance_shape": [180, 3, 15, 15],
            "independent_bitwise_match": True,
        },
        "registered_inputs": {
            "raw_input_manifest_rows": 184,
            "raw_input_manifest_sha256": sha256_file(
                _REPO_ROOT / RAW_INPUT_MANIFEST
            ),
            "source_probability_files": 180,
            "all_hashes_match": True,
        },
        "historical_stopped_runs": dict(historical_stopped_runs),
        "tests": dict(test_evidence),
        "destinations_before_run": [
            {"path": path.as_posix(), "exists": False}
            for path in formal_destinations
        ],
        "scientific_status": {
            "new_design90_result_exists": False,
            "parameter_candidate_identification": "unverified_at_design90_scale",
            "noise_candidate_identification": "not_tested",
            "complete_state_accuracy": "not_tested",
            "forecast_value": "not_tested",
            "real_observation_assimilation_value": "not_tested",
        },
        "authorization_boundary": {
            "configuration_preparation": "authorized_and_completed",
            "execution": "not_authorized",
            "independent_verification": "not_authorized_until_execution",
            "seeds_2_and_3": "prohibited",
            "full_531_basin_run": "prohibited",
            "version_02_freeze": "prohibited",
        },
    }


def register_design90() -> dict:
    created = (
        MECHANISM_EVIDENCE,
        TASK_TABLE,
        INITIAL_MOMENT_MANIFEST,
        CONFIGURATION,
        RUN_MANIFEST,
        PREFLIGHT_EVIDENCE,
    )
    existing = [path for path in created if (_REPO_ROOT / path).exists()]
    if existing:
        raise FileExistsError(
            "refusing to overwrite preparation artifacts: "
            + ", ".join(path.as_posix() for path in existing)
        )
    if not (_REPO_ROOT / PREREGISTRATION).is_file():
        raise FileNotFoundError("new Design90 preregistration is missing")
    if not (_REPO_ROOT / IMPLEMENTATION_PLAN).is_file():
        raise FileNotFoundError("Design90 implementation plan is missing")
    for path in (OUTPUT_ROOT, RUN_STDOUT, RUN_STDERR, VERIFY_STDOUT, VERIFY_STDERR):
        if (_REPO_ROOT / path).exists():
            raise FileExistsError(f"registered future destination already exists: {path}")
    test_evidence = _test_evidence()
    mechanism_evidence = _mechanism_evidence()
    historical_stopped_runs = _historical_stopped_run_evidence()
    basins = _load_basins()
    task_frame = _build_source_task_table(basins)
    identities = list(zip(task_frame["basin_id"], task_frame["seed"]))
    initial_arrays = _build_initial_manifest_arrays(identities)
    # All expensive validation happens before exclusive creation begins.
    _write_json_exclusive(_REPO_ROOT / MECHANISM_EVIDENCE, mechanism_evidence)
    task_frame.to_csv(_REPO_ROOT / TASK_TABLE, index=False, mode="x")
    with (_REPO_ROOT / INITIAL_MOMENT_MANIFEST).open("xb") as handle:
        np.savez(handle, **initial_arrays)
    task_hash = sha256_file(_REPO_ROOT / TASK_TABLE)
    initial_hash = sha256_file(_REPO_ROOT / INITIAL_MOMENT_MANIFEST)
    config = _build_configuration(
        task_hash=task_hash,
        initial_hash=initial_hash,
        mechanism_evidence_hash=sha256_file(_REPO_ROOT / MECHANISM_EVIDENCE),
        historical_stopped_runs=historical_stopped_runs,
        test_evidence=test_evidence,
    )
    _write_json_exclusive(_REPO_ROOT / CONFIGURATION, config)
    config_hash = sha256_file(_REPO_ROOT / CONFIGURATION)
    verified = design_runner.verify_parameter_path_design90(
        _REPO_ROOT,
        _REPO_ROOT / CONFIGURATION,
        config_hash,
    )
    if len(verified.task_table) != 180 or verified.output_root.exists():
        raise ValueError("Design90 read-only runner preflight did not pass")
    run_manifest = _build_run_manifest(
        config_hash,
        (_REPO_ROOT / CONFIGURATION).stat().st_size,
        test_evidence,
    )
    _write_json_exclusive(_REPO_ROOT / RUN_MANIFEST, run_manifest)
    run_manifest_hash = sha256_file(_REPO_ROOT / RUN_MANIFEST)
    preflight = _build_preflight_evidence(
        config_hash=config_hash,
        run_manifest_hash=run_manifest_hash,
        historical_stopped_runs=historical_stopped_runs,
        test_evidence=test_evidence,
    )
    _write_json_exclusive(_REPO_ROOT / PREFLIGHT_EVIDENCE, preflight)
    return {
        "status": "configuration_prepared_not_run",
        "configuration_sha256": config_hash,
        "run_manifest_sha256": run_manifest_hash,
        "preflight_evidence_sha256": sha256_file(_REPO_ROOT / PREFLIGHT_EVIDENCE),
        "task_table_sha256": task_hash,
        "initial_moment_manifest_sha256": initial_hash,
        "source_tasks": 180,
        "planned_tasks": 360,
        "output_exists": (_REPO_ROOT / OUTPUT_ROOT).exists(),
    }


def _parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--prepare",
        action="store_true",
        help="create the frozen preparation artifacts; never runs the experiment",
    )
    return parser.parse_args(argv)


def main(argv=None) -> int:
    arguments = _parse_args(argv)
    if not arguments.prepare:
        print("STOP: --prepare is required", file=sys.stderr)
        return 1
    try:
        result = register_design90()
    except Exception as error:  # noqa: BLE001 - executable must stop cleanly
        print(f"STOP: {type(error).__name__}: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

"""Independently verify the clean process-noise switch result package."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from uuid import uuid4

import matplotlib.image as matplotlib_image
import numpy as np
from scipy.stats import beta as beta_distribution


PROJECT_ROOT = Path(__file__).resolve().parents[3]
SRC_ROOT = PROJECT_ROOT / "src"
if str(SRC_ROOT) not in sys.path:
    sys.path.insert(0, str(SRC_ROOT))

from scl_hydro.hbv_lite_numpy import simulate_hbv_lite  # noqa: E402


EXPERIMENT_ID = "g3_state_domain_consistent_process_noise_switch_v01"
DEFAULT_RESULT = (
    PROJECT_ROOT
    / "results/23_hbv_multilead_joint_uncertainty"
    / EXPERIMENT_ID
)
DEFAULT_VERIFICATION = (
    PROJECT_ROOT
    / "results/23_hbv_multilead_joint_uncertainty"
    / f"{EXPERIMENT_ID}_independent_verification_v01"
)
FROZEN_CONFIG = (
    PROJECT_ROOT
    / "src/hbv_multilead_joint_uncertainty/configs"
    / f"{EXPERIMENT_ID}.json"
)
PARAMETER_NAMES = (
    "parTT",
    "parCFMAX",
    "parCFR",
    "parCWH",
    "parFC",
    "parBETA",
    "parLP",
    "parK0",
    "parK1",
    "parUZL",
    "parPERC",
    "parK2",
    "lag_time",
)
HYDROLOGIC_STATE_NAMES = ("SNOWPACK", "MELTWATER", "SM", "SUZ", "SLZ")
PROCESS_IDS = (
    "lower_groundwater_low",
    "lower_groundwater_medium",
    "lower_groundwater_high",
)
EVIDENCE_KEYS = {
    "block_ids",
    "process_ids",
    "parameter_names",
    "fixed_parameter_vector",
    "process_standard_deviations",
    "process_covariances",
    "observation_standard_deviation",
    "warmup_days",
    "stage_length_days",
    "forcing_blocks",
    "process_schedule",
    "process_standard_normals",
    "observation_standard_normals",
    "initial_states",
    "initial_covariances",
    "deterministic_truth_states",
    "truth_process_perturbations",
    "truth_projection_adjustments",
    "truth_states",
    "truth_discharge",
    "observations",
    "posterior_probabilities",
    "global_posterior_states",
    "forecast_executed",
}


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def assert_verification_path_absent(path: Path) -> None:
    if Path(path).exists():
        raise FileExistsError(f"verification path already exists: {path}")


def verify_artifact_checksums(result_dir: Path) -> dict[str, bool]:
    root = Path(result_dir)
    manifest_path = root / "checksums.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if not isinstance(manifest, dict):
        raise ValueError("artifact checksum manifest is not an object")
    actual_files = {
        path.relative_to(root).as_posix()
        for path in root.rglob("*")
        if path.is_file() and path.name != "checksums.json"
    }
    if actual_files != set(manifest):
        raise ValueError("artifact checksum manifest file set mismatch")
    checks = {}
    for relative_path, expected_digest in manifest.items():
        path = root / relative_path
        passed = path.is_file() and _sha256(path) == expected_digest
        checks[relative_path] = passed
        if not passed:
            raise ValueError(f"artifact checksum mismatch: {relative_path}")
    return checks


def independent_first_complete_top_ranked_run(
    top_ranked,
    consecutive_days: int,
    window_days: int,
) -> int | None:
    values = np.asarray(top_ranked, dtype=bool)
    run = int(consecutive_days)
    window = int(window_days)
    if values.ndim != 1 or run <= 0 or window < run or len(values) < window:
        raise ValueError("independent response-run inputs are invalid")
    for start in range(window - run + 1):
        if all(bool(value) for value in values[start : start + run]):
            return start
    return None


def _project_state(state: np.ndarray, parameters: dict[str, float]) -> np.ndarray:
    values = np.asarray(state, dtype=np.float64).copy()
    if values.shape != (15,):
        raise ValueError("independent state shape mismatch")
    snow = max(float(values[0]), 0.0)
    values[0] = snow
    values[1] = np.clip(
        values[1], 0.0, parameters["parCWH"] * snow
    )
    values[2] = np.clip(values[2], 1e-5, parameters["parFC"])
    values[3:] = np.maximum(values[3:], 0.0)
    return values


def _advance_state(
    state: np.ndarray,
    forcing: np.ndarray,
    parameters: dict[str, float],
) -> np.ndarray:
    current = _project_state(state, parameters)
    initial_stores = {
        name: float(value)
        for name, value in zip(HYDROLOGIC_STATE_NAMES, current[:5])
    }
    no_lag_parameters = {**parameters, "lag_time": 1.0}
    raw_discharge, final_stores = simulate_hbv_lite(
        np.asarray([forcing[0]], dtype=np.float64),
        np.asarray([forcing[1]], dtype=np.float64),
        np.asarray([forcing[2]], dtype=np.float64),
        no_lag_parameters,
        initial_state=initial_stores,
    )
    hydrologic = np.asarray(
        [final_stores[name] for name in HYDROLOGIC_STATE_NAMES],
        dtype=np.float64,
    )
    routing_memory = np.concatenate(
        (np.asarray([raw_discharge[0]], dtype=np.float64), current[5:14])
    )
    return _project_state(
        np.concatenate((hydrologic, routing_memory)), parameters
    )


def _routed_discharge(state: np.ndarray, lag_time: float) -> float:
    count = int(np.ceil(lag_time))
    weights = np.arange(count, 0, -1, dtype=np.float64)
    weights /= weights.sum()
    return float(weights @ state[5 : 5 + count])


def _generate_forcing(config: dict) -> np.ndarray:
    forcing = config["forcing"]
    total_days = forcing["warmup_days"] + forcing["assimilation_days"]
    blocks = []
    for seed in config["seeds"]["forcing"]:
        generator = np.random.default_rng(seed)
        rain = forcing["rain_floor_mm_day"] + generator.gamma(
            forcing["rain_gamma_shape"],
            forcing["rain_gamma_scale_mm_day"],
            total_days,
        )
        blocks.append(
            np.column_stack(
                (
                    rain,
                    np.full(
                        total_days,
                        forcing["potential_evaporation_mm_day"],
                    ),
                    np.full(total_days, forcing["temperature_celsius"]),
                )
            )
        )
    return np.asarray(blocks, dtype=np.float64)


def _build_schedule(config: dict) -> np.ndarray:
    length = int(config["population"]["stage_length_days"])
    return np.asarray(
        [
            [identifier for identifier in order for _ in range(length)]
            for order in config["truth_trial_stage_orders"]
        ],
        dtype=np.str_,
    )


def _warmup_state(
    forcing: np.ndarray,
    parameters: dict[str, float],
) -> np.ndarray:
    state = np.zeros(15, dtype=np.float64)
    state[:5] = (
        0.0,
        0.0,
        parameters["parFC"] * 0.3,
        5.0,
        10.0,
    )
    for daily_forcing in forcing:
        state = _advance_state(state, daily_forcing, parameters)
    return state


def _independent_truth(
    config: dict,
    arrays: dict[str, np.ndarray],
) -> dict[str, np.ndarray]:
    forcing = _generate_forcing(config)
    schedule = _build_schedule(config)
    parameter_names = tuple(arrays["parameter_names"].astype(str))
    if parameter_names != PARAMETER_NAMES:
        raise ValueError("saved parameter-name order does not match the verifier")
    parameters = {
        name: float(value)
        for name, value in zip(
            parameter_names, arrays["fixed_parameter_vector"]
        )
    }
    standard_deviations = {
        identifier: float(value)
        for identifier, value in zip(
            PROCESS_IDS, arrays["process_standard_deviations"]
        )
    }
    warmup_days = int(config["forcing"]["warmup_days"])
    active_days = int(config["forcing"]["assimilation_days"])
    block_count = int(config["population"]["matched_block_count"])
    process_normals = np.asarray(
        [
            np.random.default_rng(seed).standard_normal(active_days)
            for seed in config["seeds"]["process_noise"]
        ]
    )
    observation_normals = np.asarray(
        [
            np.random.default_rng(seed).standard_normal(active_days)
            for seed in config["seeds"]["observation_noise"]
        ]
    )
    initial_states = np.empty((block_count, 15), dtype=np.float64)
    initial_covariances = np.empty((block_count, 15, 15), dtype=np.float64)
    shape = (block_count, 3, active_days, 15)
    deterministic = np.empty(shape, dtype=np.float64)
    perturbations = np.zeros(shape, dtype=np.float64)
    adjustments = np.empty(shape, dtype=np.float64)
    truth_states = np.empty(shape, dtype=np.float64)
    truth_discharge = np.empty(
        (block_count, 3, active_days), dtype=np.float64
    )
    observations = np.empty_like(truth_discharge)
    observation_standard_deviation = float(
        arrays["observation_standard_deviation"]
    )
    covariance_fraction = float(
        config["filter"]["initial_covariance_fraction"]
    )

    for block in range(block_count):
        initial = _warmup_state(
            forcing[block, :warmup_days], parameters
        )
        initial_states[block] = initial
        scales = np.maximum(np.abs(initial), 1.0)
        initial_covariances[block] = np.diag(
            np.square(covariance_fraction * scales)
        )
        active_forcing = forcing[block, warmup_days:]
        for trial in range(3):
            state = initial.copy()
            for day in range(active_days):
                deterministic_state = _advance_state(
                    state, active_forcing[day], parameters
                )
                perturbation = np.zeros(15, dtype=np.float64)
                perturbation[4] = (
                    process_normals[block, day]
                    * standard_deviations[schedule[trial, day]]
                )
                unprojected = deterministic_state + perturbation
                projected = _project_state(unprojected, parameters)
                adjustment = projected - unprojected
                deterministic[block, trial, day] = deterministic_state
                perturbations[block, trial, day] = perturbation
                adjustments[block, trial, day] = adjustment
                state = unprojected
                truth_states[block, trial, day] = state
                truth_discharge[block, trial, day] = _routed_discharge(
                    state, parameters["lag_time"]
                )
            observations[block, trial] = (
                truth_discharge[block, trial]
                + observation_standard_deviation
                * observation_normals[block]
            )
    return {
        "forcing_blocks": forcing,
        "process_schedule": schedule,
        "process_standard_normals": process_normals,
        "observation_standard_normals": observation_normals,
        "initial_states": initial_states,
        "initial_covariances": initial_covariances,
        "deterministic_truth_states": deterministic,
        "truth_process_perturbations": perturbations,
        "truth_projection_adjustments": adjustments,
        "truth_states": truth_states,
        "truth_discharge": truth_discharge,
        "observations": observations,
    }


def _exact_interval(
    successes: int,
    total: int,
    confidence_level: float,
) -> tuple[float, float]:
    alpha = 1.0 - confidence_level
    lower = (
        0.0
        if successes == 0
        else float(
            beta_distribution.ppf(
                alpha / 2.0, successes, total - successes + 1
            )
        )
    )
    upper = (
        1.0
        if successes == total
        else float(
            beta_distribution.ppf(
                1.0 - alpha / 2.0,
                successes + 1,
                total - successes,
            )
        )
    )
    return lower, upper


def _transition_order() -> tuple[tuple[str, str], ...]:
    return (
        (PROCESS_IDS[0], PROCESS_IDS[1]),
        (PROCESS_IDS[1], PROCESS_IDS[2]),
        (PROCESS_IDS[2], PROCESS_IDS[0]),
    )


def _independent_response(
    config: dict,
    probabilities: np.ndarray,
    schedule: np.ndarray,
) -> tuple[list[dict], list[dict]]:
    rule = config["response_rule"]
    window = int(rule["response_window_days"])
    consecutive = int(rule["consecutive_top_ranked_days"])
    candidate_index = {
        identifier: index for index, identifier in enumerate(PROCESS_IDS)
    }
    events = []
    for block in range(probabilities.shape[0]):
        for trial in range(probabilities.shape[1]):
            boundaries = np.flatnonzero(
                schedule[trial, 1:] != schedule[trial, :-1]
            ) + 1
            for boundary in boundaries:
                old_identifier = str(schedule[trial, boundary - 1])
                new_identifier = str(schedule[trial, boundary])
                top_ranked = (
                    np.argmax(
                        probabilities[
                            block, trial, boundary : boundary + window
                        ],
                        axis=-1,
                    )
                    == candidate_index[new_identifier]
                )
                start = independent_first_complete_top_ranked_run(
                    top_ranked, consecutive, window
                )
                events.append(
                    {
                        "event_id": (
                            f"block_{block + 1:02d}_trial_{trial + 1}_"
                            f"switch_day_{boundary + 1}"
                        ),
                        "block_index": block,
                        "trial_index": trial,
                        "switch_day_index": int(boundary),
                        "switch_day_number": int(boundary + 1),
                        "old_process_id": old_identifier,
                        "new_process_id": new_identifier,
                        "transition_label": (
                            f"{old_identifier}_to_{new_identifier}"
                        ),
                        "success": start is not None,
                        "response_start_day": (
                            None if start is None else int(start)
                        ),
                        "new_candidate_top_ranked_days_in_window": int(
                            np.count_nonzero(top_ranked)
                        ),
                    }
                )
    summaries = []
    for old_identifier, new_identifier in _transition_order():
        selected = [
            row
            for row in events
            if row["old_process_id"] == old_identifier
            and row["new_process_id"] == new_identifier
        ]
        successes = sum(bool(row["success"]) for row in selected)
        total = len(selected)
        lower, upper = _exact_interval(
            successes, total, float(rule["confidence_level"])
        )
        starts = [
            int(row["response_start_day"])
            for row in selected
            if row["response_start_day"] is not None
        ]
        summaries.append(
            {
                "old_process_id": old_identifier,
                "new_process_id": new_identifier,
                "transition_label": f"{old_identifier}_to_{new_identifier}",
                "event_count": total,
                "successful_event_count": successes,
                "response_fraction": successes / total,
                "exact_interval_lower": lower,
                "exact_interval_upper": upper,
                "median_response_start_day": (
                    None if not starts else float(np.median(starts))
                ),
                "maximum_response_start_day": (
                    None if not starts else int(max(starts))
                ),
                "criterion_passed": (
                    successes
                    >= rule[
                        "minimum_successful_events_per_directed_transition"
                    ]
                    and lower
                    > rule[
                        "minimum_exact_interval_lower_bound_exclusive"
                    ]
                ),
            }
        )
    return events, summaries


def _maximum_difference(actual: np.ndarray, expected: np.ndarray) -> float:
    actual_values = np.asarray(actual)
    expected_values = np.asarray(expected)
    if actual_values.shape != expected_values.shape:
        return float("inf")
    if actual_values.dtype.kind in "USO" or expected_values.dtype.kind in "USO":
        return 0.0 if np.array_equal(actual_values, expected_values) else float("inf")
    if actual_values.dtype.kind == "b" or expected_values.dtype.kind == "b":
        return 0.0 if np.array_equal(actual_values, expected_values) else float("inf")
    if actual_values.size == 0:
        return 0.0
    return float(
        np.max(
            np.abs(
                actual_values.astype(np.float64)
                - expected_values.astype(np.float64)
            )
        )
    )


def _compare_csv(
    path: Path,
    expected_rows: list[dict],
    tolerance: float,
) -> bool:
    with path.open(newline="", encoding="utf-8") as handle:
        actual_rows = list(csv.DictReader(handle))
    if len(actual_rows) != len(expected_rows):
        return False
    for actual, expected in zip(actual_rows, expected_rows):
        if set(actual) != set(expected):
            return False
        for key, expected_value in expected.items():
            actual_value = actual[key]
            if expected_value is None:
                if actual_value != "":
                    return False
            elif isinstance(expected_value, bool):
                if actual_value != str(expected_value):
                    return False
            elif isinstance(expected_value, (int, np.integer)):
                if int(actual_value) != int(expected_value):
                    return False
            elif isinstance(expected_value, (float, np.floating)):
                if abs(float(actual_value) - float(expected_value)) > tolerance:
                    return False
            elif actual_value != str(expected_value):
                return False
    return True


def _daily_rows(
    arrays: dict[str, np.ndarray],
) -> list[dict]:
    probabilities = arrays["posterior_probabilities"]
    schedule = arrays["process_schedule"].astype(str)
    block_ids = arrays["block_ids"].astype(str)
    rows = []
    for block in range(probabilities.shape[0]):
        for trial in range(probabilities.shape[1]):
            for day in range(probabilities.shape[2]):
                for candidate, candidate_id in enumerate(PROCESS_IDS):
                    rows.append(
                        {
                            "block_id": block_ids[block],
                            "truth_trial": trial + 1,
                            "day_index": day,
                            "day_number": day + 1,
                            "stage": day // 180 + 1,
                            "true_process_id": schedule[trial, day],
                            "candidate_process_id": candidate_id,
                            "posterior_probability": probabilities[
                                block, trial, day, candidate
                            ],
                        }
                    )
    return rows


def _independent_stage_accuracy(
    probabilities: np.ndarray,
    schedule: np.ndarray,
) -> list[dict]:
    top = np.argmax(probabilities, axis=-1)
    rows = []
    for candidate, identifier in enumerate(PROCESS_IDS):
        mask = np.broadcast_to(
            schedule == identifier, probabilities.shape[:3]
        )
        rows.append(
            {
                "true_process_id": identifier,
                "day_count": int(np.count_nonzero(mask)),
                "top_ranked_day_count": int(
                    np.count_nonzero((top == candidate) & mask)
                ),
                "top_ranked_fraction": float(
                    np.mean(top[mask] == candidate)
                ),
                "mean_true_candidate_probability": float(
                    np.mean(probabilities[..., candidate][mask])
                ),
            }
        )
    return rows


def _dict_rows_equal(
    actual_rows: list[dict],
    expected_rows: list[dict],
    tolerance: float,
) -> bool:
    if len(actual_rows) != len(expected_rows):
        return False
    for actual, expected in zip(actual_rows, expected_rows):
        if set(actual) != set(expected):
            return False
        for key, expected_value in expected.items():
            actual_value = actual[key]
            if expected_value is None:
                if actual_value is not None:
                    return False
            elif isinstance(expected_value, bool):
                if actual_value is not expected_value:
                    return False
            elif isinstance(expected_value, (int, np.integer)):
                if int(actual_value) != int(expected_value):
                    return False
            elif isinstance(expected_value, (float, np.floating)):
                if abs(float(actual_value) - float(expected_value)) > tolerance:
                    return False
            elif actual_value != expected_value:
                return False
    return True


def _seal_verification_report(
    verification_path: Path,
    report: dict,
) -> None:
    staging = verification_path.with_name(
        f"{verification_path.name}.incomplete.{uuid4().hex}"
    )
    staging.mkdir(parents=False)
    report_path = staging / "independent_verification.json"
    report_path.write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    (staging / "checksums.json").write_text(
        json.dumps(
            {"independent_verification.json": _sha256(report_path)},
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )
    if verification_path.exists():
        raise FileExistsError(
            f"verification path appeared during audit: {verification_path}"
        )
    staging.rename(verification_path)


def verify(
    result_dir: Path = DEFAULT_RESULT,
    verification_dir: Path = DEFAULT_VERIFICATION,
) -> dict:
    result_path = Path(result_dir).resolve()
    verification_path = Path(verification_dir).resolve()
    if result_path != DEFAULT_RESULT.resolve():
        raise ValueError("result path is not the frozen experiment path")
    if verification_path != DEFAULT_VERIFICATION.resolve():
        raise ValueError("verification path is not the frozen audit path")
    assert_verification_path_absent(verification_path)
    checksum_checks = verify_artifact_checksums(result_path)

    config = json.loads(
        (result_path / "config_snapshot.json").read_text(encoding="utf-8")
    )
    frozen_config = json.loads(FROZEN_CONFIG.read_text(encoding="utf-8"))
    config_matches_frozen = config == frozen_config
    source_hash_checks = {}
    for key in ("parameter_source", "observation_noise_source"):
        source_path = PROJECT_ROOT / config[key]["path"]
        source_hash_checks[key] = (
            source_path.is_file()
            and _sha256(source_path) == config[key]["sha256"]
        )
    snapshot_source_checks = {}
    snapshot_manifest = json.loads(
        (result_path / "source_snapshot_manifest.json").read_text(
            encoding="utf-8"
        )
    )
    if not isinstance(snapshot_manifest, list) or not snapshot_manifest:
        raise ValueError("source snapshot manifest is empty or malformed")
    for entry in snapshot_manifest:
        snapshot_relative = Path(entry["snapshot_path"])
        project_relative = Path(entry["project_relative_path"])
        if (
            snapshot_relative.is_absolute()
            or project_relative.is_absolute()
            or ".." in snapshot_relative.parts
            or ".." in project_relative.parts
        ):
            raise ValueError("source snapshot manifest contains an unsafe path")
        snapshot_path = result_path / snapshot_relative
        current_path = PROJECT_ROOT / project_relative
        snapshot_source_checks[project_relative.as_posix()] = (
            snapshot_path.is_file()
            and current_path.is_file()
            and _sha256(snapshot_path) == entry["sha256"]
            and _sha256(current_path) == entry["sha256"]
        )

    with np.load(result_path / "evidence.npz", allow_pickle=False) as archive:
        evidence_key_match = set(archive.files) == EVIDENCE_KEYS
        arrays = {name: archive[name] for name in archive.files}
    if not evidence_key_match:
        raise ValueError("saved evidence array set does not match the contract")
    if tuple(arrays["process_ids"].astype(str)) != PROCESS_IDS:
        raise ValueError("saved process identifiers do not match the contract")
    if bool(arrays["forecast_executed"]):
        raise ValueError("saved evidence reports a forbidden forecast")

    independent = _independent_truth(config, arrays)
    reconstruction_differences = {
        key: _maximum_difference(arrays[key], expected)
        for key, expected in independent.items()
    }
    expected_covariances = np.zeros((3, 15, 15), dtype=np.float64)
    for index, variance in enumerate((1.0, 16.0, 256.0)):
        expected_covariances[index, 4, 4] = variance
    reconstruction_differences["process_covariances"] = _maximum_difference(
        arrays["process_covariances"], expected_covariances
    )
    reconstruction_differences[
        "process_standard_deviations"
    ] = _maximum_difference(
        arrays["process_standard_deviations"],
        np.asarray((1.0, 4.0, 16.0)),
    )
    reconstruction_maximum = max(reconstruction_differences.values())
    tolerance = float(config["numerical_tolerance"])

    probabilities = np.asarray(
        arrays["posterior_probabilities"], dtype=np.float64
    )
    probability_checks = {
        "shape": probabilities.shape == (8, 3, 540, 3),
        "finite": bool(np.all(np.isfinite(probabilities))),
        "nonnegative": bool(np.all(probabilities >= 0.0)),
        "normalization": bool(
            np.allclose(
                probabilities.sum(axis=-1),
                1.0,
                rtol=0.0,
                atol=tolerance,
            )
        ),
        "global_posterior_shape": arrays[
            "global_posterior_states"
        ].shape
        == (8, 3, 540, 15),
        "global_posterior_finite": bool(
            np.all(np.isfinite(arrays["global_posterior_states"]))
        ),
    }
    events, response_summaries = _independent_response(
        config, probabilities, independent["process_schedule"]
    )
    csv_checks = {
        "switch_response_events": _compare_csv(
            result_path / "switch_response_events.csv", events, tolerance
        ),
        "switch_response_summary": _compare_csv(
            result_path / "switch_response_summary.csv",
            response_summaries,
            tolerance,
        ),
        "daily_probabilities": _compare_csv(
            result_path / "daily_probabilities.csv",
            _daily_rows(arrays),
            tolerance,
        ),
    }
    summary = json.loads(
        (result_path / "summary.json").read_text(encoding="utf-8")
    )
    expected_decision = (
        "supported_under_clean_synthetic_condition"
        if all(row["criterion_passed"] for row in response_summaries)
        else "not_supported_under_clean_synthetic_condition"
    )
    expected_stage_accuracy = _independent_stage_accuracy(
        probabilities, independent["process_schedule"]
    )
    projection_event_count = int(
        np.count_nonzero(
            np.any(
                independent["truth_projection_adjustments"] != 0.0,
                axis=-1,
            )
        )
    )
    maximum_projection_adjustment = float(
        np.max(np.abs(independent["truth_projection_adjustments"]))
    )
    summary_checks = {
        "status": summary.get("status")
        == "complete_pending_independent_verification",
        "conclusion_withheld": summary.get(
            "scientific_conclusion_withheld_until_independent_verification"
        )
        is True,
        "decision": summary.get("decision") == expected_decision,
        "fixed_parameter": summary.get("fixed_parameter_id")
        == "trained_center",
        "candidate_parameters_fixed": summary.get(
            "candidate_parameter_ids"
        )
        == ["trained_center"] * 3,
        "directed_transitions": _dict_rows_equal(
            summary.get("directed_transition_results", []),
            response_summaries,
            tolerance,
        ),
        "stage_accuracy": _dict_rows_equal(
            summary.get("full_stage_descriptive_accuracy", []),
            expected_stage_accuracy,
            tolerance,
        ),
        "projection_count": summary.get(
            "truth_state_domain_gate", {}
        ).get("projection_event_count")
        == projection_event_count,
        "projection_adjustment": abs(
            float(
                summary.get("truth_state_domain_gate", {}).get(
                    "maximum_absolute_projection_adjustment", np.inf
                )
            )
            - maximum_projection_adjustment
        )
        <= tolerance,
        "projection_gate_passed": summary.get(
            "truth_state_domain_gate", {}
        ).get("passed")
        is True,
        "forbidden_scope": summary.get("forbidden_scope_checks")
        == {
            "forecast_imported": False,
            "forecast_executed": False,
            "future_observations_used": False,
            "parameter_switching": False,
            "parameter_estimation": False,
        },
    }
    figure_checks = {}
    for name in ("probability_response.png", "response_summary.png"):
        try:
            image = matplotlib_image.imread(result_path / name)
            figure_checks[name] = bool(
                image.size > 0
                and image.ndim in (2, 3)
                and np.all(np.isfinite(image))
            )
        except Exception:
            figure_checks[name] = False

    required_file_checks = {
        name: (result_path / name).is_file()
        for name in config["required_result_files"]
    }
    passed = (
        config_matches_frozen
        and all(source_hash_checks.values())
        and bool(snapshot_source_checks)
        and all(snapshot_source_checks.values())
        and all(checksum_checks.values())
        and all(required_file_checks.values())
        and evidence_key_match
        and reconstruction_maximum <= tolerance
        and projection_event_count == 0
        and maximum_projection_adjustment == 0.0
        and all(probability_checks.values())
        and len(events) == 48
        and all(row["event_count"] == 16 for row in response_summaries)
        and all(csv_checks.values())
        and all(summary_checks.values())
        and all(figure_checks.values())
    )
    report = {
        "experiment_id": EXPERIMENT_ID,
        "status": "passed" if passed else "failed",
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "production_experiment_module_imported": False,
        "production_runner_imported": False,
        "forecast_module_imported": False,
        "config_matches_frozen": config_matches_frozen,
        "source_hash_checks": source_hash_checks,
        "source_snapshot_checks": snapshot_source_checks,
        "artifact_checksum_checks": checksum_checks,
        "required_file_checks": required_file_checks,
        "evidence_key_match": evidence_key_match,
        "truth_reconstruction_maximum_absolute_difference": (
            reconstruction_maximum
        ),
        "truth_reconstruction_maximum_absolute_differences": (
            reconstruction_differences
        ),
        "truth_transition_count_recomputed": 12960,
        "truth_projection_event_count_recomputed": projection_event_count,
        "truth_projection_maximum_absolute_adjustment_recomputed": (
            maximum_projection_adjustment
        ),
        "probability_checks": probability_checks,
        "response_event_count_recomputed": len(events),
        "directed_transition_results_recomputed": response_summaries,
        "independently_recomputed_decision": expected_decision,
        "csv_checks": csv_checks,
        "summary_checks": summary_checks,
        "figure_decode_checks": figure_checks,
        "numerical_tolerance": tolerance,
        "evidence_sha256": _sha256(result_path / "evidence.npz"),
    }
    _seal_verification_report(verification_path, report)
    if not passed:
        raise SystemExit(1)
    return report


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--result-dir", type=Path, default=DEFAULT_RESULT)
    parser.add_argument(
        "--verification-dir", type=Path, default=DEFAULT_VERIFICATION
    )
    args = parser.parse_args()
    report = verify(args.result_dir, args.verification_dir)
    print(json.dumps(report, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()

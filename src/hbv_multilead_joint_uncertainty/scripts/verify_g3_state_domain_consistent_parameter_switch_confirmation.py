"""Independent verifier for parameter switching without truth-state clipping."""

from __future__ import annotations

import csv
import hashlib
import json
import os
import sys
import uuid
from datetime import datetime, timezone
from itertools import combinations
from pathlib import Path

import matplotlib.image as matplotlib_image
import numpy as np
from scipy.stats import beta as beta_distribution


PROJECT_ROOT = Path(__file__).resolve().parents[3]
SRC_ROOT = PROJECT_ROOT / "src"
if str(SRC_ROOT) not in sys.path:
    sys.path.insert(0, str(SRC_ROOT))

from scl_hydro.hbv_lite_numpy import simulate_hbv_lite  # noqa: E402


EXPERIMENT_ID = "g3_state_domain_consistent_parameter_switch_confirmation_v01"
CONFIG_SHA256 = "a7c974608a647f7eade14a7fa0ee443f6148950cf7175103b21d91c6bb344059"
FROZEN_CONFIG = (
    PROJECT_ROOT
    / "src"
    / "hbv_multilead_joint_uncertainty"
    / "configs"
    / f"{EXPERIMENT_ID}.json"
)
DEFAULT_RESULT = (
    PROJECT_ROOT / "results" / "23_hbv_multilead_joint_uncertainty" / EXPERIMENT_ID
)
DEFAULT_VISUAL_REVIEW = DEFAULT_RESULT.with_name(f"{EXPERIMENT_ID}_visual_review_v01")
DEFAULT_VERIFICATION = DEFAULT_RESULT.with_name(
    f"{EXPERIMENT_ID}_independent_verification_v01"
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
EVIDENCE_KEYS = {
    "block_ids",
    "parameter_ids",
    "parameter_vectors",
    "forcing_blocks",
    "parameter_schedule",
    "process_standard_normals",
    "observation_standard_normals",
    "initial_states",
    "initial_covariances",
    "deterministic_truth_states",
    "truth_process_perturbations",
    "truth_projection_adjustments",
    "switch_boundary_projection_adjustments",
    "truth_states",
    "truth_discharge",
    "observations",
    "posterior_probabilities",
    "global_posterior_states",
    "observation_standard_deviation",
    "fixed_process_standard_deviation",
}


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def assert_verification_path_absent(path: Path = DEFAULT_VERIFICATION) -> None:
    if path.exists():
        raise FileExistsError(f"verification path already exists: {path}")


def verify_artifact_checksums(result_dir: Path) -> dict[str, bool]:
    manifest_path = result_dir / "checksums.json"
    if not manifest_path.is_file():
        raise FileNotFoundError("formal checksum manifest is missing")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if not isinstance(manifest, dict) or not manifest:
        raise ValueError("formal checksum manifest is malformed")
    checks = {}
    for relative, expected in manifest.items():
        path = result_dir / Path(relative)
        checks[relative] = path.is_file() and _sha256(path) == str(expected)
    actual = {
        path.relative_to(result_dir).as_posix()
        for path in result_dir.rglob("*")
        if path.is_file() and path.name != "checksums.json"
    }
    if actual != set(manifest):
        checks["__file_set__"] = False
    else:
        checks["__file_set__"] = True
    return checks


def verify_visual_review_checksums(visual_dir: Path) -> dict[str, bool]:
    manifest_path = visual_dir / "checksums.json"
    if not manifest_path.is_file():
        raise FileNotFoundError("visual-review checksum manifest is missing")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    expected_names = {"visual_review.csv", "review_manifest.json"}
    if set(manifest) != expected_names:
        raise ValueError("visual-review checksum manifest has an unexpected file set")
    return {
        name: (visual_dir / name).is_file()
        and _sha256(visual_dir / name) == str(manifest[name])
        for name in expected_names
    }


def _parameters_from_config(config: dict) -> tuple[tuple[str, ...], dict[str, dict[str, float]]]:
    identifiers = tuple(str(row["parameter_id"]) for row in config["parameter_candidates"])
    if len(identifiers) != 3 or len(set(identifiers)) != 3:
        raise ValueError("frozen parameter identifier contract failed")
    parameters = {
        str(row["parameter_id"]): {
            name: float(row[name]) for name in PARAMETER_NAMES
        }
        for row in config["parameter_candidates"]
    }
    if len({parameters[value]["parFC"] for value in identifiers}) != 1:
        raise ValueError("frozen candidates do not share parFC")
    if len({parameters[value]["parCWH"] for value in identifiers}) != 1:
        raise ValueError("frozen candidates do not share parCWH")
    return identifiers, parameters


def _project_state(state: np.ndarray, parameters: dict[str, float]) -> np.ndarray:
    values = np.asarray(state, dtype=np.float64).copy()
    if values.shape != (15,) or not np.all(np.isfinite(values)):
        raise ValueError("independent state shape or finiteness check failed")
    snow = max(float(values[0]), 0.0)
    values[0] = snow
    values[1] = np.clip(values[1], 0.0, parameters["parCWH"] * snow)
    values[2] = np.clip(values[2], 1e-5, parameters["parFC"])
    values[3:] = np.maximum(values[3:], 0.0)
    return values


def _advance_state(
    state: np.ndarray, forcing: np.ndarray, parameters: dict[str, float]
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
        [final_stores[name] for name in HYDROLOGIC_STATE_NAMES], dtype=np.float64
    )
    routing_memory = np.concatenate(
        (np.asarray([raw_discharge[0]], dtype=np.float64), current[5:14])
    )
    return _project_state(np.concatenate((hydrologic, routing_memory)), parameters)


def _routed_discharge(state: np.ndarray, lag_time: float) -> float:
    count = int(np.ceil(float(lag_time)))
    weights = np.arange(count, 0, -1, dtype=np.float64)
    weights /= weights.sum()
    return float(weights @ state[5 : 5 + count])


def _generate_forcing(config: dict, seeds: list[int]) -> np.ndarray:
    forcing = config["forcing"]
    total_days = int(forcing["warmup_days"]) + int(forcing["assimilation_days"])
    blocks = []
    for seed in seeds:
        generator = np.random.default_rng(int(seed))
        rain = float(forcing["rain_floor_mm_day"]) + generator.gamma(
            float(forcing["rain_gamma_shape"]),
            float(forcing["rain_gamma_scale_mm_day"]),
            total_days,
        )
        blocks.append(
            np.column_stack(
                (
                    rain,
                    np.full(total_days, float(forcing["potential_evaporation_mm_day"])),
                    np.full(total_days, float(forcing["temperature_celsius"])),
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


def _warmup_state(forcing: np.ndarray, parameters: dict[str, float]) -> np.ndarray:
    state = np.zeros(15, dtype=np.float64)
    state[:5] = (0.0, 0.0, parameters["parFC"] * 0.3, 5.0, 10.0)
    for daily_forcing in forcing:
        state = _advance_state(state, daily_forcing, parameters)
    return state


def _independent_truth(config: dict, arrays: dict[str, np.ndarray]) -> dict[str, np.ndarray]:
    identifiers, parameters = _parameters_from_config(config)
    forcing = _generate_forcing(
        config, config["formal_confirmation_seeds"]["forcing"]
    )
    schedule = _build_schedule(config)
    active_days = int(config["forcing"]["assimilation_days"])
    warmup_days = int(config["forcing"]["warmup_days"])
    block_count = int(config["population"]["matched_block_count"])
    process_normals = np.asarray(
        [
            np.random.default_rng(seed).standard_normal(active_days)
            for seed in config["formal_confirmation_seeds"]["process_noise"]
        ],
        dtype=np.float64,
    )
    observation_normals = np.asarray(
        [
            np.random.default_rng(seed).standard_normal(active_days)
            for seed in config["formal_confirmation_seeds"]["observation_noise"]
        ],
        dtype=np.float64,
    )
    initial_states = np.empty((block_count, 15), dtype=np.float64)
    initial_covariances = np.empty((block_count, 15, 15), dtype=np.float64)
    shape = (block_count, 3, active_days, 15)
    deterministic = np.empty(shape, dtype=np.float64)
    perturbations = np.zeros(shape, dtype=np.float64)
    adjustments = np.empty(shape, dtype=np.float64)
    boundary_adjustments = np.zeros(shape, dtype=np.float64)
    truth_states = np.empty(shape, dtype=np.float64)
    truth_discharge = np.empty((block_count, 3, active_days), dtype=np.float64)
    observations = np.empty_like(truth_discharge)
    covariance_fraction = float(config["filter"]["initial_covariance_fraction"])
    process_standard_deviation = float(
        config["fixed_process_noise"]["standard_deviation_mm_day"]
    )
    observation_standard_deviation = float(arrays["observation_standard_deviation"])
    reference_parameters = parameters[identifiers[1]]

    for block in range(block_count):
        initial = _warmup_state(forcing[block, :warmup_days], reference_parameters)
        initial_states[block] = initial
        scales = np.maximum(np.abs(initial), 1.0)
        initial_covariances[block] = np.diag(np.square(covariance_fraction * scales))
        active_forcing = forcing[block, warmup_days:]
        for trial in range(3):
            state = initial.copy()
            for day in range(active_days):
                identifier = str(schedule[trial, day])
                active_parameters = parameters[identifier]
                if day > 0 and schedule[trial, day] != schedule[trial, day - 1]:
                    boundary_adjustments[block, trial, day] = (
                        _project_state(state, active_parameters) - state
                    )
                deterministic_state = _advance_state(
                    state, active_forcing[day], active_parameters
                )
                perturbation = np.zeros(15, dtype=np.float64)
                perturbation[4] = (
                    process_normals[block, day] * process_standard_deviation
                )
                unprojected = deterministic_state + perturbation
                adjustment = _project_state(unprojected, active_parameters) - unprojected
                deterministic[block, trial, day] = deterministic_state
                perturbations[block, trial, day] = perturbation
                adjustments[block, trial, day] = adjustment
                state = unprojected
                truth_states[block, trial, day] = state
                truth_discharge[block, trial, day] = _routed_discharge(
                    state, active_parameters["lag_time"]
                )
            observations[block, trial] = (
                truth_discharge[block, trial]
                + observation_standard_deviation * observation_normals[block]
            )
    return {
        "forcing_blocks": forcing,
        "parameter_schedule": schedule,
        "process_standard_normals": process_normals,
        "observation_standard_normals": observation_normals,
        "initial_states": initial_states,
        "initial_covariances": initial_covariances,
        "deterministic_truth_states": deterministic,
        "truth_process_perturbations": perturbations,
        "truth_projection_adjustments": adjustments,
        "switch_boundary_projection_adjustments": boundary_adjustments,
        "truth_states": truth_states,
        "truth_discharge": truth_discharge,
        "observations": observations,
    }


def independent_first_clear_run(
    probabilities: np.ndarray,
    true_index: int,
    consecutive_days: int,
    window_days: int,
    probability_threshold: float,
    margin_threshold: float,
) -> int | None:
    values = np.asarray(probabilities, dtype=np.float64)
    window = int(window_days)
    run = int(consecutive_days)
    true_probability = values[:window, int(true_index)]
    runner_up = np.max(np.delete(values[:window], int(true_index), axis=1), axis=1)
    clear = (true_probability > float(probability_threshold)) & (
        true_probability - runner_up >= float(margin_threshold)
    )
    for start in range(window - run + 1):
        if all(bool(value) for value in clear[start : start + run]):
            return start
    return None


def _exact_interval(successes: int, total: int) -> tuple[float, float]:
    count = int(successes)
    size = int(total)
    lower = (
        0.0
        if count == 0
        else float(beta_distribution.ppf(0.025, count, size - count + 1))
    )
    upper = (
        1.0
        if count == size
        else float(beta_distribution.ppf(0.975, count + 1, size - count))
    )
    return lower, upper


def _transition_order(identifiers: tuple[str, ...]) -> tuple[tuple[str, str], ...]:
    return (
        (identifiers[0], identifiers[1]),
        (identifiers[1], identifiers[2]),
        (identifiers[2], identifiers[0]),
    )


def _independent_numeric_response(
    config: dict,
    probabilities: np.ndarray,
    schedule: np.ndarray,
) -> tuple[list[dict], list[dict]]:
    identifiers, _ = _parameters_from_config(config)
    index = {identifier: position for position, identifier in enumerate(identifiers)}
    rule = config["numerical_response_rule"]
    window = int(rule["response_window_days"])
    consecutive = int(rule["consecutive_clear_dominance_days"])
    probability_threshold = float(
        rule["minimum_new_true_candidate_probability_exclusive"]
    )
    margin_threshold = float(
        rule["minimum_probability_margin_over_runner_up_inclusive"]
    )
    events: list[dict] = []
    for block in range(probabilities.shape[0]):
        for trial in range(schedule.shape[0]):
            boundaries = np.flatnonzero(schedule[trial, 1:] != schedule[trial, :-1]) + 1
            for boundary in boundaries:
                old_identifier = str(schedule[trial, boundary - 1])
                new_identifier = str(schedule[trial, boundary])
                response = probabilities[block, trial, boundary : boundary + window]
                true_probability = response[:, index[new_identifier]]
                runner_up = np.max(
                    np.delete(response, index[new_identifier], axis=1), axis=1
                )
                start = independent_first_clear_run(
                    response,
                    index[new_identifier],
                    consecutive,
                    window,
                    probability_threshold,
                    margin_threshold,
                )
                row = {
                    "event_id": f"block_{block + 1:02d}_trial_{trial + 1}_switch_day_{boundary + 1}",
                    "block_index": block,
                    "trial_index": trial,
                    "switch_day_index": int(boundary),
                    "switch_day_number": int(boundary + 1),
                    "old_parameter_id": old_identifier,
                    "new_parameter_id": new_identifier,
                    "transition_label": f"{old_identifier}_to_{new_identifier}",
                    "numerical_success": start is not None,
                    "response_start_day": None if start is None else int(start),
                    "new_candidate_top_ranked_days_in_window": int(
                        np.count_nonzero(
                            np.argmax(response, axis=1) == index[new_identifier]
                        )
                    ),
                    "new_candidate_probability_above_half_days_in_window": int(
                        np.count_nonzero(true_probability > 0.5)
                    ),
                    "minimum_new_candidate_probability_in_window": float(np.min(true_probability)),
                    "maximum_new_candidate_probability_in_window": float(np.max(true_probability)),
                    "minimum_probability_margin_in_window": float(
                        np.min(true_probability - runner_up)
                    ),
                    "maximum_probability_margin_in_window": float(
                        np.max(true_probability - runner_up)
                    ),
                    "minimum_probability_in_qualifying_run": None,
                    "minimum_margin_in_qualifying_run": None,
                }
                if start is not None:
                    selected = slice(start, start + consecutive)
                    row["minimum_probability_in_qualifying_run"] = float(
                        np.min(true_probability[selected])
                    )
                    row["minimum_margin_in_qualifying_run"] = float(
                        np.min((true_probability - runner_up)[selected])
                    )
                events.append(row)
    summaries = []
    for old_identifier, new_identifier in _transition_order(identifiers):
        selected = [
            row
            for row in events
            if row["old_parameter_id"] == old_identifier
            and row["new_parameter_id"] == new_identifier
        ]
        successes = sum(bool(row["numerical_success"]) for row in selected)
        lower, upper = _exact_interval(successes, len(selected))
        starts = [
            int(row["response_start_day"])
            for row in selected
            if row["response_start_day"] is not None
        ]
        summaries.append(
            {
                "old_parameter_id": old_identifier,
                "new_parameter_id": new_identifier,
                "transition_label": f"{old_identifier}_to_{new_identifier}",
                "event_count": len(selected),
                "numerically_successful_event_count": successes,
                "numerical_response_fraction": successes / len(selected),
                "exact_interval_lower": lower,
                "exact_interval_upper": upper,
                "median_response_start_day": None if not starts else float(np.median(starts)),
                "maximum_response_start_day": None if not starts else int(max(starts)),
                "numerical_criterion_passed": (
                    successes
                    >= int(rule["minimum_successful_events_per_directed_transition"])
                    and lower
                    > float(rule["minimum_exact_interval_lower_bound_exclusive"])
                ),
            }
        )
    return events, summaries


def _independent_full_stage(
    config: dict, probabilities: np.ndarray, schedule: np.ndarray
) -> list[dict]:
    identifiers, _ = _parameters_from_config(config)
    index = {identifier: position for position, identifier in enumerate(identifiers)}
    top = np.argmax(probabilities, axis=-1)
    rows = []
    for identifier in identifiers:
        mask = np.broadcast_to(schedule == identifier, probabilities.shape[:3])
        true_index = index[identifier]
        rows.append(
            {
                "true_parameter_id": identifier,
                "day_count": int(np.count_nonzero(mask)),
                "top_ranked_day_count": int(np.count_nonzero((top == true_index) & mask)),
                "top_ranked_fraction": float(np.mean(top[mask] == true_index)),
                "mean_true_candidate_probability": float(
                    np.mean(probabilities[..., true_index][mask])
                ),
            }
        )
    return rows


def _maximum_difference(actual: np.ndarray, expected: np.ndarray) -> float:
    left = np.asarray(actual)
    right = np.asarray(expected)
    if left.shape != right.shape:
        return float("inf")
    if left.dtype.kind in "USO" or right.dtype.kind in "USO":
        return 0.0 if np.array_equal(left.astype(str), right.astype(str)) else float("inf")
    return float(np.max(np.abs(left.astype(np.float64) - right.astype(np.float64))))


def _compare_csv(path: Path, expected_rows: list[dict], tolerance: float) -> bool:
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
                if actual_value.lower() != str(expected_value).lower():
                    return False
            elif isinstance(expected_value, (int, float, np.integer, np.floating)):
                if abs(float(actual_value) - float(expected_value)) > tolerance:
                    return False
            elif actual_value != str(expected_value):
                return False
    return True


def _daily_rows(arrays: dict[str, np.ndarray]) -> list[dict]:
    identifiers = tuple(arrays["parameter_ids"].astype(str))
    index = {identifier: position for position, identifier in enumerate(identifiers)}
    rows = []
    for block in range(len(arrays["block_ids"])):
        for trial in range(arrays["parameter_schedule"].shape[0]):
            for day in range(arrays["parameter_schedule"].shape[1]):
                true_identifier = str(arrays["parameter_schedule"][trial, day])
                probabilities = arrays["posterior_probabilities"][block, trial, day]
                row = {
                    "block_index": block,
                    "block_id": str(arrays["block_ids"][block]),
                    "trial_index": trial,
                    "day_index": day,
                    "day_number": day + 1,
                    "true_parameter_id": true_identifier,
                    "true_candidate_probability": float(probabilities[index[true_identifier]]),
                    "top_ranked_parameter_id": str(identifiers[int(np.argmax(probabilities))]),
                }
                for candidate_index, identifier in enumerate(identifiers):
                    row[f"probability_{identifier}"] = float(probabilities[candidate_index])
                rows.append(row)
    return rows


def _dict_rows_equal(left: list[dict], right: list[dict], tolerance: float) -> bool:
    if len(left) != len(right):
        return False
    for actual, expected in zip(left, right):
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
            elif isinstance(expected_value, (int, float)):
                if abs(float(actual_value) - float(expected_value)) > tolerance:
                    return False
            elif actual_value != expected_value:
                return False
    return True


def _load_visual_review(
    result_path: Path, visual_path: Path, numeric_events: list[dict], config: dict
) -> tuple[list[dict], dict]:
    panel_manifest = json.loads(
        (result_path / "event_panel_manifest.json").read_text(encoding="utf-8")
    )
    review_manifest = json.loads(
        (visual_path / "review_manifest.json").read_text(encoding="utf-8")
    )
    with (visual_path / "visual_review.csv").open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    allowed = set(config["visual_review_rule"]["allowed_labels"])
    panel_by_review = {row["review_id"]: row for row in panel_manifest["panels"]}
    event_by_id = {row["event_id"]: row for row in numeric_events}
    if len(rows) != 48 or len(panel_by_review) != 48 or len(event_by_id) != 48:
        raise ValueError("visual review must contain forty-eight unique events")
    if set(row["review_id"] for row in rows) != set(panel_by_review):
        raise ValueError("visual review identifiers do not match panel manifest")
    if set(row["event_id"] for row in rows) != set(event_by_id):
        raise ValueError("visual review event identifiers do not match numerical events")
    if any(row["visual_label"] not in allowed for row in rows):
        raise ValueError("visual review contains an invalid label")
    if any(not row["visible_reason"].strip() for row in rows):
        raise ValueError("visual review contains an empty reason")
    if any(row["reviewed_before_numeric_unblinding"].lower() != "true" for row in rows):
        raise ValueError("visual review was not sealed before numerical unblinding")
    if review_manifest.get("numeric_decisions_opened_before_labels") is not False:
        raise ValueError("visual review manifest reports non-blinded review")
    if review_manifest.get("review_count") != 48:
        raise ValueError("visual review manifest count mismatch")
    if review_manifest.get("visual_review_csv_sha256") != _sha256(
        visual_path / "visual_review.csv"
    ):
        raise ValueError("visual review CSV hash mismatch in review manifest")
    if review_manifest.get("event_panel_manifest_sha256") != _sha256(
        result_path / "event_panel_manifest.json"
    ):
        raise ValueError("visual review source panel manifest hash mismatch")
    for row in rows:
        panel = panel_by_review[row["review_id"]]
        if row["event_id"] != panel["event_id"]:
            raise ValueError("visual review event mapping mismatch")
        panel_path = result_path / panel["panel_relative_path"]
        if _sha256(panel_path) != panel["panel_sha256"]:
            raise ValueError("visual review panel hash mismatch")
    return rows, review_manifest


def combine_numeric_and_visual_events(
    numeric_events: list[dict], visual_rows: list[dict], config: dict
) -> tuple[list[dict], list[dict]]:
    visual_by_event = {row["event_id"]: row for row in visual_rows}
    combined = []
    for event in numeric_events:
        visual = visual_by_event[event["event_id"]]
        final_success = bool(event["numerical_success"]) and visual["visual_label"] == "clear_success"
        combined.append(
            {
                **event,
                "review_id": visual["review_id"],
                "visual_label": visual["visual_label"],
                "visible_reason": visual["visible_reason"],
                "final_success": final_success,
            }
        )
    identifiers, _ = _parameters_from_config(config)
    rule = config["numerical_response_rule"]
    summaries = []
    for old_identifier, new_identifier in _transition_order(identifiers):
        selected = [
            row
            for row in combined
            if row["old_parameter_id"] == old_identifier
            and row["new_parameter_id"] == new_identifier
        ]
        successes = sum(bool(row["final_success"]) for row in selected)
        lower, upper = _exact_interval(successes, len(selected))
        summaries.append(
            {
                "old_parameter_id": old_identifier,
                "new_parameter_id": new_identifier,
                "transition_label": f"{old_identifier}_to_{new_identifier}",
                "event_count": len(selected),
                "final_successful_event_count": successes,
                "final_success_fraction": successes / len(selected),
                "exact_interval_lower": lower,
                "exact_interval_upper": upper,
                "criterion_passed": (
                    successes
                    >= int(rule["minimum_successful_events_per_directed_transition"])
                    and lower
                    > float(rule["minimum_exact_interval_lower_bound_exclusive"])
                ),
            }
        )
    return combined, summaries


def _seal_report(verification_path: Path, report: dict) -> None:
    token = uuid.uuid4().hex
    staging = verification_path.with_name(f"{verification_path.name}.staging.{token}")
    incomplete = verification_path.with_name(f"{verification_path.name}.incomplete.{token}")
    staging.mkdir(parents=False)
    try:
        report_path = staging / "independent_verification.json"
        report_path.write_text(
            json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8"
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
            raise FileExistsError("verification path appeared during audit")
        os.replace(staging, verification_path)
    except Exception:
        if staging.exists() and not incomplete.exists():
            os.replace(staging, incomplete)
        raise


def verify(
    result_dir: Path = DEFAULT_RESULT,
    visual_review_dir: Path = DEFAULT_VISUAL_REVIEW,
    verification_dir: Path = DEFAULT_VERIFICATION,
) -> dict:
    result_path = Path(result_dir).resolve()
    visual_path = Path(visual_review_dir).resolve()
    verification_path = Path(verification_dir).resolve()
    if result_path != DEFAULT_RESULT.resolve():
        raise ValueError("result path is not the frozen experiment path")
    if visual_path != DEFAULT_VISUAL_REVIEW.resolve():
        raise ValueError("visual-review path is not the frozen path")
    if verification_path != DEFAULT_VERIFICATION.resolve():
        raise ValueError("verification path is not the frozen path")
    assert_verification_path_absent(verification_path)
    if not result_path.is_dir() or not visual_path.is_dir():
        raise FileNotFoundError("formal result or visual review is missing")

    artifact_checks = verify_artifact_checksums(result_path)
    visual_checks = verify_visual_review_checksums(visual_path)
    if _sha256(FROZEN_CONFIG) != CONFIG_SHA256:
        raise ValueError("frozen config changed before verification")
    frozen_config = json.loads(FROZEN_CONFIG.read_text(encoding="utf-8"))
    config = json.loads((result_path / "config_snapshot.json").read_text(encoding="utf-8"))
    config_matches_frozen = config == frozen_config
    source_hash_checks = {}
    for key in ("parameter_source", "observation_noise_source"):
        source_path = PROJECT_ROOT / config[key]["path"]
        source_hash_checks[key] = (
            source_path.is_file() and _sha256(source_path) == config[key]["sha256"]
        )
    source_manifest = json.loads(
        (result_path / "source_manifest.json").read_text(encoding="utf-8")
    )
    current_source_checks = {
        relative: (PROJECT_ROOT / relative).is_file()
        and _sha256(PROJECT_ROOT / relative) == expected
        for relative, expected in source_manifest["files"].items()
    }

    with np.load(result_path / "evidence.npz", allow_pickle=False) as archive:
        evidence_key_match = set(archive.files) == EVIDENCE_KEYS
        arrays = {name: archive[name] for name in archive.files}
    if not evidence_key_match:
        raise ValueError("saved evidence key set changed")
    identifiers, parameters = _parameters_from_config(config)
    expected_vectors = np.asarray(
        [[parameters[identifier][name] for name in PARAMETER_NAMES] for identifier in identifiers],
        dtype=np.float64,
    )
    identity_checks = {
        "parameter_ids": tuple(arrays["parameter_ids"].astype(str)) == identifiers,
        "parameter_vectors": _maximum_difference(arrays["parameter_vectors"], expected_vectors) == 0.0,
        "fixed_process_standard_deviation": float(arrays["fixed_process_standard_deviation"])
        == float(config["fixed_process_noise"]["standard_deviation_mm_day"]),
    }
    independent = _independent_truth(config, arrays)
    reconstruction_differences = {
        key: _maximum_difference(arrays[key], value)
        for key, value in independent.items()
    }
    reconstruction_maximum = max(reconstruction_differences.values())
    tolerance = float(config["numerical_tolerance"])
    probabilities = np.asarray(arrays["posterior_probabilities"], dtype=np.float64)
    probability_checks = {
        "shape": probabilities.shape == (8, 3, 540, 3),
        "finite": bool(np.all(np.isfinite(probabilities))),
        "nonnegative": bool(np.all(probabilities >= 0.0)),
        "normalization": bool(
            np.allclose(probabilities.sum(axis=-1), 1.0, rtol=0.0, atol=tolerance)
        ),
        "global_posterior_shape": arrays["global_posterior_states"].shape
        == (8, 3, 540, 15),
        "global_posterior_finite": bool(np.all(np.isfinite(arrays["global_posterior_states"]))),
    }
    numeric_events, numeric_summaries = _independent_numeric_response(
        config, probabilities, independent["parameter_schedule"]
    )
    full_stage = _independent_full_stage(
        config, probabilities, independent["parameter_schedule"]
    )
    visual_rows, review_manifest = _load_visual_review(
        result_path, visual_path, numeric_events, config
    )
    combined_events, final_summaries = combine_numeric_and_visual_events(
        numeric_events, visual_rows, config
    )
    final_decision = (
        "all_three_parameter_switch_directions_supported"
        if all(row["criterion_passed"] for row in final_summaries)
        else "not_all_parameter_switch_directions_supported"
    )
    csv_checks = {
        "numeric_events": _compare_csv(
            result_path / "switch_response_events_numeric.csv", numeric_events, tolerance
        ),
        "numeric_summary": _compare_csv(
            result_path / "switch_response_summary_numeric.csv", numeric_summaries, tolerance
        ),
        "daily_probabilities": _compare_csv(
            result_path / "daily_probabilities.csv", _daily_rows(arrays), tolerance
        ),
    }
    summary = json.loads((result_path / "summary.json").read_text(encoding="utf-8"))
    truth_projection_count = int(
        np.count_nonzero(
            np.any(independent["truth_projection_adjustments"] != 0.0, axis=-1)
        )
    )
    boundary_projection_count = int(
        np.count_nonzero(
            np.any(
                independent["switch_boundary_projection_adjustments"] != 0.0,
                axis=-1,
            )
        )
    )
    summary_checks = {
        "status": summary.get("status")
        == "complete_pending_blinded_visual_review_and_independent_verification",
        "conclusion_withheld": summary.get("scientific_conclusion_withheld") is True,
        "numeric_summaries": _dict_rows_equal(
            summary.get("directed_transition_numeric_results", []),
            numeric_summaries,
            tolerance,
        ),
        "full_stage": _dict_rows_equal(
            summary.get("full_stage_descriptive_accuracy", []), full_stage, tolerance
        ),
        "truth_projection": summary.get("truth_projection_gate", {}).get(
            "projection_event_count"
        )
        == truth_projection_count,
        "boundary_projection": summary.get(
            "switch_boundary_projection_gate", {}
        ).get("projection_event_count")
        == boundary_projection_count,
        "forbidden_scope": summary.get("forbidden_scope_checks")
        == config["forbidden_scope"],
    }
    panel_manifest = json.loads(
        (result_path / "event_panel_manifest.json").read_text(encoding="utf-8")
    )
    panel_checks = {}
    for row in panel_manifest["panels"]:
        path = result_path / row["panel_relative_path"]
        try:
            image = matplotlib_image.imread(path)
            panel_checks[row["review_id"]] = bool(
                image.size > 0
                and image.ndim in (2, 3)
                and np.all(np.isfinite(image))
                and _sha256(path) == row["panel_sha256"]
            )
        except Exception:
            panel_checks[row["review_id"]] = False
    required_file_checks = {
        name: (result_path / name).is_file() for name in config["required_result_files"]
    }
    passed = (
        config_matches_frozen
        and all(source_hash_checks.values())
        and all(current_source_checks.values())
        and all(artifact_checks.values())
        and all(visual_checks.values())
        and all(required_file_checks.values())
        and evidence_key_match
        and all(identity_checks.values())
        and reconstruction_maximum <= tolerance
        and truth_projection_count == 0
        and boundary_projection_count == 0
        and float(np.max(np.abs(independent["truth_projection_adjustments"]))) == 0.0
        and float(
            np.max(np.abs(independent["switch_boundary_projection_adjustments"]))
        )
        == 0.0
        and all(probability_checks.values())
        and len(numeric_events) == 48
        and all(row["event_count"] == 16 for row in numeric_summaries)
        and all(csv_checks.values())
        and all(summary_checks.values())
        and len(panel_checks) == 48
        and all(panel_checks.values())
        and len(combined_events) == 48
        and review_manifest.get("review_count") == 48
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
        "current_source_hash_checks": current_source_checks,
        "artifact_checksum_checks": artifact_checks,
        "visual_review_checksum_checks": visual_checks,
        "required_file_checks": required_file_checks,
        "evidence_key_match": evidence_key_match,
        "identity_checks": identity_checks,
        "truth_reconstruction_maximum_absolute_difference": reconstruction_maximum,
        "truth_reconstruction_maximum_absolute_differences": reconstruction_differences,
        "truth_transition_count_recomputed": 12960,
        "truth_projection_event_count_recomputed": truth_projection_count,
        "switch_boundary_projection_event_count_recomputed": boundary_projection_count,
        "truth_projection_maximum_absolute_adjustment_recomputed": float(
            np.max(np.abs(independent["truth_projection_adjustments"]))
        ),
        "switch_boundary_projection_maximum_absolute_adjustment_recomputed": float(
            np.max(np.abs(independent["switch_boundary_projection_adjustments"]))
        ),
        "probability_checks": probability_checks,
        "numeric_response_event_count_recomputed": len(numeric_events),
        "numeric_directed_transition_results_recomputed": numeric_summaries,
        "visual_label_counts": {
            label: sum(row["visual_label"] == label for row in visual_rows)
            for label in config["visual_review_rule"]["allowed_labels"]
        },
        "numeric_visual_disagreements": [
            {
                "event_id": row["event_id"],
                "numerical_success": row["numerical_success"],
                "visual_label": row["visual_label"],
            }
            for row in combined_events
            if bool(row["numerical_success"])
            != (row["visual_label"] == "clear_success")
        ],
        "final_directed_transition_results": final_summaries,
        "independently_recomputed_decision": final_decision,
        "full_stage_descriptive_accuracy_recomputed": full_stage,
        "csv_checks": csv_checks,
        "summary_checks": summary_checks,
        "event_panel_decode_checks": panel_checks,
        "numerical_tolerance": tolerance,
        "evidence_sha256": _sha256(result_path / "evidence.npz"),
        "visual_review_sha256": _sha256(visual_path / "visual_review.csv"),
    }
    _seal_report(verification_path, report)
    if not passed:
        raise SystemExit(1)
    return report


def main() -> None:
    report = verify()
    print(json.dumps(report, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()

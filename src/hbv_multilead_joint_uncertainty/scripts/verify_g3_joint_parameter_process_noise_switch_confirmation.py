"""Independent verifier for joint parameter and process-noise switching.

Rebuilds every truth array from sealed inputs with the independent
``scl_hydro`` HBV-lite implementation and re-applies both frozen margin rules
to the sealed posterior probabilities.  It never imports the production
experiment core, the production runner, or any forecast module.
"""

from __future__ import annotations

import csv
import hashlib
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
from scipy.stats import beta as beta_distribution

PROJECT_ROOT = Path(__file__).resolve().parents[3]
SRC_ROOT = PROJECT_ROOT / "src"
if str(SRC_ROOT) not in sys.path:
    sys.path.insert(0, str(SRC_ROOT))

from scl_hydro.hbv_lite_numpy import simulate_hbv_lite  # noqa: E402

EXPERIMENT_ID = "g3_joint_parameter_process_noise_switch_confirmation_v04"
CONFIG_SHA256 = "2ca2c7cd288614f79d1a772c81148fa37742b9275820a2b561a78c70376e8763"
PRODUCTION_EXPERIMENT_MODULES = (
    "hbv_multilead_joint_uncertainty.joint_parameter_process_noise_switch_confirmation",
    "hbv_multilead_joint_uncertainty.state_domain_consistent_parameter_switch_confirmation",
    "hbv_multilead_joint_uncertainty.methods",
    "hbv_multilead_joint_uncertainty.synthetic_truth",
)
PRODUCTION_RUNNER_MODULE = (
    "hbv_multilead_joint_uncertainty.scripts."
    "run_g3_joint_parameter_process_noise_switch_confirmation"
)
PROJECT_NAMESPACES = ("hbv_joint_uncertainty", "hbv_multilead_joint_uncertainty", "scl_hydro")
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
    "parTT", "parCFMAX", "parCFR", "parCWH", "parFC", "parBETA", "parLP",
    "parK0", "parK1", "parUZL", "parPERC", "parK2", "lag_time",
)
HYDROLOGIC_STATE_NAMES = ("SNOWPACK", "MELTWATER", "SM", "SUZ", "SLZ")
EVIDENCE_KEYS = {
    "block_ids", "parameter_ids", "process_ids", "candidate_parameter_ids",
    "candidate_process_ids", "parameter_vectors", "parameter_names",
    "process_standard_deviations", "forcing_blocks", "parameter_schedule",
    "process_schedule", "process_standard_normals", "observation_standard_normals",
    "initial_states", "initial_covariances", "deterministic_truth_states",
    "truth_process_perturbations", "truth_projection_adjustments",
    "switch_boundary_projection_adjustments", "truth_states", "truth_discharge",
    "observations", "posterior_probabilities", "parameter_margin_probabilities",
    "noise_margin_probabilities", "global_posterior_states",
    "observation_standard_deviation",
}


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _verify_dir_checksums(directory: Path) -> dict[str, bool]:
    manifest = json.loads((directory / "checksums.json").read_text(encoding="utf-8"))
    checks = {}
    for relative, expected in manifest.items():
        path = directory / Path(relative)
        checks[relative] = path.is_file() and _sha256(path) == str(expected)
    actual = {
        path.relative_to(directory).as_posix()
        for path in directory.rglob("*")
        if path.is_file() and path.name != "checksums.json"
    }
    checks["__file_set__"] = actual == set(manifest)
    return checks


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
        name: float(value) for name, value in zip(HYDROLOGIC_STATE_NAMES, current[:5])
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


def _build_schedules(config: dict) -> tuple[np.ndarray, np.ndarray]:
    length = int(config["population"]["stage_length_days"])
    orders = config["truth_trial_stage_orders"]
    parameter_schedule = np.asarray(
        [[v for v in order for _ in range(length)] for order in orders["parameter"]],
        dtype=np.str_,
    )
    process_schedule = np.asarray(
        [[v for v in order for _ in range(length)] for order in orders["process_noise"]],
        dtype=np.str_,
    )
    return parameter_schedule, process_schedule


def _warmup_state(forcing: np.ndarray, parameters: dict[str, float]) -> np.ndarray:
    state = np.zeros(15, dtype=np.float64)
    state[:5] = (0.0, 0.0, parameters["parFC"] * 0.3, 5.0, 10.0)
    for daily_forcing in forcing:
        state = _advance_state(state, daily_forcing, parameters)
    return state


def _independent_truth(config: dict, observation_standard_deviation: float) -> dict:
    parameters = {
        str(row["parameter_id"]): {name: float(row[name]) for name in PARAMETER_NAMES}
        for row in config["parameter_candidates"]
    }
    identifiers = tuple(parameters)
    if len({parameters[v]["parFC"] for v in identifiers}) != 1:
        raise ValueError("frozen candidates do not share parFC")
    if len({parameters[v]["parCWH"] for v in identifiers}) != 1:
        raise ValueError("frozen candidates do not share parCWH")
    standard_deviations = {
        str(row["process_id"]): float(row["standard_deviation_mm_day"])
        for row in config["process_noise_candidates"]
    }
    forcing = _generate_forcing(config, config["formal_confirmation_seeds"]["forcing"])
    parameter_schedule, process_schedule = _build_schedules(config)
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
                active_parameters = parameters[str(parameter_schedule[trial, day])]
                standard_deviation = standard_deviations[
                    str(process_schedule[trial, day])
                ]
                if day > 0 and parameter_schedule[trial, day] != parameter_schedule[
                    trial, day - 1
                ]:
                    boundary_adjustments[block, trial, day] = (
                        _project_state(state, active_parameters) - state
                    )
                deterministic_state = _advance_state(
                    state, active_forcing[day], active_parameters
                )
                perturbation = np.zeros(15, dtype=np.float64)
                perturbation[4] = process_normals[block, day] * standard_deviation
                unprojected = deterministic_state + perturbation
                adjustments[block, trial, day] = (
                    _project_state(unprojected, active_parameters) - unprojected
                )
                deterministic[block, trial, day] = deterministic_state
                perturbations[block, trial, day] = perturbation
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
        "parameter_schedule": parameter_schedule,
        "process_schedule": process_schedule,
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


def _exact_interval(successes: int, total: int, confidence: float) -> tuple[float, float]:
    alpha = 1.0 - float(confidence)
    if successes == 0:
        lower = 0.0
    else:
        lower = float(beta_distribution.ppf(alpha / 2.0, successes, total - successes + 1))
    if successes == total:
        upper = 1.0
    else:
        upper = float(
            beta_distribution.ppf(1.0 - alpha / 2.0, successes + 1, total - successes)
        )
    return lower, upper


def _first_clear_dominance(values, index, run_length, window, threshold, margin):
    true_probability = values[:window, index]
    runner_up = np.max(np.delete(values[:window], index, axis=1), axis=1)
    clear = (true_probability > threshold) & (true_probability - runner_up >= margin)
    for start in range(window - run_length + 1):
        if bool(np.all(clear[start : start + run_length])):
            return start
    return None


def _first_top_ranked(values, index, run_length, window, latest_start):
    top = np.argmax(values[:window], axis=1) == index
    for start in range(latest_start + 1):
        if bool(np.all(top[start : start + run_length])):
            return start
    return None


def _recompute_decisions(config: dict, arrays: dict) -> dict:
    parameter_ids = [str(v) for v in arrays["parameter_ids"]]
    process_ids = [str(v) for v in arrays["process_ids"]]
    parameter_schedule = np.asarray(arrays["parameter_schedule"]).astype(str)
    process_schedule = np.asarray(arrays["process_schedule"]).astype(str)
    parameter_margin = np.asarray(arrays["parameter_margin_probabilities"], dtype=np.float64)
    noise_margin = np.asarray(arrays["noise_margin_probabilities"], dtype=np.float64)
    posterior = np.asarray(arrays["posterior_probabilities"], dtype=np.float64)
    candidate_parameters = [str(v) for v in arrays["candidate_parameter_ids"]]
    candidate_processes = [str(v) for v in arrays["candidate_process_ids"]]

    parameter_margin_rebuilt = np.zeros_like(parameter_margin)
    noise_margin_rebuilt = np.zeros_like(noise_margin)
    for column in range(posterior.shape[-1]):
        parameter_margin_rebuilt[
            ..., parameter_ids.index(candidate_parameters[column])
        ] += posterior[..., column]
        noise_margin_rebuilt[
            ..., process_ids.index(candidate_processes[column])
        ] += posterior[..., column]
    margin_rebuild_difference = max(
        float(np.max(np.abs(parameter_margin_rebuilt - parameter_margin))),
        float(np.max(np.abs(noise_margin_rebuilt - noise_margin))),
    )

    parameter_rule = config["parameter_margin_response_rule"]
    noise_rule = config["noise_margin_response_rule"]
    events = []
    block_count, trial_count, day_count, _ = parameter_margin.shape
    for block in range(block_count):
        for trial in range(trial_count):
            for day in range(1, day_count):
                if parameter_schedule[trial, day] == parameter_schedule[trial, day - 1]:
                    continue
                new_parameter = parameter_ids.index(parameter_schedule[trial, day])
                new_process = process_ids.index(process_schedule[trial, day])
                parameter_start = _first_clear_dominance(
                    parameter_margin[block, trial, day:],
                    new_parameter,
                    int(parameter_rule["consecutive_clear_dominance_days"]),
                    int(parameter_rule["response_window_days"]),
                    float(parameter_rule["minimum_new_true_candidate_probability_exclusive"]),
                    float(parameter_rule["minimum_probability_margin_over_runner_up_inclusive"]),
                )
                noise_start = _first_top_ranked(
                    noise_margin[block, trial, day:],
                    new_process,
                    int(noise_rule["consecutive_top_ranked_days"]),
                    int(noise_rule["response_window_days"]),
                    int(noise_rule["latest_allowed_response_start_day"]),
                )
                events.append(
                    {
                        "event_id": (
                            f"block_{block + 1:02d}_trial_{trial + 1}"
                            f"_switch_day_{day + 1}"
                        ),
                        "parameter_transition_label": (
                            f"{parameter_schedule[trial, day - 1]}_to_"
                            f"{parameter_schedule[trial, day]}"
                        ),
                        "noise_transition_label": (
                            f"{process_schedule[trial, day - 1]}_to_"
                            f"{process_schedule[trial, day]}"
                        ),
                        "parameter_numeric_success": parameter_start is not None,
                        "parameter_response_start_day": parameter_start,
                        "noise_numeric_success": noise_start is not None,
                        "noise_response_start_day": noise_start,
                    }
                )

    def summarize(label_key, success_key, start_key, rule):
        grouped: dict[str, list[dict]] = {}
        for event in events:
            grouped.setdefault(event[label_key], []).append(event)
        rows = []
        for label in sorted(grouped):
            members = grouped[label]
            successes = sum(1 for member in members if member[success_key])
            lower, upper = _exact_interval(
                successes, len(members), float(rule["confidence_level"])
            )
            starts = sorted(
                member[start_key] for member in members if member[start_key] is not None
            )
            rows.append(
                {
                    "transition_label": label,
                    "event_count": len(members),
                    "successful_event_count": successes,
                    "exact_interval_lower": lower,
                    "exact_interval_upper": upper,
                    "criterion_passed": bool(
                        successes
                        >= int(rule["minimum_successful_events_per_directed_transition"])
                        and lower > float(rule["minimum_exact_interval_lower_bound_exclusive"])
                    ),
                    "median_response_start_day": (
                        float(np.median(starts)) if starts else None
                    ),
                    "maximum_response_start_day": max(starts) if starts else None,
                }
            )
        return rows

    return {
        "margin_rebuild_maximum_absolute_difference": margin_rebuild_difference,
        "events": events,
        "parameter_margin_summaries": summarize(
            "parameter_transition_label",
            "parameter_numeric_success",
            "parameter_response_start_day",
            parameter_rule,
        ),
        "noise_margin_summaries": summarize(
            "noise_transition_label",
            "noise_numeric_success",
            "noise_response_start_day",
            noise_rule,
        ),
    }


def main() -> None:
    if DEFAULT_VERIFICATION.exists():
        raise FileExistsError(f"verification path already exists: {DEFAULT_VERIFICATION}")
    config_hash_ok = _sha256(FROZEN_CONFIG) == CONFIG_SHA256
    config = json.loads(FROZEN_CONFIG.read_text(encoding="utf-8"))
    artifact_checks = _verify_dir_checksums(DEFAULT_RESULT)
    visual_checks = _verify_dir_checksums(DEFAULT_VISUAL_REVIEW)
    snapshot_hash_ok = (
        _sha256(DEFAULT_RESULT / "config_snapshot.json")
        == json.loads((DEFAULT_RESULT / "checksums.json").read_text(encoding="utf-8"))[
            "config_snapshot.json"
        ]
    )
    source_manifest = json.loads(
        (DEFAULT_RESULT / "source_manifest.json").read_text(encoding="utf-8")
    )
    source_checks = {
        relative: (PROJECT_ROOT / relative).is_file()
        and _sha256(PROJECT_ROOT / relative) == expected
        for relative, expected in source_manifest["files"].items()
    }

    with np.load(DEFAULT_RESULT / "evidence.npz", allow_pickle=True) as archive:
        arrays = {key: archive[key] for key in archive.files}
    evidence_keys_ok = set(arrays) == EVIDENCE_KEYS
    observation_standard_deviation = float(arrays["observation_standard_deviation"])

    rebuilt = _independent_truth(config, observation_standard_deviation)
    truth_differences = {
        key: float(np.max(np.abs(np.asarray(rebuilt[key], dtype=np.float64)
                                 - np.asarray(arrays[key], dtype=np.float64))))
        for key in rebuilt
        if key not in ("parameter_schedule", "process_schedule")
    }
    schedule_match = bool(
        np.array_equal(rebuilt["parameter_schedule"], arrays["parameter_schedule"])
        and np.array_equal(rebuilt["process_schedule"], arrays["process_schedule"])
    )
    truth_projection_count = int(
        np.count_nonzero(
            np.any(rebuilt["truth_projection_adjustments"] != 0.0, axis=-1)
        )
    )
    boundary_projection_count = int(
        np.count_nonzero(
            np.any(rebuilt["switch_boundary_projection_adjustments"] != 0.0, axis=-1)
        )
    )

    posterior = np.asarray(arrays["posterior_probabilities"], dtype=np.float64)
    probability_checks = {
        "finite": bool(np.all(np.isfinite(posterior))),
        "nonnegative": bool(np.min(posterior) >= 0.0),
        "normalization": bool(
            np.allclose(posterior.sum(axis=-1), 1.0, rtol=0.0, atol=1e-12)
        ),
    }
    decisions = _recompute_decisions(config, arrays)

    sealed_summary = json.loads((DEFAULT_RESULT / "summary.json").read_text(encoding="utf-8"))
    sealed_parameter = {
        row["transition_label"]: (
            row["successful_event_count"],
            bool(row["criterion_passed"]),
        )
        for row in sealed_summary["parameter_margin_numeric_results"]
    }
    sealed_noise = {
        row["transition_label"]: (
            row["successful_event_count"],
            bool(row["criterion_passed"]),
        )
        for row in sealed_summary["noise_margin_numeric_results"]
    }
    recomputed_parameter = {
        row["transition_label"]: (row["successful_event_count"], row["criterion_passed"])
        for row in decisions["parameter_margin_summaries"]
    }
    recomputed_noise = {
        row["transition_label"]: (row["successful_event_count"], row["criterion_passed"])
        for row in decisions["noise_margin_summaries"]
    }
    decisions_match_sealed = bool(
        sealed_parameter == recomputed_parameter and sealed_noise == recomputed_noise
    )

    with (DEFAULT_VISUAL_REVIEW / "visual_review.csv").open(
        newline="", encoding="utf-8"
    ) as handle:
        visual_rows = list(csv.DictReader(handle))
    label_counts = {"parameter_margin": {}, "noise_margin": {}}
    for row in visual_rows:
        for margin in label_counts:
            label = row[f"{margin}_label"]
            label_counts[margin][label] = label_counts[margin].get(label, 0) + 1

    tolerance = float(config["numerical_tolerance"])
    loaded_modules = set(sys.modules)
    integrity = {
        "config_hash": config_hash_ok,
        "artifact_checksums": all(artifact_checks.values()),
        "visual_review_checksums": all(visual_checks.values()),
        "snapshot_hash": snapshot_hash_ok,
        "source_hashes": all(source_checks.values()),
        "evidence_keys": evidence_keys_ok,
        "schedules": schedule_match,
        "truth_rebuild_within_tolerance": max(truth_differences.values()) <= tolerance,
        "margin_rebuild_within_tolerance": (
            decisions["margin_rebuild_maximum_absolute_difference"] <= tolerance
        ),
        "zero_truth_projections": truth_projection_count == 0,
        "zero_boundary_projections": boundary_projection_count == 0,
        "probability_checks": all(probability_checks.values()),
        "decisions_match_sealed": decisions_match_sealed,
        "visual_review_rows": len(visual_rows) == 48,
        "production_experiment_module_not_imported": not (
            set(PRODUCTION_EXPERIMENT_MODULES) & loaded_modules
        ),
        "production_runner_not_imported": PRODUCTION_RUNNER_MODULE not in loaded_modules,
        "forecast_module_not_imported": not any(
            "forecast" in name
            for name in loaded_modules
            if name.startswith(PROJECT_NAMESPACES)
        ),
    }
    if not all(isinstance(value, bool) for value in integrity.values()):
        raise TypeError(
            "every integrity entry must be a plain boolean whose True value means "
            "the check passed; a mixed-polarity entry would silently corrupt the verdict"
        )
    status = "passed" if all(integrity.values()) else "failed"

    report = {
        "experiment_id": EXPERIMENT_ID,
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "status": status,
        "integrity": integrity,
        "artifact_checksum_checks": artifact_checks,
        "visual_review_checksum_checks": visual_checks,
        "current_source_hash_checks": source_checks,
        "truth_reconstruction_maximum_absolute_differences": truth_differences,
        "truth_reconstruction_maximum_absolute_difference": max(truth_differences.values()),
        "margin_rebuild_maximum_absolute_difference": (
            decisions["margin_rebuild_maximum_absolute_difference"]
        ),
        "truth_projection_event_count_recomputed": truth_projection_count,
        "switch_boundary_projection_event_count_recomputed": boundary_projection_count,
        "probability_checks": probability_checks,
        "parameter_margin_results_recomputed": decisions["parameter_margin_summaries"],
        "noise_margin_results_recomputed": decisions["noise_margin_summaries"],
        "visual_label_counts": label_counts,
        "preregistered_expectations": config["preregistered_expectations"],
        "numerical_tolerance": tolerance,
    }

    DEFAULT_VERIFICATION.mkdir(parents=True)
    report_path = DEFAULT_VERIFICATION / "independent_verification.json"
    report_path.write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    (DEFAULT_VERIFICATION / "checksums.json").write_text(
        json.dumps(
            {"independent_verification.json": _sha256(report_path)},
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )
    print(json.dumps({"status": status, "integrity": integrity}, indent=2, sort_keys=True))
    if status != "passed":
        raise SystemExit(1)


if __name__ == "__main__":
    main()

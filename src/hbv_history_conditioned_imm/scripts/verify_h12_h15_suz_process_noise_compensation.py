"""Independently verify H12-H15 direct upper-zone state compensation."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import shutil
import tempfile
from pathlib import Path
from typing import Any, Mapping, Sequence

import numpy as np

from hbv_history_conditioned_imm.scripts.run_h12_h15_suz_process_noise_sensitivity import (
    DIRECT_COMPENSATION_CRITERION,
)
from hbv_history_conditioned_imm.scripts.verify_h06_h08_objective_ablation import (
    METHODS,
    verify_result_directory,
)
from hbv_history_conditioned_imm.synthetic import make_block_seeds


EXPECTED_STANDARD_DEVIATIONS = (0.1, 0.3, 1.0, 3.0)
TRUTH_ARRAYS = (
    "truth_discharge",
    "truth_states",
    "truth_parameter_indices",
    "switch_days",
    "process_perturbations",
    "projection_adjustments",
    "accepted_process_seeds",
    "flow_standard_deviation",
    "block_ids",
)
INVARIANT_CONFIG_FIELDS = (
    "base_parameter_source",
    "base_parameters",
    "parameter_candidates",
    "data",
    "seeds",
    "forecast",
    "network",
    "training",
    "loss",
    "capability_gates",
    "required_result_files",
)


def _read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _posterior_label_scores(
    arrays: Mapping[str, np.ndarray], method: str
) -> tuple[float, float]:
    probabilities = arrays[f"{method}_posterior_probabilities"]
    modes = arrays["truth_parameter_indices"]
    if probabilities.shape != (*modes.shape, 3):
        raise ValueError(f"unexpected {method} posterior probability shape")
    selected = probabilities[
        np.arange(probabilities.shape[0])[:, None],
        np.arange(probabilities.shape[1])[None, :],
        modes,
    ]
    cross_entropy = float(
        np.mean(-np.log(np.clip(selected, np.finfo(np.float64).tiny, None)))
    )
    accuracy = float(np.mean(np.argmax(probabilities, axis=-1) == modes))
    return cross_entropy, accuracy


def _candidate_state_diagnostics(
    arrays: Mapping[str, np.ndarray],
    method: str,
    *,
    state_index: int = 3,
) -> dict[str, float]:
    """Measure same-day observation corrections for correct and wrong candidates."""

    modes = np.asarray(arrays["truth_parameter_indices"], dtype=np.int64)
    truth_states = np.asarray(arrays["truth_states"], dtype=np.float64)
    prior = np.asarray(
        arrays[f"{method}_candidate_prior_states"], dtype=np.float64
    )
    posterior = np.asarray(
        arrays[f"{method}_candidate_posterior_states"], dtype=np.float64
    )
    likelihoods = np.asarray(
        arrays[f"{method}_candidate_log_likelihoods"], dtype=np.float64
    )
    block_count, day_count = modes.shape
    expected_state_shape = (block_count, day_count, 3, 15)
    if prior.shape != expected_state_shape or posterior.shape != expected_state_shape:
        raise ValueError(f"unexpected {method} candidate state shape")
    if likelihoods.shape != (block_count, day_count, 3):
        raise ValueError(f"unexpected {method} candidate likelihood shape")
    if truth_states.shape[0] != block_count or truth_states.shape[1] < day_count:
        raise ValueError("truth states do not cover every assimilation day")
    if np.any((modes < 0) | (modes >= 3)):
        raise ValueError("truth parameter indices must be zero one or two")
    if not (
        np.all(np.isfinite(prior))
        and np.all(np.isfinite(posterior))
        and np.all(np.isfinite(likelihoods))
    ):
        raise ValueError(f"nonfinite {method} candidate diagnostic array")

    corrections = np.abs(posterior - prior)[..., state_index]
    truth = truth_states[:, :day_count, state_index, None]
    prior_errors = np.abs(prior[..., state_index] - truth)
    posterior_errors = np.abs(posterior[..., state_index] - truth)
    block_indices = np.arange(block_count)[:, None]
    day_indices = np.arange(day_count)[None, :]
    correct_corrections = corrections[block_indices, day_indices, modes]
    correct_prior_errors = prior_errors[block_indices, day_indices, modes]
    correct_posterior_errors = posterior_errors[block_indices, day_indices, modes]
    wrong_mask = np.ones((block_count, day_count, 3), dtype=bool)
    wrong_mask[block_indices, day_indices, modes] = False
    wrong_corrections = corrections[wrong_mask]
    wrong_prior_errors = prior_errors[wrong_mask]
    wrong_posterior_errors = posterior_errors[wrong_mask]

    mean_correct_correction = float(np.mean(correct_corrections))
    mean_wrong_correction = float(np.mean(wrong_corrections))
    mean_wrong_prior_error = float(np.mean(wrong_prior_errors))
    mean_wrong_posterior_error = float(np.mean(wrong_posterior_errors))
    if mean_correct_correction <= 0.0 or mean_wrong_prior_error <= 0.0:
        raise ValueError("candidate correction and prior-error denominators must be positive")
    return {
        "mean_absolute_correct_candidate_suz_correction": mean_correct_correction,
        "mean_absolute_wrong_candidate_suz_correction": mean_wrong_correction,
        "wrong_to_correct_mean_absolute_suz_correction_ratio": (
            mean_wrong_correction / mean_correct_correction
        ),
        "mean_absolute_correct_candidate_suz_prior_error": float(
            np.mean(correct_prior_errors)
        ),
        "mean_absolute_correct_candidate_suz_posterior_error": float(
            np.mean(correct_posterior_errors)
        ),
        "mean_absolute_wrong_candidate_suz_prior_error": mean_wrong_prior_error,
        "mean_absolute_wrong_candidate_suz_posterior_error": mean_wrong_posterior_error,
        "wrong_candidate_mean_absolute_suz_error_reduction": (
            (mean_wrong_prior_error - mean_wrong_posterior_error)
            / mean_wrong_prior_error
        ),
        "candidate_likelihood_mode_accuracy": float(
            np.mean(np.argmax(likelihoods, axis=-1) == modes)
        ),
    }


def _candidate_flow_fit_diagnostics(
    arrays: Mapping[str, np.ndarray],
    method: str,
    *,
    observations: np.ndarray,
    routing_weights: np.ndarray,
) -> dict[str, float]:
    """Describe how the observation update changes candidate flow residuals."""

    modes = np.asarray(arrays["truth_parameter_indices"], dtype=np.int64)
    truth_discharge = np.asarray(arrays["truth_discharge"], dtype=np.float64)
    prior = np.asarray(
        arrays[f"{method}_candidate_prior_states"], dtype=np.float64
    )
    posterior = np.asarray(
        arrays[f"{method}_candidate_posterior_states"], dtype=np.float64
    )
    block_count, day_count = modes.shape
    if observations.shape[0] != block_count or observations.shape[1] < day_count:
        raise ValueError("reconstructed observations do not cover assimilation")
    weights = np.asarray(routing_weights, dtype=np.float64)
    if weights.shape != (10,) or not np.isclose(weights.sum(), 1.0):
        raise ValueError("routing weights must contain ten values summing to one")
    expected_state_shape = (block_count, day_count, 3, 15)
    if prior.shape != expected_state_shape or posterior.shape != expected_state_shape:
        raise ValueError(f"unexpected {method} candidate state shape")

    prior_flow = np.sum(prior[..., 5:15] * weights, axis=-1)
    posterior_flow = np.sum(posterior[..., 5:15] * weights, axis=-1)
    observed_target = observations[:, :day_count, None]
    truth_target = truth_discharge[:, :day_count, None]
    prior_observed_errors = np.abs(prior_flow - observed_target)
    posterior_observed_errors = np.abs(posterior_flow - observed_target)
    prior_truth_errors = np.abs(prior_flow - truth_target)
    posterior_truth_errors = np.abs(posterior_flow - truth_target)
    block_indices = np.arange(block_count)[:, None]
    day_indices = np.arange(day_count)[None, :]
    wrong_mask = np.ones((block_count, day_count, 3), dtype=bool)
    wrong_mask[block_indices, day_indices, modes] = False

    def summary(before: np.ndarray, after: np.ndarray) -> tuple[float, float, float]:
        mean_before = float(np.mean(before))
        mean_after = float(np.mean(after))
        if mean_before <= 0.0:
            raise ValueError("candidate flow residual denominator must be positive")
        return mean_before, mean_after, (mean_before - mean_after) / mean_before

    wrong_observed = summary(
        prior_observed_errors[wrong_mask], posterior_observed_errors[wrong_mask]
    )
    wrong_truth = summary(
        prior_truth_errors[wrong_mask], posterior_truth_errors[wrong_mask]
    )
    correct_observed = summary(
        prior_observed_errors[block_indices, day_indices, modes],
        posterior_observed_errors[block_indices, day_indices, modes],
    )
    correct_truth = summary(
        prior_truth_errors[block_indices, day_indices, modes],
        posterior_truth_errors[block_indices, day_indices, modes],
    )
    return {
        "mean_absolute_wrong_candidate_observed_flow_residual_before_update": wrong_observed[
            0
        ],
        "mean_absolute_wrong_candidate_observed_flow_residual_after_update": wrong_observed[
            1
        ],
        "wrong_candidate_observed_flow_residual_reduction": wrong_observed[2],
        "mean_absolute_wrong_candidate_true_flow_residual_before_update": wrong_truth[
            0
        ],
        "mean_absolute_wrong_candidate_true_flow_residual_after_update": wrong_truth[
            1
        ],
        "wrong_candidate_true_flow_residual_reduction": wrong_truth[2],
        "correct_candidate_observed_flow_residual_reduction": correct_observed[2],
        "correct_candidate_true_flow_residual_reduction": correct_truth[2],
    }


def _reconstruct_test_observations(
    config: Mapping[str, Any], arrays: Mapping[str, np.ndarray]
) -> np.ndarray:
    data = config["data"]
    seeds = config["seeds"]
    specifications = make_block_seeds(
        split="test",
        count=int(data["test_blocks"]),
        forcing_prefix=int(seeds["forcing_prefix"]),
        process_prefix=int(seeds["process_prefix"]),
        observation_prefix=int(seeds["observation_prefix"]),
        schedule_prefix=int(seeds["schedule_prefix"]),
        split_offset=int(seeds["test_split_offset"]),
    )
    expected_ids = np.asarray(
        [specification.block_id for specification in specifications]
    )
    if not np.array_equal(expected_ids, arrays["block_ids"]):
        raise ValueError("saved test block identifiers differ from frozen seeds")
    truth_discharge = np.asarray(arrays["truth_discharge"], dtype=np.float64)
    observation_standard_deviation = float(
        data["observation_standard_deviation"]
    )
    noises = np.stack(
        [
            np.random.default_rng(specification.observation_seed).standard_normal(
                truth_discharge.shape[1]
            )
            for specification in specifications
        ]
    )
    return truth_discharge + observation_standard_deviation * noises


def _routing_weights(config: Mapping[str, Any]) -> np.ndarray:
    candidates = config["parameter_candidates"]
    if candidates.get("parameter_name") != "parK1":
        raise ValueError("H12-H15 must vary only parK1")
    lag_time = float(config["base_parameters"]["lag_time"])
    count = max(math.ceil(lag_time), 1)
    weights = np.maximum(count - np.arange(10, dtype=np.float64), 0.0)
    return weights / weights.sum()


def evaluate_direct_compensation_criterion(
    levels: Mapping[float, Mapping[str, float]],
    criterion: Mapping[str, Any],
) -> dict[str, Any]:
    ordered = tuple(
        float(value)
        for value in criterion["ordered_filter_process_standard_deviations"]
    )
    if ordered != EXPECTED_STANDARD_DEVIATIONS or set(levels) != set(ordered):
        raise ValueError("direct-compensation levels must be exactly 0.1 0.3 1.0 and 3.0")
    matched = levels[1.0]
    ratio = float(
        matched["wrong_to_correct_mean_absolute_suz_correction_ratio"]
    )
    error_reduction = float(
        matched["wrong_candidate_mean_absolute_suz_error_reduction"]
    )
    corrections = [
        float(levels[level]["mean_absolute_wrong_candidate_suz_correction"])
        for level in ordered
    ]
    ratio_passed = ratio >= float(
        criterion[
            "minimum_wrong_to_correct_mean_absolute_suz_correction_ratio"
        ]
    )
    error_reduction_passed = error_reduction >= float(
        criterion["minimum_wrong_candidate_mean_absolute_suz_error_reduction"]
    )
    dose_response_passed = bool(
        all(left < right for left, right in zip(corrections, corrections[1:]))
    )
    if not bool(
        criterion[
            "require_strictly_increasing_wrong_candidate_mean_absolute_suz_correction"
        ]
    ):
        raise ValueError("the registered criterion must require a strict dose response")
    return {
        "matched_wrong_to_correct_correction_ratio": ratio,
        "matched_minimum_wrong_to_correct_correction_ratio": float(
            criterion[
                "minimum_wrong_to_correct_mean_absolute_suz_correction_ratio"
            ]
        ),
        "matched_wrong_to_correct_correction_gate_passed": ratio_passed,
        "matched_wrong_candidate_error_reduction": error_reduction,
        "matched_minimum_wrong_candidate_error_reduction": float(
            criterion["minimum_wrong_candidate_mean_absolute_suz_error_reduction"]
        ),
        "matched_wrong_candidate_error_reduction_gate_passed": error_reduction_passed,
        "ordered_wrong_candidate_mean_absolute_suz_corrections": corrections,
        "strict_correction_dose_response_gate_passed": dose_response_passed,
        "direct_state_compensation_supported": (
            ratio_passed and error_reduction_passed and dose_response_passed
        ),
    }


def verify_suz_process_noise_sensitivity(
    result_directories: Sequence[str | Path],
) -> dict[str, Any]:
    if len(result_directories) != 4:
        raise ValueError("exactly four H12-H15 result directories are required")
    records = []
    maximum_metric_difference = 0.0
    for value in result_directories:
        root = Path(value).resolve()
        config = _read_json(root / "config_snapshot.json")
        metrics = _read_json(root / "metrics.json")
        with np.load(root / "daily_arrays.npz", allow_pickle=False) as archive:
            arrays = {name: archive[name] for name in archive.files}
        verification = verify_result_directory(root)
        if config["data"].get("fixed_process_state_name") != "SUZ":
            raise ValueError("truth process state is not SUZ")
        if float(config["data"].get("fixed_process_standard_deviation")) != 1.0:
            raise ValueError("truth SUZ process standard deviation is not 1.0")
        if config["data"].get("require_zero_projection") is not False:
            raise ValueError("truth physical projection rule changed")
        if config["filter"].get("assumed_process_state_name") != "SUZ":
            raise ValueError("filter process state is not SUZ")
        standard_deviation = float(
            config["filter"]["assumed_process_standard_deviation"]
        )
        posterior_scores = {}
        for method in METHODS:
            cross_entropy, accuracy = _posterior_label_scores(arrays, method)
            posterior_scores[method] = {
                "posterior_mode_cross_entropy": cross_entropy,
                "posterior_mode_accuracy": accuracy,
            }
            saved = metrics["methods"][method]["losses"]
            maximum_metric_difference = max(
                maximum_metric_difference,
                abs(cross_entropy - float(saved["posterior_mode_cross_entropy"])),
                abs(accuracy - float(saved["posterior_mode_accuracy"])),
            )
        observations = _reconstruct_test_observations(config, arrays)
        records.append(
            {
                "root": str(root),
                "config": config,
                "metrics": metrics,
                "arrays": arrays,
                "verification": verification,
                "standard_deviation": standard_deviation,
                "posterior_scores": posterior_scores,
                "fixed_state_diagnostics": _candidate_state_diagnostics(
                    arrays, "fixed"
                ),
                "fixed_flow_fit_diagnostics": _candidate_flow_fit_diagnostics(
                    arrays,
                    "fixed",
                    observations=observations,
                    routing_weights=_routing_weights(config),
                ),
            }
        )

    by_level = {record["standard_deviation"]: record for record in records}
    if tuple(sorted(by_level)) != EXPECTED_STANDARD_DEVIATIONS:
        raise ValueError("H12-H15 do not cover exactly 0.1 0.3 1.0 and 3.0")
    if len(by_level) != len(records):
        raise ValueError("duplicate filter process standard deviations")
    baseline = by_level[1.0]

    truth_arrays_match = {}
    config_fields_match = {}
    forecast_masks_match = {}
    perturbations_confined = True
    projections_confined = True
    all_candidate_arrays_finite = True
    all_truth_states_physical = True
    for level, record in sorted(by_level.items()):
        arrays = record["arrays"]
        truth_arrays_match[str(level)] = all(
            np.array_equal(arrays[name], baseline["arrays"][name])
            for name in TRUTH_ARRAYS
        )
        forecast_masks_match[str(level)] = all(
            np.array_equal(
                arrays[f"{method}_forecast_valid_mask"],
                baseline["arrays"][f"{method}_forecast_valid_mask"],
            )
            for method in METHODS
        )
        config_fields_match[str(level)] = all(
            record["config"][name] == baseline["config"][name]
            for name in INVARIANT_CONFIG_FIELDS
        )
        filter_config = dict(record["config"]["filter"])
        filter_config.pop("assumed_process_standard_deviation")
        baseline_filter = dict(baseline["config"]["filter"])
        baseline_filter.pop("assumed_process_standard_deviation")
        config_fields_match[str(level)] = (
            config_fields_match[str(level)] and filter_config == baseline_filter
        )

        perturbations = arrays["process_perturbations"].copy()
        perturbations[..., 3] = 0.0
        perturbations_confined = perturbations_confined and not np.any(perturbations)
        projections = arrays["projection_adjustments"].copy()
        projections[..., 3] = 0.0
        projections_confined = projections_confined and not np.any(projections)
        all_truth_states_physical = all_truth_states_physical and bool(
            np.all(arrays["truth_states"][..., 3] >= 0.0)
        )
        for method in METHODS:
            all_candidate_arrays_finite = all_candidate_arrays_finite and bool(
                np.all(
                    np.isfinite(arrays[f"{method}_candidate_prior_states"])
                )
                and np.all(
                    np.isfinite(arrays[f"{method}_candidate_posterior_states"])
                )
                and np.all(
                    np.isfinite(arrays[f"{method}_candidate_log_likelihoods"])
                )
            )

    criteria = [
        record["config"]["suz_process_noise_sensitivity_specification"][
            "direct_compensation_criterion"
        ]
        for record in records
    ]
    if not all(criterion == DIRECT_COMPENSATION_CRITERION for criterion in criteria):
        raise ValueError("direct-compensation criterion differs from registration")
    diagnostics_by_level = {
        level: record["fixed_state_diagnostics"]
        for level, record in sorted(by_level.items())
    }
    criterion_result = evaluate_direct_compensation_criterion(
        diagnostics_by_level, DIRECT_COMPENSATION_CRITERION
    )

    levels = {}
    for level, record in sorted(by_level.items()):
        methods = record["metrics"]["methods"]
        levels[str(level)] = {
            "experiment_id": record["config"]["experiment_id"],
            "fixed_candidate_state_diagnostics": record[
                "fixed_state_diagnostics"
            ],
            "fixed_candidate_flow_fit_diagnostics": record[
                "fixed_flow_fit_diagnostics"
            ],
            "posterior_label_scores": record["posterior_scores"],
            "history_conditioned_forecast_loss": float(
                methods["history_conditioned"]["losses"]["forecast"]
            ),
            "history_conditioned_oracle_brier": float(
                methods["history_conditioned"]["transition_recovery"][
                    "oracle_brier"
                ]
            ),
            "history_vs_learned_static": record["metrics"][
                "history_vs_learned_static"
            ],
            "probability_and_forecast_capability_gates": record["metrics"][
                "capability_gates"
            ],
            "probability_and_forecast_capability_passed": bool(
                record["metrics"]["synthetic_capability_passed"]
            ),
        }

    baseline_arrays = baseline["arrays"]
    projection_adjustments = baseline_arrays["projection_adjustments"][..., 3]
    perturbations = baseline_arrays["process_perturbations"][..., 3]
    realized_increments = perturbations + projection_adjustments
    projection_diagnostics = {
        "physical_projection_event_fraction": float(
            np.mean(projection_adjustments != 0.0)
        ),
        "maximum_absolute_projection_adjustment": float(
            np.max(np.abs(projection_adjustments))
        ),
        "pre_projection_process_increment_mean": float(np.mean(perturbations)),
        "pre_projection_process_increment_standard_deviation": float(
            np.std(perturbations)
        ),
        "realized_post_projection_increment_mean": float(
            np.mean(realized_increments)
        ),
        "realized_post_projection_increment_standard_deviation": float(
            np.std(realized_increments)
        ),
    }
    matched_state = baseline["fixed_state_diagnostics"]
    matched_flow = baseline["fixed_flow_fit_diagnostics"]
    post_hoc_mechanism_diagnostic = {
        "status": "post_hoc_descriptive_not_preregistered",
        "matched_wrong_candidate_suz_state_error_reduction": matched_state[
            "wrong_candidate_mean_absolute_suz_error_reduction"
        ],
        "matched_wrong_candidate_observed_flow_residual_reduction": matched_flow[
            "wrong_candidate_observed_flow_residual_reduction"
        ],
        "matched_wrong_candidate_true_flow_residual_reduction": matched_flow[
            "wrong_candidate_true_flow_residual_reduction"
        ],
        "observed_pattern_is_better_flow_fit_with_worse_hidden_state": bool(
            matched_state["wrong_candidate_mean_absolute_suz_error_reduction"]
            < 0.0
            and matched_flow["wrong_candidate_observed_flow_residual_reduction"]
            > 0.0
            and matched_flow["wrong_candidate_true_flow_residual_reduction"]
            > 0.0
        ),
        "ordered_wrong_candidate_observed_flow_residual_reductions": [
            by_level[level]["fixed_flow_fit_diagnostics"][
                "wrong_candidate_observed_flow_residual_reduction"
            ]
            for level in EXPECTED_STANDARD_DEVIATIONS
        ],
        "ordered_wrong_candidate_true_flow_residual_reductions": [
            by_level[level]["fixed_flow_fit_diagnostics"][
                "wrong_candidate_true_flow_residual_reduction"
            ]
            for level in EXPECTED_STANDARD_DEVIATIONS
        ],
        "interpretation": (
            "A wrong parameter candidate can fit discharge better by moving its "
            "hidden upper-zone state farther from the synthetic true state. This "
            "describes state compensation but is not a replacement confirmatory gate."
        ),
    }

    all_verified = (
        all(record["verification"]["all_verified"] for record in records)
        and all(truth_arrays_match.values())
        and all(forecast_masks_match.values())
        and all(config_fields_match.values())
        and perturbations_confined
        and projections_confined
        and all_candidate_arrays_finite
        and all_truth_states_physical
        and maximum_metric_difference <= 1e-12
    )
    return {
        "all_verified": all_verified,
        "truth_arrays_match": truth_arrays_match,
        "forecast_valid_masks_match": forecast_masks_match,
        "invariant_config_fields_match": config_fields_match,
        "process_perturbations_confined_to_suz": perturbations_confined,
        "projection_adjustments_confined_to_suz": projections_confined,
        "all_candidate_diagnostic_arrays_finite": all_candidate_arrays_finite,
        "all_truth_suz_states_nonnegative": all_truth_states_physical,
        "maximum_saved_metric_absolute_difference": maximum_metric_difference,
        "projection_diagnostics": projection_diagnostics,
        "levels": levels,
        "direct_compensation_criterion": dict(DIRECT_COMPENSATION_CRITERION),
        "direct_compensation_result": criterion_result,
        "post_hoc_mechanism_diagnostic": post_hoc_mechanism_diagnostic,
        "claim_boundary": (
            "Direct state compensation is separate from transition-probability "
            "recovery and flow-forecast superiority. The truth noise scale is "
            "defined before physical nonnegative projection."
        ),
    }


def write_verification_report(
    report: Mapping[str, Any], output_directory: str | Path
) -> Path:
    final_directory = Path(output_directory).resolve()
    if final_directory.exists():
        raise FileExistsError(
            f"verification output directory already exists: {final_directory}"
        )
    final_directory.parent.mkdir(parents=True, exist_ok=True)
    staging = Path(
        tempfile.mkdtemp(
            prefix=f".{final_directory.name}.staging-",
            dir=final_directory.parent,
        )
    )
    try:
        report_path = staging / "verification_report.json"
        report_path.write_text(
            json.dumps(report, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        (staging / "checksums.json").write_text(
            json.dumps(
                {"verification_report.json": _sha256(report_path)},
                indent=2,
                sort_keys=True,
            )
            + "\n",
            encoding="utf-8",
        )
        staging.replace(final_directory)
    except Exception:
        shutil.rmtree(staging, ignore_errors=True)
        raise
    return final_directory


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("result_directories", nargs=4)
    parser.add_argument("--output-directory")
    arguments = parser.parse_args()
    result = verify_suz_process_noise_sensitivity(arguments.result_directories)
    if arguments.output_directory:
        write_verification_report(result, arguments.output_directory)
    print(json.dumps(result, indent=2, sort_keys=True))
    if not result["all_verified"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()

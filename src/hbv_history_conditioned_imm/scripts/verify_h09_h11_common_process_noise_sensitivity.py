"""Verify the four-level common assumed-filter process-noise sensitivity."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any, Mapping

import numpy as np

from hbv_history_conditioned_imm.scripts.verify_h06_h08_objective_ablation import (
    METHODS,
    verify_result_directory,
)


EXPECTED_STANDARD_DEVIATIONS = (0.1, 0.3, 1.0, 3.0)
TRUTH_ARRAYS = (
    "truth_discharge",
    "truth_parameter_indices",
    "switch_days",
    "flow_standard_deviation",
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


def _filter_standard_deviation(config: Mapping[str, Any]) -> float:
    return float(
        config["filter"].get(
            "assumed_lower_groundwater_process_standard_deviation",
            config["data"][
                "fixed_lower_groundwater_process_standard_deviation"
            ],
        )
    )


def _posterior_label_scores(
    arrays: Any,
    method: str,
) -> tuple[float, float]:
    probabilities = arrays[f"{method}_posterior_probabilities"]
    modes = arrays["truth_parameter_indices"]
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


def evaluate_state_compensation_criterion(
    levels: Mapping[float, Mapping[str, float]],
    criterion: Mapping[str, Any],
) -> dict[str, Any]:
    baseline_level = float(
        criterion["baseline_filter_process_standard_deviation"]
    )
    high_level = float(
        criterion["higher_filter_process_standard_deviation"]
    )
    lower_levels = tuple(
        float(value)
        for value in criterion["lower_filter_process_standard_deviations"]
    )
    baseline = levels[baseline_level]
    fixed_cross_entropy_improvements = {
        str(level): (
            baseline["fixed_posterior_mode_cross_entropy"]
            - levels[level]["fixed_posterior_mode_cross_entropy"]
        )
        / baseline["fixed_posterior_mode_cross_entropy"]
        for level in lower_levels
    }
    high_cross_entropy_increase = (
        levels[high_level]["fixed_posterior_mode_cross_entropy"]
        - baseline["fixed_posterior_mode_cross_entropy"]
    ) / baseline["fixed_posterior_mode_cross_entropy"]
    history_forecast_improvements = {
        str(level): (
            baseline["history_forecast"] - levels[level]["history_forecast"]
        )
        / baseline["history_forecast"]
        for level in lower_levels
    }
    history_oracle_brier_improvements = {
        str(level): (
            baseline["history_oracle_brier"]
            - levels[level]["history_oracle_brier"]
        )
        / baseline["history_oracle_brier"]
        for level in lower_levels
    }
    lower_cross_entropy_passed = all(
        value
        >= float(criterion["minimum_relative_fixed_cross_entropy_improvement"])
        for value in fixed_cross_entropy_improvements.values()
    )
    high_cross_entropy_passed = high_cross_entropy_increase >= float(
        criterion["minimum_relative_high_noise_cross_entropy_increase"]
    )
    lower_history_joint_passed = any(
        history_forecast_improvements[str(level)]
        >= float(criterion["minimum_relative_history_forecast_improvement"])
        and history_oracle_brier_improvements[str(level)]
        >= float(
            criterion["minimum_relative_history_oracle_brier_improvement"]
        )
        for level in lower_levels
    )
    supported = (
        lower_cross_entropy_passed
        and high_cross_entropy_passed
        and lower_history_joint_passed
    )
    return {
        "fixed_cross_entropy_improvement_at_lower_noise": fixed_cross_entropy_improvements,
        "fixed_cross_entropy_increase_at_higher_noise": high_cross_entropy_increase,
        "history_forecast_improvement_at_lower_noise": history_forecast_improvements,
        "history_oracle_brier_improvement_at_lower_noise": history_oracle_brier_improvements,
        "lower_noise_fixed_cross_entropy_gate_passed": lower_cross_entropy_passed,
        "higher_noise_fixed_cross_entropy_gate_passed": high_cross_entropy_passed,
        "lower_noise_history_forecast_and_brier_gate_passed": lower_history_joint_passed,
        "state_compensation_supported": supported,
    }


def verify_sensitivity(
    result_directories: list[str | Path],
) -> dict[str, Any]:
    if len(result_directories) != 4:
        raise ValueError("exactly four sensitivity result directories are required")
    roots = [Path(path).resolve() for path in result_directories]
    records = []
    maximum_metric_difference = 0.0
    for root in roots:
        config = _read_json(root / "config_snapshot.json")
        metrics = _read_json(root / "metrics.json")
        arrays = np.load(root / "daily_arrays.npz", allow_pickle=False)
        verification = verify_result_directory(root)
        standard_deviation = _filter_standard_deviation(config)
        posterior_scores = {}
        for method in METHODS:
            cross_entropy, accuracy = _posterior_label_scores(arrays, method)
            posterior_scores[method] = {
                "posterior_mode_cross_entropy": cross_entropy,
                "posterior_mode_accuracy": accuracy,
            }
            maximum_metric_difference = max(
                maximum_metric_difference,
                abs(
                    cross_entropy
                    - float(
                        metrics["methods"][method]["losses"][
                            "posterior_mode_cross_entropy"
                        ]
                    )
                ),
                abs(
                    accuracy
                    - float(
                        metrics["methods"][method]["losses"][
                            "posterior_mode_accuracy"
                        ]
                    )
                ),
            )
        records.append(
            {
                "root": root,
                "config": config,
                "metrics": metrics,
                "arrays": arrays,
                "verification": verification,
                "standard_deviation": standard_deviation,
                "posterior_scores": posterior_scores,
            }
        )

    by_level = {record["standard_deviation"]: record for record in records}
    if tuple(sorted(by_level)) != EXPECTED_STANDARD_DEVIATIONS:
        raise ValueError("sensitivity results do not cover exactly 0.1 0.3 1.0 and 3.0")
    baseline = by_level[1.0]
    truth_arrays_match = {}
    config_fields_match = {}
    forecast_masks_match = {}
    for level, record in sorted(by_level.items()):
        truth_arrays_match[str(level)] = all(
            np.array_equal(record["arrays"][name], baseline["arrays"][name])
            for name in TRUTH_ARRAYS
        )
        forecast_masks_match[str(level)] = all(
            np.array_equal(
                record["arrays"][f"{method}_forecast_valid_mask"],
                baseline["arrays"][f"{method}_forecast_valid_mask"],
            )
            for method in METHODS
        )
        config_fields_match[str(level)] = all(
            record["config"][name] == baseline["config"][name]
            for name in INVARIANT_CONFIG_FIELDS
        )
        common_filter = dict(record["config"]["filter"])
        common_filter.pop(
            "assumed_lower_groundwater_process_standard_deviation",
            None,
        )
        baseline_filter = dict(baseline["config"]["filter"])
        baseline_filter.pop(
            "assumed_lower_groundwater_process_standard_deviation",
            None,
        )
        config_fields_match[str(level)] = (
            config_fields_match[str(level)] and common_filter == baseline_filter
        )

    sensitivity_levels = {}
    for level, record in sorted(by_level.items()):
        methods = record["metrics"]["methods"]
        sensitivity_levels[level] = {
            "experiment_id": record["config"]["experiment_id"],
            "fixed_posterior_mode_cross_entropy": record["posterior_scores"][
                "fixed"
            ]["posterior_mode_cross_entropy"],
            "fixed_posterior_mode_accuracy": record["posterior_scores"]["fixed"][
                "posterior_mode_accuracy"
            ],
            "history_forecast": float(methods["history_conditioned"]["losses"]["forecast"]),
            "history_oracle_brier": float(
                methods["history_conditioned"]["transition_recovery"]["oracle_brier"]
            ),
            "history_vs_static_forecast_increase": float(
                record["metrics"]["history_vs_learned_static"][
                    "relative_overall_forecast_loss_increase"
                ]
            ),
            "history_vs_static_oracle_brier_reduction": float(
                record["metrics"]["history_vs_learned_static"][
                    "relative_oracle_brier_reduction"
                ]
            ),
            "synthetic_capability_passed": bool(
                record["metrics"]["synthetic_capability_passed"]
            ),
        }

    nonbaseline_records = [by_level[level] for level in (0.1, 0.3, 3.0)]
    criteria = [
        record["config"]["filter_noise_sensitivity_specification"][
            "state_compensation_criterion"
        ]
        for record in nonbaseline_records
    ]
    if not all(criterion == criteria[0] for criterion in criteria[1:]):
        raise ValueError("state-compensation criteria differ across experiments")
    criterion_result = evaluate_state_compensation_criterion(
        sensitivity_levels,
        criteria[0],
    )
    all_verified = (
        all(record["verification"]["all_verified"] for record in records)
        and all(truth_arrays_match.values())
        and all(forecast_masks_match.values())
        and all(config_fields_match.values())
        and maximum_metric_difference <= 1e-12
    )
    return {
        "all_verified": all_verified,
        "truth_arrays_match": truth_arrays_match,
        "forecast_valid_masks_match": forecast_masks_match,
        "invariant_config_fields_match": config_fields_match,
        "maximum_saved_metric_absolute_difference": maximum_metric_difference,
        "levels": {str(level): values for level, values in sensitivity_levels.items()},
        "state_compensation_criterion": criteria[0],
        "state_compensation_result": criterion_result,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("result_directories", nargs=4)
    arguments = parser.parse_args()
    result = verify_sensitivity(arguments.result_directories)
    print(json.dumps(result, indent=2, sort_keys=True))
    if not result["all_verified"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()

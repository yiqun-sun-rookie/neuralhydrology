"""Independently verify an H17 supervised probability artifact directory."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
from pathlib import Path
from typing import Any, Mapping

import numpy as np
import torch


def _is_explicit_duration(config: Mapping[str, Any]) -> bool:
    return (
        config.get("network", {}).get("transition_architecture")
        == "explicit_causal_duration"
    )


def _dynamic_metric_key(config: Mapping[str, Any]) -> str:
    return (
        "explicit_causal_duration_transition_matrix"
        if _is_explicit_duration(config)
        else "recurrent_history_dynamic_matrix"
    )


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _project_root(result_root: Path, supplied: str | Path | None) -> Path | None:
    if supplied is not None:
        return Path(supplied).resolve()
    for candidate in (result_root, *result_root.parents):
        if (candidate / "src/hbv_history_conditioned_imm").is_dir():
            return candidate
    return None


def _independent_scores(
    matrices: np.ndarray,
    source_indices: np.ndarray,
    targets: np.ndarray,
    evaluation_mask: np.ndarray,
    switch_mask: np.ndarray,
    ages: np.ndarray,
) -> dict[str, Any]:
    expected = (*source_indices.shape, 3, 3)
    if matrices.shape != expected:
        raise ValueError(f"transition matrices must have shape {expected}")
    blocks, days = np.nonzero(evaluation_mask)
    sources = source_indices[blocks, days]
    predicted = matrices[blocks, days, sources]
    target = targets[blocks, days]
    squared = np.square(predicted - target).sum(axis=-1)
    tiny = np.finfo(predicted.dtype).tiny
    cross_entropy = np.where(
        target > 0.0,
        -target * np.log(np.clip(predicted, tiny, None)),
        0.0,
    ).sum(axis=-1)
    predicted_hazard = 1.0 - predicted[np.arange(sources.size), sources]
    oracle_hazard = 1.0 - target[np.arange(sources.size), sources]
    hazard_error = np.abs(predicted_hazard - oracle_hazard)
    selected_ages = ages[blocks, days]
    bins = {
        "age_1_29": (selected_ages >= 1) & (selected_ages <= 29),
        "age_30_39": (selected_ages >= 30) & (selected_ages <= 39),
        "age_40_49": (selected_ages >= 40) & (selected_ages <= 49),
        "age_50_plus": selected_ages >= 50,
    }
    age_metrics: dict[str, Any] = {}
    for name, selected in bins.items():
        count = int(np.count_nonzero(selected))
        age_metrics[name] = {
            "count": count,
            "oracle_brier": float(np.mean(squared[selected])) if count else None,
            "switch_hazard_mean_absolute_error": (
                float(np.mean(hazard_error[selected])) if count else None
            ),
            "mean_predicted_switch_hazard": (
                float(np.mean(predicted_hazard[selected])) if count else None
            ),
            "mean_oracle_switch_hazard": (
                float(np.mean(oracle_hazard[selected])) if count else None
            ),
        }
    return {
        "evaluated_transition_count": int(np.count_nonzero(evaluation_mask)),
        "switch_event_count": int(np.count_nonzero(switch_mask)),
        "oracle_brier": float(np.mean(squared)),
        "oracle_cross_entropy": float(np.mean(cross_entropy)),
        "switch_hazard_mean_absolute_error": float(np.mean(hazard_error)),
        "mean_predicted_switch_hazard": float(np.mean(predicted_hazard)),
        "mean_oracle_switch_hazard": float(np.mean(oracle_hazard)),
        "maximum_transition_row_sum_error": float(
            np.max(np.abs(matrices.sum(axis=-1) - 1.0))
        ),
        "minimum_transition_probability": float(np.min(matrices)),
        "age_bin_metrics": age_metrics,
    }


def _close(left: Any, right: Any, *, tolerance: float = 1e-12) -> bool:
    if isinstance(left, Mapping) and isinstance(right, Mapping):
        return set(left) == set(right) and all(
            _close(left[key], right[key], tolerance=tolerance) for key in left
        )
    if left is None or right is None or isinstance(left, (str, bool)):
        return left == right
    if isinstance(left, (int, float)) and isinstance(right, (int, float)):
        return math.isclose(
            float(left), float(right), rel_tol=0.0, abs_tol=tolerance
        )
    return left == right


def _read_history(path: Path) -> list[dict[str, float]]:
    with path.open("r", encoding="utf-8", newline="") as handle:
        rows = [
            {name: float(value) for name, value in row.items()}
            for row in csv.DictReader(handle)
        ]
    return rows


def _checkpoint_checks(
    path: Path,
    history_path: Path,
    *,
    config: Mapping[str, Any],
    expected_method: str,
    expected_seed: int,
    history_requires_statistics: bool,
    expected_experiment_id: str | None = None,
) -> bool:
    checkpoint = torch.load(path, map_location="cpu", weights_only=False)
    history = _read_history(history_path)
    epochs = int(config["training"]["epochs"])
    external_frozen_checkpoint = (
        expected_experiment_id is not None
        and expected_experiment_id != config["experiment_id"]
    )
    if (not external_frozen_checkpoint and len(history) != epochs) or not history:
        return False
    finite_history = all(
        math.isfinite(value) for row in history for value in row.values()
    )
    best_row = min(history, key=lambda row: row["validation_oracle_brier"])
    state = checkpoint.get("network_state_dict", {})
    finite_state = bool(state) and all(
        torch.is_tensor(value) and torch.isfinite(value).all()
        for value in state.values()
    )
    metadata_ok = (
        checkpoint.get("experiment_id")
        == (expected_experiment_id or config["experiment_id"])
        and checkpoint.get("method") == expected_method
        and int(checkpoint.get("initialization_seed", -1)) == expected_seed
        and int(checkpoint.get("best_epoch", -1)) == int(best_row["epoch"])
        and math.isclose(
            float(checkpoint.get("best_validation_brier", math.nan)),
            float(best_row["validation_oracle_brier"]),
            rel_tol=0.0,
            abs_tol=1e-15,
        )
        and checkpoint.get("synthetic_active_row_supervision_used") is True
        and checkpoint.get("truth_state_used") is False
        and checkpoint.get("truth_discharge_used") is False
        and checkpoint.get("true_destination_used") is False
        and checkpoint.get("block_identifier_used") is False
        and checkpoint.get("random_seed_used_as_network_input") is False
        and int(checkpoint.get("test_reads_before_selection", -1)) == 0
    )
    if _is_explicit_duration(config) and expected_method == (
        "explicit_causal_duration_transition_matrix"
    ):
        metadata_ok = bool(
            metadata_ok
            and checkpoint.get("checkpoint_schema_version") == 2
            and checkpoint.get("transition_architecture")
            == "explicit_causal_duration"
            and checkpoint.get("duration_contract")
            == config.get("duration_contract")
            and checkpoint.get("feature_statistics_used") is False
            and checkpoint.get("warm_started") is False
            and checkpoint.get("h17b_recurrent_checkpoint_loaded") is False
        )
    statistics = checkpoint.get("feature_statistics")
    if history_requires_statistics:
        statistics_ok = (
            isinstance(statistics, Mapping)
            and statistics.get("source")
            == "fixed_transition_training_observation_rollout"
            and statistics.get("truth_used") is False
            and statistics.get("supervision_used") is False
            and statistics.get("validation_used") is False
            and statistics.get("test_used") is False
            and torch.isfinite(statistics["feature_mean"]).all()
            and torch.all(statistics["feature_standard_deviation"] > 0.0)
        )
    else:
        statistics_ok = statistics is None
    gradients_reached_network = max(
        row["maximum_absolute_gradient"] for row in history
    ) > 0.0
    return bool(
        finite_history
        and finite_state
        and metadata_ok
        and statistics_ok
        and gradients_reached_network
    )


def _relative_reduction(reference: float, candidate: float) -> float:
    return (float(reference) - float(candidate)) / float(reference)


def verify_h17_result(
    result_directory: str | Path,
    *,
    verify_checksums: bool = True,
    project_root: str | Path | None = None,
) -> dict[str, Any]:
    """Recompute H17 scores, gates, provenance, and checkpoint selection."""

    root = Path(result_directory).resolve()
    config = json.loads((root / "config_snapshot.json").read_text("utf-8"))
    explicit_duration = _is_explicit_duration(config)
    dynamic_metric_key = _dynamic_metric_key(config)
    required = set(str(name) for name in config["required_result_files"])
    found = {path.name for path in root.iterdir() if path.is_file()}
    expected = (
        required
        if verify_checksums
        else required - {"independent_verification.json", "checksums.json"}
    )
    exact_file_set = found == expected

    checksum_coverage = True
    checksum_ok = True
    if verify_checksums:
        checksum_path = root / "checksums.json"
        if not checksum_path.is_file():
            checksum_coverage = False
            checksum_ok = False
        else:
            checksums = json.loads(checksum_path.read_text("utf-8"))
            checksum_coverage = set(checksums) == required - {"checksums.json"}
            checksum_ok = checksum_coverage and all(
                (root / name).is_file() and _sha256(root / name) == digest
                for name, digest in checksums.items()
            )

    resolved_project = _project_root(root, project_root)
    source_hashes_verified = resolved_project is not None
    if resolved_project is not None:
        for name in (
            "source_h16_config_snapshot",
            "source_h16_preflight_arrays",
            "source_h16_preflight_report",
            "source_h16_independent_verification",
        ):
            source = (resolved_project / str(config[name]["path"])).resolve()
            source_hashes_verified = bool(
                source_hashes_verified
                and source.is_file()
                and _sha256(source) == str(config[name]["sha256"])
            )

    with np.load(root / "daily_arrays.npz", allow_pickle=False) as source:
        arrays = {name: source[name] for name in source.files}
    forbidden_array_names = {
        "truth_states",
        "truth_discharge",
        "true_parameter_indices",
        "block_ids",
        "block_seeds",
        "accepted_process_seeds",
        "rejected_process_seeds",
    }
    daily_arrays_exclude_forbidden_truth = not (
        forbidden_array_names & set(arrays)
    )
    sources = np.asarray(arrays["active_source_indices"], dtype=np.int64)
    targets = np.asarray(
        arrays["oracle_active_row_probabilities"], dtype=np.float64
    )
    evaluated = np.asarray(arrays["transition_evaluation_mask"], dtype=np.bool_)
    switched = np.asarray(arrays["switch_event_mask"], dtype=np.bool_)
    ages = np.asarray(arrays["regime_age_before_transition"], dtype=np.int64)
    expected_shape = (
        int(config["data"]["test_blocks"]),
        int(config["data"]["assimilation_days"]),
    )
    supervision_shapes_match = (
        sources.shape == expected_shape
        and targets.shape == (*expected_shape, 3)
        and evaluated.shape == expected_shape
        and switched.shape == expected_shape
        and ages.shape == expected_shape
    )
    evaluation_mask_legal = (
        not np.any(evaluated[:, 0])
        and np.all(evaluated[:, 1:])
        and np.all(switched <= evaluated)
        and np.all(sources[evaluated] >= 0)
        and np.all(sources[evaluated] <= 2)
        and np.max(np.abs(targets[evaluated].sum(axis=-1) - 1.0)) <= 1e-12
    )

    metrics = json.loads((root / "metrics.json").read_text("utf-8"))
    saved_methods: dict[str, Any] = {
        "fixed_transition_matrix": metrics["fixed_transition_matrix"],
        "learned_history_free_static_matrix": metrics[
            "learned_history_free_static_matrix"
        ],
    }
    recomputed_methods: dict[str, Any] = {
        "fixed_transition_matrix": _independent_scores(
            np.asarray(arrays["fixed_transition_matrices"]),
            sources,
            targets,
            evaluated,
            switched,
            ages,
        ),
        "learned_history_free_static_matrix": _independent_scores(
            np.asarray(arrays["static_transition_matrices"]),
            sources,
            targets,
            evaluated,
            switched,
            ages,
        ),
    }
    seeds = tuple(
        int(value)
        for value in config["training"]["history_network_initialization_seeds"]
    )
    history_identifiers_match = np.array_equal(
        np.asarray(arrays["history_seed_ids"], dtype=np.int64),
        np.asarray(seeds, dtype=np.int64),
    )
    for seed in seeds:
        name = str(seed)
        saved_methods[f"history_seed_{seed}"] = dict(
            metrics[dynamic_metric_key][name]
        )
        saved_methods[f"history_seed_{seed}"].pop(
            "relative_oracle_brier_reduction_vs_static", None
        )
        saved_methods[f"history_seed_{seed}"].pop(
            "relative_hazard_mae_reduction_vs_static", None
        )
        recomputed_methods[f"history_seed_{seed}"] = _independent_scores(
            np.asarray(arrays[f"history_seed_{seed}_transition_matrices"]),
            sources,
            targets,
            evaluated,
            switched,
            ages,
        )
    scores_match = all(
        _close(saved_methods[name], recomputed_methods[name])
        for name in recomputed_methods
    )

    stay = float(config["filter"]["base_transition_stay_probability"])
    switch = (1.0 - stay) / 2.0
    expected_base = np.asarray(
        [[stay, switch, switch], [switch, stay, switch], [switch, switch, stay]]
    )
    fixed_matrix_matches = np.array_equal(
        arrays["fixed_transition_matrices"],
        np.broadcast_to(
            expected_base,
            arrays["fixed_transition_matrices"].shape,
        ),
    )
    static_history_invariant = np.array_equal(
        arrays["static_transition_matrices"],
        np.broadcast_to(
            arrays["static_transition_matrices"][:1, :1],
            arrays["static_transition_matrices"].shape,
        ),
    )

    static_scores = recomputed_methods["learned_history_free_static_matrix"]
    thresholds = config["capability_gates"]
    expected_gate_passes: dict[str, bool] = {}
    for method_name in (
        "fixed_transition_matrix",
        "learned_history_free_static_matrix",
    ):
        recomputed = recomputed_methods[method_name]
        expected_gate_passes[f"{method_name}_row_stochastic"] = (
            float(recomputed["maximum_transition_row_sum_error"])
            <= float(thresholds["maximum_transition_row_sum_error"])
        )
        expected_gate_passes[f"{method_name}_nonnegative_probability"] = (
            float(recomputed["minimum_transition_probability"])
            >= float(thresholds["minimum_transition_probability"])
        )
    reductions_match = True
    for seed in seeds:
        saved = metrics[dynamic_metric_key][str(seed)]
        recomputed = recomputed_methods[f"history_seed_{seed}"]
        brier_reduction = _relative_reduction(
            static_scores["oracle_brier"], recomputed["oracle_brier"]
        )
        hazard_reduction = _relative_reduction(
            static_scores["switch_hazard_mean_absolute_error"],
            recomputed["switch_hazard_mean_absolute_error"],
        )
        reductions_match = bool(
            reductions_match
            and math.isclose(
                brier_reduction,
                float(saved["relative_oracle_brier_reduction_vs_static"]),
                rel_tol=0.0,
                abs_tol=1e-12,
            )
            and math.isclose(
                hazard_reduction,
                float(saved["relative_hazard_mae_reduction_vs_static"]),
                rel_tol=0.0,
                abs_tol=1e-12,
            )
        )
        expected_gate_passes[f"history_seed_{seed}_oracle_brier_reduction"] = (
            brier_reduction
            >= float(
                thresholds[
                    "minimum_each_history_seed_relative_oracle_brier_reduction_vs_static"
                ]
            )
        )
        expected_gate_passes[f"history_seed_{seed}_hazard_mae_reduction"] = (
            hazard_reduction
            >= float(
                thresholds[
                    "minimum_each_history_seed_relative_hazard_mae_reduction_vs_static"
                ]
            )
        )
        expected_gate_passes[f"history_seed_{seed}_row_stochastic"] = (
            float(recomputed["maximum_transition_row_sum_error"])
            <= float(thresholds["maximum_transition_row_sum_error"])
        )
        expected_gate_passes[f"history_seed_{seed}_nonnegative_probability"] = (
            float(recomputed["minimum_transition_probability"])
            >= float(thresholds["minimum_transition_probability"])
        )

    causality = json.loads((root / "causality_audit.json").read_text("utf-8"))
    causal_values_match = (
        float(causality["maximum_current_observation_effect_on_same_day_transition"])
        == max(
            float(values["current_observation_effect_on_same_day_transition"])
            for values in causality["per_seed"].values()
        )
        and float(causality["maximum_future_observation_effect_on_earlier_transition"])
        == max(
            float(values["future_observation_effect_on_earlier_transition"])
            for values in causality["per_seed"].values()
        )
    )
    if explicit_duration:
        causal_values_match = bool(
            causal_values_match
            and float(causality["minimum_duration_state_effect_on_transition"])
            == min(
                float(values["duration_state_effect_on_transition"])
                for values in causality["per_seed"].values()
            )
            and float(
                causality["minimum_past_observation_effect_on_later_transition"]
            )
            == min(
                float(values["past_observation_effect_on_later_transition"])
                for values in causality["per_seed"].values()
            )
        )
        positive_causal_gate = {
            "duration_state_changes_transition": float(
                causality["minimum_duration_state_effect_on_transition"]
            )
            > float(
                thresholds[
                    "minimum_permitted_duration_state_effect_on_transition"
                ]
            )
        }
    else:
        causal_values_match = bool(
            causal_values_match
            and float(
                causality[
                    "minimum_permitted_prior_forcing_effect_on_next_transition"
                ]
            )
            == min(
                float(values["permitted_prior_forcing_effect_on_next_transition"])
                for values in causality["per_seed"].values()
            )
        )
        positive_causal_gate = {
            "prior_forcing_can_change_next_transition": float(
                causality[
                    "minimum_permitted_prior_forcing_effect_on_next_transition"
                ]
            )
            > float(
                thresholds[
                    "minimum_permitted_prior_forcing_effect_on_next_transition"
                ]
            )
        }
    expected_gate_passes.update(
        {
            "current_observation_cannot_change_same_day_transition": float(
                causality[
                    "maximum_current_observation_effect_on_same_day_transition"
                ]
            )
            <= float(
                thresholds[
                    "maximum_current_observation_effect_on_same_day_transition"
                ]
            ),
            "future_observation_cannot_change_earlier_transition": float(
                causality[
                    "maximum_future_observation_effect_on_earlier_transition"
                ]
            )
            <= float(
                thresholds[
                    "maximum_future_observation_effect_on_earlier_transition"
                ]
            ),
            **positive_causal_gate,
            "no_forbidden_training_inputs": int(
                causality["forbidden_training_input_count"]
            )
            <= int(thresholds["maximum_forbidden_training_input_count"]),
            "no_test_reads_before_checkpoint_selection": int(
                causality["test_reads_before_all_checkpoint_selections"]
            )
            <= int(
                thresholds[
                    "maximum_test_reads_before_all_checkpoint_selections"
                ]
            ),
        }
    )
    saved_gates = metrics["capability_gates"]
    gate_logic_matches = all(
        bool(saved_gates[name]["passed"]) == passed
        for name, passed in expected_gate_passes.items()
    )
    expected_all_passed = all(expected_gate_passes.values())
    gate_logic_matches = bool(
        gate_logic_matches
        and bool(saved_gates["all_capability_gates_passed"])
        == expected_all_passed
        and bool(metrics["supervised_probability_capability_passed"])
        == expected_all_passed
    )

    normalization = json.loads(
        (root / "normalization_audit.json").read_text("utf-8")
    )
    normalization_matches = (
        normalization["source"]
        == "fixed_transition_training_observation_rollout"
        and int(normalization["feature_count"]) == 21
        and normalization["truth_used"] is False
        and normalization["supervision_used"] is False
        and normalization["validation_used"] is False
        and normalization["test_used"] is False
        and normalization.get("used_by_transition_module", True)
        is (not explicit_duration)
        and np.isfinite(arrays["feature_mean"]).all()
        and np.all(arrays["feature_standard_deviation"] > 0.0)
        and math.isclose(
            float(np.min(arrays["feature_standard_deviation"])),
            float(normalization["minimum_feature_standard_deviation"]),
            rel_tol=0.0,
            abs_tol=1e-15,
        )
    )

    checkpoints_ok = _checkpoint_checks(
        root / "static_best_checkpoint.pt",
        root / "static_training_history.csv",
        config=config,
        expected_method="learned_history_free_static_matrix",
        expected_seed=int(config["training"]["static_matrix_initialization_seed"]),
        history_requires_statistics=False,
        expected_experiment_id=str(
            config.get("source_h17_static_reference", {}).get(
                "experiment_id", config["experiment_id"]
            )
        ),
    )
    for seed in seeds:
        checkpoints_ok = bool(
            checkpoints_ok
            and _checkpoint_checks(
                root / f"history_seed_{seed}_best_checkpoint.pt",
                root / f"history_seed_{seed}_training_history.csv",
                config=config,
                expected_method=dynamic_metric_key,
                expected_seed=seed,
                history_requires_statistics=not explicit_duration,
            )
        )

    registry = json.loads((root / "registry_entry.json").read_text("utf-8"))
    if config.get("experiment_kind") == "supervised_probability_repair":
        if explicit_duration:
            expected_status = (
                "completed_supervised_repair_diagnostic_pass"
                if expected_all_passed
                else "completed_supervised_repair_diagnostic_hold"
            )
        else:
            expected_status = (
                "completed_supervised_repair_go"
                if expected_all_passed
                else "completed_supervised_repair_hold"
            )
    else:
        expected_status = (
            "completed_supervised_upper_bound_go"
            if expected_all_passed
            else "completed_supervised_upper_bound_hold"
        )
    registry_matches = (
        registry.get("exp_id") == config["experiment_id"]
        and registry.get("run_dir") == config["result_relative_path"]
        and registry.get("status") == expected_status
    )
    claim_boundary_matches = (
        metrics["claim_boundary"] == config["claim_boundary"]
        and metrics["method_contract"] == config["method_contract"]
        and metrics["synthetic_active_row_supervision_used"] is True
        and metrics["physical_filter_gradient_stopped"] is True
        and metrics["recurrent_hidden_gradient_retained"]
        is (not explicit_duration)
        and metrics.get("duration_state_gradient_retained", False)
        is explicit_duration
        and metrics["strict_observation_evidence_learning_established"] is False
        and metrics["state_superiority_established"] is False
        and metrics["forecast_value_established"] is False
        and metrics["closed_loop_stability_established"] is False
        and metrics["real_basin_claim_established"] is False
        and metrics["h18_registered_or_run"] is False
    )
    checks = {
        "exact_required_file_set": bool(exact_file_set),
        "checksum_coverage": bool(checksum_coverage),
        "checksums": bool(checksum_ok),
        "frozen_h16_source_hashes": bool(source_hashes_verified),
        "daily_arrays_exclude_forbidden_truth_and_metadata": bool(
            daily_arrays_exclude_forbidden_truth
        ),
        "supervision_shapes_match_config": bool(supervision_shapes_match),
        "evaluation_mask_and_targets_are_legal": bool(evaluation_mask_legal),
        "history_seed_identifiers_match": bool(history_identifiers_match),
        "independently_recomputed_scores_match": bool(scores_match),
        "relative_reductions_match": bool(reductions_match),
        "fixed_transition_matrices_match_config": bool(fixed_matrix_matches),
        "learned_static_matrix_is_history_invariant": bool(static_history_invariant),
        "causality_aggregates_match_per_seed_values": bool(causal_values_match),
        "capability_gate_logic_matches": bool(gate_logic_matches),
        "normalization_is_training_observation_only": bool(normalization_matches),
        "validation_checkpoint_selection_and_metadata_match": bool(
            checkpoints_ok
        ),
        "registry_status_matches_decision": bool(registry_matches),
        "scientific_claim_boundary_matches": bool(claim_boundary_matches),
    }
    return {
        "experiment_id": config["experiment_id"],
        "verified": all(checks.values()),
        "checksum_verification_requested": bool(verify_checksums),
        "checks": checks,
        "independent_values": {
            "static_oracle_brier": static_scores["oracle_brier"],
            "static_hazard_mean_absolute_error": static_scores[
                "switch_hazard_mean_absolute_error"
            ],
            "each_history_seed_relative_oracle_brier_reduction": {
                str(seed): _relative_reduction(
                    static_scores["oracle_brier"],
                    recomputed_methods[f"history_seed_{seed}"]["oracle_brier"],
                )
                for seed in seeds
            },
            "each_history_seed_relative_hazard_mae_reduction": {
                str(seed): _relative_reduction(
                    static_scores["switch_hazard_mean_absolute_error"],
                    recomputed_methods[f"history_seed_{seed}"][
                        "switch_hazard_mean_absolute_error"
                    ],
                )
                for seed in seeds
            },
            "all_capability_gates_passed": expected_all_passed,
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("result_directory")
    parser.add_argument("--project-root")
    arguments = parser.parse_args()
    result = verify_h17_result(
        arguments.result_directory, project_root=arguments.project_root
    )
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()

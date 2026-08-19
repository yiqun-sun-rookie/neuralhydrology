"""Run the H17 supervised active-row probability upper-bound experiment."""

from __future__ import annotations

import argparse
import csv
from dataclasses import dataclass, replace
import json
import math
import os
import platform
import shutil
import sys
import zipfile
from pathlib import Path
from typing import Any, Mapping

import numpy as np
import torch

from hbv_history_conditioned_imm.causal_duration import (
    CausalSemiMarkovTransitionModule,
    ModeDurationState,
)
from hbv_history_conditioned_imm.filter import (
    DifferentiableInteractingMultipleModel,
)
from hbv_history_conditioned_imm.hbv import HBV15Model
from hbv_history_conditioned_imm.long_history import ObservableAssimilationBatch
from hbv_history_conditioned_imm.network import (
    HistoryTransitionNetwork,
    StaticTransitionNetwork,
)
from hbv_history_conditioned_imm.parameter_switch import (
    build_parameter_candidates,
)
from hbv_history_conditioned_imm.scripts.run_h01_end_to_end_smoke import (
    _git_head,
    _sha256,
    _write_json,
    load_registry_row,
)
from hbv_history_conditioned_imm.scripts.verify_h17_supervised_probability_upper_bound import (
    verify_h17_result,
)
from hbv_history_conditioned_imm.supervised_probability import (
    ActiveRowSupervision,
    ObservableFeatureStatistics,
    ProbabilityRolloutResult,
    ProbabilityTrainingProgress,
    ProbabilityTrainingResult,
    build_age_source_balancing_weights,
    fit_observable_feature_statistics,
    rollout_history_probability,
    rollout_semi_markov_probability,
    rollout_static_probability,
    score_probability_rollout,
    train_supervised_probability,
    train_supervised_probability_chunk,
)


DynamicTransitionNetwork = (
    HistoryTransitionNetwork | CausalSemiMarkovTransitionModule
)


PACKAGE_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CONFIG_PATH = (
    PACKAGE_ROOT
    / "configs/h17_supervised_active_row_probability_upper_bound_v01.json"
)


@dataclass(frozen=True)
class H17DataSplit:
    """Separated observable inputs and authorized synthetic supervision."""

    name: str
    observable: ObservableAssimilationBatch
    supervision: ActiveRowSupervision


def load_h17_config(path: str | Path) -> dict[str, Any]:
    """Load and validate the frozen H17 experiment identity."""

    with Path(path).open("r", encoding="utf-8") as handle:
        config = json.load(handle)
    required = {
        "experiment_id",
        "result_relative_path",
        "source_h16_config_snapshot",
        "source_h16_preflight_arrays",
        "source_h16_preflight_report",
        "source_h16_independent_verification",
        "base_parameters",
        "parameter_candidates",
        "data",
        "controls",
        "method_contract",
        "filter",
        "network",
        "normalization",
        "supervision_contract",
        "closed_loop_gradient_contract",
        "training",
        "loss",
        "capability_gates",
        "required_result_files",
    }
    missing = required - set(config)
    if missing:
        raise ValueError(f"H17 configuration is missing fields: {sorted(missing)}")
    if config["experiment_id"] != (
        "h17_supervised_active_row_probability_upper_bound_v01"
    ):
        raise ValueError("unexpected H17 experiment identifier")
    seeds = tuple(config["training"]["history_network_initialization_seeds"])
    if len(seeds) != 3 or len(set(seeds)) != 3:
        raise ValueError("H17 requires exactly three recurrent initialization seeds")
    required_files = tuple(str(name) for name in config["required_result_files"])
    if not required_files or len(required_files) != len(set(required_files)):
        raise ValueError("required H17 result files must be nonempty and unique")
    for seed in seeds:
        for suffix in ("training_history.csv", "best_checkpoint.pt"):
            if f"history_seed_{seed}_{suffix}" not in required_files:
                raise ValueError("H17 recurrent artifacts do not match configured seeds")
    return config


def _source_paths(
    config: Mapping[str, Any], project_root: Path
) -> dict[str, tuple[Path, str]]:
    names = (
        "source_h16_config_snapshot",
        "source_h16_preflight_arrays",
        "source_h16_preflight_report",
        "source_h16_independent_verification",
    )
    return {
        name: (
            (project_root / str(config[name]["path"])).resolve(),
            str(config[name]["sha256"]),
        )
        for name in names
    }


def _verify_h16_sources(
    config: Mapping[str, Any], project_root: Path
) -> dict[str, Any]:
    sources = _source_paths(config, project_root)
    hashes: dict[str, dict[str, Any]] = {}
    for name, (path, expected) in sources.items():
        if not path.is_file():
            raise FileNotFoundError(f"missing frozen H16 source: {path}")
        observed = _sha256(path)
        verified = observed == expected
        hashes[name] = {
            "path": str(path.relative_to(project_root)),
            "expected_sha256": expected,
            "observed_sha256": observed,
            "verified": verified,
        }
        if not verified:
            raise ValueError(f"H16 source hash mismatch: {name}")
    report_path = sources["source_h16_preflight_report"][0]
    verification_path = sources["source_h16_independent_verification"][0]
    report = json.loads(report_path.read_text(encoding="utf-8"))
    independent = json.loads(verification_path.read_text(encoding="utf-8"))
    if report.get("preflight_passed") is not True:
        raise ValueError("H16 preflight did not authorize H17 implementation")
    if independent.get("verified") is not True:
        raise ValueError("H16 independent verification did not pass")
    return {
        "source_hashes": hashes,
        "all_source_hashes_verified": all(
            bool(values["verified"]) for values in hashes.values()
        ),
        "h16_preflight_passed": True,
        "h16_independent_verification_passed": True,
        "forbidden_training_input_count": 0,
    }


def load_h17_data_split(
    config: Mapping[str, Any],
    project_root: str | Path,
    split_name: str,
) -> tuple[H17DataSplit, dict[str, Any]]:
    """Load one split without exposing truth, identifiers, or seeds to training."""

    if split_name not in {"training", "validation", "test"}:
        raise ValueError("H17 split must be training, validation, or test")
    root = Path(project_root).resolve()
    audit = _verify_h16_sources(config, root)
    arrays_path = _source_paths(config, root)["source_h16_preflight_arrays"][0]
    count = int(config["data"][f"{split_name}_blocks"])
    days = int(config["data"]["assimilation_days"])
    with np.load(arrays_path, allow_pickle=False) as source:
        labels = np.asarray(source["split_labels"]).astype(str)
        available = np.flatnonzero(labels == split_name)
        if count <= 0 or available.size < count:
            raise ValueError(f"H16 does not contain the requested {split_name} blocks")
        selected = available[:count]
        if days <= 1 or source["forcing"].shape[1] < days:
            raise ValueError("H16 does not cover the requested assimilation days")
        observable = ObservableAssimilationBatch(
            forcing=torch.as_tensor(
                np.asarray(source["forcing"])[selected, :days],
                dtype=torch.float64,
            ).clone(),
            observations=torch.as_tensor(
                np.asarray(source["observations"])[selected, :days],
                dtype=torch.float64,
            ).clone(),
            initial_states=torch.as_tensor(
                np.asarray(source["initial_states"])[selected],
                dtype=torch.float64,
            ).clone(),
            initial_covariances=torch.as_tensor(
                np.asarray(source["initial_covariances"])[selected],
                dtype=torch.float64,
            ).clone(),
            assimilation_days=days,
        )
        supervision = ActiveRowSupervision(
            source_indices=torch.as_tensor(
                np.asarray(source["active_source_indices"])[selected, :days],
                dtype=torch.int64,
            ).clone(),
            target_probabilities=torch.as_tensor(
                np.asarray(source["oracle_active_row_probabilities"])[
                    selected, :days
                ],
                dtype=torch.float64,
            ).clone(),
            evaluation_mask=torch.as_tensor(
                np.asarray(source["transition_evaluation_mask"])[selected, :days],
                dtype=torch.bool,
            ).clone(),
            switch_event_mask=torch.as_tensor(
                np.asarray(source["switch_event_mask"])[selected, :days],
                dtype=torch.bool,
            ).clone(),
            regime_age_before_transition=torch.as_tensor(
                np.asarray(source["regime_age_before_transition"])[selected, :days],
                dtype=torch.int64,
            ).clone(),
        )
    audit = {
        **audit,
        "split": split_name,
        "selected_block_count": count,
        "assimilation_days": days,
        "network_observable_fields": [
            "forcing through previous day",
            "previous global posterior fifteen-state mean",
            "previous posterior candidate probabilities",
        ],
        "synthetic_supervision_fields": [
            "active source index",
            "active source row oracle probabilities",
            "evaluation mask",
            "switch event mask",
            "prior regime age",
        ],
        "truth_state_used": False,
        "truth_discharge_used": False,
        "true_destination_used": False,
        "block_identifier_used": False,
        "random_seed_used": False,
    }
    return H17DataSplit(split_name, observable, supervision), audit


def _base_transition(config: Mapping[str, Any]) -> torch.Tensor:
    stay = float(config["filter"]["base_transition_stay_probability"])
    if not 0.0 < stay < 1.0:
        raise ValueError("base stay probability must be inside zero and one")
    switch = (1.0 - stay) / 2.0
    return torch.tensor(
        [[stay, switch, switch], [switch, stay, switch], [switch, switch, stay]],
        dtype=torch.float64,
    )


def _parameter_candidates(
    config: Mapping[str, Any],
) -> dict[str, dict[str, float]]:
    candidates = build_parameter_candidates(
        config["base_parameters"], config["parameter_candidates"]["values"]
    )
    if tuple(candidates) != tuple(config["parameter_candidates"]["ids"]):
        raise ValueError("H17 candidate order differs from the frozen contract")
    return candidates


def _estimator(
    config: Mapping[str, Any],
    candidates: Mapping[str, Mapping[str, float]],
) -> DifferentiableInteractingMultipleModel:
    state_names = {"SUZ": 3, "SLZ": 4}
    state_name = str(config["filter"]["process_state_name"])
    if state_name not in state_names:
        raise ValueError("H17 process state must be SUZ or SLZ")
    covariance = torch.zeros((3, 15, 15), dtype=torch.float64)
    process_sd = float(config["filter"]["common_process_standard_deviation"])
    covariance[:, state_names[state_name], state_names[state_name]] = process_sd**2
    return DifferentiableInteractingMultipleModel(
        models=tuple(HBV15Model(parameters) for parameters in candidates.values()),
        process_covariances=covariance,
        observation_variance=float(
            config["filter"]["observation_standard_deviation"]
        )
        ** 2,
    )


def _history_network(
    config: Mapping[str, Any],
    base_transition: torch.Tensor,
    statistics: ObservableFeatureStatistics,
) -> DynamicTransitionNetwork:
    if _is_explicit_duration(config):
        return CausalSemiMarkovTransitionModule(
            base_transition=base_transition,
            maximum_age=int(config["duration_contract"]["maximum_age"]),
            hazard_hidden_size=int(
                config["duration_contract"]["hazard_hidden_size"]
            ),
            maximum_logit_correction=float(
                config["duration_contract"]["maximum_logit_correction"]
            ),
            minimum_differentiable_mode_probability=float(
                config["duration_contract"].get(
                    "minimum_differentiable_mode_probability", 1e-12
                )
            ),
            age_risk_representation=str(
                config["duration_contract"].get(
                    "age_risk_representation", "smooth_tanh_network"
                )
            ),
            piecewise_knot_count=int(
                config["duration_contract"].get("piecewise_knot_count", 31)
            ),
        )
    return HistoryTransitionNetwork(
        base_transition=base_transition,
        feature_mean=statistics.feature_mean,
        feature_standard_deviation=statistics.feature_standard_deviation,
        hidden_size=int(config["network"]["hidden_size"]),
        maximum_logit_correction=float(
            config["network"]["maximum_logit_correction"]
        ),
        output_parameterization=str(
            config["network"].get("output_parameterization", "full_matrix")
        ),
    )


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


def _dynamic_method_name(config: Mapping[str, Any]) -> str:
    return _dynamic_metric_key(config)


def _rollout_dynamic_probability(
    split: H17DataSplit,
    network: DynamicTransitionNetwork,
    estimator: DifferentiableInteractingMultipleModel,
) -> ProbabilityRolloutResult:
    if isinstance(network, CausalSemiMarkovTransitionModule):
        return rollout_semi_markov_probability(
            split.observable,
            split.supervision,
            network,
            estimator,
        )
    return rollout_history_probability(
        split.observable,
        split.supervision,
        network,
        estimator,
    )


def _static_network(
    config: Mapping[str, Any], base_transition: torch.Tensor
) -> StaticTransitionNetwork:
    return StaticTransitionNetwork(
        base_transition=base_transition,
        maximum_logit_correction=float(
            config["network"]["maximum_logit_correction"]
        ),
    )


def _training_arguments(config: Mapping[str, Any]) -> dict[str, Any]:
    values = config["training"]
    return {
        "epochs": int(values["epochs"]),
        "learning_rate": float(values["learning_rate"]),
        "weight_decay": float(values["weight_decay"]),
        "gradient_clip_norm": float(values["gradient_clip_norm"]),
        "training_objective": str(
            values.get("objective", "active_row_brier")
        ),
    }


def _training_weights_and_audit(
    config: Mapping[str, Any],
    supervision: ActiveRowSupervision,
) -> tuple[torch.Tensor | None, dict[str, Any] | None]:
    weighting = str(config["training"].get("sample_weighting", "uniform"))
    if weighting == "uniform":
        return None, None
    if weighting != "sqrt_inverse_age_source_frequency":
        raise ValueError("unknown supervised probability sample weighting")
    weights = build_age_source_balancing_weights(supervision)
    mask = supervision.evaluation_mask
    ages = supervision.regime_age_before_transition[mask]
    sources = supervision.source_indices[mask]
    age_groups = torch.where(
        ages < 30,
        torch.zeros_like(ages),
        torch.where(ages < 40, torch.ones_like(ages), torch.full_like(ages, 2)),
    )
    counts = torch.zeros((3, 3), dtype=torch.int64)
    mean_weights = torch.zeros((3, 3), dtype=torch.float64)
    selected_weights = weights[mask]
    for age_group in range(3):
        for source in range(3):
            selected = (age_groups == age_group) & (sources == source)
            counts[age_group, source] = int(selected.sum())
            if torch.any(selected):
                mean_weights[age_group, source] = selected_weights[selected].mean()
    audit = {
        "method": weighting,
        "age_groups": ["age_1_29", "age_30_39", "age_40_plus"],
        "source_order": list(config["parameter_candidates"]["ids"]),
        "training_cell_counts": counts.tolist(),
        "training_cell_mean_weights": mean_weights.tolist(),
        "evaluated_training_day_count": int(mask.sum()),
        "mean_evaluated_training_weight": float(selected_weights.mean()),
        "minimum_evaluated_training_weight": float(selected_weights.min()),
        "maximum_evaluated_training_weight": float(selected_weights.max()),
        "weights_computed_from_training_supervision_only": True,
        "validation_read_count_for_weighting": 0,
        "test_read_count_for_weighting": 0,
        "validation_metrics_weighted": False,
        "test_metrics_weighted": False,
    }
    return weights, audit


def _progress_printer(label: str):
    def print_record(record: Mapping[str, float]) -> None:
        epoch = int(record["epoch"])
        print(
            f"{label} epoch={epoch} "
            f"train_brier={record['training_oracle_brier']:.9f} "
            f"validation_brier={record['validation_oracle_brier']:.9f}",
            flush=True,
        )

    return print_record


def _relative_reduction(reference: float, candidate: float) -> float:
    if not math.isfinite(reference) or not math.isfinite(candidate) or reference <= 0.0:
        raise ValueError("relative reduction requires finite values and positive reference")
    return (reference - candidate) / reference


def evaluate_probability_gates(
    config: Mapping[str, Any],
    metrics: Mapping[str, Any],
    causality_audit: Mapping[str, Any],
) -> dict[str, Any]:
    """Apply the frozen every-seed capability and interface thresholds."""

    thresholds = config["capability_gates"]
    static = metrics["learned_history_free_static_matrix"]
    histories = metrics[_dynamic_metric_key(config)]
    gates: dict[str, Any] = {}
    for method_name in (
        "fixed_transition_matrix",
        "learned_history_free_static_matrix",
    ):
        if method_name not in metrics:
            continue
        method_values = metrics[method_name]
        if "maximum_transition_row_sum_error" in method_values:
            row_error = float(method_values["maximum_transition_row_sum_error"])
            gates[f"{method_name}_row_stochastic"] = {
                "value": row_error,
                "threshold_maximum": float(
                    thresholds["maximum_transition_row_sum_error"]
                ),
                "passed": row_error
                <= float(thresholds["maximum_transition_row_sum_error"]),
            }
        if "minimum_transition_probability" in method_values:
            minimum_probability = float(
                method_values["minimum_transition_probability"]
            )
            gates[f"{method_name}_nonnegative_probability"] = {
                "value": minimum_probability,
                "threshold_minimum": float(
                    thresholds["minimum_transition_probability"]
                ),
                "passed": minimum_probability
                >= float(thresholds["minimum_transition_probability"]),
            }
    for seed in config["training"]["history_network_initialization_seeds"]:
        name = str(seed)
        values = histories[name]
        brier_reduction = _relative_reduction(
            float(static["oracle_brier"]), float(values["oracle_brier"])
        )
        hazard_reduction = _relative_reduction(
            float(static["switch_hazard_mean_absolute_error"]),
            float(values["switch_hazard_mean_absolute_error"]),
        )
        gates[f"history_seed_{seed}_oracle_brier_reduction"] = {
            "value": brier_reduction,
            "threshold_minimum": float(
                thresholds[
                    "minimum_each_history_seed_relative_oracle_brier_reduction_vs_static"
                ]
            ),
            "passed": brier_reduction
            >= float(
                thresholds[
                    "minimum_each_history_seed_relative_oracle_brier_reduction_vs_static"
                ]
            ),
        }
        gates[f"history_seed_{seed}_hazard_mae_reduction"] = {
            "value": hazard_reduction,
            "threshold_minimum": float(
                thresholds[
                    "minimum_each_history_seed_relative_hazard_mae_reduction_vs_static"
                ]
            ),
            "passed": hazard_reduction
            >= float(
                thresholds[
                    "minimum_each_history_seed_relative_hazard_mae_reduction_vs_static"
                ]
            ),
        }
        row_error = float(values["maximum_transition_row_sum_error"])
        gates[f"history_seed_{seed}_row_stochastic"] = {
            "value": row_error,
            "threshold_maximum": float(
                thresholds["maximum_transition_row_sum_error"]
            ),
            "passed": row_error
            <= float(thresholds["maximum_transition_row_sum_error"]),
        }
        minimum_probability = float(values["minimum_transition_probability"])
        gates[f"history_seed_{seed}_nonnegative_probability"] = {
            "value": minimum_probability,
            "threshold_minimum": float(
                thresholds["minimum_transition_probability"]
            ),
            "passed": minimum_probability
            >= float(thresholds["minimum_transition_probability"]),
        }
    common_causal_definitions = (
        (
            "current_observation_cannot_change_same_day_transition",
            "maximum_current_observation_effect_on_same_day_transition",
            "maximum_current_observation_effect_on_same_day_transition",
            "maximum",
        ),
        (
            "future_observation_cannot_change_earlier_transition",
            "maximum_future_observation_effect_on_earlier_transition",
            "maximum_future_observation_effect_on_earlier_transition",
            "maximum",
        ),
    )
    positive_causal_definition = (
        (
            "duration_state_changes_transition",
            "minimum_duration_state_effect_on_transition",
            "minimum_permitted_duration_state_effect_on_transition",
            "strict_minimum",
        )
        if _is_explicit_duration(config)
        else (
            "prior_forcing_can_change_next_transition",
            "minimum_permitted_prior_forcing_effect_on_next_transition",
            "minimum_permitted_prior_forcing_effect_on_next_transition",
            "strict_minimum",
        )
    )
    causal_definitions = (
        *common_causal_definitions,
        positive_causal_definition,
        (
            "no_forbidden_training_inputs",
            "forbidden_training_input_count",
            "maximum_forbidden_training_input_count",
            "maximum",
        ),
        (
            "no_test_reads_before_checkpoint_selection",
            "test_reads_before_all_checkpoint_selections",
            "maximum_test_reads_before_all_checkpoint_selections",
            "maximum",
        ),
    )
    for gate_name, value_name, threshold_name, direction in causal_definitions:
        value = causality_audit[value_name]
        threshold = thresholds[threshold_name]
        if direction == "strict_minimum":
            passed = float(value) > float(threshold)
            gates[gate_name] = {
                "value": value,
                "threshold_strict_minimum": threshold,
                "passed": passed,
            }
        else:
            passed = float(value) <= float(threshold)
            gates[gate_name] = {
                "value": value,
                "threshold_maximum": threshold,
                "passed": passed,
            }
    gates["all_capability_gates_passed"] = all(
        bool(values["passed"])
        for name, values in gates.items()
        if name != "all_capability_gates_passed"
    )
    return gates


def _write_history(
    path: Path, history: tuple[Mapping[str, float], ...]
) -> None:
    if not history:
        raise ValueError("training history cannot be empty")
    temporary = path.with_suffix(path.suffix + ".tmp")
    with temporary.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(history[0]))
        writer.writeheader()
        writer.writerows(history)
    temporary.replace(path)


def _save_checkpoint(
    path: Path,
    *,
    experiment_id: str,
    method: str,
    seed: int,
    training: ProbabilityTrainingResult,
    statistics: ObservableFeatureStatistics | None,
    transition_architecture: str | None = None,
    duration_contract: Mapping[str, Any] | None = None,
) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    payload: dict[str, Any] = {
        "experiment_id": experiment_id,
        "method": method,
        "initialization_seed": int(seed),
        "best_epoch": int(training.best_epoch),
        "best_validation_brier": float(training.best_validation_brier),
        "network_state_dict": dict(training.best_network_state),
        "synthetic_active_row_supervision_used": True,
        "truth_state_used": False,
        "truth_discharge_used": False,
        "true_destination_used": False,
        "block_identifier_used": False,
        "random_seed_used_as_network_input": False,
        "test_reads_before_selection": int(training.test_reads_before_selection),
    }
    if transition_architecture is not None:
        payload.update(
            {
                "checkpoint_schema_version": 2,
                "transition_architecture": str(transition_architecture),
                "feature_statistics_used": statistics is not None,
                "warm_started": False,
                "h17b_recurrent_checkpoint_loaded": False,
            }
        )
    if duration_contract is not None:
        payload["duration_contract"] = dict(duration_contract)
    if statistics is not None:
        payload["feature_statistics"] = {
            "feature_mean": statistics.feature_mean,
            "feature_standard_deviation": statistics.feature_standard_deviation,
            "source": statistics.source,
            "truth_used": statistics.truth_used,
            "supervision_used": statistics.supervision_used,
            "validation_used": statistics.validation_used,
            "test_used": statistics.test_used,
        }
    torch.save(payload, temporary)
    temporary.replace(path)


def _fixed_probability_rollout(
    supervision: ActiveRowSupervision,
    base_transition: torch.Tensor,
) -> ProbabilityRolloutResult:
    blocks, days = supervision.source_indices.shape
    matrices = base_transition.expand(blocks, days, -1, -1).clone()
    scores = score_probability_rollout(matrices, supervision)
    loss = torch.as_tensor(scores.oracle_brier, dtype=base_transition.dtype)
    return ProbabilityRolloutResult(
        loss=loss,
        transition_matrices=matrices,
        scores=scores,
        physical_filter_gradient_stopped=True,
    )


def _causality_audit(
    split: H17DataSplit,
    histories: Mapping[str, tuple[DynamicTransitionNetwork, ProbabilityRolloutResult]],
    estimator_factory,
    *,
    forbidden_training_input_count: int,
    test_reads_before_selection: int,
) -> dict[str, Any]:
    explicit_duration = all(
        isinstance(network, CausalSemiMarkovTransitionModule)
        for network, _ in histories.values()
    )
    if explicit_duration != any(
        isinstance(network, CausalSemiMarkovTransitionModule)
        for network, _ in histories.values()
    ):
        raise ValueError("causality audit cannot mix transition architectures")
    day = 3 if explicit_duration else 1
    if split.observable.assimilation_days <= day + 1:
        raise ValueError("causality audit does not have enough assimilation days")
    per_seed: dict[str, Any] = {}
    for seed, (network, baseline_result) in histories.items():
        baseline = baseline_result.transition_matrices.detach()
        current_values = split.observable.observations.clone()
        current_values[:, day] += 5.0
        current_observable = replace(
            split.observable, observations=current_values
        )
        current = _rollout_dynamic_probability(
            H17DataSplit(split.name, current_observable, split.supervision),
            network,
            estimator_factory(),
        ).transition_matrices.detach()
        future_values = split.observable.observations.clone()
        future_values[:, day + 1] += 5.0
        future_observable = replace(split.observable, observations=future_values)
        future = _rollout_dynamic_probability(
            H17DataSplit(split.name, future_observable, split.supervision),
            network,
            estimator_factory(),
        ).transition_matrices.detach()
        seed_values: dict[str, Any] = {
            "audit_transition_day": day,
            "current_observation_perturbation": 5.0,
            "future_observation_perturbation": 5.0,
            "current_observation_effect_on_same_day_transition": float(
                torch.max(torch.abs(baseline[:, day] - current[:, day]))
            ),
            "future_observation_effect_on_earlier_transition": float(
                torch.max(torch.abs(baseline[:, day] - future[:, day]))
            ),
        }
        if isinstance(network, CausalSemiMarkovTransitionModule):
            past_values = split.observable.observations.clone()
            past_values[:, day - 2] += 5.0
            past_observable = replace(split.observable, observations=past_values)
            past = _rollout_dynamic_probability(
                H17DataSplit(split.name, past_observable, split.supervision),
                network,
                estimator_factory(),
            ).transition_matrices.detach()
            blocks = split.observable.forcing.shape[0]
            young = torch.zeros(
                (blocks, 3, network.maximum_age),
                dtype=network.base_transition.dtype,
                device=network.base_transition.device,
            )
            older = torch.zeros_like(young)
            young[..., 0] = 1.0 / 3.0
            older[..., min(39, network.maximum_age - 1)] = 1.0 / 3.0
            young_transition = network(
                ModeDurationState(joint_probabilities=young)
            ).transition_matrix.detach()
            older_transition = network(
                ModeDurationState(joint_probabilities=older)
            ).transition_matrix.detach()
            seed_values.update(
                {
                    "past_observation_day": day - 2,
                    "past_observation_perturbation": 5.0,
                    "past_observation_effect_on_later_transition": float(
                        torch.max(torch.abs(baseline[:, day] - past[:, day]))
                    ),
                    "duration_state_comparison_mode_marginals": [
                        1.0 / 3.0,
                        1.0 / 3.0,
                        1.0 / 3.0,
                    ],
                    "duration_state_comparison_ages": [
                        1,
                        min(40, network.maximum_age),
                    ],
                    "duration_state_effect_on_transition": float(
                        torch.max(
                            torch.abs(young_transition - older_transition)
                        )
                    ),
                }
            )
        else:
            permitted_values = split.observable.forcing.clone()
            permitted_values[:, day - 1, 0] += 1.0
            permitted_observable = replace(
                split.observable, forcing=permitted_values
            )
            permitted = rollout_history_probability(
                permitted_observable,
                split.supervision,
                network,
                estimator_factory(),
            ).transition_matrices.detach()
            seed_values.update(
                {
                    "prior_forcing_coordinate_zero_perturbation": 1.0,
                    "permitted_prior_forcing_effect_on_next_transition": float(
                        torch.max(
                            torch.abs(baseline[:, day] - permitted[:, day])
                        )
                    ),
                }
            )
        per_seed[seed] = seed_values
    current_maximum = max(
        float(values["current_observation_effect_on_same_day_transition"])
        for values in per_seed.values()
    )
    future_maximum = max(
        float(values["future_observation_effect_on_earlier_transition"])
        for values in per_seed.values()
    )
    result = {
        "transition_day_information_cutoff": "history through previous day",
        "per_seed": per_seed,
        "maximum_current_observation_effect_on_same_day_transition": current_maximum,
        "maximum_future_observation_effect_on_earlier_transition": future_maximum,
        "forbidden_training_input_count": int(forbidden_training_input_count),
        "test_reads_before_all_checkpoint_selections": int(
            test_reads_before_selection
        ),
    }
    if explicit_duration:
        result.update(
            {
                "minimum_past_observation_effect_on_later_transition": min(
                    float(values["past_observation_effect_on_later_transition"])
                    for values in per_seed.values()
                ),
                "minimum_duration_state_effect_on_transition": min(
                    float(values["duration_state_effect_on_transition"])
                    for values in per_seed.values()
                ),
            }
        )
    else:
        result["minimum_permitted_prior_forcing_effect_on_next_transition"] = min(
            float(values["permitted_prior_forcing_effect_on_next_transition"])
            for values in per_seed.values()
        )
    return result


def _save_daily_arrays(
    path: Path,
    split: H17DataSplit,
    statistics: ObservableFeatureStatistics,
    fixed: ProbabilityRolloutResult,
    static: ProbabilityRolloutResult,
    histories: Mapping[str, tuple[DynamicTransitionNetwork, ProbabilityRolloutResult]],
) -> None:
    values: dict[str, np.ndarray] = {
        "test_forcing": split.observable.forcing.detach().cpu().numpy(),
        "test_observations": split.observable.observations.detach().cpu().numpy(),
        "test_initial_states": split.observable.initial_states.detach().cpu().numpy(),
        "test_initial_covariances": split.observable.initial_covariances.detach().cpu().numpy(),
        "active_source_indices": split.supervision.source_indices.cpu().numpy(),
        "oracle_active_row_probabilities": (
            split.supervision.target_probabilities.cpu().numpy()
        ),
        "transition_evaluation_mask": split.supervision.evaluation_mask.cpu().numpy(),
        "switch_event_mask": split.supervision.switch_event_mask.cpu().numpy(),
        "regime_age_before_transition": (
            split.supervision.regime_age_before_transition.cpu().numpy()
        ),
        "feature_mean": statistics.feature_mean.detach().cpu().numpy(),
        "feature_standard_deviation": (
            statistics.feature_standard_deviation.detach().cpu().numpy()
        ),
        "fixed_transition_matrices": (
            fixed.transition_matrices.detach().cpu().numpy()
        ),
        "static_transition_matrices": (
            static.transition_matrices.detach().cpu().numpy()
        ),
        "history_seed_ids": np.asarray(tuple(histories), dtype=np.int64),
    }
    for seed, (_, result) in histories.items():
        values[f"history_seed_{seed}_transition_matrices"] = (
            result.transition_matrices.detach().cpu().numpy()
        )
        if result.duration_source_hazards is not None:
            values[f"history_seed_{seed}_duration_source_hazards"] = (
                result.duration_source_hazards.detach().cpu().numpy()
            )
        if result.duration_expected_ages is not None:
            values[f"history_seed_{seed}_duration_expected_ages"] = (
                result.duration_expected_ages.detach().cpu().numpy()
            )
        if result.posterior_mode_probabilities is not None:
            values[f"history_seed_{seed}_posterior_mode_probabilities"] = (
                result.posterior_mode_probabilities.detach().cpu().numpy()
            )
        if result.age_hazards is not None:
            values[f"history_seed_{seed}_age_hazards"] = (
                result.age_hazards.detach().cpu().numpy()
            )
    temporary = path.with_suffix(path.suffix + ".tmp")
    with temporary.open("wb") as handle:
        np.savez_compressed(handle, **values)
    temporary.replace(path)


def _duration_state_audit(
    split: H17DataSplit,
    histories: Mapping[str, tuple[DynamicTransitionNetwork, ProbabilityRolloutResult]],
) -> dict[str, Any]:
    """Separate learned age-risk amplitude from causal duration/source inference."""

    mask = split.supervision.evaluation_mask
    sources = split.supervision.source_indices[mask]
    ages = split.supervision.regime_age_before_transition[mask]
    targets = split.supervision.target_probabilities[mask]
    row_indices = torch.arange(sources.numel(), device=sources.device)
    oracle_hazards = 1.0 - targets[row_indices, sources]
    per_seed: dict[str, Any] = {}
    for seed, (network, result) in histories.items():
        if not isinstance(network, CausalSemiMarkovTransitionModule):
            raise TypeError("duration state audit requires duration networks")
        if (
            result.duration_source_hazards is None
            or result.duration_expected_ages is None
            or result.posterior_mode_probabilities is None
            or result.age_hazards is None
        ):
            raise ValueError("duration rollout diagnostics are incomplete")
        inferred_hazards = result.duration_source_hazards[mask]
        inferred_active = inferred_hazards[row_indices, sources]
        expected_ages = result.duration_expected_ages[mask]
        expected_active_ages = expected_ages[row_indices, sources]
        posterior = result.posterior_mode_probabilities[mask]
        active_posterior = posterior[row_indices, sources]
        age_indices = torch.clamp(ages - 1, max=result.age_hazards.numel() - 1)
        direct_age_hazards = result.age_hazards[age_indices]
        transition_hazards = 1.0 - torch.diagonal(
            result.transition_matrices, dim1=-2, dim2=-1
        )
        seed_audit = {
            "evaluated_day_count": int(mask.sum()),
            "direct_age_risk_mean_absolute_error": float(
                torch.mean(torch.abs(direct_age_hazards - oracle_hazards))
            ),
            "inferred_active_source_risk_mean_absolute_error": float(
                torch.mean(torch.abs(inferred_active - oracle_hazards))
            ),
            "active_source_expected_age_mean_absolute_error": float(
                torch.mean(torch.abs(expected_active_ages - ages))
            ),
            "mean_posterior_probability_of_true_source": float(
                active_posterior.mean()
            ),
            "minimum_age_hazard": float(result.age_hazards.min()),
            "maximum_age_hazard": float(result.age_hazards.max()),
            "maximum_transition_hazard_diagnostic_mismatch": float(
                torch.max(
                    torch.abs(
                        transition_hazards - result.duration_source_hazards
                    )
                )
            ),
            "maximum_posterior_mode_sum_error": float(
                torch.max(
                    torch.abs(
                        result.posterior_mode_probabilities.sum(dim=-1) - 1.0
                    )
                )
            ),
            "minimum_expected_age": float(result.duration_expected_ages.min()),
            "maximum_expected_age": float(result.duration_expected_ages.max()),
        }
        if network.age_risk_representation == "monotone_piecewise_linear":
            increments = torch.diff(result.age_hazards)
            seed_audit.update(
                {
                    "minimum_age_hazard_increment": float(increments.min()),
                    "age_hazard_nondecreasing": bool(
                        torch.all(increments >= -1e-15)
                    ),
                }
            )
        per_seed[seed] = seed_audit
    return {
        "true_mode_and_age_used_for_scoring_only": True,
        "true_mode_or_age_used_by_transition_module": False,
        "risk_amplitude_diagnostic": (
            "direct learned age-risk curve versus the frozen oracle hazard"
        ),
        "duration_and_source_diagnostic": (
            "causal expected age and posterior mass at the true source"
        ),
        "per_seed": per_seed,
    }


def _stratified_probability_metrics(
    split: H17DataSplit,
    methods: Mapping[str, ProbabilityRolloutResult],
) -> dict[str, Any]:
    mask = split.supervision.evaluation_mask
    sources = split.supervision.source_indices
    ages = split.supervision.regime_age_before_transition
    targets = split.supervision.target_probabilities
    age_groups = {
        "age_1_29": (ages >= 1) & (ages <= 29),
        "age_30_39": (ages >= 30) & (ages <= 39),
        "age_40_49": (ages >= 40) & (ages <= 49),
        "age_50_plus": ages >= 50,
    }

    def selected_scores(
        result: ProbabilityRolloutResult, selected: torch.Tensor
    ) -> dict[str, int | float | None]:
        count = int(selected.sum())
        if count == 0:
            return {
                "count": 0,
                "oracle_brier": None,
                "switch_hazard_mean_absolute_error": None,
            }
        blocks, days = torch.nonzero(selected, as_tuple=True)
        selected_sources = sources[blocks, days]
        rows = result.transition_matrices[blocks, days, selected_sources]
        selected_targets = targets[blocks, days]
        indices = torch.arange(count, device=rows.device)
        return {
            "count": count,
            "oracle_brier": float(
                torch.sum((rows - selected_targets).square(), dim=-1).mean()
            ),
            "switch_hazard_mean_absolute_error": float(
                torch.mean(
                    torch.abs(
                        (1.0 - rows[indices, selected_sources])
                        - (1.0 - selected_targets[indices, selected_sources])
                    )
                )
            ),
        }

    values: dict[str, Any] = {
        "age_bins": list(age_groups),
        "source_ids": [
            "slow_recession",
            "calibrated_recession",
            "fast_recession",
        ],
        "methods": {},
    }
    for method_name, result in methods.items():
        method: dict[str, Any] = {
            "by_source": {},
            "by_age_and_source": {},
            "by_block": {},
            "by_target_coordinate": {},
        }
        for source_index in range(3):
            method["by_source"][str(source_index)] = selected_scores(
                result, mask & (sources == source_index)
            )
        for age_name, age_mask in age_groups.items():
            method["by_age_and_source"][age_name] = {
                str(source_index): selected_scores(
                    result,
                    mask & age_mask & (sources == source_index),
                )
                for source_index in range(3)
            }
        for block in range(mask.shape[0]):
            selected = torch.zeros_like(mask)
            selected[block] = mask[block]
            method["by_block"][str(block)] = selected_scores(result, selected)
        blocks, days = torch.nonzero(mask, as_tuple=True)
        active_sources = sources[blocks, days]
        rows = result.transition_matrices[blocks, days, active_sources]
        selected_targets = targets[blocks, days]
        for target_index in range(3):
            method["by_target_coordinate"][str(target_index)] = {
                "count": int(rows.shape[0]),
                "mean_squared_probability_error": float(
                    torch.mean(
                        (
                            rows[:, target_index]
                            - selected_targets[:, target_index]
                        ).square()
                    )
                ),
                "mean_absolute_probability_error": float(
                    torch.mean(
                        torch.abs(
                            rows[:, target_index]
                            - selected_targets[:, target_index]
                        )
                    )
                ),
            }
        values["methods"][method_name] = method
    return values


def _all_finite(value: Any) -> bool:
    if isinstance(value, Mapping):
        return all(_all_finite(item) for item in value.values())
    if isinstance(value, (list, tuple)):
        return all(_all_finite(item) for item in value)
    if isinstance(value, bool) or value is None or isinstance(value, str):
        return True
    if isinstance(value, (int, float)):
        return math.isfinite(float(value))
    return True


def _save_phase_context(
    path: Path, statistics: ObservableFeatureStatistics
) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    torch.save(
        {
            "feature_mean": statistics.feature_mean,
            "feature_standard_deviation": statistics.feature_standard_deviation,
            "source": statistics.source,
            "truth_used": statistics.truth_used,
            "supervision_used": statistics.supervision_used,
            "validation_used": statistics.validation_used,
            "test_used": statistics.test_used,
        },
        temporary,
    )
    temporary.replace(path)


def _load_phase_statistics(path: Path) -> ObservableFeatureStatistics:
    values = torch.load(path, map_location="cpu", weights_only=False)
    return ObservableFeatureStatistics(
        feature_mean=values["feature_mean"],
        feature_standard_deviation=values["feature_standard_deviation"],
        source=str(values["source"]),
        truth_used=bool(values["truth_used"]),
        supervision_used=bool(values["supervision_used"]),
        validation_used=bool(values["validation_used"]),
        test_used=bool(values["test_used"]),
    )


def _checkpoint_payload(path: Path) -> dict[str, Any]:
    return torch.load(path, map_location="cpu", weights_only=False)


def _save_training_progress(
    path: Path, progress: ProbabilityTrainingProgress
) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    torch.save(progress, temporary)
    temporary.replace(path)


def _load_training_progress(path: Path) -> ProbabilityTrainingProgress:
    progress = torch.load(path, map_location="cpu", weights_only=False)
    if not isinstance(progress, ProbabilityTrainingProgress):
        raise TypeError("saved H17 training progress has an unexpected type")
    return progress


def _completed_training_result(
    progress: ProbabilityTrainingProgress,
) -> ProbabilityTrainingResult:
    if not progress.complete:
        raise ValueError("cannot freeze an incomplete training progress object")
    return ProbabilityTrainingResult(
        best_epoch=progress.best_epoch,
        best_validation_brier=progress.best_validation_brier,
        history=progress.history,
        best_network_state=progress.best_network_state,
        test_reads_before_selection=progress.test_reads_before_selection,
    )


def _is_supervised_repair(config: Mapping[str, Any]) -> bool:
    return config.get("experiment_kind") == "supervised_probability_repair"


def _verify_result_artifact(
    result_directory: Path,
    *,
    config: Mapping[str, Any],
    verify_checksums: bool,
    project_root: Path,
) -> dict[str, Any]:
    if _is_supervised_repair(config):
        from hbv_history_conditioned_imm.scripts.verify_h17_supervised_probability_repair import (
            verify_supervised_probability_repair,
        )

        return verify_supervised_probability_repair(
            result_directory,
            verify_checksums=verify_checksums,
            project_root=project_root,
        )
    return verify_h17_result(
        result_directory,
        verify_checksums=verify_checksums,
        project_root=project_root,
    )


def _copy_frozen_static_reference(
    config: Mapping[str, Any],
    *,
    project_root: Path,
    staging: Path,
) -> dict[str, Any]:
    reference = config.get("source_h17_static_reference")
    if not isinstance(reference, Mapping):
        raise ValueError("supervised repair requires a frozen H17 static reference")
    copied: dict[str, Any] = {}
    for label, destination_name in (
        ("checkpoint", "static_best_checkpoint.pt"),
        ("training_history", "static_training_history.csv"),
    ):
        specification = reference.get(label)
        if not isinstance(specification, Mapping):
            raise ValueError(f"frozen H17 static {label} specification is missing")
        source = (project_root / str(specification["path"])).resolve()
        expected = str(specification["sha256"])
        if not source.is_file() or _sha256(source) != expected:
            raise ValueError(f"frozen H17 static {label} hash mismatch")
        shutil.copy2(source, staging / destination_name)
        copied[label] = {
            "path": str(source.relative_to(project_root)),
            "sha256": expected,
            "copied_byte_for_byte": _sha256(staging / destination_name) == expected,
        }
    copied["experiment_id"] = str(reference["experiment_id"])
    copied["retrained"] = False
    copied["all_hashes_verified"] = all(
        bool(values["copied_byte_for_byte"])
        for values in copied.values()
        if isinstance(values, Mapping) and "copied_byte_for_byte" in values
    )
    if not copied["all_hashes_verified"]:
        raise ValueError("copied H17 static reference differs from its frozen source")
    return copied


def _write_repair_audits(
    config: Mapping[str, Any],
    *,
    project_root: Path,
    staging: Path,
    static_reference: Mapping[str, Any],
) -> None:
    repair_contract = config.get("repair_contract")
    if not isinstance(repair_contract, Mapping):
        raise ValueError("supervised repair contract is missing")
    _write_json(staging / "repair_contract.json", dict(repair_contract))
    _write_json(staging / "static_reference.json", dict(static_reference))
    _write_json(
        staging / "evaluation_role_audit.json",
        {
            "h16_test_split_previously_inspected_for_h17_failure_attribution": True,
            "current_evaluation_role": "development_diagnostic",
            "independent_generalization_evidence": False,
            "passing_this_split_alone_establishes_solution": False,
            "fresh_reserved_confirmation_required_after_diagnostic_pass": True,
            "h18_authorized": False,
        },
    )
    reference = config["source_h17_static_reference"]
    h17_root = (project_root / str(reference["result_directory"])).resolve()
    h17_verification = verify_h17_result(h17_root, project_root=project_root)
    checksums_path = h17_root / "checksums.json"
    source_integrity = {
        "h17_result_directory": str(h17_root.relative_to(project_root)),
        "h17_independent_verification_passed": h17_verification.get("verified") is True,
        "h17_checksums_sha256": _sha256(checksums_path),
        "expected_h17_checksums_sha256": str(reference["checksums_sha256"]),
        "h17_unchanged": (
            h17_verification.get("verified") is True
            and _sha256(checksums_path) == str(reference["checksums_sha256"])
        ),
        "h18_registered_or_run": False,
    }
    if not source_integrity["h17_unchanged"]:
        raise ValueError("frozen H17 evidence changed during repair execution")
    baseline = config.get("baseline_repair")
    if isinstance(baseline, Mapping):
        baseline_root = (
            project_root / str(baseline["result_directory"])
        ).resolve()
        baseline_declaration = (
            project_root / str(baseline["declaration"]["path"])
        ).resolve()
        baseline_values = {
            "experiment_id": str(baseline["experiment_id"]),
            "declaration_sha256": _sha256(baseline_declaration),
            "expected_declaration_sha256": str(
                baseline["declaration"]["sha256"]
            ),
            "checksums_sha256": _sha256(baseline_root / "checksums.json"),
            "expected_checksums_sha256": str(baseline["checksums_sha256"]),
            "independent_verification_sha256": _sha256(
                baseline_root / "independent_verification.json"
            ),
            "expected_independent_verification_sha256": str(
                baseline["independent_verification_sha256"]
            ),
        }
        baseline_values["all_hashes_verified"] = all(
            baseline_values[observed] == baseline_values[expected]
            for observed, expected in (
                ("declaration_sha256", "expected_declaration_sha256"),
                ("checksums_sha256", "expected_checksums_sha256"),
                (
                    "independent_verification_sha256",
                    "expected_independent_verification_sha256",
                ),
            )
        )
        if not baseline_values["all_hashes_verified"]:
            raise ValueError("frozen H17B baseline evidence changed")
        source_integrity["h17b_baseline"] = baseline_values
    baseline_duration = config.get("baseline_duration_repair")
    if isinstance(baseline_duration, Mapping):
        baseline_duration_root = (
            project_root / str(baseline_duration["result_directory"])
        ).resolve()
        baseline_duration_declaration = (
            project_root / str(baseline_duration["declaration"]["path"])
        ).resolve()
        baseline_duration_values = {
            "experiment_id": str(baseline_duration["experiment_id"]),
            "declaration_sha256": _sha256(baseline_duration_declaration),
            "expected_declaration_sha256": str(
                baseline_duration["declaration"]["sha256"]
            ),
            "checksums_sha256": _sha256(
                baseline_duration_root / "checksums.json"
            ),
            "expected_checksums_sha256": str(
                baseline_duration["checksums_sha256"]
            ),
            "independent_verification_sha256": _sha256(
                baseline_duration_root / "independent_verification.json"
            ),
            "expected_independent_verification_sha256": str(
                baseline_duration["independent_verification_sha256"]
            ),
        }
        baseline_duration_values["all_hashes_verified"] = all(
            baseline_duration_values[observed]
            == baseline_duration_values[expected]
            for observed, expected in (
                ("declaration_sha256", "expected_declaration_sha256"),
                ("checksums_sha256", "expected_checksums_sha256"),
                (
                    "independent_verification_sha256",
                    "expected_independent_verification_sha256",
                ),
            )
        )
        if not baseline_duration_values["all_hashes_verified"]:
            raise ValueError("frozen H17D baseline evidence changed")
        source_integrity["h17d_baseline"] = baseline_duration_values
    baseline_age_risk = config.get("baseline_age_risk_repair")
    if isinstance(baseline_age_risk, Mapping):
        baseline_age_risk_root = (
            project_root / str(baseline_age_risk["result_directory"])
        ).resolve()
        baseline_age_risk_declaration = (
            project_root / str(baseline_age_risk["declaration"]["path"])
        ).resolve()
        baseline_age_risk_snapshot = (
            project_root / str(baseline_age_risk["config_snapshot"]["path"])
        ).resolve()
        baseline_age_risk_values = {
            "experiment_id": str(baseline_age_risk["experiment_id"]),
            "declaration_sha256": _sha256(baseline_age_risk_declaration),
            "expected_declaration_sha256": str(
                baseline_age_risk["declaration"]["sha256"]
            ),
            "config_snapshot_sha256": _sha256(baseline_age_risk_snapshot),
            "expected_config_snapshot_sha256": str(
                baseline_age_risk["config_snapshot"]["sha256"]
            ),
            "checksums_sha256": _sha256(
                baseline_age_risk_root / "checksums.json"
            ),
            "expected_checksums_sha256": str(
                baseline_age_risk["checksums_sha256"]
            ),
            "independent_verification_sha256": _sha256(
                baseline_age_risk_root / "independent_verification.json"
            ),
            "expected_independent_verification_sha256": str(
                baseline_age_risk["independent_verification_sha256"]
            ),
        }
        baseline_age_risk_values["all_hashes_verified"] = all(
            baseline_age_risk_values[observed]
            == baseline_age_risk_values[expected]
            for observed, expected in (
                ("declaration_sha256", "expected_declaration_sha256"),
                ("config_snapshot_sha256", "expected_config_snapshot_sha256"),
                ("checksums_sha256", "expected_checksums_sha256"),
                (
                    "independent_verification_sha256",
                    "expected_independent_verification_sha256",
                ),
            )
        )
        if not baseline_age_risk_values["all_hashes_verified"]:
            raise ValueError("frozen H17E baseline evidence changed")
        source_integrity["h17e_baseline"] = baseline_age_risk_values
    _write_json(staging / "source_integrity_audit.json", source_integrity)

    source_files = tuple(str(value) for value in config["source_snapshot_files"])
    manifest: dict[str, str] = {}
    with zipfile.ZipFile(
        staging / "source_snapshot.zip", mode="w", compression=zipfile.ZIP_DEFLATED
    ) as archive:
        for relative_name in source_files:
            source = (project_root / relative_name).resolve()
            if not source.is_file():
                raise FileNotFoundError(f"repair source snapshot file is missing: {source}")
            manifest[relative_name] = _sha256(source)
            archive.write(source, arcname=relative_name.replace("\\", "/"))
    _write_json(
        staging / "source_manifest.json",
        {
            "files": manifest,
            "source_snapshot_sha256": _sha256(staging / "source_snapshot.zip"),
        },
    )


def run_h17_probability_upper_bound(
    config: Mapping[str, Any],
    *,
    project_root: str | Path,
    result_directory_override: str | Path | None = None,
    maximum_new_history_seeds: int | None = None,
    maximum_new_history_epochs: int | None = None,
) -> Path:
    """Train resumable seeds, then test once and atomically publish H17."""

    if maximum_new_history_seeds is not None and (
        isinstance(maximum_new_history_seeds, bool)
        or int(maximum_new_history_seeds) != maximum_new_history_seeds
        or int(maximum_new_history_seeds) < 0
    ):
        raise ValueError("maximum new history seeds must be a nonnegative integer")
    if maximum_new_history_epochs is not None and (
        isinstance(maximum_new_history_epochs, bool)
        or int(maximum_new_history_epochs) != maximum_new_history_epochs
        or int(maximum_new_history_epochs) <= 0
    ):
        raise ValueError("maximum new history epochs must be a positive integer")
    root = Path(project_root).resolve()
    final_directory = (
        Path(result_directory_override).resolve()
        if result_directory_override is not None
        else (root / str(config["result_relative_path"])).resolve()
    )
    if final_directory.exists():
        raise FileExistsError(f"result directory already exists: {final_directory}")
    final_directory.parent.mkdir(parents=True, exist_ok=True)
    registry_row = load_registry_row(str(config["experiment_id"]))
    if registry_row["run_dir"] != str(config["result_relative_path"]):
        raise ValueError("H17 registry and config output roots differ")
    staging = final_directory.parent / (
        f".{config['experiment_id']}.staging-resumable"
    )
    candidates = _parameter_candidates(config)
    base_transition = _base_transition(config)
    _verify_h16_sources(config, root)
    phase_context_path = staging / "phase_context.pt"
    static_checkpoint_path = staging / "static_best_checkpoint.pt"
    if not staging.exists():
        staging.mkdir()
        training_split, source_audit = load_h17_data_split(
            config, root, "training"
        )
        validation_split, validation_source_audit = load_h17_data_split(
            config, root, "validation"
        )
        _, weighting_audit = _training_weights_and_audit(
            config, training_split.supervision
        )
        statistics = fit_observable_feature_statistics(
            training_split.observable,
            _estimator(config, candidates),
            base_transition,
            float(config["normalization"]["standard_deviation_floor"]),
        )
        normalization_audit = {
            "source": statistics.source,
            "feature_count": int(statistics.feature_mean.numel()),
            "minimum_feature_standard_deviation": float(
                statistics.feature_standard_deviation.min()
            ),
            "maximum_feature_standard_deviation": float(
                statistics.feature_standard_deviation.max()
            ),
            "standard_deviation_floor": float(
                config["normalization"]["standard_deviation_floor"]
            ),
            "truth_used": statistics.truth_used,
            "supervision_used": statistics.supervision_used,
            "validation_used": statistics.validation_used,
            "test_used": statistics.test_used,
            "used_by_transition_module": not _is_explicit_duration(config),
            "training_source_audit": source_audit,
            "validation_source_hashes_verified": bool(
                validation_source_audit["all_source_hashes_verified"]
            ),
        }
        _write_json(staging / "config_snapshot.json", dict(config))
        _write_json(staging / "normalization_audit.json", normalization_audit)
        if weighting_audit is not None:
            _write_json(staging / "weighting_audit.json", weighting_audit)
        if _is_supervised_repair(config):
            static_reference = _copy_frozen_static_reference(
                config,
                project_root=root,
                staging=staging,
            )
            _write_json(staging / "static_reference.json", static_reference)
        else:
            static_seed = int(
                config["training"]["static_matrix_initialization_seed"]
            )
            torch.manual_seed(static_seed)
            static_network = _static_network(config, base_transition)
            static_training = train_supervised_probability(
                training_split.observable,
                training_split.supervision,
                validation_split.observable,
                validation_split.supervision,
                static_network,
                _estimator(config, candidates),
                **_training_arguments(config),
                progress_callback=_progress_printer("static"),
            )
            _write_history(
                staging / "static_training_history.csv", static_training.history
            )
            _save_checkpoint(
                static_checkpoint_path,
                experiment_id=str(config["experiment_id"]),
                method="learned_history_free_static_matrix",
                seed=static_seed,
                training=static_training,
                statistics=None,
            )
            print(
                f"static checkpoint frozen at epoch {static_training.best_epoch}",
                flush=True,
            )
        _save_phase_context(phase_context_path, statistics)
    else:
        if not phase_context_path.is_file() or not static_checkpoint_path.is_file():
            raise RuntimeError("resumable H17 staging is incomplete before history training")
        saved_config = json.loads(
            (staging / "config_snapshot.json").read_text(encoding="utf-8")
        )
        if saved_config != dict(config):
            raise ValueError("resumable H17 staging config differs from requested config")
        statistics = _load_phase_statistics(phase_context_path)

    missing_seeds = []
    for seed_value in config["training"]["history_network_initialization_seeds"]:
        seed = int(seed_value)
        history_path = staging / f"history_seed_{seed}_training_history.csv"
        checkpoint_path = staging / f"history_seed_{seed}_best_checkpoint.pt"
        progress_path = staging / f"history_seed_{seed}_training_progress.pt"
        if history_path.is_file() != checkpoint_path.is_file():
            raise RuntimeError(f"history seed {seed} has an incomplete atomic artifact pair")
        if checkpoint_path.is_file() and progress_path.is_file():
            raise RuntimeError(f"history seed {seed} has both final and progress files")
        if not checkpoint_path.is_file():
            missing_seeds.append(seed)

    if maximum_new_history_seeds == 0 and missing_seeds:
        raise RuntimeError("history checkpoints remain but new seed training is disabled")
    if missing_seeds:
        training_split, _ = load_h17_data_split(config, root, "training")
        validation_split, _ = load_h17_data_split(config, root, "validation")
        training_sample_weights, _ = _training_weights_and_audit(
            config, training_split.supervision
        )
    new_seed_count = 0
    for seed in missing_seeds:
        torch.manual_seed(seed)
        network = _history_network(config, base_transition, statistics)
        progress_path = staging / f"history_seed_{seed}_training_progress.pt"
        if maximum_new_history_epochs is not None:
            resume_progress = (
                _load_training_progress(progress_path)
                if progress_path.is_file()
                else None
            )
            progress = train_supervised_probability_chunk(
                training_split.observable,
                training_split.supervision,
                validation_split.observable,
                validation_split.supervision,
                network,
                _estimator(config, candidates),
                **_training_arguments(config),
                training_sample_weights=training_sample_weights,
                maximum_new_epochs=int(maximum_new_history_epochs),
                resume_progress=resume_progress,
                progress_callback=_progress_printer(f"history seed {seed}"),
            )
            _save_training_progress(progress_path, progress)
            if not progress.complete:
                print(
                    f"history seed {seed} progress frozen after "
                    f"{progress.completed_epochs} of {progress.total_epochs} epochs",
                    flush=True,
                )
                print(f"resumable H17 staging retained at {staging}", flush=True)
                return staging
            training = _completed_training_result(progress)
        else:
            training = train_supervised_probability(
                training_split.observable,
                training_split.supervision,
                validation_split.observable,
                validation_split.supervision,
                network,
                _estimator(config, candidates),
                **_training_arguments(config),
                training_sample_weights=training_sample_weights,
                progress_callback=_progress_printer(f"history seed {seed}"),
            )
        _write_history(
            staging / f"history_seed_{seed}_training_history.csv",
            training.history,
        )
        _save_checkpoint(
            staging / f"history_seed_{seed}_best_checkpoint.pt",
            experiment_id=str(config["experiment_id"]),
            method=_dynamic_method_name(config),
            seed=seed,
            training=training,
            statistics=None if _is_explicit_duration(config) else statistics,
            transition_architecture=(
                "explicit_causal_duration"
                if _is_explicit_duration(config)
                else "recurrent_history"
            ),
            duration_contract=(
                config["duration_contract"]
                if _is_explicit_duration(config)
                else None
            ),
        )
        if progress_path.is_file():
            progress_path.unlink()
        new_seed_count += 1
        print(
            f"history seed {seed} checkpoint frozen at epoch {training.best_epoch}",
            flush=True,
        )
        if (
            maximum_new_history_seeds is not None
            and new_seed_count >= maximum_new_history_seeds
        ):
            print(f"resumable H17 staging retained at {staging}", flush=True)
            return staging
        if maximum_new_history_epochs is not None:
            print(f"resumable H17 staging retained at {staging}", flush=True)
            return staging

    static_payload = _checkpoint_payload(static_checkpoint_path)
    static_network = _static_network(config, base_transition)
    static_network.load_state_dict(static_payload["network_state_dict"])
    history_networks: dict[str, DynamicTransitionNetwork] = {}
    test_reads_before_selection = int(static_payload["test_reads_before_selection"])
    for seed_value in config["training"]["history_network_initialization_seeds"]:
        seed = int(seed_value)
        payload = _checkpoint_payload(
            staging / f"history_seed_{seed}_best_checkpoint.pt"
        )
        network = _history_network(config, base_transition, statistics)
        network.load_state_dict(payload["network_state_dict"])
        history_networks[str(seed)] = network
        test_reads_before_selection += int(payload["test_reads_before_selection"])

    test_split, test_source_audit = load_h17_data_split(config, root, "test")
    fixed_result = _fixed_probability_rollout(test_split.supervision, base_transition)
    with torch.no_grad():
        static_result = rollout_static_probability(
            test_split.supervision,
            static_network,
            dtype=test_split.observable.forcing.dtype,
            device=test_split.observable.forcing.device,
        )
    history_results: dict[
        str, tuple[DynamicTransitionNetwork, ProbabilityRolloutResult]
    ] = {}
    for seed, network in history_networks.items():
        network.eval()
        with torch.no_grad():
            result = _rollout_dynamic_probability(
                test_split,
                network,
                _estimator(config, candidates),
            )
        history_results[seed] = (network, result)

    causality_audit = _causality_audit(
        test_split,
        history_results,
        lambda: _estimator(config, candidates),
        forbidden_training_input_count=int(
            test_source_audit["forbidden_training_input_count"]
        ),
        test_reads_before_selection=test_reads_before_selection,
    )
    dynamic_metric_key = _dynamic_metric_key(config)
    metrics: dict[str, Any] = {
        "experiment_id": config["experiment_id"],
        "fixed_transition_matrix": fixed_result.scores.to_dict(),
        "learned_history_free_static_matrix": static_result.scores.to_dict(),
        dynamic_metric_key: {
            seed: result.scores.to_dict()
            for seed, (_, result) in history_results.items()
        },
        "method_contract": dict(config["method_contract"]),
        "test_reads_before_all_checkpoint_selections": int(
            test_reads_before_selection
        ),
        "synthetic_active_row_supervision_used": True,
        "physical_filter_gradient_stopped": True,
        "recurrent_hidden_gradient_retained": not _is_explicit_duration(config),
        "duration_state_gradient_retained": _is_explicit_duration(config),
        "strict_observation_evidence_learning_established": False,
        "state_superiority_established": False,
        "forecast_value_established": False,
        "closed_loop_stability_established": False,
        "real_basin_claim_established": False,
        "h18_registered_or_run": False,
        "claim_boundary": config["claim_boundary"],
    }
    static_brier = float(static_result.scores.oracle_brier)
    static_hazard = float(static_result.scores.switch_hazard_mean_absolute_error)
    for seed, values in metrics[dynamic_metric_key].items():
        values["relative_oracle_brier_reduction_vs_static"] = (
            _relative_reduction(static_brier, float(values["oracle_brier"]))
        )
        values["relative_hazard_mae_reduction_vs_static"] = _relative_reduction(
            static_hazard,
            float(values["switch_hazard_mean_absolute_error"]),
        )
    gates = evaluate_probability_gates(config, metrics, causality_audit)
    capability_passed = bool(gates["all_capability_gates_passed"])
    metrics["capability_gates"] = gates
    metrics["supervised_probability_capability_passed"] = capability_passed
    if _is_supervised_repair(config):
        metrics["evaluation_role"] = "development_diagnostic"
        metrics["independent_generalization_evidence"] = False
        metrics["decision"] = (
            "DEVELOPMENT_DIAGNOSTIC_PASS_FRESH_CONFIRMATION_REQUIRED_"
            "H18_REMAINS_UNAUTHORIZED"
            if capability_passed
            else "SUPERVISED_REPAIR_HOLD_H18_REMAINS_UNAUTHORIZED"
        )
    else:
        metrics["decision"] = (
            "SUPERVISED_CAPABILITY_GO_H18_REMAINS_UNAUTHORIZED"
            if capability_passed
            else "SUPERVISED_CAPABILITY_HOLD_H18_REMAINS_UNAUTHORIZED"
        )
    if not _all_finite(metrics) or not _all_finite(causality_audit):
        raise ValueError("H17 metrics or causality audit contain non-finite values")

    completed_registry_row = dict(registry_row)
    if _is_supervised_repair(config):
        if _is_explicit_duration(config):
            completed_registry_row["status"] = (
                "completed_supervised_repair_diagnostic_pass"
                if capability_passed
                else "completed_supervised_repair_diagnostic_hold"
            )
        else:
            completed_registry_row["status"] = (
                "completed_supervised_repair_go"
                if capability_passed
                else "completed_supervised_repair_hold"
            )
    else:
        completed_registry_row["status"] = (
            "completed_supervised_upper_bound_go"
            if capability_passed
            else "completed_supervised_upper_bound_hold"
        )
    completed_registry_row["notes"] = (
        f"Checksum-verified supervised upper-bound run; decision "
        f"{metrics['decision']}; H18 was not registered or run"
    )
    _write_json(staging / "registry_entry.json", completed_registry_row)
    _save_daily_arrays(
        staging / "daily_arrays.npz",
        test_split,
        statistics,
        fixed_result,
        static_result,
        history_results,
    )
    _write_json(staging / "metrics.json", metrics)
    _write_json(staging / "causality_audit.json", causality_audit)
    if _is_explicit_duration(config):
        _write_json(
            staging / "duration_contract.json",
            dict(config["duration_contract"]),
        )
        _write_json(
            staging / "duration_causality_audit.json",
            {
                **dict(causality_audit),
                "same_day_observation_used": False,
                "future_observation_used": False,
                "true_mode_used": False,
                "true_age_used": False,
                "hard_argmax_reset_used": False,
            },
        )
        _write_json(
            staging / "duration_state_audit.json",
            _duration_state_audit(test_split, history_results),
        )
        _write_json(
            staging / "stratified_metrics.json",
            _stratified_probability_metrics(
                test_split,
                {
                    "learned_history_free_static_matrix": static_result,
                    **{
                        f"history_seed_{seed}": result
                        for seed, (_, result) in history_results.items()
                    },
                },
            ),
        )
    if _is_supervised_repair(config):
        static_reference = json.loads(
            (staging / "static_reference.json").read_text(encoding="utf-8")
        )
        _write_repair_audits(
            config,
            project_root=root,
            staging=staging,
            static_reference=static_reference,
        )
    _write_json(
        staging / "environment.json",
        {
            "python": sys.version,
            "platform": platform.platform(),
            "torch": torch.__version__,
            "numpy": np.__version__,
            "torch_threads": torch.get_num_threads(),
            "git_head": _git_head(root),
            "process_id": os.getpid(),
        },
    )
    if _is_explicit_duration(config):
        expected_live_status = str(completed_registry_row["status"])
        observed_live_status = str(registry_row["status"])
        if observed_live_status == "registered_supervised_repair":
            print(
                "H17D diagnostic artifacts are frozen; update the single live "
                f"registry row to {expected_live_status} before final verification",
                flush=True,
            )
            return staging
        if observed_live_status != expected_live_status:
            raise ValueError(
                "H17D live registry status does not match the frozen diagnostic decision"
            )
    phase_context_path.unlink()
    required = set(str(name) for name in config["required_result_files"])
    expected_before_verification = required - {
        "independent_verification.json",
        "checksums.json",
    }
    if {path.name for path in staging.iterdir() if path.is_file()} != (
        expected_before_verification
    ):
        raise RuntimeError("H17 staging output is incomplete before verification")
    independent = _verify_result_artifact(
        staging,
        config=config,
        verify_checksums=False,
        project_root=root,
    )
    if independent["verified"] is not True:
        raise ValueError(
            "H17 independent staging verification failed: "
            + json.dumps(independent, sort_keys=True)
        )
    _write_json(staging / "independent_verification.json", independent)
    checksums = {
        name: _sha256(staging / name)
        for name in sorted(required - {"checksums.json"})
    }
    _write_json(staging / "checksums.json", checksums)
    if {path.name for path in staging.iterdir() if path.is_file()} != required:
        raise RuntimeError("H17 staging output does not match its required file set")
    checksum_verification = _verify_result_artifact(
        staging,
        config=config,
        verify_checksums=True,
        project_root=root,
    )
    if checksum_verification["verified"] is not True:
        raise ValueError("H17 checksum verification failed before publication")
    staging.replace(final_directory)
    return final_directory


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", default=str(DEFAULT_CONFIG_PATH))
    parser.add_argument("--project-root", default=str(PACKAGE_ROOT.parents[1]))
    parser.add_argument("--maximum-new-history-seeds", type=int)
    parser.add_argument("--maximum-new-history-epochs", type=int)
    arguments = parser.parse_args()
    config = load_h17_config(arguments.config)
    output = run_h17_probability_upper_bound(
        config,
        project_root=arguments.project_root,
        maximum_new_history_seeds=arguments.maximum_new_history_seeds,
        maximum_new_history_epochs=arguments.maximum_new_history_epochs,
    )
    print(output, flush=True)


if __name__ == "__main__":
    main()

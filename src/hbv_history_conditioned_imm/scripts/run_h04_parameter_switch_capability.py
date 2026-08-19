"""Run the registered history-conditioned HBV parameter-switch capability test."""

from __future__ import annotations

import argparse
import csv
import json
import math
import os
import platform
import shutil
import sys
import tempfile
from pathlib import Path
from typing import Any, Mapping, Sequence

import numpy as np
import torch

from hbv_history_conditioned_imm.filter import DifferentiableInteractingMultipleModel
from hbv_history_conditioned_imm.hbv import HBV15Model
from hbv_history_conditioned_imm.network import (
    HistoryTransitionNetwork,
    StaticTransitionNetwork,
)
from hbv_history_conditioned_imm.parameter_switch import (
    ParameterSwitchBatch,
    audit_parameter_signal,
    build_parameter_candidates,
    generate_parameter_switch_batch,
)
from hbv_history_conditioned_imm.parameter_training import (
    ParameterLossWeights,
    ParameterRolloutResult,
    ParameterTrainingStatistics,
    _slice_batch,
    fit_parameter_training_statistics,
    loss_values,
    rollout_parameter_switch,
    train_parameter_transition,
)
from hbv_history_conditioned_imm.probability_audit import (
    build_active_row_oracle,
    score_transition_recovery,
)
from hbv_history_conditioned_imm.scripts.run_h01_end_to_end_smoke import (
    _git_head,
    _sha256,
    _write_json,
    load_registry_row,
)
from hbv_history_conditioned_imm.synthetic import make_block_seeds


PACKAGE_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CONFIG_PATH = PACKAGE_ROOT / "configs" / "h04_parameter_switch_capability_v01.json"
PROCESS_STATE_INDICES = {"SUZ": 3, "SLZ": 4}


def load_h04_config(path: str | Path) -> dict[str, Any]:
    with Path(path).open("r", encoding="utf-8") as handle:
        config = json.load(handle)
    required = {
        "experiment_id",
        "result_relative_path",
        "base_parameter_source",
        "base_parameters",
        "parameter_candidates",
        "data",
        "seeds",
        "filter",
        "forecast",
        "network",
        "training",
        "loss",
        "capability_gates",
        "required_result_files",
    }
    missing = required - set(config)
    if missing:
        raise ValueError(f"H04 configuration is missing fields: {sorted(missing)}")
    if config["experiment_id"] != "h04_parameter_switch_capability_v01":
        raise ValueError("unexpected H04 experiment identifier")
    if len(config["required_result_files"]) != len(
        set(config["required_result_files"])
    ):
        raise ValueError("required H04 result files must be unique")
    return config


def _base_transition(stay_probability: float) -> torch.Tensor:
    stay = float(stay_probability)
    if stay <= 0.0 or stay >= 1.0:
        raise ValueError("base stay probability must lie between zero and one")
    switch = (1.0 - stay) / 2.0
    return torch.tensor(
        [[stay, switch, switch], [switch, stay, switch], [switch, switch, stay]],
        dtype=torch.float64,
    )


def _parameter_candidates(config: Mapping[str, Any]) -> dict[str, dict[str, float]]:
    specification = config["parameter_candidates"]
    candidates = build_parameter_candidates(
        config["base_parameters"], specification["values"]
    )
    if tuple(candidates) != tuple(specification["ids"]):
        raise ValueError("configured parameter identifiers differ from the implementation")
    return candidates


def _truth_process_definition(
    config: Mapping[str, Any],
) -> tuple[int, float]:
    data = config["data"]
    state_name = str(data.get("fixed_process_state_name", "SLZ"))
    if state_name not in PROCESS_STATE_INDICES:
        raise ValueError("truth process state name must be SUZ or SLZ")
    if "fixed_process_standard_deviation" in data:
        deviation = float(data["fixed_process_standard_deviation"])
    else:
        deviation = float(
            data["fixed_lower_groundwater_process_standard_deviation"]
        )
    if not math.isfinite(deviation) or deviation <= 0.0:
        raise ValueError(
            "truth process standard deviation must be finite and positive"
        )
    return PROCESS_STATE_INDICES[state_name], deviation


def _filter_process_definition(
    config: Mapping[str, Any],
) -> tuple[int, float]:
    filter_config = config["filter"]
    if (
        "assumed_process_state_name" in filter_config
        or "assumed_process_standard_deviation" in filter_config
    ):
        truth_index, truth_deviation = _truth_process_definition(config)
        default_name = next(
            name for name, index in PROCESS_STATE_INDICES.items() if index == truth_index
        )
        state_name = str(
            filter_config.get("assumed_process_state_name", default_name)
        )
        deviation = float(
            filter_config.get(
                "assumed_process_standard_deviation", truth_deviation
            )
        )
    elif "assumed_lower_groundwater_process_standard_deviation" in filter_config:
        state_name = "SLZ"
        deviation = float(
            filter_config[
                "assumed_lower_groundwater_process_standard_deviation"
            ]
        )
    else:
        return _truth_process_definition(config)
    if state_name not in PROCESS_STATE_INDICES:
        raise ValueError("assumed filter process state name must be SUZ or SLZ")
    if not math.isfinite(deviation) or deviation <= 0.0:
        raise ValueError(
            "assumed filter process standard deviation must be finite and positive"
        )
    return PROCESS_STATE_INDICES[state_name], deviation


def _generate_splits(
    config: Mapping[str, Any],
    candidates: Mapping[str, Mapping[str, float]],
) -> tuple[ParameterSwitchBatch, ParameterSwitchBatch, ParameterSwitchBatch]:
    data = config["data"]
    seeds = config["seeds"]
    process_state_index, process_standard_deviation = _truth_process_definition(
        config
    )
    definitions = (
        ("training", int(data["training_blocks"]), int(seeds["training_split_offset"])),
        (
            "validation",
            int(data["validation_blocks"]),
            int(seeds["validation_split_offset"]),
        ),
        ("test", int(data["test_blocks"]), int(seeds["test_split_offset"])),
    )
    batches = []
    for split, count, offset in definitions:
        block_seeds = make_block_seeds(
            split=split,
            count=count,
            forcing_prefix=int(seeds["forcing_prefix"]),
            process_prefix=int(seeds["process_prefix"]),
            observation_prefix=int(seeds["observation_prefix"]),
            schedule_prefix=int(seeds["schedule_prefix"]),
            split_offset=offset,
        )
        batches.append(
            generate_parameter_switch_batch(
                block_seeds=block_seeds,
                parameter_candidates=candidates,
                assimilation_days=int(data["assimilation_days"]),
                maximum_forecast_lead=int(data["maximum_forecast_lead"]),
                warmup_days=int(data["warmup_days"]),
                minimum_duration=int(data["minimum_regime_duration_days"]),
                maximum_duration=int(data["maximum_regime_duration_days"]),
                process_standard_deviation=process_standard_deviation,
                process_state_index=process_state_index,
                require_zero_projection=bool(
                    data.get("require_zero_projection", True)
                ),
                observation_standard_deviation=float(
                    data["observation_standard_deviation"]
                ),
                initial_covariance_fraction=float(data["initial_covariance_fraction"]),
            )
        )
    return tuple(batches)  # type: ignore[return-value]


def _estimator(
    config: Mapping[str, Any],
    candidates: Mapping[str, Mapping[str, float]],
) -> DifferentiableInteractingMultipleModel:
    process_state_index, deviation = _filter_process_definition(config)
    covariance = torch.zeros((3, 15, 15), dtype=torch.float64)
    covariance[:, process_state_index, process_state_index] = deviation**2
    return DifferentiableInteractingMultipleModel(
        models=tuple(HBV15Model(values) for values in candidates.values()),
        process_covariances=covariance,
        observation_variance=float(
            config["data"]["observation_standard_deviation"]
        )
        ** 2,
    )


def _loss_weights(config: Mapping[str, Any]) -> ParameterLossWeights:
    values = config["loss"]
    if any(
        float(values[name]) != 0.0
        for name in (
            "true_state_supervision",
            "true_mode_supervision",
            "oracle_transition_supervision",
        )
    ):
        raise ValueError("H04 primary training must not use synthetic truth labels")
    return ParameterLossWeights(
        forecast=float(values["normalized_multilead_flow_mse"]),
        observation_negative_log_evidence=float(
            values["observation_negative_log_evidence"]
        ),
        transition_kl=float(values["transition_kl_from_base"]),
        transition_temporal_smoothness=float(
            values["transition_temporal_smoothness"]
        ),
    )


def _history_network(
    config: Mapping[str, Any],
    statistics: ParameterTrainingStatistics,
    base_transition: torch.Tensor,
) -> HistoryTransitionNetwork:
    return HistoryTransitionNetwork(
        base_transition=base_transition,
        feature_mean=statistics.feature_mean,
        feature_standard_deviation=statistics.feature_standard_deviation,
        hidden_size=int(config["network"]["hidden_size"]),
        maximum_logit_correction=float(
            config["network"]["maximum_logit_correction"]
        ),
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


def _write_history(path: Path, history: tuple[dict[str, float], ...]) -> None:
    if not history:
        raise ValueError("training history cannot be empty")
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(history[0]))
        writer.writeheader()
        writer.writerows(history)


def _save_checkpoint(
    path: Path,
    *,
    experiment_id: str,
    method: str,
    best_epoch: int,
    network_state: Mapping[str, torch.Tensor],
    statistics: ParameterTrainingStatistics,
    loss_weights: ParameterLossWeights,
) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    torch.save(
        {
            "experiment_id": experiment_id,
            "method": method,
            "best_epoch": int(best_epoch),
            "network_state_dict": network_state,
            "training_statistics": {
                "feature_mean": statistics.feature_mean,
                "feature_standard_deviation": statistics.feature_standard_deviation,
                "flow_standard_deviation": statistics.flow_standard_deviation,
            },
            "loss_weights": {
                "forecast": loss_weights.forecast,
                "observation_negative_log_evidence": loss_weights.observation_negative_log_evidence,
                "transition_kl": loss_weights.transition_kl,
                "transition_temporal_smoothness": loss_weights.transition_temporal_smoothness,
            },
            "true_labels_used_in_training": False,
        },
        temporary,
    )
    temporary.replace(path)


def _post_switch_forecast_loss(
    batch: ParameterSwitchBatch,
    rollout: ParameterRolloutResult,
    flow_standard_deviation: torch.Tensor,
    window_days: int = 7,
) -> float:
    days = batch.assimilation_days
    origin_mask = torch.zeros(
        (len(batch.block_ids), days), dtype=torch.bool, device=batch.forcing.device
    )
    for block in range(len(batch.block_ids)):
        for switch in batch.switch_days[block]:
            start = int(switch)
            origin_mask[block, start : min(start + int(window_days), days)] = True
    errors = []
    for lead_index, lead in enumerate(rollout.forecast_leads):
        target = batch.truth_discharge[:, lead : lead + days]
        errors.append(
            (
                (rollout.forecast_discharge[:, :, lead_index] - target)
                / flow_standard_deviation
            ).square()
        )
    error_tensor = torch.stack(errors, dim=-1)
    selected = rollout.forecast_valid_mask & origin_mask.unsqueeze(-1)
    if not torch.any(selected):
        raise ValueError("post-switch forecast mask is empty")
    return float(error_tensor[selected].mean())


def _method_metrics(
    *,
    batch: ParameterSwitchBatch,
    rollout: ParameterRolloutResult,
    statistics: ParameterTrainingStatistics,
    minimum_duration: int,
    maximum_duration: int,
) -> dict[str, Any]:
    oracle = build_active_row_oracle(batch, minimum_duration, maximum_duration)
    recovery = score_transition_recovery(
        rollout.transition_matrices.detach(), oracle
    ).to_dict()
    matrix = rollout.transition_matrices.detach()
    return {
        "losses": loss_values(rollout.losses),
        "transition_recovery": recovery,
        "post_switch_days_0_to_6_forecast_loss": _post_switch_forecast_loss(
            batch, rollout, statistics.flow_standard_deviation
        ),
        "maximum_transition_row_sum_error": float(
            torch.max(torch.abs(matrix.sum(dim=-1) - 1.0))
        ),
        "minimum_transition_probability": float(matrix.min()),
        "maximum_absolute_transition_correction": float(
            rollout.transition_corrections.detach().abs().max()
        ),
    }


def _relative_reduction(reference: float, candidate: float) -> float:
    if reference <= 0.0 or not math.isfinite(reference) or not math.isfinite(candidate):
        raise ValueError("relative-reduction inputs must be finite with positive reference")
    return (reference - candidate) / reference


def _gradient_audit(
    *,
    batch: ParameterSwitchBatch,
    network: HistoryTransitionNetwork,
    estimator: DifferentiableInteractingMultipleModel,
    candidates: Mapping[str, Mapping[str, float]],
    statistics: ParameterTrainingStatistics,
    leads: Sequence[int],
    loss_weights: ParameterLossWeights,
) -> dict[str, float | bool]:
    audit_batch = _slice_batch(batch, (0,))
    observations = audit_batch.observations.clone().requires_grad_(True)
    rollout = rollout_parameter_switch(
        audit_batch,
        network,
        estimator,
        candidates,
        statistics,
        forecast_leads=leads,
        observations=observations,
        loss_weights=loss_weights,
    )
    parameters = tuple(network.parameters())
    forecast_gradients = torch.autograd.grad(
        rollout.losses.forecast,
        parameters,
        retain_graph=True,
        allow_unused=True,
    )
    evidence_gradients = torch.autograd.grad(
        rollout.losses.observation_negative_log_evidence,
        parameters,
        retain_graph=True,
        allow_unused=True,
    )
    total_objective_gradients = torch.autograd.grad(
        rollout.losses.total,
        parameters,
        retain_graph=True,
        allow_unused=True,
    )
    audit_day = min(10, audit_batch.assimilation_days - 1)
    observation_gradient = torch.autograd.grad(
        rollout.transition_matrices[:, audit_day, 0, 0].sum(), observations
    )[0]

    def maximum(gradients) -> float:
        values = [
            float(gradient.detach().abs().max())
            for gradient in gradients
            if gradient is not None and torch.isfinite(gradient).all()
        ]
        return max(values, default=0.0)

    return {
        "maximum_absolute_forecast_loss_gradient_to_network": maximum(
            forecast_gradients
        ),
        "maximum_absolute_evidence_loss_gradient_to_network": maximum(
            evidence_gradients
        ),
        "maximum_absolute_total_objective_gradient_to_network": maximum(
            total_objective_gradients
        ),
        "maximum_absolute_past_observation_gradient": float(
            observation_gradient[:, :audit_day].abs().max()
        )
        if audit_day > 0
        else 0.0,
        "maximum_absolute_current_observation_gradient": float(
            observation_gradient[:, audit_day].abs().max()
        ),
        "maximum_absolute_future_observation_gradient": float(
            observation_gradient[:, audit_day + 1 :].abs().max()
        )
        if audit_day + 1 < observation_gradient.shape[1]
        else 0.0,
        "audit_day_zero_based": float(audit_day),
        "true_labels_used_in_training": False,
    }


def _save_daily_arrays(
    path: Path,
    *,
    batch: ParameterSwitchBatch,
    rollouts: Mapping[str, ParameterRolloutResult],
    statistics: ParameterTrainingStatistics,
) -> None:
    values: dict[str, np.ndarray] = {
        "truth_parameter_indices": batch.true_parameter_indices[
            :, : batch.assimilation_days
        ].cpu().numpy(),
        "truth_discharge": batch.truth_discharge.cpu().numpy(),
        "truth_states": batch.truth_states.cpu().numpy(),
        "process_perturbations": batch.process_perturbations.cpu().numpy(),
        "projection_adjustments": batch.projection_adjustments.cpu().numpy(),
        "accepted_process_seeds": np.asarray(
            batch.accepted_process_seeds, dtype=np.int64
        ),
        "switch_days": batch.switch_days.cpu().numpy(),
        "forecast_leads": np.asarray(next(iter(rollouts.values())).forecast_leads),
        "flow_standard_deviation": np.asarray(
            float(statistics.flow_standard_deviation)
        ),
        "block_ids": np.asarray(batch.block_ids),
    }
    for method, rollout in rollouts.items():
        prefix = str(method)
        values[f"{prefix}_transition_matrices"] = (
            rollout.transition_matrices.detach().cpu().numpy()
        )
        values[f"{prefix}_prior_probabilities"] = (
            rollout.prior_probabilities.detach().cpu().numpy()
        )
        values[f"{prefix}_posterior_probabilities"] = (
            rollout.posterior_probabilities.detach().cpu().numpy()
        )
        values[f"{prefix}_forecast_discharge"] = (
            rollout.forecast_discharge.detach().cpu().numpy()
        )
        values[f"{prefix}_forecast_valid_mask"] = (
            rollout.forecast_valid_mask.cpu().numpy()
        )
        values[f"{prefix}_observation_log_evidence"] = (
            rollout.observation_log_evidence.detach().cpu().numpy()
        )
        values[f"{prefix}_candidate_log_likelihoods"] = (
            rollout.candidate_log_likelihoods.detach().cpu().numpy()
        )
        values[f"{prefix}_candidate_prior_states"] = (
            rollout.candidate_prior_states.detach().cpu().numpy()
        )
        values[f"{prefix}_candidate_posterior_states"] = (
            rollout.candidate_posterior_states.detach().cpu().numpy()
        )
    temporary = path.with_suffix(path.suffix + ".tmp")
    with temporary.open("wb") as handle:
        np.savez_compressed(handle, **values)
    temporary.replace(path)


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


def run_parameter_switch_capability(
    config: Mapping[str, Any],
    *,
    project_root: str | Path,
    result_directory_override: str | Path | None = None,
) -> Path:
    """Train both controls, read test once, audit, and atomically publish H04."""

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
        raise ValueError("H04 registry and config output roots differ")
    source = (root / str(config["base_parameter_source"]["path"])).resolve()
    if _sha256(source) != str(config["base_parameter_source"]["sha256"]):
        raise ValueError("base parameter source hash mismatch")

    staging = Path(
        tempfile.mkdtemp(
            prefix=f".{config['experiment_id']}.staging-",
            dir=final_directory.parent,
        )
    )
    try:
        candidates = _parameter_candidates(config)
        training_batch, validation_batch, test_batch = _generate_splits(
            config, candidates
        )
        maximum_projection = float(
            max(
                training_batch.projection_adjustments.abs().max(),
                validation_batch.projection_adjustments.abs().max(),
                test_batch.projection_adjustments.abs().max(),
            )
        )
        process_state_index, _ = _truth_process_definition(config)
        maximum_projection_outside_process_state = 0.0
        for split_batch in (training_batch, validation_batch, test_batch):
            outside = split_batch.projection_adjustments.clone()
            outside[..., process_state_index] = 0.0
            maximum_projection_outside_process_state = max(
                maximum_projection_outside_process_state,
                float(outside.abs().max()),
            )
        signal_audit = audit_parameter_signal(
            training_batch,
            candidates,
            observation_standard_deviation=float(
                config["data"]["observation_standard_deviation"]
            ),
            leads=tuple(int(value) for value in config["forecast"]["leads_days"]),
        )
        signal_audit["maximum_absolute_projection_adjustment_all_splits"] = (
            maximum_projection
        )
        signal_audit[
            "maximum_absolute_projection_adjustment_outside_process_state"
        ] = maximum_projection_outside_process_state
        gates = config["capability_gates"]
        require_zero_projection = bool(
            config["data"].get("require_zero_projection", True)
        )
        if require_zero_projection:
            projection_threshold = float(
                gates["maximum_absolute_projection_adjustment"]
            )
            projection_gate_name = "zero_projection"
            projection_gate = {
                "value": maximum_projection,
                "threshold_maximum": projection_threshold,
                "passed": maximum_projection <= projection_threshold,
            }
            if not projection_gate["passed"]:
                raise ValueError("parameter-switch truth required state projection")
        else:
            if gates.get(
                "projection_adjustments_must_be_confined_to_process_state"
            ) is not True:
                raise ValueError(
                    "projected truth must require process-state-confined adjustments"
                )
            projection_gate_name = "projection_confined_to_process_state"
            projection_gate = {
                "value": maximum_projection_outside_process_state,
                "threshold_maximum": 0.0,
                "passed": maximum_projection_outside_process_state == 0.0,
                "maximum_absolute_projection_adjustment": maximum_projection,
            }
            if not projection_gate["passed"]:
                raise ValueError("truth projection changed a non-process state")
        if float(
            signal_audit["minimum_pairwise_rmse_to_observation_sd_ratio"]
        ) < float(gates["minimum_pairwise_rmse_to_observation_sd_ratio"]):
            raise ValueError("H04 parameter candidates failed the signal gate")

        statistics = fit_parameter_training_statistics(training_batch)
        estimator = _estimator(config, candidates)
        base_transition = _base_transition(
            float(config["filter"]["base_transition_stay_probability"])
        )
        loss_weights = _loss_weights(config)
        leads = tuple(int(value) for value in config["forecast"]["leads_days"])
        training = config["training"]

        torch.manual_seed(int(config["seeds"]["static_matrix_initialization"]))
        learned_static = _static_network(config, base_transition)
        static_training = train_parameter_transition(
            training_batch,
            validation_batch,
            learned_static,
            estimator,
            candidates,
            statistics,
            forecast_leads=leads,
            epochs=int(training["epochs"]),
            batch_size=int(training["batch_size"]),
            learning_rate=float(training["learning_rate"]),
            weight_decay=float(training["weight_decay"]),
            forbidden_test_batch=test_batch,
            loss_weights=loss_weights,
        )

        torch.manual_seed(int(config["seeds"]["history_network_initialization"]))
        history_network = _history_network(config, statistics, base_transition)
        history_training = train_parameter_transition(
            training_batch,
            validation_batch,
            history_network,
            estimator,
            candidates,
            statistics,
            forecast_leads=leads,
            epochs=int(training["epochs"]),
            batch_size=int(training["batch_size"]),
            learning_rate=float(training["learning_rate"]),
            weight_decay=float(training["weight_decay"]),
            forbidden_test_batch=test_batch,
            loss_weights=loss_weights,
        )

        fixed_network = _static_network(config, base_transition)
        fixed_network.eval()
        learned_static.eval()
        history_network.eval()
        with torch.no_grad():
            rollouts = {
                "fixed": rollout_parameter_switch(
                    test_batch,
                    fixed_network,
                    estimator,
                    candidates,
                    statistics,
                    forecast_leads=leads,
                    loss_weights=loss_weights,
                ),
                "learned_static": rollout_parameter_switch(
                    test_batch,
                    learned_static,
                    estimator,
                    candidates,
                    statistics,
                    forecast_leads=leads,
                    loss_weights=loss_weights,
                ),
                "history_conditioned": rollout_parameter_switch(
                    test_batch,
                    history_network,
                    estimator,
                    candidates,
                    statistics,
                    forecast_leads=leads,
                    loss_weights=loss_weights,
                ),
            }

        method_metrics = {
            method: _method_metrics(
                batch=test_batch,
                rollout=rollout,
                statistics=statistics,
                minimum_duration=int(config["data"]["minimum_regime_duration_days"]),
                maximum_duration=int(config["data"]["maximum_regime_duration_days"]),
            )
            for method, rollout in rollouts.items()
        }
        static_metrics = method_metrics["learned_static"]
        history_metrics = method_metrics["history_conditioned"]
        brier_reduction = _relative_reduction(
            float(static_metrics["transition_recovery"]["oracle_brier"]),
            float(history_metrics["transition_recovery"]["oracle_brier"]),
        )
        hazard_reduction = _relative_reduction(
            float(
                static_metrics["transition_recovery"][
                    "switch_hazard_mean_absolute_error"
                ]
            ),
            float(
                history_metrics["transition_recovery"][
                    "switch_hazard_mean_absolute_error"
                ]
            ),
        )
        post_switch_reduction = _relative_reduction(
            float(static_metrics["post_switch_days_0_to_6_forecast_loss"]),
            float(history_metrics["post_switch_days_0_to_6_forecast_loss"]),
        )
        static_overall = float(static_metrics["losses"]["forecast"])
        history_overall = float(history_metrics["losses"]["forecast"])
        overall_increase = (history_overall - static_overall) / static_overall

        legal = all(
            float(values["maximum_transition_row_sum_error"])
            <= float(gates["maximum_transition_row_sum_error"])
            and float(values["minimum_transition_probability"])
            >= float(gates["minimum_transition_probability"])
            for values in method_metrics.values()
        )
        gate_results = {
            projection_gate_name: projection_gate,
            "filter_free_parameter_signal": {
                "value": float(
                    signal_audit[
                        "minimum_pairwise_rmse_to_observation_sd_ratio"
                    ]
                ),
                "threshold_minimum": float(
                    gates["minimum_pairwise_rmse_to_observation_sd_ratio"]
                ),
                "passed": float(
                    signal_audit[
                        "minimum_pairwise_rmse_to_observation_sd_ratio"
                    ]
                )
                >= float(gates["minimum_pairwise_rmse_to_observation_sd_ratio"]),
            },
            "legal_transition_matrices": {
                "value": legal,
                "passed": legal,
            },
            "oracle_brier_reduction_history_vs_static": {
                "value": brier_reduction,
                "threshold_minimum": float(
                    gates[
                        "minimum_relative_oracle_brier_reduction_history_vs_static"
                    ]
                ),
                "passed": brier_reduction
                >= float(
                    gates[
                        "minimum_relative_oracle_brier_reduction_history_vs_static"
                    ]
                ),
            },
            "hazard_mae_reduction_history_vs_static": {
                "value": hazard_reduction,
                "threshold_minimum": float(
                    gates[
                        "minimum_relative_hazard_mae_reduction_history_vs_static"
                    ]
                ),
                "passed": hazard_reduction
                >= float(
                    gates[
                        "minimum_relative_hazard_mae_reduction_history_vs_static"
                    ]
                ),
            },
            "post_switch_forecast_reduction_history_vs_static": {
                "value": post_switch_reduction,
                "threshold_minimum": float(
                    gates[
                        "minimum_relative_post_switch_forecast_loss_reduction_history_vs_static"
                    ]
                ),
                "passed": post_switch_reduction
                >= float(
                    gates[
                        "minimum_relative_post_switch_forecast_loss_reduction_history_vs_static"
                    ]
                ),
            },
            "overall_forecast_non_degradation_history_vs_static": {
                "value": overall_increase,
                "threshold_maximum": float(
                    gates[
                        "maximum_relative_overall_forecast_loss_increase_history_vs_static"
                    ]
                ),
                "passed": overall_increase
                <= float(
                    gates[
                        "maximum_relative_overall_forecast_loss_increase_history_vs_static"
                    ]
                ),
            },
        }
        synthetic_capability_passed = all(
            bool(values["passed"]) for values in gate_results.values()
        )
        metrics = {
            "experiment_id": config["experiment_id"],
            "methods": method_metrics,
            "history_vs_learned_static": {
                "relative_oracle_brier_reduction": brier_reduction,
                "relative_switch_hazard_mae_reduction": hazard_reduction,
                "relative_post_switch_forecast_loss_reduction": post_switch_reduction,
                "relative_overall_forecast_loss_increase": overall_increase,
            },
            "capability_gates": gate_results,
            "synthetic_capability_passed": synthetic_capability_passed,
            "true_labels_used_in_training": False,
            "test_reads_before_both_checkpoint_selections": max(
                static_training.test_reads_before_selection,
                history_training.test_reads_before_selection,
            ),
            "test_read_after_both_checkpoint_selections": True,
            "best_epochs": {
                "learned_static": static_training.best_epoch,
                "history_conditioned": history_training.best_epoch,
            },
            "scientific_real_basin_superiority_established": False,
        }
        gradient_audit = _gradient_audit(
            batch=test_batch,
            network=history_network,
            estimator=estimator,
            candidates=candidates,
            statistics=statistics,
            leads=leads,
            loss_weights=loss_weights,
        )
        if (
            float(
                gradient_audit[
                    "maximum_absolute_forecast_loss_gradient_to_network"
                ]
            )
            <= 0.0
            or float(
                gradient_audit[
                    "maximum_absolute_evidence_loss_gradient_to_network"
                ]
            )
            <= 0.0
        ):
            raise ValueError("H04 losses did not reach the history network")
        if (
            float(
                gradient_audit[
                    "maximum_absolute_total_objective_gradient_to_network"
                ]
            )
            <= 0.0
        ):
            raise ValueError("H04 optimized objective did not reach the history network")
        if (
            float(
                gradient_audit["maximum_absolute_current_observation_gradient"]
            )
            != 0.0
            or float(
                gradient_audit["maximum_absolute_future_observation_gradient"]
            )
            != 0.0
        ):
            raise ValueError("current or future observation leaked into transition prior")
        if not _all_finite(metrics) or not _all_finite(gradient_audit):
            raise ValueError("H04 metrics contain non-finite values")

        _write_json(staging / "config_snapshot.json", dict(config))
        _write_json(staging / "registry_entry.json", registry_row)
        _write_json(staging / "signal_audit.json", signal_audit)
        _write_history(
            staging / "static_training_history.csv", static_training.history
        )
        _write_history(
            staging / "history_training_history.csv", history_training.history
        )
        _save_checkpoint(
            staging / "static_best_checkpoint.pt",
            experiment_id=str(config["experiment_id"]),
            method="learned_history_free_constant",
            best_epoch=static_training.best_epoch,
            network_state=static_training.best_network_state,
            statistics=statistics,
            loss_weights=loss_weights,
        )
        _save_checkpoint(
            staging / "history_best_checkpoint.pt",
            experiment_id=str(config["experiment_id"]),
            method="history_conditioned_dynamic",
            best_epoch=history_training.best_epoch,
            network_state=history_training.best_network_state,
            statistics=statistics,
            loss_weights=loss_weights,
        )
        _save_daily_arrays(
            staging / "daily_arrays.npz",
            batch=test_batch,
            rollouts=rollouts,
            statistics=statistics,
        )
        _write_json(staging / "metrics.json", metrics)
        _write_json(staging / "gradient_audit.json", gradient_audit)
        _write_json(
            staging / "environment.json",
            {
                "python": sys.version,
                "platform": platform.platform(),
                "torch": torch.__version__,
                "numpy": np.__version__,
                "git_head": _git_head(root),
                "process_id": os.getpid(),
            },
        )
        required = tuple(config["required_result_files"])
        missing_before_checksums = [
            name
            for name in required
            if name != "checksums.json" and not (staging / name).is_file()
        ]
        if missing_before_checksums:
            raise RuntimeError(
                f"H04 staging output is incomplete: {missing_before_checksums}"
            )
        checksums = {
            name: _sha256(staging / name)
            for name in required
            if name != "checksums.json"
        }
        _write_json(staging / "checksums.json", checksums)
        missing = [name for name in required if not (staging / name).is_file()]
        if missing:
            raise RuntimeError(f"H04 staging output is incomplete: {missing}")
        staging.replace(final_directory)
        return final_directory
    except Exception:
        if staging.exists() and staging.parent == final_directory.parent:
            shutil.rmtree(staging)
        raise


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", default=str(DEFAULT_CONFIG_PATH))
    parser.add_argument("--project-root", default=str(PACKAGE_ROOT.parents[1]))
    arguments = parser.parse_args()
    config = load_h04_config(arguments.config)
    output = run_parameter_switch_capability(
        config, project_root=arguments.project_root
    )
    print(output)


if __name__ == "__main__":
    main()

"""Run the registered active-row transition-probability recovery audit."""

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
from typing import Any, Mapping

import torch

from hbv_history_conditioned_imm.hbv import HBV15Model
from hbv_history_conditioned_imm.network import HistoryTransitionNetwork
from hbv_history_conditioned_imm.probability_audit import (
    active_transition_rows,
    build_active_row_oracle,
    score_transition_recovery,
)
from hbv_history_conditioned_imm.training import (
    LossWeights,
    TrainingStatistics,
    rollout_end_to_end,
    train_history_transition,
)
from hbv_history_conditioned_imm.scripts.run_h01_end_to_end_smoke import (
    _base_transition,
    _build_estimator,
    _generate_splits,
    _git_head,
    _sha256,
    _write_json,
    load_config,
    load_registry_row,
)


def load_probability_config(path: str | Path) -> dict[str, Any]:
    with Path(path).open("r", encoding="utf-8") as handle:
        config = json.load(handle)
    required = {
        "experiment_id",
        "result_relative_path",
        "source_h01_config",
        "source_h01_checkpoint",
        "oracle",
        "flow_only_loss",
        "required_result_files",
    }
    missing = required - set(config)
    if missing:
        raise ValueError(f"probability audit config is missing: {sorted(missing)}")
    return config


def _loss_values(losses) -> dict[str, float]:
    return {
        "training_objective_total": float(losses.total),
        "forecast": float(losses.forecast),
        "state": float(losses.state),
        "prior_cross_entropy": float(losses.prior_cross_entropy),
        "transition_kl": float(losses.transition_kl),
        "transition_temporal_smoothness": float(
            losses.transition_temporal_smoothness
        ),
        "active_row_oracle_brier": float(losses.active_row_oracle_brier),
    }


def _all_finite(values: Any) -> bool:
    if isinstance(values, Mapping):
        return all(_all_finite(value) for value in values.values())
    if isinstance(values, (list, tuple)):
        return all(_all_finite(value) for value in values)
    if isinstance(values, float):
        return math.isfinite(values)
    return True


def _network(
    base_config: Mapping[str, Any],
    statistics: TrainingStatistics,
) -> HistoryTransitionNetwork:
    return HistoryTransitionNetwork(
        base_transition=_base_transition(
            base_config["filter"]["base_transition_stay_probability"]
        ),
        feature_mean=statistics.feature_mean,
        feature_standard_deviation=statistics.feature_standard_deviation,
        hidden_size=int(base_config["network"]["hidden_size"]),
        maximum_logit_correction=float(
            base_config["network"]["maximum_logit_correction"]
        ),
    )


def _flow_only_weights(config: Mapping[str, Any]) -> LossWeights:
    values = config["flow_only_loss"]
    return LossWeights(
        forecast=float(values["forecast"]),
        state=float(values["state"]),
        prior_cross_entropy=float(values["prior_cross_entropy"]),
        transition_kl=float(values["transition_kl"]),
        transition_temporal_smoothness=float(
            values["transition_temporal_smoothness"]
        ),
    )


def _daily_rows(
    *,
    arm_id: str,
    block_ids: tuple[str, ...],
    transition_matrices: torch.Tensor,
    oracle,
) -> list[dict[str, int | float | str]]:
    active_rows = active_transition_rows(
        transition_matrices, oracle.source_indices
    )
    records = []
    for block, block_id in enumerate(block_ids):
        for day in range(transition_matrices.shape[1]):
            if not bool(oracle.evaluation_mask[block, day]):
                continue
            source = int(oracle.source_indices[block, day])
            destination = int(oracle.destination_indices[block, day])
            predicted = active_rows[block, day]
            expected = oracle.active_row_probabilities[block, day]
            predicted_hazard = float(predicted.sum() - predicted[source])
            records.append(
                {
                    "arm_id": arm_id,
                    "block_id": block_id,
                    "transition_day_zero_based": day,
                    "segment_age_days": int(oracle.segment_age[block, day]),
                    "source_process_index": source,
                    "realized_destination_process_index": destination,
                    "is_realized_switch": int(
                        oracle.switch_event_mask[block, day]
                    ),
                    "oracle_switch_hazard": float(
                        oracle.switch_hazard[block, day]
                    ),
                    "predicted_switch_hazard": predicted_hazard,
                    "oracle_probability_low": float(expected[0]),
                    "oracle_probability_medium": float(expected[1]),
                    "oracle_probability_high": float(expected[2]),
                    "predicted_probability_low": float(predicted[0]),
                    "predicted_probability_medium": float(predicted[1]),
                    "predicted_probability_high": float(predicted[2]),
                }
            )
    return records


def run_probability_audit(
    config: Mapping[str, Any],
    *,
    project_root: str | Path,
    result_directory_override: str | Path | None = None,
) -> Path:
    """Train the flow-only arm, then score three frozen arms on held-out data."""
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
        raise ValueError("registry and probability-audit output roots differ")
    for source_key in ("source_h01_config", "source_h01_checkpoint"):
        source = (root / str(config[source_key]["path"])).resolve()
        if _sha256(source) != str(config[source_key]["sha256"]):
            raise ValueError(f"source hash mismatch: {source_key}")

    source_config_path = (
        root / str(config["source_h01_config"]["path"])
    ).resolve()
    source_checkpoint_path = (
        root / str(config["source_h01_checkpoint"]["path"])
    ).resolve()
    base_config = load_config(source_config_path)
    source_checkpoint = torch.load(
        source_checkpoint_path, map_location="cpu", weights_only=False
    )
    if source_checkpoint["experiment_id"] != base_config["experiment_id"]:
        raise ValueError("source checkpoint and source config identifiers differ")
    statistics = TrainingStatistics(**source_checkpoint["training_statistics"])

    staging = Path(
        tempfile.mkdtemp(
            prefix=f".{config['experiment_id']}.staging-",
            dir=final_directory.parent,
        )
    )
    try:
        torch.manual_seed(int(base_config["seeds"]["network_initialization"]))
        training_batch, validation_batch, test_batch = _generate_splits(base_config)
        model = HBV15Model(base_config["parameters"])
        estimator = _build_estimator(base_config, model)
        leads = tuple(
            int(value)
            for value in base_config["training"]["forecast_leads_days"]
        )

        mixed_network = _network(base_config, statistics)
        mixed_network.load_state_dict(source_checkpoint["network_state_dict"])
        mixed_network.eval()

        torch.manual_seed(int(base_config["seeds"]["network_initialization"]))
        flow_network = _network(base_config, statistics)
        flow_weights = _flow_only_weights(config)
        training_result = train_history_transition(
            training_batch,
            validation_batch,
            flow_network,
            estimator,
            model,
            statistics,
            forecast_leads=leads,
            epochs=int(base_config["training"]["epochs"]),
            batch_size=int(base_config["training"]["batch_size"]),
            learning_rate=float(base_config["training"]["learning_rate"]),
            weight_decay=float(base_config["training"]["weight_decay"]),
            forbidden_test_batch=test_batch,
            loss_weights=flow_weights,
        )
        if training_result.test_reads_before_selection != 0:
            raise ValueError("test split was read before flow-only checkpoint selection")

        fixed_network = _network(base_config, statistics)
        fixed_network.eval()
        flow_network.eval()
        with torch.no_grad():
            fixed_rollout = rollout_end_to_end(
                test_batch,
                fixed_network,
                estimator,
                model,
                statistics,
                forecast_leads=leads,
            )
            mixed_rollout = rollout_end_to_end(
                test_batch,
                mixed_network,
                estimator,
                model,
                statistics,
                forecast_leads=leads,
            )
            flow_rollout = rollout_end_to_end(
                test_batch,
                flow_network,
                estimator,
                model,
                statistics,
                forecast_leads=leads,
                loss_weights=flow_weights,
            )

        oracle_config = config["oracle"]
        oracle = build_active_row_oracle(
            test_batch,
            int(oracle_config["minimum_duration_days"]),
            int(oracle_config["maximum_duration_days"]),
        )
        rollouts = {
            "fixed_transition": fixed_rollout,
            "mixed_loss_dynamic": mixed_rollout,
            "flow_only_dynamic": flow_rollout,
        }
        arm_metrics = {}
        daily_records = []
        for arm_id, rollout in rollouts.items():
            recovery = score_transition_recovery(
                rollout.transition_matrices, oracle
            )
            arm_metrics[arm_id] = {
                "losses": _loss_values(rollout.losses),
                "transition_recovery": recovery.to_dict(),
                "maximum_transition_row_sum_error": float(
                    (rollout.transition_matrices.sum(dim=-1) - 1.0)
                    .abs()
                    .max()
                ),
                "minimum_transition_probability": float(
                    rollout.transition_matrices.min()
                ),
                "maximum_absolute_deviation_from_fixed": float(
                    (
                        rollout.transition_matrices
                        - fixed_network.base_transition
                    )
                    .abs()
                    .max()
                ),
            }
            daily_records.extend(
                _daily_rows(
                    arm_id=arm_id,
                    block_ids=test_batch.block_ids,
                    transition_matrices=rollout.transition_matrices,
                    oracle=oracle,
                )
            )
        fixed_scores = arm_metrics["fixed_transition"]["transition_recovery"]
        comparisons = {}
        for arm_id in ("mixed_loss_dynamic", "flow_only_dynamic"):
            scores = arm_metrics[arm_id]["transition_recovery"]
            comparisons[arm_id] = {
                "oracle_brier_improvement_vs_fixed": fixed_scores[
                    "oracle_brier"
                ]
                - scores["oracle_brier"],
                "switch_hazard_mae_improvement_vs_fixed": fixed_scores[
                    "switch_hazard_mean_absolute_error"
                ]
                - scores["switch_hazard_mean_absolute_error"],
                "realized_log_score_improvement_vs_fixed": fixed_scores[
                    "realized_transition_negative_log_score"
                ]
                - scores["realized_transition_negative_log_score"],
                "forecast_loss_improvement_vs_fixed": arm_metrics[
                    "fixed_transition"
                ]["losses"]["forecast"]
                - arm_metrics[arm_id]["losses"]["forecast"],
                "active_row_recovery_better_than_fixed_point_estimate": bool(
                    scores["oracle_brier"] < fixed_scores["oracle_brier"]
                    and scores["switch_hazard_mean_absolute_error"]
                    < fixed_scores["switch_hazard_mean_absolute_error"]
                ),
            }
        metrics = {
            "experiment_id": config["experiment_id"],
            "source_experiment_id": base_config["experiment_id"],
            "flow_only_best_epoch": training_result.best_epoch,
            "flow_only_best_validation_loss": training_result.best_validation_loss,
            "test_reads_before_selection": training_result.test_reads_before_selection,
            "oracle_scope": {
                "evaluated_rows": "realized source row only",
                "evaluated_transition_count": int(
                    torch.count_nonzero(oracle.evaluation_mask)
                ),
                "switch_event_count": int(
                    torch.count_nonzero(oracle.switch_event_mask)
                ),
                "post_second_switch_censored": True,
            },
            "arms": arm_metrics,
            "comparisons": comparisons,
            "diagnostic_only": True,
            "full_transition_matrix_recovered": False,
            "scientific_superiority_established": False,
        }
        if not _all_finite(metrics):
            raise ValueError("probability audit produced non-finite metrics")
        for values in arm_metrics.values():
            if values["maximum_transition_row_sum_error"] > 1e-12:
                raise ValueError("transition row-sum gate failed")
            if values["minimum_transition_probability"] < 0.0:
                raise ValueError("transition nonnegativity gate failed")

        _write_json(staging / "config_snapshot.json", dict(config))
        _write_json(staging / "registry_entry.json", registry_row)
        history_path = staging / "flow_only_training_history.csv"
        with history_path.open("w", encoding="utf-8", newline="") as handle:
            writer = csv.DictWriter(
                handle, fieldnames=list(training_result.history[0].keys())
            )
            writer.writeheader()
            writer.writerows(training_result.history)
        checkpoint_path = staging / "flow_only_best_checkpoint.pt"
        checkpoint_temporary = checkpoint_path.with_suffix(".pt.tmp")
        torch.save(
            {
                "experiment_id": config["experiment_id"],
                "source_experiment_id": base_config["experiment_id"],
                "best_epoch": training_result.best_epoch,
                "network_state_dict": training_result.best_network_state,
                "training_statistics": source_checkpoint["training_statistics"],
                "loss_weights": config["flow_only_loss"],
            },
            checkpoint_temporary,
        )
        checkpoint_temporary.replace(checkpoint_path)
        _write_json(staging / "probability_metrics.json", metrics)
        daily_path = staging / "daily_active_row_audit.csv"
        with daily_path.open("w", encoding="utf-8", newline="") as handle:
            writer = csv.DictWriter(
                handle, fieldnames=list(daily_records[0].keys())
            )
            writer.writeheader()
            writer.writerows(daily_records)
        environment = {
            "python": sys.version,
            "platform": platform.platform(),
            "torch": torch.__version__,
            "git_head": _git_head(root),
            "process_id": os.getpid(),
            "source_h01_config_sha256": config["source_h01_config"][
                "sha256"
            ],
            "source_h01_checkpoint_sha256": config[
                "source_h01_checkpoint"
            ]["sha256"],
        }
        _write_json(staging / "environment.json", environment)
        required = tuple(config["required_result_files"])
        absent = [
            name
            for name in required
            if name != "checksums.json" and not (staging / name).is_file()
        ]
        if absent:
            raise RuntimeError(f"probability audit staging is incomplete: {absent}")
        checksums = {
            name: _sha256(staging / name)
            for name in required
            if name != "checksums.json"
        }
        _write_json(staging / "checksums.json", checksums)
        if any(not (staging / name).is_file() for name in required):
            raise RuntimeError("probability audit required files are incomplete")
        staging.replace(final_directory)
        return final_directory
    except Exception:
        if staging.exists() and staging.parent == final_directory.parent:
            shutil.rmtree(staging)
        raise


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True)
    arguments = parser.parse_args()
    config_path = Path(arguments.config).resolve()
    config = load_probability_config(config_path)
    project_root = Path(__file__).resolve().parents[3]
    result = run_probability_audit(config, project_root=project_root)
    print(result)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

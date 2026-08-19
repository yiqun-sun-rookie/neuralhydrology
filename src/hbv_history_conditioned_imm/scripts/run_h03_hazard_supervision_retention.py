"""Run known-hazard supervision followed by generated-flow-only fine-tuning."""

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
    _build_estimator,
    _generate_splits,
    _git_head,
    _sha256,
    _write_json,
    load_config,
    load_registry_row,
)
from hbv_history_conditioned_imm.scripts.run_h02_transition_probability_recovery import (
    _all_finite,
    _daily_rows,
    _loss_values,
    _network,
)


def load_hazard_config(path: str | Path) -> dict[str, Any]:
    with Path(path).open("r", encoding="utf-8") as handle:
        config = json.load(handle)
    required = {
        "experiment_id",
        "result_relative_path",
        "source_h01_config",
        "source_h02_config",
        "source_h02_flow_only_checkpoint",
        "oracle",
        "supervised_phase",
        "retention_phase",
        "capability_gates",
        "retention_gates",
        "required_result_files",
    }
    missing = required - set(config)
    if missing:
        raise ValueError(f"hazard supervision config is missing: {sorted(missing)}")
    return config


def loss_weights_from_config(phase: Mapping[str, Any]) -> LossWeights:
    values = phase["loss_weights"]
    return LossWeights(
        forecast=float(values["forecast"]),
        state=float(values["state"]),
        prior_cross_entropy=float(values["prior_cross_entropy"]),
        transition_kl=float(values["transition_kl"]),
        transition_temporal_smoothness=float(
            values["transition_temporal_smoothness"]
        ),
        active_row_oracle_brier=float(values["active_row_oracle_brier"]),
    )


def _age_hazard_summary(transition_matrices: torch.Tensor, oracle) -> dict[str, float]:
    rows = active_transition_rows(transition_matrices, oracle.source_indices)
    source_one_hot = torch.nn.functional.one_hot(
        oracle.source_indices, num_classes=3
    ).to(dtype=rows.dtype)
    predicted_hazard = (rows * (1.0 - source_one_hot)).sum(dim=-1)
    evaluated = oracle.evaluation_mask
    minimum_age = int(oracle.segment_age[oracle.switch_hazard > 0.0].min())
    early = evaluated & (oracle.segment_age < minimum_age)
    late = evaluated & (oracle.segment_age >= minimum_age)
    if not torch.any(early) or not torch.any(late):
        raise ValueError("hazard age groups are empty")
    early_mean = float(predicted_hazard[early].mean())
    late_mean = float(predicted_hazard[late].mean())
    return {
        "early_age_predicted_hazard": early_mean,
        "switch_eligible_age_predicted_hazard": late_mean,
        "late_minus_early_predicted_hazard": late_mean - early_mean,
    }


def _write_history(path: Path, history: tuple[dict[str, float], ...]) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(history[0].keys()))
        writer.writeheader()
        writer.writerows(history)


def _save_checkpoint(
    path: Path,
    *,
    experiment_id: str,
    phase: str,
    best_epoch: int,
    network_state: Mapping[str, torch.Tensor],
    statistics: Mapping[str, torch.Tensor],
    loss_weights: Mapping[str, float],
) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    torch.save(
        {
            "experiment_id": experiment_id,
            "phase": phase,
            "best_epoch": best_epoch,
            "network_state_dict": network_state,
            "training_statistics": statistics,
            "loss_weights": loss_weights,
        },
        temporary,
    )
    temporary.replace(path)


def run_hazard_supervision_retention(
    config: Mapping[str, Any],
    *,
    project_root: str | Path,
    result_directory_override: str | Path | None = None,
) -> Path:
    """Train two phases, freeze both checkpoints, and then read test data."""
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
        raise ValueError("h03 registry and config output roots differ")
    for source_key in (
        "source_h01_config",
        "source_h02_config",
        "source_h02_flow_only_checkpoint",
    ):
        source = (root / str(config[source_key]["path"])).resolve()
        if _sha256(source) != str(config[source_key]["sha256"]):
            raise ValueError(f"source hash mismatch: {source_key}")

    base_config_path = (root / str(config["source_h01_config"]["path"])).resolve()
    h02_config_path = (root / str(config["source_h02_config"]["path"])).resolve()
    h02_checkpoint_path = (
        root / str(config["source_h02_flow_only_checkpoint"]["path"])
    ).resolve()
    base_config = load_config(base_config_path)
    with h02_config_path.open("r", encoding="utf-8") as handle:
        h02_config = json.load(handle)
    h02_checkpoint = torch.load(
        h02_checkpoint_path, map_location="cpu", weights_only=False
    )
    if h02_checkpoint["experiment_id"] != h02_config["experiment_id"]:
        raise ValueError("h02 checkpoint and config identifiers differ")
    statistics = TrainingStatistics(**h02_checkpoint["training_statistics"])
    statistics_mapping = h02_checkpoint["training_statistics"]

    staging = Path(
        tempfile.mkdtemp(
            prefix=f".{config['experiment_id']}.staging-",
            dir=final_directory.parent,
        )
    )
    try:
        training_batch, validation_batch, test_batch = _generate_splits(base_config)
        model = HBV15Model(base_config["parameters"])
        estimator = _build_estimator(base_config, model)
        leads = tuple(
            int(value)
            for value in base_config["training"]["forecast_leads_days"]
        )
        oracle_bounds = (
            int(config["oracle"]["minimum_duration_days"]),
            int(config["oracle"]["maximum_duration_days"]),
        )

        supervised_phase = config["supervised_phase"]
        supervised_weights = loss_weights_from_config(supervised_phase)
        torch.manual_seed(int(base_config["seeds"]["network_initialization"]))
        supervised_network = _network(base_config, statistics)
        supervised_result = train_history_transition(
            training_batch,
            validation_batch,
            supervised_network,
            estimator,
            model,
            statistics,
            forecast_leads=leads,
            epochs=int(supervised_phase["epochs"]),
            batch_size=int(supervised_phase["batch_size"]),
            learning_rate=float(supervised_phase["learning_rate"]),
            weight_decay=float(base_config["training"]["weight_decay"]),
            forbidden_test_batch=test_batch,
            loss_weights=supervised_weights,
            oracle_duration_bounds=oracle_bounds,
        )

        retention_phase = config["retention_phase"]
        retention_weights = loss_weights_from_config(retention_phase)
        retention_network = _network(base_config, statistics)
        retention_network.load_state_dict(supervised_result.best_network_state)
        retention_result = train_history_transition(
            training_batch,
            validation_batch,
            retention_network,
            estimator,
            model,
            statistics,
            forecast_leads=leads,
            epochs=int(retention_phase["epochs"]),
            batch_size=int(retention_phase["batch_size"]),
            learning_rate=float(retention_phase["learning_rate"]),
            weight_decay=float(base_config["training"]["weight_decay"]),
            forbidden_test_batch=test_batch,
            loss_weights=retention_weights,
            oracle_duration_bounds=oracle_bounds,
        )
        if (
            supervised_result.test_reads_before_selection != 0
            or retention_result.test_reads_before_selection != 0
        ):
            raise ValueError("test split was read during checkpoint selection")

        fixed_network = _network(base_config, statistics)
        fixed_network.eval()
        h02_network = _network(base_config, statistics)
        h02_network.load_state_dict(h02_checkpoint["network_state_dict"])
        h02_network.eval()
        supervised_network.eval()
        retention_network.eval()
        with torch.no_grad():
            fixed_rollout = rollout_end_to_end(
                test_batch,
                fixed_network,
                estimator,
                model,
                statistics,
                forecast_leads=leads,
                oracle_duration_bounds=oracle_bounds,
            )
            h02_rollout = rollout_end_to_end(
                test_batch,
                h02_network,
                estimator,
                model,
                statistics,
                forecast_leads=leads,
                loss_weights=retention_weights,
                oracle_duration_bounds=oracle_bounds,
            )
            supervised_rollout = rollout_end_to_end(
                test_batch,
                supervised_network,
                estimator,
                model,
                statistics,
                forecast_leads=leads,
                loss_weights=supervised_weights,
                oracle_duration_bounds=oracle_bounds,
            )
            retention_rollout = rollout_end_to_end(
                test_batch,
                retention_network,
                estimator,
                model,
                statistics,
                forecast_leads=leads,
                loss_weights=retention_weights,
                oracle_duration_bounds=oracle_bounds,
            )

        oracle = build_active_row_oracle(test_batch, *oracle_bounds)
        rollouts = {
            "fixed_transition": fixed_rollout,
            "h02_flow_only": h02_rollout,
            "hazard_supervised": supervised_rollout,
            "post_flow_only_retention": retention_rollout,
        }
        arm_metrics = {}
        daily_records = []
        for arm_id, rollout in rollouts.items():
            scores = score_transition_recovery(
                rollout.transition_matrices, oracle
            )
            arm_metrics[arm_id] = {
                "losses": _loss_values(rollout.losses),
                "transition_recovery": scores.to_dict(),
                "age_hazard": _age_hazard_summary(
                    rollout.transition_matrices, oracle
                ),
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
        supervised_scores = arm_metrics["hazard_supervised"][
            "transition_recovery"
        ]
        retention_scores = arm_metrics["post_flow_only_retention"][
            "transition_recovery"
        ]
        relative_brier_reduction = (
            fixed_scores["oracle_brier"] - supervised_scores["oracle_brier"]
        ) / fixed_scores["oracle_brier"]
        fixed_hazard_error = fixed_scores[
            "switch_hazard_mean_absolute_error"
        ]
        supervised_hazard_error = supervised_scores[
            "switch_hazard_mean_absolute_error"
        ]
        retention_hazard_error = retention_scores[
            "switch_hazard_mean_absolute_error"
        ]
        relative_hazard_reduction = (
            fixed_hazard_error - supervised_hazard_error
        ) / fixed_hazard_error
        supervised_hazard_improvement = (
            fixed_hazard_error - supervised_hazard_error
        )
        retention_hazard_improvement = (
            fixed_hazard_error - retention_hazard_error
        )
        retained_fraction = (
            retention_hazard_improvement / supervised_hazard_improvement
            if supervised_hazard_improvement > 0.0
            else 0.0
        )
        h02_forecast = arm_metrics["h02_flow_only"]["losses"]["forecast"]
        retention_forecast = arm_metrics["post_flow_only_retention"][
            "losses"
        ]["forecast"]
        relative_retention_forecast_increase = (
            retention_forecast - h02_forecast
        ) / h02_forecast

        capability_thresholds = config["capability_gates"]
        capability_gates = {
            "oracle_brier_relative_reduction": relative_brier_reduction
            >= float(
                capability_thresholds[
                    "minimum_relative_oracle_brier_reduction_vs_fixed"
                ]
            ),
            "switch_hazard_mae_relative_reduction": relative_hazard_reduction
            >= float(
                capability_thresholds[
                    "minimum_relative_switch_hazard_mae_reduction_vs_fixed"
                ]
            ),
            "late_minus_early_hazard": arm_metrics["hazard_supervised"][
                "age_hazard"
            ]["late_minus_early_predicted_hazard"]
            >= float(
                capability_thresholds[
                    "minimum_late_minus_early_predicted_hazard"
                ]
            ),
        }
        retention_thresholds = config["retention_gates"]
        retention_gates = {
            "retained_hazard_improvement": retained_fraction
            >= float(
                retention_thresholds[
                    "minimum_retained_fraction_of_supervised_hazard_mae_improvement"
                ]
            ),
            "forecast_loss_within_h02_tolerance": relative_retention_forecast_increase
            <= float(
                retention_thresholds[
                    "maximum_relative_forecast_loss_increase_vs_h02_flow_only"
                ]
            ),
        }
        metrics = {
            "experiment_id": config["experiment_id"],
            "source_h02_experiment_id": h02_config["experiment_id"],
            "supervised_best_epoch": supervised_result.best_epoch,
            "retention_best_epoch": retention_result.best_epoch,
            "test_reads_before_selection": 0,
            "oracle_scope": {
                "evaluated_transition_count": int(
                    torch.count_nonzero(oracle.evaluation_mask)
                ),
                "switch_event_count": int(
                    torch.count_nonzero(oracle.switch_event_mask)
                ),
                "realized_source_row_only": True,
            },
            "arms": arm_metrics,
            "capability_values": {
                "relative_oracle_brier_reduction_vs_fixed": relative_brier_reduction,
                "relative_switch_hazard_mae_reduction_vs_fixed": relative_hazard_reduction,
                "late_minus_early_predicted_hazard": arm_metrics[
                    "hazard_supervised"
                ]["age_hazard"]["late_minus_early_predicted_hazard"],
            },
            "capability_gates": capability_gates,
            "capability_overall_pass": all(capability_gates.values()),
            "retention_values": {
                "retained_fraction_of_supervised_hazard_mae_improvement": retained_fraction,
                "relative_forecast_loss_increase_vs_h02_flow_only": relative_retention_forecast_increase,
            },
            "retention_gates": retention_gates,
            "retention_overall_pass": all(retention_gates.values()),
            "diagnostic_only": True,
            "real_basin_probability_recovery_established": False,
        }
        if not _all_finite(metrics):
            raise ValueError("h03 metrics contain non-finite values")
        for values in arm_metrics.values():
            if values["maximum_transition_row_sum_error"] > 1e-12:
                raise ValueError("h03 transition row-sum gate failed")
            if values["minimum_transition_probability"] < 0.0:
                raise ValueError("h03 transition nonnegativity gate failed")

        _write_json(staging / "config_snapshot.json", dict(config))
        _write_json(staging / "registry_entry.json", registry_row)
        _write_history(
            staging / "supervised_training_history.csv",
            supervised_result.history,
        )
        _write_history(
            staging / "retention_training_history.csv",
            retention_result.history,
        )
        _save_checkpoint(
            staging / "supervised_best_checkpoint.pt",
            experiment_id=str(config["experiment_id"]),
            phase="hazard_supervised",
            best_epoch=supervised_result.best_epoch,
            network_state=supervised_result.best_network_state,
            statistics=statistics_mapping,
            loss_weights=supervised_phase["loss_weights"],
        )
        _save_checkpoint(
            staging / "retention_best_checkpoint.pt",
            experiment_id=str(config["experiment_id"]),
            phase="post_flow_only_retention",
            best_epoch=retention_result.best_epoch,
            network_state=retention_result.best_network_state,
            statistics=statistics_mapping,
            loss_weights=retention_phase["loss_weights"],
        )
        _write_json(staging / "metrics.json", metrics)
        with (staging / "daily_active_row_audit.csv").open(
            "w", encoding="utf-8", newline=""
        ) as handle:
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
            "source_hashes": {
                key: config[key]["sha256"]
                for key in (
                    "source_h01_config",
                    "source_h02_config",
                    "source_h02_flow_only_checkpoint",
                )
            },
        }
        _write_json(staging / "environment.json", environment)
        required = tuple(config["required_result_files"])
        missing = [
            name
            for name in required
            if name != "checksums.json" and not (staging / name).is_file()
        ]
        if missing:
            raise RuntimeError(f"h03 staging output is incomplete: {missing}")
        checksums = {
            name: _sha256(staging / name)
            for name in required
            if name != "checksums.json"
        }
        _write_json(staging / "checksums.json", checksums)
        if any(not (staging / name).is_file() for name in required):
            raise RuntimeError("h03 required files are incomplete")
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
    config = load_hazard_config(Path(arguments.config).resolve())
    project_root = Path(__file__).resolve().parents[3]
    result = run_hazard_supervision_retention(
        config, project_root=project_root
    )
    print(result)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

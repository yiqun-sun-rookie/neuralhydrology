"""Run the registered generated-flow end-to-end diagnostic smoke experiment."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import os
import platform
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any, Mapping

import torch

from hbv_history_conditioned_imm.filter import DifferentiableInteractingMultipleModel
from hbv_history_conditioned_imm.hbv import HBV15Model
from hbv_history_conditioned_imm.network import (
    HistoryTransitionNetwork,
    build_history_features,
)
from hbv_history_conditioned_imm.synthetic import (
    SyntheticBatch,
    generate_synthetic_batch,
    make_block_seeds,
)
from hbv_history_conditioned_imm.training import (
    TrainingStatistics,
    fit_training_statistics,
    rollout_end_to_end,
    train_history_transition,
)


PACKAGE_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_REGISTRY_PATH = PACKAGE_ROOT / "configs" / "experiment_registry.csv"


def load_config(path: str | Path) -> dict[str, Any]:
    config_path = Path(path)
    with config_path.open("r", encoding="utf-8") as handle:
        config = json.load(handle)
    required = {
        "experiment_id",
        "result_relative_path",
        "parameters",
        "data",
        "seeds",
        "filter",
        "network",
        "training",
        "required_result_files",
    }
    missing = required - set(config)
    if missing:
        raise ValueError(f"configuration is missing fields: {sorted(missing)}")
    return config


def load_registry_row(
    experiment_id: str,
    registry_path: str | Path = DEFAULT_REGISTRY_PATH,
) -> dict[str, str]:
    with Path(registry_path).open("r", encoding="utf-8", newline="") as handle:
        matches = [
            row
            for row in csv.DictReader(handle)
            if row.get("exp_id") == str(experiment_id)
        ]
    if len(matches) != 1:
        raise ValueError(
            f"experiment registry must contain exactly one row for {experiment_id}"
        )
    return matches[0]


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _write_json(path: Path, values: Mapping[str, Any]) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    with temporary.open("w", encoding="utf-8") as handle:
        json.dump(values, handle, indent=2, sort_keys=True, allow_nan=False)
        handle.write("\n")
    temporary.replace(path)


def _loss_values(losses) -> dict[str, float]:
    return {
        "total": float(losses.total.detach()),
        "forecast": float(losses.forecast.detach()),
        "state": float(losses.state.detach()),
        "prior_cross_entropy": float(losses.prior_cross_entropy.detach()),
        "transition_kl": float(losses.transition_kl.detach()),
        "transition_temporal_smoothness": float(
            losses.transition_temporal_smoothness.detach()
        ),
        "active_row_oracle_brier": float(
            losses.active_row_oracle_brier.detach()
        ),
    }


def _base_transition(stay_probability: float) -> torch.Tensor:
    stay = float(stay_probability)
    if stay <= 0.0 or stay >= 1.0:
        raise ValueError("base transition stay probability must lie between zero and one")
    switch = (1.0 - stay) / 2.0
    return torch.tensor(
        [[stay, switch, switch], [switch, stay, switch], [switch, switch, stay]],
        dtype=torch.float64,
    )


def _process_covariances(standard_deviations) -> torch.Tensor:
    deviations = torch.as_tensor(standard_deviations, dtype=torch.float64)
    if deviations.shape != (3,) or torch.any(deviations <= 0.0):
        raise ValueError("three positive process standard deviations are required")
    covariance = torch.zeros((3, 15, 15), dtype=torch.float64)
    covariance[:, 4, 4] = deviations.square()
    return covariance


def _build_estimator(config: Mapping[str, Any], model: HBV15Model):
    data = config["data"]
    return DifferentiableInteractingMultipleModel(
        models=(model, model, model),
        process_covariances=_process_covariances(
            data["process_standard_deviations_mm_day"]
        ),
        observation_variance=float(data["observation_standard_deviation"]) ** 2,
    )


def _generate_splits(config: Mapping[str, Any]) -> tuple[SyntheticBatch, ...]:
    data = config["data"]
    seeds = config["seeds"]
    split_definitions = (
        ("training", int(data["training_blocks"]), int(seeds["training_split_offset"])),
        ("validation", int(data["validation_blocks"]), int(seeds["validation_split_offset"])),
        ("test", int(data["test_blocks"]), int(seeds["test_split_offset"])),
    )
    batches = []
    for split, count, offset in split_definitions:
        specifications = make_block_seeds(
            split=split,
            count=count,
            forcing_prefix=int(seeds["forcing_prefix"]),
            process_prefix=int(seeds["process_prefix"]),
            observation_prefix=int(seeds["observation_prefix"]),
            schedule_prefix=int(seeds["schedule_prefix"]),
            split_offset=offset,
        )
        batches.append(
            generate_synthetic_batch(
                block_seeds=specifications,
                parameters=config["parameters"],
                process_standard_deviations=data[
                    "process_standard_deviations_mm_day"
                ],
                assimilation_days=int(data["assimilation_days"]),
                maximum_forecast_lead=int(data["maximum_forecast_lead"]),
                warmup_days=int(data["warmup_days"]),
                minimum_duration=int(data["minimum_regime_duration_days"]),
                maximum_duration=int(data["maximum_regime_duration_days"]),
                observation_standard_deviation=float(
                    data["observation_standard_deviation"]
                ),
                initial_covariance_fraction=float(
                    data["initial_covariance_fraction"]
                ),
            )
        )
    train, validation, test = batches
    if not train.seed_set.isdisjoint(validation.seed_set):
        raise ValueError("training and validation seeds overlap")
    if not train.seed_set.isdisjoint(test.seed_set):
        raise ValueError("training and test seeds overlap")
    if not validation.seed_set.isdisjoint(test.seed_set):
        raise ValueError("validation and test seeds overlap")
    return train, validation, test


def _first_block(batch: SyntheticBatch) -> SyntheticBatch:
    return SyntheticBatch(
        forcing=batch.forcing[:1],
        observations=batch.observations[:1],
        truth_states=batch.truth_states[:1],
        truth_discharge=batch.truth_discharge[:1],
        true_process_indices=batch.true_process_indices[:1],
        projection_adjustments=batch.projection_adjustments[:1],
        initial_states=batch.initial_states[:1],
        initial_covariances=batch.initial_covariances[:1],
        switch_days=batch.switch_days[:1],
        block_ids=batch.block_ids[:1],
        block_seeds=batch.block_seeds[:1],
        accepted_process_seeds=batch.accepted_process_seeds[:1],
        rejected_process_seeds=batch.rejected_process_seeds,
        assimilation_days=batch.assimilation_days,
    )


def _causality_audit(
    batch: SyntheticBatch,
    network: HistoryTransitionNetwork,
    estimator: DifferentiableInteractingMultipleModel,
    audit_day: int,
) -> dict[str, float | int]:
    sample = _first_block(batch)
    observations = sample.observations.detach().clone().requires_grad_(True)
    states = sample.initial_states.unsqueeze(1).expand(-1, 3, -1).clone()
    covariances = sample.initial_covariances.unsqueeze(1).expand(-1, 3, -1, -1).clone()
    probabilities = torch.full((1, 3), 1.0 / 3.0, dtype=torch.float64)
    hidden = network.initial_hidden(1, dtype=torch.float64, device=torch.device("cpu"))
    previous_forcing = torch.zeros((1, 3), dtype=torch.float64)
    previous_global_state = sample.initial_states
    selected_transition = None
    for day in range(audit_day + 1):
        features = build_history_features(
            previous_forcing, previous_global_state, probabilities
        )
        transition, hidden, _ = network(features, hidden)
        if day == audit_day:
            selected_transition = transition
            break
        update = estimator.step(
            states=states,
            covariances=covariances,
            probabilities=probabilities,
            transition_matrix=transition,
            forcing=sample.forcing[:, day],
            observation=observations[:, day],
        )
        states = update.posterior_states
        covariances = update.posterior_covariances
        probabilities = update.posterior_probabilities
        previous_forcing = sample.forcing[:, day]
        previous_global_state = update.global_posterior_states
    if selected_transition is None:
        raise RuntimeError("causality audit did not reach its selected day")
    gradient = torch.autograd.grad(
        selected_transition[:, 0, 0].sum(), observations
    )[0]
    return {
        "audit_day_zero_based": int(audit_day),
        "maximum_absolute_past_observation_gradient": float(
            gradient[:, :audit_day].abs().max()
        ),
        "maximum_absolute_current_observation_gradient": float(
            gradient[:, audit_day].abs().max()
        ),
        "maximum_absolute_future_observation_gradient": float(
            gradient[:, audit_day + 1 :].abs().max()
        ),
    }


def _git_head(project_root: Path) -> str:
    result = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        cwd=project_root,
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()


def _all_finite(values: Any) -> bool:
    if isinstance(values, Mapping):
        return all(_all_finite(value) for value in values.values())
    if isinstance(values, (list, tuple)):
        return all(_all_finite(value) for value in values)
    if isinstance(values, float):
        return math.isfinite(values)
    return True


def run_smoke(
    config: Mapping[str, Any],
    *,
    project_root: str | Path,
    result_directory_override: str | Path | None = None,
) -> Path:
    """Execute once, validate staging evidence, then atomically publish it."""
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
        raise ValueError("registry run directory does not match the configuration")
    parameter_source = (root / config["parameter_source"]["path"]).resolve()
    if _sha256(parameter_source) != str(config["parameter_source"]["sha256"]):
        raise ValueError("frozen parameter source hash does not match")

    staging = Path(
        tempfile.mkdtemp(
            prefix=f".{config['experiment_id']}.staging-",
            dir=final_directory.parent,
        )
    )
    try:
        torch.manual_seed(int(config["seeds"]["network_initialization"]))
        training_batch, validation_batch, test_batch = _generate_splits(config)
        statistics = fit_training_statistics(training_batch)
        base_transition = _base_transition(
            config["filter"]["base_transition_stay_probability"]
        )
        network = HistoryTransitionNetwork(
            base_transition=base_transition,
            feature_mean=statistics.feature_mean,
            feature_standard_deviation=statistics.feature_standard_deviation,
            hidden_size=int(config["network"]["hidden_size"]),
            maximum_logit_correction=float(
                config["network"]["maximum_logit_correction"]
            ),
        )
        model = HBV15Model(config["parameters"])
        estimator = _build_estimator(config, model)
        training = config["training"]
        leads = tuple(int(value) for value in training["forecast_leads_days"])
        training_result = train_history_transition(
            training_batch,
            validation_batch,
            network,
            estimator,
            model,
            statistics,
            forecast_leads=leads,
            epochs=int(training["epochs"]),
            batch_size=int(training["batch_size"]),
            learning_rate=float(training["learning_rate"]),
            weight_decay=float(training["weight_decay"]),
            forbidden_test_batch=test_batch,
        )

        network.eval()
        with torch.no_grad():
            trained_test_rollout = rollout_end_to_end(
                test_batch,
                network,
                estimator,
                model,
                statistics,
                forecast_leads=leads,
            )
        fixed_network = HistoryTransitionNetwork(
            base_transition=base_transition,
            feature_mean=statistics.feature_mean,
            feature_standard_deviation=statistics.feature_standard_deviation,
            hidden_size=int(config["network"]["hidden_size"]),
            maximum_logit_correction=float(
                config["network"]["maximum_logit_correction"]
            ),
        )
        fixed_network.eval()
        with torch.no_grad():
            fixed_test_rollout = rollout_end_to_end(
                test_batch,
                fixed_network,
                estimator,
                model,
                statistics,
                forecast_leads=leads,
            )
        trained_metrics = _loss_values(trained_test_rollout.losses)
        fixed_metrics = _loss_values(fixed_test_rollout.losses)
        forecast_difference = fixed_metrics["forecast"] - trained_metrics["forecast"]
        metrics = {
            "experiment_id": config["experiment_id"],
            "best_epoch": training_result.best_epoch,
            "best_validation_total_loss": training_result.best_validation_loss,
            "trained_dynamic_test": trained_metrics,
            "fixed_transition_test": fixed_metrics,
            "fixed_minus_dynamic_test_forecast_loss": forecast_difference,
            "relative_test_forecast_loss_change_dynamic_vs_fixed": (
                (trained_metrics["forecast"] - fixed_metrics["forecast"])
                / fixed_metrics["forecast"]
            ),
            "test_read_after_checkpoint_selection": True,
            "test_reads_before_selection": training_result.test_reads_before_selection,
            "diagnostic_only": True,
            "scientific_superiority_established": False,
            "accepted_process_seeds": {
                "training": list(training_batch.accepted_process_seeds),
                "validation": list(validation_batch.accepted_process_seeds),
                "test": list(test_batch.accepted_process_seeds),
            },
            "rejected_process_seeds": {
                "training": list(training_batch.rejected_process_seeds),
                "validation": list(validation_batch.rejected_process_seeds),
                "test": list(test_batch.rejected_process_seeds),
            },
            "maximum_absolute_projection_adjustment": float(
                max(
                    training_batch.projection_adjustments.abs().max(),
                    validation_batch.projection_adjustments.abs().max(),
                    test_batch.projection_adjustments.abs().max(),
                )
            ),
            "maximum_transition_row_sum_error": float(
                (
                    trained_test_rollout.transition_matrices.sum(dim=-1) - 1.0
                ).abs().max()
            ),
            "minimum_transition_probability": float(
                trained_test_rollout.transition_matrices.min()
            ),
            "maximum_absolute_transition_correction": float(
                trained_test_rollout.transition_corrections.abs().max()
            ),
        }
        forecast_gradient_maximum = max(
            row["train_forecast_gradient_maximum"]
            for row in training_result.history
        )
        gradient_audit = {
            "maximum_absolute_forecast_loss_gradient_to_network": forecast_gradient_maximum,
            **_causality_audit(
                test_batch,
                network,
                estimator,
                audit_day=min(10, test_batch.assimilation_days - 1),
            ),
        }
        if forecast_gradient_maximum <= 0.0:
            raise ValueError("forecast loss did not produce a nonzero network gradient")
        if gradient_audit["maximum_absolute_current_observation_gradient"] != 0.0:
            raise ValueError("current observation leaked into the current transition matrix")
        if metrics["maximum_absolute_projection_adjustment"] != 0.0:
            raise ValueError("synthetic truth required projection")
        if metrics["maximum_transition_row_sum_error"] > 1e-12:
            raise ValueError("a learned transition matrix is not row stochastic")
        if not _all_finite(metrics) or not _all_finite(gradient_audit):
            raise ValueError("saved metrics or gradients contain non-finite values")

        _write_json(staging / "config_snapshot.json", dict(config))
        _write_json(staging / "registry_entry.json", registry_row)
        history_path = staging / "training_history.csv"
        with history_path.open("w", encoding="utf-8", newline="") as handle:
            writer = csv.DictWriter(
                handle, fieldnames=list(training_result.history[0].keys())
            )
            writer.writeheader()
            writer.writerows(training_result.history)
        checkpoint_path = staging / "best_checkpoint.pt"
        checkpoint_temporary = checkpoint_path.with_suffix(".pt.tmp")
        torch.save(
            {
                "experiment_id": config["experiment_id"],
                "best_epoch": training_result.best_epoch,
                "network_state_dict": training_result.best_network_state,
                "training_statistics": {
                    "feature_mean": statistics.feature_mean,
                    "feature_standard_deviation": statistics.feature_standard_deviation,
                    "flow_standard_deviation": statistics.flow_standard_deviation,
                    "state_standard_deviation": statistics.state_standard_deviation,
                },
            },
            checkpoint_temporary,
        )
        checkpoint_temporary.replace(checkpoint_path)
        _write_json(staging / "metrics.json", metrics)
        _write_json(staging / "gradient_audit.json", gradient_audit)
        environment = {
            "python": sys.version,
            "platform": platform.platform(),
            "torch": torch.__version__,
            "git_head": _git_head(root),
            "process_id": os.getpid(),
        }
        _write_json(staging / "environment.json", environment)
        required = tuple(config["required_result_files"])
        missing_before_checksums = [
            name for name in required if name != "checksums.json" and not (staging / name).is_file()
        ]
        if missing_before_checksums:
            raise RuntimeError(f"staging output is incomplete: {missing_before_checksums}")
        checksums = {
            name: _sha256(staging / name)
            for name in required
            if name != "checksums.json"
        }
        _write_json(staging / "checksums.json", checksums)
        missing = [name for name in required if not (staging / name).is_file()]
        if missing:
            raise RuntimeError(f"staging output is incomplete: {missing}")
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
    config = load_config(config_path)
    project_root = Path(__file__).resolve().parents[3]
    result = run_smoke(config, project_root=project_root)
    print(result)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

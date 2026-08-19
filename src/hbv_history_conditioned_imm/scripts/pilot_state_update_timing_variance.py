"""Throwaway pilot: time the strict observation-only three-method state update.

This script exists ONLY to fill gaps 1-4 of the H18 contract draft
(docs/plans/H18_CONTRACT_DRAFT_20260814_STATE_UPDATE_THREE_METHOD.md section 8):
wall-clock per epoch, gradient finiteness, block-to-block variance of the
fifteen-state global-posterior RMSE, and memory behaviour.

Hard constraints enforced here:
  * a throwaway seed namespace that is structurally disjoint from every
    registered namespace (H16 16102-16105, H17P 16300000000);
  * no test split is generated or read at all;
  * synthetic truth NEVER enters normalization, the loss, or checkpoint
    selection - it is touched only after training, to score RMSE;
  * no gate decision, no registry row, no experiment identifier, and an output
    directory whose name does not start with "h18".

It is not a scientific run and its numbers must not be quoted as results.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import json
from pathlib import Path
import platform
import time
from typing import Mapping, Sequence

import numpy as np
import torch

from hbv_history_conditioned_imm.filter import (
    DifferentiableInteractingMultipleModel,
)
from hbv_history_conditioned_imm.hbv import STATE_COUNT, HBV15Model
from hbv_history_conditioned_imm.long_history import (
    LongHistoryParameterSwitchBatch,
    ObservableAssimilationBatch,
    generate_long_history_parameter_switch_batch,
)
from hbv_history_conditioned_imm.network import (
    FEATURE_COUNT,
    HistoryTransitionNetwork,
    StaticTransitionNetwork,
    build_history_features,
)
from hbv_history_conditioned_imm.parameter_switch import (
    PARAMETER_IDS,
    build_parameter_candidates,
)
from hbv_history_conditioned_imm.synthetic import BlockSeeds


PILOT_SEED_BASE = 18_900_000_000
STATE_NAMES = (
    "SNOWPACK",
    "MELTWATER",
    "SM",
    "SUZ",
    "SLZ",
    *(f"qraw_t_minus_{offset}" for offset in range(10)),
)

BASE_PARAMETERS = {
    "parTT": 0.4899906312144009,
    "parCFMAX": 2.5549045075022465,
    "parCFR": 0.0463012343434304,
    "parCWH": 4.790858379798471e-09,
    "parFC": 115.41144086847932,
    "parBETA": 1.0000000698913354,
    "parLP": 0.9999992059019986,
    "parK0": 0.8999999945687556,
    "parK1": 0.3593900045350728,
    "parUZL": 44.36393857438976,
    "parPERC": 9.99999952398291,
    "parK2": 0.0221122277234756,
    "lag_time": 1.7953195629813012,
}
RECESSION_COEFFICIENTS = (0.04, 0.3593900045350728, 0.8)
DURATION_HAZARD = {
    "early_age_maximum_exclusive": 30,
    "early_hazard": 0.001,
    "ramp_start_age": 30,
    "ramp_end_age": 50,
    "ramp_start_hazard": 0.01,
    "ramp_slope_per_day": 0.022,
    "late_hazard": 0.45,
}
BASE_STAY_PROBABILITY = 0.9729768340057481
PROCESS_STATE_INDEX = 4
PROCESS_STANDARD_DEVIATION = 1.0
OBSERVATION_STANDARD_DEVIATION = 0.15
WARMUP_DAYS = 90
MAXIMUM_FORECAST_LEAD = 7


def pilot_block_seeds(count: int, split_offset: int) -> tuple[BlockSeeds, ...]:
    """Build a throwaway namespace with wide, non-colliding seed families.

    The generator adds attempt * 1_000_000 to process_seed on projection
    rejection, so the process family is given a 200_000_000 window of its own.
    """

    base = PILOT_SEED_BASE + split_offset * 10_000
    return tuple(
        BlockSeeds(
            block_id=f"pilot_s{split_offset}_b{index:03d}",
            forcing_seed=base + 100_000_000 + index,
            process_seed=base + 200_000_000 + index,
            observation_seed=base + 400_000_000 + index,
            schedule_seed=base + 500_000_000 + index,
        )
        for index in range(int(count))
    )


def build_estimator(
    candidates: Mapping[str, Mapping[str, float]],
) -> DifferentiableInteractingMultipleModel:
    models = [HBV15Model(candidates[name]) for name in PARAMETER_IDS]
    process = torch.zeros(
        (len(models), STATE_COUNT, STATE_COUNT), dtype=torch.float64
    )
    process[:, PROCESS_STATE_INDEX, PROCESS_STATE_INDEX] = (
        PROCESS_STANDARD_DEVIATION**2
    )
    return DifferentiableInteractingMultipleModel(
        models,
        process,
        OBSERVATION_STANDARD_DEVIATION**2,
    )


def base_transition_matrix() -> torch.Tensor:
    stay = float(BASE_STAY_PROBABILITY)
    off = (1.0 - stay) / 2.0
    matrix = torch.full((3, 3), off, dtype=torch.float64)
    matrix.fill_diagonal_(stay)
    return matrix


class FixedTransitionNetwork(torch.nn.Module):
    """Emit one frozen matrix every day; carries no trainable parameters."""

    def __init__(self, *, base_transition: torch.Tensor) -> None:
        super().__init__()
        base = torch.as_tensor(base_transition)
        self.register_buffer("base_transition", base / base.sum(-1, keepdim=True))

    def initial_hidden(
        self, batch_size: int, *, dtype=None, device=None
    ) -> torch.Tensor:
        return torch.zeros(
            (int(batch_size), 1),
            dtype=dtype or self.base_transition.dtype,
            device=device or self.base_transition.device,
        )

    def forward(
        self, previous_features: torch.Tensor, hidden: torch.Tensor
    ) -> tuple[torch.Tensor, torch.Tensor, torch.Tensor]:
        batch = previous_features.shape[0]
        matrix = self.base_transition.expand(batch, -1, -1)
        return matrix, hidden, torch.zeros_like(matrix)


@dataclass(frozen=True)
class RolloutOutput:
    negative_log_evidence: torch.Tensor
    global_posterior_states: torch.Tensor
    posterior_probabilities: torch.Tensor
    transition_matrices: torch.Tensor
    history_features: torch.Tensor


def rollout_observation_only(
    observable: ObservableAssimilationBatch,
    network: torch.nn.Module,
    estimator: DifferentiableInteractingMultipleModel,
    *,
    feature_mean: torch.Tensor | None = None,
    feature_standard_deviation: torch.Tensor | None = None,
    collect_features: bool = False,
) -> RolloutOutput:
    """Run the full daily cycle using observable quantities only.

    No field of the synthetic truth is reachable from this function: its input
    type carries forcing, observations, and initial moments and nothing else.
    """

    days = int(observable.assimilation_days)
    batch = observable.forcing.shape[0]
    dtype = observable.forcing.dtype
    device = observable.forcing.device

    states = (
        observable.initial_states.unsqueeze(1).expand(-1, 3, -1).clone()
    )
    covariances = (
        observable.initial_covariances.unsqueeze(1).expand(-1, 3, -1, -1).clone()
    )
    probabilities = torch.full((batch, 3), 1.0 / 3.0, dtype=dtype, device=device)
    hidden = network.initial_hidden(batch, dtype=dtype, device=device)
    previous_forcing = torch.zeros((batch, 3), dtype=dtype, device=device)
    previous_global_state = observable.initial_states

    evidence: list[torch.Tensor] = []
    global_states: list[torch.Tensor] = []
    posteriors: list[torch.Tensor] = []
    transitions: list[torch.Tensor] = []
    features: list[torch.Tensor] = []

    for day in range(days):
        raw_features = build_history_features(
            previous_forcing, previous_global_state, probabilities
        )
        if collect_features:
            features.append(raw_features.detach())
        transition, hidden, _ = network(raw_features, hidden)
        update = estimator.step(
            states=states,
            covariances=covariances,
            probabilities=probabilities,
            transition_matrix=transition,
            forcing=observable.forcing[:, day],
            observation=observable.observations[:, day],
        )
        log_prior = torch.log(
            torch.clamp(
                update.prior_probabilities,
                min=torch.finfo(dtype).tiny,
            )
        )
        evidence.append(
            torch.logsumexp(log_prior + update.log_likelihoods, dim=-1)
        )
        global_states.append(update.global_posterior_states)
        posteriors.append(update.posterior_probabilities)
        transitions.append(transition)

        states = update.posterior_states
        covariances = update.posterior_covariances
        probabilities = update.posterior_probabilities
        previous_forcing = observable.forcing[:, day]
        previous_global_state = update.global_posterior_states

    return RolloutOutput(
        negative_log_evidence=-torch.stack(evidence, dim=1).mean(),
        global_posterior_states=torch.stack(global_states, dim=1),
        posterior_probabilities=torch.stack(posteriors, dim=1),
        transition_matrices=torch.stack(transitions, dim=1),
        history_features=(
            torch.stack(features, dim=1)
            if collect_features
            else torch.zeros((batch, 0, FEATURE_COUNT), dtype=dtype)
        ),
    )


def fit_observation_only_statistics(
    observable: ObservableAssimilationBatch,
    estimator: DifferentiableInteractingMultipleModel,
) -> tuple[torch.Tensor, torch.Tensor]:
    """Fit the 21-feature normalizer from a fixed-matrix causal rollout.

    This replaces the leaking normalizer at parameter_training.py:98-101, which
    fits on truth_states and one-hot true_parameter_indices.
    """

    network = FixedTransitionNetwork(base_transition=base_transition_matrix())
    with torch.no_grad():
        output = rollout_observation_only(
            observable, network, estimator, collect_features=True
        )
    flat = output.history_features.reshape(-1, FEATURE_COUNT)
    mean = flat.mean(dim=0)
    standard_deviation = torch.clamp(flat.std(dim=0, unbiased=False), min=1e-6)
    return mean, standard_deviation


def normalized_state_rmse_per_block(
    estimate: torch.Tensor,
    truth: torch.Tensor,
    scales: torch.Tensor,
    keep: torch.Tensor,
) -> np.ndarray:
    """Per-block RMSE over days and retained states, each state pre-scaled."""

    error = (estimate - truth) / scales
    squared = error.square()[:, :, keep]
    return np.sqrt(
        squared.mean(dim=(1, 2)).detach().cpu().numpy().astype(np.float64)
    )


def train_arm(
    name: str,
    network: torch.nn.Module,
    estimator: DifferentiableInteractingMultipleModel,
    training: ObservableAssimilationBatch,
    validation: ObservableAssimilationBatch,
    *,
    epochs: int,
    minibatch: int,
    learning_rate: float,
    weight_decay: float,
) -> dict[str, object]:
    optimizer = torch.optim.AdamW(
        network.parameters(), lr=learning_rate, weight_decay=weight_decay
    )
    blocks = training.forcing.shape[0]
    history: list[dict[str, float]] = []
    non_finite_gradient_steps = 0
    maximum_gradient = 0.0
    best_validation = float("inf")
    best_epoch = 0

    for epoch in range(1, int(epochs) + 1):
        network.train()
        started = time.perf_counter()
        running = 0.0
        for start in range(0, blocks, int(minibatch)):
            stop = min(start + int(minibatch), blocks)
            index = torch.arange(start, stop)
            subset = ObservableAssimilationBatch(
                forcing=training.forcing[index],
                observations=training.observations[index],
                initial_states=training.initial_states[index],
                initial_covariances=training.initial_covariances[index],
                assimilation_days=training.assimilation_days,
            )
            optimizer.zero_grad(set_to_none=True)
            output = rollout_observation_only(subset, network, estimator)
            output.negative_log_evidence.backward()
            for parameter in network.parameters():
                if parameter.grad is None:
                    continue
                if not torch.isfinite(parameter.grad).all():
                    non_finite_gradient_steps += 1
                    break
                maximum_gradient = max(
                    maximum_gradient, float(parameter.grad.abs().max())
                )
            torch.nn.utils.clip_grad_norm_(network.parameters(), max_norm=1.0)
            optimizer.step()
            running += float(output.negative_log_evidence.detach()) * (stop - start)
        train_seconds = time.perf_counter() - started

        network.eval()
        validation_started = time.perf_counter()
        with torch.no_grad():
            validation_output = rollout_observation_only(
                validation, network, estimator
            )
        validation_loss = float(validation_output.negative_log_evidence)
        validation_seconds = time.perf_counter() - validation_started

        history.append(
            {
                "epoch": float(epoch),
                "train_negative_log_evidence": running / blocks,
                "validation_negative_log_evidence": validation_loss,
                "train_seconds": train_seconds,
                "validation_seconds": validation_seconds,
            }
        )
        if validation_loss < best_validation:
            best_validation = validation_loss
            best_epoch = epoch
        print(
            f"  [{name}] epoch {epoch}/{epochs} "
            f"train={running / blocks:.6f} val={validation_loss:.6f} "
            f"{train_seconds:.1f}s+{validation_seconds:.1f}s",
            flush=True,
        )

    return {
        "history": history,
        "best_epoch": best_epoch,
        "best_validation_negative_log_evidence": best_validation,
        "non_finite_gradient_steps": non_finite_gradient_steps,
        "maximum_absolute_gradient": maximum_gradient,
        "trainable_parameter_count": sum(
            int(parameter.numel()) for parameter in network.parameters()
        ),
        "mean_train_seconds_per_epoch": float(
            np.mean([row["train_seconds"] for row in history])
        ),
    }


def paired_bootstrap(
    difference: np.ndarray, *, draws: int, seed: int
) -> dict[str, float]:
    generator = np.random.default_rng(int(seed))
    count = difference.size
    samples = generator.integers(0, count, size=(int(draws), count))
    means = difference[samples].mean(axis=1)
    return {
        "point_estimate": float(difference.mean()),
        "block_standard_deviation": float(difference.std(ddof=1)),
        "lower_95": float(np.quantile(means, 0.025)),
        "upper_95": float(np.quantile(means, 0.975)),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--training-blocks", type=int, default=8)
    parser.add_argument("--validation-blocks", type=int, default=4)
    parser.add_argument("--assimilation-days", type=int, default=300)
    parser.add_argument("--epochs", type=int, default=3)
    parser.add_argument("--minibatch", type=int, default=4)
    parser.add_argument("--learning-rate", type=float, default=3e-3)
    parser.add_argument("--weight-decay", type=float, default=1e-4)
    parser.add_argument("--bootstrap-draws", type=int, default=20000)
    parser.add_argument("--threads", type=int, default=0)
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path(
            "results/23_hbv_multilead_joint_uncertainty/"
            "pilot_state_update_timing_variance_throwaway_v01"
        ),
    )
    arguments = parser.parse_args()
    if arguments.threads > 0:
        torch.set_num_threads(int(arguments.threads))
    torch.manual_seed(1710101)

    candidates = build_parameter_candidates(BASE_PARAMETERS, RECESSION_COEFFICIENTS)
    estimator = build_estimator(candidates)

    print("generating pilot truth (throwaway namespace)...", flush=True)
    generation_started = time.perf_counter()
    splits: dict[str, LongHistoryParameterSwitchBatch] = {}
    for offset, (label, count) in enumerate(
        (("train", arguments.training_blocks), ("validation", arguments.validation_blocks))
    ):
        splits[label] = generate_long_history_parameter_switch_batch(
            block_seeds=pilot_block_seeds(count, offset),
            parameter_candidates=candidates,
            warmup_parameter_id="calibrated_recession",
            assimilation_days=int(arguments.assimilation_days),
            maximum_forecast_lead=MAXIMUM_FORECAST_LEAD,
            warmup_days=WARMUP_DAYS,
            hazard=DURATION_HAZARD,
            process_standard_deviation=PROCESS_STANDARD_DEVIATION,
            observation_standard_deviation=OBSERVATION_STANDARD_DEVIATION,
            process_state_index=PROCESS_STATE_INDEX,
            require_zero_projection=True,
        )
    generation_seconds = time.perf_counter() - generation_started
    print(f"  generation took {generation_seconds:.1f}s", flush=True)

    training_observable = splits["train"].as_observable()
    validation_observable = splits["validation"].as_observable()

    switch_counts = {
        label: int(batch.switch_event_mask[:, : arguments.assimilation_days].sum())
        for label, batch in splits.items()
    }
    print(f"  switch events: {switch_counts}", flush=True)

    print("fitting observation-only normalizer (fixed matrix rollout)...", flush=True)
    normalizer_started = time.perf_counter()
    feature_mean, feature_standard_deviation = fit_observation_only_statistics(
        training_observable, estimator
    )
    normalizer_seconds = time.perf_counter() - normalizer_started
    print(f"  one no-grad rollout over training blocks: {normalizer_seconds:.1f}s", flush=True)

    arms: dict[str, object] = {}
    networks: dict[str, torch.nn.Module] = {
        "fixed": FixedTransitionNetwork(base_transition=base_transition_matrix()),
        "static": StaticTransitionNetwork(base_transition=base_transition_matrix()),
        "history": HistoryTransitionNetwork(
            base_transition=base_transition_matrix(),
            feature_mean=feature_mean,
            feature_standard_deviation=feature_standard_deviation,
        ),
    }
    for name in ("static", "history"):
        print(f"training {name}...", flush=True)
        arms[name] = train_arm(
            name,
            networks[name],
            estimator,
            training_observable,
            validation_observable,
            epochs=int(arguments.epochs),
            minibatch=int(arguments.minibatch),
            learning_rate=float(arguments.learning_rate),
            weight_decay=float(arguments.weight_decay),
        )

    # ---- truth is touched for the first time below, for scoring only ----
    print("scoring fifteen-state global posterior on validation...", flush=True)
    truth = splits["validation"].truth_states[:, : arguments.assimilation_days]
    scales = truth.std(dim=(0, 1), unbiased=False)
    keep = scales > 1e-8
    degenerate = [
        STATE_NAMES[index]
        for index in range(STATE_COUNT)
        if not bool(keep[index])
    ]
    safe_scales = torch.where(keep, scales, torch.ones_like(scales))

    per_block: dict[str, np.ndarray] = {}
    for name, network in networks.items():
        network.eval()
        with torch.no_grad():
            output = rollout_observation_only(
                validation_observable, network, estimator
            )
        per_block[name] = normalized_state_rmse_per_block(
            output.global_posterior_states, truth, safe_scales, keep
        )

    contrasts = {
        "static_minus_history": paired_bootstrap(
            per_block["static"] - per_block["history"],
            draws=int(arguments.bootstrap_draws),
            seed=20260814,
        ),
        "fixed_minus_static": paired_bootstrap(
            per_block["fixed"] - per_block["static"],
            draws=int(arguments.bootstrap_draws),
            seed=20260815,
        ),
        "fixed_minus_history": paired_bootstrap(
            per_block["fixed"] - per_block["history"],
            draws=int(arguments.bootstrap_draws),
            seed=20260816,
        ),
    }

    report = {
        "artifact_role": "throwaway_pilot_for_h18_contract_gaps_1_to_4",
        "publication_ready": False,
        "gate_decisions_made": 0,
        "experiment_identifier_consumed": None,
        "registry_row_written": False,
        "test_split_generated": False,
        "test_split_reads": 0,
        "truth_used_in_training": False,
        "truth_used_for": "post-training RMSE scoring only",
        "seed_namespace_base": PILOT_SEED_BASE,
        "configuration": {
            "training_blocks": int(arguments.training_blocks),
            "validation_blocks": int(arguments.validation_blocks),
            "assimilation_days": int(arguments.assimilation_days),
            "epochs": int(arguments.epochs),
            "minibatch": int(arguments.minibatch),
            "learning_rate": float(arguments.learning_rate),
            "weight_decay": float(arguments.weight_decay),
            "loss": "one-step observation negative log evidence only",
            "multi_lead_forecast_loss_weight": 0.0,
            "transition_regularizer_weights": 0.0,
        },
        "environment": {
            "python": platform.python_version(),
            "torch": torch.__version__,
            "numpy": np.__version__,
            "threads": int(torch.get_num_threads()),
            "device": "cpu",
        },
        "timing_seconds": {
            "truth_generation": generation_seconds,
            "observation_only_normalizer_rollout": normalizer_seconds,
        },
        "switch_events_in_assimilation_window": switch_counts,
        "arms": arms,
        "state_scoring": {
            "normalization": "each state divided by its validation truth std",
            "degenerate_zero_variance_states": degenerate,
            "scored_state_count": int(keep.sum()),
            "per_block_rmse": {
                name: values.tolist() for name, values in per_block.items()
            },
            "mean_rmse": {
                name: float(values.mean()) for name, values in per_block.items()
            },
        },
        "paired_block_contrasts": contrasts,
        "claim_boundary": (
            "Timing, gradient finiteness, and block-level variance only. The "
            "networks are trained for a few epochs on a tiny throwaway sample; "
            "no contrast here is evidence for or against any method."
        ),
    }

    output_dir = Path(arguments.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    (output_dir / "pilot_report.json").write_text(
        json.dumps(report, indent=2, sort_keys=True), encoding="utf-8"
    )
    np.savez(
        output_dir / "pilot_per_block_rmse.npz",
        **{name: values for name, values in per_block.items()},
    )
    print(json.dumps(report["paired_block_contrasts"], indent=2))
    print(f"wrote {output_dir / 'pilot_report.json'}")


if __name__ == "__main__":
    main()

"""Throwaway pilot: a real end-to-end run of the three-method contest.

Strict observation-only training (one-step observation negative log evidence),
validation-selected checkpoints, then scoring on a large held-out evaluation
split that is never touched during training or selection.

Arms scored: fixed, static (trained), history (trained), oracle_hazard (the
true generative matrix, i.e. the ceiling a learned rule could ever reach).

Endpoints scored on the evaluation split:
  * fifteen-state global-posterior normalized RMSE (per block)
  * posterior mode accuracy
  * active-source-row Brier against the known true row
  * switch-hazard mean absolute error

Still a development diagnostic: throwaway seed namespace, no gate decisions,
no experiment identifier, no registry row.  It does NOT consume H18 data.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
from pathlib import Path
import sys
import time

import numpy as np
import torch

from hbv_history_conditioned_imm.hbv import STATE_COUNT
from hbv_history_conditioned_imm.long_history import (
    ObservableAssimilationBatch,
    generate_long_history_parameter_switch_batch,
)
from hbv_history_conditioned_imm.network import (
    HistoryTransitionNetwork,
    StaticTransitionNetwork,
)
from hbv_history_conditioned_imm.parameter_switch import build_parameter_candidates


_TIMING = Path(__file__).with_name("pilot_state_update_timing_variance.py")
_CEILING = Path(__file__).with_name("pilot_state_update_oracle_ceiling.py")


def _load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


_pilot = _load(_TIMING, "_pilot_timing")
_ceiling = _load(_CEILING, "_pilot_ceiling")


class PrecomputedTransitionNetwork(torch.nn.Module):
    """Emit a stored per-day matrix; the hidden state carries the day index."""

    def __init__(self, matrices: torch.Tensor) -> None:
        super().__init__()
        self.register_buffer("matrices", matrices)

    def initial_hidden(self, batch_size: int, *, dtype=None, device=None):
        return torch.zeros(
            (int(batch_size), 1),
            dtype=dtype or self.matrices.dtype,
            device=device or self.matrices.device,
        )

    def forward(self, previous_features: torch.Tensor, hidden: torch.Tensor):
        day = int(hidden[0, 0].item())
        matrix = self.matrices[:, day]
        return matrix, hidden + 1.0, torch.zeros_like(matrix)


def probability_scores(
    transition_matrices: torch.Tensor, batch, days: int
) -> tuple[np.ndarray, np.ndarray]:
    """Per-block active-source-row Brier and switch-hazard absolute error."""

    sources = batch.active_source_indices[:, :days]
    mask = batch.transition_evaluation_mask[:, :days]
    truth_rows = batch.oracle_active_row_probabilities[:, :days]
    safe = torch.clamp(sources, min=0)
    index = safe.reshape(*safe.shape, 1, 1).expand(-1, -1, 1, 3)
    predicted_rows = torch.gather(transition_matrices, 2, index).squeeze(2)

    brier = (predicted_rows - truth_rows).square().sum(dim=-1)
    true_stay = torch.gather(truth_rows, 2, safe.unsqueeze(-1)).squeeze(-1)
    predicted_stay = torch.gather(predicted_rows, 2, safe.unsqueeze(-1)).squeeze(-1)
    hazard_error = ((1.0 - predicted_stay) - (1.0 - true_stay)).abs()

    weights = mask.to(dtype=brier.dtype)
    total = weights.sum(dim=1)
    return (
        ((brier * weights).sum(dim=1) / total).cpu().numpy().astype(np.float64),
        ((hazard_error * weights).sum(dim=1) / total).cpu().numpy().astype(np.float64),
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--training-blocks", type=int, default=48)
    parser.add_argument("--validation-blocks", type=int, default=24)
    parser.add_argument("--evaluation-blocks", type=int, default=120)
    parser.add_argument("--assimilation-days", type=int, default=300)
    parser.add_argument("--epochs", type=int, default=40)
    parser.add_argument("--minibatch", type=int, default=16)
    parser.add_argument("--learning-rate", type=float, default=3e-3)
    parser.add_argument("--weight-decay", type=float, default=1e-4)
    parser.add_argument("--bootstrap-draws", type=int, default=20000)
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path(
            "results/23_hbv_multilead_joint_uncertainty/"
            "pilot_state_update_end_to_end_throwaway_v01"
        ),
    )
    arguments = parser.parse_args()
    days = int(arguments.assimilation_days)
    torch.manual_seed(1710101)

    candidates = build_parameter_candidates(
        _pilot.BASE_PARAMETERS, _pilot.RECESSION_COEFFICIENTS
    )
    estimator = _pilot.build_estimator(candidates)

    def generate(count: int, offset: int):
        return generate_long_history_parameter_switch_batch(
            block_seeds=_pilot.pilot_block_seeds(count, offset),
            parameter_candidates=candidates,
            warmup_parameter_id="calibrated_recession",
            assimilation_days=days,
            maximum_forecast_lead=_pilot.MAXIMUM_FORECAST_LEAD,
            warmup_days=_pilot.WARMUP_DAYS,
            hazard=_pilot.DURATION_HAZARD,
            process_standard_deviation=_pilot.PROCESS_STANDARD_DEVIATION,
            observation_standard_deviation=_pilot.OBSERVATION_STANDARD_DEVIATION,
            process_state_index=_pilot.PROCESS_STATE_INDEX,
            require_zero_projection=True,
        )

    def trim(batch) -> ObservableAssimilationBatch:
        full = batch.as_observable()
        return ObservableAssimilationBatch(
            forcing=full.forcing[:, :days],
            observations=full.observations[:, :days],
            initial_states=full.initial_states,
            initial_covariances=full.initial_covariances,
            assimilation_days=days,
        )

    print("generating throwaway splits...", flush=True)
    started = time.perf_counter()
    training = generate(int(arguments.training_blocks), 0)
    validation = generate(int(arguments.validation_blocks), 1)
    evaluation = generate(int(arguments.evaluation_blocks), 2)
    generation_seconds = time.perf_counter() - started
    training_observable = trim(training)
    validation_observable = trim(validation)
    evaluation_observable = trim(evaluation)
    switch_counts = {
        "train": int(training.switch_event_mask[:, :days].sum()),
        "validation": int(validation.switch_event_mask[:, :days].sum()),
        "evaluation": int(evaluation.switch_event_mask[:, :days].sum()),
    }
    print(f"  {generation_seconds:.1f}s, switch events {switch_counts}", flush=True)

    feature_mean, feature_standard_deviation = _pilot.fit_observation_only_statistics(
        training_observable, estimator
    )

    networks: dict[str, torch.nn.Module] = {
        "fixed": _pilot.FixedTransitionNetwork(
            base_transition=_pilot.base_transition_matrix()
        ),
        "static": StaticTransitionNetwork(
            base_transition=_pilot.base_transition_matrix()
        ),
        "history": HistoryTransitionNetwork(
            base_transition=_pilot.base_transition_matrix(),
            feature_mean=feature_mean,
            feature_standard_deviation=feature_standard_deviation,
        ),
    }

    arms: dict[str, object] = {}
    for name in ("static", "history"):
        print(f"training {name}...", flush=True)
        arms[name] = _pilot.train_arm(
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

    print("scoring on the held-out evaluation split...", flush=True)
    truth = evaluation.truth_states[:, :days]
    scales = truth.std(dim=(0, 1), unbiased=False)
    keep = scales > 1e-8
    safe_scales = torch.where(keep, scales, torch.ones_like(scales))
    true_modes = evaluation.true_parameter_indices[:, :days]

    networks["oracle_hazard"] = PrecomputedTransitionNetwork(
        _ceiling.oracle_hazard_matrices(evaluation, days)
    )

    per_block_rmse: dict[str, np.ndarray] = {}
    per_block_brier: dict[str, np.ndarray] = {}
    per_block_hazard: dict[str, np.ndarray] = {}
    summary: dict[str, dict[str, float]] = {}
    for name, network in networks.items():
        network.eval()
        with torch.no_grad():
            output = _pilot.rollout_observation_only(
                evaluation_observable, network, estimator
            )
        per_block_rmse[name] = _pilot.normalized_state_rmse_per_block(
            output.global_posterior_states, truth, safe_scales, keep
        )
        brier, hazard = probability_scores(output.transition_matrices, evaluation, days)
        per_block_brier[name] = brier
        per_block_hazard[name] = hazard
        summary[name] = {
            "mean_state_rmse": float(per_block_rmse[name].mean()),
            "mean_active_row_brier": float(brier.mean()),
            "mean_switch_hazard_absolute_error": float(hazard.mean()),
            "posterior_mode_accuracy": float(
                (output.posterior_probabilities.argmax(dim=-1) == true_modes)
                .to(dtype=torch.float64)
                .mean()
            ),
        }
        print(
            f"  {name:16s} rmse={summary[name]['mean_state_rmse']:.7f} "
            f"brier={summary[name]['mean_active_row_brier']:.3e} "
            f"hazard_mae={summary[name]['mean_switch_hazard_absolute_error']:.5f} "
            f"mode_acc={summary[name]['posterior_mode_accuracy']:.4f}",
            flush=True,
        )

    def contrast(better: str, worse: str, values: dict[str, np.ndarray], seed: int):
        return _pilot.paired_bootstrap(
            values[worse] - values[better],
            draws=int(arguments.bootstrap_draws),
            seed=seed,
        )

    ceiling = float(
        per_block_rmse["fixed"].mean() - per_block_rmse["oracle_hazard"].mean()
    )
    achieved = float(
        per_block_rmse["static"].mean() - per_block_rmse["history"].mean()
    )
    contrasts = {
        "state_rmse": {
            "history_versus_static": contrast(
                "history", "static", per_block_rmse, 20260901
            ),
            "history_versus_fixed": contrast(
                "history", "fixed", per_block_rmse, 20260902
            ),
            "static_versus_fixed": contrast(
                "static", "fixed", per_block_rmse, 20260903
            ),
            "oracle_hazard_versus_fixed": contrast(
                "oracle_hazard", "fixed", per_block_rmse, 20260904
            ),
        },
        "active_row_brier": {
            "history_versus_static": contrast(
                "history", "static", per_block_brier, 20260905
            ),
            "history_versus_fixed": contrast(
                "history", "fixed", per_block_brier, 20260906
            ),
        },
        "switch_hazard_absolute_error": {
            "history_versus_static": contrast(
                "history", "static", per_block_hazard, 20260907
            ),
            "history_versus_fixed": contrast(
                "history", "fixed", per_block_hazard, 20260908
            ),
        },
    }

    report = {
        "artifact_role": "throwaway_end_to_end_development_diagnostic",
        "publication_ready": False,
        "gate_decisions_made": 0,
        "experiment_identifier_consumed": None,
        "registry_row_written": False,
        "h18_data_consumed": False,
        "seed_namespace_base": _pilot.PILOT_SEED_BASE,
        "configuration": {
            "training_blocks": int(arguments.training_blocks),
            "validation_blocks": int(arguments.validation_blocks),
            "evaluation_blocks": int(arguments.evaluation_blocks),
            "assimilation_days": days,
            "epochs": int(arguments.epochs),
            "minibatch": int(arguments.minibatch),
            "learning_rate": float(arguments.learning_rate),
            "weight_decay": float(arguments.weight_decay),
            "loss": "one-step observation negative log evidence only",
            "truth_in_training": False,
            "checkpoint_selection": "best validation negative log evidence",
        },
        "switch_events": switch_counts,
        "generation_seconds": generation_seconds,
        "degenerate_zero_variance_states": [
            _pilot.STATE_NAMES[index]
            for index in range(STATE_COUNT)
            if not bool(keep[index])
        ],
        "training": arms,
        "evaluation_summary": summary,
        "ceiling_analysis": {
            "state_rmse_ceiling_fixed_minus_oracle_hazard": ceiling,
            "state_rmse_achieved_static_minus_history": achieved,
            "fraction_of_ceiling_captured": (
                achieved / ceiling if ceiling != 0.0 else None
            ),
        },
        "paired_block_contrasts": contrasts,
        "per_block": {
            "state_rmse": {k: v.tolist() for k, v in per_block_rmse.items()},
            "active_row_brier": {k: v.tolist() for k, v in per_block_brier.items()},
            "switch_hazard_absolute_error": {
                k: v.tolist() for k, v in per_block_hazard.items()
            },
        },
        "claim_boundary": (
            "Development diagnostic on a throwaway synthetic namespace with one "
            "initialization seed per learned arm. Not a preregistered result and "
            "not evidence for or against any H18 hypothesis."
        ),
    }

    output_dir = Path(arguments.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    (output_dir / "end_to_end_report.json").write_text(
        json.dumps(report, indent=2, sort_keys=True), encoding="utf-8"
    )
    print(json.dumps(report["ceiling_analysis"], indent=2))
    print(json.dumps(contrasts["state_rmse"], indent=2))
    print(f"wrote {output_dir / 'end_to_end_report.json'}")


if __name__ == "__main__":
    main()

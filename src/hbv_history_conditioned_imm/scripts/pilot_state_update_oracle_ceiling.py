"""Throwaway pilot: measure the ORACLE CEILING of the state-update endpoint.

Question: on this synthetic design, how much can ANY transition-matrix rule
improve the fifteen-state global posterior?  If even a perfectly-informed
oracle cannot beat the fixed matrix, the H18 state main endpoint is dead on
arrival and no amount of compute will rescue it.

Four evaluation-only arms, identical filter / data / observations:
  * fixed              - the frozen base matrix every day (reference)
  * oracle_hazard      - the TRUE generative matrix every day (perfect knowledge
                         of the duration-hazard law; still probabilistic).  This
                         is the best a learned transition rule could ever be.
  * oracle_attribution - every row places 1-eps on the TRUE mode of day t
                         (perfect attribution).  Collapses the mixture onto the
                         correct candidate, so it is numerically equivalent to
                         running one filter with the true parameter each day.
                         This is the absolute physical ceiling.
  * uniform            - a maximally uninformative matrix (1/3 everywhere), the
                         opposite extreme, to bracket the achievable range.

No training, no optimizer, no checkpoint, no gate decision, no registry row,
no experiment identifier.  Reuses the same throwaway seed namespace as
pilot_state_update_timing_variance.py.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import time

import numpy as np
import torch

from hbv_history_conditioned_imm.hbv import STATE_COUNT
from hbv_history_conditioned_imm.long_history import (
    ObservableAssimilationBatch,
    generate_long_history_parameter_switch_batch,
)
from hbv_history_conditioned_imm.parameter_switch import build_parameter_candidates
from hbv_history_conditioned_imm.state_trajectory import (
    rollout_filter_state_trajectory,
)

import importlib.util
import sys

_TIMING = Path(__file__).with_name("pilot_state_update_timing_variance.py")
_spec = importlib.util.spec_from_file_location("_pilot_timing", _TIMING)
_pilot = importlib.util.module_from_spec(_spec)
sys.modules["_pilot_timing"] = _pilot
_spec.loader.exec_module(_pilot)


ATTRIBUTION_EPSILON = 1e-6


def oracle_hazard_matrices(batch, days: int) -> torch.Tensor:
    """Rebuild the exact generative matrix: stay 1-h, each other mode h/2."""

    rows = batch.oracle_active_row_probabilities[:, :days]
    sources = batch.active_source_indices[:, :days]
    evaluated = batch.transition_evaluation_mask[:, :days]
    blocks = rows.shape[0]

    stay = torch.gather(rows, 2, torch.clamp(sources, min=0).unsqueeze(-1)).squeeze(-1)
    hazard = 1.0 - stay
    base = _pilot.base_transition_matrix()
    hazard = torch.where(
        evaluated, hazard, torch.full_like(hazard, 1.0 - float(base[0, 0]))
    )

    identity = torch.eye(3, dtype=rows.dtype).reshape(1, 1, 3, 3)
    off = (hazard / 2.0).reshape(blocks, days, 1, 1)
    matrix = identity * (1.0 - hazard).reshape(blocks, days, 1, 1) + (
        1.0 - identity
    ) * off
    return matrix / matrix.sum(dim=-1, keepdim=True)


def oracle_attribution_matrices(batch, days: int) -> torch.Tensor:
    """Every row concentrates on the true mode of day t (perfect attribution)."""

    modes = batch.true_parameter_indices[:, :days]
    blocks = modes.shape[0]
    matrix = torch.full(
        (blocks, days, 3, 3),
        ATTRIBUTION_EPSILON / 2.0,
        dtype=batch.forcing.dtype,
    )
    index = modes.reshape(blocks, days, 1, 1).expand(-1, -1, 3, 1)
    matrix.scatter_(3, index, 1.0 - ATTRIBUTION_EPSILON)
    return matrix / matrix.sum(dim=-1, keepdim=True)


def constant_matrices(matrix: torch.Tensor, blocks: int, days: int) -> torch.Tensor:
    normalized = matrix / matrix.sum(dim=-1, keepdim=True)
    return normalized.reshape(1, 1, 3, 3).expand(blocks, days, -1, -1).contiguous()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--blocks", type=int, default=12)
    parser.add_argument("--assimilation-days", type=int, default=300)
    parser.add_argument("--bootstrap-draws", type=int, default=20000)
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path(
            "results/23_hbv_multilead_joint_uncertainty/"
            "pilot_state_update_timing_variance_throwaway_v01"
        ),
    )
    arguments = parser.parse_args()
    days = int(arguments.assimilation_days)

    candidates = build_parameter_candidates(
        _pilot.BASE_PARAMETERS, _pilot.RECESSION_COEFFICIENTS
    )
    estimator = _pilot.build_estimator(candidates)

    print("regenerating the pilot validation split (same throwaway seeds)...", flush=True)
    batch = generate_long_history_parameter_switch_batch(
        block_seeds=_pilot.pilot_block_seeds(int(arguments.blocks), 1),
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
    full = batch.as_observable()
    observable = ObservableAssimilationBatch(
        forcing=full.forcing[:, :days],
        observations=full.observations[:, :days],
        initial_states=full.initial_states,
        initial_covariances=full.initial_covariances,
        assimilation_days=days,
    )
    blocks = observable.forcing.shape[0]

    uniform = torch.full((3, 3), 1.0 / 3.0, dtype=torch.float64)
    arms = {
        "fixed": constant_matrices(_pilot.base_transition_matrix(), blocks, days),
        "uniform": constant_matrices(uniform, blocks, days),
        "oracle_hazard": oracle_hazard_matrices(batch, days),
        "oracle_attribution": oracle_attribution_matrices(batch, days),
    }

    truth = batch.truth_states[:, :days]
    scales = truth.std(dim=(0, 1), unbiased=False)
    keep = scales > 1e-8
    safe_scales = torch.where(keep, scales, torch.ones_like(scales))
    store_keep = keep.clone()
    store_keep[5:] = False
    routing_keep = keep.clone()
    routing_keep[:5] = False

    true_modes = batch.true_parameter_indices[:, :days]
    per_block: dict[str, np.ndarray] = {}
    summary: dict[str, dict[str, float]] = {}
    for name, matrices in arms.items():
        started = time.perf_counter()
        trajectory = rollout_filter_state_trajectory(
            observable, matrices, estimator, candidate_parameters=candidates
        )
        estimate = trajectory.global_posterior_states
        per_block[name] = _pilot.normalized_state_rmse_per_block(
            estimate, truth, safe_scales, keep
        )
        summary[name] = {
            "mean_rmse_all_scored_states": float(per_block[name].mean()),
            "mean_rmse_stores_only": float(
                _pilot.normalized_state_rmse_per_block(
                    estimate, truth, safe_scales, store_keep
                ).mean()
            ),
            "mean_rmse_routing_only": float(
                _pilot.normalized_state_rmse_per_block(
                    estimate, truth, safe_scales, routing_keep
                ).mean()
            ),
            "posterior_mode_accuracy": float(
                (
                    trajectory.posterior_mode_probabilities.argmax(dim=-1)
                    == true_modes
                )
                .to(dtype=torch.float64)
                .mean()
            ),
            "seconds": time.perf_counter() - started,
        }
        print(
            f"  {name:20s} rmse={summary[name]['mean_rmse_all_scored_states']:.7f} "
            f"mode_acc={summary[name]['posterior_mode_accuracy']:.4f} "
            f"({summary[name]['seconds']:.1f}s)",
            flush=True,
        )

    reference = per_block["fixed"]
    contrasts = {}
    for name in ("uniform", "oracle_hazard", "oracle_attribution"):
        statistics = _pilot.paired_bootstrap(
            reference - per_block[name],
            draws=int(arguments.bootstrap_draws),
            seed=20260817,
        )
        statistics["relative_to_fixed_mean_rmse"] = float(
            statistics["point_estimate"] / reference.mean()
        )
        contrasts[f"fixed_minus_{name}"] = statistics

    report = {
        "artifact_role": "throwaway_pilot_oracle_ceiling_for_h18_state_endpoint",
        "publication_ready": False,
        "gate_decisions_made": 0,
        "experiment_identifier_consumed": None,
        "registry_row_written": False,
        "training_performed": False,
        "optimizer_created": False,
        "seed_namespace_base": _pilot.PILOT_SEED_BASE,
        "configuration": {
            "blocks": blocks,
            "assimilation_days": days,
            "attribution_epsilon": ATTRIBUTION_EPSILON,
            "split_reused": "the pilot validation split (offset 1)",
        },
        "arm_definitions": {
            "fixed": "frozen base matrix, the reference",
            "uniform": "one third everywhere, maximally uninformative",
            "oracle_hazard": "the exact generative matrix from the true regime age",
            "oracle_attribution": (
                "every row concentrates on the true mode of day t; numerically "
                "equivalent to running one filter with the true parameter daily"
            ),
        },
        "degenerate_zero_variance_states": [
            _pilot.STATE_NAMES[index]
            for index in range(STATE_COUNT)
            if not bool(keep[index])
        ],
        "scored_state_count": int(keep.sum()),
        "arm_summary": summary,
        "per_block_rmse": {name: values.tolist() for name, values in per_block.items()},
        "paired_block_contrasts_versus_fixed": contrasts,
        "claim_boundary": (
            "Evaluation-only ceiling probe on one throwaway synthetic split. It "
            "bounds what any transition-matrix rule could achieve here; it is not "
            "evidence about any trained method."
        ),
    }

    output_dir = Path(arguments.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    (output_dir / "oracle_ceiling_report.json").write_text(
        json.dumps(report, indent=2, sort_keys=True), encoding="utf-8"
    )
    print(json.dumps(contrasts, indent=2))
    print(f"wrote {output_dir / 'oracle_ceiling_report.json'}")


if __name__ == "__main__":
    main()

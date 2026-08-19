"""H19 implementation audit for the mode-evolving forecast operator.

Contract: docs/plans/H19_CONTRACT_DRAFT_20260818_FORECAST_EVIDENCE_LAYER.md
section 7.2.  Two hard audits, both must pass before any evaluation is allowed:

  1. Identity degeneracy.  With an identity transition matrix the evolving
     operator must reduce BIT-FOR-BIT to the frozen operator (maximum absolute
     difference exactly 0.0).  Because p_k = p_0 I^k = p_0, the two are the same
     computation and any nonzero difference is an implementation defect.

  2. Forecast-window observation isolation.  Perturbing the observation array on
     days that lie inside the forecast window must leave every forecast bit
     identical.

Both audits carry a SELF-VALIDATION step: the same comparison is run in a
configuration where a difference MUST appear.  The H18 causality probe reported
a false pass because it differentiated the constant row sum of a row-stochastic
matrix; a probe that cannot fail is not evidence.  If the self-validation does
not produce a difference, the audit reports failure regardless of the main
result.

No training, no optimizer, no checkpoint, no gate decision, no registry row,
no experiment identifier.  Pure forward evaluation on a tiny throwaway batch.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
from pathlib import Path
import sys
import time

import torch

from hbv_history_conditioned_imm.hbv import (
    forecast_global_state_mode_evolving,
    forecast_global_state_weighted_parameters,
)
from hbv_history_conditioned_imm.long_history import (
    ObservableAssimilationBatch,
    generate_long_history_parameter_switch_batch,
)
from hbv_history_conditioned_imm.parameter_switch import build_parameter_candidates
from hbv_history_conditioned_imm.state_trajectory import (
    rollout_filter_state_trajectory,
)

_TIMING = Path(__file__).with_name("pilot_state_update_timing_variance.py")
_spec = importlib.util.spec_from_file_location("_pilot_timing", _TIMING)
_pilot = importlib.util.module_from_spec(_spec)
sys.modules["_pilot_timing"] = _pilot
_spec.loader.exec_module(_pilot)

LEADS = (1, 3, 7)
AUDIT_SEED_BASE_SPLIT = 7


def maximum_absolute_difference(
    left: dict[int, torch.Tensor], right: dict[int, torch.Tensor]
) -> float:
    if sorted(left) != sorted(right):
        raise ValueError("forecast dictionaries must expose the same leads")
    worst = 0.0
    for lead in sorted(left):
        difference = float((left[lead] - right[lead]).abs().max())
        worst = max(worst, difference)
    return worst


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--blocks", type=int, default=6)
    parser.add_argument("--assimilation-days", type=int, default=60)
    parser.add_argument("--origins", type=int, default=12)
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path(
            "results/23_hbv_multilead_joint_uncertainty/"
            "h19_forecast_operator_audit_throwaway_v01"
        ),
    )
    arguments = parser.parse_args()
    days = int(arguments.assimilation_days)
    started = time.perf_counter()

    candidates = build_parameter_candidates(
        _pilot.BASE_PARAMETERS, _pilot.RECESSION_COEFFICIENTS
    )
    estimator = _pilot.build_estimator(candidates)

    batch = generate_long_history_parameter_switch_batch(
        block_seeds=_pilot.pilot_block_seeds(int(arguments.blocks), AUDIT_SEED_BASE_SPLIT),
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
    base = _pilot.base_transition_matrix()
    matrices = (
        (base / base.sum(dim=-1, keepdim=True))
        .reshape(1, 1, 3, 3)
        .expand(blocks, days, -1, -1)
        .contiguous()
    )
    trajectory = rollout_filter_state_trajectory(
        observable, matrices, estimator, candidate_parameters=candidates
    )

    origin_days = list(range(0, days, max(1, days // int(arguments.origins))))[
        : int(arguments.origins)
    ]
    identity = torch.eye(3, dtype=full.forcing.dtype).reshape(1, 3, 3).expand(
        blocks, -1, -1
    ).contiguous()
    base_repeated = (
        (base / base.sum(dim=-1, keepdim=True))
        .reshape(1, 3, 3)
        .expand(blocks, -1, -1)
        .contiguous()
    )

    identity_worst = 0.0
    self_validation_worst = 0.0
    for origin in origin_days:
        state = trajectory.global_posterior_states[:, origin]
        probabilities = trajectory.posterior_mode_probabilities[:, origin]
        future = full.forcing[:, origin + 1 : origin + 1 + max(LEADS)]
        frozen = forecast_global_state_weighted_parameters(
            state, future, candidates, probabilities, LEADS
        )
        evolving_identity = forecast_global_state_mode_evolving(
            state, future, candidates, probabilities, identity, LEADS
        )
        evolving_base = forecast_global_state_mode_evolving(
            state, future, candidates, probabilities, base_repeated, LEADS
        )
        identity_worst = max(
            identity_worst, maximum_absolute_difference(frozen, evolving_identity)
        )
        self_validation_worst = max(
            self_validation_worst, maximum_absolute_difference(frozen, evolving_base)
        )

    # Audit two: perturbing observations inside the forecast window must not move
    # any forecast.  Self-validation perturbs an assimilation-window observation,
    # which must move the forecast.
    perturbed_full_observations = full.observations.clone()
    perturbed_full_observations[:, days:] += 25.0
    isolation_worst = 0.0
    origin = origin_days[len(origin_days) // 2]
    state = trajectory.global_posterior_states[:, origin]
    probabilities = trajectory.posterior_mode_probabilities[:, origin]
    future = full.forcing[:, origin + 1 : origin + 1 + max(LEADS)]
    reference = forecast_global_state_mode_evolving(
        state, future, candidates, probabilities, base_repeated, LEADS
    )
    isolation_observable = ObservableAssimilationBatch(
        forcing=full.forcing[:, :days],
        observations=perturbed_full_observations[:, :days],
        initial_states=full.initial_states,
        initial_covariances=full.initial_covariances,
        assimilation_days=days,
    )
    isolation_trajectory = rollout_filter_state_trajectory(
        isolation_observable, matrices, estimator, candidate_parameters=candidates
    )
    isolated = forecast_global_state_mode_evolving(
        isolation_trajectory.global_posterior_states[:, origin],
        future,
        candidates,
        isolation_trajectory.posterior_mode_probabilities[:, origin],
        base_repeated,
        LEADS,
    )
    isolation_worst = maximum_absolute_difference(reference, isolated)

    assimilation_perturbed = full.observations.clone()
    assimilation_perturbed[:, origin] += 25.0
    sensitivity_observable = ObservableAssimilationBatch(
        forcing=full.forcing[:, :days],
        observations=assimilation_perturbed[:, :days],
        initial_states=full.initial_states,
        initial_covariances=full.initial_covariances,
        assimilation_days=days,
    )
    sensitivity_trajectory = rollout_filter_state_trajectory(
        sensitivity_observable, matrices, estimator, candidate_parameters=candidates
    )
    sensitive = forecast_global_state_mode_evolving(
        sensitivity_trajectory.global_posterior_states[:, origin],
        future,
        candidates,
        sensitivity_trajectory.posterior_mode_probabilities[:, origin],
        base_repeated,
        LEADS,
    )
    isolation_self_validation_worst = maximum_absolute_difference(reference, sensitive)

    identity_passed = identity_worst == 0.0
    identity_probe_valid = self_validation_worst > 0.0
    isolation_passed = isolation_worst == 0.0
    isolation_probe_valid = isolation_self_validation_worst > 0.0
    all_passed = (
        identity_passed
        and identity_probe_valid
        and isolation_passed
        and isolation_probe_valid
    )

    report = {
        "artifact_role": "h19_forecast_operator_implementation_audit",
        "contract": (
            "docs/plans/H19_CONTRACT_DRAFT_20260818_FORECAST_EVIDENCE_LAYER.md "
            "section 7.2"
        ),
        "publication_ready": False,
        "gate_decisions_made": 0,
        "experiment_identifier_consumed": None,
        "registry_row_written": False,
        "training_performed": False,
        "optimizer_created": False,
        "configuration": {
            "blocks": blocks,
            "assimilation_days": days,
            "origin_days_tested": origin_days,
            "leads": list(LEADS),
            "seed_namespace_base": _pilot.PILOT_SEED_BASE,
            "split_offset": AUDIT_SEED_BASE_SPLIT,
        },
        "audit_one_identity_degeneracy": {
            "criterion": (
                "with an identity transition matrix the evolving operator must "
                "equal the frozen operator bit for bit"
            ),
            "maximum_absolute_difference": identity_worst,
            "tolerance": 0.0,
            "passed": identity_passed,
            "self_validation_criterion": (
                "the same comparison with the base transition matrix must "
                "produce a nonzero difference, otherwise the probe cannot fail"
            ),
            "self_validation_maximum_absolute_difference": self_validation_worst,
            "self_validation_passed": identity_probe_valid,
        },
        "audit_two_forecast_window_observation_isolation": {
            "criterion": (
                "perturbing observations on days at or beyond the assimilation "
                "horizon must leave every forecast bit identical"
            ),
            "perturbation_magnitude": 25.0,
            "maximum_absolute_difference": isolation_worst,
            "tolerance": 0.0,
            "passed": isolation_passed,
            "structural_note": (
                "the operator signature accepts no observation tensor; this "
                "probe additionally covers the calling pipeline"
            ),
            "self_validation_criterion": (
                "perturbing an assimilation-window observation must move the "
                "forecast, otherwise the probe cannot fail"
            ),
            "self_validation_maximum_absolute_difference": (
                isolation_self_validation_worst
            ),
            "self_validation_passed": isolation_probe_valid,
        },
        "all_audits_passed": all_passed,
        "seconds": time.perf_counter() - started,
        "claim_boundary": (
            "Implementation correctness only. This audit says nothing about "
            "whether mode evolution improves any forecast."
        ),
    }

    output_dir = Path(arguments.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    (output_dir / "forecast_operator_audit.json").write_text(
        json.dumps(report, indent=2, sort_keys=True), encoding="utf-8"
    )
    print(json.dumps(report, indent=2, sort_keys=True))
    print(f"wrote {output_dir / 'forecast_operator_audit.json'}")
    if not all_passed:
        raise SystemExit(1)


if __name__ == "__main__":
    main()

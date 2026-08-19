"""H19 stage zero: measure the CEILING of mode evolution inside the forecast window.

Contract: docs/plans/H19_CONTRACT_DRAFT_20260818_FORECAST_EVIDENCE_LAYER.md
sections 3.1 and 5.1.

Question: once assimilation has produced one global posterior state, how much
can ANY transition rule improve the multi-lead discharge forecast by letting the
mode distribution evolve during the forecast window?  If even perfect knowledge
of the mode on every forecast day buys nothing, the whole forecast evidence
layer is dead and no trained method can rescue it.

ISOLATION (deliberate design choice, must be read with the numbers): every arm
shares ONE assimilation pass driven by the frozen base matrix, so all arms start
from bit-identical origin states and origin probabilities.  The only thing that
differs is what happens inside the forecast window.  This measures the
forecast-window headroom alone; it does NOT measure what an oracle system that
also assimilated better could achieve.

Five evaluation-only arms:
  * frozen_base                 - current operator, parameters frozen at origin
  * evolving_base               - mode evolves by the frozen base matrix
  * evolving_uniform            - mode evolves by a one-third matrix (degrader)
  * evolving_oracle_hazard      - mode evolves by the TRUE generative matrix on
                                  each forecast day (perfect transition law)
  * evolving_oracle_attribution - mode is placed on the TRUE mode of each
                                  forecast day (perfect attribution; the real
                                  upper bound, which no mode-based rule can beat)

The contract anchors both the gate and the stage-one threshold on the
ATTRIBUTION ceiling, not the hazard ceiling: H18 already showed a learned
history rule can EXCEED the true generative matrix, so the hazard arm is not an
upper bound.  The hazard arm is reported as context only.

No training, no optimizer, no checkpoint, no registry row, no experiment
identifier.  Throwaway seed namespace.  The gate decision is REPORTED, never
acted on: the contract requires the user to decide after seeing these numbers.
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
PRIMARY_LEAD = 7
ATTRIBUTION_EPSILON = 1e-6
STAGE_ZERO_SPLIT_OFFSET = 3
GATE_RELATIVE_FLOOR = 0.01
GATE_GREY_ZONE_UPPER = 0.03
BOOTSTRAP_SEED = 20260818


def hazard_matrices_full(batch, total_days: int) -> torch.Tensor:
    """The exact generative matrix on every day, including forecast days."""

    rows = batch.oracle_active_row_probabilities[:, :total_days]
    sources = batch.active_source_indices[:, :total_days]
    evaluated = batch.transition_evaluation_mask[:, :total_days]
    blocks = rows.shape[0]
    stay = torch.gather(rows, 2, torch.clamp(sources, min=0).unsqueeze(-1)).squeeze(-1)
    hazard = 1.0 - stay
    base = _pilot.base_transition_matrix()
    hazard = torch.where(
        evaluated, hazard, torch.full_like(hazard, 1.0 - float(base[0, 0]))
    )
    identity = torch.eye(3, dtype=rows.dtype).reshape(1, 1, 3, 3)
    off = (hazard / 2.0).reshape(blocks, total_days, 1, 1)
    matrix = identity * (1.0 - hazard).reshape(blocks, total_days, 1, 1) + (
        1.0 - identity
    ) * off
    return matrix / matrix.sum(dim=-1, keepdim=True)


def attribution_matrices_full(batch, total_days: int) -> torch.Tensor:
    """Every row concentrates on the true mode of that day (perfect attribution)."""

    modes = batch.true_parameter_indices[:, :total_days]
    blocks = modes.shape[0]
    matrix = torch.full(
        (blocks, total_days, 3, 3),
        ATTRIBUTION_EPSILON / 2.0,
        dtype=batch.forcing.dtype,
    )
    index = modes.reshape(blocks, total_days, 1, 1).expand(-1, -1, 3, 1)
    matrix.scatter_(3, index, 1.0 - ATTRIBUTION_EPSILON)
    return matrix / matrix.sum(dim=-1, keepdim=True)


def per_block_forecast_rmse(errors: np.ndarray) -> np.ndarray:
    """Root mean square forecast error within each block. Blocks are the unit."""

    return np.sqrt((errors**2).mean(axis=1))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--blocks", type=int, default=200)
    parser.add_argument("--assimilation-days", type=int, default=300)
    parser.add_argument("--bootstrap-draws", type=int, default=20000)
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path(
            "results/23_hbv_multilead_joint_uncertainty/"
            "h19_forecast_window_ceiling_throwaway_v01"
        ),
    )
    arguments = parser.parse_args()
    days = int(arguments.assimilation_days)
    horizon = max(LEADS)
    total_days = days + horizon
    started = time.perf_counter()

    candidates = build_parameter_candidates(
        _pilot.BASE_PARAMETERS, _pilot.RECESSION_COEFFICIENTS
    )
    estimator = _pilot.build_estimator(candidates)

    print("generating the stage-zero throwaway split...", flush=True)
    batch = generate_long_history_parameter_switch_batch(
        block_seeds=_pilot.pilot_block_seeds(
            int(arguments.blocks), STAGE_ZERO_SPLIT_OFFSET
        ),
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
    normalized_base = base / base.sum(dim=-1, keepdim=True)

    print("one shared assimilation pass with the base matrix...", flush=True)
    assimilation_matrices = (
        normalized_base.reshape(1, 1, 3, 3).expand(blocks, days, -1, -1).contiguous()
    )
    trajectory = rollout_filter_state_trajectory(
        observable, assimilation_matrices, estimator, candidate_parameters=candidates
    )

    hazard_full = hazard_matrices_full(batch, total_days)
    attribution_full = attribution_matrices_full(batch, total_days)
    base_window = (
        normalized_base.reshape(1, 1, 3, 3).expand(blocks, horizon, -1, -1).contiguous()
    )
    uniform_window = torch.full(
        (blocks, horizon, 3, 3), 1.0 / 3.0, dtype=full.forcing.dtype
    )

    arm_names = (
        "frozen_base",
        "evolving_base",
        "evolving_uniform",
        "evolving_oracle_hazard",
        "evolving_oracle_attribution",
    )
    errors = {
        name: {lead: np.zeros((blocks, days), dtype=np.float64) for lead in LEADS}
        for name in arm_names
    }
    mode_hits = {name: np.zeros((blocks, days), dtype=np.float64) for name in arm_names}
    truth_discharge = batch.truth_discharge
    true_modes = batch.true_parameter_indices

    print(f"forecasting from {days} origins on {blocks} blocks...", flush=True)
    for origin in range(days):
        state = trajectory.global_posterior_states[:, origin]
        probabilities = trajectory.posterior_mode_probabilities[:, origin]
        future = full.forcing[:, origin + 1 : origin + 1 + horizon]
        windows = {
            "evolving_base": base_window,
            "evolving_uniform": uniform_window,
            "evolving_oracle_hazard": hazard_full[:, origin + 1 : origin + 1 + horizon],
            "evolving_oracle_attribution": attribution_full[
                :, origin + 1 : origin + 1 + horizon
            ],
        }
        outputs = {
            "frozen_base": forecast_global_state_weighted_parameters(
                state, future, candidates, probabilities, LEADS
            )
        }
        for name, window in windows.items():
            outputs[name] = forecast_global_state_mode_evolving(
                state, future, candidates, probabilities, window, LEADS
            )
        for name in arm_names:
            for lead in LEADS:
                target = truth_discharge[:, origin + lead]
                errors[name][lead][:, origin] = (
                    (outputs[name][lead] - target).detach().numpy()
                )
        normalized_probabilities = probabilities / probabilities.sum(
            dim=-1, keepdim=True
        )
        target_mode = true_modes[:, origin + PRIMARY_LEAD]
        mode_hits["frozen_base"][:, origin] = (
            (normalized_probabilities.argmax(dim=-1) == target_mode)
            .to(dtype=torch.float64)
            .numpy()
        )
        for name, window in windows.items():
            advanced = normalized_probabilities
            for step in range(PRIMARY_LEAD):
                advanced = torch.einsum("bm,bmn->bn", advanced, window[:, step])
            mode_hits[name][:, origin] = (
                (advanced.argmax(dim=-1) == target_mode).to(dtype=torch.float64).numpy()
            )
        if (origin + 1) % 50 == 0:
            print(f"  origin {origin + 1}/{days}", flush=True)

    per_block = {
        name: {lead: per_block_forecast_rmse(errors[name][lead]) for lead in LEADS}
        for name in arm_names
    }
    summary = {
        name: {
            **{
                f"mean_forecast_rmse_lead_{lead}": float(per_block[name][lead].mean())
                for lead in LEADS
            },
            f"mode_accuracy_at_lead_{PRIMARY_LEAD}": float(mode_hits[name].mean()),
        }
        for name in arm_names
    }
    for name in arm_names:
        row = summary[name]
        print(
            f"  {name:28s} "
            f"lead1={row['mean_forecast_rmse_lead_1']:.7f} "
            f"lead3={row['mean_forecast_rmse_lead_3']:.7f} "
            f"lead7={row['mean_forecast_rmse_lead_7']:.7f} "
            f"mode_acc_l7={row[f'mode_accuracy_at_lead_{PRIMARY_LEAD}']:.4f}",
            flush=True,
        )

    reference = per_block["frozen_base"]
    contrasts: dict[str, dict] = {}
    for name in arm_names[1:]:
        for lead in LEADS:
            statistics = _pilot.paired_bootstrap(
                reference[lead] - per_block[name][lead],
                draws=int(arguments.bootstrap_draws),
                seed=BOOTSTRAP_SEED + lead,
            )
            statistics["relative_to_frozen_base"] = float(
                statistics["point_estimate"] / reference[lead].mean()
            )
            contrasts[f"frozen_base_minus_{name}_lead_{lead}"] = statistics

    # Rule-quality contrasts: with the operator ALREADY evolving, how much does a
    # better transition matrix buy?  This is the space stage one competes in, so
    # its bootstrap width is the power floor for the stage-one primary endpoint.
    rule_contrasts: dict[str, dict] = {}
    for name in ("evolving_oracle_hazard", "evolving_oracle_attribution"):
        for lead in LEADS:
            statistics = _pilot.paired_bootstrap(
                per_block["evolving_base"][lead] - per_block[name][lead],
                draws=int(arguments.bootstrap_draws),
                seed=BOOTSTRAP_SEED + 100 + lead,
            )
            statistics["relative_to_evolving_base"] = float(
                statistics["point_estimate"]
                / per_block["evolving_base"][lead].mean()
            )
            statistics["interval_half_width"] = float(
                (statistics["upper_95"] - statistics["lower_95"]) / 2.0
            )
            statistics["interval_excludes_zero"] = bool(
                statistics["lower_95"] > 0.0 or statistics["upper_95"] < 0.0
            )
            rule_contrasts[f"evolving_base_minus_{name}_lead_{lead}"] = statistics

    rule_key = f"evolving_base_minus_evolving_oracle_hazard_lead_{PRIMARY_LEAD}"
    rule_space = rule_contrasts[rule_key]
    power_floor = {
        "question": (
            "stage one compares transition RULES with the operator already "
            "evolving, so the contestable space is evolving_base minus "
            "oracle_hazard, not frozen minus oracle_hazard"
        ),
        "contestable_space_point_estimate": float(rule_space["point_estimate"]),
        "contestable_space_interval": [
            float(rule_space["lower_95"]),
            float(rule_space["upper_95"]),
        ],
        "contestable_space_interval_excludes_zero": bool(
            rule_space["interval_excludes_zero"]
        ),
        "bootstrap_interval_half_width_at_this_block_count": float(
            rule_space["interval_half_width"]
        ),
        "blocks_used_here": blocks,
        "half_width_projected_to_400_blocks": float(
            rule_space["interval_half_width"] * (blocks / 400.0) ** 0.5
        ),
        "verdict_note": (
            "If the projected half width at the stage-one block count is not "
            "comfortably smaller than the contestable space, the stage-one "
            "primary endpoint cannot resolve the effect and running it would "
            "burn an experiment identifier on an underpowered test. Reported, "
            "not acted on."
        ),
    }

    attribution_key = (
        f"frozen_base_minus_evolving_oracle_attribution_lead_{PRIMARY_LEAD}"
    )
    hazard_key = f"frozen_base_minus_evolving_oracle_hazard_lead_{PRIMARY_LEAD}"
    ceiling = contrasts[attribution_key]
    hazard_ceiling = contrasts[hazard_key]
    interval = (
        float(ceiling["lower_95"]) if "lower_95" in ceiling else None,
        float(ceiling["upper_95"]) if "upper_95" in ceiling else None,
    )
    interval_contains_zero = bool(
        interval[0] is not None
        and interval[1] is not None
        and interval[0] <= 0.0 <= interval[1]
    )
    relative = float(ceiling["relative_to_frozen_base"])
    below_floor = relative < GATE_RELATIVE_FLOOR
    gate_kills = interval_contains_zero or below_floor
    grey_zone = (not gate_kills) and relative < GATE_GREY_ZONE_UPPER

    report = {
        "artifact_role": "h19_stage_zero_forecast_window_ceiling_probe",
        "contract": (
            "docs/plans/H19_CONTRACT_DRAFT_20260818_FORECAST_EVIDENCE_LAYER.md "
            "sections 3.1 and 5.1"
        ),
        "publication_ready": False,
        "gate_decisions_made": 0,
        "gate_decision_is_reported_not_acted_on": True,
        "experiment_identifier_consumed": None,
        "registry_row_written": False,
        "training_performed": False,
        "optimizer_created": False,
        "seed_namespace_base": _pilot.PILOT_SEED_BASE,
        "configuration": {
            "blocks": blocks,
            "assimilation_days": days,
            "origins_per_block": days,
            "leads": list(LEADS),
            "primary_lead": PRIMARY_LEAD,
            "attribution_epsilon": ATTRIBUTION_EPSILON,
            "split_offset": STAGE_ZERO_SPLIT_OFFSET,
            "bootstrap_draws": int(arguments.bootstrap_draws),
        },
        "isolation_note": (
            "All arms share one assimilation pass driven by the frozen base "
            "matrix, so origin states and origin probabilities are bit "
            "identical across arms. Only the forecast window differs. These "
            "numbers bound forecast-window headroom alone."
        ),
        "arm_summary": summary,
        "paired_block_contrasts_versus_frozen_base": contrasts,
        "paired_block_contrasts_versus_evolving_base": rule_contrasts,
        "stage_one_power_floor": power_floor,
        "per_block_forecast_rmse": {
            name: {
                str(lead): per_block[name][lead].tolist() for lead in LEADS
            }
            for name in arm_names
        },
        "gate": {
            "anchor": "attribution ceiling at lead seven",
            "attribution_ceiling_point_estimate": float(ceiling["point_estimate"]),
            "attribution_ceiling_relative": relative,
            "attribution_ceiling_interval_contains_zero": interval_contains_zero,
            "hazard_ceiling_point_estimate": float(hazard_ceiling["point_estimate"]),
            "hazard_ceiling_relative": float(
                hazard_ceiling["relative_to_frozen_base"]
            ),
            "relative_floor": GATE_RELATIVE_FLOOR,
            "grey_zone_upper": GATE_GREY_ZONE_UPPER,
            "gate_would_kill_the_layer": gate_kills,
            "gate_in_grey_zone_requiring_user_judgement": grey_zone,
            "implied_stage_one_threshold_if_continued": float(
                0.10 * ceiling["point_estimate"]
            ),
            "implied_threshold_as_multiple_of_hazard_ceiling": (
                float(
                    0.10
                    * ceiling["point_estimate"]
                    / hazard_ceiling["point_estimate"]
                )
                if float(hazard_ceiling["point_estimate"]) > 0.0
                else None
            ),
            "threshold_exceeds_hazard_ceiling": bool(
                float(hazard_ceiling["point_estimate"]) > 0.0
                and 0.10 * float(ceiling["point_estimate"])
                > float(hazard_ceiling["point_estimate"])
            ),
            "threshold_calibration_warning": (
                "If threshold_exceeds_hazard_ceiling is true, the frozen rule "
                "T = 0.10 x attribution ceiling demands that a learned rule "
                "OUTPERFORM the perfect transition law outright. H18 showed that "
                "is possible (a learned rule beat oracle_hazard by about 1.10x in "
                "the state layer) but the required multiple here must be checked "
                "against that precedent before stage one is designed. This is the "
                "same failure mode that killed H18: a threshold set above what the "
                "design can plausibly deliver. Reported, not acted on."
            ),
            "user_decision_required_before_any_next_step": True,
        },
        "claim_boundary": (
            "Evaluation-only ceiling probe on one throwaway synthetic split, "
            "with assimilation held identical across arms. It bounds what mode "
            "evolution inside the forecast window could achieve here. It is not "
            "evidence about any trained method, and it cannot separate a real "
            "absence of mechanism from a network never optimised for forecasting."
        ),
    }

    output_dir = Path(arguments.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    (output_dir / "forecast_window_ceiling_report.json").write_text(
        json.dumps(report, indent=2, sort_keys=True), encoding="utf-8"
    )
    print(json.dumps(report["gate"], indent=2, sort_keys=True))
    print(f"elapsed {time.perf_counter() - started:.1f}s")
    print(f"wrote {output_dir / 'forecast_window_ceiling_report.json'}")


if __name__ == "__main__":
    main()

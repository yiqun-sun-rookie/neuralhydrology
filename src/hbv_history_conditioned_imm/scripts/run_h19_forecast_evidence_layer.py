"""H19 stage one: the forecast evidence layer, pure forward evaluation.

Contract: docs/plans/H19_CONTRACT_DRAFT_20260818_FORECAST_EVIDENCE_LAYER.md
(sections 3.2, 5.2 and 11; where section 11 conflicts with earlier sections it
wins).

Unique variable: how the daily three by three transition matrix is produced
(fixed / static / history times three seeds).  Everything else is held at the
H18 values.  The forecast operator is the mode-evolving one for the primary
endpoint; the frozen operator is run for every arm as a paired within-arm
control.

ZERO TRAINING.  No optimizer, no backward pass, no new weights.  The five
networks are the checkpoints H18 already selected; this layer only replays them
forward.  Lead seven is a scoring ruler, never a training target.

Primary endpoint (frozen before this file was run, contract section 11.6):
  lead seven forecast discharge RMSE, static minus history seed mean, both arms
  under the evolving operator, blocks as the statistical unit, paired bootstrap.
  Pass requires BOTH:
    * the paired bootstrap 95 percent interval excludes zero, history better
    * the effect is at least T = 0.0017554

T was fixed as 0.50 times the stage-zero contestable space (0.0035108, the gap
between evolving with an ordinary base matrix and evolving with the true
generative matrix, measured on a disjoint throwaway namespace at 2000 blocks).
It is NOT 0.10 times the attribution ceiling: that rule would give 0.0242500,
which is 6.9 times the contestable space and would repeat the H18 threshold
mis-setting.
"""

from __future__ import annotations

import argparse
from hashlib import sha256
import importlib.util
import json
from pathlib import Path
import platform
import sys
import time

import numpy as np
import torch

from hbv_history_conditioned_imm.hbv import (
    forecast_global_state_mode_evolving,
    forecast_global_state_weighted_parameters,
)
from hbv_history_conditioned_imm.long_history import (
    generate_long_history_parameter_switch_batch,
)
from hbv_history_conditioned_imm.network import (
    HistoryTransitionNetwork,
    StaticTransitionNetwork,
    build_history_features,
)
from hbv_history_conditioned_imm.parameter_switch import build_parameter_candidates
from hbv_history_conditioned_imm.synthetic import BlockSeeds

_H18 = Path(__file__).with_name("run_h18_observation_only_state_update.py")
_spec = importlib.util.spec_from_file_location("_h18_runner", _H18)
_h18 = importlib.util.module_from_spec(_spec)
sys.modules["_h18_runner"] = _h18
_spec.loader.exec_module(_h18)

EXPERIMENT_ID = "h19_forecast_evidence_layer_v01"
SOURCE_EXPERIMENT_ID = "h18_observation_only_state_update_v01"
SEED_BASE = 22_000_000_000
FAMILY = dict(_h18.FAMILY)
SPLIT_OFFSET = {"evaluation": 2}
EVALUATION_BLOCKS = 4000
DAYS = _h18.DAYS
LEADS = (1, 3, 7)
PRIMARY_LEAD = 7
AGE_STRATUM_MINIMUM = 50
FROZEN_THRESHOLD = 0.0017554
STAGE_ZERO_CONTESTABLE_SPACE = 0.0035108
BOOTSTRAP = {
    "primary": 20260818,
    "per_seed": 20260819,
    "descriptive": 20260820,
    "draws": 20000,
}
ARMS = ("fixed", "static") + tuple(
    f"history_seed_{seed}" for seed in _h18.HISTORY_SEEDS
)
HISTORY_ARMS = tuple(f"history_seed_{seed}" for seed in _h18.HISTORY_SEEDS)
OPERATORS = ("evolving", "frozen")


def block_seeds(count: int) -> tuple[BlockSeeds, ...]:
    base = SEED_BASE + SPLIT_OFFSET["evaluation"] * 10_000
    return tuple(
        BlockSeeds(
            block_id=f"h19_evaluation_b{index:04d}",
            forcing_seed=base + FAMILY["forcing"] + index,
            process_seed=base + FAMILY["process"] + index,
            observation_seed=base + FAMILY["observation"] + index,
            schedule_seed=base + FAMILY["schedule"] + index,
        )
        for index in range(int(count))
    )


def load_networks(source_dir: Path) -> dict[str, torch.nn.Module]:
    """Rebuild the H18 networks and restore their selected checkpoints."""

    base = _h18.base_transition_matrix()
    networks: dict[str, torch.nn.Module] = {"fixed": _h18.FixedTransitionNetwork()}

    static = StaticTransitionNetwork(base_transition=base)
    static.load_state_dict(torch.load(source_dir / "static_best_checkpoint.pt", map_location="cpu"))
    networks["static"] = static

    sentinel_mean = torch.zeros(21, dtype=base.dtype)
    sentinel_sd = torch.ones(21, dtype=base.dtype)
    for seed in _h18.HISTORY_SEEDS:
        name = f"history_seed_{seed}"
        network = HistoryTransitionNetwork(
            base_transition=base,
            feature_mean=sentinel_mean,
            feature_standard_deviation=sentinel_sd,
        )
        state = torch.load(source_dir / f"{name}_best_checkpoint.pt", map_location="cpu")
        network.load_state_dict(state)
        # The normalizer is carried as buffers inside the checkpoint. If it were
        # not, the sentinel would survive and every history arm would silently
        # receive unnormalized features. Refuse to run in that case.
        if torch.equal(network.feature_mean, sentinel_mean) or torch.equal(
            network.feature_standard_deviation, sentinel_sd
        ):
            raise SystemExit(
                f"{name}: checkpoint did not carry the feature normalizer; "
                "the history arm would be silently broken"
            )
        networks[name] = network
    for network in networks.values():
        network.eval()
        for parameter in network.parameters():
            parameter.requires_grad_(False)
    return networks


def evaluate_arm(
    name: str,
    network: torch.nn.Module,
    estimator,
    batch,
    candidates,
    *,
    days: int,
) -> dict[str, np.ndarray]:
    """One forward pass: assimilate, and forecast from every origin.

    Forecasts are issued inside the assimilation loop so that no per-day
    transition or covariance array is ever retained.
    """

    observable = batch.as_observable()
    forcing = observable.forcing
    observations = observable.observations
    blocks = forcing.shape[0]
    dtype = forcing.dtype
    horizon = max(LEADS)

    states = observable.initial_states.unsqueeze(1).expand(-1, 3, -1).clone()
    covariances = observable.initial_covariances.unsqueeze(1).expand(-1, 3, -1, -1).clone()
    probabilities = torch.full((blocks, 3), 1.0 / 3.0, dtype=dtype)
    hidden = network.initial_hidden(blocks, dtype=dtype)
    previous_forcing = torch.zeros((blocks, 3), dtype=dtype)
    previous_global = observable.initial_states

    squared = {
        operator: {lead: np.zeros((blocks, days), dtype=np.float64) for lead in LEADS}
        for operator in OPERATORS
    }
    primary_forecast = np.zeros((blocks, days), dtype=np.float64)
    mode_accuracy = np.zeros((blocks, days), dtype=np.float64)

    truth_discharge = batch.truth_discharge
    true_modes = batch.true_parameter_indices

    with torch.no_grad():
        for day in range(int(days)):
            raw = build_history_features(previous_forcing, previous_global, probabilities)
            transition, hidden, _ = network(raw, hidden)
            update = estimator.step(
                states=states,
                covariances=covariances,
                probabilities=probabilities,
                transition_matrix=transition,
                forcing=forcing[:, day],
                observation=observations[:, day],
            )
            origin_state = update.global_posterior_states
            origin_probabilities = update.posterior_probabilities
            future = forcing[:, day + 1 : day + 1 + horizon]

            evolving = forecast_global_state_mode_evolving(
                origin_state, future, candidates, origin_probabilities, transition, LEADS
            )
            frozen = forecast_global_state_weighted_parameters(
                origin_state, future, candidates, origin_probabilities, LEADS
            )
            for lead in LEADS:
                target = truth_discharge[:, day + lead]
                squared["evolving"][lead][:, day] = (
                    (evolving[lead] - target).numpy() ** 2
                )
                squared["frozen"][lead][:, day] = ((frozen[lead] - target).numpy() ** 2)
            primary_forecast[:, day] = evolving[PRIMARY_LEAD].numpy()

            normalized = origin_probabilities / origin_probabilities.sum(dim=-1, keepdim=True)
            advanced = normalized
            row = transition / transition.sum(dim=-1, keepdim=True)
            for _ in range(PRIMARY_LEAD):
                advanced = torch.einsum("bm,bmn->bn", advanced, row)
            mode_accuracy[:, day] = (
                (advanced.argmax(dim=-1) == true_modes[:, day + PRIMARY_LEAD])
                .to(dtype=torch.float64)
                .numpy()
            )

            states = update.posterior_states
            covariances = update.posterior_covariances
            probabilities = update.posterior_probabilities
            previous_forcing = forcing[:, day]
            previous_global = update.global_posterior_states

    result: dict[str, np.ndarray] = {}
    for operator in OPERATORS:
        for lead in LEADS:
            result[f"rmse_{operator}_lead_{lead}"] = np.sqrt(
                squared[operator][lead].mean(axis=1)
            )
    result["primary_forecast"] = primary_forecast
    result["mode_accuracy"] = mode_accuracy.mean(axis=1)
    return result


def paired_bootstrap(difference: np.ndarray, *, draws: int, seed: int, quantiles=(0.025, 0.975)) -> dict[str, float]:
    generator = np.random.default_rng(int(seed))
    count = difference.size
    samples = generator.integers(0, count, size=(int(draws), count))
    means = difference[samples].mean(axis=1)
    return {
        "point_estimate": float(difference.mean()),
        "block_standard_deviation": float(difference.std(ddof=1)),
        "lower": float(np.quantile(means, quantiles[0])),
        "upper": float(np.quantile(means, quantiles[1])),
        "interval_excludes_zero": bool(
            float(np.quantile(means, quantiles[0])) > 0.0
            or float(np.quantile(means, quantiles[1])) < 0.0
        ),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--smoke", action="store_true")
    parser.add_argument("--blocks", type=int, default=EVALUATION_BLOCKS)
    arguments = parser.parse_args()
    blocks_requested = 6 if arguments.smoke else int(arguments.blocks)
    days = 40 if arguments.smoke else DAYS
    run_dir = (
        Path("results/23_hbv_multilead_joint_uncertainty/.h19_smoke_dev_only")
        if arguments.smoke
        else Path(f"results/23_hbv_multilead_joint_uncertainty/{EXPERIMENT_ID}")
    )
    run_dir.mkdir(parents=True, exist_ok=True)
    wall_start = time.perf_counter()

    source_dir = Path(
        f"results/23_hbv_multilead_joint_uncertainty/{SOURCE_EXPERIMENT_ID}"
    )
    print("restoring the H18 checkpoints (no training happens here)...", flush=True)
    networks = load_networks(source_dir)
    estimator = _h18.build_estimator()
    candidates = build_parameter_candidates(
        _h18.BASE_PARAMETERS, _h18.RECESSION_COEFFICIENTS
    )

    print(f"generating {blocks_requested} fresh evaluation blocks (namespace {SEED_BASE})...", flush=True)
    generation_started = time.perf_counter()
    batch = generate_long_history_parameter_switch_batch(
        block_seeds=block_seeds(blocks_requested),
        parameter_candidates=candidates,
        warmup_parameter_id="calibrated_recession",
        assimilation_days=days,
        maximum_forecast_lead=_h18.MAX_LEAD,
        warmup_days=_h18.WARMUP_DAYS,
        hazard=_h18.DURATION_HAZARD,
        process_standard_deviation=_h18.PROCESS_SD,
        observation_standard_deviation=_h18.OBSERVATION_SD,
        process_state_index=_h18.PROCESS_STATE_INDEX,
        require_zero_projection=True,
    )
    generation_seconds = time.perf_counter() - generation_started
    blocks = batch.forcing.shape[0]

    switches = int(batch.switch_event_mask[:, :days].sum())
    age = batch.regime_age_before_transition[:, :days].numpy()
    aged_mask = age >= AGE_STRATUM_MINIMUM

    results: dict[str, dict[str, np.ndarray]] = {}
    timing: dict[str, float] = {"evaluation_generation": generation_seconds}
    for name in ARMS:
        started = time.perf_counter()
        results[name] = evaluate_arm(
            name, networks[name], estimator, batch, candidates, days=days
        )
        timing[f"arm_{name}"] = time.perf_counter() - started
        print(
            f"  {name:22s} lead7_evolving={results[name]['rmse_evolving_lead_7'].mean():.7f} "
            f"lead7_frozen={results[name]['rmse_frozen_lead_7'].mean():.7f} "
            f"mode_acc={results[name]['mode_accuracy'].mean():.4f} "
            f"({timing[f'arm_{name}']:.0f}s)",
            flush=True,
        )

    history_stack = {
        f"rmse_evolving_lead_{lead}": np.mean(
            [results[name][f"rmse_evolving_lead_{lead}"] for name in HISTORY_ARMS],
            axis=0,
        )
        for lead in LEADS
    }
    primary_difference = (
        results["static"][f"rmse_evolving_lead_{PRIMARY_LEAD}"]
        - history_stack[f"rmse_evolving_lead_{PRIMARY_LEAD}"]
    )
    primary = paired_bootstrap(
        primary_difference, draws=BOOTSTRAP["draws"], seed=BOOTSTRAP["primary"]
    )
    passed_interval = bool(primary["interval_excludes_zero"] and primary["point_estimate"] > 0.0)
    passed_threshold = bool(primary["point_estimate"] >= FROZEN_THRESHOLD)
    decision = (
        "H19_FORECAST_EVIDENCE_PASS"
        if (passed_interval and passed_threshold)
        else (
            "H19_FORECAST_NO_DISTINGUISHABLE_EFFECT"
            if not passed_interval
            else "H19_FORECAST_BELOW_PREREGISTERED_THRESHOLD"
        )
    )

    descriptive: dict[str, dict] = {}
    for lead in LEADS:
        descriptive[f"static_minus_history_lead_{lead}"] = paired_bootstrap(
            results["static"][f"rmse_evolving_lead_{lead}"]
            - history_stack[f"rmse_evolving_lead_{lead}"],
            draws=BOOTSTRAP["draws"],
            seed=BOOTSTRAP["descriptive"] + lead,
        )
        descriptive[f"fixed_minus_history_lead_{lead}"] = paired_bootstrap(
            results["fixed"][f"rmse_evolving_lead_{lead}"]
            - history_stack[f"rmse_evolving_lead_{lead}"],
            draws=BOOTSTRAP["draws"],
            seed=BOOTSTRAP["descriptive"] + 10 + lead,
        )
        descriptive[f"fixed_minus_static_lead_{lead}"] = paired_bootstrap(
            results["fixed"][f"rmse_evolving_lead_{lead}"]
            - results["static"][f"rmse_evolving_lead_{lead}"],
            draws=BOOTSTRAP["draws"],
            seed=BOOTSTRAP["descriptive"] + 20 + lead,
        )
    for name in ARMS:
        descriptive[f"operator_gain_{name}_lead_{PRIMARY_LEAD}"] = paired_bootstrap(
            results[name][f"rmse_frozen_lead_{PRIMARY_LEAD}"]
            - results[name][f"rmse_evolving_lead_{PRIMARY_LEAD}"],
            draws=BOOTSTRAP["draws"],
            seed=BOOTSTRAP["descriptive"] + 30,
        )
    per_seed = {
        name: paired_bootstrap(
            results["static"][f"rmse_evolving_lead_{PRIMARY_LEAD}"]
            - results[name][f"rmse_evolving_lead_{PRIMARY_LEAD}"],
            draws=BOOTSTRAP["draws"],
            seed=BOOTSTRAP["per_seed"],
        )
        for name in HISTORY_ARMS
    }
    monotone = [
        descriptive[f"static_minus_history_lead_{lead}"]["point_estimate"]
        for lead in LEADS
    ]
    monotone_holds = bool(all(b >= a for a, b in zip(monotone, monotone[1:])))

    arrays = {
        "truth_discharge_at_primary_lead": batch.truth_discharge[
            :, PRIMARY_LEAD : days + PRIMARY_LEAD
        ].numpy(),
        "regime_age_before_transition": age,
    }
    for name in ARMS:
        arrays[f"{name}_primary_forecast"] = results[name]["primary_forecast"]
        for operator in OPERATORS:
            for lead in LEADS:
                arrays[f"{name}_rmse_{operator}_lead_{lead}"] = results[name][
                    f"rmse_{operator}_lead_{lead}"
                ]
    np.savez(run_dir / "evaluation_arrays.npz", **arrays)
    for name in ARMS:
        torch.save(
            networks[name].state_dict(), run_dir / f"{name}_restored_checkpoint.pt"
        )

    timing["total_wall"] = time.perf_counter() - wall_start
    metrics = {
        "experiment_id": EXPERIMENT_ID,
        "contract": (
            "docs/plans/H19_CONTRACT_DRAFT_20260818_FORECAST_EVIDENCE_LAYER.md"
        ),
        "source_experiment": SOURCE_EXPERIMENT_ID,
        "training_performed": False,
        "optimizer_created": False,
        "backward_passes": 0,
        "environment": {"torch": torch.__version__, "platform": platform.platform()},
        "configuration": {
            "evaluation_blocks": blocks,
            "assimilation_days": days,
            "origins_per_block": days,
            "leads": list(LEADS),
            "primary_lead": PRIMARY_LEAD,
            "seed_namespace_base": SEED_BASE,
            "switch_events": switches,
            "age_stratum_minimum": AGE_STRATUM_MINIMUM,
            "bootstrap": BOOTSTRAP,
        },
        "frozen_before_this_run": {
            "threshold": FROZEN_THRESHOLD,
            "threshold_rule": "0.50 x stage-zero contestable space",
            "stage_zero_contestable_space": STAGE_ZERO_CONTESTABLE_SPACE,
            "superseded_rule_value": 0.02425001,
            "superseded_rule_reason": (
                "0.10 x attribution ceiling is 6.9x the contestable space and "
                "would repeat the H18 threshold mis-setting"
            ),
        },
        "arm_summary": {
            name: {
                **{
                    f"mean_rmse_{operator}_lead_{lead}": float(
                        results[name][f"rmse_{operator}_lead_{lead}"].mean()
                    )
                    for operator in OPERATORS
                    for lead in LEADS
                },
                "mode_accuracy_at_primary_lead": float(
                    results[name]["mode_accuracy"].mean()
                ),
            }
            for name in ARMS
        },
        "history_seed_mean_rmse_evolving": {
            f"lead_{lead}": float(history_stack[f"rmse_evolving_lead_{lead}"].mean())
            for lead in LEADS
        },
        "primary_endpoint": {
            "definition": (
                "lead seven forecast discharge RMSE, static minus history seed "
                "mean, both under the evolving operator, blocks as the unit"
            ),
            **primary,
            "threshold": FROZEN_THRESHOLD,
            "interval_criterion_met": passed_interval,
            "threshold_criterion_met": passed_threshold,
            "decision": decision,
        },
        "descriptive_secondary": descriptive,
        "per_seed_static_minus_history": per_seed,
        "monotonicity_check": {
            "effect_by_lead": {str(lead): value for lead, value in zip(LEADS, monotone)},
            "non_decreasing": monotone_holds,
            "note": (
                "descriptive only; failure does not change the decision but must "
                "be disclosed"
            ),
        },
        "timing_seconds": timing,
        "claim_boundary": (
            "Synthetic ideal-twin forecast evidence only. It establishes neither "
            "real-basin forecast value nor recovery of the true transition "
            "probabilities. A negative result cannot separate an absent mechanism "
            "from a network never optimised for forecasting, because every arm "
            "reuses checkpoints trained on a one-step observation evidence loss."
        ),
    }
    (run_dir / "metrics.json").write_text(
        json.dumps(metrics, indent=2, sort_keys=True), encoding="utf-8"
    )

    checksums = {}
    for path in sorted(run_dir.iterdir()):
        if path.name == "checksums.json":
            continue
        checksums[path.name] = sha256(path.read_bytes()).hexdigest()
    (run_dir / "checksums.json").write_text(
        json.dumps(checksums, indent=2, sort_keys=True), encoding="utf-8"
    )

    print()
    print(json.dumps(metrics["primary_endpoint"], indent=2, sort_keys=True))
    print(f"total wall {timing['total_wall']:.1f}s -> {run_dir}")


if __name__ == "__main__":
    main()

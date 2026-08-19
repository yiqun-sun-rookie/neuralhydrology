"""H18 formal runner: observation-only three-method state update (v01).

Preregistered contract:
  docs/plans/H18_CONTRACT_DRAFT_20260814_STATE_UPDATE_THREE_METHOD.md
Frozen declaration:
  configs/h18_observation_only_state_update_v01.json
User authorization: 2026-08-14 ("go" to contract finalization and formal run).

Structural guarantees:
  * training touches ObservableAssimilationBatch fields only; synthetic truth
    is generated but never reachable from the training path;
  * the evaluation split is GENERATED only after both trainable arms have
    finished training and checkpoint selection;
  * decisive metrics are computed in numpy from the exact arrays that are
    saved, so the independent verifier can reproduce them bit-for-bit.
"""

from __future__ import annotations

import argparse
from copy import deepcopy
from hashlib import sha256
import json
from pathlib import Path
import platform
import time

import numpy as np
import torch

from hbv_history_conditioned_imm.filter import (
    DifferentiableInteractingMultipleModel,
)
from hbv_history_conditioned_imm.hbv import STATE_COUNT, HBV15Model
from hbv_history_conditioned_imm.long_history import (
    ObservableAssimilationBatch,
    generate_long_history_parameter_switch_batch,
)
from hbv_history_conditioned_imm.network import (
    HistoryTransitionNetwork,
    StaticTransitionNetwork,
    build_history_features,
)
from hbv_history_conditioned_imm.parameter_switch import (
    PARAMETER_IDS,
    _generate_one_truth,
    build_parameter_candidates,
)
from hbv_history_conditioned_imm.synthetic import BlockSeeds


EXPERIMENT_ID = "h18_observation_only_state_update_v01"
SEED_BASE = 21_000_000_000
FAMILY = {"forcing": 100_000_000, "process": 200_000_000, "observation": 400_000_000, "schedule": 500_000_000}
SPLIT_OFFSET = {"train": 0, "validation": 1, "evaluation": 2}
HISTORY_SEEDS = (1810101, 1810102, 1810103)
BOOTSTRAP = {"anchor_G": 20260901, "primary_H": 20260902, "per_seed": 20260910, "accuracy": 20260920, "draws": 20000}

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
PROCESS_SD = 1.0
OBSERVATION_SD = 0.15
WARMUP_DAYS = 90
MAX_LEAD = 7
DAYS = 300

TRAIN_BLOCKS = 96
VALIDATION_BLOCKS = 24
EVALUATION_BLOCKS = 400
EPOCHS = 40
MINIBATCH = 8
LEARNING_RATE = 3e-3
WEIGHT_DECAY = 1e-4
COVARIANCE_FULL_BLOCKS = 40

STATE_NAMES = (
    "SNOWPACK", "MELTWATER", "SM", "SUZ", "SLZ",
    *(f"qraw_t_minus_{offset}" for offset in range(10)),
)


def block_seeds(count: int, split: str) -> tuple[BlockSeeds, ...]:
    base = SEED_BASE + SPLIT_OFFSET[split] * 10_000
    return tuple(
        BlockSeeds(
            block_id=f"h18_{split}_b{index:03d}",
            forcing_seed=base + FAMILY["forcing"] + index,
            process_seed=base + FAMILY["process"] + index,
            observation_seed=base + FAMILY["observation"] + index,
            schedule_seed=base + FAMILY["schedule"] + index,
        )
        for index in range(int(count))
    )


def generate_split(split: str, count: int):
    return generate_long_history_parameter_switch_batch(
        block_seeds=block_seeds(count, split),
        parameter_candidates=build_parameter_candidates(BASE_PARAMETERS, RECESSION_COEFFICIENTS),
        warmup_parameter_id="calibrated_recession",
        assimilation_days=DAYS,
        maximum_forecast_lead=MAX_LEAD,
        warmup_days=WARMUP_DAYS,
        hazard=DURATION_HAZARD,
        process_standard_deviation=PROCESS_SD,
        observation_standard_deviation=OBSERVATION_SD,
        process_state_index=PROCESS_STATE_INDEX,
        require_zero_projection=True,
    )


def build_estimator() -> DifferentiableInteractingMultipleModel:
    candidates = build_parameter_candidates(BASE_PARAMETERS, RECESSION_COEFFICIENTS)
    models = [HBV15Model(candidates[name]) for name in PARAMETER_IDS]
    process = torch.zeros((3, STATE_COUNT, STATE_COUNT), dtype=torch.float64)
    process[:, PROCESS_STATE_INDEX, PROCESS_STATE_INDEX] = PROCESS_SD**2
    return DifferentiableInteractingMultipleModel(models, process, OBSERVATION_SD**2)


def base_transition_matrix() -> torch.Tensor:
    stay = float(BASE_STAY_PROBABILITY)
    matrix = torch.full((3, 3), (1.0 - stay) / 2.0, dtype=torch.float64)
    matrix.fill_diagonal_(stay)
    return matrix


class FixedTransitionNetwork(torch.nn.Module):
    def __init__(self) -> None:
        super().__init__()
        base = base_transition_matrix()
        self.register_buffer("base_transition", base / base.sum(-1, keepdim=True))

    def initial_hidden(self, batch_size: int, *, dtype=None, device=None) -> torch.Tensor:
        return torch.zeros((int(batch_size), 1), dtype=dtype or self.base_transition.dtype, device=device or self.base_transition.device)

    def forward(self, previous_features, hidden):
        matrix = self.base_transition.expand(previous_features.shape[0], -1, -1)
        return matrix, hidden, torch.zeros_like(matrix)


def slice_observable(observable: ObservableAssimilationBatch, index: torch.Tensor) -> ObservableAssimilationBatch:
    return ObservableAssimilationBatch(
        forcing=observable.forcing[index],
        observations=observable.observations[index],
        initial_states=observable.initial_states[index],
        initial_covariances=observable.initial_covariances[index],
        assimilation_days=observable.assimilation_days,
    )


def rollout(
    observable: ObservableAssimilationBatch,
    network: torch.nn.Module,
    estimator: DifferentiableInteractingMultipleModel,
    *,
    days: int,
    collect: bool = False,
    collect_features: bool = False,
) -> dict[str, torch.Tensor]:
    batch = observable.forcing.shape[0]
    dtype = observable.forcing.dtype
    device = observable.forcing.device
    states = observable.initial_states.unsqueeze(1).expand(-1, 3, -1).clone()
    covariances = observable.initial_covariances.unsqueeze(1).expand(-1, 3, -1, -1).clone()
    probabilities = torch.full((batch, 3), 1.0 / 3.0, dtype=dtype, device=device)
    hidden = network.initial_hidden(batch, dtype=dtype, device=device)
    previous_forcing = torch.zeros((batch, 3), dtype=dtype, device=device)
    previous_global = observable.initial_states

    evidence: list[torch.Tensor] = []
    collected: dict[str, list[torch.Tensor]] = {
        key: [] for key in ("global_states", "global_covs", "prior_probs", "posterior_probs", "transitions")
    }
    features: list[torch.Tensor] = []

    for day in range(int(days)):
        raw = build_history_features(previous_forcing, previous_global, probabilities)
        if collect_features:
            features.append(raw)
        transition, hidden, _ = network(raw, hidden)
        update = estimator.step(
            states=states,
            covariances=covariances,
            probabilities=probabilities,
            transition_matrix=transition,
            forcing=observable.forcing[:, day],
            observation=observable.observations[:, day],
        )
        log_prior = torch.log(torch.clamp(update.prior_probabilities, min=torch.finfo(dtype).tiny))
        evidence.append(torch.logsumexp(log_prior + update.log_likelihoods, dim=-1))
        if collect:
            collected["global_states"].append(update.global_posterior_states)
            collected["global_covs"].append(update.global_posterior_covariances)
            collected["prior_probs"].append(update.prior_probabilities)
            collected["posterior_probs"].append(update.posterior_probabilities)
            collected["transitions"].append(transition)
        states = update.posterior_states
        covariances = update.posterior_covariances
        probabilities = update.posterior_probabilities
        previous_forcing = observable.forcing[:, day]
        previous_global = update.global_posterior_states

    result: dict[str, torch.Tensor] = {
        "negative_log_evidence": -torch.stack(evidence, dim=1).mean()
    }
    if collect:
        result.update({key: torch.stack(values, dim=1) for key, values in collected.items()})
    if collect_features:
        result["features"] = torch.stack(features, dim=1)
    return result


def fit_normalizer(train_observable, estimator):
    with torch.no_grad():
        output = rollout(train_observable, FixedTransitionNetwork(), estimator, days=DAYS, collect_features=True)
    flat = output["features"].reshape(-1, 21)
    return flat.mean(dim=0), torch.clamp(flat.std(dim=0, unbiased=False), min=1e-6)


def train_arm(name, network, estimator, train_observable, validation_observable, *, epochs, minibatch):
    optimizer = torch.optim.AdamW(network.parameters(), lr=LEARNING_RATE, weight_decay=WEIGHT_DECAY)
    blocks = train_observable.forcing.shape[0]
    history_rows: list[dict[str, float]] = []
    non_finite = 0
    best = float("inf")
    best_epoch = 0
    best_state = deepcopy(network.state_dict())
    for epoch in range(1, int(epochs) + 1):
        network.train()
        started = time.perf_counter()
        running = 0.0
        for start in range(0, blocks, int(minibatch)):
            stop = min(start + int(minibatch), blocks)
            subset = slice_observable(train_observable, torch.arange(start, stop))
            optimizer.zero_grad(set_to_none=True)
            output = rollout(subset, network, estimator, days=DAYS)
            output["negative_log_evidence"].backward()
            for parameter in network.parameters():
                if parameter.grad is not None and not torch.isfinite(parameter.grad).all():
                    non_finite += 1
                    break
            torch.nn.utils.clip_grad_norm_(network.parameters(), max_norm=1.0)
            optimizer.step()
            running += float(output["negative_log_evidence"].detach()) * (stop - start)
        network.eval()
        with torch.no_grad():
            validation = float(
                rollout(validation_observable, network, estimator, days=DAYS)["negative_log_evidence"]
            )
        row = {
            "epoch": float(epoch),
            "train_negative_log_evidence": running / blocks,
            "validation_negative_log_evidence": validation,
            "train_seconds": time.perf_counter() - started,
        }
        history_rows.append(row)
        if validation < best:
            best = validation
            best_epoch = epoch
            best_state = deepcopy(network.state_dict())
        print(f"  [{name}] epoch {epoch}/{epochs} train={row['train_negative_log_evidence']:.6f} val={validation:.6f} {row['train_seconds']:.0f}s", flush=True)
    network.load_state_dict(best_state)
    return {
        "history": history_rows,
        "best_epoch": best_epoch,
        "best_validation_negative_log_evidence": best,
        "non_finite_gradient_steps": non_finite,
        "trainable_parameter_count": sum(int(p.numel()) for p in network.parameters()),
    }


def signal_ratio_preflight(train_batch) -> dict[str, float]:
    candidates = build_parameter_candidates(BASE_PARAMETERS, RECESSION_COEFFICIENTS)
    forcing = train_batch.forcing.numpy()
    initial = train_batch.initial_states.numpy()
    total = forcing.shape[1]
    blocks = forcing.shape[0]
    discharge = {}
    for index, identifier in enumerate(PARAMETER_IDS):
        rows = []
        for block in range(blocks):
            truth = _generate_one_truth(
                forcing=forcing[block],
                initial_state=initial[block],
                schedule_indices=np.full(total, index, dtype=np.int64),
                parameter_ids=PARAMETER_IDS,
                parameter_candidates=candidates,
                process_normals=np.zeros(total),
                process_standard_deviation=PROCESS_SD,
                process_state_index=PROCESS_STATE_INDEX,
                require_zero_projection=False,
            )
            rows.append(truth["discharge"][:DAYS])
        discharge[identifier] = np.stack(rows)
    ratios = {}
    for a in range(3):
        for b in range(a + 1, 3):
            key = f"{PARAMETER_IDS[a]}__vs__{PARAMETER_IDS[b]}"
            rmse = float(np.sqrt(np.mean((discharge[PARAMETER_IDS[a]] - discharge[PARAMETER_IDS[b]]) ** 2)))
            ratios[key] = rmse / OBSERVATION_SD
    minimum = float(min(ratios.values()))
    return {"pairwise_ratios": ratios, "minimum_ratio": minimum, "passed": minimum > 2.0}


def causality_audit(history_network, estimator, train_observable) -> dict[str, object]:
    days = 80
    cut = 40
    index = torch.arange(0, 1)
    observations = train_observable.observations[index, :].clone().requires_grad_(True)
    observable = ObservableAssimilationBatch(
        forcing=train_observable.forcing[index],
        observations=observations,
        initial_states=train_observable.initial_states[index],
        initial_covariances=train_observable.initial_covariances[index],
        assimilation_days=train_observable.assimilation_days,
    )
    output = rollout(observable, history_network, estimator, days=days, collect=True)
    # Differentiate ONE entry.  Summing the whole row-stochastic matrix gives the
    # constant 3.0, whose gradient is identically zero, which would make the audit
    # vacuously report "no dependence" on every day including the past.
    output["transitions"][0, cut, 0, 0].backward()
    gradient = observations.grad[0]
    same_or_future = float(gradient[cut:days].abs().max())
    strictly_past = float(gradient[:cut].abs().max())
    return {
        "audit_day": cut,
        "audit_days_total": days,
        "max_abs_gradient_same_or_future_day": same_or_future,
        "max_abs_gradient_strictly_past_day": strictly_past,
        "passed": same_or_future == 0.0 and strictly_past > 0.0,
    }


def per_block_rmse(estimate: np.ndarray, truth: np.ndarray, scales: np.ndarray, keep: np.ndarray) -> np.ndarray:
    error = (estimate - truth) / scales
    return np.sqrt(np.mean(np.square(error[:, :, keep]), axis=(1, 2)))


def paired_bootstrap(difference: np.ndarray, *, seed: int, lower_quantile: float, upper_quantile: float) -> dict[str, float]:
    generator = np.random.default_rng(int(seed))
    count = difference.size
    samples = generator.integers(0, count, size=(int(BOOTSTRAP["draws"]), count))
    means = difference[samples].mean(axis=1)
    return {
        "point_estimate": float(difference.mean()),
        "block_standard_deviation": float(difference.std(ddof=1)),
        "lower": float(np.quantile(means, lower_quantile)),
        "upper": float(np.quantile(means, upper_quantile)),
        "lower_quantile": lower_quantile,
        "upper_quantile": upper_quantile,
    }


def sha256_file(path: Path) -> str:
    digest = sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def compute_metrics(arrays: dict[str, np.ndarray], method_names: tuple[str, ...]) -> dict[str, object]:
    """Decisive metrics from the exact arrays that are saved (numpy only)."""

    truth = arrays["truth_states"]
    scales = truth.std(axis=(0, 1))
    keep = scales > 1e-8
    safe = np.where(keep, scales, 1.0)
    store_keep = keep.copy(); store_keep[5:] = False
    routing_keep = keep.copy(); routing_keep[:5] = False

    true_modes = arrays["true_modes"]
    sources = arrays["active_sources"]
    ages = arrays["regime_ages"]
    evaluated = arrays["eval_mask"].astype(bool)
    oracle = arrays["oracle_rows"]

    rmse: dict[str, np.ndarray] = {}
    accuracy: dict[str, np.ndarray] = {}
    summary: dict[str, dict[str, float]] = {}
    for method in method_names:
        states = arrays[f"{method}__global_states"]
        rmse[method] = per_block_rmse(states, truth, safe, keep)
        posterior = arrays[f"{method}__posterior_probs"]
        accuracy[method] = (posterior.argmax(axis=-1) == true_modes).mean(axis=1)
        transitions = arrays[f"{method}__transitions"]
        rows = np.take_along_axis(
            transitions,
            np.clip(sources, 0, None)[..., None, None].repeat(3, axis=-1),
            axis=2,
        )[:, :, 0, :]
        brier = float(np.sum((rows[evaluated] - oracle[evaluated]) ** 2, axis=-1).mean())
        predicted_stay = np.take_along_axis(rows, np.clip(sources, 0, None)[..., None], axis=-1)[..., 0]
        true_stay = np.take_along_axis(oracle, np.clip(sources, 0, None)[..., None], axis=-1)[..., 0]
        hazard_error = np.abs((1.0 - predicted_stay) - (1.0 - true_stay))
        age_bins = {
            "age_lt_30": (ages < 30),
            "age_30_39": (ages >= 30) & (ages < 40),
            "age_40_49": (ages >= 40) & (ages < 50),
            "age_ge_50": (ages >= 50),
        }
        summary[method] = {
            "mean_rmse": float(rmse[method].mean()),
            "mean_rmse_stores_only": float(per_block_rmse(states, truth, safe, store_keep).mean()),
            "mean_rmse_routing_only": float(per_block_rmse(states, truth, safe, routing_keep).mean()),
            "mode_accuracy": float(accuracy[method].mean()),
            "active_row_brier": brier,
            "switch_hazard_mae": float(hazard_error[evaluated].mean()),
            **{
                f"switch_hazard_mae_{label}": (
                    float(hazard_error[mask & evaluated].mean())
                    if bool((mask & evaluated).any())
                    else None
                )
                for label, mask in age_bins.items()
            },
        }

    history_members = [m for m in method_names if m.startswith("history_seed_")]
    history_mean_rmse = np.mean([rmse[m] for m in history_members], axis=0)
    history_mean_accuracy = np.mean([accuracy[m] for m in history_members], axis=0)

    anchor = paired_bootstrap(
        rmse["fixed"] - rmse["static"],
        seed=BOOTSTRAP["anchor_G"], lower_quantile=0.025, upper_quantile=0.975,
    )
    branch_a = anchor["point_estimate"] > 0.0 and anchor["lower"] > 0.0
    threshold = (
        0.5 * anchor["point_estimate"] if branch_a else 0.05 * float(rmse["static"].mean())
    )
    primary = paired_bootstrap(
        rmse["static"] - history_mean_rmse,
        seed=BOOTSTRAP["primary_H"], lower_quantile=0.0125, upper_quantile=0.9875,
    )
    passed = primary["lower"] > 0.0 and primary["point_estimate"] >= threshold
    per_seed = {
        member: paired_bootstrap(
            rmse["static"] - rmse[member],
            seed=BOOTSTRAP["per_seed"], lower_quantile=0.025, upper_quantile=0.975,
        )
        for member in history_members
    }
    accuracy_contrast = paired_bootstrap(
        history_mean_accuracy - accuracy["static"],
        seed=BOOTSTRAP["accuracy"], lower_quantile=0.025, upper_quantile=0.975,
    )
    history_vs_fixed = paired_bootstrap(
        rmse["fixed"] - history_mean_rmse,
        seed=BOOTSTRAP["primary_H"], lower_quantile=0.025, upper_quantile=0.975,
    )

    return {
        "scored_state_count": int(keep.sum()),
        "degenerate_zero_variance_states": [STATE_NAMES[i] for i in range(STATE_COUNT) if not keep[i]],
        "state_scales": scales.tolist(),
        "arm_summary": summary,
        "per_block_rmse": {m: rmse[m].tolist() for m in method_names},
        "history_seed_mean_per_block_rmse": history_mean_rmse.tolist(),
        "primary_endpoint": {
            "anchor_G_fixed_minus_static": anchor,
            "branch": "A" if branch_a else "B",
            "threshold_T": float(threshold),
            "H_static_minus_history_seed_mean": primary,
            "interval_excludes_zero": bool(primary["lower"] > 0.0),
            "point_estimate_reaches_threshold": bool(primary["point_estimate"] >= threshold),
            "passed": bool(passed),
        },
        "secondary_descriptive": {
            "per_seed_static_minus_history": per_seed,
            "history_seed_mean_minus_static_mode_accuracy": accuracy_contrast,
            "fixed_minus_history_seed_mean_rmse": history_vs_fixed,
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--smoke", action="store_true", help="tiny development smoke run into the scratch area; never the formal directory")
    arguments = parser.parse_args()

    global TRAIN_BLOCKS, VALIDATION_BLOCKS, EVALUATION_BLOCKS, EPOCHS, COVARIANCE_FULL_BLOCKS
    if arguments.smoke:
        TRAIN_BLOCKS, VALIDATION_BLOCKS, EVALUATION_BLOCKS, EPOCHS, COVARIANCE_FULL_BLOCKS = 4, 2, 6, 2, 2
        run_dir = Path("results/23_hbv_multilead_joint_uncertainty/.h18_smoke_dev_only")
    else:
        run_dir = Path(f"results/23_hbv_multilead_joint_uncertainty/{EXPERIMENT_ID}")
    run_dir.mkdir(parents=True, exist_ok=True)

    wall_start = time.perf_counter()
    estimator = build_estimator()

    print("generating train and validation splits...", flush=True)
    t0 = time.perf_counter()
    train_batch = generate_split("train", TRAIN_BLOCKS)
    validation_batch = generate_split("validation", VALIDATION_BLOCKS)
    generation_seconds = time.perf_counter() - t0
    train_observable = train_batch.as_observable()
    validation_observable = validation_batch.as_observable()

    print("signal-ratio preflight...", flush=True)
    t0 = time.perf_counter()
    signal = signal_ratio_preflight(train_batch)
    signal["seconds"] = time.perf_counter() - t0
    print(f"  minimum pairwise ratio {signal['minimum_ratio']:.4f} passed={signal['passed']}", flush=True)
    if not signal["passed"]:
        (run_dir / "preflight_failure.json").write_text(json.dumps(signal, indent=2), encoding="utf-8")
        raise SystemExit("signal-ratio preflight failed; run stopped before any training")

    print("fitting observation-only normalizer...", flush=True)
    feature_mean, feature_sd = fit_normalizer(train_observable, estimator)

    training_reports: dict[str, object] = {}
    networks: dict[str, torch.nn.Module] = {"fixed": FixedTransitionNetwork()}

    print("training static (deterministic, single run)...", flush=True)
    static_network = StaticTransitionNetwork(base_transition=base_transition_matrix())
    training_reports["static"] = train_arm(
        "static", static_network, estimator, train_observable, validation_observable,
        epochs=EPOCHS, minibatch=MINIBATCH,
    )
    networks["static"] = static_network

    for seed in HISTORY_SEEDS:
        print(f"training history seed {seed}...", flush=True)
        torch.manual_seed(int(seed))
        history_network = HistoryTransitionNetwork(
            base_transition=base_transition_matrix(),
            feature_mean=feature_mean,
            feature_standard_deviation=feature_sd,
        )
        training_reports[f"history_seed_{seed}"] = train_arm(
            f"history_{seed}", history_network, estimator, train_observable, validation_observable,
            epochs=EPOCHS, minibatch=MINIBATCH,
        )
        networks[f"history_seed_{seed}"] = history_network

    print("causality audit on the first trained history network...", flush=True)
    audit = causality_audit(networks[f"history_seed_{HISTORY_SEEDS[0]}"], estimator, train_observable)
    print(f"  same/future max grad {audit['max_abs_gradient_same_or_future_day']:.3e}, past max grad {audit['max_abs_gradient_strictly_past_day']:.3e}, passed={audit['passed']}", flush=True)

    print("generating the evaluation split (checkpoint selection is complete)...", flush=True)
    t0 = time.perf_counter()
    evaluation_batch = generate_split("evaluation", EVALUATION_BLOCKS)
    evaluation_generation_seconds = time.perf_counter() - t0
    evaluation_observable = evaluation_batch.as_observable()

    directed = {}
    modes = evaluation_batch.true_parameter_indices[:, :DAYS].numpy()
    switches = evaluation_batch.switch_event_mask[:, :DAYS].numpy().astype(bool)
    for block in range(modes.shape[0]):
        for day in np.nonzero(switches[block])[0]:
            key = f"{modes[block, day - 1]}->{modes[block, day]}"
            directed[key] = directed.get(key, 0) + 1

    arrays: dict[str, np.ndarray] = {
        "truth_states": evaluation_batch.truth_states[:, :DAYS].numpy().astype("<f8"),
        "true_modes": modes.astype("<i8"),
        "active_sources": evaluation_batch.active_source_indices[:, :DAYS].numpy().astype("<i8"),
        "regime_ages": evaluation_batch.regime_age_before_transition[:, :DAYS].numpy().astype("<i8"),
        "eval_mask": evaluation_batch.transition_evaluation_mask[:, :DAYS].numpy(),
        "switch_mask": switches,
        "oracle_rows": evaluation_batch.oracle_active_row_probabilities[:, :DAYS].numpy().astype("<f8"),
        "observations": evaluation_observable.observations[:, :DAYS].numpy().astype("<f8"),
        "forcing": evaluation_observable.forcing[:, :DAYS].numpy().astype("<f8"),
        "initial_states": evaluation_observable.initial_states.numpy().astype("<f8"),
        "initial_covariances": evaluation_observable.initial_covariances.numpy().astype("<f8"),
    }

    method_names = ("fixed", "static", *(f"history_seed_{seed}" for seed in HISTORY_SEEDS))
    evaluation_seconds: dict[str, float] = {}
    for method in method_names:
        print(f"evaluating {method} on {EVALUATION_BLOCKS} blocks...", flush=True)
        t0 = time.perf_counter()
        networks[method].eval()
        with torch.no_grad():
            output = rollout(evaluation_observable, networks[method], estimator, days=DAYS, collect=True)
        arrays[f"{method}__global_states"] = output["global_states"].numpy().astype("<f8")
        covariances = output["global_covs"].numpy().astype("<f8")
        arrays[f"{method}__global_cov_diag"] = np.diagonal(covariances, axis1=-2, axis2=-1).copy()
        arrays[f"{method}__global_cov_full_first_blocks"] = covariances[:COVARIANCE_FULL_BLOCKS].copy()
        arrays[f"{method}__prior_probs"] = output["prior_probs"].numpy().astype("<f8")
        arrays[f"{method}__posterior_probs"] = output["posterior_probs"].numpy().astype("<f8")
        arrays[f"{method}__transitions"] = output["transitions"].numpy().astype("<f8")
        evaluation_seconds[method] = time.perf_counter() - t0
        del output, covariances

    print("computing decisive metrics from the saved arrays...", flush=True)
    metrics = compute_metrics(arrays, method_names)
    decision = "H18_STATE_UPDATE_PASS" if metrics["primary_endpoint"]["passed"] else "H18_STATE_UPDATE_HOLD_H18F_PRESPECIFIED"

    print("writing artifacts...", flush=True)
    np.savez(run_dir / "evaluation_arrays.npz", **arrays)
    for method in method_names:
        if method == "fixed":
            continue
        torch.save(networks[method].state_dict(), run_dir / f"{method}_best_checkpoint.pt")

    report = {
        "experiment_id": EXPERIMENT_ID,
        "smoke": bool(arguments.smoke),
        "decision": decision,
        "configuration": {
            "training_blocks": TRAIN_BLOCKS, "validation_blocks": VALIDATION_BLOCKS,
            "evaluation_blocks": EVALUATION_BLOCKS, "assimilation_days": DAYS,
            "epochs": EPOCHS, "minibatch": MINIBATCH, "learning_rate": LEARNING_RATE,
            "weight_decay": WEIGHT_DECAY, "history_seeds": list(HISTORY_SEEDS),
            "seed_namespace_base": SEED_BASE, "bootstrap": BOOTSTRAP,
            "loss": "one-step observation negative log evidence only",
            "covariance_full_blocks": COVARIANCE_FULL_BLOCKS,
        },
        "truth_isolation": {
            "true_labels_used_in_training": False,
            "mechanism": "training path receives ObservableAssimilationBatch only; normalizer fitted from a fixed-matrix causal rollout on training observables",
            "evaluation_generated_after_checkpoint_selection": True,
        },
        "preflight_signal_ratio": signal,
        "causality_audit": audit,
        "evaluation_coverage": {
            "switch_events": int(switches.sum()),
            "directed_transition_counts": directed,
        },
        "training": training_reports,
        "timing_seconds": {
            "train_validation_generation": generation_seconds,
            "evaluation_generation": evaluation_generation_seconds,
            "evaluation_rollouts": evaluation_seconds,
            "total_wall": time.perf_counter() - wall_start,
        },
        "environment": {
            "python": platform.python_version(), "torch": torch.__version__,
            "numpy": np.__version__, "threads": int(torch.get_num_threads()),
        },
        "metrics": metrics,
        "claim_boundary": (
            "Synthetic ideal-twin state-update evidence under strict observation-only "
            "training. No forecast, real-basin, or probability-recovery claim."
        ),
    }
    (run_dir / "metrics.json").write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")

    checksums = {
        path.name: sha256_file(path)
        for path in sorted(run_dir.iterdir())
        if path.is_file() and path.name != "checksums.json"
    }
    (run_dir / "checksums.json").write_text(json.dumps(checksums, indent=2, sort_keys=True), encoding="utf-8")

    print(json.dumps({"decision": decision, "primary": metrics["primary_endpoint"]}, indent=2))
    print(f"wrote {run_dir}")


if __name__ == "__main__":
    main()

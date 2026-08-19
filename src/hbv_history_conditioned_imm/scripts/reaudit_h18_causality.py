"""Re-run the H18 layer-1 causality gate after fixing a defect in the audit itself.

The original in-run audit backpropagated the SUM of a row-stochastic 3x3 matrix.
That sum is the constant 3.0, so its gradient is identically zero for every input
day.  The audit therefore reported "no dependence on same/future days" (vacuously
true) AND "no dependence on past days" (vacuously false), and failed.

This script differentiates a single transition entry instead, which is the correct
probe, and re-runs the gate against the SAVED checkpoints.  It retrains nothing and
changes no metric: the causality gate constrains the network's information flow, not
the reported performance numbers.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import torch

import importlib.util
import sys

_RUNNER = Path(__file__).with_name("run_h18_observation_only_state_update.py")
_spec = importlib.util.spec_from_file_location("_h18_runner", _RUNNER)
_runner = importlib.util.module_from_spec(_spec)
sys.modules["_h18_runner"] = _runner
_spec.loader.exec_module(_runner)

from hbv_history_conditioned_imm.long_history import ObservableAssimilationBatch
from hbv_history_conditioned_imm.network import HistoryTransitionNetwork


def audit_one(network, estimator, train_observable, *, days: int, cut: int) -> dict[str, object]:
    index = torch.arange(0, 1)
    observations = train_observable.observations[index, :].clone().requires_grad_(True)
    observable = ObservableAssimilationBatch(
        forcing=train_observable.forcing[index],
        observations=observations,
        initial_states=train_observable.initial_states[index],
        initial_covariances=train_observable.initial_covariances[index],
        assimilation_days=train_observable.assimilation_days,
    )
    output = _runner.rollout(observable, network, estimator, days=days, collect=True)
    output["transitions"][0, cut, 0, 0].backward()
    gradient = observations.grad[0]
    same_or_future = float(gradient[cut:days].abs().max())
    strictly_past = float(gradient[:cut].abs().max())
    return {
        "probe": "single transition entry [day=cut, source=0, destination=0]",
        "audit_day": cut,
        "audit_days_total": days,
        "max_abs_gradient_same_or_future_day": same_or_future,
        "max_abs_gradient_strictly_past_day": strictly_past,
        "same_or_future_is_exactly_zero": same_or_future == 0.0,
        "past_dependence_is_positive": strictly_past > 0.0,
        "passed": same_or_future == 0.0 and strictly_past > 0.0,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-dir", type=Path, default=Path(f"results/23_hbv_multilead_joint_uncertainty/{_runner.EXPERIMENT_ID}"))
    arguments = parser.parse_args()

    estimator = _runner.build_estimator()
    train_batch = _runner.generate_split("train", _runner.TRAIN_BLOCKS)
    train_observable = train_batch.as_observable()
    feature_mean, feature_sd = _runner.fit_normalizer(train_observable, estimator)

    results: dict[str, object] = {}
    for seed in _runner.HISTORY_SEEDS:
        name = f"history_seed_{seed}"
        checkpoint = arguments.run_dir / f"{name}_best_checkpoint.pt"
        network = HistoryTransitionNetwork(
            base_transition=_runner.base_transition_matrix(),
            feature_mean=feature_mean,
            feature_standard_deviation=feature_sd,
        )
        network.load_state_dict(torch.load(checkpoint, weights_only=True))
        network.eval()
        results[name] = audit_one(network, estimator, train_observable, days=80, cut=40)
        print(f"  {name}: future={results[name]['max_abs_gradient_same_or_future_day']:.3e} "
              f"past={results[name]['max_abs_gradient_strictly_past_day']:.3e} "
              f"passed={results[name]['passed']}", flush=True)

    report = {
        "supersedes": "the causality_audit block inside metrics.json, which used a defective probe",
        "defect": "backpropagating the sum of a row-stochastic matrix (constant 3.0) yields identically zero gradients, making the past-dependence check vacuously fail",
        "retraining_performed": False,
        "metrics_changed": False,
        "per_seed": results,
        "all_passed": all(value["passed"] for value in results.values()),
    }
    path = arguments.run_dir / "causality_audit_v2.json"
    path.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
    print(json.dumps({"all_passed": report["all_passed"]}, indent=2))
    print(f"wrote {path}")


if __name__ == "__main__":
    main()

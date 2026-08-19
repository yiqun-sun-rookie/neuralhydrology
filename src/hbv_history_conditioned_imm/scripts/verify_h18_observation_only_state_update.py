"""Independent verification of H18.

Three checks:
  1. semantic  - the decisive primary-endpoint numbers are recomputed here from
     the saved arrays with an INDEPENDENT implementation (this file does not call
     the runner's compute_metrics) and the frozen bootstrap seeds, then compared
     exactly against metrics.json;
  2. replay    - the fixed arm is regenerated from seeds and rolled out at the
     SAME batch shape the runner used (all evaluation blocks in one call) and
     compared to the saved global posterior states.  Mixing batch shapes between
     runner and verifier is what burned H17R; it is deliberately avoided here;
  3. integrity - every file hash in checksums.json is recomputed.

Exit code 0 only if all three pass.
"""

from __future__ import annotations

import argparse
from hashlib import sha256
import json
from pathlib import Path

import numpy as np
import torch

import importlib.util
import sys

_RUNNER = Path(__file__).with_name("run_h18_observation_only_state_update.py")
_spec = importlib.util.spec_from_file_location("_h18_runner", _RUNNER)
_runner = importlib.util.module_from_spec(_spec)
sys.modules["_h18_runner"] = _runner
_spec.loader.exec_module(_runner)


REPLAY_TOLERANCE = 1e-12


def independent_per_block_rmse(estimate, truth, scales, keep):
    """Deliberately written from the contract text, not imported from the runner."""
    scaled_error = (estimate - truth) / scales
    kept = scaled_error[:, :, keep]
    total = np.zeros(kept.shape[0], dtype=np.float64)
    for block in range(kept.shape[0]):
        total[block] = np.sqrt((kept[block] ** 2).sum() / kept[block].size)
    return total


def independent_bootstrap(difference, *, seed, lower_quantile, upper_quantile, draws):
    generator = np.random.default_rng(int(seed))
    count = difference.size
    samples = generator.integers(0, count, size=(int(draws), count))
    means = difference[samples].mean(axis=1)
    return {
        "point_estimate": float(difference.mean()),
        "block_standard_deviation": float(difference.std(ddof=1)),
        "lower": float(np.quantile(means, lower_quantile)),
        "upper": float(np.quantile(means, upper_quantile)),
    }


# Criterion note (recorded 2026-08-14, after the first verification attempt).
#
# The first version of this file demanded BIT-IDENTICAL agreement from a
# deliberately INDEPENDENT reimplementation.  That is self-contradictory: a
# different-but-correct summation order differs in the last bits, so bit-identity
# can only be met by copying the runner's exact operation sequence, which destroys
# the independence the check exists to provide.  Observed discrepancies were about
# 1e-17 on values of about 7e-2, i.e. roughly two units in the last place.
#
# Exact equality is retained where it IS the right criterion - replaying the same
# computation (regenerated inputs, fixed-arm rollout, file hashes).  For the
# independently reimplemented statistics the criterion is DECISION INVARIANCE:
# the discrepancy must be negligible in relative terms AND every decision margin
# must exceed the discrepancy by a large factor, so no discrepancy of this size
# could flip any gate.  Loosening did not rescue a failing result: the primary
# endpoint fails under both the runner's numbers and the verifier's.
RELATIVE_AGREEMENT_TOLERANCE = 1e-9
DECISION_MARGIN_SAFETY_FACTOR = 1e6


def compare(label, produced, expected, failures, discrepancies):
    for key, value in produced.items():
        reference = expected[key]
        absolute = abs(value - reference)
        scale = max(abs(value), abs(reference), 1e-300)
        discrepancies.append(absolute)
        if absolute / scale > RELATIVE_AGREEMENT_TOLERANCE:
            failures.append(
                f"{label}.{key}: verifier={value!r} saved={reference!r} "
                f"relative difference {absolute / scale:.3e}"
            )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-dir", type=Path, default=Path(f"results/23_hbv_multilead_joint_uncertainty/{_runner.EXPERIMENT_ID}"))
    arguments = parser.parse_args()
    run_dir = arguments.run_dir
    failures: list[str] = []

    report = json.loads((run_dir / "metrics.json").read_text(encoding="utf-8"))
    saved = report["metrics"]
    bootstrap = report["configuration"]["bootstrap"]
    draws = int(bootstrap["draws"])
    arrays = np.load(run_dir / "evaluation_arrays.npz")

    # ---------------- check 1: independent semantic recomputation ----------------
    truth = arrays["truth_states"]
    scales = truth.std(axis=(0, 1))
    keep = scales > 1e-8
    safe = np.where(keep, scales, 1.0)
    if int(keep.sum()) != saved["scored_state_count"]:
        failures.append(f"scored_state_count: verifier={int(keep.sum())} saved={saved['scored_state_count']}")

    seeds = report["configuration"]["history_seeds"]
    members = [f"history_seed_{seed}" for seed in seeds]
    discrepancies: list[float] = []
    rmse = {
        name: independent_per_block_rmse(arrays[f"{name}__global_states"], truth, safe, keep)
        for name in ("fixed", "static", *members)
    }
    for name, values in rmse.items():
        saved_values = np.asarray(saved["per_block_rmse"][name], dtype=np.float64)
        relative = float(np.abs(values - saved_values).max() / max(float(np.abs(saved_values).max()), 1e-300))
        discrepancies.append(float(np.abs(values - saved_values).max()))
        if relative > RELATIVE_AGREEMENT_TOLERANCE:
            failures.append(f"per_block_rmse[{name}]: relative difference {relative:.3e}")

    history_mean = np.mean([rmse[name] for name in members], axis=0)
    saved_mean = np.asarray(saved["history_seed_mean_per_block_rmse"], dtype=np.float64)
    mean_relative = float(np.abs(history_mean - saved_mean).max() / max(float(np.abs(saved_mean).max()), 1e-300))
    discrepancies.append(float(np.abs(history_mean - saved_mean).max()))
    if mean_relative > RELATIVE_AGREEMENT_TOLERANCE:
        failures.append(f"history_seed_mean_per_block_rmse: relative difference {mean_relative:.3e}")

    primary_saved = saved["primary_endpoint"]
    anchor = independent_bootstrap(
        rmse["fixed"] - rmse["static"],
        seed=bootstrap["anchor_G"], lower_quantile=0.025, upper_quantile=0.975, draws=draws,
    )
    compare("anchor_G", anchor, primary_saved["anchor_G_fixed_minus_static"], failures, discrepancies)

    branch_a = anchor["point_estimate"] > 0.0 and anchor["lower"] > 0.0
    branch = "A" if branch_a else "B"
    if branch != primary_saved["branch"]:
        failures.append(f"branch: verifier={branch} saved={primary_saved['branch']}")
    threshold = 0.5 * anchor["point_estimate"] if branch_a else 0.05 * float(rmse["static"].mean())
    discrepancies.append(abs(threshold - primary_saved["threshold_T"]))
    if abs(threshold - primary_saved["threshold_T"]) / max(abs(threshold), 1e-300) > RELATIVE_AGREEMENT_TOLERANCE:
        failures.append(f"threshold_T: verifier={threshold!r} saved={primary_saved['threshold_T']!r}")

    primary = independent_bootstrap(
        rmse["static"] - history_mean,
        seed=bootstrap["primary_H"], lower_quantile=0.0125, upper_quantile=0.9875, draws=draws,
    )
    compare("H_static_minus_history", primary, primary_saved["H_static_minus_history_seed_mean"], failures, discrepancies)

    # Decision invariance: no gate may sit closer to its boundary than the observed
    # numerical discrepancy, multiplied by a large safety factor.
    worst_discrepancy = max(discrepancies)
    margins = {
        "threshold_margin": abs(primary["point_estimate"] - threshold),
        "interval_zero_margin": abs(primary["lower"]),
        "anchor_branch_margin": abs(anchor["lower"]),
    }
    for name, margin in margins.items():
        if margin <= worst_discrepancy * DECISION_MARGIN_SAFETY_FACTOR:
            failures.append(
                f"decision invariance {name}: margin {margin:.3e} is not safely above "
                f"the numerical discrepancy {worst_discrepancy:.3e}"
            )

    passed = bool(primary["lower"] > 0.0 and primary["point_estimate"] >= threshold)
    if passed != primary_saved["passed"]:
        failures.append(f"primary passed: verifier={passed} saved={primary_saved['passed']}")
    expected_decision = "H18_STATE_UPDATE_PASS" if passed else "H18_STATE_UPDATE_HOLD_H18F_PRESPECIFIED"
    if expected_decision != report["decision"]:
        failures.append(f"decision: verifier={expected_decision} saved={report['decision']}")

    # ---------------- check 2: fixed-arm replay at the runner's batch shape ------
    estimator = _runner.build_estimator()
    evaluation_batch = _runner.generate_split("evaluation", int(report["configuration"]["evaluation_blocks"]))
    observable = evaluation_batch.as_observable()
    for name in ("forcing", "observations", "initial_states", "initial_covariances"):
        regenerated = getattr(observable, name).numpy()
        if name in ("forcing", "observations"):
            regenerated = regenerated[:, : _runner.DAYS]
        if not np.array_equal(regenerated.astype("<f8"), arrays[name]):
            failures.append(f"regenerated {name} does not match the saved array bit-for-bit")
    with torch.no_grad():
        replay = _runner.rollout(
            observable, _runner.FixedTransitionNetwork(), estimator,
            days=_runner.DAYS, collect=True,
        )
    difference = float(
        np.abs(replay["global_states"].numpy().astype("<f8") - arrays["fixed__global_states"]).max()
    )
    if not difference <= REPLAY_TOLERANCE:
        failures.append(f"fixed-arm replay max abs difference {difference:.3e} exceeds {REPLAY_TOLERANCE:.0e}")

    # ---------------- check 3: file integrity -----------------------------------
    checksums = json.loads((run_dir / "checksums.json").read_text(encoding="utf-8"))
    present = {path.name for path in run_dir.iterdir() if path.is_file()}
    uncovered = sorted(present - set(checksums) - {"checksums.json"})
    for name, expected_hash in checksums.items():
        path = run_dir / name
        if not path.is_file():
            failures.append(f"checksummed file missing: {name}")
            continue
        digest = sha256()
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
        if digest.hexdigest() != expected_hash:
            failures.append(f"checksum mismatch: {name}")

    verification = {
        "experiment_id": report["experiment_id"],
        "independent_semantic_recomputation_passed": not any(
            item.startswith(("per_block_rmse", "anchor_G", "H_static", "branch", "threshold", "primary", "decision", "scored_state_count", "history_seed_mean"))
            for item in failures
        ),
        "fixed_arm_replay_max_abs_difference": difference,
        "fixed_arm_replay_tolerance": REPLAY_TOLERANCE,
        "fixed_arm_replay_batch_shape": list(observable.forcing.shape[:1]) + [_runner.DAYS],
        "replay_batch_shape_matches_runner": True,
        "semantic_criterion": (
            "independent reimplementation compared by relative tolerance plus decision "
            "invariance, not bit-identity; see the criterion note in this script"
        ),
        "relative_agreement_tolerance": RELATIVE_AGREEMENT_TOLERANCE,
        "worst_absolute_discrepancy": worst_discrepancy,
        "decision_margins": margins,
        "checksums_verified": sum(1 for _ in checksums),
        "files_outside_the_checksummed_set": uncovered,
        "failures": failures,
        "all_verified": not failures,
        "verified_decision": report["decision"],
    }
    (run_dir / "independent_verification.json").write_text(
        json.dumps(verification, indent=2, sort_keys=True), encoding="utf-8"
    )
    print(json.dumps({k: v for k, v in verification.items() if k != "failures"}, indent=2))
    if failures:
        print("FAILURES:")
        for item in failures:
            print(f"  - {item}")
    print(f"wrote {run_dir / 'independent_verification.json'}")
    raise SystemExit(0 if not failures else 1)


if __name__ == "__main__":
    main()

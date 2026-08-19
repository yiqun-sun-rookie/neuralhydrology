"""Independent verification of the H19 forecast evidence layer.

Contract section 7.1.  The semantic criterion is relative tolerance plus
DECISION INVARIANCE, not bit identity: a deliberately independent
reimplementation must be allowed a different summation order.  Bit identity is
kept where it is the correct criterion:

  * every file digest in checksums.json must match the file on disk exactly;
  * every restored checkpoint must be bit-identical to the H18 source
    checkpoint, which is what proves that no training occurred in this layer;
  * the evaluation seed namespace must be disjoint from H18.

The decisive numbers are recomputed from the RAW saved forecasts, never from the
runner summary.  The runner accumulated squared error day by day inside the
assimilation loop; this verifier instead loads the stored forecast array and the
stored truth array and rebuilds the per-block RMSE, the seed mean, the paired
difference, the bootstrap and the decision from scratch.
"""

from __future__ import annotations

import argparse
from hashlib import sha256
import json
import math
from pathlib import Path

import numpy as np
import torch

EXPERIMENT_ID = "h19_forecast_evidence_layer_v01"
SOURCE_EXPERIMENT_ID = "h18_observation_only_state_update_v01"
RELATIVE_TOLERANCE = 1e-9
PRIMARY_LEAD = 7
ARMS = (
    "fixed",
    "static",
    "history_seed_1810101",
    "history_seed_1810102",
    "history_seed_1810103",
)
HISTORY_ARMS = ARMS[2:]
SOURCE_CHECKPOINTS = {
    "static": "static_best_checkpoint.pt",
    "history_seed_1810101": "history_seed_1810101_best_checkpoint.pt",
    "history_seed_1810102": "history_seed_1810102_best_checkpoint.pt",
    "history_seed_1810103": "history_seed_1810103_best_checkpoint.pt",
}


def relative_agreement(left: float, right: float) -> float:
    scale = max(abs(left), abs(right), 1e-300)
    return abs(left - right) / scale


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--run-dir",
        type=Path,
        default=Path(f"results/23_hbv_multilead_joint_uncertainty/{EXPERIMENT_ID}"),
    )
    parser.add_argument(
        "--source-dir",
        type=Path,
        default=Path(
            f"results/23_hbv_multilead_joint_uncertainty/{SOURCE_EXPERIMENT_ID}"
        ),
    )
    arguments = parser.parse_args()
    run_dir = arguments.run_dir
    failures: list[str] = []

    metrics = json.loads((run_dir / "metrics.json").read_text(encoding="utf-8"))
    stored_checksums = json.loads(
        (run_dir / "checksums.json").read_text(encoding="utf-8")
    )
    arrays = np.load(run_dir / "evaluation_arrays.npz")

    # ---- bit identity where it belongs: file digests -------------------------
    digest_mismatches = []
    for name, digest in stored_checksums.items():
        path = run_dir / name
        if not path.exists():
            digest_mismatches.append(f"{name}: missing")
            continue
        if sha256(path.read_bytes()).hexdigest() != digest:
            digest_mismatches.append(f"{name}: digest changed")
    uncovered = sorted(
        path.name
        for path in run_dir.iterdir()
        if path.name not in stored_checksums and path.name != "checksums.json"
    )
    if digest_mismatches:
        failures.append(f"file digests: {digest_mismatches}")

    # ---- bit identity: no training happened ---------------------------------
    checkpoint_identical: dict[str, bool] = {}
    for arm, source_name in SOURCE_CHECKPOINTS.items():
        restored = torch.load(run_dir / f"{arm}_restored_checkpoint.pt", map_location="cpu")
        source = torch.load(arguments.source_dir / source_name, map_location="cpu")
        same = sorted(restored) == sorted(source) and all(
            torch.equal(restored[key], source[key]) for key in source
        )
        checkpoint_identical[arm] = bool(same)
        if not same:
            failures.append(f"{arm}: restored weights differ from the H18 checkpoint")
    normalizer_present = {
        arm: bool(
            "feature_mean" in torch.load(run_dir / f"{arm}_restored_checkpoint.pt", map_location="cpu")
        )
        for arm in HISTORY_ARMS
    }
    if not all(normalizer_present.values()):
        failures.append("a history checkpoint lacks the feature normalizer buffers")

    # ---- seed namespace disjointness ----------------------------------------
    namespace = int(metrics["configuration"]["seed_namespace_base"])
    namespace_disjoint = namespace != 21_000_000_000
    if not namespace_disjoint:
        failures.append("evaluation namespace collides with H18")

    # ---- structural: this layer must not train ------------------------------
    zero_training = (
        metrics.get("training_performed") is False
        and metrics.get("optimizer_created") is False
        and metrics.get("backward_passes") == 0
    )
    if not zero_training:
        failures.append("metrics do not assert zero training")

    # ---- independent recomputation from the raw arrays ----------------------
    truth = arrays["truth_discharge_at_primary_lead"]
    recomputed: dict[str, np.ndarray] = {}
    worst_rmse_disagreement = 0.0
    for arm in ARMS:
        forecast = arrays[f"{arm}_primary_forecast"]
        if forecast.shape != truth.shape:
            failures.append(f"{arm}: forecast and truth shapes disagree")
            continue
        # Deliberately DIFFERENT numerical path from the runner. The runner
        # accumulated squared error into an array and reduced it with the numpy
        # pairwise mean. Here each block is reduced with exact summation, which
        # is a different algorithm and must therefore differ in the last bits.
        # If this produced bit-identical output it would prove the two paths are
        # the same computation, which is exactly what an independent check must
        # not be.
        squared = (forecast - truth) ** 2
        independent = np.array(
            [
                math.sqrt(math.fsum(row) / row.size)
                for row in squared
            ],
            dtype=np.float64,
        )
        stored = arrays[f"{arm}_rmse_evolving_lead_{PRIMARY_LEAD}"]
        recomputed[arm] = independent
        worst = float(
            np.max(
                np.abs(independent - stored)
                / np.maximum(np.abs(stored), 1e-300)
            )
        )
        worst_rmse_disagreement = max(worst_rmse_disagreement, worst)
    if worst_rmse_disagreement > RELATIVE_TOLERANCE:
        failures.append(
            f"per-block RMSE disagreement {worst_rmse_disagreement:.3e} exceeds tolerance"
        )

    history_mean = np.mean([recomputed[arm] for arm in HISTORY_ARMS], axis=0)
    difference = recomputed["static"] - history_mean
    point = float(difference.mean())

    bootstrap = metrics["configuration"]["bootstrap"]
    generator = np.random.default_rng(int(bootstrap["primary"]))
    samples = generator.integers(0, difference.size, size=(int(bootstrap["draws"]), difference.size))
    means = difference[samples].mean(axis=1)
    lower = float(np.quantile(means, 0.025))
    upper = float(np.quantile(means, 0.975))

    reported = metrics["primary_endpoint"]
    point_agreement = relative_agreement(point, float(reported["point_estimate"]))
    lower_agreement = relative_agreement(lower, float(reported["lower"]))
    upper_agreement = relative_agreement(upper, float(reported["upper"]))
    worst_agreement = max(point_agreement, lower_agreement, upper_agreement)
    if worst_agreement > RELATIVE_TOLERANCE:
        failures.append(f"primary endpoint disagreement {worst_agreement:.3e} exceeds tolerance")

    threshold = float(metrics["frozen_before_this_run"]["threshold"])
    independent_interval_met = bool((lower > 0.0 or upper < 0.0) and point > 0.0)
    independent_threshold_met = bool(point >= threshold)
    independent_decision = (
        "H19_FORECAST_EVIDENCE_PASS"
        if (independent_interval_met and independent_threshold_met)
        else (
            "H19_FORECAST_NO_DISTINGUISHABLE_EFFECT"
            if not independent_interval_met
            else "H19_FORECAST_BELOW_PREREGISTERED_THRESHOLD"
        )
    )
    decision_invariant = independent_decision == reported["decision"]
    if not decision_invariant:
        failures.append(
            f"decision differs: independent {independent_decision} versus reported {reported['decision']}"
        )

    # decision margins: how far the verdict is from flipping
    margins = {
        "distance_to_threshold": float(point - threshold),
        "distance_of_interval_to_zero": float(min(abs(lower), abs(upper)) if (lower > 0 or upper < 0) else 0.0),
    }
    smallest_margin = min(abs(margins["distance_to_threshold"]), abs(margins["distance_of_interval_to_zero"]))

    all_verified = not failures
    report = {
        "experiment_id": EXPERIMENT_ID,
        "all_verified": all_verified,
        "failures": failures,
        "semantic_criterion": (
            "independent recomputation from the raw saved forecast arrays, "
            "compared by relative tolerance plus decision invariance, not bit "
            "identity"
        ),
        "relative_agreement_tolerance": RELATIVE_TOLERANCE,
        "worst_per_block_rmse_relative_disagreement": worst_rmse_disagreement,
        "worst_primary_endpoint_relative_disagreement": worst_agreement,
        "independent_primary_endpoint": {
            "point_estimate": point,
            "lower": lower,
            "upper": upper,
            "interval_criterion_met": independent_interval_met,
            "threshold_criterion_met": independent_threshold_met,
            "decision": independent_decision,
        },
        "reported_primary_endpoint": {
            "point_estimate": float(reported["point_estimate"]),
            "lower": float(reported["lower"]),
            "upper": float(reported["upper"]),
            "decision": reported["decision"],
        },
        "decision_invariant": decision_invariant,
        "decision_margins": margins,
        "smallest_decision_margin": smallest_margin,
        "margin_over_worst_disagreement": (
            float(smallest_margin / worst_agreement) if worst_agreement > 0.0 else None
        ),
        "bit_identity_checks": {
            "file_digests_all_match": not digest_mismatches,
            "files_outside_the_checksummed_set": uncovered,
            "restored_checkpoints_identical_to_h18": checkpoint_identical,
            "history_normalizer_buffers_present": normalizer_present,
        },
        "zero_training_asserted_and_structurally_consistent": bool(
            zero_training and all(checkpoint_identical.values())
        ),
        "evaluation_namespace_disjoint_from_h18": namespace_disjoint,
        "claim_boundary": (
            "Verification of computation only. It says nothing about whether the "
            "scientific claim generalises beyond this synthetic ideal twin."
        ),
    }
    (run_dir / "independent_verification.json").write_text(
        json.dumps(report, indent=2, sort_keys=True), encoding="utf-8"
    )
    print(json.dumps(report, indent=2, sort_keys=True))
    if not all_verified:
        raise SystemExit(1)


if __name__ == "__main__":
    main()

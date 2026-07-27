"""Post-hoc comparability sensitivity audit for the five frozen candidates."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Mapping

import numpy as np
import pandas as pd

from train_equal_experts_v06 import _atomic_frame, _atomic_text, _sha256
from train_v05 import validate_frozen_file_hash


_REPO = Path(__file__).resolve().parents[2]
_EXPECTED = {
    "audit_id": "A06-COMPARABILITY",
    "audit_type": "posthoc_sensitivity_not_preregistered_candidate_gate",
    "practical_equivalence_margin": 0.01,
    "bootstrap_resamples": 100_000,
    "bootstrap_seed": 20_260_727,
    "bootstrap_unit": "basin",
    "confidence_interval": [0.025, 0.975],
    "results_root": "results/26_historical_band_experts/comparability_audit_v06",
    "formal_evaluation_access": False,
}
_INPUT_EXPECTED = (
    (1, "joint_equal_experts", 1, "c34f3c2b3d27aca05f2f42f0412a16f4d430bf6950a0c9d67e187c32d38e4a7a"),
    (2, "frozen_recent_output_residual", 1, "4080183785ce39e51db966568d5422fcb1f39211ec3b459bb749f85e13f2307e"),
    (3, "frozen_recent_history_state", 1, "c5aaae25f7fe9c4b13fe99676efd0e14361080ab4a75bd6c80ed285f11e0698b"),
    (4, "two_seed_late_concat_ensemble", 2, "9469c28742ecfcf316e480249671dc6765bb6969ff311ef597f89589296976d9"),
    (5, "three_seed_late_concat_ensemble", 3, "6c247441749f38df87bc15166629288a17199a6a84a9b08e99ab555439b6e834"),
)


def validate_comparability_audit_config_v06(config: Mapping) -> None:
    for key, expected in _EXPECTED.items():
        if config.get(key) != expected:
            raise ValueError(f"{key} must be frozen at {expected!r}, got {config.get(key)!r}")
    inputs = config.get("inputs")
    if not isinstance(inputs, list) or len(inputs) != 5:
        raise ValueError("inputs must contain the five frozen candidate iterations")
    actual = tuple(
        (
            int(item.get("iteration", -1)),
            item.get("label"),
            int(item.get("candidate_training_seed_count", -1)),
            item.get("sha256"),
        )
        for item in inputs
    )
    if actual != _INPUT_EXPECTED:
        raise ValueError("inputs differ from the frozen comparability audit definition")


def bootstrap_median_ci_v06(
    delta: np.ndarray,
    n_resamples: int,
    seed: int,
) -> tuple[float, float]:
    values = np.asarray(delta, dtype=np.float64)
    if values.ndim != 1 or len(values) == 0 or not np.isfinite(values).all():
        raise ValueError("delta must be a nonempty finite one-dimensional array")
    if int(n_resamples) <= 0:
        raise ValueError("n_resamples must be positive")
    generator = np.random.default_rng(int(seed))
    medians = []
    remaining = int(n_resamples)
    while remaining:
        count = min(10_000, remaining)
        indices = generator.integers(0, len(values), size=(count, len(values)))
        medians.append(np.median(values[indices], axis=1))
        remaining -= count
    samples = np.concatenate(medians)
    lower, upper = np.quantile(samples, [0.025, 0.975])
    return float(lower), float(upper)


def audit_candidate_v06(
    paired: pd.DataFrame,
    margin: float,
    bootstrap_resamples: int,
    bootstrap_seed: int,
    candidate_training_seed_count: int,
) -> dict:
    required = {"basin", "nse_classic", "nse_candidate"}
    if not required.issubset(paired.columns):
        raise ValueError("paired metrics lack required columns")
    if len(paired) != 60 or paired["basin"].astype(str).nunique() != 60:
        raise ValueError("paired metrics must contain 60 unique basins")
    delta = (
        paired["nse_candidate"].to_numpy(dtype=np.float64)
        - paired["nse_classic"].to_numpy(dtype=np.float64)
    )
    lower, upper = bootstrap_median_ci_v06(
        delta,
        n_resamples=int(bootstrap_resamples),
        seed=int(bootstrap_seed),
    )
    median = float(np.median(delta))
    practical_equivalence = bool(lower > -float(margin) and upper < float(margin))
    if practical_equivalence and int(candidate_training_seed_count) == 1:
        interpretation = "posthoc_equivalent_single_training_seed_only"
    elif practical_equivalence:
        interpretation = "posthoc_equivalent_across_ensemble_members"
    else:
        interpretation = "posthoc_equivalence_not_supported"
    return {
        "n_basins": int(len(delta)),
        "candidate_training_seed_count": int(candidate_training_seed_count),
        "median_delta_classic": median,
        "bootstrap_median_ci95": [lower, upper],
        "superiority_delta_at_least_0_01": bool(median >= 0.01),
        "posthoc_noninferior_to_minus_0_01": bool(lower > -float(margin)),
        "posthoc_practical_equivalence_within_plus_minus_0_01": practical_equivalence,
        "fraction_abs_delta_within_margin": float(np.mean(np.abs(delta) <= float(margin))),
        "n_delta_below_minus_margin": int(np.sum(delta < -float(margin))),
        "n_delta_above_plus_margin": int(np.sum(delta > float(margin))),
        "delta_quantiles_10_50_90": [
            float(value) for value in np.quantile(delta, [0.1, 0.5, 0.9])
        ],
        "interpretation": interpretation,
    }


def run_comparability_audit_v06(config: Mapping) -> dict:
    validate_comparability_audit_config_v06(config)
    root = _REPO / config["results_root"]
    if root.exists() and any(root.iterdir()):
        raise FileExistsError(f"output directory is not empty: {root}")
    root.mkdir(parents=True, exist_ok=True)
    results = []
    rows = []
    for item in config["inputs"]:
        path = _REPO / item["paired_file"]
        validate_frozen_file_hash(path, item["sha256"], f"iteration {item['iteration']} paired metrics")
        paired = pd.read_csv(path, dtype={"basin": str})
        result = audit_candidate_v06(
            paired,
            margin=float(config["practical_equivalence_margin"]),
            bootstrap_resamples=int(config["bootstrap_resamples"]),
            bootstrap_seed=int(config["bootstrap_seed"]) + int(item["iteration"]),
            candidate_training_seed_count=int(item["candidate_training_seed_count"]),
        )
        result.update({
            "iteration": int(item["iteration"]),
            "label": item["label"],
            "paired_file_sha256": item["sha256"],
        })
        results.append(result)
        rows.append({
            "iteration": result["iteration"],
            "label": result["label"],
            "candidate_training_seed_count": result["candidate_training_seed_count"],
            "median_delta_classic": result["median_delta_classic"],
            "ci95_lower": result["bootstrap_median_ci95"][0],
            "ci95_upper": result["bootstrap_median_ci95"][1],
            "fraction_abs_delta_within_margin": result["fraction_abs_delta_within_margin"],
            "posthoc_practical_equivalence": result[
                "posthoc_practical_equivalence_within_plus_minus_0_01"
            ],
            "interpretation": result["interpretation"],
        })
    iteration_two = next(result for result in results if result["iteration"] == 2)
    iteration_three = next(result for result in results if result["iteration"] == 3)
    summary = {
        "status": "complete",
        "audit_id": config["audit_id"],
        "audit_type": config["audit_type"],
        "practical_equivalence_margin": float(config["practical_equivalence_margin"]),
        "candidate_results": results,
        "minimum_internal_comparability_supported_single_seed": bool(
            iteration_two["posthoc_practical_equivalence_within_plus_minus_0_01"]
            and iteration_three["posthoc_practical_equivalence_within_plus_minus_0_01"]
        ),
        "stable_multiseed_superiority_supported": False,
        "formal_evaluation_access": False,
        "limitations": [
            "equivalence margin was not preregistered before candidate evaluation",
            "equal-width expert candidates were evaluated with one training seed",
            "all comparisons use the same internal validation period",
        ],
    }
    _atomic_frame(root / "per_candidate.csv", pd.DataFrame(rows))
    _atomic_text(root / "summary.json", json.dumps(summary, indent=2, sort_keys=True))
    artifact_names = ("per_candidate.csv", "summary.json")
    manifest = {
        "status": "complete",
        "audit_id": config["audit_id"],
        "inputs": {
            item["paired_file"]: item["sha256"]
            for item in config["inputs"]
        },
        "data_access": {
            "paired_metric_artifacts_only": True,
            "raw_observed_discharge_reads": 0,
            "formal_evaluation_access": False,
        },
        "artifacts": {
            name: _sha256(root / name)
            for name in artifact_names
        },
    }
    _atomic_text(root / "manifest.json", json.dumps(manifest, indent=2, sort_keys=True))
    return summary


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, required=True)
    args = parser.parse_args()
    config = json.loads(args.config.read_text(encoding="utf-8"))
    print(json.dumps(run_comparability_audit_v06(config), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()

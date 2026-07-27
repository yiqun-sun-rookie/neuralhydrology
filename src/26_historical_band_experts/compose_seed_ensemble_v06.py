"""Compose and score the preregistered two-seed late-concatenation ensemble."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Mapping, Sequence

import numpy as np
import pandas as pd

from analyze_frozen_residual_v06 import (
    _assert_same_targets,
    _load_predictions,
    _named_nse_v06,
    evaluate_stage1_frozen_residual_v06,
)
from train_equal_experts_v06 import _atomic_frame, _atomic_text, _sha256
from train_v05 import validate_frozen_file_hash


_REPO = Path(__file__).resolve().parents[2]
_EXPECTED = {
    "experiment_id": "E06-I04",
    "experiment_family": "late_concat_seed_ensemble_i04_v06",
    "candidate_iteration": 4,
    "candidate_iteration_budget": 5,
    "mode": "pilot",
    "iteration_three_summary_sha256": "0379dad25f085c447bf39503b1aeb4408f867c908cdd6ec9d6dc2ae7da7a146e",
    "ensemble_operation": "rowwise_arithmetic_mean_qsim",
    "member_seeds": [200, 300],
    "member_weights": [0.5, 0.5],
    "discovery_seed_excluded": 100,
    "legacy_late_concat_predictions_sha256": "dc67277dd9302e7fe5985728a87d82178de1029a9f2bab123a3cbe72d5807941",
    "stage1_gates": {
        "median_delta_classic_at_least": 0.01,
        "median_delta_capacity_above": 0.0,
        "median_delta_late_concat_above": 0.0,
        "win_fraction_classic_at_least": 0.55,
    },
    "formal_evaluation_access": False,
}
_MEMBER_EXPECTED = {
    "candidate_members": (
        (200, 0.5, "034b39bc6f376a15d1fcaee3cffdd00c3e2d15f1cdf18743fcf0a756ba4e16b0"),
        (300, 0.5, "9389ea15cfd90fc000b7d7170ce2223c6475391e39314f66103c6c5057bf3a3e"),
    ),
    "classic_members": (
        (200, 0.5, "dfd025110659d0b8df5684aa566a9a1a43013a704f73cf3cfeeb6c2e2429c6f9"),
        (300, 0.5, "7558b1ca940168a60d5756e1154cf48c46603019970de7bde660c30fbad55591"),
    ),
    "capacity_members": (
        (200, 0.5, "1183ee7b5bdf30596df00728d63e0141729b0cb820bcda205775bd14faa26def"),
        (300, 0.5, "b40bc1048e2f275d0c50eaf51618c81bf25d95ca802d440bcafe30b12539d7ee"),
    ),
}


def validate_seed_ensemble_config_v06(config: Mapping) -> None:
    for key, expected in _EXPECTED.items():
        if config.get(key) != expected:
            raise ValueError(f"{key} must be frozen at {expected!r}, got {config.get(key)!r}")
    if not str(config.get("results_root", "")).endswith("late_concat_seed_ensemble_i04_v06"):
        raise ValueError("results_root must be isolated for seed-ensemble iteration 4")
    for group, expected_rows in _MEMBER_EXPECTED.items():
        members = config.get(group)
        if not isinstance(members, list) or len(members) != 2:
            raise ValueError(f"{group} must contain two frozen members")
        actual_rows = tuple(
            (int(member.get("seed", -1)), float(member.get("weight", -1)), member.get("sha256"))
            for member in members
        )
        if actual_rows != expected_rows:
            raise ValueError(f"{group} members differ from the frozen definition")


def compose_prediction_frames_v06(
    frames: Sequence[pd.DataFrame],
    weights: Sequence[float],
) -> pd.DataFrame:
    if len(frames) != len(weights) or not frames:
        raise ValueError("frames and weights must have the same nonzero length")
    if not np.isclose(float(sum(weights)), 1.0, rtol=0.0, atol=1e-15):
        raise ValueError("ensemble weights must sum to one")
    ordered = [
        frame.sort_values(["basin", "date"]).reset_index(drop=True)
        for frame in frames
    ]
    reference = ordered[0]
    expected_columns = ["basin", "date", "qobs", "qsim"]
    if list(reference.columns) != expected_columns:
        raise ValueError("prediction columns are invalid")
    for index, frame in enumerate(ordered[1:], start=1):
        if list(frame.columns) != expected_columns:
            raise ValueError(f"prediction columns are invalid for member {index}")
        if not frame[["basin", "date"]].equals(reference[["basin", "date"]]):
            raise ValueError("ensemble member keys differ")
        if not np.array_equal(frame["qobs"].to_numpy(), reference["qobs"].to_numpy()):
            raise ValueError("ensemble member observations differ")
    qsim = np.zeros(len(reference), dtype=np.float64)
    for frame, weight in zip(ordered, weights):
        qsim += float(weight) * frame["qsim"].to_numpy(dtype=np.float64)
    result = reference[["basin", "date", "qobs"]].copy()
    result["qsim"] = qsim
    return result


def _load_member_group(config: Mapping, group: str) -> pd.DataFrame:
    frames = []
    weights = []
    for member in config[group]:
        path = _REPO / member["predictions"]
        validate_frozen_file_hash(path, member["sha256"], f"{group} seed {member['seed']}")
        frames.append(_load_predictions(path))
        weights.append(float(member["weight"]))
    return compose_prediction_frames_v06(frames, weights)


def run_seed_ensemble_v06(config: Mapping) -> dict:
    validate_seed_ensemble_config_v06(config)
    validate_frozen_file_hash(
        _REPO / config["iteration_three_summary"],
        config["iteration_three_summary_sha256"],
        "iteration-three summary",
    )
    validate_frozen_file_hash(
        _REPO / config["legacy_late_concat_predictions"],
        config["legacy_late_concat_predictions_sha256"],
        "legacy late-concat predictions",
    )
    root = _REPO / config["results_root"]
    if root.exists() and any(root.iterdir()):
        raise FileExistsError(f"output directory is not empty: {root}")
    root.mkdir(parents=True, exist_ok=True)

    ensembles = {
        "candidate": _load_member_group(config, "candidate_members"),
        "classic": _load_member_group(config, "classic_members"),
        "capacity": _load_member_group(config, "capacity_members"),
    }
    legacy = _load_predictions(_REPO / config["legacy_late_concat_predictions"])
    reference = ensembles["classic"]
    for name, frame in {**ensembles, "late_concat": legacy}.items():
        _assert_same_targets(reference, frame, name)
    for name, frame in ensembles.items():
        _atomic_frame(root / f"{name}_predictions.csv", frame)

    metrics = {
        name: _named_nse_v06(frame, name)
        for name, frame in {**ensembles, "late_concat": legacy}.items()
    }
    paired = metrics["classic"]
    for name in ("capacity", "late_concat", "candidate"):
        paired = paired.merge(metrics[name], on="basin", how="inner", validate="one_to_one")
    paired = paired.sort_values("basin").reset_index(drop=True)
    if len(paired) != 60:
        raise ValueError(f"paired basin count must be 60, got {len(paired)}")
    stage1 = evaluate_stage1_frozen_residual_v06(paired, config["stage1_gates"])
    median_nse = {
        name: float(np.nanmedian(frame[f"nse_{name}"]))
        for name, frame in metrics.items()
    }
    passed = bool(stage1["passed"])
    summary = {
        "status": (
            "complete_internal_seed_confirmation_pass"
            if passed
            else "complete_internal_seed_confirmation_no_go"
        ),
        "evidence_scope": "same_validation_period_new_training_seeds",
        "discovery_seed_excluded": int(config["discovery_seed_excluded"]),
        "member_seeds": list(config["member_seeds"]),
        "median_nse": median_nse,
        "stage1": stage1,
        "formal_evaluation_access": False,
    }
    _atomic_frame(root / "paired_per_basin.csv", paired)
    _atomic_text(root / "summary.json", json.dumps(summary, indent=2, sort_keys=True))
    artifact_names = (
        "candidate_predictions.csv",
        "classic_predictions.csv",
        "capacity_predictions.csv",
        "paired_per_basin.csv",
        "summary.json",
    )
    manifest = {
        "status": "complete",
        "experiment_id": config["experiment_id"],
        "experiment_family": config["experiment_family"],
        "candidate_iteration": int(config["candidate_iteration"]),
        "member_seeds": list(config["member_seeds"]),
        "member_weights": list(config["member_weights"]),
        "ensemble_operation": config["ensemble_operation"],
        "n_validation_predictions": 43_860,
        "data_access": {
            "raw_observed_discharge_reads": 0,
            "prediction_artifacts_only": True,
            "formal_evaluation_access": False,
        },
        "artifacts": {name: _sha256(root / name) for name in artifact_names},
    }
    _atomic_text(root / "manifest.json", json.dumps(manifest, indent=2, sort_keys=True))
    return summary


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, required=True)
    args = parser.parse_args()
    config = json.loads(args.config.read_text(encoding="utf-8"))
    print(json.dumps(run_seed_ensemble_v06(config), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()

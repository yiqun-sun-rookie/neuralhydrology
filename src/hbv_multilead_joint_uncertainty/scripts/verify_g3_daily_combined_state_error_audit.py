"""Independently recompute the daily combined-state error audit."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np


PROJECT_ROOT = Path(__file__).resolve().parents[3]
DEFAULT_RESULT = (
    PROJECT_ROOT
    / "results"
    / "23_hbv_multilead_joint_uncertainty"
    / "g3_daily_combined_state_error_audit_v01"
)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _maximum_difference(left, right) -> float:
    return float(
        np.max(
            np.abs(
                np.asarray(left, dtype=np.float64)
                - np.asarray(right, dtype=np.float64)
            )
        )
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--result-dir", type=Path, default=DEFAULT_RESULT)
    args = parser.parse_args()
    result_dir = args.result_dir.resolve()
    config = json.loads(
        (result_dir / "config_snapshot.json").read_text(encoding="utf-8")
    )
    source_path = PROJECT_ROOT / config["sealed_source"]["path"]
    if _sha256(source_path) != config["sealed_source"]["sha256"]:
        raise ValueError("sealed source SHA-256 mismatch")

    with np.load(result_dir / "evidence.npz", allow_pickle=False) as saved:
        saved_arrays = {name: saved[name].copy() for name in saved.files}
    with np.load(source_path, allow_pickle=False) as source:
        days = int(np.asarray(source["assimilation_days"]).item())
        names = tuple(str(value) for value in source["method_names"])
        states = source["method_assimilation_states"][:, :, :, :days, :5]
        truth = source["truth_states"][:, :, :days, :5]
        errors = states - truth[:, :, None, :, :]
        squared = np.square(errors)
        all_day_rmse = np.sqrt(np.mean(squared, axis=(0, 1, 3)))
        daily_rmse = np.sqrt(np.mean(squared, axis=(0, 1)))
        block_mse = np.mean(squared, axis=(1, 3))
        truth_standard_deviation = np.std(truth, axis=(0, 1, 2))
        standardized_rmse = (
            all_day_rmse / truth_standard_deviation[None, :]
        )
        primary_index = names.index(config["primary_method"])
        baseline_indices = np.asarray(
            [names.index(value) for value in config["baseline_methods"]]
        )
        block_difference = (
            block_mse[:, primary_index : primary_index + 1]
            - block_mse[:, baseline_indices]
        )
        bootstrap = saved_arrays["bootstrap_indices"]
        bootstrap_difference = np.mean(block_difference[bootstrap], axis=1)
        mean_difference = np.mean(block_difference, axis=0)
        low = np.quantile(bootstrap_difference, 0.025, axis=0)
        high = np.quantile(bootstrap_difference, 0.975, axis=0)
        relative = (
            all_day_rmse[primary_index][None, :]
            / all_day_rmse[baseline_indices]
            - 1.0
        )
        candidate_count = int(
            source["method_candidate_counts"][primary_index]
        )
        probabilities = source["method_assimilation_probabilities"][
            :, :, primary_index, :days, :candidate_count
        ]
        parameter_vectors = source["parameter_vectors"][:candidate_count]
        weighted_parameters = np.einsum(
            "btdc,cp->btdp",
            probabilities / np.sum(probabilities, axis=-1)[..., None],
            parameter_vectors,
        )

    expected = {
        "errors": errors,
        "all_day_rmse": all_day_rmse,
        "daily_rmse": daily_rmse,
        "block_mse": block_mse,
        "truth_standard_deviation": truth_standard_deviation,
        "standardized_rmse": standardized_rmse,
        "block_mse_difference": block_difference,
        "mean_mse_difference": mean_difference,
        "mse_difference_ci_low": low,
        "mse_difference_ci_high": high,
        "relative_rmse_fraction": relative,
        "posterior_probabilities": probabilities,
        "posterior_weighted_parameters": weighted_parameters,
        "parameter_vectors": parameter_vectors,
    }
    differences = {
        name: _maximum_difference(saved_arrays[name], values)
        for name, values in expected.items()
    }
    tolerance = 1e-12
    passed = all(value <= tolerance for value in differences.values())
    report = {
        "status": "passed" if passed else "failed",
        "independent_recomputation": True,
        "primary_population": "all 540 assimilation days",
        "time_since_switch_grouping_used": False,
        "tolerance": tolerance,
        "maximum_absolute_differences": differences,
        "source_sha256": _sha256(source_path),
        "evidence_sha256": _sha256(result_dir / "evidence.npz"),
    }
    (result_dir / "independent_verification.json").write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(report, indent=2))
    if not passed:
        raise SystemExit(1)


if __name__ == "__main__":
    main()

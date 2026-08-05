"""Independently verify the propagation-form comparison from source arrays."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np


PROJECT_ROOT = Path(__file__).resolve().parents[3]
DEFAULT_RESULT = (
    PROJECT_ROOT
    / "results/23_hbv_multilead_joint_uncertainty/"
    "g3_forecast_propagation_form_comparison_v01"
)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--result-dir", type=Path, default=DEFAULT_RESULT)
    args = parser.parse_args()
    result_dir = args.result_dir.resolve()
    config = json.loads((result_dir / "config_snapshot.json").read_text(encoding="utf-8"))
    deterministic_path = PROJECT_ROOT / config["sealed_deterministic_evidence"]["path"]
    historical_path = PROJECT_ROOT / config["sealed_historical_readout_evidence"]["path"]
    with np.load(result_dir / "evidence.npz", allow_pickle=False) as archive:
        saved = {name: archive[name].copy() for name in archive.files}
    with np.load(deterministic_path, allow_pickle=False) as deterministic, np.load(
        historical_path, allow_pickle=False
    ) as historical:
        methods = tuple(config["methods"])
        forecasts = (
            np.asarray(
                deterministic[
                    "forecast__posterior_all_states__posterior_weighted_parameters"
                ][:, :, 180:540],
                dtype=np.float64,
            ),
            np.asarray(
                historical[
                    "forecast__posterior_unique_complete_covariance_weighted_parameters"
                ], dtype=np.float64
            ),
            np.asarray(
                historical[
                    "forecast__posterior_unique_within_covariance_weighted_parameters"
                ], dtype=np.float64
            ),
            np.asarray(historical["forecast__current_multiple_states"], dtype=np.float64),
            np.asarray(
                historical["forecast__no_state_interaction_multiple_states"], dtype=np.float64
            ),
        )
        truth = np.asarray(historical["truth_forecasts"], dtype=np.float64)
        mask = np.asarray(historical["same_stage_mask"], dtype=bool)
        bootstrap = np.asarray(historical["bootstrap_indices"], dtype=np.int64)
    rmse = []
    block = []
    for forecast in forecasts:
        squared = np.square(forecast - truth)
        method_rmse = np.empty(7)
        method_block = np.empty((8, 7))
        for lead in range(7):
            selected = squared[:, :, mask[:, lead], lead]
            method_rmse[lead] = np.sqrt(np.mean(selected))
            method_block[:, lead] = np.mean(selected, axis=(1, 2))
        rmse.append(method_rmse)
        block.append(method_block)
    differences = {}
    for position, method in enumerate(methods):
        differences[f"forecast__{method}"] = float(
            np.max(np.abs(saved[f"forecast__{method}"] - forecasts[position]))
        )
        differences[f"rmse__{method}"] = float(
            np.max(np.abs(saved[f"rmse__{method}"] - rmse[position]))
        )
        differences[f"block_mse__{method}"] = float(
            np.max(np.abs(saved[f"block_mse__{method}"] - block[position]))
        )
    for position, baseline in enumerate(methods[1:], start=1):
        difference = block[0] - block[position]
        boot = np.mean(difference[bootstrap], axis=1)
        values = {
            "mean_mse_difference": np.mean(difference, axis=0),
            "ci_low": np.quantile(boot, 0.025, axis=0),
            "ci_high": np.quantile(boot, 0.975, axis=0),
            "relative_rmse_fraction": rmse[0] / rmse[position] - 1.0,
            "block_mse_difference": difference,
        }
        for field, value in values.items():
            key = f"comparison__deterministic__minus__{baseline}__{field}"
            differences[key] = float(np.max(np.abs(saved[key] - value)))
    passed = max(differences.values()) <= 1e-12
    report = {
        "status": "passed" if passed else "failed",
        "independent_array_recomputation": True,
        "maximum_absolute_difference": max(differences.values()),
        "differences": differences,
        "evidence_sha256": _sha256(result_dir / "evidence.npz"),
    }
    (result_dir / "independent_verification.json").write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(json.dumps(report, indent=2))
    if not passed:
        raise SystemExit(1)


if __name__ == "__main__":
    main()

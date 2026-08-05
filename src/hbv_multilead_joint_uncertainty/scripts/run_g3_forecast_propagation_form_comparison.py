"""Compare direct deterministic and historical uncertainty propagation forms."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np


PROJECT_ROOT = Path(__file__).resolve().parents[3]
DEFAULT_CONFIG = (
    PROJECT_ROOT
    / "src/hbv_multilead_joint_uncertainty/configs/"
    "g3_forecast_propagation_form_comparison_v01.json"
)
DEFAULT_OUTPUT = (
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


def _write_json(path: Path, payload) -> None:
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def _summarize(forecasts, truth, mask, bootstrap, methods):
    rmse = {}
    block_mse = {}
    for method in methods:
        squared = np.square(forecasts[method] - truth)
        rmse[method] = np.empty(7)
        block_mse[method] = np.empty((truth.shape[0], 7))
        for lead in range(7):
            selected = squared[:, :, mask[:, lead], lead]
            rmse[method][lead] = np.sqrt(np.mean(selected))
            block_mse[method][:, lead] = np.mean(selected, axis=(1, 2))
    comparisons = {}
    primary = methods[0]
    for baseline in methods[1:]:
        difference = block_mse[primary] - block_mse[baseline]
        boot = np.mean(difference[bootstrap], axis=1)
        comparisons[baseline] = {
            "mean_mse_difference": np.mean(difference, axis=0),
            "ci_low": np.quantile(boot, 0.025, axis=0),
            "ci_high": np.quantile(boot, 0.975, axis=0),
            "relative_rmse_fraction": rmse[primary] / rmse[baseline] - 1.0,
            "block_mse_difference": difference,
        }
    return rmse, block_mse, comparisons


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    config_path = args.config.resolve()
    config = json.loads(config_path.read_text(encoding="utf-8"))
    methods = tuple(config["methods"])
    if tuple(config["lead_days"]) != tuple(range(1, 8)) or len(methods) != 5:
        raise ValueError("frozen comparison contract changed")
    deterministic_path = PROJECT_ROOT / config["sealed_deterministic_evidence"]["path"]
    historical_path = PROJECT_ROOT / config["sealed_historical_readout_evidence"]["path"]
    if _sha256(deterministic_path) != config["sealed_deterministic_evidence"]["sha256"]:
        raise ValueError("deterministic evidence SHA-256 mismatch")
    if _sha256(historical_path) != config["sealed_historical_readout_evidence"]["sha256"]:
        raise ValueError("historical evidence SHA-256 mismatch")
    output_dir = args.output_dir.resolve()
    if output_dir.exists():
        raise FileExistsError(f"output directory already exists: {output_dir}")
    with np.load(deterministic_path, allow_pickle=False) as deterministic, np.load(
        historical_path, allow_pickle=False
    ) as historical:
        forecasts = {
            methods[0]: np.asarray(
                deterministic[
                    "forecast__posterior_all_states__posterior_weighted_parameters"
                ][:, :, 180:540],
                dtype=np.float64,
            ),
            methods[1]: np.asarray(
                historical[
                    "forecast__posterior_unique_complete_covariance_weighted_parameters"
                ],
                dtype=np.float64,
            ),
            methods[2]: np.asarray(
                historical[
                    "forecast__posterior_unique_within_covariance_weighted_parameters"
                ],
                dtype=np.float64,
            ),
            methods[3]: np.asarray(
                historical["forecast__current_multiple_states"], dtype=np.float64
            ),
            methods[4]: np.asarray(
                historical["forecast__no_state_interaction_multiple_states"],
                dtype=np.float64,
            ),
        }
        truth = np.asarray(historical["truth_forecasts"], dtype=np.float64)
        mask = np.asarray(historical["same_stage_mask"], dtype=bool)
        bootstrap = np.asarray(historical["bootstrap_indices"], dtype=np.int64)
        rmse, block_mse, comparisons = _summarize(
            forecasts, truth, mask, bootstrap, methods
        )
    output_dir.mkdir(parents=True)
    (output_dir / "config_snapshot.json").write_text(
        config_path.read_text(encoding="utf-8"), encoding="utf-8"
    )
    arrays = {
        "method_names": np.asarray(methods),
        "lead_days": np.arange(1, 8),
        "same_stage_mask": mask,
        "truth_forecasts": truth,
        "bootstrap_indices": bootstrap,
    }
    for method in methods:
        arrays[f"forecast__{method}"] = forecasts[method]
        arrays[f"rmse__{method}"] = rmse[method]
        arrays[f"block_mse__{method}"] = block_mse[method]
    for baseline, values in comparisons.items():
        for field, value in values.items():
            arrays[f"comparison__deterministic__minus__{baseline}__{field}"] = value
    np.savez_compressed(output_dir / "evidence.npz", **arrays)
    summary = {
        "experiment_id": config["experiment_id"],
        "classification": config["classification"],
        "status": "complete",
        "population": "origins 180 through 539 with same-stage targets",
        "rmse": {method: rmse[method].tolist() for method in methods},
        "deterministic_comparisons": {
            baseline: {
                field: value.tolist()
                for field, value in values.items()
                if field != "block_mse_difference"
            }
            for baseline, values in comparisons.items()
        },
        "scope_limit": config["scope_limit"],
    }
    _write_json(output_dir / "summary.json", summary)
    _write_json(
        output_dir / "checksums.json",
        {
            "deterministic_source_sha256": _sha256(deterministic_path),
            "historical_source_sha256": _sha256(historical_path),
            "evidence_sha256": _sha256(output_dir / "evidence.npz"),
            "summary_sha256": _sha256(output_dir / "summary.json"),
        },
    )
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()

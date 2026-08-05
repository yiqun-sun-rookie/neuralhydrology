"""Build the all-day direct combined-state error audit from sealed evidence."""

from __future__ import annotations

import argparse
import hashlib
import json
import platform
import shutil
import sys
from pathlib import Path

import numpy as np


PROJECT_ROOT = Path(__file__).resolve().parents[3]
SRC_ROOT = PROJECT_ROOT / "src"
if str(SRC_ROOT) not in sys.path:
    sys.path.insert(0, str(SRC_ROOT))

from hbv_multilead_joint_uncertainty.daily_combined_state_error import (  # noqa: E402
    bootstrap_block_indices,
    posterior_weighted_parameters,
    summarize_daily_combined_state_error,
)


DEFAULT_CONFIG = (
    PROJECT_ROOT
    / "src"
    / "hbv_multilead_joint_uncertainty"
    / "configs"
    / "g3_daily_combined_state_error_audit_v01.json"
)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _write_json(path: Path, payload) -> None:
    path.write_text(
        json.dumps(payload, indent=2, ensure_ascii=False, sort_keys=True)
        + "\n",
        encoding="utf-8",
    )


def _direction(low: float, high: float) -> str:
    if high < 0.0:
        return "detectable_improvement"
    if low > 0.0:
        return "detectable_deterioration"
    return "not_detectable"


def _summary_payload(config, statistics, weighted_parameters, source_sha):
    method_names = tuple(statistics["method_names"])
    state_names = tuple(statistics["state_names"])
    primary = str(np.asarray(statistics["primary_method"]).item())
    baselines = tuple(statistics["baseline_methods"])
    primary_index = method_names.index(primary)
    result = {
        "experiment_id": config["experiment_id"],
        "classification": config["classification"],
        "status": "complete",
        "source_evidence_sha256": source_sha,
        "primary_population": "all 540 assimilation days",
        "time_since_switch_grouping_used": False,
        "method_names": list(method_names),
        "state_names": list(state_names),
        "primary_method": primary,
        "baseline_methods": list(baselines),
        "sample_shape": {
            "blocks": int(statistics["errors"].shape[0]),
            "truth_trials": int(statistics["errors"].shape[1]),
            "days": int(statistics["errors"].shape[3]),
            "hydrologic_states": int(statistics["errors"].shape[4]),
        },
        "all_day_rmse_mm": {},
        "primary_comparisons": {},
        "posterior_weighted_parameter_daily_variation": {
            "mean_within_series_standard_deviation": np.mean(
                np.std(weighted_parameters, axis=2),
                axis=(0, 1),
            ).tolist(),
            "minimum": np.min(weighted_parameters, axis=(0, 1, 2)).tolist(),
            "maximum": np.max(weighted_parameters, axis=(0, 1, 2)).tolist(),
        },
        "conclusion_boundary": config["scope_limit"],
    }
    for method_index, method in enumerate(method_names):
        result["all_day_rmse_mm"][method] = {
            state: float(statistics["all_day_rmse"][method_index, state_index])
            for state_index, state in enumerate(state_names)
        }
    for baseline_index, baseline in enumerate(baselines):
        result["primary_comparisons"][baseline] = {
            state: {
                "relative_rmse_percent": float(
                    100.0
                    * statistics["relative_rmse_fraction"][
                        baseline_index, state_index
                    ]
                ),
                "mean_mse_difference": float(
                    statistics["mean_mse_difference"][
                        baseline_index, state_index
                    ]
                ),
                "mse_difference_95_percent_interval": [
                    float(
                        statistics["mse_difference_ci_low"][
                            baseline_index, state_index
                        ]
                    ),
                    float(
                        statistics["mse_difference_ci_high"][
                            baseline_index, state_index
                        ]
                    ),
                ],
                "paired_direction": _direction(
                    float(
                        statistics["mse_difference_ci_low"][
                            baseline_index, state_index
                        ]
                    ),
                    float(
                        statistics["mse_difference_ci_high"][
                            baseline_index, state_index
                        ]
                    ),
                ),
            }
            for state_index, state in enumerate(state_names)
        }
    result["primary_all_day_rmse_mm"] = result["all_day_rmse_mm"][primary]
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    args = parser.parse_args()

    config_path = args.config.resolve()
    config = json.loads(config_path.read_text(encoding="utf-8"))
    forbidden = {
        "days_since_switch",
        "post_switch_window",
        "time_strata",
        "switch_days",
    }
    if forbidden.intersection(config):
        raise ValueError("the direct state audit cannot define switch-distance strata")

    source_path = PROJECT_ROOT / config["sealed_source"]["path"]
    source_sha = _sha256(source_path)
    if source_sha != config["sealed_source"]["sha256"]:
        raise ValueError("sealed source SHA-256 does not match the config")

    output_dir = PROJECT_ROOT / config["output_dir"]
    if output_dir.exists():
        raise FileExistsError(f"output directory already exists: {output_dir}")
    output_dir.mkdir(parents=True)

    with np.load(source_path, allow_pickle=False) as source:
        days = int(np.asarray(source["assimilation_days"]).item())
        if days != int(config["assimilation_days"]):
            raise ValueError("assimilation_days does not match the config")
        method_names = tuple(str(value) for value in source["method_names"])
        if method_names != tuple(config["expected_method_names"]):
            raise ValueError("sealed method names do not match the config")
        method_states = source["method_assimilation_states"][:, :, :, :days]
        truth_states = source["truth_states"][:, :, :days]
        block_count = method_states.shape[0]
        bootstrap = bootstrap_block_indices(
            block_count,
            int(config["bootstrap"]["replicates"]),
            int(config["bootstrap"]["seed"]),
        )
        statistics = summarize_daily_combined_state_error(
            method_states,
            truth_states,
            method_names,
            bootstrap,
            primary_method=config["primary_method"],
            baseline_methods=config["baseline_methods"],
        )

        primary_index = method_names.index(config["primary_method"])
        candidate_count = int(source["method_candidate_counts"][primary_index])
        candidate_ids = tuple(
            str(value)
            for value in source["method_candidate_ids"][
                primary_index, :candidate_count
            ]
        )
        if candidate_ids != tuple(
            config["expected_parameter_only_candidate_ids"]
        ):
            raise ValueError("parameter-only candidate order is not frozen")
        probabilities = source["method_assimilation_probabilities"][
            :, :, primary_index, :days, :candidate_count
        ]
        parameter_vectors = source["parameter_vectors"][:candidate_count]
        weighted_parameters = posterior_weighted_parameters(
            probabilities,
            parameter_vectors,
        )

    shutil.copy2(config_path, output_dir / "config_snapshot.json")
    snapshot_dir = output_dir / "source_snapshot"
    snapshot_dir.mkdir()
    snapshot_sources = {
        "daily_combined_state_error.py": (
            PROJECT_ROOT
            / "src"
            / "hbv_multilead_joint_uncertainty"
            / "daily_combined_state_error.py"
        ),
        "run_g3_daily_combined_state_error_audit.py": Path(__file__),
        "verify_g3_daily_combined_state_error_audit.py": (
            Path(__file__).with_name(
                "verify_g3_daily_combined_state_error_audit.py"
            )
        ),
        "2026-07-31-id23-daily-combined-state-error-audit.md": (
            PROJECT_ROOT
            / "docs"
            / "plans"
            / "2026-07-31-id23-daily-combined-state-error-audit.md"
        ),
    }
    for name, source in snapshot_sources.items():
        shutil.copy2(source, snapshot_dir / name)
    np.savez_compressed(
        output_dir / "evidence.npz",
        method_names=np.asarray(statistics["method_names"]),
        state_names=np.asarray(statistics["state_names"]),
        primary_method=np.asarray(config["primary_method"]),
        baseline_methods=np.asarray(statistics["baseline_methods"]),
        day_indices=statistics["day_indices"],
        errors=statistics["errors"],
        all_day_rmse=statistics["all_day_rmse"],
        daily_rmse=statistics["daily_rmse"],
        block_mse=statistics["block_mse"],
        truth_standard_deviation=statistics["truth_standard_deviation"],
        standardized_rmse=statistics["standardized_rmse"],
        block_mse_difference=statistics["block_mse_difference"],
        mean_mse_difference=statistics["mean_mse_difference"],
        mse_difference_ci_low=statistics["mse_difference_ci_low"],
        mse_difference_ci_high=statistics["mse_difference_ci_high"],
        relative_rmse_fraction=statistics["relative_rmse_fraction"],
        bootstrap_indices=statistics["bootstrap_indices"],
        posterior_probabilities=probabilities,
        posterior_weighted_parameters=weighted_parameters,
        parameter_vectors=parameter_vectors,
        candidate_ids=np.asarray(candidate_ids),
    )
    summary = _summary_payload(
        config,
        statistics,
        weighted_parameters,
        source_sha,
    )
    _write_json(output_dir / "summary.json", summary)
    _write_json(
        output_dir / "environment.json",
        {
            "python": sys.version,
            "platform": platform.platform(),
            "numpy": np.__version__,
        },
    )
    _write_json(
        output_dir / "checksums.json",
        {
            "sealed_source": {
                "path": str(source_path.relative_to(PROJECT_ROOT)),
                "sha256": source_sha,
            },
            "config_snapshot.json": _sha256(
                output_dir / "config_snapshot.json"
            ),
            "evidence.npz": _sha256(output_dir / "evidence.npz"),
            "summary.json": _sha256(output_dir / "summary.json"),
            "source_snapshot": {
                name: _sha256(snapshot_dir / name)
                for name in sorted(snapshot_sources)
            },
        },
    )
    if _sha256(source_path) != source_sha:
        raise RuntimeError("sealed source changed during the audit")
    print(json.dumps(summary, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()

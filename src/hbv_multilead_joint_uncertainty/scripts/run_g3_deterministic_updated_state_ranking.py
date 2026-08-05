"""Rank every saved updated state under the same true-parameter forecast."""

from __future__ import annotations

import argparse
import hashlib
import json
import platform
import shutil
import sys
import time
from pathlib import Path

import numpy as np


PROJECT_ROOT = Path(__file__).resolve().parents[3]
SRC_ROOT = PROJECT_ROOT / "src"
if str(SRC_ROOT) not in sys.path:
    sys.path.insert(0, str(SRC_ROOT))

from hbv_joint_uncertainty.hbv_adapter import PARAMETER_NAMES  # noqa: E402
from hbv_multilead_joint_uncertainty.deterministic_unique_state_forecast import (  # noqa: E402
    build_all_stage_daily_index,
    forecast_deterministic_state,
)
from hbv_multilead_joint_uncertainty.synthetic_truth import (  # noqa: E402
    advance_reference_state,
    reference_routed_discharge,
)


DEFAULT_CONFIG = (
    PROJECT_ROOT
    / "src/hbv_multilead_joint_uncertainty/configs/"
    "g3_deterministic_updated_state_ranking_v01.json"
)
DEFAULT_OUTPUT = (
    PROJECT_ROOT
    / "results/23_hbv_multilead_joint_uncertainty/"
    "g3_deterministic_updated_state_ranking_v01"
)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _write_json(path: Path, payload) -> None:
    path.write_text(
        json.dumps(payload, indent=2, ensure_ascii=False, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def _parameter_map(vector) -> dict[str, float]:
    return {
        name: float(value)
        for name, value in zip(PARAMETER_NAMES, np.asarray(vector, dtype=np.float64))
    }


def _reference_forecast(state, parameters, forcing, leads):
    mapping = _parameter_map(parameters)
    current = np.asarray(state, dtype=np.float64).copy()
    result = np.empty(len(leads), dtype=np.float64)
    lead_to_row = {int(value): row for row, value in enumerate(leads)}
    for step in range(1, int(leads[-1]) + 1):
        current = advance_reference_state(current, *forcing[step - 1], mapping)
        if step in lead_to_row:
            result[lead_to_row[step]] = reference_routed_discharge(
                current, mapping["lag_time"]
            )
    return result


def _summarize(forecasts, truth, mask, bootstrap, methods):
    rmse = {}
    block_mse = {}
    for method in methods:
        squared = np.square(forecasts[method] - truth)
        rmse[method] = np.empty(7)
        block_mse[method] = np.empty((truth.shape[0], 7))
        for lead in range(7):
            selected = squared[..., lead][:, mask[..., lead]]
            rmse[method][lead] = np.sqrt(np.mean(selected))
            block_mse[method][:, lead] = np.mean(selected, axis=1)
    comparisons = {}
    for baseline in methods:
        if baseline == "parameter_only":
            continue
        difference = block_mse["parameter_only"] - block_mse[baseline]
        boot = np.mean(difference[bootstrap], axis=1)
        relative = np.full(7, np.nan, dtype=np.float64)
        stable = rmse[baseline] > 1e-12
        relative[stable] = (
            rmse["parameter_only"][stable] / rmse[baseline][stable] - 1.0
        )
        comparisons[baseline] = {
            "mean_mse_difference": np.mean(difference, axis=0),
            "ci_low": np.quantile(boot, 0.025, axis=0),
            "ci_high": np.quantile(boot, 0.975, axis=0),
            "relative_rmse_fraction": relative,
            "block_mse_difference": difference,
        }
    ranking = np.asarray(
        [[method for method in sorted(methods, key=lambda name: rmse[name][lead])] for lead in range(7)]
    )
    return rmse, block_mse, comparisons, ranking


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    config_path = args.config.resolve()
    config = json.loads(config_path.read_text(encoding="utf-8"))
    expected_methods = (
        "open_loop",
        "fixed_filter",
        "parameter_only",
        "noise_only",
        "joint",
        "truth_state_oracle",
    )
    if tuple(config["state_methods"]) != expected_methods:
        raise ValueError("state method order differs from the frozen contract")
    if tuple(config["lead_days"]) != tuple(range(1, 8)):
        raise ValueError("lead days must equal 1 through 7")
    source = PROJECT_ROOT / config["sealed_ideal_evidence"]["path"]
    source_sha = _sha256(source)
    if source_sha != config["sealed_ideal_evidence"]["sha256"]:
        raise ValueError("sealed ideal evidence SHA-256 mismatch")
    output_dir = args.output_dir.resolve()
    if output_dir.exists():
        raise FileExistsError(f"output directory already exists: {output_dir}")

    started = time.monotonic()
    with np.load(source, allow_pickle=False) as evidence:
        methods = tuple(str(value) for value in evidence["method_names"])
        if methods != expected_methods[:-1]:
            raise ValueError("sealed method order changed")
        assimilation_days = int(np.asarray(evidence["assimilation_days"]).item())
        schedule = np.asarray(evidence["truth_parameter_indices"], dtype=np.int64)
        index = build_all_stage_daily_index(
            schedule,
            assimilation_days=assimilation_days,
            lead_days=config["lead_days"],
        )
        parameters = np.asarray(evidence["parameter_vectors"], dtype=np.float64)
        truth_parameters = parameters[schedule[:, :assimilation_days]]
        method_states = np.asarray(
            evidence["method_assimilation_states"][:, :, :, :assimilation_days],
            dtype=np.float64,
        )
        truth_states_all = np.asarray(evidence["truth_states"], dtype=np.float64)
        truth_origin_states = truth_states_all[:, :, :assimilation_days]
        state_sources = {
            method: method_states[:, :, position]
            for position, method in enumerate(methods)
        }
        state_sources["truth_state_oracle"] = truth_origin_states
        forcing = np.asarray(evidence["forcing_blocks"], dtype=np.float64)
        warmup = int(np.asarray(evidence["warmup_days"]).item())
        active_forcing = forcing[:, warmup:]
        truth_discharge = np.asarray(evidence["truth_discharge"], dtype=np.float64)
        truth_forecasts = np.empty((8, 3, 540, 7), dtype=np.float64)
        for block in range(8):
            for truth in range(3):
                truth_forecasts[block, truth] = truth_discharge[
                    block, truth, index.target_indices
                ]

        preflight_maximum = 0.0
        preflight_count = 0
        for method in expected_methods:
            for block in range(8):
                for truth in range(3):
                    for origin in (0, 179, 180, 359, 360, 539):
                        parameter = truth_parameters[truth, origin]
                        future = active_forcing[block, origin + 1 : origin + 8]
                        production = forecast_deterministic_state(
                            state_sources[method][block, truth, origin],
                            parameter,
                            future,
                            index.lead_days,
                        ).discharge
                        reference = _reference_forecast(
                            state_sources[method][block, truth, origin],
                            parameter,
                            future,
                            index.lead_days,
                        )
                        preflight_maximum = max(
                            preflight_maximum,
                            float(np.max(np.abs(production - reference))),
                        )
                        preflight_count += 1
        if preflight_maximum > float(config["numerical_tolerance"]):
            raise RuntimeError("production-reference preflight failed")

        forecasts = {}
        for method_number, method in enumerate(expected_methods, start=1):
            values = np.empty((8, 3, 540, 7), dtype=np.float64)
            for block in range(8):
                for truth in range(3):
                    for origin in range(540):
                        values[block, truth, origin] = forecast_deterministic_state(
                            state_sources[method][block, truth, origin],
                            truth_parameters[truth, origin],
                            active_forcing[block, origin + 1 : origin + 8],
                            index.lead_days,
                        ).discharge
            forecasts[method] = values
            print(f"state methods {method_number}/{len(expected_methods)}", flush=True)
        bootstrap = np.random.default_rng(int(config["bootstrap"]["seed"])).integers(
            0, 8, size=(int(config["bootstrap"]["replicates"]), 8), dtype=np.int64
        )
        rmse, block_mse, comparisons, ranking = _summarize(
            forecasts,
            truth_forecasts,
            index.same_stage_mask,
            bootstrap,
            expected_methods,
        )

    output_dir.mkdir(parents=True)
    shutil.copy2(config_path, output_dir / "config_snapshot.json")
    npz = {
        "method_names": np.asarray(expected_methods),
        "lead_days": index.lead_days,
        "origin_indices": index.origin_indices,
        "target_indices": index.target_indices,
        "same_stage_mask": index.same_stage_mask,
        "truth_forecasts": truth_forecasts,
        "bootstrap_indices": bootstrap,
        "ranking": ranking,
    }
    for method in expected_methods:
        npz[f"forecast__{method}"] = forecasts[method]
        npz[f"rmse__{method}"] = rmse[method]
        npz[f"block_mse__{method}"] = block_mse[method]
    for baseline, values in comparisons.items():
        for field, value in values.items():
            npz[f"comparison__parameter_only__minus__{baseline}__{field}"] = value
    np.savez_compressed(output_dir / "evidence.npz", **npz)
    summary = {
        "experiment_id": config["experiment_id"],
        "classification": config["classification"],
        "status": "complete",
        "primary_population": config["primary_population"],
        "same_stage_sample_count_across_truth_trials": np.sum(
            index.same_stage_mask, axis=(0, 1)
        ).tolist(),
        "rmse": {method: rmse[method].tolist() for method in expected_methods},
        "ranking_best_to_worst": {
            f"lead_{lead}_day": ranking[row].tolist()
            for row, lead in enumerate(index.lead_days)
        },
        "parameter_only_comparisons": {
            baseline: {
                field: (
                    [None if not np.isfinite(item) else float(item) for item in value]
                    if field == "relative_rmse_fraction"
                    else value.tolist()
                )
                for field, value in values.items()
                if field != "block_mse_difference"
            }
            for baseline, values in comparisons.items()
        },
        "correctness_gates": {
            "production_reference_count": preflight_count,
            "production_reference_maximum_absolute_difference": preflight_maximum,
            "passed": True,
            "covariance_used": False,
            "future_discharge_observations_used": False,
        },
        "elapsed_seconds": time.monotonic() - started,
        "scope_limit": config["scope_limit"],
    }
    _write_json(output_dir / "summary.json", summary)
    _write_json(
        output_dir / "environment.json",
        {"python": sys.version, "platform": platform.platform(), "numpy": np.__version__},
    )
    _write_json(
        output_dir / "checksums.json",
        {
            "sealed_ideal_evidence_sha256": source_sha,
            "config_snapshot.json": _sha256(output_dir / "config_snapshot.json"),
            "evidence.npz": _sha256(output_dir / "evidence.npz"),
            "summary.json": _sha256(output_dir / "summary.json"),
        },
    )
    print(json.dumps(summary, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()

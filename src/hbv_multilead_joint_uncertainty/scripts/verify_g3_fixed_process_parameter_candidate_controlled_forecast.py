"""Independently verify the fixed-process parameter-candidate forecast audit."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
from pathlib import Path

import numpy as np


PROJECT_ROOT = Path(__file__).resolve().parents[3]
SRC_ROOT = PROJECT_ROOT / "src"
if str(SRC_ROOT) not in sys.path:
    sys.path.insert(0, str(SRC_ROOT))

from hbv_joint_uncertainty.hbv_adapter import PARAMETER_NAMES  # noqa: E402
from hbv_multilead_joint_uncertainty.synthetic_truth import (  # noqa: E402
    advance_reference_state,
    reference_routed_discharge,
)


DEFAULT_RESULT = (
    PROJECT_ROOT
    / "results/23_hbv_multilead_joint_uncertainty/"
    "g3_fixed_process_parameter_candidate_controlled_forecast_v01"
)
SEALED_METHODS = (
    "open_loop",
    "fixed_filter",
    "parameter_only",
    "noise_only",
    "joint",
)
SEALED_COUNTS = (1, 1, 3, 3, 9)
CONTROLLED_METHODS = (
    "single_fixed_parameter_filter_state",
    "three_parameter_candidates_combined_state",
)
FIXED_CANDIDATES = ("trained_center__process_2",)
THREE_CANDIDATES = (
    "equifinal_diverse_1__process_2",
    "trained_center__process_2",
    "equifinal_diverse_2__process_2",
)
PARAMETER_IDS = (
    "equifinal_diverse_1",
    "trained_center",
    "equifinal_diverse_2",
)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _maximum_difference(left, right) -> float:
    left_values = np.asarray(left, dtype=np.float64)
    right_values = np.asarray(right, dtype=np.float64)
    if left_values.shape != right_values.shape:
        return float("inf")
    if not np.array_equal(np.isnan(left_values), np.isnan(right_values)):
        return float("inf")
    finite = np.isfinite(left_values) & np.isfinite(right_values)
    if not np.array_equal(np.isinf(left_values), np.isinf(right_values)):
        return float("inf")
    return float(
        np.max(np.abs(left_values[finite] - right_values[finite]), initial=0.0)
    )


def _reference_forecast(state, parameter_vector, forcing) -> np.ndarray:
    parameters = {
        name: float(value)
        for name, value in zip(
            PARAMETER_NAMES, np.asarray(parameter_vector, dtype=np.float64)
        )
    }
    current = np.asarray(state, dtype=np.float64).copy()
    result = np.empty(7, dtype=np.float64)
    for lead in range(7):
        current = advance_reference_state(current, *forcing[lead], parameters)
        result[lead] = reference_routed_discharge(
            current, parameters["lag_time"]
        )
    return result


def _candidate_contract(evidence) -> dict[str, object]:
    methods = tuple(str(value) for value in evidence["method_names"])
    counts = tuple(int(value) for value in evidence["method_candidate_counts"])
    if methods != SEALED_METHODS or counts != SEALED_COUNTS:
        raise ValueError("sealed method or candidate-count contract changed")
    identifiers = np.asarray(evidence["method_candidate_ids"])
    fixed_index = methods.index("fixed_filter")
    three_index = methods.index("parameter_only")
    fixed = tuple(str(value) for value in identifiers[fixed_index, : counts[fixed_index]])
    three = tuple(str(value) for value in identifiers[three_index, : counts[three_index]])
    if fixed != FIXED_CANDIDATES or three != THREE_CANDIDATES:
        raise ValueError("sealed one-versus-three candidate identifiers changed")
    fixed_processes = tuple(value.rsplit("__", 1)[1] for value in fixed)
    three_processes = tuple(value.rsplit("__", 1)[1] for value in three)
    if fixed_processes != ("process_2",) or three_processes != ("process_2",) * 3:
        raise ValueError("controlled candidates do not share process_2")
    return {
        "source_indices": (fixed_index, three_index),
        "source_names": ("fixed_filter", "parameter_only"),
        "fixed_candidates": fixed,
        "three_candidates": three,
    }


def _recompute_statistics(forecasts, truth, same_stage, stages, bootstrap):
    block_count, _, _, lead_count = truth.shape
    rmse = np.empty((2, lead_count), dtype=np.float64)
    block_mse = np.empty((2, block_count, lead_count), dtype=np.float64)
    stage_rmse = np.empty((2, 3, lead_count), dtype=np.float64)
    stage_samples = np.empty((3, lead_count), dtype=np.int64)
    for method_index, method in enumerate(CONTROLLED_METHODS):
        squared = np.square(forecasts[method] - truth)
        for lead in range(lead_count):
            mask = same_stage[..., lead]
            selected = squared[..., lead][:, mask]
            rmse[method_index, lead] = np.sqrt(np.mean(selected))
            block_mse[method_index, :, lead] = np.mean(selected, axis=1)
            for stage in range(3):
                stage_mask = mask & (stages == stage)
                stage_samples[stage, lead] = int(np.sum(stage_mask))
                stage_rmse[method_index, stage, lead] = np.sqrt(
                    np.mean(squared[..., lead][:, stage_mask])
                )
    difference = block_mse[1] - block_mse[0]
    bootstrap_means = np.mean(difference[bootstrap], axis=1)
    mean_difference = np.mean(difference, axis=0)
    ci_low = np.quantile(bootstrap_means, 0.025, axis=0)
    ci_high = np.quantile(bootstrap_means, 0.975, axis=0)
    relative = rmse[1] / rmse[0] - 1.0
    decision = (relative <= -0.01) & (ci_high < 0.0)
    return {
        "rmse": rmse,
        "block_mse": block_mse,
        "stage_rmse": stage_rmse,
        "stage_samples": stage_samples,
        "difference": difference,
        "mean_difference": mean_difference,
        "ci_low": ci_low,
        "ci_high": ci_high,
        "relative": relative,
        "decision": decision,
    }


def verify(result_dir: Path) -> dict:
    result_dir = result_dir.resolve()
    report_path = result_dir / "independent_verification.json"
    if report_path.exists():
        raise FileExistsError(f"independent verification already exists: {report_path}")
    config = json.loads(
        (result_dir / "config_snapshot.json").read_text(encoding="utf-8")
    )
    if (
        config.get("fixed_process_id") != "process_2"
        or config.get("fixed_forecast_parameter_id") != "trained_center"
        or tuple(config.get("state_methods", ())) != CONTROLLED_METHODS
        or tuple(config.get("lead_days", ())) != tuple(range(1, 8))
        or config.get("assimilation_days") != 540
    ):
        raise ValueError("result config does not match the controlled contract")
    source = (PROJECT_ROOT / config["sealed_ideal_evidence"]["path"]).resolve()
    source_hash = _sha256(source)
    if source_hash != config["sealed_ideal_evidence"]["sha256"]:
        raise ValueError("sealed ideal evidence SHA-256 mismatch")
    checksums = json.loads((result_dir / "checksums.json").read_text(encoding="utf-8"))
    checksum_checks = {
        name: checksums.get(name) == _sha256(result_dir / name)
        for name in (
            "config_snapshot.json",
            "environment.json",
            "evidence.npz",
            "summary.json",
        )
    }
    checksum_checks["sealed_ideal_evidence_sha256"] = (
        checksums.get("sealed_ideal_evidence_sha256") == source_hash
    )

    with np.load(result_dir / "evidence.npz", allow_pickle=False) as archive:
        saved = {name: archive[name].copy() for name in archive.files}
    with np.load(source, allow_pickle=False) as source_archive:
        contract = _candidate_contract(source_archive)
        parameter_ids = tuple(str(value) for value in source_archive["parameter_ids"])
        if parameter_ids != PARAMETER_IDS:
            raise ValueError("sealed parameter identifier order changed")
        parameter_vectors = np.asarray(source_archive["parameter_vectors"], dtype=np.float64)
        fixed_parameter = parameter_vectors[parameter_ids.index("trained_center")].copy()
        assimilation_days = int(np.asarray(source_archive["assimilation_days"]).item())
        schedule = np.asarray(source_archive["truth_parameter_indices"], dtype=np.int64)
        origins = np.arange(assimilation_days, dtype=np.int64)
        leads = np.arange(1, 8, dtype=np.int64)
        targets = origins[:, None] + leads[None, :]
        origin_parameters = schedule[:, origins]
        target_parameters = schedule[:, targets]
        same_stage = target_parameters == origin_parameters[:, :, None]
        all_states = np.asarray(
            source_archive["method_assimilation_states"][:, :, :, :assimilation_days],
            dtype=np.float64,
        )
        states = {
            method: all_states[:, :, source_index]
            for method, source_index in zip(
                CONTROLLED_METHODS, contract["source_indices"]
            )
        }
        warmup = int(np.asarray(source_archive["warmup_days"]).item())
        forcing = np.asarray(source_archive["forcing_blocks"], dtype=np.float64)[:, warmup:]
        truth_discharge = np.asarray(source_archive["truth_discharge"], dtype=np.float64)
        truth_forecasts = truth_discharge[:, :, targets]
        forecasts = {}
        for method_number, method in enumerate(CONTROLLED_METHODS, start=1):
            values = np.empty((8, 3, assimilation_days, 7), dtype=np.float64)
            for block in range(8):
                for truth in range(3):
                    for origin in range(assimilation_days):
                        values[block, truth, origin] = _reference_forecast(
                            states[method][block, truth, origin],
                            fixed_parameter,
                            forcing[block, origin + 1 : origin + 8],
                        )
            forecasts[method] = values
            print(
                f"independent controlled state methods {method_number}/{len(CONTROLLED_METHODS)}",
                flush=True,
            )

    bootstrap = np.random.default_rng(int(config["bootstrap"]["seed"])).integers(
        0,
        8,
        size=(int(config["bootstrap"]["replicates"]), 8),
        dtype=np.int64,
    )
    statistics = _recompute_statistics(
        forecasts, truth_forecasts, same_stage, origin_parameters, bootstrap
    )
    expected_numeric = {
        "source_method_indices": np.asarray(contract["source_indices"], dtype=np.int64),
        "fixed_forecast_parameter_vector": fixed_parameter,
        "lead_days": leads,
        "origin_indices": origins,
        "target_indices": targets,
        "origin_parameter_indices": origin_parameters,
        "target_parameter_indices": target_parameters,
        "same_stage_mask": same_stage,
        "truth_forecasts": truth_forecasts,
        "bootstrap_indices": bootstrap,
        "same_stage_sample_count_per_block": np.sum(same_stage, axis=(0, 1)),
        "same_stage_sample_count_all_blocks": 8 * np.sum(same_stage, axis=(0, 1)),
        "stage_sample_count_per_block": statistics["stage_samples"],
        "stage_rmse": statistics["stage_rmse"],
        "block_mse_difference": statistics["difference"],
        "mean_mse_difference": statistics["mean_difference"],
        "paired_mse_ci_low": statistics["ci_low"],
        "paired_mse_ci_high": statistics["ci_high"],
        "relative_rmse_fraction": statistics["relative"],
    }
    for method_index, method in enumerate(CONTROLLED_METHODS):
        expected_numeric[f"forecast__{method}"] = forecasts[method]
        expected_numeric[f"rmse__{method}"] = statistics["rmse"][method_index]
        expected_numeric[f"block_mse__{method}"] = statistics["block_mse"][method_index]
    differences = {
        name: _maximum_difference(saved[name], value)
        for name, value in expected_numeric.items()
    }
    label_checks = {
        "method_names": tuple(saved["method_names"].astype(str)) == CONTROLLED_METHODS,
        "source_method_names": tuple(saved["source_method_names"].astype(str))
        == contract["source_names"],
        "fixed_filter_candidate_ids": tuple(
            saved["fixed_filter_candidate_ids"].astype(str)
        )
        == FIXED_CANDIDATES,
        "three_parameter_candidate_ids": tuple(
            saved["three_parameter_candidate_ids"].astype(str)
        )
        == THREE_CANDIDATES,
        "fixed_process_id": str(saved["fixed_process_id"].item()) == "process_2",
        "fixed_forecast_parameter_id": str(
            saved["fixed_forecast_parameter_id"].item()
        )
        == "trained_center",
        "parameter_ids": tuple(saved["parameter_ids"].astype(str)) == PARAMETER_IDS,
        "improvement_decision": np.array_equal(
            saved["improvement_decision"], statistics["decision"]
        ),
    }

    summary = json.loads((result_dir / "summary.json").read_text(encoding="utf-8"))
    primary = summary["all_stage_primary"]
    summary_differences = {
        "single_filter_root_mean_square_error": _maximum_difference(
            primary["single_filter_root_mean_square_error"], statistics["rmse"][0]
        ),
        "three_parameter_candidates_root_mean_square_error": _maximum_difference(
            primary["three_parameter_candidates_root_mean_square_error"], statistics["rmse"][1]
        ),
        "relative_root_mean_square_error_percent": _maximum_difference(
            primary["three_minus_single_relative_root_mean_square_error_percent"],
            100.0 * statistics["relative"],
        ),
        "mean_squared_error_difference": _maximum_difference(
            primary["three_minus_single_mean_squared_error_difference"],
            statistics["mean_difference"],
        ),
        "interval_low": _maximum_difference(
            primary["paired_mean_squared_error_difference_95_percent_interval_low"],
            statistics["ci_low"],
        ),
        "interval_high": _maximum_difference(
            primary["paired_mean_squared_error_difference_95_percent_interval_high"],
            statistics["ci_high"],
        ),
    }
    summary_checks = {
        "status_pending_before_verification": summary.get("status")
        == "complete_pending_independent_verification",
        "only_changed_factor": summary.get("only_changed_factor")
        == "assimilation parameter candidate count: 1 versus 3",
        "decision": primary.get("three_parameter_candidates_improves")
        == statistics["decision"].tolist(),
    }
    tolerance = float(config["numerical_tolerance"])
    passed = (
        all(value <= tolerance for value in differences.values())
        and all(value <= tolerance for value in summary_differences.values())
        and all(label_checks.values())
        and all(summary_checks.values())
        and all(checksum_checks.values())
    )
    report = {
        "status": "passed" if passed else "failed",
        "independent_reference_model": True,
        "production_deterministic_forecast_module_imported": False,
        "production_controlled_summary_module_imported": False,
        "tolerance": tolerance,
        "maximum_absolute_differences": differences,
        "maximum_summary_differences": summary_differences,
        "maximum_absolute_difference_overall": max(
            list(differences.values()) + list(summary_differences.values())
        ),
        "label_checks": label_checks,
        "summary_checks": summary_checks,
        "checksum_checks": checksum_checks,
        "evidence_sha256": _sha256(result_dir / "evidence.npz"),
        "sealed_ideal_evidence_sha256": source_hash,
    }
    temporary = result_dir / ".independent_verification.json.incomplete"
    if temporary.exists():
        raise FileExistsError(f"verification staging file already exists: {temporary}")
    temporary.write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    os.replace(temporary, report_path)
    print(json.dumps(report, indent=2), flush=True)
    if not passed:
        raise SystemExit(1)
    return report


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--result-dir", type=Path, default=DEFAULT_RESULT)
    args = parser.parse_args()
    verify(args.result_dir)


if __name__ == "__main__":
    main()

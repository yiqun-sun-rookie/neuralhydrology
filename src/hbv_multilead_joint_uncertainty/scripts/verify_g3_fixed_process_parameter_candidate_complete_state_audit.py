"""Independently verify the no-forecast complete-state controlled audit."""

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

from hbv_joint_uncertainty.hbv_adapter import STATE_NAMES  # noqa: E402


EXPERIMENT_ID = "g3_fixed_process_parameter_candidate_complete_state_audit_v01"
DEFAULT_RESULT = (
    PROJECT_ROOT / "results/23_hbv_multilead_joint_uncertainty" / EXPERIMENT_ID
)
SEALED_METHODS = (
    "open_loop",
    "fixed_filter",
    "parameter_only",
    "noise_only",
    "joint",
)
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
GROUP_NAMES = ("hydrologic_stores", "routing_memory")
GROUP_SLICES = (slice(0, 5), slice(5, 15))


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
    return float(
        np.max(np.abs(left_values[finite] - right_values[finite]), initial=0.0)
    )


def _decide(low, high):
    low_values = np.asarray(low, dtype=np.float64)
    high_values = np.asarray(high, dtype=np.float64)
    return np.where(
        high_values < 0.0,
        "improves",
        np.where(low_values > 0.0, "worsens", "inconclusive"),
    )


def _candidate_contract(source) -> tuple[int, int]:
    methods = tuple(source["method_names"].astype(str))
    counts = tuple(int(value) for value in source["method_candidate_counts"])
    if methods != SEALED_METHODS or counts != (1, 1, 3, 3, 9):
        raise ValueError("sealed method or candidate-count contract changed")
    identifiers = np.asarray(source["method_candidate_ids"])
    fixed_index = methods.index("fixed_filter")
    three_index = methods.index("parameter_only")
    fixed = tuple(identifiers[fixed_index, : counts[fixed_index]].astype(str))
    three = tuple(identifiers[three_index, : counts[three_index]].astype(str))
    if fixed != FIXED_CANDIDATES or three != THREE_CANDIDATES:
        raise ValueError("sealed controlled candidate identifiers changed")
    if any(value.rsplit("__", 1)[1] != "process_2" for value in fixed + three):
        raise ValueError("controlled candidates do not share process_2")
    return fixed_index, three_index


def _statistics(estimates, truth, bootstrap):
    standard_deviation = np.std(truth, axis=(0, 1, 2))
    errors = estimates - truth[:, :, None]
    squared = np.square(errors)
    standardized = squared / np.square(standard_deviation[None, None, None, None])
    state_rmse = np.sqrt(np.mean(squared, axis=(0, 1, 3)))
    state_standardized_rmse = state_rmse / standard_deviation[None]
    state_block_mse = np.mean(squared, axis=(1, 3))
    state_difference = state_block_mse[:, 1] - state_block_mse[:, 0]
    state_bootstrap = np.mean(state_difference[bootstrap], axis=1)
    state_low = np.quantile(state_bootstrap, 0.025, axis=0)
    state_high = np.quantile(state_bootstrap, 0.975, axis=0)

    group_raw = np.empty((2, 2), dtype=np.float64)
    group_standardized = np.empty((2, 2), dtype=np.float64)
    group_block = np.empty((8, 2, 2), dtype=np.float64)
    for index, state_slice in enumerate(GROUP_SLICES):
        group_raw[:, index] = np.sqrt(
            np.mean(squared[..., state_slice], axis=(0, 1, 3, 4))
        )
        group_standardized[:, index] = np.sqrt(
            np.mean(standardized[..., state_slice], axis=(0, 1, 3, 4))
        )
        group_block[:, :, index] = np.mean(
            standardized[..., state_slice], axis=(1, 3, 4)
        )
    group_difference = group_block[:, 1] - group_block[:, 0]
    group_bootstrap = np.mean(group_difference[bootstrap], axis=1)
    group_low = np.quantile(group_bootstrap, 0.025, axis=0)
    group_high = np.quantile(group_bootstrap, 0.975, axis=0)

    complete_rmse = np.sqrt(np.mean(standardized, axis=(0, 1, 3, 4)))
    complete_block = np.mean(standardized, axis=(1, 3, 4))
    complete_difference = complete_block[:, 1] - complete_block[:, 0]
    complete_bootstrap = np.mean(complete_difference[bootstrap], axis=1)
    complete_low = float(np.quantile(complete_bootstrap, 0.025))
    complete_high = float(np.quantile(complete_bootstrap, 0.975))
    return {
        "truth_standard_deviation": standard_deviation,
        "per_state_rmse": state_rmse,
        "per_state_standardized_rmse": state_standardized_rmse,
        "per_state_block_mse": state_block_mse,
        "per_state_block_mse_difference": state_difference,
        "per_state_mean_mse_difference": np.mean(state_difference, axis=0),
        "per_state_mse_ci_low": state_low,
        "per_state_mse_ci_high": state_high,
        "per_state_relative_rmse_fraction": state_rmse[1] / state_rmse[0] - 1.0,
        "per_state_decision": _decide(state_low, state_high),
        "group_raw_rmse": group_raw,
        "group_standardized_rmse": group_standardized,
        "group_block_standardized_mse": group_block,
        "group_block_standardized_mse_difference": group_difference,
        "group_standardized_mse_ci_low": group_low,
        "group_standardized_mse_ci_high": group_high,
        "group_relative_standardized_rmse_fraction": (
            group_standardized[1] / group_standardized[0] - 1.0
        ),
        "group_decision": _decide(group_low, group_high),
        "complete_standardized_rmse": complete_rmse,
        "complete_block_standardized_mse": complete_block,
        "complete_block_standardized_mse_difference": complete_difference,
        "complete_standardized_mse_difference": float(np.mean(complete_difference)),
        "complete_standardized_mse_ci_low": complete_low,
        "complete_standardized_mse_ci_high": complete_high,
        "complete_relative_standardized_rmse_fraction": float(
            complete_rmse[1] / complete_rmse[0] - 1.0
        ),
        "complete_decision": str(_decide(complete_low, complete_high).item()),
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
        config.get("experiment_id") != EXPERIMENT_ID
        or config.get("fixed_process_id") != "process_2"
        or config.get("state_count") != 15
        or config.get("assimilation_days") != 540
    ):
        raise ValueError("result config differs from the frozen state contract")
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
    checksum_checks["sealed_source"] = (
        checksums.get("sealed_ideal_evidence_sha256") == source_hash
    )

    with np.load(result_dir / "evidence.npz", allow_pickle=False) as archive:
        saved = {name: archive[name].copy() for name in archive.files}
    with np.load(source, allow_pickle=False) as source_archive:
        fixed_index, three_index = _candidate_contract(source_archive)
        estimates = np.stack(
            (
                source_archive["method_assimilation_states"][:, :, fixed_index, :540],
                source_archive["method_assimilation_states"][:, :, three_index, :540],
            ),
            axis=2,
        ).astype(np.float64)
        truth = np.asarray(source_archive["truth_states"][:, :, :540], dtype=np.float64)
    bootstrap = np.random.default_rng(int(config["bootstrap"]["seed"])).integers(
        0, 8, size=(int(config["bootstrap"]["replicates"]), 8), dtype=np.int64
    )
    statistics = _statistics(estimates, truth, bootstrap)

    expected_numeric = {
        "source_method_indices": np.asarray((fixed_index, three_index), dtype=np.int64),
        "day_indices": np.arange(540, dtype=np.int64),
        "bootstrap_indices": bootstrap,
        **{
            name: value
            for name, value in statistics.items()
            if name not in {"per_state_decision", "group_decision", "complete_decision"}
        },
    }
    differences = {
        name: _maximum_difference(saved[name], value)
        for name, value in expected_numeric.items()
    }
    label_checks = {
        "method_names": tuple(saved["method_names"].astype(str)) == CONTROLLED_METHODS,
        "source_method_names": tuple(saved["source_method_names"].astype(str))
        == ("fixed_filter", "parameter_only"),
        "fixed_filter_candidate_ids": tuple(
            saved["fixed_filter_candidate_ids"].astype(str)
        )
        == FIXED_CANDIDATES,
        "three_parameter_candidate_ids": tuple(
            saved["three_parameter_candidate_ids"].astype(str)
        )
        == THREE_CANDIDATES,
        "fixed_process_id": str(saved["fixed_process_id"].item()) == "process_2",
        "state_names": tuple(saved["state_names"].astype(str)) == tuple(STATE_NAMES),
        "state_group_names": tuple(saved["state_group_names"].astype(str))
        == GROUP_NAMES,
        "per_state_decision": np.array_equal(
            saved["per_state_decision"].astype(str), statistics["per_state_decision"]
        ),
        "group_decision": np.array_equal(
            saved["group_decision"].astype(str), statistics["group_decision"]
        ),
        "complete_decision": str(saved["complete_decision"].item())
        == statistics["complete_decision"],
    }

    summary = json.loads((result_dir / "summary.json").read_text(encoding="utf-8"))
    summary_differences = {}
    for index, state_name in enumerate(STATE_NAMES):
        values = summary["per_state"][state_name]
        summary_differences[f"{state_name}_single_rmse"] = _maximum_difference(
            values["single_filter_root_mean_square_error"],
            statistics["per_state_rmse"][0, index],
        )
        summary_differences[f"{state_name}_three_rmse"] = _maximum_difference(
            values["three_parameter_candidates_root_mean_square_error"],
            statistics["per_state_rmse"][1, index],
        )
        summary_differences[f"{state_name}_relative_percent"] = _maximum_difference(
            values["three_minus_single_relative_root_mean_square_error_percent"],
            100.0 * statistics["per_state_relative_rmse_fraction"][index],
        )
    complete = summary["complete_equal_component_standardized_error"]
    summary_differences["complete_single"] = _maximum_difference(
        complete[CONTROLLED_METHODS[0]], statistics["complete_standardized_rmse"][0]
    )
    summary_differences["complete_three"] = _maximum_difference(
        complete[CONTROLLED_METHODS[1]], statistics["complete_standardized_rmse"][1]
    )
    summary_checks = {
        "pending_status": summary.get("status")
        == "complete_pending_independent_verification",
        "forecast_not_executed": summary.get("forecast_executed") is False,
        "only_changed_factor": summary.get("only_changed_factor")
        == "assimilation parameter candidate count: 1 versus 3",
        "complete_decision": complete.get("decision")
        == statistics["complete_decision"],
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
        "forecast_module_imported": False,
        "production_state_summary_module_imported": False,
        "tolerance": tolerance,
        "maximum_absolute_differences": differences,
        "maximum_summary_differences": summary_differences,
        "maximum_absolute_difference_overall": max(
            list(differences.values()) + list(summary_differences.values())
        ),
        "label_checks": label_checks,
        "summary_checks": summary_checks,
        "checksum_checks": checksum_checks,
        "sealed_ideal_evidence_sha256": source_hash,
        "evidence_sha256": _sha256(result_dir / "evidence.npz"),
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

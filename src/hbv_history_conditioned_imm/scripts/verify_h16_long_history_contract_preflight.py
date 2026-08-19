"""Independently verify an H16 long-history preflight artifact directory."""

from __future__ import annotations

import argparse
import hashlib
from itertools import combinations
import json
import math
from pathlib import Path
from typing import Any, Mapping

import numpy as np
import torch

from hbv_history_conditioned_imm.hbv import HBV15Model, forecast_global_state
from hbv_history_conditioned_imm.parameter_switch import build_parameter_candidates


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _hazard(age: int, specification: Mapping[str, Any]) -> float:
    ramp_start = int(specification["ramp_start_age"])
    ramp_end = int(specification["ramp_end_age"])
    if int(age) < ramp_start:
        return float(specification["early_hazard"])
    if int(age) <= ramp_end:
        return float(specification["ramp_start_hazard"]) + float(
            specification["ramp_slope_per_day"]
        ) * (int(age) - ramp_start)
    return float(specification["late_hazard"])


def _duration_mean(specification: Mapping[str, Any]) -> float:
    survival = 1.0
    expected = 0.0
    age = 1
    while survival > 1e-15:
        probability = survival * _hazard(age, specification)
        expected += age * probability
        survival -= probability
        age += 1
        if age > 1_000_000:
            raise RuntimeError("independent duration calculation did not converge")
    return expected


def _probability_bounds(config: Mapping[str, Any]) -> tuple[float, float]:
    stay = float(config["filter"]["base_transition_stay_probability"])
    base_hazard = 1.0 - stay
    cap = float(config["network_output_contract"]["maximum_logit_correction"])
    ratio = math.exp(2.0 * cap)
    lower = base_hazard / (base_hazard + stay * ratio)
    upper = base_hazard * ratio / (stay + base_hazard * ratio)
    return lower, upper


def _recompute_signal_ratio(
    arrays: Mapping[str, np.ndarray], config: Mapping[str, Any]
) -> float:
    split_labels = np.asarray(arrays["split_labels"]).astype(str)
    selected_blocks = np.flatnonzero(split_labels == "training")
    days = int(config["data"]["assimilation_days"])
    leads = tuple(int(value) for value in config["forecast"]["leads_days"])
    maximum_lead = max(leads)
    modes = np.asarray(arrays["true_parameter_indices"])
    origins: list[tuple[int, int]] = []
    for block in selected_blocks:
        for day in range(days):
            stop = day + maximum_lead
            if stop >= modes.shape[1]:
                continue
            window = modes[block, day : stop + 1]
            if np.all(window == window[0]):
                origins.append((int(block), day))
    if not origins:
        raise ValueError("independent signal audit found no valid origins")

    states = torch.as_tensor(
        np.stack([arrays["truth_states"][block, day] for block, day in origins]),
        dtype=torch.float64,
    )
    forcing = torch.as_tensor(
        np.stack(
            [
                arrays["forcing"][
                    block, day + 1 : day + 1 + maximum_lead
                ]
                for block, day in origins
            ]
        ),
        dtype=torch.float64,
    )
    candidates = build_parameter_candidates(
        config["base_parameters"], config["parameter_candidates"]["values"]
    )
    forecasts = {
        identifier: forecast_global_state(
            states,
            forcing,
            HBV15Model(parameters),
            leads,
        )
        for identifier, parameters in candidates.items()
    }
    pairwise = []
    for first, second in combinations(candidates, 2):
        for lead in leads:
            difference = forecasts[first][lead] - forecasts[second][lead]
            pairwise.append(float(torch.sqrt(torch.mean(difference.square()))))
    return min(pairwise) / float(
        config["data"]["observation_standard_deviation"]
    )


def verify_h16_result(
    result_directory: str | Path, *, verify_checksums: bool = True
) -> dict[str, Any]:
    """Recompute decisive H16 preflight checks without importing its runner."""

    root = Path(result_directory).resolve()
    config = json.loads((root / "config_snapshot.json").read_text("utf-8"))
    required = set(str(name) for name in config["required_result_files"])
    found = {path.name for path in root.iterdir() if path.is_file()}
    if verify_checksums:
        exact_file_set = found == required
    else:
        exact_file_set = found == required - {
            "independent_verification.json",
            "checksums.json",
        }

    checksum_ok = True
    checksum_coverage = True
    if verify_checksums:
        checksum_path = root / "checksums.json"
        if not checksum_path.is_file():
            checksum_ok = False
            checksum_coverage = False
        else:
            checksums = json.loads(checksum_path.read_text("utf-8"))
            checksum_coverage = set(checksums) == required - {"checksums.json"}
            checksum_ok = checksum_coverage and all(
                (root / name).is_file() and _sha256(root / name) == expected
                for name, expected in checksums.items()
            )

    source = np.load(root / "preflight_arrays.npz", allow_pickle=False)
    arrays = {name: source[name] for name in source.files}
    modes = np.asarray(arrays["true_parameter_indices"], dtype=np.int64)
    sources = np.asarray(arrays["active_source_indices"], dtype=np.int64)
    ages = np.asarray(arrays["regime_age_before_transition"], dtype=np.int64)
    oracle = np.asarray(
        arrays["oracle_active_row_probabilities"], dtype=np.float64
    )
    evaluated = np.asarray(arrays["transition_evaluation_mask"], dtype=np.bool_)
    switched = np.asarray(arrays["switch_event_mask"], dtype=np.bool_)
    day_count = modes.shape[1]
    expected_evaluation = np.ones_like(evaluated)
    expected_evaluation[:, 0] = False
    evaluation_mask_legal = np.array_equal(evaluated, expected_evaluation)
    source_indices_match = np.array_equal(sources[:, 1:], modes[:, :-1]) and np.all(
        sources[:, 0] == -1
    )
    switch_mask_matches = np.array_equal(
        switched[:, 1:], modes[:, 1:] != modes[:, :-1]
    ) and not np.any(switched[:, 0])

    expected_oracle = np.zeros_like(oracle)
    for block, day in zip(*np.nonzero(evaluated)):
        source_mode = int(sources[block, day])
        switch_hazard = _hazard(int(ages[block, day]), config["duration_hazard"])
        expected_oracle[block, day] = switch_hazard / 2.0
        expected_oracle[block, day, source_mode] = 1.0 - switch_hazard
    oracle_difference = float(np.max(np.abs(oracle - expected_oracle)))
    oracle_row_sum_error = float(
        np.max(np.abs(oracle[evaluated].sum(axis=-1) - 1.0))
    )

    assimilation_days = int(config["data"]["assimilation_days"])
    assimilation_switches = switched[:, :assimilation_days]
    total_events = int(np.count_nonzero(assimilation_switches))
    parameter_ids = tuple(np.asarray(arrays["parameter_ids"]).astype(str).tolist())
    directed: dict[str, int] = {}
    for source_mode in range(3):
        for destination_mode in range(3):
            if source_mode == destination_mode:
                continue
            count = int(
                np.count_nonzero(
                    assimilation_switches
                    & (sources == source_mode)[:, :assimilation_days]
                    & (modes == destination_mode)[:, :assimilation_days]
                )
            )
            directed[
                f"{parameter_ids[source_mode]}->{parameter_ids[destination_mode]}"
            ] = count
    event_audit = json.loads((root / "event_coverage_audit.json").read_text("utf-8"))
    event_counts_match = (
        total_events == int(event_audit["total_switch_events"])
        and directed == event_audit["directed_transition_counts"]
    )

    hazard_audit = json.loads((root / "hazard_audit.json").read_text("utf-8"))
    independent_duration_mean = _duration_mean(config["duration_hazard"])
    hazard_summary_matches = math.isclose(
        independent_duration_mean,
        float(hazard_audit["expected_duration_days"]),
        rel_tol=0.0,
        abs_tol=1e-12,
    ) and math.isclose(
        1.0 - 1.0 / independent_duration_mean,
        float(config["filter"]["base_transition_stay_probability"]),
        rel_tol=0.0,
        abs_tol=1e-15,
    )

    probability_audit = json.loads(
        (root / "probability_range_audit.json").read_text("utf-8")
    )
    lower, upper = _probability_bounds(config)
    truth_minimum = float(config["network_output_contract"]["truth_total_hazard_minimum"])
    truth_maximum = float(config["network_output_contract"]["truth_total_hazard_maximum"])
    probability_bounds_match = (
        math.isclose(
            lower,
            float(probability_audit["minimum_total_switch_hazard"]),
            rel_tol=0.0,
            abs_tol=1e-15,
        )
        and math.isclose(
            upper,
            float(probability_audit["maximum_total_switch_hazard"]),
            rel_tol=0.0,
            abs_tol=1e-15,
        )
        and lower <= truth_minimum
        and upper >= truth_maximum
    )

    initialization_audit = json.loads(
        (root / "initialization_audit.json").read_text("utf-8")
    )
    state_difference = float(
        np.max(
            np.abs(
                arrays["initialization_reference_states"]
                - arrays["initialization_counterfactual_states"]
            )
        )
    )
    covariance_difference = float(
        np.max(
            np.abs(
                arrays["initialization_reference_covariances"]
                - arrays["initialization_counterfactual_covariances"]
            )
        )
    )
    initialization_matches = (
        state_difference
        == float(
            initialization_audit["maximum_initial_state_counterfactual_difference"]
        )
        == 0.0
        and covariance_difference
        == float(
            initialization_audit[
                "maximum_initial_covariance_counterfactual_difference"
            ]
        )
        == 0.0
        and np.all(
            arrays["initialization_reference_first_modes"]
            != arrays["initialization_counterfactual_first_modes"]
        )
    )

    projection_maximum = float(np.max(np.abs(arrays["projection_adjustments"])))
    projection_audit_matches = projection_maximum == 0.0
    signal_audit = json.loads((root / "signal_audit.json").read_text("utf-8"))
    signal_ratio = _recompute_signal_ratio(arrays, config)
    signal_audit_matches = math.isclose(
        signal_ratio,
        float(signal_audit["minimum_pairwise_rmse_to_observation_sd_ratio"]),
        rel_tol=0.0,
        abs_tol=1e-12,
    )

    interface_audit = json.loads((root / "interface_audit.json").read_text("utf-8"))
    forbidden_fields = set(interface_audit["forbidden_truth_fields"])
    observable_fields = set(interface_audit["observable_field_names"])
    interface_matches = (
        not (forbidden_fields & observable_fields)
        and int(interface_audit["forbidden_observable_truth_field_count"]) == 0
        and interface_audit["current_observation_is_transition_input"] is False
        and interface_audit["block_identifiers_available"] is False
        and interface_audit["random_seeds_available"] is False
    )
    forecast_audit = json.loads(
        (root / "forecast_contract_audit.json").read_text("utf-8")
    )
    forecast_contract_matches = (
        forecast_audit["origin_state"] == config["forecast"]["origin_state"]
        and forecast_audit["parameter_readout"]
        == config["forecast"]["parameter_readout"]
        and forecast_audit["candidate_trajectories_used"] is False
        and forecast_audit["primary_readout_contract_passed"] is True
    )

    legacy = json.loads(
        (root / "legacy_initialization_channel_audit.json").read_text("utf-8")
    )
    legacy_logic_matches = bool(
        legacy["legacy_initial_state_leakage_established"]
    ) == bool(
        legacy["legacy_initialization_depends_on_first_true_mode"]
        and legacy["maximum_day_0_transition_coordinate_range"] > 0.0
        and legacy["trained_history_network_day_0_prior_top_label_accuracy"]
        > legacy["majority_class_accuracy"]
    )

    report = json.loads((root / "preflight_report.json").read_text("utf-8"))
    saved_gates_passed = all(
        bool(values["passed"]) for values in report["gates"].values()
    )
    report_logic_matches = bool(report["preflight_passed"]) == saved_gates_passed
    no_training_artifacts = (
        report["execution"]
        == {
            "training_started": False,
            "checkpoint_created": False,
            "optimizer_created": False,
        }
        and not any(path.suffix == ".pt" or "checkpoint" in path.name for path in root.iterdir())
    )

    checks = {
        "exact_required_file_set": bool(exact_file_set),
        "checksum_coverage": bool(checksum_coverage),
        "checksums": bool(checksum_ok),
        "evaluation_mask_has_only_day_0_excluded": bool(evaluation_mask_legal),
        "source_indices_match_previous_modes": bool(source_indices_match),
        "switch_mask_matches_mode_changes": bool(switch_mask_matches),
        "oracle_active_rows_match_frozen_hazard": oracle_difference == 0.0,
        "oracle_active_rows_sum_to_one": oracle_row_sum_error
        <= float(config["capability_gates"]["maximum_oracle_active_row_sum_error"]),
        "event_counts_match": bool(event_counts_match),
        "hazard_summary_matches": bool(hazard_summary_matches),
        "probability_bounds_match": bool(probability_bounds_match),
        "initialization_counterfactuals_match": bool(initialization_matches),
        "zero_projection_matches": bool(projection_audit_matches),
        "signal_audit_matches": bool(signal_audit_matches),
        "observation_only_interface_matches": bool(interface_matches),
        "single_global_state_forecast_contract_matches": bool(
            forecast_contract_matches
        ),
        "legacy_leakage_logic_matches": bool(legacy_logic_matches),
        "preflight_gate_logic_matches": bool(report_logic_matches),
        "no_training_or_checkpoint_artifacts": bool(no_training_artifacts),
        "array_day_count_matches_config": day_count
        == int(config["data"]["assimilation_days"])
        + int(config["data"]["maximum_forecast_lead"]),
    }
    return {
        "experiment_id": config["experiment_id"],
        "verified": all(checks.values()),
        "checksum_verification_requested": bool(verify_checksums),
        "checks": checks,
        "independent_values": {
            "expected_duration_days": independent_duration_mean,
            "total_switch_events": total_events,
            "directed_transition_counts": directed,
            "maximum_oracle_probability_difference": oracle_difference,
            "maximum_oracle_active_row_sum_error": oracle_row_sum_error,
            "minimum_total_switch_hazard": lower,
            "maximum_total_switch_hazard": upper,
            "maximum_initial_state_counterfactual_difference": state_difference,
            "maximum_initial_covariance_counterfactual_difference": covariance_difference,
            "maximum_absolute_projection_adjustment": projection_maximum,
            "minimum_pairwise_rmse_to_observation_sd_ratio": signal_ratio,
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("result_directory")
    arguments = parser.parse_args()
    result = verify_h16_result(arguments.result_directory)
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()

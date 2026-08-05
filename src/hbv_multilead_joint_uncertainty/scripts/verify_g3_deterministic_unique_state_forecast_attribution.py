"""Independently verify deterministic unique-state forecast attribution."""

from __future__ import annotations

import argparse
import hashlib
import json
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
    project_reference_state,
    reference_routed_discharge,
)


DEFAULT_RESULT = (
    PROJECT_ROOT
    / "results"
    / "23_hbv_multilead_joint_uncertainty"
    / "g3_deterministic_unique_state_forecast_attribution_v01"
)
STATE_SOURCES = (
    "posterior_all_states",
    "truth_all_states",
    "posterior_hydrologic_truth_routing",
    "truth_hydrologic_posterior_routing",
)
PARAMETER_SOURCES = (
    "true_stage_parameters",
    "posterior_weighted_parameters",
    "maximum_posterior_parameters",
)
METHODS = tuple(
    f"{state_source}__{parameter_source}"
    for state_source in STATE_SOURCES
    for parameter_source in PARAMETER_SOURCES
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
    return float(np.max(np.abs(left_values - right_values), initial=0.0))


def _parameter_map(vector) -> dict[str, float]:
    return {
        name: float(value)
        for name, value in zip(PARAMETER_NAMES, np.asarray(vector, dtype=np.float64))
    }


def _reference_forecast(state, parameters, forcing, leads) -> np.ndarray:
    current = np.asarray(state, dtype=np.float64).copy()
    mapping = _parameter_map(parameters)
    result = np.empty(len(leads), dtype=np.float64)
    lead_to_row = {int(lead): row for row, lead in enumerate(leads)}
    for step in range(1, int(leads[-1]) + 1):
        current = advance_reference_state(current, *forcing[step - 1], mapping)
        if step in lead_to_row:
            result[lead_to_row[step]] = reference_routed_discharge(
                current, mapping["lag_time"]
            )
    return result


def _rebuild_state_sources(posterior, truth) -> dict[str, np.ndarray]:
    posterior_hydrologic = truth.copy()
    posterior_hydrologic[..., :5] = posterior[..., :5]
    posterior_routing = truth.copy()
    posterior_routing[..., 5:] = posterior[..., 5:]
    return {
        "posterior_all_states": posterior,
        "truth_all_states": truth,
        "posterior_hydrologic_truth_routing": posterior_hydrologic,
        "truth_hydrologic_posterior_routing": posterior_routing,
    }


def _recompute_forecasts(
    states,
    parameters,
    active_forcing,
    origins,
    leads,
) -> dict[str, np.ndarray]:
    shape = (
        next(iter(states.values())).shape[0],
        next(iter(states.values())).shape[1],
        len(origins),
        len(leads),
    )
    result = {}
    for state_name in STATE_SOURCES:
        for parameter_name in PARAMETER_SOURCES:
            method = f"{state_name}__{parameter_name}"
            values = np.empty(shape, dtype=np.float64)
            for block in range(shape[0]):
                for truth in range(shape[1]):
                    for row, origin in enumerate(origins):
                        values[block, truth, row] = _reference_forecast(
                            states[state_name][block, truth, row],
                            parameters[parameter_name][block, truth, row],
                            active_forcing[block, origin + 1 : origin + 8],
                            leads,
                        )
            result[method] = values
            print(f"independent deterministic methods {len(result)}/{len(METHODS)}", flush=True)
    return result


def _forecast_statistics(forecasts, truth, mask, bootstrap):
    squared = {}
    rmse = {}
    block_mse = {}
    for method in METHODS:
        errors = np.square(forecasts[method] - truth)
        squared[method] = errors
        rmse_values = np.empty(7)
        blocks = np.empty((truth.shape[0], 7))
        for lead in range(7):
            selected = errors[..., lead][:, mask[..., lead]]
            rmse_values[lead] = np.sqrt(np.mean(selected))
            blocks[:, lead] = np.mean(selected, axis=1)
        rmse[method] = rmse_values
        block_mse[method] = blocks
    pairs = (
        (
            "truth_all_states__true_stage_parameters",
            "posterior_all_states__true_stage_parameters",
        ),
        (
            "posterior_all_states__true_stage_parameters",
            "posterior_all_states__posterior_weighted_parameters",
        ),
        (
            "posterior_hydrologic_truth_routing__true_stage_parameters",
            "posterior_all_states__true_stage_parameters",
        ),
        (
            "truth_hydrologic_posterior_routing__true_stage_parameters",
            "posterior_all_states__true_stage_parameters",
        ),
    )
    comparisons = {}
    for left, right in pairs:
        difference = block_mse[left] - block_mse[right]
        boot = np.mean(difference[bootstrap], axis=1)
        comparisons[f"{left}__minus__{right}"] = {
            "block_mean_mse_difference": difference,
            "mean_mse_difference": np.mean(difference, axis=0),
            "ci_low": np.quantile(boot, 0.025, axis=0),
            "ci_high": np.quantile(boot, 0.975, axis=0),
            "left_rmse": rmse[left],
            "right_rmse": rmse[right],
            "relative_rmse_fraction": rmse[left] / rmse[right] - 1.0,
        }
    return squared, rmse, block_mse, comparisons


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--result-dir", type=Path, default=DEFAULT_RESULT)
    args = parser.parse_args()
    result_dir = args.result_dir.resolve()
    config = json.loads(
        (result_dir / "config_snapshot.json").read_text(encoding="utf-8")
    )
    ideal_path = PROJECT_ROOT / config["sealed_ideal_evidence"]["path"]
    readout_path = PROJECT_ROOT / config["sealed_readout_evidence"]["path"]
    if _sha256(ideal_path) != config["sealed_ideal_evidence"]["sha256"]:
        raise ValueError("sealed ideal evidence SHA-256 mismatch")
    if _sha256(readout_path) != config["sealed_readout_evidence"]["sha256"]:
        raise ValueError("sealed readout evidence SHA-256 mismatch")
    with np.load(result_dir / "evidence.npz", allow_pickle=False) as saved_archive:
        saved = {name: saved_archive[name].copy() for name in saved_archive.files}

    with np.load(ideal_path, allow_pickle=False) as ideal, np.load(
        readout_path, allow_pickle=False
    ) as readout:
        assimilation_days = int(np.asarray(ideal["assimilation_days"]).item())
        warmup = int(np.asarray(ideal["warmup_days"]).item())
        active_forcing = np.asarray(ideal["forcing_blocks"], dtype=np.float64)[:, warmup:]
        truth_parameter_indices = np.asarray(ideal["truth_parameter_indices"], dtype=np.int64)
        parameter_vectors = np.asarray(ideal["parameter_vectors"], dtype=np.float64)
        origins = np.arange(assimilation_days, dtype=np.int64)
        leads = np.arange(1, 8, dtype=np.int64)
        targets = origins[:, None] + leads[None, :]
        origin_parameter_indices = truth_parameter_indices[:, origins]
        target_parameter_indices = truth_parameter_indices[:, targets]
        same_stage = target_parameter_indices == origin_parameter_indices[:, :, None]
        truth_states_all = np.asarray(ideal["truth_states"], dtype=np.float64)
        truth_origin_states = truth_states_all[:, :, :assimilation_days]
        method_names = tuple(str(value) for value in ideal["method_names"])
        primary_index = method_names.index("parameter_only")
        method_states = np.asarray(
            ideal["method_assimilation_states"][:, :, :, :assimilation_days],
            dtype=np.float64,
        )
        posterior_states = method_states[:, :, primary_index]
        probabilities = np.asarray(
            ideal["method_assimilation_probabilities"][
                :, :, primary_index, :assimilation_days, :3
            ],
            dtype=np.float64,
        )
        probabilities /= np.sum(probabilities, axis=-1)[..., None]
        parameter_sources = {
            "true_stage_parameters": np.broadcast_to(
                parameter_vectors[truth_parameter_indices[:, :assimilation_days]][None, ...],
                (*posterior_states.shape[:3], len(PARAMETER_NAMES)),
            ).copy(),
            "posterior_weighted_parameters": np.einsum(
                "btoc,cp->btop", probabilities, parameter_vectors
            ),
            "maximum_posterior_parameters": parameter_vectors[
                np.argmax(probabilities, axis=-1)
            ],
        }
        state_sources = _rebuild_state_sources(posterior_states, truth_origin_states)
        truth_discharge = np.asarray(ideal["truth_discharge"], dtype=np.float64)
        truth_forecasts = np.empty((8, 3, 540, 7), dtype=np.float64)
        for block in range(8):
            for truth in range(3):
                truth_forecasts[block, truth] = truth_discharge[block, truth, targets]
        forecasts = _recompute_forecasts(
            state_sources,
            parameter_sources,
            active_forcing,
            origins,
            leads,
        )
        bootstrap = saved["bootstrap_indices"]
        squared, rmse, block_mse, comparisons = _forecast_statistics(
            forecasts, truth_forecasts, same_stage, bootstrap
        )

        state_errors = method_states - truth_origin_states[:, :, None]
        state_squared = np.square(state_errors)
        complete_rmse = np.sqrt(np.mean(state_squared, axis=(0, 1, 3)))
        complete_block_mse = np.mean(state_squared, axis=(1, 3))
        complete_group_rmse = np.column_stack(
            (
                np.sqrt(np.mean(state_squared[..., :5], axis=(0, 1, 3, 4))),
                np.sqrt(np.mean(state_squared[..., 5:], axis=(0, 1, 3, 4))),
            )
        )
        origin_predictions = np.empty(method_states.shape[:4], dtype=np.float64)
        for block in range(8):
            for truth in range(3):
                for method in range(len(method_names)):
                    for day in range(assimilation_days):
                        parameters = _parameter_map(
                            parameter_vectors[truth_parameter_indices[truth, day]]
                        )
                        physical = project_reference_state(
                            method_states[block, truth, method, day], parameters
                        )
                        origin_predictions[block, truth, method, day] = (
                            reference_routed_discharge(physical, parameters["lag_time"])
                        )
        origin_rmse = np.sqrt(
            np.mean(
                np.square(
                    origin_predictions
                    - truth_discharge[:, :, None, :assimilation_days]
                ),
                axis=(0, 1, 3),
            )
        )

        historical_expected = {}
        deterministic_common = forecasts[
            "posterior_all_states__true_stage_parameters"
        ][:, :, 180:540]
        historical_truth = np.asarray(readout["truth_forecasts"], dtype=np.float64)
        historical_mask = np.asarray(readout["same_stage_mask"], dtype=bool)
        for control_name, key in (
            (
                "full_interaction_multiple_trajectory_ensemble",
                "forecast__current_multiple_states",
            ),
            (
                "no_state_interaction_multiple_trajectory_ensemble",
                "forecast__no_state_interaction_multiple_states",
            ),
        ):
            control = np.asarray(readout[key], dtype=np.float64)
            left_squared = np.square(deterministic_common - historical_truth)
            right_squared = np.square(control - historical_truth)
            left_rmse = np.empty(7)
            control_rmse = np.empty(7)
            difference = np.empty((8, 7))
            for lead in range(7):
                selected = historical_mask[:, lead]
                left = left_squared[:, :, selected, lead]
                right = right_squared[:, :, selected, lead]
                left_rmse[lead] = np.sqrt(np.mean(left))
                control_rmse[lead] = np.sqrt(np.mean(right))
                difference[:, lead] = np.mean(left - right, axis=(1, 2))
            boot = np.mean(difference[bootstrap], axis=1)
            historical_expected[f"{control_name}__forecast"] = control
            historical_expected[f"{control_name}__left_rmse"] = left_rmse
            historical_expected[f"{control_name}__control_rmse"] = control_rmse
            historical_expected[f"{control_name}__block_mse_difference"] = difference
            historical_expected[f"{control_name}__ci_low"] = np.quantile(boot, 0.025, axis=0)
            historical_expected[f"{control_name}__ci_high"] = np.quantile(boot, 0.975, axis=0)

    expected = {
        "lead_days": leads,
        "origin_indices": origins,
        "target_indices": targets,
        "origin_parameter_indices": origin_parameter_indices,
        "target_parameter_indices": target_parameter_indices,
        "same_stage_mask": same_stage,
        "cross_switch_mask": ~same_stage,
        "truth_forecasts": truth_forecasts,
        "complete_state_all_day_rmse": complete_rmse,
        "complete_state_block_mse": complete_block_mse,
        "complete_state_group_rmse": complete_group_rmse,
        "origin_discharge_rmse_using_true_lag": origin_rmse,
        "parameter_vectors": parameter_vectors,
        "truth_parameter_vectors": parameter_sources["true_stage_parameters"],
        "posterior_weighted_parameter_vectors": parameter_sources[
            "posterior_weighted_parameters"
        ],
        "maximum_posterior_parameter_vectors": parameter_sources[
            "maximum_posterior_parameters"
        ],
        "posterior_states": posterior_states,
        "truth_origin_states": truth_origin_states,
    }
    for method in METHODS:
        expected[f"forecast__{method}"] = forecasts[method]
        expected[f"squared_error__{method}"] = squared[method]
        expected[f"rmse__{method}"] = rmse[method]
        expected[f"block_mse__{method}"] = block_mse[method]
    for name, values in comparisons.items():
        for field, value in values.items():
            expected[f"comparison__{name}__{field}"] = value
    for name, value in historical_expected.items():
        expected[f"historical__{name}"] = value

    differences = {
        name: _maximum_difference(saved[name], value)
        for name, value in expected.items()
    }
    label_checks = {
        "method_names": tuple(saved["method_names"].astype(str)) == METHODS,
        "state_source_names": tuple(saved["state_source_names"].astype(str))
        == STATE_SOURCES,
        "parameter_source_names": tuple(saved["parameter_source_names"].astype(str))
        == PARAMETER_SOURCES,
        "complete_state_method_names": tuple(
            saved["complete_state_method_names"].astype(str)
        )
        == method_names,
    }
    tolerance = float(config["numerical_tolerances"]["independent_forecast"])
    passed = all(value <= tolerance for value in differences.values()) and all(
        label_checks.values()
    )
    report = {
        "status": "passed" if passed else "failed",
        "independent_reference_model": True,
        "production_forecast_module_imported": False,
        "tolerance": tolerance,
        "maximum_absolute_differences": differences,
        "label_checks": label_checks,
        "maximum_absolute_difference_overall": max(differences.values()),
        "evidence_sha256": _sha256(result_dir / "evidence.npz"),
        "sealed_ideal_evidence_sha256": _sha256(ideal_path),
        "sealed_readout_evidence_sha256": _sha256(readout_path),
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

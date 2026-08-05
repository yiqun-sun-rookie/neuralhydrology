"""Independently recompute the forecast-sensitive state-error experiment."""

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

from hbv_joint_uncertainty.hbv_adapter import (  # noqa: E402
    HYDRO_STATE_NAMES,
    PARAMETER_NAMES,
    STATE_NAMES,
)
from hbv_multilead_joint_uncertainty.synthetic_truth import (  # noqa: E402
    advance_reference_state,
    reference_routed_discharge,
)


DEFAULT_RESULT = (
    PROJECT_ROOT
    / "results/23_hbv_multilead_joint_uncertainty/"
    "g3_forecast_sensitive_state_error_attribution_v01"
)
METHODS = ("parameter_only", "joint")
INTERVENTIONS = (
    "baseline_estimated",
    *(f"truth_component__{name}" for name in STATE_NAMES),
    "truth_hydrologic_group",
    "truth_routing_group",
    "truth_all_states",
)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _maximum_difference(left, right) -> float:
    left_values = np.asarray(left)
    right_values = np.asarray(right)
    if left_values.shape != right_values.shape:
        return float("inf")
    if left_values.dtype.kind in "OUS" or right_values.dtype.kind in "OUS":
        return 0.0 if np.array_equal(left_values.astype(str), right_values.astype(str)) else float("inf")
    if left_values.dtype.kind == "b" or right_values.dtype.kind == "b":
        return 0.0 if np.array_equal(left_values, right_values) else float("inf")
    if not np.all(np.isfinite(left_values)) or not np.all(np.isfinite(right_values)):
        return float("inf")
    return float(np.max(np.abs(left_values.astype(float) - right_values.astype(float))))


def _parameter_map(vector) -> dict[str, float]:
    values = np.asarray(vector, dtype=np.float64)
    return {name: float(value) for name, value in zip(PARAMETER_NAMES, values)}


def _reference_forecast(state, parameter_vector, forcing, leads) -> np.ndarray:
    parameters = _parameter_map(parameter_vector)
    current = np.asarray(state, dtype=np.float64).copy()
    result = np.empty(len(leads), dtype=np.float64)
    lead_to_row = {int(value): row for row, value in enumerate(leads)}
    for step in range(1, int(leads[-1]) + 1):
        current = advance_reference_state(
            current,
            *np.asarray(forcing[step - 1], dtype=np.float64),
            parameters,
        )
        if step in lead_to_row:
            result[lead_to_row[step]] = reference_routed_discharge(
                current, parameters["lag_time"]
            )
    return result


def _rebuild_interventions(estimated, truth) -> dict[str, np.ndarray]:
    estimated_values = np.asarray(estimated, dtype=np.float64)
    truth_values = np.asarray(truth, dtype=np.float64)
    result = {"baseline_estimated": estimated_values.copy()}
    for index, name in enumerate(STATE_NAMES):
        corrected = estimated_values.copy()
        corrected[..., index] = truth_values[..., index]
        result[f"truth_component__{name}"] = corrected
    hydro_count = len(HYDRO_STATE_NAMES)
    corrected_hydro = estimated_values.copy()
    corrected_hydro[..., :hydro_count] = truth_values[..., :hydro_count]
    corrected_routing = estimated_values.copy()
    corrected_routing[..., hydro_count:] = truth_values[..., hydro_count:]
    result["truth_hydrologic_group"] = corrected_hydro
    result["truth_routing_group"] = corrected_routing
    result["truth_all_states"] = truth_values.copy()
    return result


def _recompute_statistics(forecasts, truth, mask, bootstrap, threshold):
    rmse = np.empty((len(METHODS), len(INTERVENTIONS), 7), dtype=np.float64)
    block_mse = np.empty((len(METHODS), len(INTERVENTIONS), 8, 7), dtype=np.float64)
    for method_index, method in enumerate(METHODS):
        for intervention_index, intervention in enumerate(INTERVENTIONS):
            squared = np.square(forecasts[method][intervention] - truth)
            for lead in range(7):
                selected = squared[..., lead][:, mask[..., lead]]
                rmse[method_index, intervention_index, lead] = np.sqrt(np.mean(selected))
                block_mse[method_index, intervention_index, :, lead] = np.mean(selected, axis=1)
    difference = block_mse - block_mse[:, 0:1]
    mean_difference = np.mean(difference, axis=2)
    bootstrap_mean = np.mean(difference[:, :, bootstrap, :], axis=3)
    ci_low = np.quantile(bootstrap_mean, 0.025, axis=2)
    ci_high = np.quantile(bootstrap_mean, 0.975, axis=2)
    relative = rmse / rmse[:, 0:1] - 1.0
    contributor = (relative <= -threshold) & (ci_high < 0.0)
    harmful = (relative >= threshold) & (ci_low > 0.0)
    contributor[:, 0] = False
    harmful[:, 0] = False
    component_order = np.argsort(rmse[:, 1:16, :], axis=1)
    ranking = np.asarray(INTERVENTIONS[1:16], dtype=str)[component_order]
    return {
        "rmse": rmse,
        "block_mse": block_mse,
        "block_mse_difference_from_baseline": difference,
        "mean_mse_difference_from_baseline": mean_difference,
        "ci_low": ci_low,
        "ci_high": ci_high,
        "relative_rmse_change": relative,
        "material_contributor": contributor,
        "material_harmful": harmful,
        "component_ranking": ranking,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--result-dir", type=Path, default=DEFAULT_RESULT)
    args = parser.parse_args()
    result_dir = args.result_dir.resolve()
    config = json.loads((result_dir / "config_snapshot.json").read_text(encoding="utf-8"))
    source = (PROJECT_ROOT / config["sealed_ideal_evidence"]["path"]).resolve()
    source_sha = _sha256(source)
    if source_sha != config["sealed_ideal_evidence"]["sha256"]:
        raise ValueError("sealed source hash changed")

    with np.load(source, allow_pickle=False) as source_data, np.load(
        result_dir / "evidence.npz", allow_pickle=False
    ) as saved:
        method_names = tuple(str(value) for value in source_data["method_names"])
        if method_names != ("open_loop", "fixed_filter", "parameter_only", "noise_only", "joint"):
            raise ValueError("sealed method order changed")
        assimilation_days = int(np.asarray(source_data["assimilation_days"]).item())
        leads = np.asarray(config["lead_days"], dtype=np.int64)
        origins = np.arange(assimilation_days, dtype=np.int64)
        targets = origins[:, None] + leads[None, :]
        schedule = np.asarray(source_data["truth_parameter_indices"], dtype=np.int64)
        origin_parameters = schedule[:, origins]
        target_parameters = schedule[:, targets]
        mask = target_parameters == origin_parameters[:, :, None]
        truth_discharge = np.asarray(source_data["truth_discharge"], dtype=np.float64)
        truth_forecasts = np.empty((8, 3, 540, 7), dtype=np.float64)
        for block in range(8):
            for truth_index in range(3):
                truth_forecasts[block, truth_index] = truth_discharge[
                    block, truth_index, targets
                ]
        all_states = np.asarray(
            source_data["method_assimilation_states"][..., :assimilation_days, :],
            dtype=np.float64,
        )
        truth_states = np.asarray(
            source_data["truth_states"][:, :, :assimilation_days], dtype=np.float64
        )
        state_sources = {
            method: all_states[:, :, method_names.index(method)] for method in METHODS
        }
        interventions = {
            method: _rebuild_interventions(state_sources[method], truth_states)
            for method in METHODS
        }
        parameters = np.asarray(source_data["parameter_vectors"], dtype=np.float64)
        forcing = np.asarray(source_data["forcing_blocks"], dtype=np.float64)
        warmup = int(np.asarray(source_data["warmup_days"]).item())
        active_forcing = forcing[:, warmup:]
        forecasts = {method: {} for method in METHODS}
        total = len(METHODS) * len(INTERVENTIONS)
        completed = 0
        for method in METHODS:
            for intervention in INTERVENTIONS:
                states = interventions[method][intervention]
                values = np.empty((8, 3, 540, 7), dtype=np.float64)
                for block in range(8):
                    for truth_index in range(3):
                        for origin in range(540):
                            values[block, truth_index, origin] = _reference_forecast(
                                states[block, truth_index, origin],
                                parameters[schedule[truth_index, origin]],
                                active_forcing[block, origin + 1 : origin + 8],
                                leads,
                            )
                forecasts[method][intervention] = values
                completed += 1
                print(f"independent state interventions {completed}/{total}", flush=True)

        bootstrap = np.asarray(saved["bootstrap_indices"], dtype=np.int64)
        statistics = _recompute_statistics(
            forecasts,
            truth_forecasts,
            mask,
            bootstrap,
            float(config["screening_rule"]["minimum_relative_rmse_reduction"]),
        )
        expected = {
            "method_names": np.asarray(METHODS),
            "intervention_names": np.asarray(INTERVENTIONS),
            "state_names": np.asarray(STATE_NAMES),
            "lead_days": leads,
            "origin_indices": origins,
            "target_indices": targets,
            "same_stage_mask": mask,
            "cross_switch_mask": ~mask,
            "truth_forecasts": truth_forecasts,
            "bootstrap_indices": bootstrap,
            **statistics,
        }
        for method in METHODS:
            for intervention in INTERVENTIONS:
                expected[f"forecast__{method}__{intervention}"] = forecasts[method][
                    intervention
                ]
        saved_keys = set(saved.files)
        expected_keys = set(expected)
        differences = {
            key: _maximum_difference(saved[key], value)
            for key, value in expected.items()
            if key in saved_keys
        }
        missing_keys = sorted(expected_keys - saved_keys)
        unexpected_keys = sorted(saved_keys - expected_keys)

    summary = json.loads((result_dir / "summary.json").read_text(encoding="utf-8"))
    tolerance = float(config["numerical_tolerance"])
    rmse = statistics["rmse"]
    relative = statistics["relative_rmse_change"]
    ranking = statistics["component_ranking"]
    summary_checks = {
        "baseline_rmse": all(
            np.array_equal(
                np.asarray(summary["baseline_rmse"][method]), rmse[index, 0]
            )
            for index, method in enumerate(METHODS)
        ),
        "best_single_component_by_lead": all(
            tuple(summary["best_single_component_by_lead"][method])
            == tuple(ranking[index, 0])
            for index, method in enumerate(METHODS)
        ),
        "group_relative_rmse_change": all(
            _maximum_difference(
                np.asarray(summary["group_relative_rmse_change"][method][name]),
                relative[index, INTERVENTIONS.index(name)],
            )
            <= tolerance
            for index, method in enumerate(METHODS)
            for name in (
                "truth_hydrologic_group",
                "truth_routing_group",
                "truth_all_states",
            )
        ),
    }
    maximum = max(differences.values()) if differences else float("inf")
    passed = (
        not missing_keys
        and not unexpected_keys
        and maximum <= tolerance
        and all(summary_checks.values())
    )
    report = {
        "status": "passed" if passed else "failed",
        "independent_reference_model": True,
        "production_state_intervention_module_imported": False,
        "production_deterministic_forecast_module_imported": False,
        "tolerance": tolerance,
        "maximum_absolute_difference_overall": maximum,
        "maximum_absolute_differences": differences,
        "missing_keys": missing_keys,
        "unexpected_keys": unexpected_keys,
        "summary_checks": summary_checks,
        "sealed_ideal_evidence_sha256": source_sha,
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

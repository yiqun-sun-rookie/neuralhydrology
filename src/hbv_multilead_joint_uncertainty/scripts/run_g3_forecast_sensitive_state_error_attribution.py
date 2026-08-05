"""Run marginal state-error corrections under one deterministic forecast."""

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

from hbv_joint_uncertainty.hbv_adapter import (  # noqa: E402
    PARAMETER_NAMES,
    STATE_NAMES,
)
from hbv_multilead_joint_uncertainty.deterministic_unique_state_forecast import (  # noqa: E402
    build_all_stage_daily_index,
    forecast_deterministic_state,
)
from hbv_multilead_joint_uncertainty.forecast_sensitive_state_error import (  # noqa: E402
    COMPONENT_INTERVENTIONS,
    INTERVENTION_NAMES,
    STATE_METHODS,
    build_state_interventions,
    summarize_intervention_forecasts,
)
from hbv_multilead_joint_uncertainty.synthetic_truth import (  # noqa: E402
    advance_reference_state,
    reference_routed_discharge,
)


EXPERIMENT_ID = "g3_forecast_sensitive_state_error_attribution_v01"
DEFAULT_CONFIG = (
    PROJECT_ROOT
    / "src/hbv_multilead_joint_uncertainty/configs/"
    "g3_forecast_sensitive_state_error_attribution_v01.json"
)
DEFAULT_OUTPUT = (
    PROJECT_ROOT
    / "results/23_hbv_multilead_joint_uncertainty/"
    "g3_forecast_sensitive_state_error_attribution_v01"
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


def _validate_config(config: dict) -> None:
    if config.get("experiment_id") != EXPERIMENT_ID:
        raise ValueError("unexpected experiment identifier")
    if int(config.get("assimilation_days", -1)) != 540:
        raise ValueError("assimilation days must equal 540")
    if tuple(config.get("lead_days", ())) != tuple(range(1, 8)):
        raise ValueError("lead days must equal 1 through 7")
    if tuple(config.get("state_methods", ())) != STATE_METHODS:
        raise ValueError("state method order differs from the frozen contract")
    if config.get("parameter_source") != "true_stage_parameters":
        raise ValueError("parameter source must remain true stage parameters")
    if config.get("cross_switch_policy") != "exclude_from_primary_metrics":
        raise ValueError("cross-switch policy changed")
    bootstrap = config.get("bootstrap", {})
    if int(bootstrap.get("replicates", 0)) != 20000:
        raise ValueError("bootstrap replicates must equal 20,000")
    if int(bootstrap.get("seed", -1)) != 20260801:
        raise ValueError("bootstrap seed changed")
    if bootstrap.get("unit") != "matched_block":
        raise ValueError("bootstrap unit must be matched block")
    rule = config.get("screening_rule", {})
    if float(rule.get("minimum_relative_rmse_reduction", -1.0)) != 0.01:
        raise ValueError("material reduction threshold must equal 1 percent")
    if bool(rule.get("multiplicity_controlled", True)):
        raise ValueError("exploratory intervals must not be labeled multiplicity controlled")
    resources = config.get("resource_limits", {})
    if not bool(resources.get("sequential_intervention_processing")):
        raise ValueError("interventions must be processed sequentially")
    if float(resources.get("maximum_peak_memory_gibibytes", 0.0)) > 1.0:
        raise ValueError("peak memory contract exceeds 1 gibibyte")


def _parameter_map(vector) -> dict[str, float]:
    values = np.asarray(vector, dtype=np.float64)
    if values.shape != (len(PARAMETER_NAMES),):
        raise ValueError("parameter vector shape changed")
    return {name: float(value) for name, value in zip(PARAMETER_NAMES, values)}


def _reference_forecast(state, parameter_vector, forcing, lead_days) -> np.ndarray:
    parameters = _parameter_map(parameter_vector)
    current = np.asarray(state, dtype=np.float64).copy()
    leads = np.asarray(lead_days, dtype=np.int64)
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


def _select_state_sources(method_names, method_states) -> dict[str, np.ndarray]:
    names = tuple(str(value) for value in method_names)
    states = np.asarray(method_states, dtype=np.float64)
    if names != ("open_loop", "fixed_filter", "parameter_only", "noise_only", "joint"):
        raise ValueError("sealed state method order changed")
    if states.ndim != 5 or states.shape[-1] != len(STATE_NAMES):
        raise ValueError("sealed method state shape changed")
    return {
        method: states[:, :, names.index(method)].copy()
        for method in STATE_METHODS
    }


def _truth_forecasts(truth_discharge, target_indices) -> np.ndarray:
    discharge = np.asarray(truth_discharge, dtype=np.float64)
    targets = np.asarray(target_indices, dtype=np.int64)
    if discharge.ndim != 3 or targets.ndim != 2:
        raise ValueError("truth discharge or target index shape changed")
    result = np.empty((discharge.shape[0], discharge.shape[1], *targets.shape))
    for block in range(discharge.shape[0]):
        for truth in range(discharge.shape[1]):
            result[block, truth] = discharge[block, truth, targets]
    return result


def _preflight(
    state_interventions,
    parameter_vectors,
    truth_parameter_indices,
    active_forcing,
    lead_days,
) -> tuple[int, float]:
    maximum = 0.0
    count = 0
    representative = (
        "baseline_estimated",
        COMPONENT_INTERVENTIONS[0],
        COMPONENT_INTERVENTIONS[5],
        "truth_all_states",
    )
    for method in STATE_METHODS:
        for intervention in representative:
            states = state_interventions[method][intervention]
            for block in range(states.shape[0]):
                for truth in range(states.shape[1]):
                    for origin in (0, 179, 180, 359, 360, 539):
                        parameter = parameter_vectors[
                            truth_parameter_indices[truth, origin]
                        ]
                        forcing = active_forcing[block, origin + 1 : origin + 8]
                        production = forecast_deterministic_state(
                            states[block, truth, origin],
                            parameter,
                            forcing,
                            lead_days,
                        ).discharge
                        reference = _reference_forecast(
                            states[block, truth, origin],
                            parameter,
                            forcing,
                            lead_days,
                        )
                        maximum = max(
                            maximum,
                            float(np.max(np.abs(production - reference))),
                        )
                        count += 1
    return count, maximum


def _forecast_interventions(
    state_interventions,
    parameter_vectors,
    truth_parameter_indices,
    active_forcing,
    lead_days,
) -> dict[str, dict[str, np.ndarray]]:
    forecasts: dict[str, dict[str, np.ndarray]] = {}
    total = len(STATE_METHODS) * len(INTERVENTION_NAMES)
    completed = 0
    for method in STATE_METHODS:
        forecasts[method] = {}
        for intervention in INTERVENTION_NAMES:
            states = state_interventions[method][intervention]
            values = np.empty((*states.shape[:3], len(lead_days)), dtype=np.float64)
            for block in range(states.shape[0]):
                for truth in range(states.shape[1]):
                    for origin in range(states.shape[2]):
                        parameter = parameter_vectors[
                            truth_parameter_indices[truth, origin]
                        ]
                        values[block, truth, origin] = forecast_deterministic_state(
                            states[block, truth, origin],
                            parameter,
                            active_forcing[block, origin + 1 : origin + 8],
                            lead_days,
                        ).discharge
            forecasts[method][intervention] = values
            completed += 1
            print(f"state interventions {completed}/{total}", flush=True)
    return forecasts


def _summary_payload(config, statistics, elapsed_seconds, preflight_count, preflight_maximum):
    methods = tuple(statistics["method_names"])
    interventions = tuple(statistics["intervention_names"])
    rmse = np.asarray(statistics["rmse"])
    relative = np.asarray(statistics["relative_rmse_change"])
    contributors = np.asarray(statistics["material_contributor"], dtype=bool)
    harmful = np.asarray(statistics["material_harmful"], dtype=bool)
    component_ranking = np.asarray(statistics["component_ranking"], dtype=str)
    group_names = ("truth_hydrologic_group", "truth_routing_group", "truth_all_states")
    return {
        "experiment_id": config["experiment_id"],
        "classification": config["classification"],
        "status": "complete_pending_independent_verification",
        "primary_population": config["primary_population"],
        "same_stage_sample_count_across_truth_trials": np.asarray(
            statistics["same_stage_sample_count"]
        ).tolist(),
        "baseline_rmse": {
            method: rmse[index, 0].tolist() for index, method in enumerate(methods)
        },
        "best_single_component_by_lead": {
            method: component_ranking[index, 0].tolist()
            for index, method in enumerate(methods)
        },
        "screened_material_contributors": {
            method: {
                f"lead_{lead}_day": [
                    interventions[position]
                    for position in range(1, 1 + len(COMPONENT_INTERVENTIONS))
                    if contributors[method_index, position, lead - 1]
                ]
                for lead in range(1, 8)
            }
            for method_index, method in enumerate(methods)
        },
        "screened_material_harmful_corrections": {
            method: {
                f"lead_{lead}_day": [
                    interventions[position]
                    for position in range(1, 1 + len(COMPONENT_INTERVENTIONS))
                    if harmful[method_index, position, lead - 1]
                ]
                for lead in range(1, 8)
            }
            for method_index, method in enumerate(methods)
        },
        "group_relative_rmse_change": {
            method: {
                name: relative[method_index, interventions.index(name)].tolist()
                for name in group_names
            }
            for method_index, method in enumerate(methods)
        },
        "correctness_gates": {
            "production_reference_count": preflight_count,
            "production_reference_maximum_absolute_difference": preflight_maximum,
            "full_truth_forecasts_identical_between_state_methods": bool(
                np.array_equal(
                    rmse[0, interventions.index("truth_all_states")],
                    rmse[1, interventions.index("truth_all_states")],
                )
            ),
            "covariance_used": False,
            "future_discharge_observations_used": False,
            "multiple_candidate_trajectories_used": False,
        },
        "elapsed_seconds": elapsed_seconds,
        "scope_limit": config["scope_limit"],
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    config_path = args.config.resolve()
    config = json.loads(config_path.read_text(encoding="utf-8"))
    _validate_config(config)
    source = (PROJECT_ROOT / config["sealed_ideal_evidence"]["path"]).resolve()
    source_sha = _sha256(source)
    if source_sha != config["sealed_ideal_evidence"]["sha256"]:
        raise ValueError("sealed ideal evidence SHA-256 mismatch")
    output_dir = args.output_dir.resolve()
    if output_dir.exists():
        raise FileExistsError(f"output directory already exists: {output_dir}")

    started = time.monotonic()
    with np.load(source, allow_pickle=False) as evidence:
        assimilation_days = int(np.asarray(evidence["assimilation_days"]).item())
        if assimilation_days != config["assimilation_days"]:
            raise ValueError("sealed assimilation day count changed")
        schedule = np.asarray(evidence["truth_parameter_indices"], dtype=np.int64)
        index = build_all_stage_daily_index(
            schedule,
            assimilation_days=assimilation_days,
            lead_days=config["lead_days"],
        )
        method_states = np.asarray(
            evidence["method_assimilation_states"][..., :assimilation_days, :],
            dtype=np.float64,
        )
        state_sources = _select_state_sources(evidence["method_names"], method_states)
        truth_states = np.asarray(
            evidence["truth_states"][:, :, :assimilation_days], dtype=np.float64
        )
        state_interventions = {
            method: build_state_interventions(state_sources[method], truth_states)
            for method in STATE_METHODS
        }
        parameter_vectors = np.asarray(evidence["parameter_vectors"], dtype=np.float64)
        forcing = np.asarray(evidence["forcing_blocks"], dtype=np.float64)
        warmup = int(np.asarray(evidence["warmup_days"]).item())
        active_forcing = forcing[:, warmup:]
        truth_forecasts = _truth_forecasts(
            evidence["truth_discharge"], index.target_indices
        )
        preflight_count, preflight_maximum = _preflight(
            state_interventions,
            parameter_vectors,
            schedule,
            active_forcing,
            index.lead_days,
        )
        if preflight_maximum > float(config["numerical_tolerance"]):
            raise RuntimeError("production-reference preflight failed")
        forecasts = _forecast_interventions(
            state_interventions,
            parameter_vectors,
            schedule,
            active_forcing,
            index.lead_days,
        )

    full_truth = "truth_all_states"
    full_truth_difference = float(
        np.max(
            np.abs(
                forecasts[STATE_METHODS[0]][full_truth]
                - forecasts[STATE_METHODS[1]][full_truth]
            )
        )
    )
    if full_truth_difference != 0.0:
        raise RuntimeError("full truth forecasts differ between state methods")
    bootstrap = np.random.default_rng(int(config["bootstrap"]["seed"])).integers(
        0,
        truth_forecasts.shape[0],
        size=(int(config["bootstrap"]["replicates"]), truth_forecasts.shape[0]),
        dtype=np.int64,
    )
    statistics = summarize_intervention_forecasts(
        forecasts,
        truth_forecasts,
        index.same_stage_mask,
        bootstrap,
        minimum_relative_rmse_reduction=float(
            config["screening_rule"]["minimum_relative_rmse_reduction"]
        ),
    )
    elapsed = time.monotonic() - started
    summary = _summary_payload(
        config, statistics, elapsed, preflight_count, preflight_maximum
    )
    summary["correctness_gates"][
        "full_truth_forecast_maximum_absolute_difference_between_state_methods"
    ] = full_truth_difference

    output_dir.mkdir(parents=True)
    shutil.copy2(config_path, output_dir / "config_snapshot.json")
    payload = {
        "method_names": np.asarray(STATE_METHODS),
        "intervention_names": np.asarray(INTERVENTION_NAMES),
        "state_names": np.asarray(STATE_NAMES),
        "lead_days": index.lead_days,
        "origin_indices": index.origin_indices,
        "target_indices": index.target_indices,
        "same_stage_mask": index.same_stage_mask,
        "cross_switch_mask": index.cross_switch_mask,
        "truth_forecasts": truth_forecasts,
        "bootstrap_indices": bootstrap,
        "rmse": statistics["rmse"],
        "block_mse": statistics["block_mse"],
        "block_mse_difference_from_baseline": statistics[
            "block_mse_difference_from_baseline"
        ],
        "mean_mse_difference_from_baseline": statistics[
            "mean_mse_difference_from_baseline"
        ],
        "ci_low": statistics["ci_low"],
        "ci_high": statistics["ci_high"],
        "relative_rmse_change": statistics["relative_rmse_change"],
        "material_contributor": statistics["material_contributor"],
        "material_harmful": statistics["material_harmful"],
        "component_ranking": statistics["component_ranking"],
    }
    for method in STATE_METHODS:
        for intervention in INTERVENTION_NAMES:
            payload[f"forecast__{method}__{intervention}"] = forecasts[method][
                intervention
            ]
    np.savez_compressed(output_dir / "evidence.npz", **payload)
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

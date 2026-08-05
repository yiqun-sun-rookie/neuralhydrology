"""Run the deterministic unique-state forecast mechanism attribution audit."""

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
    routed_discharge,
)
from hbv_joint_uncertainty.preflight import project_hbv_state  # noqa: E402
from hbv_multilead_joint_uncertainty.deterministic_unique_state_forecast import (  # noqa: E402
    DETERMINISTIC_METHODS,
    PARAMETER_SOURCES,
    STATE_SOURCES,
    build_all_stage_daily_index,
    build_factorial_state_sources,
    forecast_deterministic_state,
    summarize_complete_state_error,
    summarize_deterministic_forecasts,
)
from hbv_multilead_joint_uncertainty.synthetic_truth import (  # noqa: E402
    advance_reference_state,
    reference_routed_discharge,
)


DEFAULT_CONFIG = (
    PROJECT_ROOT
    / "src"
    / "hbv_multilead_joint_uncertainty"
    / "configs"
    / "g3_deterministic_unique_state_forecast_attribution_v01.json"
)
DEFAULT_OUTPUT = (
    PROJECT_ROOT
    / "results"
    / "23_hbv_multilead_joint_uncertainty"
    / "g3_deterministic_unique_state_forecast_attribution_v01"
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


def _checked_source(root: Path, contract: dict) -> tuple[Path, str]:
    path = (root / contract["path"]).resolve()
    digest = _sha256(path)
    if digest != contract["sha256"]:
        raise ValueError(f"sealed source SHA-256 mismatch: {contract['path']}")
    return path, digest


def _validate_config(config: dict) -> None:
    if config.get("experiment_id") != "g3_deterministic_unique_state_forecast_attribution_v01":
        raise ValueError("unexpected experiment identifier")
    if int(config.get("assimilation_days", -1)) != 540:
        raise ValueError("assimilation days must equal 540")
    if tuple(config.get("lead_days", ())) != tuple(range(1, 8)):
        raise ValueError("lead days must equal 1 through 7")
    if tuple(config.get("state_sources", ())) != STATE_SOURCES:
        raise ValueError("state source order differs from the frozen contract")
    if tuple(config.get("parameter_sources", ())) != PARAMETER_SOURCES:
        raise ValueError("parameter source order differs from the frozen contract")
    bootstrap = config.get("bootstrap", {})
    if int(bootstrap.get("replicates", 0)) != 20000:
        raise ValueError("bootstrap replicates must equal 20,000")
    if bootstrap.get("unit") != "matched_block":
        raise ValueError("bootstrap unit must be matched block")
    if config.get("cross_switch_policy") != "diagnostic_only":
        raise ValueError("cross-switch forecasts must remain diagnostic only")
    if not bool(config.get("resource_limits", {}).get("sequential_method_processing")):
        raise ValueError("methods must be processed sequentially")


def _parameter_map(vector) -> dict[str, float]:
    values = np.asarray(vector, dtype=np.float64)
    if values.shape != (len(PARAMETER_NAMES),):
        raise ValueError("parameter vector has changed shape")
    return {name: float(value) for name, value in zip(PARAMETER_NAMES, values)}


def _reference_forecast(state, parameters, forcing, leads) -> np.ndarray:
    parameter_map = _parameter_map(parameters)
    current = np.asarray(state, dtype=np.float64).copy()
    result = np.empty(len(leads), dtype=np.float64)
    lead_to_row = {int(lead): row for row, lead in enumerate(leads)}
    for step in range(1, int(leads[-1]) + 1):
        current = advance_reference_state(current, *forcing[step - 1], parameter_map)
        if step in lead_to_row:
            result[lead_to_row[step]] = reference_routed_discharge(
                current, parameter_map["lag_time"]
            )
    return result


def _parameter_sources(
    parameter_vectors: np.ndarray,
    truth_parameter_indices: np.ndarray,
    probabilities: np.ndarray,
) -> dict[str, np.ndarray]:
    normalized = probabilities / np.sum(probabilities, axis=-1)[..., None]
    weighted = np.einsum("btoc,cp->btop", normalized, parameter_vectors)
    maximum = parameter_vectors[np.argmax(normalized, axis=-1)]
    truth = parameter_vectors[truth_parameter_indices]
    truth = np.broadcast_to(truth[None, ...], weighted.shape).copy()
    return {
        "true_stage_parameters": truth,
        "posterior_weighted_parameters": weighted,
        "maximum_posterior_parameters": maximum,
    }


def _truth_forecasts(truth_discharge: np.ndarray, targets: np.ndarray) -> np.ndarray:
    blocks, truths, _ = truth_discharge.shape
    result = np.empty((blocks, truths, *targets.shape), dtype=np.float64)
    for block in range(blocks):
        for truth in range(truths):
            result[block, truth] = truth_discharge[block, truth, targets]
    return result


def _transition_alignment_gate(
    truth_states,
    truth_deterministic_states,
    active_forcing,
    parameter_vectors,
    truth_parameter_indices,
) -> tuple[float, int]:
    maximum = 0.0
    count = 0
    for block in range(truth_states.shape[0]):
        for truth in range(truth_states.shape[1]):
            for target in range(1, truth_states.shape[2]):
                parameters = _parameter_map(
                    parameter_vectors[truth_parameter_indices[truth, target]]
                )
                predicted = advance_reference_state(
                    truth_states[block, truth, target - 1],
                    *active_forcing[block, target],
                    parameters,
                )
                difference = float(
                    np.max(
                        np.abs(
                            predicted
                            - truth_deterministic_states[block, truth, target]
                        )
                    )
                )
                maximum = max(maximum, difference)
                count += 1
    return maximum, count


def _production_reference_preflight(
    state_sources,
    parameter_sources,
    active_forcing,
    origins,
    leads,
) -> tuple[float, int]:
    selected_origins = np.asarray([0, 179, 180, 359, 360, 539], dtype=np.int64)
    maximum = 0.0
    count = 0
    for state_name in STATE_SOURCES:
        for parameter_name in PARAMETER_SOURCES:
            states = state_sources[state_name]
            parameters = parameter_sources[parameter_name]
            for block in range(states.shape[0]):
                for truth in range(states.shape[1]):
                    for origin in selected_origins:
                        forcing = active_forcing[block, origin + 1 : origin + 8]
                        production = forecast_deterministic_state(
                            states[block, truth, origin],
                            parameters[block, truth, origin],
                            forcing,
                            leads,
                        ).discharge
                        reference = _reference_forecast(
                            states[block, truth, origin],
                            parameters[block, truth, origin],
                            forcing,
                            leads,
                        )
                        maximum = max(
                            maximum,
                            float(np.max(np.abs(production - reference))),
                        )
                        count += 1
    if not np.array_equal(origins[selected_origins], selected_origins):
        raise ValueError("origin sequence changed during preflight")
    return maximum, count


def _run_forecasts(
    state_sources,
    parameter_sources,
    active_forcing,
    origins,
    leads,
    progress_callback=None,
) -> dict[str, np.ndarray]:
    shape = (
        next(iter(state_sources.values())).shape[0],
        next(iter(state_sources.values())).shape[1],
        len(origins),
        len(leads),
    )
    forecasts: dict[str, np.ndarray] = {}
    started = time.monotonic()
    method_number = 0
    for state_name in STATE_SOURCES:
        for parameter_name in PARAMETER_SOURCES:
            method = f"{state_name}__{parameter_name}"
            values = np.empty(shape, dtype=np.float64)
            states = state_sources[state_name]
            parameters = parameter_sources[parameter_name]
            for block in range(shape[0]):
                for truth in range(shape[1]):
                    for row, origin in enumerate(origins):
                        values[block, truth, row] = forecast_deterministic_state(
                            states[block, truth, row],
                            parameters[block, truth, row],
                            active_forcing[block, origin + 1 : origin + 8],
                            leads,
                        ).discharge
            forecasts[method] = values
            method_number += 1
            if progress_callback is not None:
                progress_callback(method_number, len(DETERMINISTIC_METHODS), time.monotonic() - started)
    return forecasts


def _origin_discharge_rmse(
    method_states,
    truth_discharge,
    parameter_vectors,
    truth_parameter_indices,
) -> np.ndarray:
    values = np.empty(method_states.shape[:4], dtype=np.float64)
    for block in range(method_states.shape[0]):
        for truth in range(method_states.shape[1]):
            for method in range(method_states.shape[2]):
                for day in range(method_states.shape[3]):
                    parameters = _parameter_map(
                        parameter_vectors[truth_parameter_indices[truth, day]]
                    )
                    physical = project_hbv_state(
                        method_states[block, truth, method, day], parameters
                    )
                    values[block, truth, method, day] = routed_discharge(
                        physical, parameters["lag_time"]
                    )
    errors = values - truth_discharge[:, :, None, : method_states.shape[3]]
    return np.sqrt(np.mean(np.square(errors), axis=(0, 1, 3)))


def _historical_control_summary(
    deterministic_forecast,
    readout,
    bootstrap,
) -> dict[str, np.ndarray]:
    controls = {
        "full_interaction_multiple_trajectory_ensemble": np.asarray(
            readout["forecast__current_multiple_states"], dtype=np.float64
        ),
        "no_state_interaction_multiple_trajectory_ensemble": np.asarray(
            readout["forecast__no_state_interaction_multiple_states"], dtype=np.float64
        ),
    }
    truth = np.asarray(readout["truth_forecasts"], dtype=np.float64)
    mask = np.asarray(readout["same_stage_mask"], dtype=bool)
    deterministic = deterministic_forecast[:, :, 180:540]
    result: dict[str, np.ndarray] = {}
    for name, values in controls.items():
        left_squared = np.square(deterministic - truth)
        right_squared = np.square(values - truth)
        left_rmse = np.empty(7)
        right_rmse = np.empty(7)
        difference = np.empty((values.shape[0], 7))
        for lead in range(7):
            selected = mask[:, lead]
            left_selected = left_squared[:, :, selected, lead]
            right_selected = right_squared[:, :, selected, lead]
            left_rmse[lead] = np.sqrt(np.mean(left_selected))
            right_rmse[lead] = np.sqrt(np.mean(right_selected))
            difference[:, lead] = np.mean(left_selected - right_selected, axis=(1, 2))
        boot = np.mean(difference[bootstrap], axis=1)
        result[f"{name}__forecast"] = values.copy()
        result[f"{name}__left_rmse"] = left_rmse
        result[f"{name}__control_rmse"] = right_rmse
        result[f"{name}__block_mse_difference"] = difference
        result[f"{name}__ci_low"] = np.quantile(boot, 0.025, axis=0)
        result[f"{name}__ci_high"] = np.quantile(boot, 0.975, axis=0)
    return result


def _summary(config, statistics, state_statistics, origin_rmse, historical, gates, elapsed):
    rmse = statistics["rmse"]
    comparisons = statistics["comparisons"]
    parameter_effect = comparisons[
        "posterior_all_states__true_stage_parameters__minus__posterior_all_states__posterior_weighted_parameters"
    ]
    routing_effect = comparisons[
        "posterior_hydrologic_truth_routing__true_stage_parameters__minus__posterior_all_states__true_stage_parameters"
    ]
    hydrologic_effect = comparisons[
        "truth_hydrologic_posterior_routing__true_stage_parameters__minus__posterior_all_states__true_stage_parameters"
    ]
    truth_effect = comparisons[
        "truth_all_states__true_stage_parameters__minus__posterior_all_states__true_stage_parameters"
    ]
    return {
        "experiment_id": config["experiment_id"],
        "classification": config["classification"],
        "status": "complete",
        "primary_population": config["primary_population"],
        "sample_shape": {
            "blocks": 8,
            "truth_trials": 3,
            "origins": 540,
            "lead_days": 7,
            "deterministic_methods": 12,
            "state_components": 15,
        },
        "same_stage_sample_count_across_truth_trials": statistics[
            "same_stage_sample_count"
        ].tolist(),
        "deterministic_rmse": {
            method: np.asarray(rmse[method]).tolist() for method in DETERMINISTIC_METHODS
        },
        "complete_state_rmse": {
            method: np.asarray(state_statistics["all_day_rmse"])[index].tolist()
            for index, method in enumerate(state_statistics["method_names"])
        },
        "state_group_rmse": {
            method: {
                "hydrologic_stores": float(state_statistics["group_rmse"][index, 0]),
                "routing_memory": float(state_statistics["group_rmse"][index, 1]),
                "origin_discharge_using_true_lag": float(origin_rmse[index]),
            }
            for index, method in enumerate(state_statistics["method_names"])
        },
        "attribution": {
            "true_complete_state_effect_relative_rmse_fraction": truth_effect[
                "relative_rmse_fraction"
            ].tolist(),
            "true_parameter_effect_relative_rmse_fraction": parameter_effect[
                "relative_rmse_fraction"
            ].tolist(),
            "true_routing_memory_effect_relative_rmse_fraction": routing_effect[
                "relative_rmse_fraction"
            ].tolist(),
            "true_hydrologic_store_effect_relative_rmse_fraction": hydrologic_effect[
                "relative_rmse_fraction"
            ].tolist(),
            "paired_95_percent_intervals": {
                name: {
                    "ci_low": value["ci_low"].tolist(),
                    "ci_high": value["ci_high"].tolist(),
                }
                for name, value in comparisons.items()
            },
        },
        "historical_ensemble_control_comparison": {
            key: value.tolist()
            for key, value in historical.items()
            if not key.endswith("__forecast")
        },
        "correctness_gates": gates,
        "elapsed_seconds": float(elapsed),
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
    ideal_path, ideal_sha = _checked_source(PROJECT_ROOT, config["sealed_ideal_evidence"])
    readout_path, readout_sha = _checked_source(PROJECT_ROOT, config["sealed_readout_evidence"])
    output_dir = args.output_dir.resolve()
    if output_dir.exists():
        raise FileExistsError(f"output directory already exists: {output_dir}")

    started = time.monotonic()
    with np.load(ideal_path, allow_pickle=False) as ideal, np.load(
        readout_path, allow_pickle=False
    ) as readout:
        assimilation_days = int(np.asarray(ideal["assimilation_days"]).item())
        if assimilation_days != 540:
            raise ValueError("sealed assimilation day count changed")
        method_names = tuple(str(value) for value in ideal["method_names"])
        primary_index = method_names.index("parameter_only")
        candidate_count = int(ideal["method_candidate_counts"][primary_index])
        if candidate_count != 3:
            raise ValueError("parameter-only candidate count changed")
        parameter_vectors = np.asarray(ideal["parameter_vectors"], dtype=np.float64)
        if parameter_vectors.shape != (3, len(PARAMETER_NAMES)):
            raise ValueError("parameter vector matrix changed")
        truth_parameter_indices = np.asarray(
            ideal["truth_parameter_indices"], dtype=np.int64
        )
        index = build_all_stage_daily_index(
            truth_parameter_indices,
            assimilation_days=assimilation_days,
            lead_days=config["lead_days"],
        )
        forcing = np.asarray(ideal["forcing_blocks"], dtype=np.float64)
        warmup = int(np.asarray(ideal["warmup_days"]).item())
        active_forcing = forcing[:, warmup:]
        truth_states_all = np.asarray(ideal["truth_states"], dtype=np.float64)
        deterministic_truth = np.asarray(
            ideal["truth_deterministic_states"], dtype=np.float64
        )
        truth_discharge = np.asarray(ideal["truth_discharge"], dtype=np.float64)
        method_states = np.asarray(
            ideal["method_assimilation_states"][:, :, :, :assimilation_days],
            dtype=np.float64,
        )
        posterior_states = method_states[:, :, primary_index]
        truth_origin_states = truth_states_all[:, :, :assimilation_days]
        probabilities = np.asarray(
            ideal["method_assimilation_probabilities"][
                :, :, primary_index, :assimilation_days, :candidate_count
            ],
            dtype=np.float64,
        )
        if not np.allclose(np.sum(probabilities, axis=-1), 1.0, rtol=0.0, atol=1e-12):
            raise ValueError("posterior candidate probabilities do not sum to one")

        transition_difference, transition_count = _transition_alignment_gate(
            truth_states_all,
            deterministic_truth,
            active_forcing,
            parameter_vectors,
            truth_parameter_indices,
        )
        posterior_alignment = float(
            np.max(
                np.abs(
                    posterior_states[:, :, 180:540]
                    - np.asarray(readout["posterior_mean_states"], dtype=np.float64)
                )
            )
        )
        state_sources = build_factorial_state_sources(
            posterior_states, truth_origin_states
        )
        parameter_sources = _parameter_sources(
            parameter_vectors,
            truth_parameter_indices[:, :assimilation_days],
            probabilities,
        )
        preflight_difference, preflight_count = _production_reference_preflight(
            state_sources,
            parameter_sources,
            active_forcing,
            index.origin_indices,
            index.lead_days,
        )
        tolerance = config["numerical_tolerances"]
        gates = {
            "truth_transition_alignment_count": int(transition_count),
            "truth_transition_alignment_maximum_absolute_difference": transition_difference,
            "truth_transition_alignment_passed": bool(
                transition_difference <= float(tolerance["source_alignment"])
            ),
            "posterior_state_archive_alignment_maximum_absolute_difference": posterior_alignment,
            "posterior_state_archive_alignment_passed": bool(
                posterior_alignment <= float(tolerance["posterior_state_alignment"])
            ),
            "production_reference_preflight_count": int(preflight_count),
            "production_reference_preflight_maximum_absolute_difference": preflight_difference,
            "production_reference_preflight_passed": bool(
                preflight_difference <= float(tolerance["independent_forecast"])
            ),
            "covariance_loaded_or_used": False,
            "future_discharge_observations_used": False,
            "all_pre_experiment_gates_passed": False,
        }
        gates["all_pre_experiment_gates_passed"] = bool(
            gates["truth_transition_alignment_passed"]
            and gates["posterior_state_archive_alignment_passed"]
            and gates["production_reference_preflight_passed"]
            and not gates["covariance_loaded_or_used"]
            and not gates["future_discharge_observations_used"]
        )
        if not gates["all_pre_experiment_gates_passed"]:
            raise RuntimeError("pre-experiment correctness gate failed")

        def progress(done, total, elapsed):
            print(f"deterministic methods {done}/{total}; elapsed={elapsed:.1f}s", flush=True)

        forecasts = _run_forecasts(
            state_sources,
            parameter_sources,
            active_forcing,
            index.origin_indices,
            index.lead_days,
            progress_callback=progress,
        )
        truth_forecasts = _truth_forecasts(truth_discharge, index.target_indices)
        bootstrap = np.random.default_rng(int(config["bootstrap"]["seed"])).integers(
            0,
            method_states.shape[0],
            size=(int(config["bootstrap"]["replicates"]), method_states.shape[0]),
            dtype=np.int64,
        )
        statistics = summarize_deterministic_forecasts(
            forecasts,
            truth_forecasts,
            index.same_stage_mask,
            bootstrap,
        )
        state_statistics = summarize_complete_state_error(
            method_states,
            truth_origin_states,
            method_names,
        )
        origin_rmse = _origin_discharge_rmse(
            method_states,
            truth_discharge,
            parameter_vectors,
            truth_parameter_indices,
        )
        historical = _historical_control_summary(
            forecasts["posterior_all_states__true_stage_parameters"],
            readout,
            bootstrap,
        )

    output_dir.mkdir(parents=True)
    shutil.copy2(config_path, output_dir / "config_snapshot.json")
    snapshot_dir = output_dir / "source_snapshot"
    snapshot_dir.mkdir()
    snapshot_sources = {
        "deterministic_unique_state_forecast.py": (
            PROJECT_ROOT
            / "src"
            / "hbv_multilead_joint_uncertainty"
            / "deterministic_unique_state_forecast.py"
        ),
        "run_g3_deterministic_unique_state_forecast_attribution.py": Path(__file__),
        "verify_g3_deterministic_unique_state_forecast_attribution.py": Path(__file__).with_name(
            "verify_g3_deterministic_unique_state_forecast_attribution.py"
        ),
        "2026-07-31-id23-deterministic-unique-state-attribution-design.md": (
            PROJECT_ROOT
            / "docs"
            / "plans"
            / "2026-07-31-id23-deterministic-unique-state-attribution-design.md"
        ),
    }
    for name, source in snapshot_sources.items():
        if source.exists():
            shutil.copy2(source, snapshot_dir / name)

    evidence = {
        "method_names": np.asarray(DETERMINISTIC_METHODS),
        "state_source_names": np.asarray(STATE_SOURCES),
        "parameter_source_names": np.asarray(PARAMETER_SOURCES),
        "complete_state_method_names": np.asarray(state_statistics["method_names"]),
        "state_names": np.asarray(state_statistics["state_names"]),
        "state_group_names": np.asarray(state_statistics["state_group_names"]),
        "lead_days": index.lead_days,
        "origin_indices": index.origin_indices,
        "target_indices": index.target_indices,
        "origin_parameter_indices": index.origin_parameter_indices,
        "target_parameter_indices": index.target_parameter_indices,
        "same_stage_mask": index.same_stage_mask,
        "cross_switch_mask": index.cross_switch_mask,
        "truth_forecasts": truth_forecasts,
        "bootstrap_indices": bootstrap,
        "complete_state_all_day_rmse": state_statistics["all_day_rmse"],
        "complete_state_block_mse": state_statistics["block_mse"],
        "complete_state_group_rmse": state_statistics["group_rmse"],
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
    for method in DETERMINISTIC_METHODS:
        evidence[f"forecast__{method}"] = forecasts[method]
        evidence[f"squared_error__{method}"] = statistics["squared_errors"][method]
        evidence[f"rmse__{method}"] = statistics["rmse"][method]
        evidence[f"block_mse__{method}"] = statistics["block_mse"][method]
    for name, values in statistics["comparisons"].items():
        for field, value in values.items():
            evidence[f"comparison__{name}__{field}"] = value
    for name, value in historical.items():
        evidence[f"historical__{name}"] = value
    np.savez_compressed(output_dir / "evidence.npz", **evidence)
    elapsed = time.monotonic() - started
    summary = _summary(
        config,
        statistics,
        state_statistics,
        origin_rmse,
        historical,
        gates,
        elapsed,
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
            "sealed_ideal_evidence": {"sha256": ideal_sha},
            "sealed_readout_evidence": {"sha256": readout_sha},
            "config_snapshot.json": _sha256(output_dir / "config_snapshot.json"),
            "evidence.npz": _sha256(output_dir / "evidence.npz"),
            "summary.json": _sha256(output_dir / "summary.json"),
            "source_snapshot": {
                path.name: _sha256(path)
                for path in sorted(snapshot_dir.iterdir())
                if path.is_file()
            },
        },
    )
    if _sha256(ideal_path) != ideal_sha or _sha256(readout_path) != readout_sha:
        raise RuntimeError("a sealed source changed during execution")
    print(json.dumps(summary, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()

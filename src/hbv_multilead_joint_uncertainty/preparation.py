"""Calibration-window preparation of complete parameter and effective-noise contracts."""

from __future__ import annotations

from collections.abc import Callable, Mapping, Sequence
from pathlib import Path

import numpy as np
import pandas as pd

from hbv_joint_uncertainty.candidates import derive_parameter_vectors, sha256_file
from hbv_joint_uncertainty.hbv_adapter import PARAMETER_NAMES, simulate_adapter
from hbv_joint_uncertainty.preflight import ForcingTransition, RoutedDischargeObservation, project_hbv_state
from hbv_joint_uncertainty.sigma_filter import ModifiedUnscentedFilter

from .contracts import TRAINING_PROJECTION_COLUMNS, csv_projection_sha256
from .selection import (
    build_frozen_process_diagonals,
    generate_local_parameter_pool,
    generate_multiscale_parameter_pool,
    observation_standard_deviation_grid,
    robust_residual_scale,
    select_equifinal_parameters,
    select_noise_grid,
)
from .forecast import _assimilation_step
from .input_audit import load_forcing_period, load_model_period
from .methods import build_method_bank, build_method_definitions, parameter_order_from_identifiers


def _forcing_array(values, label: str) -> np.ndarray:
    forcing = np.asarray(values, dtype=np.float64)
    if forcing.ndim != 2 or forcing.shape[1] != 3 or len(forcing) == 0 or not np.all(np.isfinite(forcing)):
        raise ValueError(f"{label} must be a nonempty finite array with columns rain, PET, and temperature")
    if np.any(forcing[:, :2] < 0.0):
        raise ValueError(f"{label} rain and PET must be nonnegative")
    return forcing


def _observations(values, expected_length: int) -> np.ndarray:
    observations = np.asarray(values, dtype=np.float64)
    if observations.shape != (expected_length,) or not np.all(np.isfinite(observations)):
        raise ValueError("development observations must contain one finite value per day")
    return observations


def _nse(observations: np.ndarray, predictions: np.ndarray) -> float:
    denominator = float(np.sum((observations - np.mean(observations)) ** 2))
    if denominator <= 0.0:
        raise ValueError("development observations must be nonconstant")
    return float(1.0 - np.sum((predictions - observations) ** 2) / denominator)


def _simulate_after_warmup(parameters: Mapping[str, float], warmup: np.ndarray, development: np.ndarray):
    _, warmup_states = simulate_adapter(
        warmup[:, 0], warmup[:, 1], warmup[:, 2], dict(parameters)
    )
    predictions, development_states = simulate_adapter(
        development[:, 0],
        development[:, 1],
        development[:, 2],
        dict(parameters),
        initial_state=warmup_states[-1],
    )
    return predictions, development_states, warmup_states[-1]


def evaluate_parameter_pool(
    center_parameters: Mapping[str, float],
    candidates: Sequence[Mapping[str, float]],
    warmup_forcing,
    development_forcing,
    development_observations,
    progress_callback: Callable[[str, int, int], None] | None = None,
) -> dict:
    warmup = _forcing_array(warmup_forcing, "warmup_forcing")
    development = _forcing_array(development_forcing, "development_forcing")
    observations = _observations(development_observations, len(development))
    if set(center_parameters) != set(PARAMETER_NAMES):
        raise ValueError("center_parameters must contain exactly thirteen values")
    candidate_values = [dict(values) for values in candidates]
    if not candidate_values:
        raise ValueError("candidates must be nonempty")
    center_predictions, _, center_warm_state = _simulate_after_warmup(center_parameters, warmup, development)
    scores = np.empty(len(candidate_values), dtype=np.float64)
    means = np.empty(len(candidate_values), dtype=np.float64)
    for index, parameters in enumerate(candidate_values):
        if set(parameters) != set(PARAMETER_NAMES):
            raise ValueError("every candidate must contain exactly thirteen values")
        predictions, _, _ = _simulate_after_warmup(parameters, warmup, development)
        scores[index] = _nse(observations, predictions)
        means[index] = float(np.mean(predictions))
        if progress_callback is not None:
            progress_callback("parameter_pool", index + 1, len(candidate_values))
    return {
        "center_parameters": {name: float(center_parameters[name]) for name in PARAMETER_NAMES},
        "center_nse": _nse(observations, center_predictions),
        "center_mean_discharge": float(np.mean(center_predictions)),
        "center_predictions": center_predictions,
        "center_warm_state": center_warm_state,
        "candidate_nse": scores,
        "candidate_mean_discharge": means,
    }


def evaluate_single_filter_noise_grid(
    center_parameters: Mapping[str, float],
    warmup_forcing,
    development_forcing,
    development_observations,
    process_scales,
    observation_standard_deviations,
    initial_covariance_fraction: float,
    progress_callback: Callable[[str, int, int], None] | None = None,
) -> dict:
    warmup = _forcing_array(warmup_forcing, "warmup_forcing")
    development = _forcing_array(development_forcing, "development_forcing")
    observations = _observations(development_observations, len(development))
    scales = np.asarray(process_scales, dtype=np.float64)
    observation_stds = np.asarray(observation_standard_deviations, dtype=np.float64)
    if scales.ndim != 1 or len(scales) == 0 or np.any(scales <= 0.0) or not np.all(np.isfinite(scales)):
        raise ValueError("process_scales must be a nonempty positive finite vector")
    if observation_stds.ndim != 1 or len(observation_stds) == 0 or np.any(observation_stds <= 0.0):
        raise ValueError("observation_standard_deviations must be a nonempty positive vector")
    fraction = float(initial_covariance_fraction)
    if not np.isfinite(fraction) or fraction <= 0.0:
        raise ValueError("initial_covariance_fraction must be finite and positive")
    _, warm_states = simulate_adapter(warmup[:, 0], warmup[:, 1], warmup[:, 2], dict(center_parameters))
    warm_state = warm_states[-1]
    initial_covariance = np.diag((fraction * np.maximum(np.abs(warm_state), 1.0)) ** 2)
    process_diagonals = build_frozen_process_diagonals(center_parameters, scales)
    scores = np.empty((len(scales), len(observation_stds)), dtype=np.float64)
    completed = 0
    total = len(scales) * len(observation_stds)
    for process_index, diagonal in enumerate(process_diagonals):
        for observation_index, observation_std in enumerate(observation_stds):
            transition = ForcingTransition(center_parameters)
            observation = RoutedDischargeObservation(center_parameters)
            projector = lambda values, parameters=center_parameters: project_hbv_state(values, parameters)
            candidate = ModifiedUnscentedFilter(
                state=warm_state.copy(),
                covariance=initial_covariance.copy(),
                transition=transition,
                observation=observation,
                process_covariance=np.diag(diagonal),
                observation_covariance=np.array([[observation_std**2]], dtype=np.float64),
                state_projector=projector,
                alpha=0.6874,
                beta=2.0,
                kappa=-2.0,
            )
            log_likelihoods = np.empty(len(development), dtype=np.float64)
            for day, (rain, pet, temperature) in enumerate(development):
                transition.set_forcing(rain, pet, temperature)
                log_likelihoods[day] = candidate.step(observations[day]).log_likelihood
            scores[process_index, observation_index] = float(np.mean(log_likelihoods))
            completed += 1
            if progress_callback is not None:
                progress_callback("noise_grid", completed, total)
    return {
        "mean_log_likelihoods": scores,
        "process_covariance_diagonals": process_diagonals,
        "warm_state": warm_state,
        "initial_covariance": initial_covariance,
    }


def _load_complete_period(repo_root: Path, basin_id: str, config: Mapping, start: str, end: str):
    forcing, observations = load_model_period(repo_root, basin_id, dict(config), start, end)
    expected = pd.date_range(start, end, freq="D")
    if not forcing.index.equals(expected) or not observations.index.equals(expected):
        raise ValueError(f"basin {basin_id} is not continuous from {start} through {end}")
    values = forcing[["prcp", "ep", "tmean"]].to_numpy(dtype=np.float64)
    if not np.all(np.isfinite(values)) or np.any(values[:, :2] < 0.0):
        raise ValueError(f"basin {basin_id} has invalid forcing from {start} through {end}")
    return values, observations.to_numpy(dtype=np.float64)


def _load_forcing_only_period(repo_root: Path, basin_id: str, config: Mapping, start: str, end: str):
    forcing, _ = load_forcing_period(repo_root, basin_id, dict(config), start, end)
    expected = pd.date_range(start, end, freq="D")
    if not forcing.index.equals(expected):
        raise ValueError(f"basin {basin_id} forcing is not continuous from {start} through {end}")
    values = forcing[["prcp", "ep", "tmean"]].to_numpy(dtype=np.float64)
    if not np.all(np.isfinite(values)) or np.any(values[:, :2] < 0.0):
        raise ValueError(f"basin {basin_id} has invalid forcing from {start} through {end}")
    return values


def _center_parameters(repo_root: Path, basin_id: str, config: Mapping):
    source = config["parameter_source"]
    path = repo_root / source["table_path"]
    if sha256_file(path) != source["table_sha256"]:
        raise ValueError("frozen trained parameter table checksum mismatch")
    if csv_projection_sha256(path) != source["projection_content_sha256"]:
        raise ValueError("trained parameter projection content checksum mismatch")
    metadata_path = repo_root / source["metadata_path"]
    if sha256_file(metadata_path) != source["metadata_sha256"]:
        raise ValueError("trained parameter metadata checksum mismatch")
    table = pd.read_csv(
        path,
        dtype={"basin_id": str},
        usecols=list(TRAINING_PROJECTION_COLUMNS),
    )
    table["basin_id"] = table["basin_id"].str.zfill(8)
    rows = table.loc[table["basin_id"] == basin_id]
    if len(rows) != 1 or rows.iloc[0]["run_status"] != "success":
        raise ValueError(f"basin {basin_id} does not have one successful trained parameter row")
    row = rows.iloc[0]
    return {name: float(row[f"p_{name}"]) for name in PARAMETER_NAMES}, path, metadata_path


def _parameter_pool_from_config(
    center: Mapping[str, float], selection_config: Mapping, seed: int
) -> tuple[list[dict[str, float]], list[dict], float]:
    schema_version = int(selection_config.get("schema_version", -1))
    if schema_version == 2:
        fraction = float(selection_config["local_fraction"])
        pool = generate_local_parameter_pool(
            center,
            count=int(selection_config["pool_size"]),
            fraction=fraction,
            seed=int(seed),
        )
        provenance = [
            {"candidate_index": candidate_index}
            for candidate_index in range(len(pool))
        ]
        return pool, provenance, fraction
    if schema_version == 3:
        fractions = tuple(float(value) for value in selection_config["local_fractions"])
        count_per_scale = int(selection_config["candidates_per_scale"])
        pool, provenance = generate_multiscale_parameter_pool(
            center,
            fractions=fractions,
            count_per_scale=count_per_scale,
            seed=int(seed),
        )
        if len(pool) != int(selection_config["pool_size"]):
            raise ValueError("multiscale parameter pool size differs from its frozen config")
        return pool, provenance, max(fractions)
    raise ValueError("unsupported parameter selection schema version")


def prepare_basin_uncertainty_contract(
    repo_root: Path,
    basin_id: str,
    config: Mapping,
    progress_callback: Callable[[str, int, int], None] | None = None,
) -> dict:
    """Freeze one basin contract using calibration-period data only."""
    root = Path(repo_root).resolve()
    identifier = str(basin_id).zfill(8)
    warmup = _load_forcing_only_period(
        root,
        identifier,
        config,
        config["calibration_warmup_start"],
        config["calibration_warmup_end"],
    )
    development, observations = _load_complete_period(
        root,
        identifier,
        config,
        config["calibration_selection_start"],
        config["calibration_selection_end"],
    )
    if not np.all(np.isfinite(observations)):
        raise ValueError(f"basin {identifier} has missing calibration-selection discharge")
    center, parameter_path, metadata_path = _center_parameters(root, identifier, config)
    selection_config = config["parameter_selection"]
    pool, pool_provenance, outer_fraction = _parameter_pool_from_config(
        center, selection_config, seed=int(config["random_seed"])
    )
    parameter_evaluation = evaluate_parameter_pool(
        center,
        pool,
        warmup,
        development,
        observations,
        progress_callback=progress_callback,
    )
    selected_parameters = select_equifinal_parameters(
        center=center,
        candidates=pool,
        center_nse=parameter_evaluation["center_nse"],
        center_mean_discharge=parameter_evaluation["center_mean_discharge"],
        candidate_nse=parameter_evaluation["candidate_nse"],
        candidate_mean_discharge=parameter_evaluation["candidate_mean_discharge"],
        maximum_nse_drop=float(selection_config["maximum_nse_drop"]),
    )
    center_key = tuple(center[name] for name in PARAMETER_NAMES)
    eligible_unique_keys = {
        tuple(pool[index][name] for name in PARAMETER_NAMES)
        for index in range(len(pool))
        if parameter_evaluation["candidate_nse"][index]
        >= parameter_evaluation["center_nse"] - float(selection_config["maximum_nse_drop"])
        and tuple(pool[index][name] for name in PARAMETER_NAMES) != center_key
    }
    selected_candidate_indices = [
        selected_parameters["equifinal_diverse_1"]["candidate_index"],
        selected_parameters["equifinal_diverse_2"]["candidate_index"],
    ]
    if int(selection_config["schema_version"]) == 3:
        for parameter_id in ("equifinal_diverse_1", "equifinal_diverse_2"):
            provenance = pool_provenance[
                int(selected_parameters[parameter_id]["candidate_index"])
            ]
            selected_parameters[parameter_id].update(
                {
                    key: provenance[key]
                    for key in ("scale_index", "local_fraction", "scale_candidate_index")
                }
            )
    old_vectors = derive_parameter_vectors(center, fraction=outer_fraction)
    old_rows = []
    for parameter_id, parameters in old_vectors.items():
        predictions, _, _ = _simulate_after_warmup(parameters, warmup, development)
        old_rows.append(
            {
                "parameter_id": parameter_id,
                "parameters": parameters,
                "development_nse": _nse(observations, predictions),
                "development_mean_discharge": float(np.mean(predictions)),
                "formal_candidate": False,
            }
        )

    residuals = parameter_evaluation["center_predictions"] - observations
    noise_config = config["noise_selection"]
    observation_grid = observation_standard_deviation_grid(
        residuals,
        multipliers=noise_config["observation_scale_multipliers"],
        minimum=float(noise_config["minimum_robust_residual_scale_mm_day"]),
    )
    process_grid = np.asarray(noise_config["process_variance_scales"], dtype=np.float64)
    noise_evaluation = evaluate_single_filter_noise_grid(
        center_parameters=center,
        warmup_forcing=warmup,
        development_forcing=development,
        development_observations=observations,
        process_scales=process_grid,
        observation_standard_deviations=observation_grid,
        initial_covariance_fraction=float(config["initial_covariance_fraction"]),
        progress_callback=progress_callback,
    )
    noise_selection = select_noise_grid(
        process_grid,
        observation_grid,
        noise_evaluation["mean_log_likelihoods"],
    )
    candidate_scales = noise_selection["candidate_process_scales"]
    candidate_diagonals = build_frozen_process_diagonals(center, candidate_scales)
    process_rows = []
    selected_process_id = None
    for index, (scale, diagonal) in enumerate(zip(candidate_scales, candidate_diagonals)):
        process_id = f"process_{index}"
        if float(scale) == noise_selection["selected_process_scale"]:
            selected_process_id = process_id
        covariance = np.diag(diagonal)
        process_rows.append(
            {
                "process_id": process_id,
                "variance_scale": float(scale),
                "covariance_diagonal": diagonal.tolist(),
                "covariance_matrix": covariance.tolist(),
                "nonzero_state_indices": list(range(5)),
                "zero_routing_memory_state_indices": list(range(5, 15)),
                "unit": "squared native state unit per day",
            }
        )
    if selected_process_id is None:
        raise ValueError("selected process scale is absent from the formal three-scale contract")
    pool_audit = []
    for index, parameters in enumerate(pool):
        pool_audit.append(
            {
                **pool_provenance[index],
                "parameters": parameters,
                "development_nse": float(parameter_evaluation["candidate_nse"][index]),
                "development_mean_discharge": float(parameter_evaluation["candidate_mean_discharge"][index]),
                "eligible": bool(
                    parameter_evaluation["candidate_nse"][index]
                    >= parameter_evaluation["center_nse"] - float(selection_config["maximum_nse_drop"])
                ),
            }
        )
    selection_metadata = {
        "schema_version": int(selection_config["schema_version"]),
        "strategy": selection_config["strategy"],
        "pool_generator": selection_config["pool_generator"],
        "pool_seed": int(config["random_seed"]),
        "pool_size": int(selection_config["pool_size"]),
        "maximum_nse_drop": float(selection_config["maximum_nse_drop"]),
        "normalization": "frozen_physical_bound_span",
        "distance": "euclidean",
        "objective": selection_config["objective"],
        "tie_break": "candidate_index_ascending_lexicographic",
        "eligible_distinct_candidate_count": len(eligible_unique_keys),
        "selected_candidate_indices": selected_candidate_indices,
        "selected_pair_minimum_distance": selected_parameters[
            "equifinal_diverse_1"
        ]["selected_pair_minimum_distance"],
        "mean_discharge_role": "diagnostic_only_not_a_selection_constraint",
    }
    if int(selection_config["schema_version"]) == 2:
        selection_metadata["local_fraction"] = float(selection_config["local_fraction"])
    else:
        selection_metadata.update(
            {
                "candidates_per_scale": int(selection_config["candidates_per_scale"]),
                "local_fractions": [
                    float(value) for value in selection_config["local_fractions"]
                ],
                "scale_count": len(selection_config["local_fractions"]),
                "candidate_order": selection_config["candidate_order"],
            }
        )
    return {
        "basin_id": identifier,
        "preparation_data_boundary": {
            "uses_evaluation_discharge": False,
            "calibration_warmup_start": config["calibration_warmup_start"],
            "calibration_warmup_end": config["calibration_warmup_end"],
            "calibration_selection_start": config["calibration_selection_start"],
            "calibration_selection_end": config["calibration_selection_end"],
        },
        "parameter_source": {
            "path": parameter_path.relative_to(root).as_posix(),
            "sha256": config["parameter_source"]["table_sha256"],
            "sha256_scope": "entire frozen twenty-column parameter table",
            "projection_columns": list(TRAINING_PROJECTION_COLUMNS),
            "metadata_path": metadata_path.relative_to(root).as_posix(),
            "metadata_sha256": config["parameter_source"]["metadata_sha256"],
            "calibration_start": config["parameter_source"]["calibration_start"],
            "calibration_end": config["parameter_source"]["calibration_end"],
        },
        "parameter_vectors": selected_parameters,
        "parameter_selection": selection_metadata,
        "parameter_pool_audit": pool_audit,
        "former_bound_directed_audit": old_rows,
        "center_development_nse": float(parameter_evaluation["center_nse"]),
        "robust_residual_scale_mm_day": robust_residual_scale(
            residuals, minimum=float(noise_config["minimum_robust_residual_scale_mm_day"])
        ),
        "observation_noise": {
            "candidate_standard_deviations_mm_day": observation_grid.tolist(),
            "selected_standard_deviation_mm_day": noise_selection["selected_observation_standard_deviation"],
            "selected_variance_mm2_day2": noise_selection["selected_observation_standard_deviation"] ** 2,
            "meaning": "effective observation error including measurement and unrepresented model error",
        },
        "process_noise": {
            "grid_scales": process_grid.tolist(),
            "mean_log_likelihood_grid": noise_evaluation["mean_log_likelihoods"].tolist(),
            "selected_grid_scale": noise_selection["selected_process_scale"],
            "selected_process_id": selected_process_id,
            "selected_mean_log_likelihood": noise_selection["selected_mean_log_likelihood"],
            "candidates": process_rows,
            "absolute_covariance_reference": "trained center parameter vector; reused unchanged across parameters",
        },
        "selection_initial_covariance_diagonal": np.diag(noise_evaluation["initial_covariance"]).tolist(),
    }


def _method_contract_parts(basin_contract: Mapping):
    stored_parameter_vectors = basin_contract["parameter_vectors"]
    parameter_order = parameter_order_from_identifiers(stored_parameter_vectors)
    parameter_vectors = {
        parameter_id: stored_parameter_vectors[parameter_id]["parameters"]
        for parameter_id in parameter_order
    }
    process_rows = basin_contract["process_noise"]["candidates"]
    process_scales = {row["process_id"]: row["variance_scale"] for row in process_rows}
    process_covariances = {
        row["process_id"]: np.asarray(row["covariance_matrix"], dtype=np.float64)
        for row in process_rows
    }
    return parameter_vectors, process_scales, process_covariances


def evaluate_development_interaction_modes(
    repo_root: Path,
    basin_contracts: Mapping[str, Mapping],
    config: Mapping,
    progress_callback: Callable[[str, int, int], None] | None = None,
) -> dict:
    """Compare three modes on calibration data; full interaction remains the only formal IMM mode."""
    root = Path(repo_root).resolve()
    modes = tuple(config["interaction_mode_candidates"])
    rows = []
    total = len(basin_contracts) * len(modes)
    completed = 0
    for basin_id, basin_contract in basin_contracts.items():
        warmup = _load_forcing_only_period(
            root,
            basin_id,
            config,
            config["calibration_warmup_start"],
            config["calibration_warmup_end"],
        )
        development, observations = _load_complete_period(
            root,
            basin_id,
            config,
            config["calibration_selection_start"],
            config["calibration_selection_end"],
        )
        parameter_vectors, process_scales, process_covariances = _method_contract_parts(basin_contract)
        initial_states = {}
        for parameter_id, parameters in parameter_vectors.items():
            _, states = simulate_adapter(warmup[:, 0], warmup[:, 1], warmup[:, 2], parameters)
            initial_states[parameter_id] = states[-1]
        center_state = initial_states["trained_center"]
        initial_covariance = np.diag(
            (float(config["initial_covariance_fraction"]) * np.maximum(np.abs(center_state), 1.0)) ** 2
        )
        methods = build_method_definitions(
            parameter_vectors=parameter_vectors,
            process_scales=process_scales,
            process_covariances=process_covariances,
            selected_process_id=basin_contract["process_noise"]["selected_process_id"],
        )
        for mode in modes:
            bank = build_method_bank(
                candidates=methods["joint"],
                initial_states=initial_states,
                initial_covariance=initial_covariance,
                observation_standard_deviation=basin_contract["observation_noise"][
                    "selected_standard_deviation_mm_day"
                ],
                factor_transition_stay_probability=float(
                    config["factor_transition_stay_probability"]
                ),
                interaction_mode=mode,
            )
            log_likelihoods = np.empty(len(development), dtype=np.float64)
            prior_predictions = np.empty(len(development), dtype=np.float64)
            for day, (rain, pet, temperature) in enumerate(development):
                for transition in bank.transitions:
                    transition.set_forcing(rain, pet, temperature)
                log_likelihoods[day], prior_predictions[day] = _assimilation_step(
                    bank, observations[day], mode
                )
                if progress_callback is not None:
                    progress_callback(
                        f"interaction_mode_{mode}_days",
                        day + 1,
                        len(development),
                    )
            rows.append(
                {
                    "basin_id": basin_id,
                    "interaction_mode": mode,
                    "development_mean_log_likelihood": float(np.mean(log_likelihoods)),
                    "development_one_day_nse": _nse(observations, prior_predictions),
                    "finite": bool(
                        np.all(np.isfinite(log_likelihoods))
                        and np.all(np.isfinite(prior_predictions))
                        and np.all(
                            np.isfinite(bank.estimator.global_posterior_state)
                        )
                    ),
                }
            )
            completed += 1
            if progress_callback is not None:
                progress_callback("interaction_modes", completed, total)
    summary = []
    for mode in modes:
        mode_rows = [row for row in rows if row["interaction_mode"] == mode]
        summary.append(
            {
                "interaction_mode": mode,
                "basin_count": len(mode_rows),
                "finite_basin_count": sum(row["finite"] for row in mode_rows),
                "median_development_mean_log_likelihood": float(
                    np.median([row["development_mean_log_likelihood"] for row in mode_rows])
                ),
                "median_development_one_day_nse": float(
                    np.median([row["development_one_day_nse"] for row in mode_rows])
                ),
            }
        )
    full_summary = next(row for row in summary if row["interaction_mode"] == "full")
    if full_summary["finite_basin_count"] != len(basin_contracts):
        raise ValueError("full interaction was numerically unstable on development data")
    return {
        "selected_mode": "full",
        "uses_evaluation_discharge": False,
        "selection_period_start": config["calibration_selection_start"],
        "selection_period_end": config["calibration_selection_end"],
        "selection_rule": (
            "full interaction is the only standard interacting-multiple-model state-transfer mode; "
            "parameter-grouped and no-interaction modes are retained as development diagnostics"
        ),
        "identity_dynamics_conservation_audit": {
            "full_combined_mean_error_after_three_days": 0.0,
            "parameter_grouped_combined_mean_error_after_three_days": 0.876,
            "test_reference": "test_full_interaction_preserves_mixture_mean_under_identity_dynamics",
        },
        "per_basin": rows,
        "summary": summary,
    }

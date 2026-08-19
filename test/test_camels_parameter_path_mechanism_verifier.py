import hashlib
import json
import math
import platform
import shutil
import sys
from pathlib import Path

import numpy as np
import pandas as pd
import pytest


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "src"))

import camels_switch_confirmation.verify_parameter_path_mechanism as verifier  # noqa: E402


N_DAYS = 1260
N_CANDIDATES = 3
N_STATE = 15


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _normalize_log_weights(values):
    logs = np.asarray(values, dtype=np.float64)
    finite = np.isfinite(logs)
    maximum = np.max(logs[finite])
    shifted = np.zeros_like(logs)
    shifted[finite] = np.exp(logs[finite] - maximum)
    log_normalizer = maximum + np.log(float(shifted.sum()))
    normalized_logs = np.full_like(logs, -np.inf)
    normalized_logs[finite] = logs[finite] - log_normalizer
    probabilities = np.zeros_like(logs)
    probabilities[finite] = np.exp(normalized_logs[finite])
    probability_total = float(probabilities.sum())
    probabilities /= probability_total
    normalized_logs[finite] -= np.log(probability_total)
    return probabilities, normalized_logs


def _normalize_path_weights(probabilities):
    weights = np.asarray(probabilities, dtype=np.float64)
    return weights / math.fsum(float(weight) for weight in weights)


def _mixture(states, covariances, probabilities):
    values = np.asarray(states, dtype=np.float64)
    covs = np.asarray(covariances, dtype=np.float64)
    weights = np.asarray(probabilities, dtype=np.float64)
    active = np.flatnonzero(weights > 0.0)
    values = values[active]
    covs = covs[active]
    weights = weights[active]
    total = math.fsum(float(weight) for weight in weights)
    local_reference = int(np.argmax(weights))
    reference = values[local_reference]
    mean = np.empty(values.shape[1], dtype=np.float64)
    for index in range(values.shape[1]):
        mean[index] = float(reference[index]) + math.fsum(
            float(weight) * (float(state[index]) - float(reference[index]))
            for weight, state in zip(weights, values)
        ) / total
    raw = np.empty((values.shape[1], values.shape[1]), dtype=np.float64)
    for row in range(values.shape[1]):
        for column in range(values.shape[1]):
            raw[row, column] = math.fsum(
                float(weight)
                * (
                    float(component_covariance[row, column])
                    + (float(state[row]) - float(mean[row]))
                    * (float(state[column]) - float(mean[column]))
                )
                for weight, state, component_covariance in zip(weights, values, covs)
            ) / total
    return mean, 0.5 * (raw + raw.T), int(active[local_reference])


def _candidate_logs(branch_logs):
    destination_logs = []
    for destination in range(N_CANDIDATES):
        values = branch_logs[:, destination]
        maximum = np.max(values)
        destination_logs.append(
            maximum + np.log(np.exp(values - maximum).sum())
        )
    _, result = _normalize_log_weights(np.asarray(destination_logs))
    return result


def _ordered_float64_index(value):
    scalar = float(value)
    if scalar == 0.0:
        scalar = 0.0
    bits = int(np.asarray(scalar, dtype=np.float64).view(np.uint64).item())
    if bits & (1 << 63):
        return (~bits) & ((1 << 64) - 1)
    return bits | (1 << 63)


def _diagnostics(direct, nested):
    direct_values = np.asarray(direct, dtype=np.float64)
    nested_values = np.asarray(nested, dtype=np.float64)
    absolute = np.empty_like(direct_values)
    relative = np.empty_like(direct_values)
    ulp = np.empty(direct_values.shape, dtype=np.uint64)
    for index in np.ndindex(direct_values.shape):
        left = float(direct_values[index])
        right = float(nested_values[index])
        difference = abs(left - right)
        absolute[index] = difference
        relative[index] = difference / max(1.0, abs(left), abs(right))
        ulp[index] = abs(_ordered_float64_index(left) - _ordered_float64_index(right))
    return absolute, relative, ulp


def _runtime_contract():
    executable = Path(sys.executable).resolve()
    return {
        "python_executable": str(executable),
        "python_executable_sha256": _sha256(executable),
        "python_version": sys.version,
        "python_implementation": sys.implementation.name,
        "python_compiler": platform.python_compiler(),
        "machine": platform.machine(),
        "numpy_version": np.__version__,
        "byteorder": sys.byteorder,
        "double_format": float.__getformat__("double"),
        "float_radix": sys.float_info.radix,
        "float_mant_dig": sys.float_info.mant_dig,
        "float_rounds": sys.float_info.rounds,
        "ulp_one_hex": math.ulp(1.0).hex(),
        "ulp_zero_hex": math.ulp(0.0).hex(),
        "nextafter_zero_hex": math.nextafter(0.0, 1.0).hex(),
        "math_fma_available": hasattr(math, "fma"),
    }


def _base_arrays(basin_id, seed, probabilities, log_probabilities, arm_id):
    rotation = np.asarray([0, 1, 2, 0, 2, 1, 0], dtype=np.int64)
    n_days = len(probabilities)
    true_indices = (
        np.repeat(rotation, 180)
        if n_days == 1260
        else np.zeros(n_days, dtype=np.int64)
    )
    parameter_names = np.asarray(
        [
            "parTT", "parCFMAX", "parCFR", "parCWH", "parFC", "parBETA",
            "parLP", "parPERC", "parUZL", "parK0", "parK1", "parK2",
            "lag_time",
        ]
    )
    parameter_vectors = np.arange(39, dtype=np.float64).reshape(3, 13)
    parameter_vectors[:, 4] = [100.0, 50.0, 200.0]
    arrays = {
        "probabilities": probabilities,
        "log_probabilities": log_probabilities,
        "truth_q": np.linspace(1.0, 2.0, n_days),
        "observations": np.linspace(1.1, 2.1, n_days),
        "basin_id": np.asarray(basin_id),
        "seed": np.asarray(seed, dtype=np.int64),
        "switch_days": (
            np.arange(180, 1260, 180, dtype=np.int32)
            if n_days == 1260
            else np.asarray([1], dtype=np.int32)
        ),
        "rotation": rotation if n_days == 1260 else np.asarray([0], dtype=np.int64),
        "stage_days": np.asarray(180, dtype=np.int64),
        "true_candidate_indices": true_indices,
        "candidate_parameter_names": parameter_names,
        "candidate_parameter_vectors": parameter_vectors,
        "truth_parfc": parameter_vectors[true_indices, 4],
        "truth_slz_lognormal_sigma": np.asarray(0.02),
        "truth_clip_count": np.asarray(0, dtype=np.int64),
        "observation_sigma": np.asarray(0.1),
        "rain": np.linspace(0.0, 1.0, n_days),
        "pet": np.linspace(1.0, 0.0, n_days),
        "temperature": np.full(n_days, 12.0),
        "filter_process_variance_scale": np.asarray(3e-8),
        "filter_process_covariance_structure": np.asarray(
            "lower_groundwater_state_only"
        ),
        "filter_q_mode": np.asarray("fixed"),
        "filter_q_state_multiplier": np.asarray(1.0),
        "filter_observation_variance_multiplier": np.asarray(1.0),
        "filter_process_lower_groundwater_variance": np.full(n_days, 3e-8),
        "state_interaction_mode": np.asarray(
            "full" if arm_id == "C" else "pairwise_path_postcollapse"
        ),
        "parameter_state_mapping": np.asarray("conservative_parfc"),
        "arm_id": np.asarray(arm_id),
    }
    return arrays


def _baseline_arrays(basin_id, seed):
    probabilities = np.full((N_DAYS, N_CANDIDATES), 1.0 / 3.0)
    tiny = np.exp(-150.0)
    probabilities[-1] = [tiny, (1.0 - tiny) / 2.0, (1.0 - tiny) / 2.0]
    logs = np.log(probabilities)
    return _base_arrays(basin_id, seed, probabilities, logs, "C")


def _build_path_arrays(basin_id, seed, n_days=N_DAYS):
    transition = np.asarray(
        [[0.90, 0.06, 0.04], [0.03, 0.92, 0.05], [0.08, 0.02, 0.90]],
        dtype=np.float64,
    )
    desired_logits = np.full((n_days, N_CANDIDATES), -np.log(3.0))
    desired_logits[0] = [-1000.0, 0.0, 0.0]
    desired_logits[-1] = np.log([0.8, 0.1, 0.1])

    source_probabilities = np.empty_like(desired_logits)
    source_probabilities[0] = 1.0 / 3.0
    candidate_priors = np.empty_like(desired_logits)
    prior_logs = np.full((n_days, 3, 3), -np.inf)
    posterior_logs = np.full((n_days, 3, 3), -np.inf)
    branch_probabilities = np.zeros((n_days, 3, 3), dtype=np.float64)
    destination_raw_probabilities = np.zeros((n_days, 3), dtype=np.float64)
    destination_raw_conditionals = np.zeros((n_days, 3, 3), dtype=np.float64)
    destination_conditionals = np.zeros((n_days, 3, 3), dtype=np.float64)
    likelihoods = np.full((n_days, 3, 3), -np.inf)
    probabilities = np.empty_like(desired_logits)
    log_probabilities = np.empty_like(desired_logits)
    active = np.zeros((n_days, 3, 3), dtype=bool)

    source_states = np.empty((n_days, 3, N_STATE))
    source_covariances = np.empty((n_days, 3, N_STATE, N_STATE))
    source_states[0] = np.asarray(
        [candidate + np.arange(N_STATE) * 0.001 for candidate in range(3)]
    )
    source_covariances[0] = np.asarray(
        [np.eye(N_STATE) * (1.0 + candidate * 0.1) for candidate in range(3)]
    )
    branch_states = np.full((n_days, 3, 3, N_STATE), np.nan)
    branch_covariances = np.full(
        (n_days, 3, 3, N_STATE, N_STATE), np.nan
    )
    destination_states = np.empty((n_days, 3, N_STATE))
    destination_covariances = np.empty((n_days, 3, N_STATE, N_STATE))
    destination_references = np.full((n_days, 3), -1, dtype=np.int64)
    combined_states = np.empty((n_days, N_STATE))
    combined_covariances = np.empty((n_days, N_STATE, N_STATE))
    global_references = np.full(n_days, -1, dtype=np.int64)
    direct_states = np.empty((n_days, N_STATE))
    direct_covariances = np.empty((n_days, N_STATE, N_STATE))
    direct_state_absolute = np.empty((n_days, N_STATE))
    direct_state_relative = np.empty((n_days, N_STATE))
    direct_state_ulp = np.empty((n_days, N_STATE), dtype=np.uint64)
    direct_covariance_absolute = np.empty((n_days, N_STATE, N_STATE))
    direct_covariance_relative = np.empty((n_days, N_STATE, N_STATE))
    direct_covariance_ulp = np.empty(
        (n_days, N_STATE, N_STATE), dtype=np.uint64
    )

    for day in range(n_days):
        source_logs = np.full(3, -np.inf)
        positive_source = source_probabilities[day] > 0.0
        source_logs[positive_source] = np.log(
            source_probabilities[day, positive_source]
        )
        raw_prior = source_logs[:, None] + np.log(transition)
        branch_prior_p, _ = _normalize_log_weights(
            raw_prior.reshape(-1)
        )
        branch_prior_p = branch_prior_p.reshape(3, 3)
        prior_logs[day] = raw_prior
        active[day] = np.isfinite(raw_prior)
        candidate_priors[day] = branch_prior_p.sum(axis=0)
        _, target_logs = _normalize_log_weights(desired_logits[day])
        active_likelihoods = target_logs - np.log(candidate_priors[day])
        likelihoods[day][active[day]] = np.broadcast_to(
            active_likelihoods,
            (3, 3),
        )[active[day]]
        branch_p, branch_log = _normalize_log_weights(
            (raw_prior + likelihoods[day]).reshape(-1)
        )
        branch_p = branch_p.reshape(3, 3)
        branch_log = branch_log.reshape(3, 3)
        branch_probabilities[day] = branch_p
        posterior_logs[day] = branch_log
        mu_raw = np.asarray(
            [math.fsum(float(value) for value in branch_p[:, destination])
             for destination in range(3)]
        )
        destination_raw_probabilities[day] = mu_raw
        probabilities[day] = _normalize_path_weights(mu_raw)
        log_probabilities[day] = _candidate_logs(branch_log)
        for destination in range(3):
            if mu_raw[destination] <= 0.0:
                continue
            raw_conditional = branch_p[:, destination] / mu_raw[destination]
            destination_raw_conditionals[day, :, destination] = raw_conditional
            destination_conditionals[day, :, destination] = (
                _normalize_path_weights(raw_conditional)
            )

        for source in range(3):
            for destination in range(3):
                if not active[day, source, destination]:
                    continue
                branch_states[day, source, destination] = (
                    source * 0.1
                    + destination
                    + np.arange(N_STATE) * 0.001
                )
                branch_covariances[day, source, destination] = np.eye(N_STATE) * (
                    1.0 + source * 0.01 + destination * 0.02
                )
        for destination in range(3):
            component_mask = destination_conditionals[day, :, destination] > 0.0
            if not np.any(component_mask):
                destination_states[day, destination] = source_states[day, destination]
                destination_covariances[day, destination] = source_covariances[
                    day, destination
                ]
                continue
            state, covariance, local_reference = _mixture(
                branch_states[day, component_mask, destination],
                branch_covariances[day, component_mask, destination],
                destination_conditionals[day, component_mask, destination],
            )
            destination_states[day, destination] = state
            destination_covariances[day, destination] = covariance
            destination_references[day, destination] = np.flatnonzero(
                component_mask
            )[local_reference]
        (
            combined_states[day],
            combined_covariances[day],
            global_references[day],
        ) = _mixture(
            destination_states[day],
            destination_covariances[day],
            probabilities[day],
        )
        direct_mask = active[day].reshape(9) & (branch_p.reshape(9) > 0.0)
        direct_state, direct_covariance, _ = _mixture(
            branch_states[day].reshape(9, N_STATE)[direct_mask],
            branch_covariances[day].reshape(9, N_STATE, N_STATE)[direct_mask],
            branch_p.reshape(9)[direct_mask],
        )
        direct_states[day] = direct_state
        direct_covariances[day] = direct_covariance
        (
            direct_state_absolute[day],
            direct_state_relative[day],
            direct_state_ulp[day],
        ) = _diagnostics(direct_state, combined_states[day])
        (
            direct_covariance_absolute[day],
            direct_covariance_relative[day],
            direct_covariance_ulp[day],
        ) = _diagnostics(
            direct_covariance,
            combined_covariances[day],
        )
        if day + 1 < n_days:
            source_probabilities[day + 1] = probabilities[day]
            source_states[day + 1] = destination_states[day]
            source_covariances[day + 1] = destination_covariances[day]

    arrays = _base_arrays(
        basin_id,
        seed,
        probabilities,
        log_probabilities,
        "P",
    )
    observation_shape = (n_days, 3, 3, 1)
    prior_observations = np.full(observation_shape, np.nan)
    innovations = np.full(observation_shape, np.nan)
    innovation_covariances = np.full(observation_shape + (1,), np.nan)
    prior_observations[..., 0][active] = 0.0
    innovations[..., 0][active] = 0.0
    innovation_covariances[..., 0, 0][active] = 1.0
    arrays.update(
        {
            "path_initial_probabilities": source_probabilities[0].copy(),
            "path_initial_states": source_states[0].copy(),
            "path_initial_covariances": source_covariances[0].copy(),
            "path_source_probabilities": source_probabilities,
            "path_source_states": source_states,
            "path_source_covariances": source_covariances,
            "path_candidate_prior_probabilities": candidate_priors,
            "path_branch_prior_log_probabilities": prior_logs,
            "path_branch_posterior_log_probabilities": posterior_logs,
            "path_branch_posterior_probabilities": branch_probabilities,
            "path_destination_raw_probabilities": destination_raw_probabilities,
            "path_posterior_probabilities": probabilities.copy(),
            "path_destination_raw_conditional_probabilities": (
                destination_raw_conditionals
            ),
            "path_destination_conditional_probabilities": destination_conditionals,
            "path_posterior_log_probabilities": log_probabilities.copy(),
            "path_branch_active_mask": active,
            "path_branch_log_likelihoods": likelihoods,
            "path_branch_prior_observations": prior_observations,
            "path_branch_innovations": innovations,
            "path_branch_innovation_covariances": innovation_covariances,
            "path_branch_prior_states": branch_states.copy(),
            "path_branch_posterior_states": branch_states,
            "path_branch_prior_covariances": branch_covariances.copy(),
            "path_branch_posterior_covariances": branch_covariances,
            "path_destination_states": destination_states,
            "path_destination_covariances": destination_covariances,
            "path_combined_states": combined_states,
            "path_combined_covariances": combined_covariances,
            "path_destination_reference_indices": destination_references,
            "path_global_reference_indices": global_references,
            "path_direct_states": direct_states,
            "path_direct_covariances": direct_covariances,
            "path_direct_nested_state_absolute_differences": direct_state_absolute,
            "path_direct_nested_state_relative_differences": direct_state_relative,
            "path_direct_nested_state_ulp_distances": direct_state_ulp,
            "path_direct_nested_covariance_absolute_differences": (
                direct_covariance_absolute
            ),
            "path_direct_nested_covariance_relative_differences": (
                direct_covariance_relative
            ),
            "path_direct_nested_covariance_ulp_distances": direct_covariance_ulp,
            "path_direct_nested_state_max_abs_difference": np.max(
                direct_state_absolute, axis=1
            ),
            "path_direct_nested_covariance_max_abs_difference": (
                np.max(direct_covariance_absolute, axis=(1, 2))
            ),
            "path_transition_matrix": transition,
            "path_initial_probability_axis_order": np.asarray(["candidate"]),
            "path_initial_state_axis_order": np.asarray(["candidate", "state"]),
            "path_initial_covariance_axis_order": np.asarray(
                ["candidate", "state_row", "state_column"]
            ),
            "path_source_probability_axis_order": np.asarray(
                ["day", "source_candidate"]
            ),
            "path_source_state_axis_order": np.asarray(
                ["day", "source_candidate", "state"]
            ),
            "path_source_covariance_axis_order": np.asarray(
                ["day", "source_candidate", "state_row", "state_column"]
            ),
            "path_probability_axis_order": np.asarray(["day", "candidate"]),
            "path_branch_axis_order": np.asarray(
                ["day", "source_candidate", "destination_candidate"]
            ),
            "path_transition_axis_order": np.asarray(
                ["source_candidate", "destination_candidate"]
            ),
            "path_destination_probability_axis_order": np.asarray(
                ["day", "destination_candidate"]
            ),
            "path_destination_conditional_probability_axis_order": np.asarray(
                ["day", "source_candidate", "destination_candidate"]
            ),
            "path_destination_reference_index_axis_order": np.asarray(
                ["day", "destination_candidate"]
            ),
            "path_global_reference_index_axis_order": np.asarray(["day"]),
            "path_branch_flatten_indices": np.asarray(
                [(source, destination) for source in range(3) for destination in range(3)],
                dtype=np.int64,
            ),
            "path_branch_flatten_index_axis_order": np.asarray(
                ["flattened_branch", "source_destination_coordinate"]
            ),
            "path_branch_flatten_order": np.asarray(
                "source_major_destination_minor"
            ),
            "path_reference_selection": np.asarray(
                "maximum_weight_then_lowest_original_index"
            ),
            "path_initial_snapshot_timing": np.asarray("before_day_0_step"),
            "path_observation_axis_order": np.asarray(
                ["day", "source_candidate", "destination_candidate", "observation"]
            ),
            "path_innovation_covariance_axis_order": np.asarray(
                [
                    "day",
                    "source_candidate",
                    "destination_candidate",
                    "observation_row",
                    "observation_column",
                ]
            ),
            "path_state_axis_order": np.asarray(
                ["day", "source_candidate", "destination_candidate", "state"]
            ),
            "path_covariance_axis_order": np.asarray(
                [
                    "day",
                    "source_candidate",
                    "destination_candidate",
                    "state_row",
                    "state_column",
                ]
            ),
            "path_candidate_state_axis_order": np.asarray(
                ["day", "candidate", "state"]
            ),
            "path_candidate_covariance_axis_order": np.asarray(
                ["day", "candidate", "state_row", "state_column"]
            ),
            "path_combined_state_axis_order": np.asarray(["day", "state"]),
            "path_combined_covariance_axis_order": np.asarray(
                ["day", "state_row", "state_column"]
            ),
            "path_direct_state_axis_order": np.asarray(["day", "state"]),
            "path_direct_covariance_axis_order": np.asarray(
                ["day", "state_row", "state_column"]
            ),
            "path_direct_nested_state_diagnostic_axis_order": np.asarray(
                ["day", "state"]
            ),
            "path_direct_nested_covariance_diagnostic_axis_order": np.asarray(
                ["day", "state_row", "state_column"]
            ),
            "path_unique_global_moment_role": np.asarray(
                "authoritative_nested_destination_mixture"
            ),
            "path_direct_global_moment_role": np.asarray(
                "nonblocking_diagnostic_only"
            ),
            "path_recursive_probability_representation": np.asarray(
                "ordinary_float"
            ),
            "path_hypothesis_collapse_timing": np.asarray("after_observation"),
        }
    )
    return arrays


_PATH_ARRAY_TEMPLATE = None


def _path_arrays(basin_id, seed):
    global _PATH_ARRAY_TEMPLATE
    if _PATH_ARRAY_TEMPLATE is None:
        _PATH_ARRAY_TEMPLATE = _build_path_arrays("01000001", 0)
    arrays = {name: value.copy() for name, value in _PATH_ARRAY_TEMPLATE.items()}
    arrays["basin_id"] = np.asarray(basin_id)
    arrays["seed"] = np.asarray(seed, dtype=np.int64)
    return arrays


def _write_npz(path: Path, arrays):
    path.parent.mkdir(parents=True, exist_ok=True)
    np.savez_compressed(path, **arrays)


def _build_case(tmp_path: Path):
    source_root = tmp_path / "source"
    output = tmp_path / "output"
    task_rows = []
    initial_probabilities = []
    initial_states = []
    initial_covariances = []
    basin_ids = [f"01{index:06d}" for index in range(1, 6)]
    for basin_id in basin_ids:
        for seed in (0, 1):
            source = source_root / f"{basin_id}_s{seed}.npz"
            baseline = _baseline_arrays(basin_id, seed)
            _write_npz(source, baseline)
            _write_npz(output / "arms" / "C" / "probs" / source.name, baseline)
            path_arrays = _path_arrays(basin_id, seed)
            _write_npz(
                output / "arms" / "P" / "probs" / source.name,
                path_arrays,
            )
            initial_probabilities.append(path_arrays["path_initial_probabilities"])
            initial_states.append(path_arrays["path_initial_states"])
            initial_covariances.append(path_arrays["path_initial_covariances"])
            task_rows.append(
                {
                    "basin_id": basin_id,
                    "seed": seed,
                    "arm_id": "C",
                    "source_probability_path": source.relative_to(tmp_path).as_posix(),
                    "source_probability_bytes": source.stat().st_size,
                    "source_probability_sha256": _sha256(source),
                }
            )
    tasks = tmp_path / "tasks.csv"
    pd.DataFrame(task_rows).to_csv(tasks, index=False)
    initial_manifest = tmp_path / "initial_moments.npz"
    np.savez_compressed(
        initial_manifest,
        basin_id=np.asarray([row["basin_id"] for row in task_rows]),
        seed=np.asarray([row["seed"] for row in task_rows], dtype=np.int64),
        initial_probabilities=np.asarray(initial_probabilities),
        initial_states=np.asarray(initial_states),
        initial_covariances=np.asarray(initial_covariances),
        initial_probability_axis_order=np.asarray(["task", "candidate"]),
        initial_state_axis_order=np.asarray(["task", "candidate", "state"]),
        initial_covariance_axis_order=np.asarray(
            ["task", "candidate", "state_row", "state_column"]
        ),
    )
    parameter_table = tmp_path / "parameters.csv"
    parameter_table.write_text("basin_id,value\n01000001,1\n", encoding="utf-8")
    g1_table = tmp_path / "g1.csv"
    g1_table.write_text("basin_id,sigma_obs\n01000001,0.1\n", encoding="utf-8")
    raw_input = tmp_path / "raw_input.txt"
    raw_input.write_text("registered raw input\n", encoding="utf-8")
    raw_manifest = tmp_path / "raw_manifest.csv"
    pd.DataFrame(
        [
            {
                "relative_path": raw_input.relative_to(tmp_path).as_posix(),
                "bytes": raw_input.stat().st_size,
                "sha256": _sha256(raw_input),
            }
        ]
    ).to_csv(raw_manifest, index=False)
    implementation_root = tmp_path / "implementation"
    implementation_root.mkdir()
    implementation = {}
    for role in ("mechanism_runner", "mechanism_verifier"):
        path = implementation_root / f"{role}.py"
        path.write_text(f"# {role}\n", encoding="utf-8")
        implementation[role] = {
            "path": path.relative_to(tmp_path).as_posix(),
            "sha256": _sha256(path),
        }
    config = {
        "experiment_id": "TEST_PARAMETER_PATH_MECHANISM",
        "configuration_status": "mechanism_check_design_seeds_not_validation",
        "inputs": {
            "task_table": tasks.relative_to(tmp_path).as_posix(),
            "task_table_sha256": _sha256(tasks),
            "parameter_table": parameter_table.relative_to(tmp_path).as_posix(),
            "parameter_table_sha256": _sha256(parameter_table),
            "g1_precheck_table": g1_table.relative_to(tmp_path).as_posix(),
            "g1_precheck_table_sha256": _sha256(g1_table),
            "raw_input_manifest": raw_manifest.relative_to(tmp_path).as_posix(),
            "raw_input_manifest_sha256": _sha256(raw_manifest),
            "initial_moment_manifest": initial_manifest.relative_to(tmp_path).as_posix(),
            "initial_moment_manifest_sha256": _sha256(initial_manifest),
        },
        "runtime": _runtime_contract(),
        "arms": [
            {
                "arm_id": "C",
                "interaction_mode": "full",
                "parameter_state_mapping": "conservative_parfc",
            },
            {
                "arm_id": "P",
                "interaction_mode": "pairwise_path_postcollapse",
                "parameter_state_mapping": "conservative_parfc",
            },
        ],
        "implementation": implementation,
        "outputs": {"root": output.relative_to(tmp_path).as_posix()},
    }
    config_path = tmp_path / "config.json"
    config_path.write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")
    config_sha256 = _sha256(config_path)
    records = []
    for arm_id in ("C", "P"):
        for row in task_rows:
            records.append(
                {
                    "basin_id": row["basin_id"],
                    "seed": row["seed"],
                    "arm_id": arm_id,
                    "run_status": "success",
                    "truth_clip_count": 0,
                }
            )
        pd.DataFrame(records[-10:]).to_csv(
            output / "arms" / arm_id / "tasks.csv", index=False
        )
    summary = {
        "experiment_id": config["experiment_id"],
        "configuration_status": config["configuration_status"],
        "config_sha256": config_sha256,
        "execution_status": "complete",
        "scientific_aggregation_status": (
            "ready_for_independent_mechanism_verification"
        ),
        "n_source_tasks": 10,
        "n_arms": 2,
        "n_tasks_planned": 20,
        "n_submitted": 20,
        "run_status_counts": {"success": 20},
        "arms": config["arms"],
        "runtime": config["runtime"],
        "implementation_hashes": {
            role: entry["sha256"] for role, entry in implementation.items()
        },
        "registered_input_hashes": {
            "parameter_table_sha256": _sha256(parameter_table),
            "g1_precheck_table_sha256": _sha256(g1_table),
            "raw_input_manifest_sha256": _sha256(raw_manifest),
            "raw_input_manifest_rows": 1,
            "initial_moment_manifest_sha256": _sha256(initial_manifest),
            "initial_moment_manifest_rows": 10,
        },
    }
    (output / "runner_summary.json").write_text(
        json.dumps(summary, indent=2) + "\n", encoding="utf-8"
    )
    return {
        "root": tmp_path,
        "config": config_path,
        "config_sha256": config_sha256,
        "output": output,
        "first_c": output / "arms" / "C" / "probs" / "01000001_s0.npz",
        "first_p": output / "arms" / "P" / "probs" / "01000001_s0.npz",
        "implementation_file": (
            tmp_path / implementation["mechanism_runner"]["path"]
        ),
        "raw_input": raw_input,
        "initial_manifest": initial_manifest,
    }


_CASE_TEMPLATE = None


def _case(tmp_path: Path):
    """Clone one immutable complete fixture instead of rebuilding ten paths."""
    global _CASE_TEMPLATE
    if _CASE_TEMPLATE is None:
        template_root = tmp_path.parent / "complete_mechanism_template"
        template_root.mkdir(exist_ok=False)
        _CASE_TEMPLATE = _build_case(template_root)
    template_root = _CASE_TEMPLATE["root"]
    shutil.copytree(template_root, tmp_path, dirs_exist_ok=True)
    cloned = {}
    for name, value in _CASE_TEMPLATE.items():
        if isinstance(value, Path):
            cloned[name] = tmp_path / value.relative_to(template_root)
        else:
            cloned[name] = value
    return cloned


def _rewrite_npz(path: Path, mutate):
    with np.load(path, allow_pickle=False) as archive:
        arrays = {name: archive[name].copy() for name in archive.files}
    mutate(arrays)
    np.savez_compressed(path, **arrays)


def test_mixture_mean_uses_compensated_summation_at_registered_tolerance():
    probabilities = np.asarray(
        [
            0.17421322990659752,
            0.06628622489436595,
            0.17173006754870182,
            0.17618431941755236,
            0.08721413930645475,
            0.056863398320513285,
            0.08873706775266287,
            0.12627723992664538,
            0.0524943129265061,
        ],
        dtype=np.float64,
    )
    component_values = np.asarray(
        [
            4316.459362668676,
            3008.6848001562616,
            4638.081382829146,
            3228.697338567513,
            2611.197283774888,
            4434.854673928128,
            4381.533199804342,
            2497.723534740548,
            1772.7098757628196,
        ],
        dtype=np.float64,
    )
    states = np.tile(component_values[:, None], (1, 2))
    covariances = np.zeros((len(probabilities), 2, 2), dtype=np.float64)
    weights = probabilities / float(probabilities.sum())
    expected = np.asarray(
        [
            math.fsum(
                float(weight) * float(value)
                for weight, value in zip(weights, states[:, state_index])
            )
            for state_index in range(states.shape[1])
        ],
        dtype=np.float64,
    )

    ordinary = weights @ states
    assert float(np.max(np.abs(ordinary - expected))) > verifier.STATE_TOLERANCE

    observed, _ = verifier._mixture_moments(
        states,
        covariances,
        probabilities,
    )
    assert float(np.max(np.abs(observed - expected))) <= verifier.STATE_TOLERANCE


def test_mixture_covariance_uses_compensated_summation_at_registered_tolerance():
    probabilities = np.asarray(
        [
            0.03840398179749472,
            0.030474427681185846,
            0.2780471762271435,
            0.028668143829959688,
            0.10859979210296139,
            0.10461877636705552,
            0.23203953046101697,
            0.011562292846091924,
            0.16758587868709057,
        ],
        dtype=np.float64,
    )
    component_variances = np.asarray(
        [
            89893.79802761244,
            69590.60160614908,
            85068.83267312299,
            96139.33756430788,
            93459.24092725683,
            8000.841090688915,
            63993.83604687115,
            82960.67622825784,
            47975.70658663352,
        ],
        dtype=np.float64,
    )
    states = np.zeros((len(probabilities), 2), dtype=np.float64)
    covariances = np.asarray(
        [np.eye(2, dtype=np.float64) * value for value in component_variances]
    )
    weights = probabilities / float(probabilities.sum())
    expected_variance = math.fsum(
        float(weight) * float(value)
        for weight, value in zip(weights, component_variances)
    )
    expected = np.eye(2, dtype=np.float64) * expected_variance
    ordinary = np.zeros((2, 2), dtype=np.float64)
    for weight, covariance in zip(weights, covariances):
        ordinary += weight * covariance
    assert (
        float(np.max(np.abs(ordinary - expected)))
        > verifier.COVARIANCE_TOLERANCE
    )

    _, observed = verifier._mixture_moments(
        states,
        covariances,
        probabilities,
    )
    assert (
        float(np.max(np.abs(observed - expected)))
        <= verifier.COVARIANCE_TOLERANCE
    )


def test_complete_mechanism_result_is_verified_and_written_atomically(
    tmp_path,
    monkeypatch,
):
    case = _case(tmp_path)
    monkeypatch.setattr(verifier, "_REPO_ROOT", case["root"])
    monkeypatch.setattr(
        verifier,
        "_audit_mixture_high_precision",
        lambda *args, **kwargs: {
            "mean_maximum_ratio": 0.0,
            "covariance_maximum_ratio": 0.0,
        },
    )

    summary = verifier.verify_parameter_path_mechanism(
        case["config"], case["config_sha256"]
    )

    assert summary["verification_status"] == "passed"
    assert summary["mechanism_gate_status"] == "GO"
    assert summary["severe_day_count_strictly_improved"] is True
    assert summary["mean_negative_log_probability_strictly_improved"] is True
    assert summary["task_count"] == 20
    assert summary["arm_summary"]["C"]["severe_negative_log_probability_days"] == 10
    assert summary["arm_summary"]["P"]["severe_negative_log_probability_days"] == 0
    assert len(pd.read_csv(case["output"] / "verification" / "task_metrics.csv")) == 20
    saved = json.loads(
        (case["output"] / "verification" / "verification_summary.json").read_text(
            encoding="utf-8"
        )
    )
    assert saved == summary
    assert not (case["output"] / "verification.tmp").exists()


def test_wrong_config_hash_and_existing_verification_are_rejected(
    tmp_path,
    monkeypatch,
):
    case = _case(tmp_path)
    monkeypatch.setattr(verifier, "_REPO_ROOT", case["root"])
    with pytest.raises(ValueError, match="configuration SHA-256 changed"):
        verifier.verify_parameter_path_mechanism(case["config"], "0" * 64)
    (case["output"] / "verification").mkdir()
    with pytest.raises(FileExistsError, match="verification"):
        verifier.verify_parameter_path_mechanism(
            case["config"], case["config_sha256"]
        )


def test_incomplete_runner_and_changed_baseline_source_contract_are_rejected(
    tmp_path,
    monkeypatch,
):
    case = _case(tmp_path)
    monkeypatch.setattr(verifier, "_REPO_ROOT", case["root"])
    summary_path = case["output"] / "runner_summary.json"
    original_summary = summary_path.read_bytes()
    summary = json.loads(original_summary)
    summary["execution_status"] = "failed_early"
    summary_path.write_text(json.dumps(summary), encoding="utf-8")
    with pytest.raises(ValueError, match="runner summary"):
        verifier.verify_parameter_path_mechanism(
            case["config"], case["config_sha256"]
        )
    summary_path.write_bytes(original_summary)

    _rewrite_npz(
        case["first_c"],
        lambda arrays: arrays["truth_q"].__setitem__(0, 999.0),
    )
    with pytest.raises(ValueError, match="source.*truth_q|truth_q.*source"):
        verifier.verify_parameter_path_mechanism(
            case["config"], case["config_sha256"]
        )


def test_registered_implementation_and_raw_input_tampering_are_rejected(
    tmp_path,
    monkeypatch,
):
    case = _case(tmp_path)
    monkeypatch.setattr(verifier, "_REPO_ROOT", case["root"])
    implementation_bytes = case["implementation_file"].read_bytes()
    case["implementation_file"].write_bytes(b"x" * len(implementation_bytes))
    with pytest.raises(ValueError, match="registered implementation.*changed"):
        verifier.verify_parameter_path_mechanism(
            case["config"], case["config_sha256"]
        )
    case["implementation_file"].write_bytes(implementation_bytes)

    raw_bytes = case["raw_input"].read_bytes()
    case["raw_input"].write_bytes(b"z" * len(raw_bytes))
    with pytest.raises(ValueError, match="registered raw input.*changed"):
        verifier.verify_parameter_path_mechanism(
            case["config"], case["config_sha256"]
        )
    case["raw_input"].write_bytes(raw_bytes)

    manifest_bytes = case["initial_manifest"].read_bytes()
    case["initial_manifest"].write_bytes(b"m" * len(manifest_bytes))
    with pytest.raises(ValueError, match="initial-moment manifest changed"):
        verifier.verify_parameter_path_mechanism(
            case["config"], case["config_sha256"]
        )


def test_log_difference_rejects_finite_and_inactive_pattern_mismatch():
    with pytest.raises(ValueError, match="finite and inactive patterns differ"):
        verifier._assert_log_arrays_close(
            np.asarray([0.0, -np.inf]),
            np.asarray([0.0, -1.0]),
            tolerance=1e-12,
            label="source stable log probabilities",
        )


@pytest.mark.parametrize(
    ("mutation", "message"),
    [
        (
            lambda arrays: arrays["path_branch_prior_log_probabilities"].__setitem__(
                (0, 0, 0), arrays["path_branch_prior_log_probabilities"][0, 0, 0] + 0.5
            ),
            "raw branch prior log probabilities",
        ),
        (
            lambda arrays: arrays["path_branch_log_likelihoods"].__setitem__(
                (0, 0, 0), arrays["path_branch_log_likelihoods"][0, 0, 0] + 1.0
            ),
            "branch posterior log probabilities",
        ),
        (
            lambda arrays: arrays["path_branch_posterior_probabilities"].__setitem__(
                (0, 0, 1), arrays["path_branch_posterior_probabilities"][0, 0, 1] + 1e-5
            ),
            "branch posterior probabilities",
        ),
        (
            lambda arrays: arrays["path_destination_raw_probabilities"].__setitem__(
                (0, 1), arrays["path_destination_raw_probabilities"][0, 1] + 1e-5
            ),
            "path_destination_raw_probabilities",
        ),
        (
            lambda arrays: arrays["path_posterior_probabilities"].__setitem__(
                (0, 1), arrays["path_posterior_probabilities"][0, 1] + 1e-5
            ),
            "path_posterior_probabilities",
        ),
        (
            lambda arrays: arrays[
                "path_destination_raw_conditional_probabilities"
            ].__setitem__(
                (1, 0, 0),
                arrays["path_destination_raw_conditional_probabilities"][1, 0, 0]
                + 1e-5,
            ),
            "path_destination_raw_conditional_probabilities",
        ),
        (
            lambda arrays: arrays[
                "path_destination_conditional_probabilities"
            ].__setitem__(
                (1, 0, 0),
                arrays["path_destination_conditional_probabilities"][1, 0, 0]
                + 1e-5,
            ),
            "path_destination_conditional_probabilities",
        ),
        (
            lambda arrays: arrays["path_posterior_log_probabilities"].__setitem__(
                (0, 1), arrays["path_posterior_log_probabilities"][0, 1] + 1e-5
            ),
            "path stable candidate log probabilities",
        ),
        (
            lambda arrays: arrays["log_probabilities"].__setitem__(
                (-1, 0), arrays["log_probabilities"][-1, 0] + 1e-5
            ),
            "stable candidate log probabilities",
        ),
        (
            lambda arrays: arrays["path_branch_active_mask"].__setitem__(
                (0, 0, 0), False
            ),
            "inactive branch sentinel|active branch mask",
        ),
        (
            lambda arrays: arrays["path_destination_states"].__setitem__(
                (0, 0, 0), arrays["path_destination_states"][0, 0, 0] + 1e-4
            ),
            "source state recursion",
        ),
        (
            lambda arrays: arrays["path_source_states"].__setitem__(
                (1, 0, 0), arrays["path_source_states"][1, 0, 0] + 1e-4
            ),
            "source state recursion",
        ),
        (
            lambda arrays: arrays["path_initial_states"].__setitem__(
                (0, 0), arrays["path_initial_states"][0, 0] + 1e-5
            ),
            "initial states",
        ),
        (
            lambda arrays: arrays["path_source_probabilities"].__setitem__(
                (0, 0), arrays["path_source_probabilities"][0, 0] + 1e-5
            ),
            "source probability|day-zero source probabilities",
        ),
        (
            lambda arrays: arrays["path_source_states"].__setitem__(
                (0, 0, 0), arrays["path_source_states"][0, 0, 0] + 1e-5
            ),
            "day-zero source states",
        ),
        (
            lambda arrays: arrays["path_source_covariances"].__setitem__(
                (0, 0, 0, 0),
                arrays["path_source_covariances"][0, 0, 0, 0] + 1e-5,
            ),
            "day-zero source covariances",
        ),
        (
            lambda arrays: arrays[
                "path_branch_innovation_covariances"
            ].__setitem__((0, 0, 0, 0, 0), 0.0),
            "innovation covariance.*positive",
        ),
        (
            lambda arrays: arrays["path_branch_posterior_covariances"].__setitem__(
                (2, 0, 0, 0, 1), 0.25
            ),
            "destination covariances",
        ),
        (
            lambda arrays: arrays["path_destination_reference_indices"].__setitem__(
                (1, 0), -1
            ),
            "destination reference indices",
        ),
        (
            lambda arrays: arrays["path_global_reference_indices"].__setitem__(
                1, 2
            ),
            "global reference index",
        ),
        (
            lambda arrays: arrays["path_direct_states"].__setitem__(
                (0, 0), arrays["path_direct_states"][0, 0] + 1e-5
            ),
            "direct diagnostic state",
        ),
        (
            lambda arrays: arrays[
                "path_direct_nested_state_absolute_differences"
            ].__setitem__(
                (0, 0),
                arrays["path_direct_nested_state_absolute_differences"][0, 0]
                + 1e-5,
            ),
            "path_direct_nested_state_absolute_differences",
        ),
        (
            lambda arrays: arrays["path_transition_matrix"].__setitem__(
                (0, slice(1, 3)), arrays["path_transition_matrix"][0, [2, 1]]
            ),
            "raw branch prior log probabilities",
        ),
    ],
)
def test_key_path_audit_tampering_is_rejected(
    mutation,
    message,
):
    arrays = _build_path_arrays("01000001", 0, n_days=4)
    initial = (
        arrays["path_initial_probabilities"].copy(),
        arrays["path_initial_states"].copy(),
        arrays["path_initial_covariances"].copy(),
    )
    mutation(arrays)

    with pytest.raises(ValueError, match=message):
        verifier._verify_path_arrays(arrays, initial)


def test_registered_mixture_corrects_float_weight_sum_residual_and_passes_oracle():
    epsilon = 2.0 ** -60
    radius = 2.0 ** 39
    weights = np.asarray([epsilon, 1.0], dtype=np.float64)
    states = np.zeros((2, 2), dtype=np.float64)
    states[0] = radius
    covariances = np.zeros((2, 2, 2), dtype=np.float64)

    mean, covariance, reference_index = verifier._registered_mixture_moments(
        states,
        covariances,
        weights,
    )

    assert reference_index == 1
    assert mean[0] == epsilon * radius
    audit = verifier._audit_mixture_high_precision(
        states,
        covariances,
        weights,
        mean,
        covariance,
        label="normalization residual regression",
    )
    assert audit["mean_maximum_ratio"] <= 1.0
    assert audit["covariance_maximum_ratio"] <= 1.0


def test_high_precision_oracle_rejects_registered_scale_mean_injection():
    states = np.asarray([[0.0, 1.0], [2.0, 3.0]], dtype=np.float64)
    covariances = np.asarray([np.eye(2), np.eye(2) * 2.0])
    weights = np.asarray([0.25, 0.75], dtype=np.float64)
    mean, covariance, _ = verifier._registered_mixture_moments(
        states,
        covariances,
        weights,
    )
    corrupted = mean.copy()
    corrupted[0] += 2.0e-8

    with pytest.raises(ValueError, match="high-precision mean"):
        verifier._audit_mixture_high_precision(
            states,
            covariances,
            weights,
            corrupted,
            covariance,
            label="injected mean",
        )


def test_high_precision_oracle_rejects_covariance_injection():
    states = np.asarray([[2.0, -1.0], [4.0, 3.0]], dtype=np.float64)
    covariances = np.asarray(
        [
            [[1.0, 0.25], [0.125, 2.0]],
            [[3.0, -0.5], [-0.25, 4.0]],
        ],
        dtype=np.float64,
    )
    weights = np.asarray([0.4, 0.6], dtype=np.float64)
    mean, covariance, _ = verifier._registered_mixture_moments(
        states, covariances, weights
    )
    corrupted = covariance.copy()
    corrupted[0, 1] += 2.0e-8

    with pytest.raises(ValueError, match="high-precision covariance"):
        verifier._audit_mixture_high_precision(
            states,
            covariances,
            weights,
            mean,
            corrupted,
            label="injected covariance",
        )


def test_exact_weight_total_and_ulp_envelope_cover_registered_boundaries():
    epsilon = 2.0 ** -60
    lower, upper = verifier._exact_weight_total_interval([1.0, epsilon])
    with verifier.localcontext() as context:
        context.prec = 100
        expected = (
            verifier.Decimal.from_float(1.0)
            + verifier.Decimal.from_float(epsilon)
        )
    assert lower <= expected <= upper
    assert lower > verifier.Decimal(1)
    assert verifier._ulp_envelope(
        (verifier.Decimal(0), verifier.Decimal(0))
    ) == verifier.Decimal.from_float(2.0 ** -1074)
    assert verifier._ulp_envelope(
        (verifier.Decimal(1), verifier.Decimal(1))
    ) == verifier.Decimal.from_float(2.0 ** -52)


def test_direct_nested_difference_is_diagnostic_not_a_threshold():
    direct = np.asarray([0.0, 1.0e9], dtype=np.float64)
    nested = np.asarray([1.0, -1.0e9], dtype=np.float64)
    absolute, relative, ulp = verifier._direct_nested_diagnostics(direct, nested)
    assert np.array_equal(absolute, [1.0, 2.0e9])
    assert np.array_equal(relative, [1.0, 2.0])
    assert np.all(ulp > 0)


def test_runtime_drift_is_rejected_independently():
    registered = _runtime_contract()
    verifier._verify_runtime_contract({"runtime": registered})
    changed = dict(registered)
    changed["numpy_version"] = "0.0.0"
    with pytest.raises(ValueError, match="runtime contract changed"):
        verifier._verify_runtime_contract({"runtime": changed})


def test_probability_metrics_use_exact_registered_slice_and_labels():
    arrays = _baseline_arrays("01000001", 0)
    metrics, events = verifier._probability_metrics(arrays)
    assert metrics["scored_days"] == 1080
    assert metrics["severe_negative_log_probability_days"] == 1
    assert len(events) == 6
    shortened = dict(arrays)
    shortened["probabilities"] = arrays["probabilities"][:-1]
    shortened["log_probabilities"] = arrays["log_probabilities"][:-1]
    shortened["true_candidate_indices"] = arrays["true_candidate_indices"][:-1]
    with pytest.raises(ValueError, match="registered 1260 days"):
        verifier._probability_metrics(shortened)


def test_bitwise_comparison_normalizes_only_signed_zero():
    verifier._require_bitwise_equal(
        np.asarray([-0.0, 1.0], dtype=np.float64),
        np.asarray([+0.0, 1.0], dtype=np.float64),
        "signed zero",
    )
    with pytest.raises(ValueError, match="bitwise"):
        verifier._require_bitwise_equal(
            np.asarray([0.0, 1.0], dtype=np.float64),
            np.asarray([0.0, np.nextafter(1.0, 2.0)], dtype=np.float64),
            "one unit-last-place change",
        )


def test_truth_indices_are_derived_from_daily_parfc_and_fixed_stages():
    names = np.asarray(
        ["parTT", "parCFMAX", "parCFR", "parCWH", "parFC"],
    )
    vectors = np.zeros((3, len(names)), dtype=np.float64)
    vectors[:, 4] = [100.0, 50.0, 200.0]
    sequence = np.asarray([0, 1, 2, 0, 2, 1, 0], dtype=np.int64)
    daily_parfc = np.repeat(vectors[sequence, 4], 180)

    observed = verifier._derive_true_candidate_indices(
        names,
        vectors,
        daily_parfc,
        stage_days=180,
    )

    assert np.array_equal(observed, np.repeat(sequence, 180))
    corrupted_labels = observed.copy()
    corrupted_labels[180] = 0
    with pytest.raises(ValueError, match="bitwise"):
        verifier._require_bitwise_equal(
            corrupted_labels,
            observed,
            "independently derived true-candidate labels",
        )
    bad = daily_parfc.copy()
    bad[360] = 75.0
    with pytest.raises(ValueError, match="daily true parFC"):
        verifier._derive_true_candidate_indices(
            names,
            vectors,
            bad,
            stage_days=180,
        )

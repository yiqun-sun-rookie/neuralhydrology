"""Independently verify the ten-task parameter-path mechanism check."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import platform
import sys
from collections.abc import Mapping
from decimal import Decimal, ROUND_CEILING, ROUND_FLOOR, localcontext
from fractions import Fraction
from pathlib import Path

import numpy as np
import pandas as pd


_REPO_ROOT = Path(__file__).resolve().parents[2]

CONFIGURATION_STATUS = "mechanism_check_design_seeds_not_validation"
EXPECTED_ARMS = (
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
)
TASK_COLUMNS = frozenset(
    {
        "basin_id",
        "seed",
        "arm_id",
        "source_probability_path",
        "source_probability_bytes",
        "source_probability_sha256",
    }
)
SOURCE_EXACT_FIELDS = (
    "truth_q",
    "observations",
    "basin_id",
    "seed",
    "switch_days",
    "rotation",
    "stage_days",
    "true_candidate_indices",
    "candidate_parameter_names",
    "candidate_parameter_vectors",
    "truth_slz_lognormal_sigma",
    "truth_clip_count",
    "observation_sigma",
    "rain",
    "pet",
    "temperature",
    "filter_process_variance_scale",
    "filter_process_covariance_structure",
    "filter_q_mode",
    "filter_q_state_multiplier",
    "filter_observation_variance_multiplier",
    "filter_process_lower_groundwater_variance",
    "state_interaction_mode",
    "parameter_state_mapping",
    "arm_id",
)
CROSS_ARM_EXACT_FIELDS = tuple(
    name
    for name in SOURCE_EXACT_FIELDS
    if name
    not in {
        "state_interaction_mode",
        "parameter_state_mapping",
        "arm_id",
    }
)
CROSS_ARM_EXACT_FIELDS = CROSS_ARM_EXACT_FIELDS + ("truth_parfc",)
PATH_REQUIRED_FIELDS = (
    "path_initial_probabilities",
    "path_initial_states",
    "path_initial_covariances",
    "path_source_probabilities",
    "path_source_states",
    "path_source_covariances",
    "path_candidate_prior_probabilities",
    "path_branch_prior_log_probabilities",
    "path_branch_posterior_log_probabilities",
    "path_branch_posterior_probabilities",
    "path_destination_raw_probabilities",
    "path_posterior_probabilities",
    "path_destination_raw_conditional_probabilities",
    "path_destination_conditional_probabilities",
    "path_posterior_log_probabilities",
    "path_branch_active_mask",
    "path_branch_log_likelihoods",
    "path_branch_prior_observations",
    "path_branch_innovations",
    "path_branch_innovation_covariances",
    "path_branch_prior_states",
    "path_branch_posterior_states",
    "path_branch_prior_covariances",
    "path_branch_posterior_covariances",
    "path_destination_states",
    "path_destination_covariances",
    "path_combined_states",
    "path_combined_covariances",
    "path_destination_reference_indices",
    "path_global_reference_indices",
    "path_direct_states",
    "path_direct_covariances",
    "path_direct_nested_state_absolute_differences",
    "path_direct_nested_state_relative_differences",
    "path_direct_nested_state_ulp_distances",
    "path_direct_nested_covariance_absolute_differences",
    "path_direct_nested_covariance_relative_differences",
    "path_direct_nested_covariance_ulp_distances",
    "path_direct_nested_state_max_abs_difference",
    "path_direct_nested_covariance_max_abs_difference",
    "path_transition_matrix",
    "path_initial_probability_axis_order",
    "path_initial_state_axis_order",
    "path_initial_covariance_axis_order",
    "path_source_probability_axis_order",
    "path_source_state_axis_order",
    "path_source_covariance_axis_order",
    "path_probability_axis_order",
    "path_branch_axis_order",
    "path_transition_axis_order",
    "path_destination_probability_axis_order",
    "path_destination_conditional_probability_axis_order",
    "path_destination_reference_index_axis_order",
    "path_global_reference_index_axis_order",
    "path_branch_flatten_indices",
    "path_branch_flatten_index_axis_order",
    "path_branch_flatten_order",
    "path_reference_selection",
    "path_initial_snapshot_timing",
    "path_observation_axis_order",
    "path_innovation_covariance_axis_order",
    "path_state_axis_order",
    "path_covariance_axis_order",
    "path_candidate_state_axis_order",
    "path_candidate_covariance_axis_order",
    "path_combined_state_axis_order",
    "path_combined_covariance_axis_order",
    "path_direct_state_axis_order",
    "path_direct_covariance_axis_order",
    "path_direct_nested_state_diagnostic_axis_order",
    "path_direct_nested_covariance_diagnostic_axis_order",
    "path_unique_global_moment_role",
    "path_direct_global_moment_role",
    "path_recursive_probability_representation",
    "path_hypothesis_collapse_timing",
)

PROBABILITY_TOLERANCE = 1e-12
STATE_TOLERANCE = 1e-12
COVARIANCE_TOLERANCE = 1e-11
SYMMETRY_TOLERANCE = 1e-12
SCORING_START = 180
SCORING_STOP = 1260
SEVERE_NLL_THRESHOLD = 100.0
DECIMAL_PRECISION = 100
UNIT_ROUNDOFF = 2.0 ** -53
MINIMUM_SUBNORMAL = 2.0 ** -1074
MEAN_GAMMA_COUNT = 64
COVARIANCE_GAMMA_COUNT = 128
MEAN_ABSOLUTE_FLOOR = 1e-12
COVARIANCE_ABSOLUTE_FLOOR = 1e-11
TRUTH_STAGE_SEQUENCE = np.asarray([0, 1, 2, 0, 2, 1, 0], dtype=np.int64)


def sha256_file(path: str | Path) -> str:
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _repository_path(root: Path, value: object, label: str) -> Path:
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{label} must be a nonempty repository-relative path")
    relative = Path(value)
    if relative.is_absolute() or relative.drive or ".." in relative.parts:
        raise ValueError(
            f"{label} must be repository-relative without parent traversal"
        )
    return root / relative


def _normalize_basin_id(value: object) -> str:
    text = str(value).strip().zfill(8)
    if len(text) != 8 or not text.isdigit():
        raise ValueError(f"invalid basin identifier: {value}")
    return text


def _load_npz(path: Path) -> dict[str, np.ndarray]:
    if not path.is_file():
        raise FileNotFoundError(f"task probability file is missing: {path}")
    try:
        with np.load(path, allow_pickle=False) as archive:
            return {name: archive[name].copy() for name in archive.files}
    except Exception as error:  # noqa: BLE001 - archive corruption is a stop
        raise ValueError(f"task probability file is unreadable: {path}") from error


def _verify_registered_files(
    root: Path,
    config: Mapping,
) -> tuple[dict[str, str], dict[str, str | int]]:
    implementation = config.get("implementation")
    if not isinstance(implementation, Mapping) or not implementation:
        raise ValueError("configuration implementation must be a nonempty mapping")
    implementation_hashes = {}
    implementation_paths = set()
    for role, entry in implementation.items():
        if not isinstance(role, str) or not isinstance(entry, Mapping):
            raise ValueError("configuration implementation entries are invalid")
        path = _repository_path(
            root,
            entry.get("path"),
            f"registered implementation {role}",
        )
        resolved = path.resolve()
        if resolved in implementation_paths:
            raise ValueError("registered implementation paths must be unique")
        implementation_paths.add(resolved)
        if not path.is_file():
            raise FileNotFoundError(f"registered implementation is missing: {path}")
        observed = sha256_file(path)
        if observed != str(entry.get("sha256")):
            raise ValueError(f"registered implementation {role} changed")
        implementation_hashes[role] = observed

    inputs = config.get("inputs")
    if not isinstance(inputs, Mapping):
        raise ValueError("configuration inputs must be a mapping")
    registered_input_hashes = {}
    for path_key, hash_key, label in (
        ("parameter_table", "parameter_table_sha256", "parameter table"),
        ("g1_precheck_table", "g1_precheck_table_sha256", "G1 precheck table"),
        (
            "raw_input_manifest",
            "raw_input_manifest_sha256",
            "raw-input manifest",
        ),
        (
            "initial_moment_manifest",
            "initial_moment_manifest_sha256",
            "initial-moment manifest",
        ),
    ):
        path = _repository_path(root, inputs.get(path_key), label)
        if not path.is_file():
            raise FileNotFoundError(f"registered {label} is missing: {path}")
        observed = sha256_file(path)
        if observed != str(inputs.get(hash_key)):
            raise ValueError(f"registered {label} changed")
        registered_input_hashes[hash_key] = observed

    manifest_path = _repository_path(
        root,
        inputs.get("raw_input_manifest"),
        "raw-input manifest",
    )
    manifest = pd.read_csv(manifest_path, keep_default_na=False)
    required_columns = {"relative_path", "bytes", "sha256"}
    if not required_columns.issubset(manifest.columns) or manifest.empty:
        raise ValueError("raw-input manifest is empty or lacks required columns")
    if manifest["relative_path"].duplicated().any():
        raise ValueError("raw-input manifest contains duplicate paths")
    for row in manifest.itertuples(index=False):
        path = _repository_path(root, row.relative_path, "registered raw input")
        try:
            expected_bytes = int(row.bytes)
            if float(row.bytes) != expected_bytes or expected_bytes < 0:
                raise ValueError
        except (TypeError, ValueError) as error:
            raise ValueError(
                f"registered raw input has an invalid byte count: {row.relative_path}"
            ) from error
        if (
            not path.is_file()
            or path.stat().st_size != expected_bytes
            or sha256_file(path) != str(row.sha256)
        ):
            raise ValueError(f"registered raw input changed: {row.relative_path}")
    registered_input_hashes["raw_input_manifest_rows"] = int(len(manifest))
    initial_manifest_path = _repository_path(
        root,
        inputs.get("initial_moment_manifest"),
        "initial-moment manifest",
    )
    initial_manifest = _load_npz(initial_manifest_path)
    if "basin_id" not in initial_manifest:
        raise ValueError("initial-moment manifest lacks basin_id")
    registered_input_hashes["initial_moment_manifest_rows"] = int(
        len(np.asarray(initial_manifest["basin_id"]))
    )
    return implementation_hashes, registered_input_hashes


def _load_initial_moment_manifest(
    root: Path,
    inputs: Mapping,
    expected_keys: set[tuple[str, int]],
) -> dict[tuple[str, int], tuple[np.ndarray, np.ndarray, np.ndarray]]:
    path = _repository_path(
        root,
        inputs.get("initial_moment_manifest"),
        "initial-moment manifest",
    )
    arrays = _load_npz(path)
    required = (
        "basin_id",
        "seed",
        "initial_probabilities",
        "initial_states",
        "initial_covariances",
        "initial_probability_axis_order",
        "initial_state_axis_order",
        "initial_covariance_axis_order",
    )
    _require_fields(arrays, required, "initial-moment manifest")
    identities = np.asarray(arrays["basin_id"])
    seeds = np.asarray(arrays["seed"])
    probabilities = np.asarray(arrays["initial_probabilities"], dtype=np.float64)
    states = np.asarray(arrays["initial_states"], dtype=np.float64)
    covariances = np.asarray(arrays["initial_covariances"], dtype=np.float64)
    task_count = len(expected_keys)
    if (
        identities.shape != (task_count,)
        or seeds.shape != (task_count,)
        or probabilities.shape != (task_count, 3)
        or states.shape != (task_count, 3, 15)
        or covariances.shape != (task_count, 3, 15, 15)
    ):
        raise ValueError("initial-moment manifest array shapes changed")
    expected_axes = {
        "initial_probability_axis_order": ["task", "candidate"],
        "initial_state_axis_order": ["task", "candidate", "state"],
        "initial_covariance_axis_order": [
            "task",
            "candidate",
            "state_row",
            "state_column",
        ],
    }
    for name, expected in expected_axes.items():
        if not np.array_equal(np.asarray(arrays[name]), np.asarray(expected)):
            raise ValueError(f"initial-moment manifest axis metadata changed for {name}")
    if (
        not np.all(np.isfinite(probabilities))
        or np.any(probabilities < 0.0)
        or np.any(probabilities > 1.0)
        or not np.all(np.isfinite(states))
        or not np.all(np.isfinite(covariances))
    ):
        raise ValueError("initial-moment manifest contains invalid values")
    if np.max(np.abs(probabilities.sum(axis=1) - 1.0)) > PROBABILITY_TOLERANCE:
        raise ValueError("initial-moment manifest probabilities are not normalized")
    _require_symmetric(
        covariances,
        "initial-moment manifest",
        SYMMETRY_TOLERANCE,
    )
    result = {}
    for index, (basin_id, seed) in enumerate(zip(identities, seeds)):
        key = (_normalize_basin_id(basin_id), int(seed))
        if key in result:
            raise ValueError("initial-moment manifest contains duplicate task identities")
        result[key] = (
            probabilities[index].copy(),
            states[index].copy(),
            covariances[index].copy(),
        )
    if set(result) != expected_keys:
        raise ValueError("initial-moment manifest task identities changed")
    return result


def _observed_runtime_contract() -> dict[str, object]:
    """Independently observe the floating-point runtime used for verification."""
    executable = Path(sys.executable).resolve()
    return {
        "python_executable": str(executable),
        "python_executable_sha256": sha256_file(executable),
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


def _verify_runtime_contract(config: Mapping) -> dict[str, object]:
    registered = config.get("runtime")
    if not isinstance(registered, Mapping):
        raise ValueError("runtime must be a mapping")
    observed = _observed_runtime_contract()
    if set(registered) != set(observed):
        raise ValueError("runtime fields changed")
    for name, expected in registered.items():
        if observed[name] != expected:
            raise ValueError(f"runtime contract changed for {name}")
    return observed


def _scalar(arrays: Mapping[str, np.ndarray], name: str):
    if name not in arrays or np.asarray(arrays[name]).shape != ():
        raise ValueError(f"{name} must be a scalar")
    return np.asarray(arrays[name]).item()


def _require_fields(arrays: Mapping[str, np.ndarray], names, label: str) -> None:
    missing = [name for name in names if name not in arrays]
    if missing:
        raise ValueError(f"{label} lacks required fields: {', '.join(missing)}")


def _maximum_absolute_difference(left, right) -> float:
    first = np.asarray(left, dtype=np.float64)
    second = np.asarray(right, dtype=np.float64)
    if first.shape != second.shape:
        return float("inf")
    if first.size == 0:
        return 0.0
    return float(np.max(np.abs(first - second)))


def _assert_log_arrays_close(
    observed,
    expected,
    *,
    tolerance: float,
    label: str,
) -> float:
    actual = np.asarray(observed, dtype=np.float64)
    reference = np.asarray(expected, dtype=np.float64)
    if actual.shape != reference.shape:
        raise ValueError(f"{label} shape changed")
    if np.any(np.isnan(actual)) or np.any(np.isposinf(actual)):
        raise ValueError(f"{label} contains NaN or positive infinity")
    if not np.array_equal(np.isfinite(actual), np.isfinite(reference)):
        raise ValueError(f"{label} finite and inactive patterns differ")
    finite = np.isfinite(reference)
    difference = (
        float(np.max(np.abs(actual[finite] - reference[finite])))
        if np.any(finite)
        else 0.0
    )
    if difference > tolerance:
        raise ValueError(f"{label} differ by {difference}, above {tolerance}")
    return difference


def _normalize_log_weights(log_weights) -> tuple[np.ndarray, np.ndarray]:
    values = np.asarray(log_weights, dtype=np.float64)
    if values.ndim != 1 or len(values) == 0:
        raise ValueError("log weights must be a nonempty vector")
    if np.any(np.isnan(values)) or np.any(np.isposinf(values)):
        raise ValueError("log weights contain NaN or positive infinity")
    finite = np.isfinite(values)
    if not np.any(finite):
        raise ValueError("log weights contain no active value")
    shifted = np.zeros_like(values)
    maximum = np.max(values[finite])
    shifted[finite] = np.exp(values[finite] - maximum)
    total = float(np.sum(shifted, dtype=np.float64))
    if not np.isfinite(total) or total <= 0.0:
        raise ValueError("log weights cannot be normalized")
    log_normalizer = maximum + np.log(total)
    normalized_logs = np.full_like(values, -np.inf)
    normalized_logs[finite] = values[finite] - log_normalizer
    probabilities = np.zeros_like(values)
    probabilities[finite] = np.exp(normalized_logs[finite])
    probability_total = float(np.sum(probabilities, dtype=np.float64))
    if not np.isfinite(probability_total) or probability_total <= 0.0:
        raise ValueError("normalized log weights contain no probability mass")
    probabilities /= probability_total
    normalized_logs[finite] -= np.log(probability_total)
    return probabilities, normalized_logs


def _logsumexp(values) -> float:
    array = np.asarray(values, dtype=np.float64)
    finite = np.isfinite(array)
    if not np.any(finite):
        return float("-inf")
    maximum = float(np.max(array[finite]))
    shifted = np.exp(array[finite] - maximum)
    return float(maximum + np.log(np.sum(shifted, dtype=np.float64)))


def _normalize_path_weights(weights) -> np.ndarray:
    """Independently execute the registered ordinary-weight normalization."""
    values = np.asarray(weights, dtype=np.float64)
    if values.ndim != 1 or len(values) == 0:
        raise ValueError("path weights must be a nonempty vector")
    if not np.all(np.isfinite(values)) or np.any(values < 0.0):
        raise ValueError("path weights must be finite and nonnegative")
    total = math.fsum(float(value) for value in values)
    if not np.isfinite(total) or total <= 0.0:
        raise ValueError("path weights contain no positive mass")
    normalized = values / total
    if not np.all(np.isfinite(normalized)):
        raise ValueError("normalized path weights are non-finite")
    return normalized


def _mixture_moments(states, covariances, probabilities):
    state_values = np.asarray(states, dtype=np.float64)
    covariance_values = np.asarray(covariances, dtype=np.float64)
    weights = np.asarray(probabilities, dtype=np.float64)
    if state_values.ndim != 2 or state_values.shape[0] == 0:
        raise ValueError("mixture states have an invalid shape")
    component_count, state_count = state_values.shape
    if covariance_values.shape != (component_count, state_count, state_count):
        raise ValueError("mixture covariances have an invalid shape")
    if weights.shape != (component_count,):
        raise ValueError("mixture probabilities have an invalid shape")
    if not np.all(np.isfinite(state_values)) or not np.all(
        np.isfinite(covariance_values)
    ):
        raise ValueError("mixture moments are non-finite")
    if not np.all(np.isfinite(weights)) or np.any(weights < 0.0):
        raise ValueError("mixture probabilities are invalid")
    total = math.fsum(float(weight) for weight in weights)
    if not np.isfinite(total) or total <= 0.0:
        raise ValueError("mixture probabilities contain no mass")
    weights = weights / total
    mean = np.empty(state_count, dtype=np.float64)
    for index in range(state_count):
        mean[index] = math.fsum(
            float(weight * state[index])
            for weight, state in zip(weights, state_values)
        )
    differences = state_values - mean
    covariance = np.empty((state_count, state_count), dtype=np.float64)
    for row in range(state_count):
        for column in range(state_count):
            covariance[row, column] = math.fsum(
                float(
                    weight
                    * (
                        component_covariance[row, column]
                        + difference[row] * difference[column]
                    )
                )
                for weight, difference, component_covariance in zip(
                    weights,
                    differences,
                    covariance_values,
                )
            )
    covariance = 0.5 * (covariance + covariance.T)
    if not np.all(np.isfinite(mean)) or not np.all(np.isfinite(covariance)):
        raise ValueError("mixture mean or covariance is non-finite")
    return mean, covariance


def _require_bitwise_equal(observed, expected, label: str) -> None:
    """Require equal float64 bits after canonicalizing signed zero only."""
    actual = np.asarray(observed)
    reference = np.asarray(expected)
    if actual.shape != reference.shape:
        raise ValueError(f"{label} bitwise shape changed")
    if actual.dtype.kind not in "fc" or reference.dtype.kind not in "fc":
        if not np.array_equal(actual, reference):
            raise ValueError(f"{label} values are not bitwise equal")
        return
    actual64 = np.asarray(actual, dtype=np.float64).copy()
    reference64 = np.asarray(reference, dtype=np.float64).copy()
    actual64[actual64 == 0.0] = 0.0
    reference64[reference64 == 0.0] = 0.0
    if not np.array_equal(actual64.view(np.uint64), reference64.view(np.uint64)):
        raise ValueError(f"{label} values are not bitwise equal")


def _float_ulp_distances(left, right) -> np.ndarray:
    first = np.asarray(left, dtype=np.float64).copy()
    second = np.asarray(right, dtype=np.float64).copy()
    if first.shape != second.shape:
        raise ValueError("ULP diagnostic shapes differ")
    if not np.all(np.isfinite(first)) or not np.all(np.isfinite(second)):
        raise ValueError("ULP diagnostics require finite values")
    first[first == 0.0] = 0.0
    second[second == 0.0] = 0.0
    sign = np.uint64(1 << 63)

    def ordered(values):
        bits = values.view(np.uint64)
        return np.where((bits & sign) != 0, ~bits, bits | sign)

    first_ordered = ordered(first)
    second_ordered = ordered(second)
    return np.where(
        first_ordered >= second_ordered,
        first_ordered - second_ordered,
        second_ordered - first_ordered,
    ).astype(np.uint64)


def _direct_nested_diagnostics(direct, nested):
    """Rebuild the registered nonblocking direct-versus-nested diagnostics."""
    direct_values = np.asarray(direct, dtype=np.float64)
    nested_values = np.asarray(nested, dtype=np.float64)
    if direct_values.shape != nested_values.shape:
        raise ValueError("direct and nested diagnostic shapes differ")
    if not np.all(np.isfinite(direct_values)) or not np.all(
        np.isfinite(nested_values)
    ):
        raise ValueError("direct and nested diagnostics must be finite")
    absolute = np.empty_like(direct_values)
    relative = np.empty_like(direct_values)
    for index in np.ndindex(direct_values.shape):
        direct_value = float(direct_values[index])
        nested_value = float(nested_values[index])
        difference = abs(direct_value - nested_value)
        scale = max(1.0, abs(direct_value), abs(nested_value))
        absolute[index] = difference
        relative[index] = difference / scale
    return absolute, relative, _float_ulp_distances(direct_values, nested_values)


def _registered_mixture_moments(
    states,
    covariances,
    probabilities,
    *,
    _maximum_components: int = 3,
):
    """Independently execute the registered at-most-three-component mixture."""
    state_values = np.asarray(states, dtype=np.float64)
    covariance_values = np.asarray(covariances, dtype=np.float64)
    weights = np.asarray(probabilities, dtype=np.float64)
    if (
        state_values.ndim != 2
        or not 1 <= len(state_values) <= int(_maximum_components)
    ):
        raise ValueError(
            "registered mixture contains an invalid number of components"
        )
    component_count, state_count = state_values.shape
    if covariance_values.shape != (component_count, state_count, state_count):
        raise ValueError("registered mixture covariance shape changed")
    if weights.shape != (component_count,):
        raise ValueError("registered mixture weight shape changed")
    if (
        not np.all(np.isfinite(state_values))
        or not np.all(np.isfinite(covariance_values))
        or not np.all(np.isfinite(weights))
        or np.any(weights < 0.0)
    ):
        raise ValueError("registered mixture inputs must be finite and nonnegative")
    active_indices = np.flatnonzero(weights > 0.0)
    if not len(active_indices):
        raise ValueError("registered mixture contains no positive weight")
    state_values = state_values[active_indices]
    covariance_values = covariance_values[active_indices]
    weights = weights[active_indices]
    total = math.fsum(float(value) for value in weights)
    if not np.isfinite(total) or not 0.5 <= total <= 2.0:
        raise ValueError("registered mixture weight total falls outside [0.5, 2]")
    local_reference = int(np.argmax(weights))
    reference_index = int(active_indices[local_reference])
    reference = state_values[local_reference]
    mean = np.empty(state_count, dtype=np.float64)
    for state_index in range(state_count):
        reference_value = float(reference[state_index])
        mean[state_index] = reference_value + math.fsum(
            float(weight)
            * (float(state[state_index]) - reference_value)
            for weight, state in zip(weights, state_values)
        ) / total
    raw_covariance = np.empty((state_count, state_count), dtype=np.float64)
    for row in range(state_count):
        for column in range(state_count):
            raw_covariance[row, column] = math.fsum(
                float(weight)
                * (
                    float(component_covariance[row, column])
                    + (float(state[row]) - float(mean[row]))
                    * (float(state[column]) - float(mean[column]))
                )
                for weight, state, component_covariance in zip(
                    weights,
                    state_values,
                    covariance_values,
                )
            ) / total
    covariance = 0.5 * (raw_covariance + raw_covariance.T)
    if not np.all(np.isfinite(mean)) or not np.all(np.isfinite(covariance)):
        raise ValueError("registered mixture produced non-finite moments")
    return mean, covariance, reference_index


def _interval_point(value: float) -> tuple[Decimal, Decimal]:
    number = float(value)
    if not np.isfinite(number):
        raise ValueError("high-precision input must be finite")
    exact = Decimal.from_float(number)
    return exact, exact


def _fraction_interval(value: Fraction) -> tuple[Decimal, Decimal]:
    numerator = Decimal(value.numerator)
    denominator = Decimal(value.denominator)
    with localcontext() as context:
        context.prec = DECIMAL_PRECISION
        context.rounding = ROUND_FLOOR
        lower = numerator / denominator
        context.rounding = ROUND_CEILING
        upper = numerator / denominator
    return lower, upper


def _exact_weight_total_interval(weights) -> tuple[Decimal, Decimal]:
    total = sum(
        (Fraction.from_float(float(value)) for value in weights),
        Fraction(0),
    )
    if total <= 0:
        raise ValueError("exact weight total must be positive")
    return _fraction_interval(total)


def _interval_add(left, right) -> tuple[Decimal, Decimal]:
    with localcontext() as context:
        context.prec = DECIMAL_PRECISION
        context.rounding = ROUND_FLOOR
        lower = left[0] + right[0]
        context.rounding = ROUND_CEILING
        upper = left[1] + right[1]
    return lower, upper


def _interval_subtract(left, right) -> tuple[Decimal, Decimal]:
    with localcontext() as context:
        context.prec = DECIMAL_PRECISION
        context.rounding = ROUND_FLOOR
        lower = left[0] - right[1]
        context.rounding = ROUND_CEILING
        upper = left[1] - right[0]
    return lower, upper


def _interval_multiply(left, right) -> tuple[Decimal, Decimal]:
    endpoint_pairs = tuple(
        (first, second)
        for first in left
        for second in right
    )
    with localcontext() as context:
        context.prec = DECIMAL_PRECISION
        context.rounding = ROUND_FLOOR
        lower = min(first * second for first, second in endpoint_pairs)
        context.rounding = ROUND_CEILING
        upper = max(first * second for first, second in endpoint_pairs)
    return lower, upper


def _interval_divide(left, right) -> tuple[Decimal, Decimal]:
    if right[0] <= 0 <= right[1]:
        raise ValueError("high-precision denominator interval contains zero")
    endpoint_pairs = tuple(
        (first, second)
        for first in left
        for second in right
    )
    with localcontext() as context:
        context.prec = DECIMAL_PRECISION
        context.rounding = ROUND_FLOOR
        lower = min(first / second for first, second in endpoint_pairs)
        context.rounding = ROUND_CEILING
        upper = max(first / second for first, second in endpoint_pairs)
    return lower, upper


def _interval_sum(values) -> tuple[Decimal, Decimal]:
    result = (Decimal(0), Decimal(0))
    for value in values:
        result = _interval_add(result, value)
    return result


def _interval_abs_upper(value) -> Decimal:
    return max(abs(value[0]), abs(value[1]))


def _interval_absolute(value) -> tuple[Decimal, Decimal]:
    if value[0] >= 0:
        return value
    if value[1] <= 0:
        return -value[1], -value[0]
    return Decimal(0), max(-value[0], value[1])


def _outward_float(endpoint: Decimal, direction: int) -> float:
    value = float(endpoint)
    if not np.isfinite(value):
        raise ValueError("high-precision reference cannot convert to finite float")
    represented = Decimal.from_float(value)
    if direction < 0 and represented > endpoint:
        value = math.nextafter(value, -math.inf)
    elif direction > 0 and represented < endpoint:
        value = math.nextafter(value, math.inf)
    if not np.isfinite(value):
        raise ValueError("outward high-precision endpoint is non-finite")
    return value


def _ulp_envelope(reference_interval) -> Decimal:
    endpoints = (
        _outward_float(reference_interval[0], -1),
        _outward_float(reference_interval[1], 1),
    )
    maximum_gap = 0.0
    for value in endpoints:
        previous = math.nextafter(value, -math.inf)
        following = math.nextafter(value, math.inf)
        if not np.isfinite(previous) or not np.isfinite(following):
            raise ValueError("ULP envelope reaches a non-finite neighbor")
        maximum_gap = max(
            maximum_gap,
            abs(value - previous),
            abs(following - value),
        )
    return Decimal.from_float(maximum_gap)


def _gamma_interval(operation_count: int) -> tuple[Decimal, Decimal]:
    unit = Fraction(1, 2 ** 53)
    product = int(operation_count) * unit
    return _fraction_interval(product / (1 - product))


def _eta_interval(multiplier: int) -> tuple[Decimal, Decimal]:
    return _fraction_interval(Fraction(int(multiplier), 2 ** 1074))


def _distance_to_interval_upper(value: float, interval) -> Decimal:
    point = Decimal.from_float(float(value))
    with localcontext() as context:
        context.prec = DECIMAL_PRECISION
        context.rounding = ROUND_CEILING
        return max(abs(point - interval[0]), abs(point - interval[1]))


def _bound_interval(
    floor: str,
    gamma_count: int,
    scale_interval,
    ulp: Decimal,
    eta_count: int,
):
    calculated = _interval_add(
        _interval_add(
            _interval_multiply(_gamma_interval(gamma_count), scale_interval),
            _interval_multiply(_interval_point(4.0), (ulp, ulp)),
        ),
        _eta_interval(eta_count),
    )
    floor_value = Decimal(floor)
    return max(floor_value, calculated[0]), max(floor_value, calculated[1])


def _ratio_upper(distance: Decimal, bound_lower: Decimal) -> Decimal:
    if bound_lower <= 0:
        raise ValueError("high-precision bound must be positive")
    with localcontext() as context:
        context.prec = DECIMAL_PRECISION
        context.rounding = ROUND_CEILING
        return distance / bound_lower


def _audit_mixture_high_precision(
    states,
    covariances,
    probabilities,
    production_mean,
    production_covariance,
    *,
    label: str,
) -> dict[str, float]:
    """Audit one registered mixture against outward Decimal intervals."""
    state_values = np.asarray(states, dtype=np.float64)
    covariance_values = np.asarray(covariances, dtype=np.float64)
    weights = np.asarray(probabilities, dtype=np.float64)
    mean = np.asarray(production_mean, dtype=np.float64)
    covariance = np.asarray(production_covariance, dtype=np.float64)
    if state_values.ndim != 2 or not 1 <= len(state_values) <= 3:
        raise ValueError(f"{label} high-precision mixture component count changed")
    component_count, state_count = state_values.shape
    if (
        covariance_values.shape != (component_count, state_count, state_count)
        or weights.shape != (component_count,)
        or mean.shape != (state_count,)
        or covariance.shape != (state_count, state_count)
    ):
        raise ValueError(f"{label} high-precision mixture shape changed")
    if (
        not np.all(np.isfinite(state_values))
        or not np.all(np.isfinite(covariance_values))
        or not np.all(np.isfinite(weights))
        or not np.all(np.isfinite(mean))
        or not np.all(np.isfinite(covariance))
        or np.any(weights < 0.0)
    ):
        raise ValueError(f"{label} high-precision mixture contains invalid values")
    active_indices = np.flatnonzero(weights > 0.0)
    if not len(active_indices):
        raise ValueError(f"{label} high-precision mixture has no active component")
    state_values = state_values[active_indices]
    covariance_values = covariance_values[active_indices]
    weights = weights[active_indices]
    weight_intervals = tuple(_interval_point(value) for value in weights)
    exact_total = _exact_weight_total_interval(weights)
    if exact_total[0] <= 0:
        raise ValueError(f"{label} exact weight total is not positive")
    reference_index = int(np.argmax(weights))
    reference = state_values[reference_index]

    mean_maximum_ratio = Decimal(0)
    for state_index in range(state_count):
        reference_interval = _interval_point(reference[state_index])
        shifted_terms = []
        absolute_terms = []
        for weight_interval, state in zip(weight_intervals, state_values):
            difference = _interval_subtract(
                _interval_point(state[state_index]),
                reference_interval,
            )
            shifted_terms.append(_interval_multiply(weight_interval, difference))
            absolute_terms.append(
                _interval_multiply(weight_interval, _interval_absolute(difference))
            )
        shifted_sum = _interval_sum(shifted_terms)
        normalized_shift = _interval_divide(shifted_sum, exact_total)
        exact_mean = _interval_add(reference_interval, normalized_shift)
        scale = _interval_divide(_interval_sum(absolute_terms), exact_total)
        bound = _bound_interval(
            "1e-12",
            MEAN_GAMMA_COUNT,
            scale,
            _ulp_envelope(exact_mean),
            128,
        )
        distance = _distance_to_interval_upper(mean[state_index], exact_mean)
        ratio = _ratio_upper(distance, bound[0])
        if ratio > 1:
            raise ValueError(
                f"{label} high-precision mean exceeds its registered bound "
                f"at state {state_index}: ratio={ratio}"
            )
        mean_maximum_ratio = max(mean_maximum_ratio, ratio)

    raw_references = [[None] * state_count for _ in range(state_count)]
    raw_scales = [[Decimal(0)] * state_count for _ in range(state_count)]
    for row in range(state_count):
        for column in range(state_count):
            terms = []
            scale_terms = []
            for weight_interval, state, component_covariance in zip(
                weight_intervals,
                state_values,
                covariance_values,
            ):
                row_difference = _interval_subtract(
                    _interval_point(state[row]),
                    _interval_point(mean[row]),
                )
                column_difference = _interval_subtract(
                    _interval_point(state[column]),
                    _interval_point(mean[column]),
                )
                centered_product = _interval_multiply(
                    row_difference,
                    column_difference,
                )
                component_term = _interval_add(
                    _interval_point(component_covariance[row, column]),
                    centered_product,
                )
                terms.append(_interval_multiply(weight_interval, component_term))
                component_scale = _interval_add(
                    _interval_absolute(
                        _interval_point(component_covariance[row, column])
                    ),
                    _interval_absolute(centered_product),
                )
                scale_terms.append(
                    _interval_multiply(weight_interval, component_scale)
                )
            raw_references[row][column] = _interval_divide(
                _interval_sum(terms),
                exact_total,
            )
            raw_scales[row][column] = _interval_divide(
                _interval_sum(scale_terms),
                exact_total,
            )

    covariance_maximum_ratio = Decimal(0)
    half = _interval_point(0.5)
    for row in range(state_count):
        for column in range(state_count):
            exact_covariance = _interval_multiply(
                _interval_add(
                    raw_references[row][column],
                    raw_references[column][row],
                ),
                half,
            )
            first_scale = raw_scales[row][column]
            second_scale = raw_scales[column][row]
            scale = (
                max(first_scale[0], second_scale[0]),
                max(first_scale[1], second_scale[1]),
            )
            bound = _bound_interval(
                "1e-11",
                COVARIANCE_GAMMA_COUNT,
                scale,
                _ulp_envelope(exact_covariance),
                256,
            )
            distance = _distance_to_interval_upper(
                covariance[row, column],
                exact_covariance,
            )
            ratio = _ratio_upper(distance, bound[0])
            if ratio > 1:
                raise ValueError(
                    f"{label} high-precision covariance exceeds its registered "
                    f"bound at ({row}, {column}): ratio={ratio}"
                )
            covariance_maximum_ratio = max(covariance_maximum_ratio, ratio)
    return {
        "mean_maximum_ratio": float(mean_maximum_ratio),
        "covariance_maximum_ratio": float(covariance_maximum_ratio),
    }


def _derive_true_candidate_indices(
    candidate_parameter_names,
    candidate_parameter_vectors,
    daily_true_parfc,
    *,
    stage_days: int,
) -> np.ndarray:
    names = np.asarray(candidate_parameter_names)
    vectors = np.asarray(candidate_parameter_vectors, dtype=np.float64)
    truth = np.asarray(daily_true_parfc, dtype=np.float64)
    matches = np.flatnonzero(names.astype(str) == "parFC")
    if len(matches) != 1:
        raise ValueError("candidate parameter names must contain parFC exactly once")
    if vectors.ndim != 2 or vectors.shape[0] != 3 or vectors.shape[1] != len(names):
        raise ValueError("candidate parameter vectors have an invalid shape")
    if truth.ndim != 1 or not np.all(np.isfinite(truth)):
        raise ValueError("daily true parFC must be a finite vector")
    if int(stage_days) != 180 or len(truth) != len(TRUTH_STAGE_SEQUENCE) * 180:
        raise ValueError("daily true parFC does not cover seven 180-day stages")
    candidate_values = vectors[:, int(matches[0])]
    equality = truth[:, None] == candidate_values[None, :]
    if not np.all(np.sum(equality, axis=1) == 1):
        raise ValueError("daily true parFC does not uniquely match a candidate")
    derived = np.argmax(equality, axis=1).astype(np.int64)
    expected = np.repeat(TRUTH_STAGE_SEQUENCE, 180)
    if not np.array_equal(derived, expected):
        raise ValueError("daily true parFC does not follow the registered stage order")
    return derived


def evaluate_events_independently(
    probabilities,
    switch_days,
    true_candidate_indices,
    response_window_days: int = 30,
    consecutive_days: int = 5,
) -> list[dict]:
    values = np.asarray(probabilities, dtype=np.float64)
    switches = np.asarray(switch_days, dtype=np.int64)
    truth = np.asarray(true_candidate_indices, dtype=np.int64)
    if values.ndim != 2 or values.shape[1] != 3:
        raise ValueError("probability array must have three candidates")
    if truth.shape != (len(values),):
        raise ValueError("true-candidate indices do not match probability days")
    events = []
    for switch in switches:
        day = int(switch)
        if day < 0 or day >= len(values):
            raise ValueError("switch day falls outside probability days")
        new_member = int(truth[day])
        old_member = int(truth[day - 1]) if day else new_member
        passed = False
        response_start = -1
        final_start = min(day + response_window_days, len(values)) - consecutive_days
        for start in range(day, final_start + 1):
            block = values[start : start + consecutive_days]
            other = np.delete(block, new_member, axis=1)
            if np.all(block[:, new_member] > 0.5) and np.all(
                block[:, new_member, None] - other >= 0.1
            ):
                passed = True
                response_start = start - day
                break
        events.append(
            {
                "switch_day": day,
                "old_member": old_member,
                "new_member": new_member,
                "passed": passed,
                "response_start": response_start,
            }
        )
    return events


def _verify_probability_arrays(arrays: Mapping[str, np.ndarray], label: str) -> None:
    _require_fields(
        arrays,
        ("probabilities", "log_probabilities", "true_candidate_indices"),
        label,
    )
    probabilities = np.asarray(arrays["probabilities"], dtype=np.float64)
    logs = np.asarray(arrays["log_probabilities"], dtype=np.float64)
    truth = np.asarray(arrays["true_candidate_indices"], dtype=np.int64)
    if (
        probabilities.ndim != 2
        or probabilities.shape[1] != 3
        or logs.shape != probabilities.shape
        or truth.shape != (len(probabilities),)
        or len(probabilities) != SCORING_STOP
    ):
        raise ValueError(f"{label} probability or truth shape changed")
    if not np.all(np.isfinite(probabilities)) or not np.all(np.isfinite(logs)):
        raise ValueError(f"{label} candidate probabilities are non-finite")
    if np.any(probabilities < 0.0) or np.any(probabilities > 1.0):
        raise ValueError(f"{label} candidate probabilities fall outside [0,1]")
    if np.max(np.abs(probabilities.sum(axis=1) - 1.0)) > PROBABILITY_TOLERANCE:
        raise ValueError(f"{label} candidate probabilities are not normalized")
    if np.max(np.abs(np.logaddexp.reduce(logs, axis=1))) > PROBABILITY_TOLERANCE:
        raise ValueError(f"{label} stable candidate logs are not normalized")
    if np.max(np.abs(np.exp(logs) - probabilities)) > PROBABILITY_TOLERANCE:
        raise ValueError(f"{label} ordinary and stable probabilities disagree")
    if np.any((truth < 0) | (truth >= 3)):
        raise ValueError(f"{label} true-candidate indices are invalid")


def _probability_metrics(arrays: Mapping[str, np.ndarray]) -> tuple[dict, list[dict]]:
    probabilities = np.asarray(arrays["probabilities"], dtype=np.float64)
    logs = np.asarray(arrays["log_probabilities"], dtype=np.float64)
    truth = np.asarray(arrays["true_candidate_indices"], dtype=np.int64)
    if len(probabilities) != SCORING_STOP:
        raise ValueError("probability metrics require the registered 1260 days")
    indices = np.arange(SCORING_START, SCORING_STOP)
    scored_truth = truth[indices]
    true_probabilities = probabilities[indices, scored_truth]
    true_negative_logs = -logs[indices, scored_truth]
    target = np.eye(3, dtype=np.float64)[scored_truth]
    daily_brier = np.sum((probabilities[indices] - target) ** 2, axis=1)
    events = evaluate_events_independently(
        probabilities,
        arrays["switch_days"],
        truth,
    )
    metrics = {
        "scored_days": int(len(indices)),
        "severe_negative_log_probability_days": int(
            np.sum(true_negative_logs > SEVERE_NLL_THRESHOLD)
        ),
        "mean_true_negative_log_probability": float(
            np.mean(true_negative_logs)
        ),
        "zero_true_probability_days": int(np.sum(true_probabilities == 0.0)),
        "multiclass_brier": float(np.mean(daily_brier)),
        "events_passed": int(sum(event["passed"] for event in events)),
        "event_count": int(len(events)),
        "_negative_log_probability_sum": float(true_negative_logs.sum()),
        "_brier_sum": float(daily_brier.sum()),
    }
    return metrics, events


def _require_symmetric(values, label: str, tolerance: float) -> None:
    array = np.asarray(values, dtype=np.float64)
    difference = _maximum_absolute_difference(array, np.swapaxes(array, -1, -2))
    if difference > tolerance:
        raise ValueError(f"{label} covariance is not symmetric")


def _verify_inactive_sentinels(
    values,
    active_mask,
    label: str,
    trailing_dimensions: int,
) -> None:
    array = np.asarray(values, dtype=np.float64)
    mask = np.asarray(active_mask, dtype=bool)
    expanded = mask[(...,) + (None,) * trailing_dimensions]
    expanded = np.broadcast_to(expanded, array.shape)
    if not np.all(np.isfinite(array[expanded])):
        raise ValueError(f"active {label} contains non-finite values")
    if not np.all(np.isnan(array[~expanded])):
        raise ValueError(f"inactive branch sentinel changed for {label}")


def _verify_path_arrays(
    arrays: Mapping[str, np.ndarray],
    initial_moments: tuple[np.ndarray, np.ndarray, np.ndarray],
) -> dict[str, float]:
    """Independently rebuild the registered postcollapse probability and moments."""
    _require_fields(arrays, PATH_REQUIRED_FIELDS, "arm P path audit")
    probabilities = np.asarray(arrays["probabilities"], dtype=np.float64)
    n_days = len(probabilities)
    expected_shapes = {
        "path_initial_probabilities": (3,),
        "path_initial_states": (3, 15),
        "path_initial_covariances": (3, 15, 15),
        "path_source_probabilities": (n_days, 3),
        "path_source_states": (n_days, 3, 15),
        "path_source_covariances": (n_days, 3, 15, 15),
        "path_candidate_prior_probabilities": (n_days, 3),
        "path_branch_prior_log_probabilities": (n_days, 3, 3),
        "path_branch_posterior_log_probabilities": (n_days, 3, 3),
        "path_branch_posterior_probabilities": (n_days, 3, 3),
        "path_destination_raw_probabilities": (n_days, 3),
        "path_posterior_probabilities": (n_days, 3),
        "path_destination_raw_conditional_probabilities": (n_days, 3, 3),
        "path_destination_conditional_probabilities": (n_days, 3, 3),
        "path_posterior_log_probabilities": (n_days, 3),
        "path_branch_active_mask": (n_days, 3, 3),
        "path_branch_log_likelihoods": (n_days, 3, 3),
        "path_branch_prior_observations": (n_days, 3, 3, 1),
        "path_branch_innovations": (n_days, 3, 3, 1),
        "path_branch_innovation_covariances": (n_days, 3, 3, 1, 1),
        "path_branch_prior_states": (n_days, 3, 3, 15),
        "path_branch_posterior_states": (n_days, 3, 3, 15),
        "path_branch_prior_covariances": (n_days, 3, 3, 15, 15),
        "path_branch_posterior_covariances": (n_days, 3, 3, 15, 15),
        "path_destination_states": (n_days, 3, 15),
        "path_destination_covariances": (n_days, 3, 15, 15),
        "path_combined_states": (n_days, 15),
        "path_combined_covariances": (n_days, 15, 15),
        "path_destination_reference_indices": (n_days, 3),
        "path_global_reference_indices": (n_days,),
        "path_direct_states": (n_days, 15),
        "path_direct_covariances": (n_days, 15, 15),
        "path_direct_nested_state_absolute_differences": (n_days, 15),
        "path_direct_nested_state_relative_differences": (n_days, 15),
        "path_direct_nested_state_ulp_distances": (n_days, 15),
        "path_direct_nested_covariance_absolute_differences": (n_days, 15, 15),
        "path_direct_nested_covariance_relative_differences": (n_days, 15, 15),
        "path_direct_nested_covariance_ulp_distances": (n_days, 15, 15),
        "path_direct_nested_state_max_abs_difference": (n_days,),
        "path_direct_nested_covariance_max_abs_difference": (n_days,),
        "path_transition_matrix": (3, 3),
        "path_branch_flatten_indices": (9, 2),
    }
    for name, shape in expected_shapes.items():
        observed_shape = np.asarray(arrays[name]).shape
        if observed_shape != shape:
            raise ValueError(
                f"arm P path field {name} shape changed: "
                f"expected {shape}, observed {observed_shape}"
            )

    metadata = {
        "path_initial_probability_axis_order": ["candidate"],
        "path_initial_state_axis_order": ["candidate", "state"],
        "path_initial_covariance_axis_order": [
            "candidate", "state_row", "state_column"
        ],
        "path_source_probability_axis_order": ["day", "source_candidate"],
        "path_source_state_axis_order": ["day", "source_candidate", "state"],
        "path_source_covariance_axis_order": [
            "day", "source_candidate", "state_row", "state_column"
        ],
        "path_probability_axis_order": ["day", "candidate"],
        "path_branch_axis_order": [
            "day", "source_candidate", "destination_candidate"
        ],
        "path_transition_axis_order": [
            "source_candidate", "destination_candidate"
        ],
        "path_destination_probability_axis_order": [
            "day", "destination_candidate"
        ],
        "path_destination_conditional_probability_axis_order": [
            "day", "source_candidate", "destination_candidate"
        ],
        "path_destination_reference_index_axis_order": [
            "day", "destination_candidate"
        ],
        "path_global_reference_index_axis_order": ["day"],
        "path_branch_flatten_index_axis_order": [
            "flattened_branch", "source_destination_coordinate"
        ],
        "path_observation_axis_order": [
            "day", "source_candidate", "destination_candidate", "observation"
        ],
        "path_innovation_covariance_axis_order": [
            "day", "source_candidate", "destination_candidate",
            "observation_row", "observation_column"
        ],
        "path_state_axis_order": [
            "day", "source_candidate", "destination_candidate", "state"
        ],
        "path_covariance_axis_order": [
            "day", "source_candidate", "destination_candidate",
            "state_row", "state_column"
        ],
        "path_candidate_state_axis_order": ["day", "candidate", "state"],
        "path_candidate_covariance_axis_order": [
            "day", "candidate", "state_row", "state_column"
        ],
        "path_combined_state_axis_order": ["day", "state"],
        "path_combined_covariance_axis_order": [
            "day", "state_row", "state_column"
        ],
        "path_direct_state_axis_order": ["day", "state"],
        "path_direct_covariance_axis_order": [
            "day", "state_row", "state_column"
        ],
        "path_direct_nested_state_diagnostic_axis_order": ["day", "state"],
        "path_direct_nested_covariance_diagnostic_axis_order": [
            "day", "state_row", "state_column"
        ],
    }
    for name, expected in metadata.items():
        if not np.array_equal(np.asarray(arrays[name]), np.asarray(expected)):
            raise ValueError(f"arm P path axis metadata changed for {name}")
    expected_flatten = np.asarray(
        [(source, destination) for source in range(3) for destination in range(3)],
        dtype=np.int64,
    )
    if not np.array_equal(arrays["path_branch_flatten_indices"], expected_flatten):
        raise ValueError("arm P source-major branch flatten identity changed")
    scalar_metadata = {
        "path_branch_flatten_order": "source_major_destination_minor",
        "path_reference_selection": "maximum_weight_then_lowest_original_index",
        "path_initial_snapshot_timing": "before_day_0_step",
        "path_unique_global_moment_role": "authoritative_nested_destination_mixture",
        "path_direct_global_moment_role": "nonblocking_diagnostic_only",
        "path_recursive_probability_representation": "ordinary_float",
        "path_hypothesis_collapse_timing": "after_observation",
    }
    for name, expected in scalar_metadata.items():
        if _scalar(arrays, name) != expected:
            raise ValueError(f"arm P path metadata changed for {name}")

    transition = np.asarray(arrays["path_transition_matrix"], dtype=np.float64)
    source_probabilities = np.asarray(
        arrays["path_source_probabilities"], dtype=np.float64
    )
    source_states = np.asarray(arrays["path_source_states"], dtype=np.float64)
    source_covariances = np.asarray(
        arrays["path_source_covariances"], dtype=np.float64
    )
    if (
        not np.all(np.isfinite(transition))
        or np.any(transition < 0.0)
        or np.max(np.abs(transition.sum(axis=1) - 1.0)) > PROBABILITY_TOLERANCE
    ):
        raise ValueError("arm P transition matrix is invalid")
    if (
        not np.all(np.isfinite(source_probabilities))
        or np.any(source_probabilities < 0.0)
        or np.any(source_probabilities > 1.0)
        or np.max(np.abs(source_probabilities.sum(axis=1) - 1.0))
        > PROBABILITY_TOLERANCE
        or not np.all(np.isfinite(source_states))
        or not np.all(np.isfinite(source_covariances))
    ):
        raise ValueError("arm P source probability or moments are invalid")

    initial_probabilities, initial_states, initial_covariances = initial_moments
    for saved_name, expected, label in (
        ("path_initial_probabilities", initial_probabilities, "initial probabilities"),
        ("path_initial_states", initial_states, "initial states"),
        ("path_initial_covariances", initial_covariances, "initial covariances"),
    ):
        _require_bitwise_equal(arrays[saved_name], expected, label)
    _require_bitwise_equal(source_probabilities[0], initial_probabilities,
                           "day-zero source probabilities")
    _require_bitwise_equal(source_states[0], initial_states,
                           "day-zero source states")
    _require_bitwise_equal(source_covariances[0], initial_covariances,
                           "day-zero source covariances")

    active = np.asarray(arrays["path_branch_active_mask"])
    if active.dtype != np.bool_:
        raise ValueError("arm P active branch mask must be boolean")
    expected_active = (
        (source_probabilities > 0.0)[:, :, None]
        & (transition > 0.0)[None, :, :]
    )
    if not np.array_equal(active, expected_active):
        raise ValueError("arm P active branch mask differs from ordinary recursion")
    prior_logs = np.asarray(
        arrays["path_branch_prior_log_probabilities"], dtype=np.float64
    )
    posterior_logs = np.asarray(
        arrays["path_branch_posterior_log_probabilities"], dtype=np.float64
    )
    likelihoods = np.asarray(
        arrays["path_branch_log_likelihoods"], dtype=np.float64
    )
    for values, label in (
        (prior_logs, "prior path log probabilities"),
        (posterior_logs, "posterior path log probabilities"),
        (likelihoods, "path log likelihoods"),
    ):
        if np.any(np.isnan(values)) or np.any(np.isposinf(values)):
            raise ValueError(f"arm P {label} contain invalid values")
        if not np.all(np.isfinite(values[active])):
            raise ValueError(f"active arm P {label} must be finite")
        if not np.all(np.isneginf(values[~active])):
            raise ValueError(f"inactive branch sentinel changed for {label}")
    branch_dense_fields = {
        "path_branch_prior_observations": 1,
        "path_branch_innovations": 1,
        "path_branch_innovation_covariances": 2,
        "path_branch_prior_states": 1,
        "path_branch_posterior_states": 1,
        "path_branch_prior_covariances": 2,
        "path_branch_posterior_covariances": 2,
    }
    for name, trailing in branch_dense_fields.items():
        _verify_inactive_sentinels(arrays[name], active, name, trailing)
    innovation_covariances = np.asarray(
        arrays["path_branch_innovation_covariances"], dtype=np.float64
    )
    if not np.all(innovation_covariances[..., 0, 0][active] > 0.0):
        raise ValueError("active branch innovation covariance must be positive")
    _require_symmetric(innovation_covariances[active], "branch innovation", 0.0)

    finite_fields = (
        "path_destination_states", "path_destination_covariances",
        "path_combined_states", "path_combined_covariances",
        "path_direct_states", "path_direct_covariances",
        "path_direct_nested_state_absolute_differences",
        "path_direct_nested_state_relative_differences",
        "path_direct_nested_covariance_absolute_differences",
        "path_direct_nested_covariance_relative_differences",
        "path_direct_nested_state_max_abs_difference",
        "path_direct_nested_covariance_max_abs_difference",
    )
    for name in finite_fields:
        if not np.all(np.isfinite(np.asarray(arrays[name], dtype=np.float64))):
            raise ValueError(f"arm P path field {name} contains non-finite values")
    for name in (
        "path_destination_covariances", "path_combined_covariances",
        "path_direct_covariances",
    ):
        _require_bitwise_equal(arrays[name], np.swapaxes(arrays[name], -1, -2),
                               f"{name} symmetry")

    _require_bitwise_equal(source_probabilities[1:], probabilities[:-1],
                           "ordinary candidate probability recursion")
    _require_bitwise_equal(source_states[1:], arrays["path_destination_states"][:-1],
                           "source state recursion")
    _require_bitwise_equal(
        source_covariances[1:], arrays["path_destination_covariances"][:-1],
        "source covariance recursion",
    )

    branch_states = np.asarray(
        arrays["path_branch_posterior_states"], dtype=np.float64
    )
    branch_covariances = np.asarray(
        arrays["path_branch_posterior_covariances"], dtype=np.float64
    )
    destination_states = np.asarray(arrays["path_destination_states"], dtype=np.float64)
    destination_covariances = np.asarray(
        arrays["path_destination_covariances"], dtype=np.float64
    )
    combined_states = np.asarray(arrays["path_combined_states"], dtype=np.float64)
    combined_covariances = np.asarray(
        arrays["path_combined_covariances"], dtype=np.float64
    )
    direct_states = np.asarray(arrays["path_direct_states"], dtype=np.float64)
    direct_covariances = np.asarray(arrays["path_direct_covariances"], dtype=np.float64)
    candidate_logs = np.asarray(arrays["log_probabilities"], dtype=np.float64)
    log_transition = np.full((3, 3), -np.inf, dtype=np.float64)
    positive_transition = transition > 0.0
    log_transition[positive_transition] = np.log(transition[positive_transition])
    maxima = {
        "authoritative_bitwise_reconstruction_maximum_difference": 0.0,
        "destination_high_precision_mean_maximum_ratio": 0.0,
        "destination_high_precision_covariance_maximum_ratio": 0.0,
        "global_high_precision_mean_maximum_ratio": 0.0,
        "global_high_precision_covariance_maximum_ratio": 0.0,
        "direct_nested_state_maximum_absolute_difference": 0.0,
        "direct_nested_covariance_maximum_absolute_difference": 0.0,
        "direct_nested_state_maximum_relative_difference": 0.0,
        "direct_nested_covariance_maximum_relative_difference": 0.0,
        "direct_nested_state_maximum_ulp_distance": 0,
        "direct_nested_covariance_maximum_ulp_distance": 0,
    }
    for day in range(n_days):
        source_logs = np.full(3, -np.inf, dtype=np.float64)
        positive_source = source_probabilities[day] > 0.0
        source_logs[positive_source] = np.log(source_probabilities[day, positive_source])
        raw_prior_logs = source_logs[:, None] + log_transition
        _require_bitwise_equal(prior_logs[day], raw_prior_logs,
                               "raw branch prior log probabilities")
        branch_prior_probabilities, _ = _normalize_log_weights(
            raw_prior_logs.reshape(-1)
        )
        branch_prior_probabilities = branch_prior_probabilities.reshape(3, 3)
        expected_candidate_priors = branch_prior_probabilities.sum(axis=0)
        _require_bitwise_equal(
            arrays["path_candidate_prior_probabilities"][day],
            expected_candidate_priors,
            "candidate prior probabilities",
        )

        w, expected_posterior_logs = _normalize_log_weights(
            (raw_prior_logs + likelihoods[day]).reshape(-1)
        )
        w = w.reshape(3, 3)
        expected_posterior_logs = expected_posterior_logs.reshape(3, 3)
        _require_bitwise_equal(
            arrays["path_branch_posterior_probabilities"][day], w,
            "branch posterior probabilities",
        )
        _require_bitwise_equal(posterior_logs[day], expected_posterior_logs,
                               "branch posterior log probabilities")
        mu_raw = np.asarray(
            [math.fsum(float(value) for value in w[:, destination])
             for destination in range(3)],
            dtype=np.float64,
        )
        beta = _normalize_path_weights(mu_raw)
        alpha_raw = np.zeros((3, 3), dtype=np.float64)
        a = np.zeros((3, 3), dtype=np.float64)
        for destination in range(3):
            if mu_raw[destination] > 0.0:
                alpha_raw[:, destination] = w[:, destination] / mu_raw[destination]
                a[:, destination] = _normalize_path_weights(alpha_raw[:, destination])
        for name, expected in (
            ("path_destination_raw_probabilities", mu_raw),
            ("path_posterior_probabilities", beta),
            ("path_destination_raw_conditional_probabilities", alpha_raw),
            ("path_destination_conditional_probabilities", a),
        ):
            _require_bitwise_equal(arrays[name][day], expected, name)
        _require_bitwise_equal(probabilities[day], beta,
                               "saved ordinary candidate probabilities")

        destination_log_weights = np.asarray(
            [_logsumexp(expected_posterior_logs[:, destination])
             for destination in range(3)],
            dtype=np.float64,
        )
        _, expected_candidate_logs = _normalize_log_weights(destination_log_weights)
        _require_bitwise_equal(
            arrays["path_posterior_log_probabilities"][day],
            expected_candidate_logs,
            "path stable candidate log probabilities",
        )
        _require_bitwise_equal(candidate_logs[day], expected_candidate_logs,
                               "stable candidate log probabilities")

        reconstructed_states = np.empty((3, 15), dtype=np.float64)
        reconstructed_covariances = np.empty((3, 15, 15), dtype=np.float64)
        reconstructed_references = np.full(3, -1, dtype=np.int64)
        for destination in range(3):
            source_indices = np.flatnonzero(a[:, destination] > 0.0)
            if len(source_indices) == 0:
                reconstructed_states[destination] = source_states[day, destination]
                reconstructed_covariances[destination] = source_covariances[
                    day, destination
                ]
                continue
            state, covariance, local_reference = _registered_mixture_moments(
                branch_states[day, source_indices, destination],
                branch_covariances[day, source_indices, destination],
                a[source_indices, destination],
            )
            reconstructed_states[destination] = state
            reconstructed_covariances[destination] = covariance
            reconstructed_references[destination] = source_indices[local_reference]
            high_precision = _audit_mixture_high_precision(
                branch_states[day, source_indices, destination],
                branch_covariances[day, source_indices, destination],
                a[source_indices, destination],
                state,
                covariance,
                label=f"day {day} destination {destination}",
            )
            maxima["destination_high_precision_mean_maximum_ratio"] = max(
                maxima["destination_high_precision_mean_maximum_ratio"],
                high_precision["mean_maximum_ratio"],
            )
            maxima["destination_high_precision_covariance_maximum_ratio"] = max(
                maxima["destination_high_precision_covariance_maximum_ratio"],
                high_precision["covariance_maximum_ratio"],
            )
        _require_bitwise_equal(destination_states[day], reconstructed_states,
                               "destination states")
        _require_bitwise_equal(destination_covariances[day], reconstructed_covariances,
                               "destination covariances")
        _require_bitwise_equal(
            arrays["path_destination_reference_indices"][day],
            reconstructed_references,
            "destination reference indices",
        )

        global_state, global_covariance, global_reference = _registered_mixture_moments(
            reconstructed_states, reconstructed_covariances, beta
        )
        _require_bitwise_equal(combined_states[day], global_state,
                               "authoritative combined state")
        _require_bitwise_equal(combined_covariances[day], global_covariance,
                               "authoritative combined covariance")
        if int(arrays["path_global_reference_indices"][day]) != global_reference:
            raise ValueError("global reference index changed")
        global_high_precision = _audit_mixture_high_precision(
            reconstructed_states,
            reconstructed_covariances,
            beta,
            global_state,
            global_covariance,
            label=f"day {day} global",
        )
        maxima["global_high_precision_mean_maximum_ratio"] = max(
            maxima["global_high_precision_mean_maximum_ratio"],
            global_high_precision["mean_maximum_ratio"],
        )
        maxima["global_high_precision_covariance_maximum_ratio"] = max(
            maxima["global_high_precision_covariance_maximum_ratio"],
            global_high_precision["covariance_maximum_ratio"],
        )

        direct_mask = w.reshape(9) > 0.0
        direct_state, direct_covariance, _ = _registered_mixture_moments(
            branch_states[day].reshape(9, 15)[direct_mask],
            branch_covariances[day].reshape(9, 15, 15)[direct_mask],
            w.reshape(9)[direct_mask],
            _maximum_components=9,
        )
        _require_bitwise_equal(direct_states[day], direct_state,
                               "direct diagnostic state")
        _require_bitwise_equal(direct_covariances[day], direct_covariance,
                               "direct diagnostic covariance")
        state_absolute, state_relative, state_ulp = _direct_nested_diagnostics(
            direct_state, global_state
        )
        covariance_absolute, covariance_relative, covariance_ulp = (
            _direct_nested_diagnostics(direct_covariance, global_covariance)
        )
        for name, expected in (
            ("path_direct_nested_state_absolute_differences", state_absolute),
            ("path_direct_nested_state_relative_differences", state_relative),
            ("path_direct_nested_state_ulp_distances", state_ulp),
            ("path_direct_nested_covariance_absolute_differences", covariance_absolute),
            ("path_direct_nested_covariance_relative_differences", covariance_relative),
            ("path_direct_nested_covariance_ulp_distances", covariance_ulp),
        ):
            _require_bitwise_equal(arrays[name][day], expected, name)
        state_maximum = float(np.max(state_absolute))
        covariance_maximum = float(np.max(covariance_absolute))
        _require_bitwise_equal(
            arrays["path_direct_nested_state_max_abs_difference"][day],
            np.asarray(state_maximum),
            "direct nested state maximum diagnostic",
        )
        _require_bitwise_equal(
            arrays["path_direct_nested_covariance_max_abs_difference"][day],
            np.asarray(covariance_maximum),
            "direct nested covariance maximum diagnostic",
        )
        maxima["direct_nested_state_maximum_absolute_difference"] = max(
            maxima["direct_nested_state_maximum_absolute_difference"], state_maximum
        )
        maxima["direct_nested_covariance_maximum_absolute_difference"] = max(
            maxima["direct_nested_covariance_maximum_absolute_difference"],
            covariance_maximum,
        )
        maxima["direct_nested_state_maximum_relative_difference"] = max(
            maxima["direct_nested_state_maximum_relative_difference"],
            float(np.max(state_relative)),
        )
        maxima["direct_nested_covariance_maximum_relative_difference"] = max(
            maxima["direct_nested_covariance_maximum_relative_difference"],
            float(np.max(covariance_relative)),
        )
        maxima["direct_nested_state_maximum_ulp_distance"] = max(
            maxima["direct_nested_state_maximum_ulp_distance"], int(np.max(state_ulp))
        )
        maxima["direct_nested_covariance_maximum_ulp_distance"] = max(
            maxima["direct_nested_covariance_maximum_ulp_distance"],
            int(np.max(covariance_ulp)),
        )
    return maxima


def _verify_task_records(
    output_root: Path,
    expected_keys: set[tuple[str, int]],
) -> None:
    for arm_id in ("C", "P"):
        path = output_root / "arms" / arm_id / "tasks.csv"
        if not path.is_file():
            raise FileNotFoundError(f"arm {arm_id} task records are missing")
        records = pd.read_csv(path, dtype={"basin_id": str}, keep_default_na=False)
        required = {"basin_id", "seed", "arm_id", "run_status", "truth_clip_count"}
        if not required.issubset(records.columns) or len(records) != 10:
            raise ValueError(f"arm {arm_id} task records are incomplete")
        records["basin_id"] = [
            _normalize_basin_id(value) for value in records["basin_id"]
        ]
        keys = set(zip(records["basin_id"], records["seed"].astype(int)))
        if (
            keys != expected_keys
            or not (records["arm_id"] == arm_id).all()
            or not (records["run_status"] == "success").all()
            or not (records["truth_clip_count"].astype(int) == 0).all()
        ):
            raise ValueError(f"arm {arm_id} task records are invalid")
        probability_files = {
            path.stem
            for path in (output_root / "arms" / arm_id / "probs").glob("*.npz")
        }
        expected_files = {f"{basin_id}_s{seed}" for basin_id, seed in expected_keys}
        if probability_files != expected_files:
            raise ValueError(f"arm {arm_id} probability file set is incomplete")


def _aggregate_task_metrics(task_rows: list[dict]) -> dict[str, dict]:
    result = {}
    for arm_id in ("C", "P"):
        rows = [row for row in task_rows if row["arm_id"] == arm_id]
        scored_days = sum(int(row["scored_days"]) for row in rows)
        event_count = sum(int(row["event_count"]) for row in rows)
        result[arm_id] = {
            "task_count": len(rows),
            "scored_days": scored_days,
            "severe_negative_log_probability_days": sum(
                int(row["severe_negative_log_probability_days"]) for row in rows
            ),
            "mean_true_negative_log_probability": float(
                sum(float(row["_negative_log_probability_sum"]) for row in rows)
                / scored_days
            ),
            "zero_true_probability_days": sum(
                int(row["zero_true_probability_days"]) for row in rows
            ),
            "multiclass_brier": float(
                sum(float(row["_brier_sum"]) for row in rows) / scored_days
            ),
            "events_passed": sum(int(row["events_passed"]) for row in rows),
            "event_count": event_count,
            "event_pass_rate": float(
                sum(int(row["events_passed"]) for row in rows) / event_count
            )
            if event_count
            else 0.0,
        }
    return result


def verify_parameter_path_mechanism(
    config_path: str | Path,
    expected_config_sha256: str,
) -> dict:
    """Verify a complete C/P mechanism run and atomically write two reports."""
    root = Path(_REPO_ROOT).resolve()
    configuration = Path(config_path)
    if not configuration.is_absolute():
        configuration = root / configuration
    configuration = configuration.resolve()
    if not configuration.is_file():
        raise FileNotFoundError(f"configuration is missing: {configuration}")
    try:
        configuration.relative_to(root)
    except ValueError as error:
        raise ValueError("configuration path must be inside the repository root") from error
    observed_config_sha256 = sha256_file(configuration)
    if observed_config_sha256 != str(expected_config_sha256):
        raise ValueError(
            "configuration SHA-256 changed: "
            f"expected {expected_config_sha256}, observed {observed_config_sha256}"
        )
    config = json.loads(configuration.read_text(encoding="utf-8"))
    if not isinstance(config, Mapping):
        raise ValueError("configuration root must be a JSON object")
    if config.get("configuration_status") != CONFIGURATION_STATUS:
        raise ValueError(f"configuration_status must be {CONFIGURATION_STATUS}")
    runtime_contract = _verify_runtime_contract(config)
    if tuple(config.get("arms", ())) != EXPECTED_ARMS:
        raise ValueError("mechanism arms must be exactly C and P")
    inputs = config.get("inputs")
    outputs = config.get("outputs")
    if not isinstance(inputs, Mapping) or not isinstance(outputs, Mapping):
        raise ValueError("configuration inputs and outputs must be mappings")
    implementation_hashes, registered_input_hashes = _verify_registered_files(
        root,
        config,
    )
    output_root = _repository_path(root, outputs.get("root"), "output root").resolve()
    if not output_root.is_dir():
        raise FileNotFoundError(f"completed output root is missing: {output_root}")
    verification_root = output_root / "verification"
    temporary_verification_root = output_root / "verification.tmp"
    if verification_root.exists() or temporary_verification_root.exists():
        raise FileExistsError(
            "verification output or temporary verification already exists"
        )

    task_table_path = _repository_path(
        root,
        inputs.get("task_table"),
        "task table",
    )
    if not task_table_path.is_file():
        raise FileNotFoundError(f"task table is missing: {task_table_path}")
    task_table_sha256 = sha256_file(task_table_path)
    if task_table_sha256 != str(inputs.get("task_table_sha256")):
        raise ValueError("task table SHA-256 changed")
    tasks = pd.read_csv(
        task_table_path,
        dtype={"basin_id": str, "arm_id": str},
        keep_default_na=False,
    )
    if not TASK_COLUMNS.issubset(tasks.columns):
        raise ValueError("task table lacks required columns")
    tasks = tasks.copy()
    tasks["basin_id"] = [_normalize_basin_id(value) for value in tasks["basin_id"]]
    numeric_seeds = pd.to_numeric(tasks["seed"], errors="coerce")
    if numeric_seeds.isna().any() or any(
        float(value) != int(value) for value in numeric_seeds
    ):
        raise ValueError("task seeds must be integers")
    tasks["seed"] = numeric_seeds.astype(int)
    task_keys = list(zip(tasks["basin_id"], tasks["seed"]))
    expected_keys = set(task_keys)
    if (
        len(tasks) != 10
        or len(expected_keys) != 10
        or set(tasks["seed"]) != {0, 1}
        or not (tasks["arm_id"] == "C").all()
    ):
        raise ValueError("task table must contain ten unique design-seed arm-C tasks")
    initial_moment_manifest = _load_initial_moment_manifest(
        root,
        inputs,
        expected_keys,
    )

    runner_summary_path = output_root / "runner_summary.json"
    if not runner_summary_path.is_file():
        raise FileNotFoundError("runner summary is missing")
    runner_summary = json.loads(runner_summary_path.read_text(encoding="utf-8"))
    if (
        runner_summary.get("execution_status") != "complete"
        or runner_summary.get("scientific_aggregation_status")
        != "ready_for_independent_mechanism_verification"
        or runner_summary.get("experiment_id") != config.get("experiment_id")
        or runner_summary.get("config_sha256") != observed_config_sha256
        or runner_summary.get("n_source_tasks") != 10
        or runner_summary.get("n_arms") != 2
        or runner_summary.get("n_tasks_planned") != 20
        or runner_summary.get("n_submitted") != 20
        or runner_summary.get("run_status_counts") != {"success": 20}
        or runner_summary.get("arms") != config.get("arms")
        or runner_summary.get("runtime") != runtime_contract
        or runner_summary.get("implementation_hashes") != implementation_hashes
        or runner_summary.get("registered_input_hashes")
        != registered_input_hashes
    ):
        raise ValueError("runner summary is incomplete or mismatched")
    _verify_task_records(output_root, expected_keys)

    task_rows = []
    maximum_source_probability_difference = 0.0
    maximum_source_log_probability_difference = 0.0
    path_maxima: dict[str, float] = {}
    for task in tasks.itertuples(index=False):
        key = (str(task.basin_id), int(task.seed))
        source_path = _repository_path(
            root,
            task.source_probability_path,
            f"source task {key}",
        )
        try:
            expected_bytes = int(task.source_probability_bytes)
        except (TypeError, ValueError) as error:
            raise ValueError("source probability byte count must be an integer") from error
        if (
            not source_path.is_file()
            or source_path.stat().st_size != expected_bytes
            or sha256_file(source_path) != str(task.source_probability_sha256)
        ):
            raise ValueError(f"registered source probability file changed for {key}")
        source_arrays = _load_npz(source_path)
        arm_arrays = {
            arm_id: _load_npz(
                output_root
                / "arms"
                / arm_id
                / "probs"
                / f"{task.basin_id}_s{task.seed}.npz"
            )
            for arm_id in ("C", "P")
        }
        _require_fields(source_arrays, SOURCE_EXACT_FIELDS, "registered source")
        _verify_probability_arrays(source_arrays, "registered source")
        for arm_id, arrays in arm_arrays.items():
            _require_fields(arrays, SOURCE_EXACT_FIELDS, f"arm {arm_id}")
            _require_fields(arrays, ("truth_parfc",), f"arm {arm_id}")
            _verify_probability_arrays(arrays, f"arm {arm_id}")
            if _normalize_basin_id(_scalar(arrays, "basin_id")) != key[0] or int(
                _scalar(arrays, "seed")
            ) != key[1]:
                raise ValueError(f"arm {arm_id} embedded task identity changed")
            if int(_scalar(arrays, "truth_clip_count")) != 0:
                raise ValueError(f"arm {arm_id} truth clipping occurred")
        if (
            _scalar(arm_arrays["C"], "arm_id") != "C"
            or _scalar(arm_arrays["C"], "state_interaction_mode") != "full"
            or _scalar(arm_arrays["C"], "parameter_state_mapping")
            != "conservative_parfc"
            or _scalar(arm_arrays["P"], "arm_id") != "P"
            or _scalar(arm_arrays["P"], "state_interaction_mode")
            != "pairwise_path_postcollapse"
            or _scalar(arm_arrays["P"], "parameter_state_mapping")
            != "conservative_parfc"
        ):
            raise ValueError("arm C or P method metadata changed")

        for name in SOURCE_EXACT_FIELDS:
            if not np.array_equal(source_arrays[name], arm_arrays["C"][name]):
                raise ValueError(f"arm C source shared field {name} differs")
        source_probability_difference = _maximum_absolute_difference(
            source_arrays["probabilities"],
            arm_arrays["C"]["probabilities"],
        )
        source_log_probability_difference = _assert_log_arrays_close(
            source_arrays["log_probabilities"],
            arm_arrays["C"]["log_probabilities"],
            tolerance=PROBABILITY_TOLERANCE,
            label="arm C source stable log probabilities",
        )
        if source_probability_difference > PROBABILITY_TOLERANCE:
            raise ValueError("arm C source ordinary probabilities differ")
        maximum_source_probability_difference = max(
            maximum_source_probability_difference,
            source_probability_difference,
        )
        maximum_source_log_probability_difference = max(
            maximum_source_log_probability_difference,
            source_log_probability_difference,
        )
        source_events = evaluate_events_independently(
            source_arrays["probabilities"],
            source_arrays["switch_days"],
            source_arrays["true_candidate_indices"],
        )
        arm_c_events = evaluate_events_independently(
            arm_arrays["C"]["probabilities"],
            arm_arrays["C"]["switch_days"],
            arm_arrays["C"]["true_candidate_indices"],
        )
        if source_events != arm_c_events:
            raise ValueError("arm C source event decisions differ")

        for name in CROSS_ARM_EXACT_FIELDS:
            if not np.array_equal(arm_arrays["C"][name], arm_arrays["P"][name]):
                raise ValueError(f"cross-arm shared field {name} differs")
        derived_truth = _derive_true_candidate_indices(
            arm_arrays["C"]["candidate_parameter_names"],
            arm_arrays["C"]["candidate_parameter_vectors"],
            arm_arrays["C"]["truth_parfc"],
            stage_days=int(_scalar(arm_arrays["C"], "stage_days")),
        )
        for arm_id in ("C", "P"):
            _require_bitwise_equal(
                arm_arrays[arm_id]["true_candidate_indices"],
                derived_truth,
                f"arm {arm_id} independently derived true-candidate labels",
            )
            if not np.array_equal(
                np.asarray(arm_arrays[arm_id]["switch_days"], dtype=np.int64),
                np.arange(180, 1260, 180, dtype=np.int64),
            ):
                raise ValueError(f"arm {arm_id} registered switch days changed")
            if not np.array_equal(
                np.asarray(arm_arrays[arm_id]["rotation"], dtype=np.int64),
                TRUTH_STAGE_SEQUENCE,
            ):
                raise ValueError(f"arm {arm_id} registered stage rotation changed")
        task_path_maxima = _verify_path_arrays(
            arm_arrays["P"],
            initial_moment_manifest[key],
        )
        for name, value in task_path_maxima.items():
            path_maxima[name] = max(path_maxima.get(name, 0.0), float(value))
        for arm_id in ("C", "P"):
            metrics, _ = _probability_metrics(arm_arrays[arm_id])
            task_rows.append(
                {
                    "arm_id": arm_id,
                    "basin_id": key[0],
                    "seed": key[1],
                    **metrics,
                }
            )

    if len(task_rows) != 20:
        raise ValueError("verified task metric count is not 20")
    arm_summary = _aggregate_task_metrics(task_rows)
    severe_improved = bool(
        arm_summary["P"]["severe_negative_log_probability_days"]
        < arm_summary["C"]["severe_negative_log_probability_days"]
    )
    mean_improved = bool(
        arm_summary["P"]["mean_true_negative_log_probability"]
        < arm_summary["C"]["mean_true_negative_log_probability"]
    )
    report = {
        "experiment_id": config.get("experiment_id"),
        "configuration_status": config.get("configuration_status"),
        "config_sha256": observed_config_sha256,
        "task_table_sha256": task_table_sha256,
        "implementation_hashes": implementation_hashes,
        "runtime": runtime_contract,
        "registered_input_hashes": registered_input_hashes,
        "verification_status": "passed",
        "task_count": 20,
        "source_task_count": 10,
        "scoring_slice": {
            "start_index_inclusive": SCORING_START,
            "stop_index_exclusive": SCORING_STOP,
            "days_per_task": SCORING_STOP - SCORING_START,
        },
        "maximum_source_probability_absolute_difference": (
            maximum_source_probability_difference
        ),
        "maximum_source_log_probability_absolute_difference": (
            maximum_source_log_probability_difference
        ),
        "path_reconstruction_maximum_absolute_differences": path_maxima,
        "arm_summary": arm_summary,
        "severe_day_count_strictly_improved": severe_improved,
        "mean_negative_log_probability_strictly_improved": mean_improved,
        "mechanism_gate_status": "GO"
        if severe_improved and mean_improved
        else "HOLD",
        "mechanism_gate_scope": (
            "failure_selected_design_seed_mechanism_check_only"
        ),
    }
    public_task_rows = [
        {key: value for key, value in row.items() if not key.startswith("_")}
        for row in task_rows
    ]
    temporary_verification_root.mkdir(exist_ok=False)
    try:
        pd.DataFrame(public_task_rows).to_csv(
            temporary_verification_root / "task_metrics.csv",
            index=False,
        )
        with (
            temporary_verification_root / "verification_summary.json"
        ).open("x", encoding="utf-8") as handle:
            json.dump(report, handle, indent=2, sort_keys=True)
            handle.write("\n")
        temporary_verification_root.rename(verification_root)
    except Exception:
        # Preserve a visible temporary directory as evidence; a later call refuses it.
        raise
    return report


def _parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", required=True)
    parser.add_argument("--expected-config-sha256", required=True)
    return parser.parse_args(argv)


def main(argv=None) -> int:
    arguments = _parse_args(argv)
    try:
        report = verify_parameter_path_mechanism(
            arguments.config,
            arguments.expected_config_sha256,
        )
    except Exception as error:  # noqa: BLE001 - executable must stop cleanly
        print(f"STOP: {type(error).__name__}: {error}", file=sys.stderr)
        return 1
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

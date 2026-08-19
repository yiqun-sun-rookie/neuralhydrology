"""Run the registered CAMELS-US process-noise-only switching experiment."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import time
from concurrent.futures import ProcessPoolExecutor, as_completed
from dataclasses import dataclass
from pathlib import Path
from typing import Mapping, Sequence

for _name in (
    "OMP_NUM_THREADS",
    "MKL_NUM_THREADS",
    "OPENBLAS_NUM_THREADS",
    "NUMEXPR_NUM_THREADS",
    "VECLIB_MAXIMUM_THREADS",
):
    os.environ.setdefault(_name, "1")

import numpy as np
import pandas as pd


_HERE = Path(__file__).resolve()
_REPO_ROOT = _HERE.parents[2]
for _path in (_REPO_ROOT / "src", _REPO_ROOT):
    if str(_path) not in sys.path:
        sys.path.insert(0, str(_path))

from camels_process_noise_only.contract import (  # noqa: E402
    evaluate_domain_projection,
    evaluate_event,
    load_design_config,
    lognormal_variance,
    switch_days_and_directions,
    truth_candidate_indices,
    validate_design_config,
)
from hbv_joint_uncertainty.hbv_adapter import advance_state  # noqa: E402
from hbv_joint_uncertainty.imm import InteractingMultipleModel  # noqa: E402
from hbv_joint_uncertainty.preflight import (  # noqa: E402
    ForcingTransition,
    build_transition_matrix,
    project_hbv_state,
)
from hbv_joint_uncertainty.sigma_filter import ModifiedUnscentedFilter  # noqa: E402


PARAMETER_KEYS = (
    "parTT",
    "parCFMAX",
    "parCFR",
    "parCWH",
    "parFC",
    "parBETA",
    "parLP",
    "parK0",
    "parK1",
    "parUZL",
    "parPERC",
    "parK2",
    "lag_time",
)
HYDRO_STATE_NAMES = ("SNOWPACK", "MELTWATER", "SM", "SUZ", "SLZ")
N_HYDRO = 5
N_STATE = 15


@dataclass(frozen=True)
class TruthResult:
    discharge: np.ndarray
    states: np.ndarray
    deterministic_lower_groundwater: np.ndarray
    standard_normals: np.ndarray
    applied_sigmas: np.ndarray
    true_candidate_indices: np.ndarray
    truth_projection_nonzero_day_count: int
    truth_projection_maximum_absolute_difference: float
    truth_projection_maximum_tolerance_ratio: float
    truth_domain_violation_count: int
    truth_state_replacement_count: int


@dataclass(frozen=True)
class NoiseBank:
    estimator: InteractingMultipleModel
    filters: tuple[ModifiedUnscentedFilter, ...]
    transitions: tuple[ForcingTransition, ...]
    sigmas: np.ndarray
    parameters: dict[str, float]


@dataclass(frozen=True)
class FilterRunResult:
    probabilities: np.ndarray
    log_probabilities: np.ndarray
    prior_probabilities: np.ndarray
    candidate_process_variances: np.ndarray
    candidate_predicted_lower_groundwater: np.ndarray
    combined_states: np.ndarray


def sha256_file(path: str | Path) -> str:
    """Return a lowercase SHA-256 digest for one file."""
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _registered_relative_path(repo_root: Path, value: str, label: str) -> Path:
    relative = Path(str(value))
    if relative.is_absolute() or ".." in relative.parts:
        raise ValueError(f"{label} must be a repository-relative path")
    path = repo_root / relative
    if not path.is_file():
        raise FileNotFoundError(f"registered {label} is missing: {path}")
    return path


def verify_registered_input_files(repo_root: str | Path, config: Mapping) -> dict:
    """Verify the registered basin list, coverage table, and every input file."""
    root = Path(repo_root)
    inputs = config.get("inputs", {})
    selection = config.get("design_selection", {})
    truth = config.get("truth", {})
    required_values = {
        "forcing input manifest": inputs.get("forcing_input_manifest"),
        "forcing input manifest SHA-256": inputs.get(
            "forcing_input_manifest_sha256"
        ),
        "forcing coverage table": inputs.get("forcing_coverage_table"),
        "forcing coverage table SHA-256": inputs.get(
            "forcing_coverage_table_sha256"
        ),
        "basin list": selection.get("basin_list"),
        "basin list SHA-256": selection.get("basin_list_sha256"),
    }
    missing = [label for label, value in required_values.items() if not value]
    if missing:
        raise ValueError("missing registered input fields: " + ", ".join(missing))

    manifest_path = _registered_relative_path(
        root, inputs["forcing_input_manifest"], "forcing input manifest"
    )
    coverage_path = _registered_relative_path(
        root, inputs["forcing_coverage_table"], "forcing coverage table"
    )
    basin_list_path = _registered_relative_path(
        root, selection["basin_list"], "basin list"
    )
    expected_hashes = (
        (
            manifest_path,
            inputs["forcing_input_manifest_sha256"],
            "forcing input manifest",
        ),
        (
            coverage_path,
            inputs["forcing_coverage_table_sha256"],
            "forcing coverage table",
        ),
        (basin_list_path, selection["basin_list_sha256"], "basin list"),
    )
    for path, expected, label in expected_hashes:
        observed = sha256_file(path)
        if observed != str(expected):
            raise ValueError(
                f"registered {label} SHA-256 changed: expected {expected}, "
                f"observed {observed}"
            )

    basin_frame = pd.read_csv(
        basin_list_path, dtype={"basin_id": str}, keep_default_na=False
    )
    if "basin_id" not in basin_frame:
        raise ValueError("registered basin list lacks basin_id")
    basin_ids = basin_frame["basin_id"].str.zfill(8).tolist()
    if not basin_ids or len(set(basin_ids)) != len(basin_ids):
        raise ValueError("registered basin list must contain unique basin identifiers")

    coverage = pd.read_csv(
        coverage_path, dtype={"basin_id": str}, keep_default_na=False
    )
    coverage_required = {
        "basin_id",
        "n_days",
        "first_date",
        "last_date",
        "all_required_forcing_finite",
    }
    if not coverage_required.issubset(coverage.columns):
        raise ValueError("registered coverage table lacks required columns")
    coverage["basin_id"] = coverage["basin_id"].str.zfill(8)
    if coverage["basin_id"].duplicated().any() or set(
        coverage["basin_id"]
    ) != set(basin_ids):
        raise ValueError("coverage basin identifiers do not match the basin list")
    coverage_days = pd.to_numeric(coverage["n_days"], errors="coerce")
    finite_flags = coverage["all_required_forcing_finite"].map(
        lambda value: str(value).strip().lower() == "true"
    )
    if not (
        (coverage_days == int(truth["window_days"])).all()
        and (coverage["first_date"] == str(truth["window_start"])).all()
        and (coverage["last_date"] == str(truth["window_end"])).all()
        and finite_flags.all()
    ):
        raise ValueError("registered forcing coverage contract failed")

    manifest = pd.read_csv(
        manifest_path, dtype={"basin_id": str}, keep_default_na=False
    )
    manifest_required = {"category", "basin_id", "relative_path", "bytes", "sha256"}
    if not manifest_required.issubset(manifest.columns):
        raise ValueError("registered input manifest lacks required columns")
    if manifest["relative_path"].duplicated().any():
        raise ValueError("registered input manifest contains duplicate paths")
    manifest["basin_id"] = manifest["basin_id"].str.zfill(8).where(
        manifest["basin_id"] != "", ""
    )
    basin_rows = manifest[manifest["category"].isin(
        ("maurer_forcing", "usgs_streamflow")
    )]
    expected_pairs = {
        (basin_id, category)
        for basin_id in basin_ids
        for category in ("maurer_forcing", "usgs_streamflow")
    }
    observed_pairs = set(zip(basin_rows["basin_id"], basin_rows["category"]))
    if observed_pairs != expected_pairs or len(basin_rows) != len(expected_pairs):
        raise ValueError("input manifest basin files do not match the basin list")
    shared_rows = manifest[manifest["category"].isin(
        ("camels_topography", "forcing_loader_source")
    )]
    if (
        set(shared_rows["category"])
        != {"camels_topography", "forcing_loader_source"}
        or len(shared_rows) != 2
        or (shared_rows["basin_id"] != "").any()
        or len(manifest) != len(expected_pairs) + 2
    ):
        raise ValueError("input manifest shared files or row count changed")

    for row in manifest.itertuples(index=False):
        path = _registered_relative_path(root, row.relative_path, "input file")
        observed_bytes = path.stat().st_size
        if observed_bytes != int(row.bytes):
            raise ValueError(
                f"registered input file size changed for {row.relative_path}: "
                f"expected {row.bytes}, observed {observed_bytes}"
            )
        observed_hash = sha256_file(path)
        if observed_hash != str(row.sha256):
            raise ValueError(
                f"registered input file SHA-256 changed for {row.relative_path}: "
                f"expected {row.sha256}, observed {observed_hash}"
            )
    return {
        "manifest_sha256": sha256_file(manifest_path),
        "manifest_row_count": int(len(manifest)),
        "coverage_sha256": sha256_file(coverage_path),
        "coverage_basin_count": int(len(coverage)),
        "basin_list_sha256": sha256_file(basin_list_path),
        "basin_count": int(len(basin_ids)),
    }


def rising_routed_discharge(state: Sequence[float], lag_time: float) -> float:
    """Route newest-first raw runoff with largest weight on the oldest value."""
    vector = np.asarray(state, dtype=np.float64)
    if vector.shape != (N_STATE,) or not np.all(np.isfinite(vector)):
        raise ValueError("state must be one finite 15-state vector")
    lag = float(lag_time)
    if not np.isfinite(lag) or lag <= 0.0:
        raise ValueError("lag_time must be finite and positive")
    n_lag = max(1, int(np.ceil(min(lag, 10.0))))
    weights = np.arange(1, n_lag + 1, dtype=np.float64)
    weights /= weights.sum()
    return float(weights @ vector[N_HYDRO : N_HYDRO + n_lag])


class RisingRoutedObservation:
    """Fixed-parameter rising-kernel discharge observation."""

    def __init__(self, parameters: Mapping[str, float]):
        self.parameters = {key: float(value) for key, value in parameters.items()}

    def __call__(self, state: np.ndarray) -> np.ndarray:
        physical = project_hbv_state(state, self.parameters)
        return np.array(
            [rising_routed_discharge(physical, self.parameters["lag_time"])],
            dtype=np.float64,
        )


def _finite_equal_length_arrays(**arrays) -> dict[str, np.ndarray]:
    converted = {
        name: np.asarray(values, dtype=np.float64) for name, values in arrays.items()
    }
    lengths = {len(values) for values in converted.values() if values.ndim == 1}
    if any(values.ndim != 1 for values in converted.values()) or len(lengths) != 1:
        raise ValueError("daily arrays must be one-dimensional with equal length")
    if not all(np.all(np.isfinite(values)) for values in converted.values()):
        raise ValueError("daily arrays must contain only finite values")
    return converted


def generate_truth(
    parameters: Mapping[str, float],
    rain,
    pet,
    temperature,
    initial_hydrologic_state,
    standard_normals,
    config: Mapping,
    parameter_bounds: Mapping,
) -> TruthResult:
    """Generate one fixed-parameter truth with only lower-groundwater noise."""
    validate_design_config(config)
    daily = _finite_equal_length_arrays(
        rain=rain,
        pet=pet,
        temperature=temperature,
        standard_normals=standard_normals,
    )
    n_days = len(daily["rain"])
    expected_days = int(config["truth"]["window_days"])
    if n_days != expected_days:
        raise ValueError(f"truth generation requires exactly {expected_days} days")
    hydrologic = np.asarray(initial_hydrologic_state, dtype=np.float64)
    if hydrologic.shape != (N_HYDRO,) or not np.all(np.isfinite(hydrologic)):
        raise ValueError("initial_hydrologic_state must be one finite five-state vector")
    fixed_parameters = {key: float(parameters[key]) for key in PARAMETER_KEYS}
    fixed_parameters["lag_time"] = min(fixed_parameters["lag_time"], 10.0)
    state = np.zeros(N_STATE, dtype=np.float64)
    state[:N_HYDRO] = hydrologic
    projected_initial = project_hbv_state(state, fixed_parameters)
    tolerance_multiplier = float(
        config["truth"]["domain_check"]["tolerance_multiplier"]
    )
    initial_check = evaluate_domain_projection(
        state, projected_initial, tolerance_multiplier
    )
    if initial_check.violated:
        raise ValueError(
            "initial truth state violates the registered physical-domain "
            f"tolerance; maximum difference is "
            f"{initial_check.maximum_absolute_difference}, maximum ratio is "
            f"{initial_check.maximum_tolerance_ratio}"
        )

    true_indices = truth_candidate_indices(config)
    sigmas = np.asarray(
        config["truth"]["candidate_lognormal_sigmas"], dtype=np.float64
    )[true_indices]
    states = np.empty((n_days, N_STATE), dtype=np.float64)
    discharge = np.empty(n_days, dtype=np.float64)
    deterministic_lower = np.empty(n_days, dtype=np.float64)
    maximum_projection_difference = 0.0
    maximum_tolerance_ratio = 0.0
    nonzero_projection_day_count = 0
    domain_violation_count = 0
    state_replacement_count = 0
    for day in range(n_days):
        state = advance_state(
            state,
            daily["rain"][day],
            daily["pet"][day],
            daily["temperature"][day],
            fixed_parameters,
            bounds=parameter_bounds,
        )
        deterministic_lower[day] = state[4]
        sigma = sigmas[day]
        state[4] *= np.exp(
            -0.5 * sigma**2 + sigma * daily["standard_normals"][day]
        )
        if not np.all(np.isfinite(state)) or state[4] <= 0.0:
            raise ValueError("truth process noise produced a non-finite or nonpositive state")
        projected = project_hbv_state(state, fixed_parameters)
        domain_check = evaluate_domain_projection(
            state, projected, tolerance_multiplier
        )
        maximum_projection_difference = max(
            maximum_projection_difference,
            domain_check.maximum_absolute_difference,
        )
        maximum_tolerance_ratio = max(
            maximum_tolerance_ratio,
            domain_check.maximum_tolerance_ratio,
        )
        if domain_check.nonzero_difference_count > 0:
            nonzero_projection_day_count += 1
        if domain_check.violated:
            domain_violation_count += 1
            raise ValueError(
                "truth state violates the registered physical-domain tolerance on "
                f"day {day}; maximum difference is "
                f"{domain_check.maximum_absolute_difference}, maximum ratio is "
                f"{domain_check.maximum_tolerance_ratio}"
            )
        states[day] = state
        discharge[day] = rising_routed_discharge(
            state, fixed_parameters["lag_time"]
        )
    return TruthResult(
        discharge=discharge,
        states=states,
        deterministic_lower_groundwater=deterministic_lower,
        standard_normals=daily["standard_normals"].copy(),
        applied_sigmas=sigmas.copy(),
        true_candidate_indices=true_indices.copy(),
        truth_projection_nonzero_day_count=nonzero_projection_day_count,
        truth_projection_maximum_absolute_difference=maximum_projection_difference,
        truth_projection_maximum_tolerance_ratio=maximum_tolerance_ratio,
        truth_domain_violation_count=domain_violation_count,
        truth_state_replacement_count=state_replacement_count,
    )


def build_noise_bank(
    parameters: Mapping[str, float],
    initial_hydrologic_state,
    sigma_obs: float,
    parameter_bounds: Mapping,
    config: Mapping,
) -> NoiseBank:
    """Build three identical-parameter filters distinguished only by process noise."""
    validate_design_config(config)
    fixed_parameters = {key: float(parameters[key]) for key in PARAMETER_KEYS}
    fixed_parameters["lag_time"] = min(fixed_parameters["lag_time"], 10.0)
    hydrologic = np.asarray(initial_hydrologic_state, dtype=np.float64)
    if hydrologic.shape != (N_HYDRO,) or not np.all(np.isfinite(hydrologic)):
        raise ValueError("initial_hydrologic_state must be one finite five-state vector")
    observation_sigma = float(sigma_obs)
    if not np.isfinite(observation_sigma) or observation_sigma <= 0.0:
        raise ValueError("sigma_obs must be finite and positive")
    sigmas = np.asarray(
        config["truth"]["candidate_lognormal_sigmas"], dtype=np.float64
    )
    filters = []
    transitions = []
    initial_state = np.zeros(N_STATE, dtype=np.float64)
    initial_state[:N_HYDRO] = hydrologic
    initial_state = project_hbv_state(initial_state, fixed_parameters)
    fraction = float(config["filter"]["initial_covariance_fraction"])
    state_scales = np.maximum(np.abs(initial_state), 1.0)
    initial_covariance = np.diag((fraction * state_scales) ** 2)
    observation_covariance = np.array(
        [[observation_sigma**2]], dtype=np.float64
    )
    sigma_points = config["filter"]["sigma_points"]
    for sigma in sigmas:
        transition = ForcingTransition(
            fixed_parameters, parameter_bounds=parameter_bounds
        )
        process_covariance = np.zeros((N_STATE, N_STATE), dtype=np.float64)
        process_covariance[4, 4] = lognormal_variance(initial_state[4], sigma)
        candidate = ModifiedUnscentedFilter(
            state=initial_state.copy(),
            covariance=initial_covariance.copy(),
            transition=transition,
            observation=RisingRoutedObservation(fixed_parameters),
            process_covariance=process_covariance,
            observation_covariance=observation_covariance.copy(),
            state_projector=lambda values, p=fixed_parameters: project_hbv_state(
                values, p
            ),
            alpha=float(sigma_points["alpha"]),
            beta=float(sigma_points["beta"]),
            kappa=float(sigma_points["kappa"]),
        )
        filters.append(candidate)
        transitions.append(transition)
    transition_matrix = build_transition_matrix(
        len(filters), float(config["filter"]["transition_diagonal"])
    )
    estimator = InteractingMultipleModel(
        filters=filters,
        transition_matrix=transition_matrix,
        initial_probabilities=np.asarray(
            config["filter"]["initial_probabilities"], dtype=np.float64
        ),
        parameter_groups=("fixed-center",) * len(filters),
    )
    estimator.interaction_mode = "full"
    return NoiseBank(
        estimator=estimator,
        filters=tuple(filters),
        transitions=tuple(transitions),
        sigmas=sigmas.copy(),
        parameters=dict(fixed_parameters),
    )


def assign_candidate_process_covariances(
    bank: NoiseBank,
    config: Mapping,
    return_predicted: bool = False,
) -> np.ndarray | tuple[np.ndarray, np.ndarray]:
    """Assign candidate-specific moment-matched covariance after interaction."""
    validate_design_config(config)
    if bank.estimator.interaction_mode != "full":
        raise ValueError("process-noise-only bank must use full interaction")
    variances = np.empty(len(bank.filters), dtype=np.float64)
    predicted_lower = np.empty(len(bank.filters), dtype=np.float64)
    for index, (candidate, transition, sigma) in enumerate(
        zip(bank.filters, bank.transitions, bank.sigmas)
    ):
        predicted = transition(candidate.state.copy())
        variance = lognormal_variance(predicted[4], sigma)
        covariance = np.zeros((N_STATE, N_STATE), dtype=np.float64)
        covariance[4, 4] = variance
        candidate.process_covariance = covariance
        variances[index] = variance
        predicted_lower[index] = predicted[4]
    if return_predicted:
        return variances, predicted_lower
    return variances


def run_filter(
    bank: NoiseBank,
    rain,
    pet,
    temperature,
    observations,
    config: Mapping,
) -> FilterRunResult:
    """Run daily full interaction with covariance assignment before filtering."""
    validate_design_config(config)
    daily = _finite_equal_length_arrays(
        rain=rain,
        pet=pet,
        temperature=temperature,
        observations=observations,
    )
    n_days = len(daily["rain"])
    probabilities = np.empty((n_days, len(bank.filters)), dtype=np.float64)
    log_probabilities = np.empty_like(probabilities)
    prior_probabilities = np.empty_like(probabilities)
    process_variances = np.empty_like(probabilities)
    predicted_lower_groundwater = np.empty_like(probabilities)
    combined_states = np.empty((n_days, N_STATE), dtype=np.float64)
    for day in range(n_days):
        for transition in bank.transitions:
            transition.set_forcing(
                daily["rain"][day],
                daily["pet"][day],
                daily["temperature"][day],
            )
        prior = bank.estimator.interact()
        variances, predicted_lower = assign_candidate_process_covariances(
            bank, config, return_predicted=True
        )
        process_variances[day] = variances
        predicted_lower_groundwater[day] = predicted_lower
        result = bank.estimator.update_after_interaction(
            np.array([daily["observations"][day]], dtype=np.float64), prior
        )
        prior_probabilities[day] = result.prior_probabilities
        probabilities[day] = result.posterior_probabilities
        log_probabilities[day] = result.posterior_log_probabilities
        combined_states[day] = result.combined_state
    if not np.all(np.isfinite(probabilities)) or not np.all(
        np.isfinite(log_probabilities)
    ):
        raise ValueError("filter produced non-finite probability evidence")
    if not np.allclose(
        probabilities.sum(axis=1), 1.0, rtol=0.0, atol=1e-12
    ):
        raise ValueError("filter probabilities do not sum to one within 1e-12")
    return FilterRunResult(
        probabilities=probabilities,
        log_probabilities=log_probabilities,
        prior_probabilities=prior_probabilities,
        candidate_process_variances=process_variances,
        candidate_predicted_lower_groundwater=predicted_lower_groundwater,
        combined_states=combined_states,
    )


def prepare_output_root(path: str | Path) -> Path:
    """Create a new output root and refuse any pre-existing target."""
    output = Path(path).resolve()
    if output.exists():
        raise FileExistsError(f"output root already exists: {output}")
    output.mkdir(parents=True, exist_ok=False)
    return output


def _atomic_save_npz(path: Path, **arrays) -> None:
    if path.exists():
        raise FileExistsError(f"task output already exists: {path}")
    temporary = path.with_suffix(".tmp.npz")
    if temporary.exists():
        raise FileExistsError(f"temporary task output already exists: {temporary}")
    np.savez_compressed(temporary, **arrays)
    temporary.replace(path)


def _run_one_task(arguments: tuple) -> dict:
    (
        basin_id,
        seed,
        parameter_row,
        sigma_obs,
        data_root,
        output_root,
        config,
        config_sha256,
    ) = arguments
    started = time.time()
    try:
        from hydroagent.data_loading import load_camels_basin
        from scl_hydro.hbv_lite_numpy import resolve_hbv_bounds

        parameters = {
            key: float(parameter_row[f"p_{key}"]) for key in PARAMETER_KEYS
        }
        parameters["lag_time"] = min(parameters["lag_time"], 10.0)
        initial_hydrologic_state = np.array(
            [float(parameter_row[f"state_{name}"]) for name in HYDRO_STATE_NAMES],
            dtype=np.float64,
        )
        forcing, _, _ = load_camels_basin(
            basin_id,
            data_root=data_root,
            start_date=config["truth"]["window_start"],
            end_date=config["truth"]["window_end"],
            forcing=config["inputs"]["forcing"],
            pet_method=config["inputs"]["pet_method"],
            keep_obs_nan_days=True,
        )
        rain = forcing["prcp"].to_numpy(dtype=np.float64)
        pet_name = "ep" if "ep" in forcing.columns else "pet"
        pet = forcing[pet_name].to_numpy(dtype=np.float64)
        temperature = (
            forcing["tmean"].to_numpy(dtype=np.float64)
            if "tmean" in forcing.columns
            else np.zeros_like(rain)
        )
        expected_days = int(config["truth"]["window_days"])
        if len(rain) != expected_days:
            raise ValueError(
                f"basin {basin_id} has {len(rain)} forcing days; expected {expected_days}"
            )
        if not np.all(np.isfinite(np.concatenate((rain, pet, temperature)))):
            raise ValueError(f"basin {basin_id} forcing contains non-finite values")

        entropy = int(config["seeds"]["entropy"])
        truth_rng = np.random.default_rng(
            np.random.SeedSequence((entropy, int(basin_id), int(seed), 0))
        )
        observation_rng = np.random.default_rng(
            np.random.SeedSequence((entropy, int(basin_id), int(seed), 1))
        )
        standard_normals = truth_rng.normal(size=expected_days)
        bounds = resolve_hbv_bounds("v5")
        truth = generate_truth(
            parameters,
            rain,
            pet,
            temperature,
            initial_hydrologic_state,
            standard_normals,
            config,
            bounds,
        )
        observations = truth.discharge + observation_rng.normal(
            0.0, float(sigma_obs), size=expected_days
        )
        bank = build_noise_bank(
            parameters,
            initial_hydrologic_state,
            float(sigma_obs),
            bounds,
            config,
        )
        filtering = run_filter(
            bank,
            rain,
            pet,
            temperature,
            observations,
            config,
        )
        switch_info = switch_days_and_directions(config)
        event_records = []
        stage_days = int(config["truth"]["stage_days"])
        for switch_day, old_index, new_index in switch_info:
            stage_probabilities = filtering.probabilities[
                switch_day : switch_day + stage_days
            ]
            event = evaluate_event(stage_probabilities, new_index, config)
            event_records.append((old_index, new_index, event))

        task_path = Path(output_root) / "tasks" / f"{basin_id}_s{seed}.npz"
        parameter_vector = np.array(
            [parameters[key] for key in PARAMETER_KEYS], dtype=np.float64
        )
        _atomic_save_npz(
            task_path,
            basin_id=np.array(str(basin_id)),
            seed=np.array(int(seed), dtype=np.int64),
            config_sha256=np.array(config_sha256),
            parameter_names=np.asarray(PARAMETER_KEYS),
            candidate_parameter_vectors=np.tile(parameter_vector, (3, 1)),
            candidate_lognormal_sigmas=bank.sigmas,
            sigma_obs=np.array(float(sigma_obs)),
            probabilities=filtering.probabilities,
            log_probabilities=filtering.log_probabilities,
            prior_probabilities=filtering.prior_probabilities,
            true_candidate_indices=truth.true_candidate_indices,
            truth_discharge=truth.discharge,
            observations=observations,
            truth_states=truth.states,
            deterministic_lower_groundwater=truth.deterministic_lower_groundwater,
            truth_standard_normals=truth.standard_normals,
            truth_applied_sigmas=truth.applied_sigmas,
            candidate_process_variances=filtering.candidate_process_variances,
            candidate_predicted_lower_groundwater=(
                filtering.candidate_predicted_lower_groundwater
            ),
            combined_states=filtering.combined_states,
            rain=rain,
            pet=pet,
            temperature=temperature,
            initial_hydrologic_state=initial_hydrologic_state,
            switch_days=np.asarray([item[0] for item in switch_info], dtype=np.int64),
            switch_old_indices=np.asarray(
                [item[1] for item in switch_info], dtype=np.int64
            ),
            switch_new_indices=np.asarray(
                [item[2] for item in switch_info], dtype=np.int64
            ),
            truth_projection_nonzero_day_count=np.array(
                truth.truth_projection_nonzero_day_count, dtype=np.int64
            ),
            truth_projection_maximum_absolute_difference=np.array(
                truth.truth_projection_maximum_absolute_difference,
                dtype=np.float64,
            ),
            truth_projection_maximum_tolerance_ratio=np.array(
                truth.truth_projection_maximum_tolerance_ratio,
                dtype=np.float64,
            ),
            truth_domain_violation_count=np.array(
                truth.truth_domain_violation_count, dtype=np.int64
            ),
            truth_state_replacement_count=np.array(
                truth.truth_state_replacement_count, dtype=np.int64
            ),
            interaction_mode=np.array("full"),
            observation_variance_multiplier=np.array(1.0),
        )
        record = {
            "basin_id": str(basin_id),
            "seed": int(seed),
            "run_status": "success",
            "error_message": "",
            "truth_projection_nonzero_day_count": (
                truth.truth_projection_nonzero_day_count
            ),
            "truth_projection_maximum_absolute_difference": (
                truth.truth_projection_maximum_absolute_difference
            ),
            "truth_projection_maximum_tolerance_ratio": (
                truth.truth_projection_maximum_tolerance_ratio
            ),
            "truth_domain_violation_count": truth.truth_domain_violation_count,
            "truth_state_replacement_count": truth.truth_state_replacement_count,
            "elapsed_seconds": round(time.time() - started, 3),
        }
        for event_index, (old_index, new_index, event) in enumerate(event_records):
            record[f"event{event_index}_direction"] = f"{old_index}->{new_index}"
            record[f"event{event_index}_pass"] = bool(event["passed"])
            record[f"event{event_index}_mean_true_probability"] = event[
                "mean_true_probability"
            ]
            record[f"event{event_index}_mean_margin"] = event["mean_margin"]
            record[f"event{event_index}_true_argmax_days"] = event[
                "true_daily_argmax_days"
            ]
        return record
    except Exception as error:  # noqa: BLE001
        return {
            "basin_id": str(basin_id),
            "seed": int(seed),
            "run_status": "failed",
            "error_message": f"{type(error).__name__}: {error}",
            "elapsed_seconds": round(time.time() - started, 3),
        }


def run_batch(
    config_path: str | Path,
    basin_list_path: str | Path,
    output_root: str | Path,
    workers: int,
    seeds: Sequence[int],
    limit: int | None = None,
    data_root: str | Path | None = None,
) -> dict:
    """Run one isolated smoke or design batch."""
    config_path = Path(config_path).resolve()
    basin_list_path = Path(basin_list_path).resolve()
    config = load_design_config(config_path)
    requested_seeds = [int(seed) for seed in seeds]
    if requested_seeds != [0, 1]:
        raise ValueError("this exploratory runner permits exactly design seeds [0, 1]")
    if workers <= 0:
        raise ValueError("workers must be positive")
    parameter_path = _REPO_ROOT / config["inputs"]["parameter_table"]
    g1_path = _REPO_ROOT / config["inputs"]["g1_precheck_table"]
    if sha256_file(parameter_path) != config["inputs"]["parameter_table_sha256"]:
        raise ValueError("parameter table SHA-256 changed")
    if sha256_file(g1_path) != config["inputs"]["g1_precheck_table_sha256"]:
        raise ValueError("G1 precheck table SHA-256 changed")
    registered_inputs = verify_registered_input_files(_REPO_ROOT, config)
    config_sha256 = sha256_file(config_path)
    if sha256_file(basin_list_path) != config["design_selection"][
        "basin_list_sha256"
    ]:
        raise ValueError("supplied basin list differs from the registered basin list")
    basin_list = pd.read_csv(basin_list_path, dtype={"basin_id": str})
    basin_list["basin_id"] = basin_list["basin_id"].str.zfill(8)
    if basin_list["basin_id"].duplicated().any():
        raise ValueError("basin list contains duplicates")
    if limit is not None:
        if limit <= 0:
            raise ValueError("limit must be positive")
        basin_list = basin_list.iloc[:limit].copy()
    parameters = pd.read_csv(parameter_path, dtype={"basin_id": str})
    parameters["basin_id"] = parameters["basin_id"].str.zfill(8)
    g1 = pd.read_csv(g1_path, dtype={"basin_id": str})
    g1["basin_id"] = g1["basin_id"].str.zfill(8)
    rows = basin_list[["basin_id"]].merge(
        parameters, on="basin_id", how="left", validate="one_to_one"
    ).merge(
        g1[["basin_id", "sigma_obs"]],
        on="basin_id",
        how="left",
        validate="one_to_one",
    )
    required = [f"p_{key}" for key in PARAMETER_KEYS] + [
        f"state_{name}" for name in HYDRO_STATE_NAMES
    ] + ["sigma_obs"]
    if rows[required].isna().any().any():
        raise ValueError("selected basin inputs contain missing values")
    registered_data_root = (_REPO_ROOT / config["inputs"]["data_root"]).resolve()
    effective_data_root = (
        Path(data_root).resolve() if data_root is not None else registered_data_root
    )
    if effective_data_root != registered_data_root:
        raise ValueError("data root override differs from the registered data root")
    output = prepare_output_root(output_root)
    (output / "tasks").mkdir(exist_ok=False)
    work = []
    for row in rows.to_dict("records"):
        for seed in requested_seeds:
            work.append(
                (
                    row["basin_id"],
                    seed,
                    row,
                    float(row["sigma_obs"]),
                    str(effective_data_root),
                    str(output),
                    config,
                    config_sha256,
                )
            )
    records = []
    started = time.time()
    with ProcessPoolExecutor(max_workers=workers) as pool:
        futures = {pool.submit(_run_one_task, item): (item[0], item[1]) for item in work}
        for completed, future in enumerate(as_completed(futures), start=1):
            basin_id, seed = futures[future]
            try:
                record = future.result()
            except Exception as error:  # noqa: BLE001
                record = {
                    "basin_id": basin_id,
                    "seed": seed,
                    "run_status": "failed",
                    "error_message": f"worker exception: {type(error).__name__}: {error}",
                }
            records.append(record)
            if completed % 20 == 0 or completed == len(work):
                elapsed_minutes = (time.time() - started) / 60.0
                print(
                    f"[{time.strftime('%H:%M:%S')}] {completed}/{len(work)} "
                    f"tasks; wall={elapsed_minutes:.1f} min",
                    flush=True,
                )
    frame = pd.DataFrame(records).sort_values(["basin_id", "seed"])
    frame.to_csv(output / "runner_records.csv", index=False)
    success_count = int((frame["run_status"] == "success").sum())
    failure_count = int((frame["run_status"] == "failed").sum())
    summary = {
        "experiment_id": config["experiment_id"],
        "configuration_revision": config["configuration_revision"],
        "configuration_status": config["configuration_status"],
        "config_path": str(config_path),
        "config_sha256": config_sha256,
        "basin_list_path": str(basin_list_path),
        "basin_list_sha256": sha256_file(basin_list_path),
        "parameter_table_sha256": sha256_file(parameter_path),
        "g1_precheck_table_sha256": sha256_file(g1_path),
        "forcing_input_manifest_sha256": registered_inputs["manifest_sha256"],
        "forcing_input_manifest_rows": registered_inputs["manifest_row_count"],
        "forcing_coverage_table_sha256": registered_inputs["coverage_sha256"],
        "forcing_coverage_basin_count": registered_inputs[
            "coverage_basin_count"
        ],
        "data_root": str(effective_data_root),
        "n_basins": int(len(rows)),
        "seeds": requested_seeds,
        "n_tasks": int(len(work)),
        "n_success": success_count,
        "n_failed": failure_count,
        "wall_clock_minutes": round((time.time() - started) / 60.0, 3),
    }
    with (output / "runner_summary.json").open("x", encoding="utf-8") as handle:
        json.dump(summary, handle, indent=2, sort_keys=True)
        handle.write("\n")
    if failure_count:
        raise RuntimeError(f"{failure_count} task(s) failed; inspect runner_records.csv")
    return summary


def _parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--config",
        default="src/camels_process_noise_only/configs/camels_process_noise_only_01a_design.json",
    )
    parser.add_argument("--basin-list", required=True)
    parser.add_argument("--output-root", required=True)
    parser.add_argument("--workers", type=int, default=2)
    parser.add_argument("--seeds", type=int, nargs="+", default=[0, 1])
    parser.add_argument("--limit", type=int, default=None)
    parser.add_argument("--data-root", default=None)
    return parser.parse_args(argv)


def main(argv=None) -> int:
    arguments = _parse_args(argv)
    try:
        summary = run_batch(
            config_path=arguments.config,
            basin_list_path=arguments.basin_list,
            output_root=arguments.output_root,
            workers=arguments.workers,
            seeds=arguments.seeds,
            limit=arguments.limit,
            data_root=arguments.data_root,
        )
    except Exception as error:  # noqa: BLE001
        print(f"STOP: {type(error).__name__}: {error}", file=sys.stderr)
        return 1
    print(json.dumps(summary, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

"""Evaluation-only capture and serialization of complete HBV-IMM state trajectories."""

from __future__ import annotations

from dataclasses import dataclass
from hashlib import sha256
import json
from pathlib import Path
import re
from typing import Mapping

import numpy as np
import torch

from .filter import DifferentiableInteractingMultipleModel
from .supervised_probability import ObservableAssimilationBatch


STATE_NAMES = (
    "SNOWPACK",
    "MELTWATER",
    "SM",
    "SUZ",
    "SLZ",
    *(f"qraw_t_minus_{offset}" for offset in range(10)),
)
STATE_UNITS = ("mm",) * 5 + ("mm/day",) * 10
MODE_NAMES = (
    "slow_recession",
    "calibrated_recession",
    "fast_recession",
)
REQUIRED_METHOD_NAMES = (
    "static",
    "history_seed_1710101",
    "history_seed_1710102",
    "history_seed_1710103",
)
REQUIRED_PROVENANCE_FILES = (
    "reserve_arrays_sha256",
    "generation_arrays_sha256",
    "config_snapshot_sha256",
    "source_snapshot_sha256",
    "environment_sha256",
    "state_trajectory_source_sha256",
)

_STATE_COUNT = len(STATE_NAMES)
_MODE_COUNT = len(MODE_NAMES)
_METHOD_PATTERN = re.compile(r"^[a-z0-9][a-z0-9_]*$")
_METHOD_FIELDS = (
    "global_posterior_states",
    "global_posterior_covariances",
    "prior_mode_probabilities",
    "posterior_mode_probabilities",
    "candidate_posterior_states",
    "candidate_posterior_covariances",
)


@dataclass(frozen=True)
class FilterStateTrajectory:
    """Every posterior moment needed to audit one full filter rollout."""

    global_posterior_states: torch.Tensor
    global_posterior_covariances: torch.Tensor
    prior_mode_probabilities: torch.Tensor
    posterior_mode_probabilities: torch.Tensor
    candidate_posterior_states: torch.Tensor
    candidate_posterior_covariances: torch.Tensor
    observable_input_sha256: str
    transition_matrices_sha256: str
    candidate_parameters_sha256: str


@dataclass(frozen=True)
class StateTrajectoryLayerContract:
    """Frozen layer identity for a state-trajectory artifact."""

    layer: str
    replay_batch_count: int
    replay_days: int
    block_ids: tuple[str, ...]
    schedule_ordinals: tuple[int, ...]
    selected_display_block_index: int | None


def _validate_observable(observable: ObservableAssimilationBatch) -> tuple[int, int]:
    forcing = observable.forcing
    if forcing.ndim != 3 or forcing.shape[-1] != 3:
        raise ValueError("observable forcing must have shape [block, day, 3]")
    blocks, days, _ = forcing.shape
    if blocks <= 0 or days <= 0:
        raise ValueError("observable must contain at least one block and one day")
    expected = {
        "observations": (blocks, days),
        "initial_states": (blocks, _STATE_COUNT),
        "initial_covariances": (blocks, _STATE_COUNT, _STATE_COUNT),
    }
    for name, shape in expected.items():
        values = getattr(observable, name)
        if values.shape != shape:
            raise ValueError(f"observable {name} must have shape {shape}")
        if values.device != forcing.device or values.dtype != forcing.dtype:
            raise ValueError(
                f"observable {name} must share forcing dtype and device"
            )
        if not torch.isfinite(values).all():
            raise ValueError(f"observable {name} must be finite")
    if observable.assimilation_days != days:
        raise ValueError("observable assimilation_days must match its day axis")
    if not torch.is_floating_point(forcing) or not torch.isfinite(forcing).all():
        raise ValueError("observable forcing must be finite floating point")
    if not torch.allclose(
        observable.initial_covariances,
        observable.initial_covariances.transpose(-1, -2),
        rtol=0.0,
        atol=1e-12,
    ):
        raise ValueError("observable initial covariances must be symmetric")
    return blocks, days


def _validate_candidate_parameter_mapping(
    candidate_parameters: Mapping[str, Mapping[str, float]],
) -> None:
    if tuple(candidate_parameters) != MODE_NAMES:
        raise ValueError(
            "candidate parameter order must be slow, calibrated, then fast recession"
        )
    parameter_names = tuple(candidate_parameters[MODE_NAMES[0]])
    if not parameter_names:
        raise ValueError("candidate parameter mappings must be nonempty")
    for mode in MODE_NAMES:
        values = candidate_parameters[mode]
        if tuple(values) != parameter_names:
            raise ValueError(
                "candidate parameter mappings must use one fixed key order"
            )
        if not np.all(np.isfinite(tuple(float(value) for value in values.values()))):
            raise ValueError("candidate parameters must be finite")


def _validate_estimator_contract(
    estimator: DifferentiableInteractingMultipleModel,
    candidate_parameters: Mapping[str, Mapping[str, float]],
) -> None:
    _validate_candidate_parameter_mapping(candidate_parameters)
    if len(estimator.models) != _MODE_COUNT:
        raise ValueError(
            "state trajectory replay requires exactly three candidate models"
        )
    for name, model in zip(MODE_NAMES, estimator.models):
        expected = {
            key: float(value)
            for key, value in candidate_parameters[name].items()
        }
        actual = {key: float(value) for key, value in model.parameters.items()}
        if actual != expected:
            raise ValueError(
                f"estimator candidate model {name} does not match its "
                "declared parameters"
            )


def _candidate_parameters_sha256(
    candidate_parameters: Mapping[str, Mapping[str, float]],
) -> str:
    payload = {
        "mode_order": list(MODE_NAMES),
        "parameters": {
            mode: {
                name: float(value)
                for name, value in sorted(candidate_parameters[mode].items())
            }
            for mode in MODE_NAMES
        },
    }
    return sha256(
        json.dumps(
            payload,
            sort_keys=True,
            separators=(",", ":"),
            allow_nan=False,
        ).encode("utf-8")
    ).hexdigest()


def _observable_input_sha256(observable: ObservableAssimilationBatch) -> str:
    fields = {
        "observable_forcing": observable.forcing,
        "observations": observable.observations,
        "initial_states": observable.initial_states,
        "initial_covariances": observable.initial_covariances,
    }
    hashes = {
        name: logical_array_sha256(
            name,
            _canonical_float64(values, name.replace("_", " ")),
        )
        for name, values in fields.items()
    }
    return sha256(
        json.dumps(
            hashes,
            sort_keys=True,
            separators=(",", ":"),
        ).encode("utf-8")
    ).hexdigest()


def _validate_transitions(
    observable: ObservableAssimilationBatch,
    transition_matrices: torch.Tensor,
    *,
    blocks: int,
    days: int,
) -> None:
    if transition_matrices.shape != (blocks, days, _MODE_COUNT, _MODE_COUNT):
        raise ValueError(
            "transition matrices must have shape [block, day, 3, 3]"
        )
    if (
        transition_matrices.device != observable.forcing.device
        or transition_matrices.dtype != observable.forcing.dtype
        or not torch.is_floating_point(transition_matrices)
    ):
        raise ValueError(
            "transition matrices must share observable floating dtype and device"
        )
    if not torch.isfinite(transition_matrices).all():
        raise ValueError("transition matrices must be finite")
    if torch.any(transition_matrices < 0.0) or torch.any(transition_matrices > 1.0):
        raise ValueError("transition probabilities must lie in [0, 1]")
    row_error = torch.max(
        torch.abs(transition_matrices.sum(dim=-1) - 1.0)
    )
    if float(row_error) > 1e-12:
        raise ValueError("transition matrix rows must sum to one within 1e-12")


def _stack(values: list[torch.Tensor]) -> torch.Tensor:
    return torch.stack(values, dim=1).detach()


def rollout_filter_state_trajectory(
    observable: ObservableAssimilationBatch,
    transition_matrices: torch.Tensor,
    estimator: DifferentiableInteractingMultipleModel,
    *,
    candidate_parameters: Mapping[str, Mapping[str, float]],
) -> FilterStateTrajectory:
    """Replay fixed daily transitions and retain all posterior state moments.

    This function performs evaluation only.  It never constructs an optimizer,
    updates a transition network, or selects a checkpoint.
    """

    blocks, days = _validate_observable(observable)
    _validate_estimator_contract(estimator, candidate_parameters)
    _validate_transitions(
        observable,
        transition_matrices,
        blocks=blocks,
        days=days,
    )
    states = (
        observable.initial_states.unsqueeze(1)
        .expand(-1, _MODE_COUNT, -1)
        .clone()
    )
    covariances = (
        observable.initial_covariances.unsqueeze(1)
        .expand(-1, _MODE_COUNT, -1, -1)
        .clone()
    )
    probabilities = torch.full(
        (blocks, _MODE_COUNT),
        1.0 / _MODE_COUNT,
        dtype=observable.forcing.dtype,
        device=observable.forcing.device,
    )
    global_states: list[torch.Tensor] = []
    global_covariances: list[torch.Tensor] = []
    prior_probabilities: list[torch.Tensor] = []
    posterior_probabilities: list[torch.Tensor] = []
    candidate_states: list[torch.Tensor] = []
    candidate_covariances: list[torch.Tensor] = []

    estimator.eval()
    with torch.no_grad():
        for day in range(days):
            update = estimator.step(
                states=states,
                covariances=covariances,
                probabilities=probabilities,
                transition_matrix=transition_matrices[:, day],
                forcing=observable.forcing[:, day],
                observation=observable.observations[:, day],
            )
            global_states.append(update.global_posterior_states)
            global_covariances.append(update.global_posterior_covariances)
            prior_probabilities.append(update.prior_probabilities)
            posterior_probabilities.append(update.posterior_probabilities)
            candidate_states.append(update.posterior_states)
            candidate_covariances.append(update.posterior_covariances)
            states = update.posterior_states
            covariances = update.posterior_covariances
            probabilities = update.posterior_probabilities

    result = FilterStateTrajectory(
        global_posterior_states=_stack(global_states),
        global_posterior_covariances=_stack(global_covariances),
        prior_mode_probabilities=_stack(prior_probabilities),
        posterior_mode_probabilities=_stack(posterior_probabilities),
        candidate_posterior_states=_stack(candidate_states),
        candidate_posterior_covariances=_stack(candidate_covariances),
        observable_input_sha256=_observable_input_sha256(observable),
        transition_matrices_sha256=logical_array_sha256(
            "transition_matrices",
            _canonical_float64(
                transition_matrices,
                "transition matrices",
            ),
        ),
        candidate_parameters_sha256=_candidate_parameters_sha256(
            candidate_parameters
        ),
    )
    for field in _METHOD_FIELDS:
        if not torch.isfinite(getattr(result, field)).all():
            raise ValueError(f"captured {field} must be finite")
    if not torch.allclose(
        result.global_posterior_covariances,
        result.global_posterior_covariances.transpose(-1, -2),
        rtol=0.0,
        atol=1e-12,
    ):
        raise ValueError("captured global posterior covariances must be symmetric")
    for name in ("prior_mode_probabilities", "posterior_mode_probabilities"):
        values = getattr(result, name)
        if torch.any(values < 0.0) or torch.any(values > 1.0):
            raise ValueError(f"captured {name} must lie on the probability simplex")
        if float(torch.max(torch.abs(values.sum(dim=-1) - 1.0))) > 1e-12:
            raise ValueError(f"captured {name} must sum to one")
    return result


def _canonical_float64(values: torch.Tensor | np.ndarray, label: str) -> np.ndarray:
    if isinstance(values, torch.Tensor):
        values = values.detach().cpu().numpy()
    array = np.asarray(values)
    if array.dtype.kind not in "fiu" or not np.all(np.isfinite(array)):
        raise ValueError(f"{label} must contain finite real numbers")
    return np.ascontiguousarray(array, dtype=np.dtype("<f8"))


def _validate_method_shape(
    method: str,
    trajectory: FilterStateTrajectory,
    *,
    blocks: int,
    days: int,
) -> None:
    expected = {
        "global_posterior_states": (blocks, days, _STATE_COUNT),
        "global_posterior_covariances": (
            blocks,
            days,
            _STATE_COUNT,
            _STATE_COUNT,
        ),
        "prior_mode_probabilities": (blocks, days, _MODE_COUNT),
        "posterior_mode_probabilities": (blocks, days, _MODE_COUNT),
        "candidate_posterior_states": (
            blocks,
            days,
            _MODE_COUNT,
            _STATE_COUNT,
        ),
        "candidate_posterior_covariances": (
            blocks,
            days,
            _MODE_COUNT,
            _STATE_COUNT,
            _STATE_COUNT,
        ),
    }
    for field, shape in expected.items():
        if getattr(trajectory, field).shape != shape:
            raise ValueError(f"method {method} field {field} must have shape {shape}")


def _validate_probability_array(values: np.ndarray, label: str) -> None:
    if np.any(values < 0.0) or np.any(values > 1.0):
        raise ValueError(f"{label} must lie on the probability simplex")
    if not np.allclose(values.sum(axis=-1), 1.0, rtol=0.0, atol=1e-12):
        raise ValueError(f"{label} must sum to one")


def _validate_symmetric_array(values: np.ndarray, label: str) -> None:
    if not np.allclose(values, values.swapaxes(-1, -2), rtol=0.0, atol=1e-12):
        raise ValueError(f"{label} must be symmetric")


def _validate_numpy_method_contract(
    method: str,
    fields: Mapping[str, np.ndarray],
) -> None:
    prior = fields["prior_mode_probabilities"]
    posterior = fields["posterior_mode_probabilities"]
    global_states = fields["global_posterior_states"]
    global_covariances = fields["global_posterior_covariances"]
    candidate_states = fields["candidate_posterior_states"]
    candidate_covariances = fields["candidate_posterior_covariances"]
    _validate_probability_array(prior, f"method {method} prior probabilities")
    _validate_probability_array(
        posterior,
        f"method {method} posterior probabilities",
    )
    _validate_symmetric_array(
        global_covariances,
        f"method {method} global covariances",
    )
    _validate_symmetric_array(
        candidate_covariances,
        f"method {method} candidate covariances",
    )
    expected_global = np.sum(posterior[..., None] * candidate_states, axis=2)
    if not np.allclose(global_states, expected_global, rtol=0.0, atol=1e-12):
        raise ValueError(f"method {method} global posterior state identity failed")
    deviations = candidate_states - global_states[:, :, None, :]
    expected_covariance = np.einsum(
        "btm,btmij->btij",
        posterior,
        candidate_covariances,
    ) + np.einsum(
        "btm,btmi,btmj->btij",
        posterior,
        deviations,
        deviations,
    )
    if not np.allclose(
        global_covariances,
        expected_covariance,
        rtol=0.0,
        atol=1e-12,
    ):
        raise ValueError(f"method {method} global posterior covariance identity failed")


def state_trajectory_arrays(
    truth_post_transition_states: torch.Tensor | np.ndarray,
    observable: ObservableAssimilationBatch,
    transition_matrices_by_method: Mapping[str, torch.Tensor | np.ndarray],
    method_trajectories: Mapping[str, FilterStateTrajectory],
    *,
    candidate_parameters: Mapping[str, Mapping[str, float]],
) -> dict[str, np.ndarray]:
    """Build the fixed, complete numerical mapping for a future result bundle."""

    blocks, days = _validate_observable(observable)
    truth = _canonical_float64(
        truth_post_transition_states,
        "truth post-transition states",
    )
    if truth.shape != (blocks, days, _STATE_COUNT):
        raise ValueError(
            "truth post-transition states must have shape [block, day, 15]"
        )
    if tuple(sorted(method_trajectories)) != tuple(sorted(REQUIRED_METHOD_NAMES)):
        raise ValueError("method trajectories must contain the fixed four-method set")
    if tuple(sorted(transition_matrices_by_method)) != tuple(
        sorted(REQUIRED_METHOD_NAMES)
    ):
        raise ValueError("transition matrices must contain the fixed four-method set")
    _validate_candidate_parameter_mapping(candidate_parameters)
    observable_hash = _observable_input_sha256(observable)
    candidate_hash = _candidate_parameters_sha256(candidate_parameters)
    arrays: dict[str, np.ndarray] = {
        "day_indices": np.arange(days, dtype=np.dtype("<f8")),
        "truth_post_transition_states": truth,
        "observable_forcing": _canonical_float64(
            observable.forcing,
            "observable forcing",
        ),
        "observations": _canonical_float64(
            observable.observations,
            "observations",
        ),
        "initial_states": _canonical_float64(
            observable.initial_states,
            "initial states",
        ),
        "initial_covariances": _canonical_float64(
            observable.initial_covariances,
            "initial covariances",
        ),
    }
    for method in REQUIRED_METHOD_NAMES:
        if not _METHOD_PATTERN.fullmatch(method):
            raise ValueError(f"method name is not a stable identifier: {method!r}")
        trajectory = method_trajectories[method]
        if trajectory.observable_input_sha256 != observable_hash:
            raise ValueError(
                f"method {method} trajectory is not bound to the supplied "
                "observable input"
            )
        if trajectory.candidate_parameters_sha256 != candidate_hash:
            raise ValueError(
                f"method {method} trajectory is not bound to the supplied candidates"
            )
        _validate_method_shape(
            method,
            trajectory,
            blocks=blocks,
            days=days,
        )
        transition_matrices = _canonical_float64(
            transition_matrices_by_method[method],
            f"{method} transition matrices",
        )
        if transition_matrices.shape != (blocks, days, _MODE_COUNT, _MODE_COUNT):
            raise ValueError(
                f"method {method} transition matrices must have shape "
                f"{(blocks, days, _MODE_COUNT, _MODE_COUNT)}"
            )
        _validate_probability_array(
            transition_matrices,
            f"method {method} transition rows",
        )
        transition_hash = logical_array_sha256(
            "transition_matrices",
            transition_matrices,
        )
        if trajectory.transition_matrices_sha256 != transition_hash:
            raise ValueError(
                f"method {method} trajectory is not bound to its supplied transitions"
            )
        arrays[f"{method}__transition_matrices"] = transition_matrices
        canonical_fields: dict[str, np.ndarray] = {}
        for field in _METHOD_FIELDS:
            canonical_fields[field] = _canonical_float64(
                getattr(trajectory, field),
                f"{method} {field}",
            )
            arrays[f"{method}__{field}"] = canonical_fields[field]
        _validate_numpy_method_contract(method, canonical_fields)
    return arrays


def logical_array_sha256(name: str, values: np.ndarray) -> str:
    """Hash an array's semantic name, dtype, shape, and C-order value bytes."""

    if not name or not isinstance(name, str):
        raise ValueError("array name must be a non-empty string")
    array = np.asarray(values)
    if array.dtype.kind == "O":
        raise ValueError("object arrays cannot be logically hashed")
    if array.dtype.byteorder == ">":
        array = array.byteswap().view(array.dtype.newbyteorder("<"))
    elif array.dtype.byteorder == "=":
        array = array.astype(array.dtype.newbyteorder("<"), copy=False)
    array = np.ascontiguousarray(array)
    header = json.dumps(
        {"name": name, "dtype": array.dtype.str, "shape": list(array.shape)},
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    digest = sha256()
    digest.update(header)
    digest.update(b"\0")
    digest.update(array.tobytes(order="C"))
    return digest.hexdigest()


def _dimensions_for(name: str) -> list[str]:
    if name == "day_indices":
        return ["day"]
    if name == "observable_forcing":
        return ["block", "day", "forcing_feature"]
    if name == "observations":
        return ["block", "day"]
    if name == "initial_states":
        return ["block", "state"]
    if name == "initial_covariances":
        return ["block", "state_i", "state_j"]
    if name == "truth_post_transition_states" or name.endswith(
        "__global_posterior_states"
    ):
        return ["block", "day", "state"]
    if name.endswith("__transition_matrices"):
        return ["block", "day", "source_mode", "destination_mode"]
    if name.endswith("__global_posterior_covariances"):
        return ["block", "day", "state_i", "state_j"]
    if name.endswith("__prior_mode_probabilities") or name.endswith(
        "__posterior_mode_probabilities"
    ):
        return ["block", "day", "mode"]
    if name.endswith("__candidate_posterior_states"):
        return ["block", "day", "mode", "state"]
    if name.endswith("__candidate_posterior_covariances"):
        return ["block", "day", "mode", "state_i", "state_j"]
    raise ValueError(f"unrecognized state trajectory array: {name}")


def _units_for(name: str) -> str | list[str]:
    if name == "day_indices":
        return "day_index"
    if name == "observable_forcing":
        return ["mm/day", "mm/day", "degree_Celsius"]
    if name == "observations":
        return "mm/day"
    if name.endswith("probabilities"):
        return "dimensionless"
    if name.endswith("transition_matrices"):
        return "dimensionless"
    if name.endswith("covariances"):
        return "outer_product_of_state_units"
    return list(STATE_UNITS)


def _expected_array_shapes(blocks: int, days: int) -> dict[str, tuple[int, ...]]:
    expected: dict[str, tuple[int, ...]] = {
        "day_indices": (days,),
        "truth_post_transition_states": (blocks, days, _STATE_COUNT),
        "observable_forcing": (blocks, days, 3),
        "observations": (blocks, days),
        "initial_states": (blocks, _STATE_COUNT),
        "initial_covariances": (blocks, _STATE_COUNT, _STATE_COUNT),
    }
    method_shapes = {
        "transition_matrices": (blocks, days, _MODE_COUNT, _MODE_COUNT),
        "global_posterior_states": (blocks, days, _STATE_COUNT),
        "global_posterior_covariances": (
            blocks,
            days,
            _STATE_COUNT,
            _STATE_COUNT,
        ),
        "prior_mode_probabilities": (blocks, days, _MODE_COUNT),
        "posterior_mode_probabilities": (blocks, days, _MODE_COUNT),
        "candidate_posterior_states": (
            blocks,
            days,
            _MODE_COUNT,
            _STATE_COUNT,
        ),
        "candidate_posterior_covariances": (
            blocks,
            days,
            _MODE_COUNT,
            _STATE_COUNT,
            _STATE_COUNT,
        ),
    }
    for method in REQUIRED_METHOD_NAMES:
        for field, shape in method_shapes.items():
            expected[f"{method}__{field}"] = shape
    return expected


def _sha256_file(path: Path) -> str:
    digest = sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _validated_file_mapping(
    values: Mapping[str, str | Path],
    expected_keys: tuple[str, ...],
    label: str,
) -> dict[str, dict[str, str]]:
    if set(values) != set(expected_keys):
        raise ValueError(f"{label} must contain exactly {list(expected_keys)}")
    result: dict[str, dict[str, str]] = {}
    for key in expected_keys:
        path = Path(values[key]).resolve()
        if not path.is_file():
            raise ValueError(f"{label} file does not exist: {path}")
        result[key] = {
            "path": path.as_posix(),
            "sha256": _sha256_file(path),
        }
    return result


def _validate_layer_contract(
    contract: StateTrajectoryLayerContract,
    *,
    blocks: int,
    days: int,
) -> None:
    if contract.replay_batch_count != blocks or contract.replay_days != days:
        raise ValueError("layer replay shape does not match the saved arrays")
    if len(contract.block_ids) != blocks or len(set(contract.block_ids)) != blocks:
        raise ValueError("layer block identifiers must be complete and unique")
    if any(not value for value in contract.block_ids):
        raise ValueError("layer block identifiers must be nonempty")
    if (
        len(contract.schedule_ordinals) != blocks
        or len(set(contract.schedule_ordinals)) != blocks
        or any(value <= 0 for value in contract.schedule_ordinals)
    ):
        raise ValueError(
            "layer schedule ordinals must be complete, positive, and unique"
        )
    if contract.layer == "natural_core":
        if blocks != 120 or days != 300:
            raise ValueError("natural-core publication requires exactly 120 by 300")
        if contract.schedule_ordinals != tuple(range(1, 121)):
            raise ValueError("natural-core schedule ordinals must be 1 through 120")
        if contract.selected_display_block_index != 0:
            raise ValueError("natural-core display block must be the fixed first block")
        return
    if contract.layer == "rare_duration_coverage":
        if days != 300:
            raise ValueError("rare-duration publication requires exactly 300 days")
        if contract.schedule_ordinals != tuple(sorted(contract.schedule_ordinals)):
            raise ValueError(
                "rare-duration schedule ordinals must stay in frozen order"
            )
        if contract.selected_display_block_index is not None:
            raise ValueError("rare-duration coverage has no selected display block")
        return
    if contract.layer == "test_fixture":
        if contract.selected_display_block_index not in (None, 0):
            raise ValueError("test fixture display index must be zero or absent")
        return
    raise ValueError(f"unsupported state trajectory layer: {contract.layer}")


def state_trajectory_manifest(
    arrays: Mapping[str, np.ndarray],
    *,
    layer_contract: StateTrajectoryLayerContract,
    checkpoint_files_by_method: Mapping[str, str | Path],
    provenance_files: Mapping[str, str | Path],
) -> dict[str, object]:
    """Describe and hash the exact fixed-schema state trajectory mapping."""

    if "truth_post_transition_states" not in arrays:
        raise ValueError("truth post-transition states are missing")
    truth = np.asarray(arrays["truth_post_transition_states"])
    if truth.ndim != 3 or truth.shape[-1] != _STATE_COUNT:
        raise ValueError("truth state trajectory shape is invalid")
    blocks, days, _ = truth.shape
    expected_shapes = _expected_array_shapes(blocks, days)
    if set(arrays) != set(expected_shapes):
        missing = sorted(set(expected_shapes) - set(arrays))
        extra = sorted(set(arrays) - set(expected_shapes))
        raise ValueError(
            f"state trajectory array schema mismatch; missing={missing}, extra={extra}"
        )
    _validate_layer_contract(
        layer_contract,
        blocks=blocks,
        days=days,
    )
    checkpoint_files = _validated_file_mapping(
        checkpoint_files_by_method,
        REQUIRED_METHOD_NAMES,
        "checkpoint files",
    )
    provenance_file_records = _validated_file_mapping(
        provenance_files,
        REQUIRED_PROVENANCE_FILES,
        "provenance files",
    )
    array_manifest: dict[str, object] = {}
    for name in sorted(arrays):
        values = np.asarray(arrays[name])
        if values.dtype.str != "<f8" or not values.flags.c_contiguous:
            raise ValueError(
                f"state trajectory array {name} is not canonical <f8 C-order"
            )
        if not np.all(np.isfinite(values)):
            raise ValueError(
                f"state trajectory array {name} contains non-finite values"
            )
        dimensions = _dimensions_for(name)
        if values.shape != expected_shapes[name]:
            raise ValueError(
                f"state trajectory array {name} must have shape {expected_shapes[name]}"
            )
        array_manifest[name] = {
            "shape": list(values.shape),
            "dtype": values.dtype.str,
            "dimensions": dimensions,
            "units": _units_for(name),
            "logical_sha256": logical_array_sha256(name, values),
        }
    if not np.array_equal(
        np.asarray(arrays["day_indices"]),
        np.arange(days, dtype=np.dtype("<f8")),
    ):
        raise ValueError("day indices must be the complete zero-based sequence")
    _validate_symmetric_array(
        np.asarray(arrays["initial_covariances"]),
        "initial covariances",
    )
    for method in REQUIRED_METHOD_NAMES:
        _validate_probability_array(
            np.asarray(arrays[f"{method}__transition_matrices"]),
            f"method {method} transition rows",
        )
        _validate_numpy_method_contract(
            method,
            {
                field: np.asarray(arrays[f"{method}__{field}"])
                for field in _METHOD_FIELDS
            },
        )
    return {
        "schema_version": 2,
        "state_names": list(STATE_NAMES),
        "state_units": list(STATE_UNITS),
        "forcing_names": ["rain", "potential_evaporation", "temperature"],
        "forcing_units": ["mm/day", "mm/day", "degree_Celsius"],
        "mode_names": list(MODE_NAMES),
        "method_names": list(REQUIRED_METHOD_NAMES),
        "publication_ready": False,
        "evidence_role": "capture_bundle_requires_independent_verification",
        "publication_blocker": (
            "a newly authorized runner and independent verifier must bind canonical "
            "result paths, block identity, truth, checkpoints, and replayed transitions"
        ),
        "layer_contract": {
            "layer": layer_contract.layer,
            "replay_batch_count": layer_contract.replay_batch_count,
            "replay_days": layer_contract.replay_days,
            "block_ids": list(layer_contract.block_ids),
            "schedule_ordinals": list(layer_contract.schedule_ordinals),
            "selected_display_block_index": (
                layer_contract.selected_display_block_index
            ),
        },
        "checkpoint_files_by_method": checkpoint_files,
        "provenance_files": provenance_file_records,
        "time_semantics": {
            "initial_state_day": -1,
            "truth_day_t": "after physical transition into day t",
            "posterior_day_t": "after assimilating the observation from day t",
            "transition_day_t": (
                "emitted before assimilating the observation from day t"
            ),
        },
        "logical_hash_contract": "sha256(name,dtype,shape,C-order-bytes)",
        "arrays": array_manifest,
    }

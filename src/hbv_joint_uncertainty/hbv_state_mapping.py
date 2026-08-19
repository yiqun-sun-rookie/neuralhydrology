"""Conservative HBV-lite state conversion for soil-capacity hypotheses."""

from __future__ import annotations

from collections.abc import Mapping

import numpy as np

from .hbv_adapter import STATE_NAMES
from .sigma_filter import ScaledSigmaPoints, unscented_transform


SOIL_INDEX = 2
UPPER_GROUNDWATER_INDEX = 3


def _finite_state(values, label: str) -> np.ndarray:
    state = np.asarray(values, dtype=np.float64)
    expected = (len(STATE_NAMES),)
    if state.shape != expected:
        raise ValueError(f"{label} must have shape {expected}, got {state.shape}")
    if not np.all(np.isfinite(state)):
        raise ValueError(f"{label} must contain only finite values")
    return state


def _finite_covariance(values, label: str) -> np.ndarray:
    covariance = np.asarray(values, dtype=np.float64)
    size = len(STATE_NAMES)
    expected = (size, size)
    if covariance.shape != expected:
        raise ValueError(f"{label} must have shape {expected}, got {covariance.shape}")
    if not np.all(np.isfinite(covariance)):
        raise ValueError(f"{label} must contain only finite values")
    if not np.allclose(covariance, covariance.T, rtol=0.0, atol=1e-12):
        raise ValueError(f"{label} must be symmetric")
    symmetric = 0.5 * (covariance + covariance.T)
    eigenvalues = np.linalg.eigvalsh(symmetric)
    scale = max(float(np.max(np.abs(eigenvalues))), 1.0)
    tolerance = max(
        1e-12,
        np.finfo(np.float64).eps * size * scale * 100.0,
    )
    if float(eigenvalues.min()) < -tolerance:
        raise ValueError(
            f"{label} must be positive semidefinite; minimum eigenvalue is "
            f"{float(eigenvalues.min())}"
        )
    return symmetric


def _field_capacity(parameters: Mapping[str, float], label: str) -> float:
    if "parFC" not in parameters:
        raise ValueError(f"{label} must contain parFC")
    capacity = float(parameters["parFC"])
    if not np.isfinite(capacity) or capacity <= 0.0:
        raise ValueError(f"{label} parFC must be finite and positive")
    return capacity


def _validate_parameter_pair(
    source_parameters: Mapping[str, float],
    destination_parameters: Mapping[str, float],
) -> tuple[float, float]:
    source_keys = set(source_parameters)
    destination_keys = set(destination_parameters)
    if source_keys != destination_keys:
        raise ValueError(
            "source and destination parameter keys must match; only parFC may differ"
        )
    source_capacity = _field_capacity(source_parameters, "source parameters")
    destination_capacity = _field_capacity(
        destination_parameters,
        "destination parameters",
    )
    for name in sorted(source_keys - {"parFC"}):
        source_value = float(source_parameters[name])
        destination_value = float(destination_parameters[name])
        if not np.isfinite(source_value) or not np.isfinite(destination_value):
            raise ValueError("source and destination parameters must be finite")
        if source_value != destination_value:
            raise ValueError(
                f"only parFC may differ between parameter hypotheses; {name} differs"
            )
    return source_capacity, destination_capacity


def remap_parfc_state(
    state,
    source_parameters: Mapping[str, float],
    destination_parameters: Mapping[str, float],
) -> np.ndarray:
    """Map one state between field-capacity hypotheses without losing water.

    Capacity increases and non-binding decreases leave the state unchanged.
    For a binding decrease, soil water above the destination capacity is moved
    into the upper groundwater store. All other stores and routing memories are
    copied exactly.
    """
    source_capacity, destination_capacity = _validate_parameter_pair(
        source_parameters,
        destination_parameters,
    )
    mapped = _finite_state(state, "state").copy()
    if destination_capacity >= source_capacity:
        return mapped
    excess = max(float(mapped[SOIL_INDEX]) - destination_capacity, 0.0)
    if excess == 0.0:
        return mapped
    water_before = float(mapped[SOIL_INDEX] + mapped[UPPER_GROUNDWATER_INDEX])
    mapped[SOIL_INDEX] = destination_capacity
    mapped[UPPER_GROUNDWATER_INDEX] += excess
    water_after = float(mapped[SOIL_INDEX] + mapped[UPPER_GROUNDWATER_INDEX])
    if not np.isclose(water_after, water_before, rtol=0.0, atol=1e-12):
        raise ValueError("parFC state conversion did not conserve soil-plus-upper water")
    return mapped


def project_hbv_state_conserving_soil_excess(
    state,
    parameters: Mapping[str, float],
) -> np.ndarray:
    """Project a state while moving soil excess to the upper store.

    This is an opt-in alternative to the legacy direct-clipping projector. It
    deliberately retains the legacy treatment of negative values and snow
    liquid-water bounds, but it does not delete water above ``parFC``.
    """
    projected = _finite_state(state, "state").copy()
    capacity = _field_capacity(parameters, "parameters")
    if "parCWH" not in parameters:
        raise ValueError("parameters must contain parCWH")
    liquid_fraction = float(parameters["parCWH"])
    if not np.isfinite(liquid_fraction) or liquid_fraction < 0.0:
        raise ValueError("parameters parCWH must be finite and nonnegative")

    soil_excess = max(float(projected[SOIL_INDEX]) - capacity, 0.0)
    if soil_excess > 0.0:
        projected[SOIL_INDEX] -= soil_excess
        projected[UPPER_GROUNDWATER_INDEX] += soil_excess

    snow = max(float(projected[0]), 0.0)
    projected[0] = snow
    projected[1] = np.clip(projected[1], 0.0, liquid_fraction * snow)
    projected[SOIL_INDEX] = np.clip(projected[SOIL_INDEX], 1e-5, capacity)
    projected[UPPER_GROUNDWATER_INDEX:] = np.maximum(
        projected[UPPER_GROUNDWATER_INDEX:],
        0.0,
    )
    if not np.all(np.isfinite(projected)):
        raise ValueError("projected HBV-lite state is non-finite")
    return projected


def remap_parfc_moments(
    mean,
    covariance,
    source_parameters: Mapping[str, float],
    destination_parameters: Mapping[str, float],
    sigma_points: ScaledSigmaPoints,
) -> tuple[np.ndarray, np.ndarray]:
    """Convert one source model's moments into a destination parameter space."""
    source_capacity, destination_capacity = _validate_parameter_pair(
        source_parameters,
        destination_parameters,
    )
    source_mean = _finite_state(mean, "mean")
    source_covariance = _finite_covariance(covariance, "covariance")
    if destination_capacity >= source_capacity:
        return source_mean.copy(), source_covariance.copy()
    if not isinstance(sigma_points, ScaledSigmaPoints):
        raise TypeError("sigma_points must be a ScaledSigmaPoints instance")
    if sigma_points.n != len(STATE_NAMES):
        raise ValueError(
            f"sigma_points dimension must be {len(STATE_NAMES)}, got {sigma_points.n}"
        )

    source_sigmas = sigma_points.sigma_points(source_mean, source_covariance)
    mapped_sigmas = np.asarray(
        [
            remap_parfc_state(
                point,
                source_parameters,
                destination_parameters,
            )
            for point in source_sigmas
        ],
        dtype=np.float64,
    )
    if np.array_equal(mapped_sigmas, source_sigmas):
        return source_mean.copy(), source_covariance.copy()

    source_sigma_mean, source_sigma_covariance = unscented_transform(
        source_sigmas,
        sigma_points.mean_weights,
        sigma_points.covariance_weights,
    )
    mapped_mean, mapped_covariance = unscented_transform(
        mapped_sigmas,
        sigma_points.mean_weights,
        sigma_points.covariance_weights,
    )
    mapped_mean = _finite_state(mapped_mean, "mapped mean").copy()
    mapped_covariance = _finite_covariance(
        mapped_covariance,
        "mapped covariance",
    )

    selector = np.zeros(len(STATE_NAMES), dtype=np.float64)
    selector[SOIL_INDEX] = 1.0
    selector[UPPER_GROUNDWATER_INDEX] = 1.0
    expected_mean = float(selector @ source_sigma_mean)
    actual_mean = float(selector @ mapped_mean)
    expected_variance = float(selector @ source_sigma_covariance @ selector)
    actual_variance = float(selector @ mapped_covariance @ selector)
    mean_tolerance = 1e-10 * max(abs(expected_mean), 1.0)
    variance_tolerance = 1e-10 * max(abs(expected_variance), 1.0)
    if not np.isclose(actual_mean, expected_mean, rtol=0.0, atol=mean_tolerance):
        raise ValueError("moment conversion did not conserve soil-plus-upper mean")
    if not np.isclose(
        actual_variance,
        expected_variance,
        rtol=0.0,
        atol=variance_tolerance,
    ):
        raise ValueError("moment conversion did not conserve soil-plus-upper variance")
    if mapped_mean[SOIL_INDEX] > destination_capacity + 1e-10:
        raise ValueError("mapped mean exceeds the destination parFC")
    return mapped_mean, mapped_covariance

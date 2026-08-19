import sys
from pathlib import Path

import numpy as np
import pytest


sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from hbv_joint_uncertainty.hbv_state_mapping import (  # noqa: E402
    project_hbv_state_conserving_soil_excess,
    remap_parfc_moments,
    remap_parfc_state,
)
from hbv_joint_uncertainty.sigma_filter import (  # noqa: E402
    ScaledSigmaPoints,
    unscented_transform,
)


def _parameters(field_capacity: float, beta: float = 2.0) -> dict[str, float]:
    return {
        "parFC": float(field_capacity),
        "parBETA": float(beta),
        "parCWH": 0.1,
    }


def _state(soil: float = 80.0, upper: float = 10.0) -> np.ndarray:
    return np.array(
        [5.0, 0.2, soil, upper, 30.0, *np.arange(1.0, 11.0)],
        dtype=np.float64,
    )


def test_same_capacity_mapping_is_exact_identity_for_state_and_moments():
    parameters = _parameters(100.0)
    state = _state(soil=99.0, upper=20.0)
    covariance = np.diag(np.linspace(0.01, 0.15, 15))
    sigma_points = ScaledSigmaPoints(15)

    mapped_state = remap_parfc_state(state, parameters, parameters)
    mapped_mean, mapped_covariance = remap_parfc_moments(
        state,
        covariance,
        parameters,
        parameters,
        sigma_points,
    )

    np.testing.assert_array_equal(mapped_state, state)
    np.testing.assert_array_equal(mapped_mean, state)
    np.testing.assert_array_equal(mapped_covariance, covariance)
    assert mapped_state is not state
    assert mapped_mean is not state
    assert mapped_covariance is not covariance


def test_capacity_reduction_transfers_excess_to_upper_store_and_preserves_water():
    source = _parameters(200.0)
    destination = _parameters(100.0)
    state = _state(soil=160.0, upper=20.0)

    mapped = remap_parfc_state(state, source, destination)

    assert mapped[2] == 100.0
    assert mapped[3] == 80.0
    np.testing.assert_array_equal(mapped[[0, 1, 4]], state[[0, 1, 4]])
    np.testing.assert_array_equal(mapped[5:], state[5:])
    assert mapped[:5].sum() == pytest.approx(state[:5].sum(), abs=1e-12)


@pytest.mark.parametrize(
    ("source_capacity", "destination_capacity", "soil"),
    [
        (100.0, 200.0, 80.0),
        (200.0, 100.0, 80.0),
    ],
)
def test_capacity_increase_or_nonbinding_reduction_does_not_move_water(
    source_capacity,
    destination_capacity,
    soil,
):
    state = _state(soil=soil, upper=12.0)

    mapped = remap_parfc_state(
        state,
        _parameters(source_capacity),
        _parameters(destination_capacity),
    )

    np.testing.assert_array_equal(mapped, state)


def test_capacity_increase_moment_mapping_is_exact_identity():
    mean = _state(soil=80.0, upper=12.0)
    covariance = np.diag(np.linspace(0.01, 0.15, 15))

    mapped_mean, mapped_covariance = remap_parfc_moments(
        mean,
        covariance,
        _parameters(100.0),
        _parameters(200.0),
        ScaledSigmaPoints(15),
    )

    np.testing.assert_array_equal(mapped_mean, mean)
    np.testing.assert_array_equal(mapped_covariance, covariance)


def test_nonbinding_reduction_with_singular_covariance_is_exact_moment_identity():
    mean = _state(soil=185.28479483508727, upper=31.252171736189926)
    covariance = np.zeros((15, 15), dtype=np.float64)
    covariance[0, 0] = 793.1911756257341
    covariance[2, 2] = 1.46817939e-5
    covariance[3, 3] = 0.220048185
    covariance[2, 3] = covariance[3, 2] = 2.24787981e-4

    mapped_mean, mapped_covariance = remap_parfc_moments(
        mean,
        covariance,
        _parameters(730.7683739499867),
        _parameters(365.3841869749933),
        ScaledSigmaPoints(15),
    )

    np.testing.assert_array_equal(mapped_mean, mean)
    np.testing.assert_array_equal(mapped_covariance, covariance)


def test_mapping_rejects_parameter_changes_other_than_field_capacity():
    with pytest.raises(ValueError, match="only parFC may differ"):
        remap_parfc_state(
            _state(),
            _parameters(100.0, beta=2.0),
            _parameters(200.0, beta=3.0),
        )


def test_conservative_projector_transfers_soil_excess_before_other_bounds():
    raw = _state(soil=160.0, upper=20.0)
    raw[0] = -1.0
    raw[1] = 10.0

    projected = project_hbv_state_conserving_soil_excess(
        raw,
        _parameters(100.0),
    )

    assert projected[0] == 0.0
    assert projected[1] == 0.0
    assert projected[2] == 100.0
    assert projected[3] == 80.0
    np.testing.assert_array_equal(projected[5:], raw[5:])


def test_reduction_moment_mapping_matches_affine_reference():
    source = _parameters(200.0)
    destination = _parameters(100.0)
    mean = _state(soil=160.0, upper=20.0)
    covariance = np.diag(np.linspace(0.01, 0.15, 15))
    covariance[2, 3] = covariance[3, 2] = 0.02
    sigma_points = ScaledSigmaPoints(15)

    mapped_mean, mapped_covariance = remap_parfc_moments(
        mean,
        covariance,
        source,
        destination,
        sigma_points,
    )

    jacobian = np.eye(15)
    jacobian[2, :] = 0.0
    jacobian[3, 2] = 1.0
    expected_mean = remap_parfc_state(mean, source, destination)
    expected_covariance = jacobian @ covariance @ jacobian.T
    np.testing.assert_allclose(mapped_mean, expected_mean, rtol=0.0, atol=2e-12)
    np.testing.assert_allclose(
        mapped_covariance,
        expected_covariance,
        rtol=0.0,
        atol=2e-12,
    )


def test_kink_crossing_preserves_soil_plus_upper_mean_and_variance():
    source = _parameters(200.0)
    destination = _parameters(100.0)
    mean = _state(soil=100.0, upper=20.0)
    covariance = np.diag(np.linspace(0.01, 0.15, 15))
    covariance[2, 2] = 400.0
    covariance[3, 3] = 25.0
    covariance[2, 3] = covariance[3, 2] = -20.0
    sigma_points = ScaledSigmaPoints(15)

    mapped_mean, mapped_covariance = remap_parfc_moments(
        mean,
        covariance,
        source,
        destination,
        sigma_points,
    )

    total_selector = np.zeros(15)
    total_selector[2:4] = 1.0
    assert total_selector @ mapped_mean == pytest.approx(
        total_selector @ mean,
        abs=1e-10,
    )
    assert total_selector @ mapped_covariance @ total_selector == pytest.approx(
        total_selector @ covariance @ total_selector,
        abs=1e-9,
    )
    assert np.all(np.isfinite(mapped_covariance))
    np.testing.assert_allclose(
        mapped_covariance,
        mapped_covariance.T,
        rtol=0.0,
        atol=1e-12,
    )
    assert np.linalg.eigvalsh(mapped_covariance).min() >= -1e-10
    assert mapped_mean[2] <= destination["parFC"] + 1e-12


def test_kink_crossing_with_singular_covariance_preserves_same_sigma_total_moments():
    source = _parameters(200.0)
    destination = _parameters(100.0)
    mean = _state(soil=100.0, upper=31.25)
    covariance = np.zeros((15, 15), dtype=np.float64)
    covariance[0, 0] = 793.1911756257341
    covariance[2, 2] = 1e-4
    covariance[3, 3] = 0.22
    covariance[2, 3] = covariance[3, 2] = -0.001
    sigma_points = ScaledSigmaPoints(15)
    source_sigmas = sigma_points.sigma_points(mean, covariance)
    source_sigma_mean, source_sigma_covariance = unscented_transform(
        source_sigmas,
        sigma_points.mean_weights,
        sigma_points.covariance_weights,
    )

    mapped_mean, mapped_covariance = remap_parfc_moments(
        mean,
        covariance,
        source,
        destination,
        sigma_points,
    )

    total_selector = np.zeros(15)
    total_selector[2:4] = 1.0
    assert total_selector @ mapped_mean == pytest.approx(
        total_selector @ source_sigma_mean,
        abs=1e-10,
    )
    assert total_selector @ mapped_covariance @ total_selector == pytest.approx(
        total_selector @ source_sigma_covariance @ total_selector,
        abs=1e-10,
    )
    assert mapped_mean[2] <= destination["parFC"] + 1e-12

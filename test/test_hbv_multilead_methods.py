import sys
from pathlib import Path

import numpy as np
import pytest


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "src"))

from hbv_joint_uncertainty.hbv_adapter import initial_state_vector  # noqa: E402
from hbv_multilead_joint_uncertainty.methods import (  # noqa: E402
    LEGACY_PARAMETER_ORDER,
    METHOD_ORDER,
    PARAMETER_ORDER,
    build_method_bank,
    build_method_definitions,
)


CENTER = {
    "parTT": 0.0,
    "parCFMAX": 3.0,
    "parCFR": 0.05,
    "parCWH": 0.1,
    "parFC": 200.0,
    "parBETA": 2.0,
    "parLP": 0.8,
    "parK0": 0.2,
    "parK1": 0.1,
    "parUZL": 20.0,
    "parPERC": 1.0,
    "parK2": 0.05,
    "lag_time": 2.0,
}


def _parameter_vectors():
    return {
        "equifinal_low_flow": {**CENTER, "parTT": -0.1},
        "trained_center": CENTER.copy(),
        "equifinal_high_flow": {**CENTER, "parTT": 0.1},
    }


def _diverse_parameter_vectors():
    return {
        "equifinal_diverse_1": {**CENTER, "parTT": -0.1},
        "trained_center": CENTER.copy(),
        "equifinal_diverse_2": {**CENTER, "parTT": 0.1},
    }


def _process_contract():
    scales = {"process_low": 1e-7, "process_selected": 1e-6, "process_high": 1e-5}
    covariances = {}
    for noise_id, scale in scales.items():
        diagonal = np.zeros(15)
        diagonal[:5] = scale * np.arange(1.0, 6.0) ** 2
        covariances[noise_id] = np.diag(diagonal)
    return scales, covariances


def test_five_methods_have_one_one_three_three_and_nine_candidates():
    scales, covariances = _process_contract()
    methods = build_method_definitions(
        parameter_vectors=_parameter_vectors(),
        process_scales=scales,
        process_covariances=covariances,
        selected_process_id="process_selected",
    )

    assert tuple(methods) == METHOD_ORDER
    assert {name: len(values) for name, values in methods.items()} == {
        "open_loop": 1,
        "fixed_filter": 1,
        "parameter_only": 3,
        "noise_only": 3,
        "joint": 9,
    }


@pytest.mark.parametrize(
    ("parameter_vectors", "expected_order"),
    [
        (_diverse_parameter_vectors, PARAMETER_ORDER),
        (_parameter_vectors, LEGACY_PARAMETER_ORDER),
    ],
)
def test_method_builder_supports_current_and_legacy_frozen_parameter_identifiers(
    parameter_vectors, expected_order
):
    scales, covariances = _process_contract()

    methods = build_method_definitions(
        parameter_vectors=parameter_vectors(),
        process_scales=scales,
        process_covariances=covariances,
        selected_process_id="process_selected",
    )

    assert tuple(candidate.parameter_id for candidate in methods["parameter_only"]) == expected_order
    assert len(methods["joint"]) == 9


def test_same_noise_identifier_has_bitwise_equal_absolute_covariance_across_parameters():
    scales, covariances = _process_contract()
    methods = build_method_definitions(
        parameter_vectors=_parameter_vectors(),
        process_scales=scales,
        process_covariances=covariances,
        selected_process_id="process_selected",
    )

    joint = methods["joint"]
    for noise_id in scales:
        matrices = [candidate.process_covariance for candidate in joint if candidate.process_id == noise_id]
        assert len(matrices) == 3
        for matrix in matrices[1:]:
            np.testing.assert_array_equal(matrix, matrices[0])


def test_all_filter_candidates_share_the_frozen_initial_covariance_and_observation_variance():
    scales, covariances = _process_contract()
    methods = build_method_definitions(
        parameter_vectors=_parameter_vectors(),
        process_scales=scales,
        process_covariances=covariances,
        selected_process_id="process_selected",
    )
    states = {
        parameter_id: initial_state_vector(parameters)
        for parameter_id, parameters in _parameter_vectors().items()
    }
    initial_covariance = np.diag(np.linspace(1e-6, 15e-6, 15))

    bank = build_method_bank(
        candidates=methods["joint"],
        initial_states=states,
        initial_covariance=initial_covariance,
        observation_standard_deviation=0.25,
        factor_transition_stay_probability=0.98,
    )

    for candidate_filter in bank.estimator.filters:
        np.testing.assert_array_equal(candidate_filter.covariance, initial_covariance)
        np.testing.assert_array_equal(candidate_filter.observation_covariance, np.array([[0.25**2]]))
    assert getattr(bank.estimator, "interaction_mode") == "full"


def test_factorial_transition_has_the_same_two_percent_marginal_switch_rate_in_all_methods():
    scales, covariances = _process_contract()
    methods = build_method_definitions(
        parameter_vectors=_parameter_vectors(),
        process_scales=scales,
        process_covariances=covariances,
        selected_process_id="process_selected",
    )
    states = {
        parameter_id: initial_state_vector(parameters)
        for parameter_id, parameters in _parameter_vectors().items()
    }
    for method in ("parameter_only", "noise_only", "joint"):
        candidates = methods[method]
        bank = build_method_bank(
            candidates=candidates,
            initial_states=states,
            initial_covariance=np.eye(15) * 1e-6,
            observation_standard_deviation=0.25,
            factor_transition_stay_probability=0.98,
        )
        matrix = bank.estimator.transition_matrix
        for source, candidate in enumerate(candidates):
            parameter_switch = sum(
                matrix[source, destination]
                for destination, other in enumerate(candidates)
                if other.parameter_id != candidate.parameter_id
            )
            process_switch = sum(
                matrix[source, destination]
                for destination, other in enumerate(candidates)
                if other.process_id != candidate.process_id
            )
            if method in {"parameter_only", "joint"}:
                assert parameter_switch == pytest.approx(0.02)
            else:
                assert parameter_switch == pytest.approx(0.0)
            if method in {"noise_only", "joint"}:
                assert process_switch == pytest.approx(0.02)
            else:
                assert process_switch == pytest.approx(0.0)


def test_method_builder_rejects_parameter_dependent_process_covariance_shapes():
    scales, covariances = _process_contract()
    covariances["process_high"] = np.eye(14)

    with pytest.raises(ValueError, match="15 by 15"):
        build_method_definitions(
            parameter_vectors=_parameter_vectors(),
            process_scales=scales,
            process_covariances=covariances,
            selected_process_id="process_selected",
        )

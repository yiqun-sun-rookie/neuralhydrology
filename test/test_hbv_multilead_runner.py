import sys
from pathlib import Path

import numpy as np


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "src"))

from hbv_joint_uncertainty.hbv_adapter import initial_state_vector, simulate_adapter  # noqa: E402
from hbv_multilead_joint_uncertainty.runner import run_five_methods, run_open_loop_multilead  # noqa: E402


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


def _contract_parts():
    parameters = {
        "equifinal_low_flow": {**CENTER, "parFC": 190.0},
        "trained_center": CENTER.copy(),
        "equifinal_high_flow": {**CENTER, "parFC": 210.0},
    }
    scales = {"process_low": 1e-8, "process_selected": 1e-7, "process_high": 1e-6}
    covariances = {}
    for process_id, scale in scales.items():
        diagonal = np.zeros(15)
        diagonal[:5] = scale * np.array([200.0, 20.0, 200.0, 20.0, 20.0]) ** 2
        covariances[process_id] = np.diag(diagonal)
    states = {parameter_id: initial_state_vector(values) for parameter_id, values in parameters.items()}
    return parameters, scales, covariances, states


def _forcing(days=12):
    x = np.arange(days, dtype=np.float64)
    return np.column_stack((2.0 + 0.5 * np.sin(x), np.full(days, 1.0), np.full(days, 5.0)))


def test_open_loop_targets_are_the_direct_continuous_model_values():
    forcing = _forcing()
    initial_state = initial_state_vector(CENTER)
    direct, _ = simulate_adapter(
        forcing[:, 0], forcing[:, 1], forcing[:, 2], CENTER, initial_state=initial_state
    )

    result = run_open_loop_multilead(forcing, CENTER, initial_state, lead_days=(1, 3, 7))

    np.testing.assert_array_equal(result.origin_indices, np.arange(5))
    np.testing.assert_array_equal(result.target_indices[0], np.array([1, 3, 7]))
    np.testing.assert_allclose(result.predictions, direct[result.target_indices], rtol=0.0, atol=1e-12)


def test_all_five_methods_share_origins_targets_and_observations():
    parameters, scales, covariances, states = _contract_parts()
    forcing = _forcing()
    observations = np.linspace(0.1, 1.2, len(forcing))

    results = run_five_methods(
        forcing=forcing,
        observations=observations,
        parameter_vectors=parameters,
        process_scales=scales,
        process_covariances=covariances,
        selected_process_id="process_selected",
        initial_states=states,
        initial_covariance=np.eye(15) * 1e-6,
        observation_standard_deviation=0.5,
        factor_transition_stay_probability=0.98,
        interaction_mode="full",
        lead_days=(1, 3, 7),
    )

    assert tuple(results) == ("open_loop", "fixed_filter", "parameter_only", "noise_only", "joint")
    reference = results["open_loop"]
    for result in results.values():
        np.testing.assert_array_equal(result.origin_indices, reference.origin_indices)
        np.testing.assert_array_equal(result.target_indices, reference.target_indices)
        np.testing.assert_array_equal(result.target_observations, observations[result.target_indices])
        assert result.predictions.shape == (5, 3)
    assert {name: len(result.candidate_ids) for name, result in results.items()} == {
        "open_loop": 1,
        "fixed_filter": 1,
        "parameter_only": 3,
        "noise_only": 3,
        "joint": 9,
    }


def test_every_method_forecast_is_unchanged_by_discharge_after_its_origin():
    parameters, scales, covariances, states = _contract_parts()
    forcing = _forcing(days=10)
    observations = np.linspace(0.1, 1.0, len(forcing))
    arguments = dict(
        forcing=forcing,
        parameter_vectors=parameters,
        process_scales=scales,
        process_covariances=covariances,
        selected_process_id="process_selected",
        initial_states=states,
        initial_covariance=np.eye(15) * 1e-6,
        observation_standard_deviation=0.5,
        factor_transition_stay_probability=0.98,
        interaction_mode="full",
        lead_days=(1, 3, 7),
    )
    reference = run_five_methods(observations=observations, **arguments)
    for row, origin in enumerate(reference["joint"].origin_indices):
        perturbed_observations = observations.copy()
        perturbed_observations[origin + 1:] += 1000.0
        perturbed = run_five_methods(observations=perturbed_observations, **arguments)
        for method in reference:
            np.testing.assert_allclose(
                reference[method].predictions[row], perturbed[method].predictions[row], rtol=0.0, atol=0.0
            )


def test_future_discharge_availability_does_not_block_already_issued_forecasts():
    parameters, scales, covariances, states = _contract_parts()
    forcing = _forcing(days=10)
    complete = np.linspace(0.1, 1.0, len(forcing))
    unavailable_future = complete.copy()
    unavailable_future[-7:] = np.nan
    arguments = dict(
        forcing=forcing,
        parameter_vectors=parameters,
        process_scales=scales,
        process_covariances=covariances,
        selected_process_id="process_selected",
        initial_states=states,
        initial_covariance=np.eye(15) * 1e-6,
        observation_standard_deviation=0.5,
        factor_transition_stay_probability=0.98,
        interaction_mode="full",
        lead_days=(1, 3, 7),
    )

    reference = run_five_methods(observations=complete, **arguments)
    unavailable = run_five_methods(observations=unavailable_future, **arguments)

    for method in reference:
        np.testing.assert_array_equal(reference[method].predictions, unavailable[method].predictions)

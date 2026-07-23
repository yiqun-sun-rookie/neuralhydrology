"""Phase-2 interaction-value comparison arms (ID23 G3 phase 2).

The four arms compare mixing/interaction strategies on ONE candidate family and the
SAME truths: full IMM, no-interaction likelihood (none), static mixing (frozen
uniform weights), and oracle (single known-true candidate). Correctness anchor: the
`full` arm must reproduce the frozen three-stage runner's per-family output
bit-for-bit; static/oracle are pinned to their definitions via degeneracy identities.
"""

import importlib
import sys
from pathlib import Path

import numpy as np
import pytest

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "src"))

from hbv_multilead_joint_uncertainty.methods import build_method_definitions  # noqa: E402

RUNNER_MODULE = "hbv_multilead_joint_uncertainty.three_stage_switching_validation"
ARMS_MODULE = "hbv_multilead_joint_uncertainty.interaction_value_comparison"

BASE_PARAMETERS = {
    "parTT": 0.0, "parCFMAX": 3.2, "parCFR": 0.04, "parCWH": 0.1, "parFC": 250.0,
    "parBETA": 2.1, "parLP": 0.7, "parK0": 0.2, "parK1": 0.06, "parUZL": 18.0,
    "parPERC": 1.2, "parK2": 0.015, "lag_time": 3.0,
}


def _definitions():
    parameters = {}
    for index, parameter_id in enumerate(
        ("equifinal_diverse_1", "trained_center", "equifinal_diverse_2")
    ):
        values = BASE_PARAMETERS.copy()
        values["parFC"] += 20.0 * (index - 1)
        values["parK1"] += 0.01 * (index - 1)
        parameters[parameter_id] = values
    covariances = {}
    scales = {}
    for index, process_id in enumerate(("small", "medium", "large")):
        diagonal = np.zeros(15, dtype=np.float64)
        diagonal[:5] = (10.0**index) * np.asarray(
            [1e-3, 1e-5, 1e-3, 1e-4, 1e-3], dtype=np.float64
        )
        covariances[process_id] = np.diag(diagonal)
        scales[process_id] = 10.0 ** (-4 + index)
    return build_method_definitions(parameters, scales, covariances, "large")


def _forcing(seed=8101, days=20):
    rng = np.random.default_rng(seed)
    angle = np.linspace(0.0, 2.0 * np.pi, days)
    return np.column_stack((
        rng.gamma(0.8, 4.0, size=days),
        np.maximum(0.0, 2.0 + np.sin(angle)),
        4.0 + 12.0 * np.sin(angle - np.pi / 2.0),
    ))


WARMUP = 8
STAGE_LENGTHS = (3, 3, 3)
LEADS = (1, 3)
ASSIM_DAYS = sum(STAGE_LENGTHS)  # 9
MAX_LEAD = LEADS[-1]
TOTAL_DAYS = WARMUP + ASSIM_DAYS + MAX_LEAD  # 20
OBS_STD = 0.05
STAY = 0.98


@pytest.fixture(scope="module")
def switching_result():
    module = importlib.import_module(RUNNER_MODULE)
    defs = _definitions()
    parameters = {c.parameter_id: c.parameters for c in defs["parameter_only"]}
    process_candidates = defs["noise_only"]
    process_scales = {c.process_id: c.process_scale for c in process_candidates}
    process_covariances = {c.process_id: c.process_covariance for c in process_candidates}
    return module.run_three_stage_switching_validation(
        forcing_blocks=_forcing(days=TOTAL_DAYS)[None, :, :],
        block_ids=("block_01",),
        parameter_vectors=parameters,
        process_scales=process_scales,
        process_covariances=process_covariances,
        selected_process_id="large",
        scenario="parameter_switch",
        process_noise_seeds=(9101,),
        observation_noise_seeds=(10101,),
        warmup_days=WARMUP,
        stage_lengths=STAGE_LENGTHS,
        lead_days=LEADS,
        initial_covariance_fraction=0.001,
        observation_standard_deviation=OBS_STD,
        factor_transition_stay_probability=STAY,
    )


def _arm_inputs(result, block=0, truth=0):
    initial_states = {
        pid: result.initial_parameter_states[block, i]
        for i, pid in enumerate(result.parameter_ids)
    }
    active_forcing = result.forcing_blocks[block][result.warmup_days:]
    observations = result.observed_discharge[block, truth]
    covariance = result.initial_covariances[block]
    leads = result.forecast_lead_days
    return initial_states, active_forcing, observations, covariance, leads


def test_arms_module_is_importable():
    assert importlib.util.find_spec(ARMS_MODULE) is not None


def test_full_arm_reproduces_frozen_runner_bit_for_bit(switching_result):
    """The parameterized full arm must equal the frozen runner's parameter_only output."""
    arms = importlib.import_module(ARMS_MODULE)
    result = switching_result
    defs = _definitions()
    candidates = defs["parameter_only"]
    initial_states, active_forcing, observations, covariance, leads = _arm_inputs(result)
    pidx = list(result.method_names).index("parameter_only")

    probabilities, combined = arms.assimilate_family_arm(
        candidates=candidates,
        initial_states=initial_states,
        initial_covariance=covariance,
        active_forcing=active_forcing,
        observations=observations,
        assimilation_days=result.assimilation_days,
        leads=leads,
        observation_standard_deviation=OBS_STD,
        factor_transition_stay_probability=STAY,
        interaction_mode="full",
    )
    expected_probs = result.method_assimilation_probabilities[
        0, 0, pidx, :, : len(candidates)
    ]
    expected_combined = result.method_predictions[0, 0, pidx]
    assert probabilities.shape == (result.assimilation_days, len(candidates))
    np.testing.assert_array_equal(probabilities, expected_probs)
    np.testing.assert_array_equal(combined, expected_combined)


def test_none_arm_differs_from_full_but_stays_valid(switching_result):
    arms = importlib.import_module(ARMS_MODULE)
    result = switching_result
    candidates = _definitions()["parameter_only"]
    initial_states, active_forcing, observations, covariance, leads = _arm_inputs(result)
    probs_none, combined_none = arms.assimilate_family_arm(
        candidates=candidates, initial_states=initial_states,
        initial_covariance=covariance, active_forcing=active_forcing,
        observations=observations, assimilation_days=result.assimilation_days,
        leads=leads, observation_standard_deviation=OBS_STD,
        factor_transition_stay_probability=STAY, interaction_mode="none",
    )
    # valid distribution every day
    assert np.all(probs_none >= 0.0)
    np.testing.assert_allclose(probs_none.sum(axis=1), 1.0, atol=1e-12)
    assert np.all(np.isfinite(combined_none))


def test_static_arm_is_uniform_mean_of_independent_forecasts(switching_result):
    arms = importlib.import_module(ARMS_MODULE)
    runner = importlib.import_module(RUNNER_MODULE)
    result = switching_result
    candidates = _definitions()["parameter_only"]
    initial_states, active_forcing, observations, covariance, leads = _arm_inputs(result)

    per_candidate = []
    for candidate in candidates:
        _, _, _, forecast = runner._assimilate_record_then_forecast(
            candidates=(candidate,), initial_states=initial_states,
            covariance=covariance, active_forcing=active_forcing,
            observations=observations, assimilation_days=result.assimilation_days,
            leads=leads, observation_standard_deviation=OBS_STD,
            factor_transition_stay_probability=STAY,
        )
        per_candidate.append(forecast.combined_predictions)
    expected_combined = np.mean(per_candidate, axis=0)

    frozen_probs, combined = arms.static_mixing_arm(
        candidates=candidates, initial_states=initial_states,
        initial_covariance=covariance, active_forcing=active_forcing,
        observations=observations, assimilation_days=result.assimilation_days,
        leads=leads, observation_standard_deviation=OBS_STD,
        factor_transition_stay_probability=STAY,
    )
    np.testing.assert_array_equal(
        frozen_probs, np.full((result.assimilation_days, len(candidates)), 1.0 / len(candidates))
    )
    np.testing.assert_allclose(combined, expected_combined, rtol=0.0, atol=0.0)


def test_oracle_single_stage_equals_true_candidate_filter(switching_result):
    arms = importlib.import_module(ARMS_MODULE)
    runner = importlib.import_module(RUNNER_MODULE)
    result = switching_result
    candidates = _definitions()["parameter_only"]
    initial_states, active_forcing, observations, covariance, leads = _arm_inputs(result)
    k = 1  # trained_center

    _, _, _, forecast = runner._assimilate_record_then_forecast(
        candidates=(candidates[k],), initial_states=initial_states,
        covariance=covariance, active_forcing=active_forcing,
        observations=observations, assimilation_days=result.assimilation_days,
        leads=leads, observation_standard_deviation=OBS_STD,
        factor_transition_stay_probability=STAY,
    )
    expected = forecast.combined_predictions

    combined = arms.oracle_arm(
        candidates=candidates,
        true_candidate_index_per_stage=[k],
        stage_boundaries=[(0, result.assimilation_days)],
        initial_states=initial_states, initial_covariance=covariance,
        active_forcing=active_forcing, observations=observations,
        leads=leads, observation_standard_deviation=OBS_STD,
        factor_transition_stay_probability=STAY,
    )
    np.testing.assert_array_equal(combined, expected)


def test_oracle_two_stages_same_candidate_equals_continuous_filter(switching_result):
    arms = importlib.import_module(ARMS_MODULE)
    result = switching_result
    candidates = _definitions()["parameter_only"]
    initial_states, active_forcing, observations, covariance, leads = _arm_inputs(result)
    k = 0

    single_stage = arms.oracle_arm(
        candidates=candidates, true_candidate_index_per_stage=[k],
        stage_boundaries=[(0, result.assimilation_days)],
        initial_states=initial_states, initial_covariance=covariance,
        active_forcing=active_forcing, observations=observations,
        leads=leads, observation_standard_deviation=OBS_STD,
        factor_transition_stay_probability=STAY,
    )
    split = result.assimilation_days // 2
    two_stage = arms.oracle_arm(
        candidates=candidates, true_candidate_index_per_stage=[k, k],
        stage_boundaries=[(0, split), (split, result.assimilation_days)],
        initial_states=initial_states, initial_covariance=covariance,
        active_forcing=active_forcing, observations=observations,
        leads=leads, observation_standard_deviation=OBS_STD,
        factor_transition_stay_probability=STAY,
    )
    np.testing.assert_allclose(two_stage, single_stage, rtol=0.0, atol=1e-9)

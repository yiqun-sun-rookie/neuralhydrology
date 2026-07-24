"""Forecast-phase weight drift comparison (ID23 G3 follow-up, 2026-07-24).

Design freeze: docs/plans/2026-07-24-g3-forecast-weight-drift-design.md

The follow-up holds the forecast-combination weights at the final assimilation
posterior instead of propagating them through the transition matrix on each
forecast day, and measures the net effect on multi-lead forecast error.

Correctness anchors:
  1. the new path reproduces the phase-2 arm's combined forecast bit-for-bit;
  2. under no interaction, candidate forecast paths equal independent
     single-candidate runs bit-for-bit -- this is what makes the primary
     comparison single-factor (changing weights cannot move the paths);
  3. frozen combination with uniform weights equals the phase-2 static arm;
  4. the drift the experiment removes is actually present.
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
DRIFT_MODULE = "hbv_multilead_joint_uncertainty.forecast_weight_drift"

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
ASSIM_DAYS = sum(STAGE_LENGTHS)
MAX_LEAD = LEADS[-1]
TOTAL_DAYS = WARMUP + ASSIM_DAYS + MAX_LEAD
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


def _inputs(result, block=0, truth=0):
    initial_states = {
        pid: result.initial_parameter_states[block, i]
        for i, pid in enumerate(result.parameter_ids)
    }
    return (
        initial_states,
        result.forcing_blocks[block][result.warmup_days:],
        result.observed_discharge[block, truth],
        result.initial_covariances[block],
        result.forecast_lead_days,
    )


def _run_paths(result, mode):
    drift = importlib.import_module(DRIFT_MODULE)
    candidates = _definitions()["parameter_only"]
    initial_states, forcing, observations, covariance, leads = _inputs(result)
    return drift.assimilate_family_forecast_paths(
        candidates=candidates,
        initial_states=initial_states,
        initial_covariance=covariance,
        active_forcing=forcing,
        observations=observations,
        assimilation_days=ASSIM_DAYS,
        leads=leads,
        observation_standard_deviation=OBS_STD,
        factor_transition_stay_probability=STAY,
        interaction_mode=mode,
    )


# --------------------------------------------------------------------------- #
# Anchor 1: the new path reproduces the phase-2 arm bit-for-bit
# --------------------------------------------------------------------------- #


@pytest.mark.parametrize("mode", ["full", "none"])
def test_forecast_paths_reproduce_phase_two_arm_bit_for_bit(switching_result, mode):
    arms = importlib.import_module(ARMS_MODULE)
    candidates = _definitions()["parameter_only"]
    initial_states, forcing, observations, covariance, leads = _inputs(switching_result)
    reference_probabilities, reference_forecast = arms.assimilate_family_arm(
        candidates=candidates,
        initial_states=initial_states,
        initial_covariance=covariance,
        active_forcing=forcing,
        observations=observations,
        assimilation_days=ASSIM_DAYS,
        leads=leads,
        observation_standard_deviation=OBS_STD,
        factor_transition_stay_probability=STAY,
        interaction_mode=mode,
    )
    paths = _run_paths(switching_result, mode)
    np.testing.assert_array_equal(paths["drifting_forecast"], reference_forecast)
    np.testing.assert_array_equal(
        paths["assimilation_probabilities"], reference_probabilities
    )
    np.testing.assert_array_equal(
        paths["final_posterior_weights"], reference_probabilities[-1]
    )


# --------------------------------------------------------------------------- #
# Anchor 2: under no interaction the candidate paths are weight-independent
# --------------------------------------------------------------------------- #


def test_no_interaction_candidate_paths_equal_independent_single_candidate_runs(
    switching_result,
):
    runner = importlib.import_module(RUNNER_MODULE)
    candidates = _definitions()["parameter_only"]
    initial_states, forcing, observations, covariance, leads = _inputs(switching_result)
    paths = _run_paths(switching_result, "none")
    for index, candidate in enumerate(candidates):
        _, _, _, single = runner._assimilate_record_then_forecast(
            candidates=(candidate,),
            initial_states=initial_states,
            covariance=covariance,
            active_forcing=forcing,
            observations=observations,
            assimilation_days=ASSIM_DAYS,
            leads=np.asarray(tuple(int(v) for v in leads), dtype=np.int64),
            observation_standard_deviation=OBS_STD,
            factor_transition_stay_probability=STAY,
        )
        np.testing.assert_array_equal(
            paths["candidate_predictions"][:, index], single.combined_predictions
        )


def test_full_interaction_candidate_paths_differ_from_independent_runs(switching_result):
    """State mixing moves the paths, so the full method is NOT weight-independent."""
    none_paths = _run_paths(switching_result, "none")
    full_paths = _run_paths(switching_result, "full")
    assert not np.array_equal(
        full_paths["candidate_predictions"], none_paths["candidate_predictions"]
    )


# --------------------------------------------------------------------------- #
# Anchor 3: uniform frozen weights reproduce the phase-2 static arm
# --------------------------------------------------------------------------- #


def test_uniform_frozen_weights_reproduce_static_mixing_arm(switching_result):
    drift = importlib.import_module(DRIFT_MODULE)
    arms = importlib.import_module(ARMS_MODULE)
    candidates = _definitions()["parameter_only"]
    initial_states, forcing, observations, covariance, leads = _inputs(switching_result)
    _, static_forecast = arms.static_mixing_arm(
        candidates=candidates,
        initial_states=initial_states,
        initial_covariance=covariance,
        active_forcing=forcing,
        observations=observations,
        assimilation_days=ASSIM_DAYS,
        leads=leads,
        observation_standard_deviation=OBS_STD,
        factor_transition_stay_probability=STAY,
    )
    paths = _run_paths(switching_result, "none")
    uniform = np.full(len(candidates), 1.0 / len(candidates), dtype=np.float64)
    combined = drift.frozen_weight_forecast(paths["candidate_predictions"], uniform)
    np.testing.assert_allclose(combined, static_forecast, rtol=0.0, atol=1e-12)


# --------------------------------------------------------------------------- #
# Anchor 4: the drift being removed is actually present
# --------------------------------------------------------------------------- #


def test_forecast_weights_drift_away_from_the_final_posterior(switching_result):
    paths = _run_paths(switching_result, "none")
    frozen = paths["final_posterior_weights"]
    forecast_weights = paths["forecast_weights"]
    assert forecast_weights.shape == (len(LEADS), len(frozen))
    assert not np.array_equal(forecast_weights[-1], frozen)
    leading = int(np.argmax(frozen))
    assert forecast_weights[-1][leading] < frozen[leading]
    np.testing.assert_allclose(forecast_weights.sum(axis=1), 1.0, rtol=0.0, atol=1e-12)


# --------------------------------------------------------------------------- #
# frozen_weight_forecast: definition and validation
# --------------------------------------------------------------------------- #


def test_frozen_weight_forecast_is_the_weighted_sum():
    drift = importlib.import_module(DRIFT_MODULE)
    predictions = np.asarray([[1.0, 2.0, 4.0], [10.0, 20.0, 40.0]], dtype=np.float64)
    weights = np.asarray([0.5, 0.25, 0.25], dtype=np.float64)
    np.testing.assert_allclose(
        drift.frozen_weight_forecast(predictions, weights),
        np.asarray([0.5 + 0.5 + 1.0, 5.0 + 5.0 + 10.0]),
        rtol=0.0,
        atol=0.0,
    )


@pytest.mark.parametrize(
    "weights",
    [
        np.asarray([0.5, 0.25], dtype=np.float64),
        np.asarray([0.5, 0.6, -0.1], dtype=np.float64),
        np.asarray([0.5, 0.25, 0.10], dtype=np.float64),
    ],
)
def test_frozen_weight_forecast_rejects_invalid_weights(weights):
    drift = importlib.import_module(DRIFT_MODULE)
    predictions = np.asarray([[1.0, 2.0, 4.0]], dtype=np.float64)
    with pytest.raises(ValueError):
        drift.frozen_weight_forecast(predictions, weights)


# --------------------------------------------------------------------------- #
# Summarizer verdicts
# --------------------------------------------------------------------------- #


def _driver_stub(frozen_errors, drifting_errors):
    frozen_errors = np.asarray(frozen_errors, dtype=np.float64)
    drifting_errors = np.asarray(drifting_errors, dtype=np.float64)
    return {
        "leads": np.asarray(LEADS, dtype=np.int64),
        "methods": ("none", "full"),
        "squared_errors": {
            ("none", "frozen"): frozen_errors,
            ("none", "drifting"): drifting_errors,
            ("full", "frozen"): frozen_errors,
            ("full", "drifting"): drifting_errors,
        },
        "forecast_weights": {
            "none": np.zeros((frozen_errors.shape[0], frozen_errors.shape[1], len(LEADS), 3)),
            "full": np.zeros((frozen_errors.shape[0], frozen_errors.shape[1], len(LEADS), 3)),
        },
        "final_posterior_weights": {
            "none": np.zeros((frozen_errors.shape[0], frozen_errors.shape[1], 3)),
            "full": np.zeros((frozen_errors.shape[0], frozen_errors.shape[1], 3)),
        },
        "true_candidate_labels": np.zeros((frozen_errors.shape[1], ASSIM_DAYS), dtype=np.int64),
        "oracle_squared_errors": drifting_errors,
    }


def test_summarizer_calls_drift_harmful_when_frozen_is_uniformly_better():
    drift = importlib.import_module(DRIFT_MODULE)
    blocks, truths, leads = 8, 2, len(LEADS)
    drifting = np.full((blocks, truths, leads), 4.0)
    frozen = np.full((blocks, truths, leads), 1.0)
    summary = drift.summarize_forecast_weight_drift(
        _driver_stub(frozen, drifting), bootstrap_replicates=200, bootstrap_seed=7
    )
    assert summary["verdict"]["none"] == ["drift_harmful"] * leads


def test_summarizer_calls_drift_helpful_when_frozen_is_uniformly_worse():
    drift = importlib.import_module(DRIFT_MODULE)
    blocks, truths, leads = 8, 2, len(LEADS)
    drifting = np.full((blocks, truths, leads), 1.0)
    frozen = np.full((blocks, truths, leads), 4.0)
    summary = drift.summarize_forecast_weight_drift(
        _driver_stub(frozen, drifting), bootstrap_replicates=200, bootstrap_seed=7
    )
    assert summary["verdict"]["none"] == ["drift_helpful"] * leads


def test_summarizer_calls_not_significant_when_the_interval_spans_zero():
    drift = importlib.import_module(DRIFT_MODULE)
    blocks, truths, leads = 8, 2, len(LEADS)
    rng = np.random.default_rng(4242)
    drifting = rng.normal(10.0, 3.0, size=(blocks, truths, leads))
    frozen = drifting.copy()
    frozen[0] += 5.0
    frozen[1] -= 5.0
    summary = drift.summarize_forecast_weight_drift(
        _driver_stub(frozen, drifting), bootstrap_replicates=2000, bootstrap_seed=7
    )
    assert summary["verdict"]["none"] == ["not_significant"] * leads

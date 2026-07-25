"""Forecasts always freeze candidate probabilities after assimilation.

The model-switching transition matrix is an assimilation mechanism. During the
forecast horizon, the copied bank uses an identity transition matrix so that
the final posterior probabilities remain fixed and cross-candidate forecast
state mixing is absent. The input posterior bank remains unchanged.
"""

import inspect
import sys
from pathlib import Path

import numpy as np
import pytest

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "src"))

from hbv_joint_uncertainty.candidates import CandidateDefinition  # noqa: E402
from hbv_joint_uncertainty.imm import InteractingMultipleModel  # noqa: E402
from hbv_joint_uncertainty.preflight import CandidateBank  # noqa: E402
from hbv_joint_uncertainty.sigma_filter import ModifiedUnscentedFilter  # noqa: E402
from hbv_multilead_joint_uncertainty.forecast import forecast_from_posterior  # noqa: E402
from hbv_multilead_joint_uncertainty.interaction_value_comparison import (  # noqa: E402
    assimilate_family_arm,
    compare_interaction_arms,
    oracle_arm,
    static_mixing_arm,
)
from hbv_multilead_joint_uncertainty.three_stage_switching_validation import (  # noqa: E402
    _assimilate_record_then_forecast,
    run_three_stage_switching_validation,
)


LEADS = (1, 2, 3)


class ScalarForcingTransition:
    def __init__(self):
        self.value = None

    def set_forcing(self, rain, pet, temperature):
        del pet, temperature
        self.value = float(rain)

    def __call__(self, state):
        if self.value is None:
            raise RuntimeError("forcing is not set")
        return np.asarray(state, dtype=np.float64) + self.value


def _two_candidate_bank(
    states=(0.0, 10.0),
    probabilities=(0.8, 0.2),
    transition_matrix=((0.9, 0.1), (0.2, 0.8)),
    process_variance=0.2,
):
    """A bank whose non-identity matrix would make forecast drift observable.

    The forecast contract must ignore that matrix without mutating the bank.
    """
    transitions = (ScalarForcingTransition(), ScalarForcingTransition())
    filters = [
        ModifiedUnscentedFilter(
            state=np.array([state], dtype=np.float64),
            covariance=np.array([[0.01]], dtype=np.float64),
            transition=transition,
            observation=lambda values: np.asarray(values, dtype=np.float64),
            process_covariance=np.array([[process_variance]], dtype=np.float64),
            observation_covariance=np.array([[1e-6]], dtype=np.float64),
            alpha=0.5,
            beta=2.0,
            kappa=0.0,
        )
        for state, transition in zip(states, transitions)
    ]
    estimator = InteractingMultipleModel(
        filters=filters,
        transition_matrix=np.array(transition_matrix, dtype=np.float64),
        initial_probabilities=np.array(probabilities, dtype=np.float64),
        parameter_groups=["low", "high"],
    )
    definitions = tuple(
        CandidateDefinition(
            candidate_id=label,
            parameter_id=label,
            noise_variance_scale=1.0,
            parameters={},
            parameter_group=(float(index),),
        )
        for index, label in enumerate(("low", "high"))
    )
    return CandidateBank(estimator=estimator, transitions=transitions, definitions=definitions)


def _future(days=3):
    return np.zeros((days, 3), dtype=np.float64)


def test_forecast_holds_weights_at_the_origin_posterior():
    bank = _two_candidate_bank()
    origin = bank.estimator.probabilities.copy()

    result = forecast_from_posterior(bank, _future(), lead_days=LEADS)

    for row in range(len(LEADS)):
        np.testing.assert_allclose(result.probabilities[row], origin, rtol=0.0, atol=1e-12)


def test_forecast_removes_state_mixing_so_full_equals_none():
    full = forecast_from_posterior(
        _two_candidate_bank(), _future(), lead_days=LEADS, interaction_mode="full"
    )
    none = forecast_from_posterior(
        _two_candidate_bank(), _future(), lead_days=LEADS, interaction_mode="none"
    )

    np.testing.assert_array_equal(full.candidate_predictions, none.candidate_predictions)
    np.testing.assert_array_equal(full.combined_predictions, none.combined_predictions)
    np.testing.assert_array_equal(full.probabilities, none.probabilities)


def test_forecast_combined_equals_origin_weight_combination_of_candidate_paths():
    bank = _two_candidate_bank()
    origin = bank.estimator.probabilities.copy()

    result = forecast_from_posterior(
        bank, _future(), lead_days=LEADS, interaction_mode="full"
    )

    for row in range(len(LEADS)):
        expected = origin @ result.candidate_predictions[row]
        np.testing.assert_allclose(result.combined_predictions[row], expected, rtol=0.0, atol=1e-12)


@pytest.mark.parametrize(
    "function",
    (
        forecast_from_posterior,
        _assimilate_record_then_forecast,
        run_three_stage_switching_validation,
        assimilate_family_arm,
        static_mixing_arm,
        oracle_arm,
        compare_interaction_arms,
    ),
)
def test_forecast_transition_parameter_is_absent(function):
    assert "forecast_transition" not in inspect.signature(function).parameters


def test_removed_forecast_transition_keyword_is_rejected():
    with pytest.raises(TypeError, match="forecast_transition"):
        forecast_from_posterior(
            _two_candidate_bank(), _future(), lead_days=LEADS, forecast_transition="markov"
        )


def test_forecast_does_not_mutate_the_input_bank_transition_matrix():
    bank = _two_candidate_bank()
    before = bank.estimator.transition_matrix.copy()

    forecast_from_posterior(bank, _future(), lead_days=LEADS)

    np.testing.assert_array_equal(bank.estimator.transition_matrix, before)

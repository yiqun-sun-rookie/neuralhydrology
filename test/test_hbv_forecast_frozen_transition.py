"""Forecast-phase transition modes: markov (default, drift) vs frozen (no P).

The ``frozen`` mode carries the user's methodological line: during the forecast
horizon the model-switching matrix P must NOT be applied. Holding the forecast
transition at the identity matrix (a) freezes the model probabilities at the
final assimilation posterior and (b) removes forecast-phase state mixing, which
is exactly "do not use P in the forecast" for every interaction mode. The default
``markov`` mode reproduces the historical drifting behaviour bit-for-bit so no
sealed experiment moves.
"""

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
    """A two-candidate bank with distinct states and a non-identity transition.

    Distinct states make forecast-phase state mixing observable; the non-identity
    transition makes the markov weight drift observable.
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


def test_frozen_holds_weights_at_the_origin_posterior():
    bank = _two_candidate_bank()
    origin = bank.estimator.probabilities.copy()

    result = forecast_from_posterior(bank, _future(), lead_days=LEADS, forecast_transition="frozen")

    for row in range(len(LEADS)):
        np.testing.assert_allclose(result.probabilities[row], origin, rtol=0.0, atol=1e-12)


def test_markov_forecast_drifts_weights_away_from_the_origin():
    bank = _two_candidate_bank()
    origin = bank.estimator.probabilities.copy()

    result = forecast_from_posterior(bank, _future(), lead_days=LEADS, forecast_transition="markov")

    assert not np.allclose(result.probabilities[0], origin, atol=1e-6)


def test_default_forecast_transition_reproduces_markov_bit_for_bit():
    default = forecast_from_posterior(_two_candidate_bank(), _future(), lead_days=LEADS)
    markov = forecast_from_posterior(
        _two_candidate_bank(), _future(), lead_days=LEADS, forecast_transition="markov"
    )

    np.testing.assert_array_equal(default.combined_predictions, markov.combined_predictions)
    np.testing.assert_array_equal(default.probabilities, markov.probabilities)
    np.testing.assert_array_equal(default.candidate_predictions, markov.candidate_predictions)


def test_frozen_removes_forecast_state_mixing_so_full_equals_none():
    full_frozen = forecast_from_posterior(
        _two_candidate_bank(), _future(), lead_days=LEADS,
        interaction_mode="full", forecast_transition="frozen",
    )
    none_frozen = forecast_from_posterior(
        _two_candidate_bank(), _future(), lead_days=LEADS,
        interaction_mode="none", forecast_transition="frozen",
    )

    np.testing.assert_array_equal(full_frozen.candidate_predictions, none_frozen.candidate_predictions)
    np.testing.assert_array_equal(full_frozen.combined_predictions, none_frozen.combined_predictions)
    np.testing.assert_array_equal(full_frozen.probabilities, none_frozen.probabilities)


def test_frozen_combined_equals_frozen_weight_combination_of_candidate_paths():
    bank = _two_candidate_bank()
    origin = bank.estimator.probabilities.copy()

    result = forecast_from_posterior(
        bank, _future(), lead_days=LEADS,
        interaction_mode="full", forecast_transition="frozen",
    )

    for row in range(len(LEADS)):
        expected = origin @ result.candidate_predictions[row]
        np.testing.assert_allclose(result.combined_predictions[row], expected, rtol=0.0, atol=1e-12)


def test_markov_full_differs_from_frozen_full_when_candidates_diverge():
    # Under linear dynamics the mixture mean is conserved, so the observable effect of
    # the flag is on the individual candidate paths (markov mixes them, frozen does not)
    # and on the model probabilities (markov drifts them, frozen holds them).
    markov = forecast_from_posterior(
        _two_candidate_bank(), _future(), lead_days=LEADS,
        interaction_mode="full", forecast_transition="markov",
    )
    frozen = forecast_from_posterior(
        _two_candidate_bank(), _future(), lead_days=LEADS,
        interaction_mode="full", forecast_transition="frozen",
    )

    assert not np.allclose(markov.candidate_predictions, frozen.candidate_predictions, atol=1e-9)
    assert not np.allclose(markov.probabilities, frozen.probabilities, atol=1e-9)


def test_invalid_forecast_transition_is_rejected():
    with pytest.raises(ValueError, match="forecast_transition"):
        forecast_from_posterior(
            _two_candidate_bank(), _future(), lead_days=LEADS, forecast_transition="bogus"
        )


def test_frozen_forecast_does_not_mutate_the_input_bank_transition_matrix():
    bank = _two_candidate_bank()
    before = bank.estimator.transition_matrix.copy()

    forecast_from_posterior(bank, _future(), lead_days=LEADS, forecast_transition="frozen")

    np.testing.assert_array_equal(bank.estimator.transition_matrix, before)

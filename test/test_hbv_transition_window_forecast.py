"""Tests for forecasts issued at fixed post-switch origins."""

from __future__ import annotations

import numpy as np
import pytest

from hbv_joint_uncertainty.candidates import CandidateDefinition
from hbv_joint_uncertainty.imm import InteractingMultipleModel
from hbv_joint_uncertainty.preflight import CandidateBank
from hbv_joint_uncertainty.sigma_filter import ModifiedUnscentedFilter
from hbv_multilead_joint_uncertainty.forecast import (
    run_multilead_assimilation,
)
from hbv_multilead_joint_uncertainty.transition_window_forecast import (
    collect_forecasts_at_origins,
    post_switch_origins,
)


class _ScalarTransition:
    def __init__(self):
        self.value = None

    def set_forcing(self, rain, pet, temperature):
        del pet, temperature
        self.value = float(rain)

    def __call__(self, state):
        return np.asarray(state, dtype=np.float64) + self.value


def _bank():
    transition = _ScalarTransition()
    sigma_filter = ModifiedUnscentedFilter(
        state=np.asarray([0.0]),
        covariance=np.asarray([[0.1]]),
        transition=transition,
        observation=lambda state: np.asarray(state, dtype=np.float64),
        process_covariance=np.zeros((1, 1)),
        observation_covariance=np.asarray([[0.01]]),
        alpha=0.5,
        beta=2.0,
        kappa=0.0,
    )
    estimator = InteractingMultipleModel(
        filters=[sigma_filter],
        transition_matrix=np.ones((1, 1)),
        initial_probabilities=np.ones(1),
        parameter_groups=["only"],
    )
    definition = CandidateDefinition(
        candidate_id="only",
        parameter_id="only",
        noise_variance_scale=1.0,
        parameters={},
        parameter_group=(0.0,),
    )
    return CandidateBank(
        estimator=estimator,
        transitions=(transition,),
        definitions=(definition,),
    )


def test_post_switch_origins_use_exact_first_seven_days():
    origins = post_switch_origins(
        switch_days=(180, 360),
        offsets=tuple(range(7)),
        crosscheck_origin=539,
    )

    np.testing.assert_array_equal(
        origins,
        [*range(180, 187), *range(360, 367), 539],
    )
    assert not origins.flags.writeable


def test_origin_collector_matches_full_runner_and_does_not_mutate_bank():
    forcing = np.column_stack(
        (
            np.linspace(0.1, 2.0, 20),
            np.zeros(20),
            np.zeros(20),
        )
    )
    observations = np.linspace(0.2, 4.0, 20)
    bank = _bank()
    state_before = bank.estimator.filters[0].state.copy()
    covariance_before = bank.estimator.filters[0].covariance.copy()
    probability_before = bank.estimator.probabilities.copy()

    selected = collect_forecasts_at_origins(
        forcing=forcing,
        observations=observations,
        bank=bank,
        origin_indices=(2, 5, 9),
        lead_days=(1, 3, 7),
    )
    full = run_multilead_assimilation(
        forcing=forcing,
        observations=observations,
        bank=_bank(),
        lead_days=(1, 3, 7),
    )
    rows = np.searchsorted(full.origin_indices, selected.origin_indices)

    np.testing.assert_array_equal(
        selected.target_indices,
        full.target_indices[rows],
    )
    np.testing.assert_allclose(
        selected.predictions,
        full.predictions[rows],
        rtol=0.0,
        atol=0.0,
    )
    np.testing.assert_allclose(
        selected.candidate_predictions,
        full.candidate_predictions[rows],
        rtol=0.0,
        atol=0.0,
    )
    np.testing.assert_allclose(
        selected.probabilities,
        full.probabilities[rows],
        rtol=0.0,
        atol=0.0,
    )
    np.testing.assert_array_equal(bank.estimator.filters[0].state, state_before)
    np.testing.assert_array_equal(
        bank.estimator.filters[0].covariance,
        covariance_before,
    )
    np.testing.assert_array_equal(
        bank.estimator.probabilities,
        probability_before,
    )


def test_future_observations_cannot_change_collected_forecasts():
    forcing = np.column_stack(
        (np.ones(20), np.zeros(20), np.zeros(20))
    )
    observations = np.arange(20, dtype=np.float64)
    baseline = collect_forecasts_at_origins(
        forcing,
        observations,
        _bank(),
        origin_indices=(2, 5, 9),
    )
    changed = observations.copy()
    changed[10:] = 1e12

    result = collect_forecasts_at_origins(
        forcing,
        changed,
        _bank(),
        origin_indices=(2, 5, 9),
    )

    np.testing.assert_array_equal(result.predictions, baseline.predictions)
    np.testing.assert_array_equal(
        result.candidate_predictions,
        baseline.candidate_predictions,
    )
    np.testing.assert_array_equal(result.probabilities, baseline.probabilities)


@pytest.mark.parametrize(
    ("origins", "match"),
    [
        ((2, 2), "strictly increasing"),
        ((5, 2), "strictly increasing"),
        ((-1, 2), "nonnegative"),
        ((2, 13), "cover"),
    ],
)
def test_invalid_origins_are_rejected(origins, match):
    forcing = np.ones((20, 3))
    observations = np.ones(20)

    with pytest.raises(ValueError, match=match):
        collect_forecasts_at_origins(
            forcing,
            observations,
            _bank(),
            origin_indices=origins,
        )

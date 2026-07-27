"""Tests for rolling candidate forecast-skill readout."""

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
from hbv_multilead_joint_uncertainty.predictive_skill_readout import (
    collect_recent_candidate_hindcasts,
    required_hindcast_origins,
    rolling_predictive_skill_readout,
)


def _case(window=3):
    leads = np.asarray([1, 3, 7], dtype=np.int64)
    origins = np.arange(0, 12, dtype=np.int64)
    targets = origins[:, None] + leads
    candidates = np.zeros((len(origins), len(leads), 3))
    observations = np.arange(30, dtype=np.float64)
    for row, origin in enumerate(origins):
        candidates[row, 0] = observations[origin + 1] + [0.0, 1.0, 2.0]
        candidates[row, 1] = observations[origin + 3] + [3.0, 0.0, 1.0]
        candidates[row, 2] = observations[origin + 7] + [2.0, 1.0, 0.0]
    final_candidates = np.asarray(
        [
            [10.0, 20.0, 30.0],
            [40.0, 50.0, 60.0],
            [70.0, 80.0, 90.0],
        ]
    )
    final_probabilities = np.asarray([0.2, 0.3, 0.5])
    return {
        "origin_indices": origins,
        "target_indices": targets,
        "historical_candidate_predictions": candidates,
        "observations": observations,
        "final_candidate_predictions": final_candidates,
        "final_probabilities": final_probabilities,
        "final_origin_index": 11,
        "lead_days": leads,
        "window": window,
    }


class _ScalarTransition:
    def __init__(self):
        self.value = None

    def set_forcing(self, rain, pet, temperature):
        del pet, temperature
        self.value = float(rain)

    def __call__(self, state):
        return np.asarray(state, dtype=np.float64) + self.value


def _scalar_bank():
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


def test_required_origins_are_exact_for_three_and_seven_day_scores():
    origins = required_hindcast_origins(
        final_origin_index=539,
        lead_days=(1, 3, 7),
        window=30,
    )

    np.testing.assert_array_equal(
        origins,
        np.asarray([*range(503, 537), 539]),
    )
    assert not origins.flags.writeable


def test_recent_hindcasts_match_full_origin_runner_and_do_not_mutate_bank():
    forcing = np.column_stack(
        (
            np.linspace(0.1, 1.7, 17),
            np.zeros(17),
            np.zeros(17),
        )
    )
    observations = np.linspace(0.2, 3.4, 17)
    bank = _scalar_bank()
    state_before = bank.estimator.filters[0].state.copy()
    covariance_before = bank.estimator.filters[0].covariance.copy()
    probability_before = bank.estimator.probabilities.copy()

    recent = collect_recent_candidate_hindcasts(
        forcing=forcing,
        observations=observations,
        bank=bank,
        final_origin_index=9,
        lead_days=(1, 3, 7),
        window=2,
    )
    full = run_multilead_assimilation(
        forcing=forcing,
        observations=observations,
        bank=_scalar_bank(),
        lead_days=(1, 3, 7),
    )
    rows = np.searchsorted(full.origin_indices, recent.origin_indices)

    np.testing.assert_array_equal(
        recent.origin_indices,
        [1, 2, 5, 6, 9],
    )
    np.testing.assert_array_equal(
        recent.target_indices,
        full.target_indices[rows],
    )
    np.testing.assert_allclose(
        recent.candidate_predictions,
        full.candidate_predictions[rows],
        rtol=0.0,
        atol=0.0,
    )
    np.testing.assert_allclose(
        recent.final_probabilities,
        full.probabilities[-1, 0],
        rtol=0.0,
        atol=0.0,
    )
    np.testing.assert_array_equal(
        bank.estimator.filters[0].state,
        state_before,
    )
    np.testing.assert_array_equal(
        bank.estimator.filters[0].covariance,
        covariance_before,
    )
    np.testing.assert_array_equal(
        bank.estimator.probabilities,
        probability_before,
    )


def test_readout_preserves_one_day_and_selects_skill_by_lead():
    case = _case()

    result = rolling_predictive_skill_readout(**case)

    np.testing.assert_allclose(result.predictions, [23.0, 50.0, 90.0])
    np.testing.assert_array_equal(
        result.selected_candidate_indices,
        [-1, 1, 2],
    )
    np.testing.assert_allclose(
        result.weights,
        [
            [0.2, 0.3, 0.5],
            [0.0, 1.0, 0.0],
            [0.0, 0.0, 1.0],
        ],
    )
    assert np.isnan(result.historical_mean_squared_errors[0]).all()
    np.testing.assert_allclose(
        result.historical_mean_squared_errors[1],
        [9.0, 0.0, 1.0],
    )
    np.testing.assert_allclose(
        result.historical_mean_squared_errors[2],
        [4.0, 1.0, 0.0],
    )


def test_readout_uses_only_the_latest_completed_window():
    case = _case(window=3)
    predictions = case["historical_candidate_predictions"]
    predictions[:5, 1, 0] = (
        case["observations"][case["target_indices"][:5, 1]] + 100.0
    )
    predictions[6:9, 1, 0] = case["observations"][
        case["target_indices"][6:9, 1]
    ]
    predictions[6:9, 1, 1] += 5.0

    result = rolling_predictive_skill_readout(**case)

    assert result.selected_candidate_indices[1] == 0
    np.testing.assert_array_equal(
        result.history_origin_indices[1],
        [6, 7, 8],
    )


def test_future_observations_cannot_change_readout():
    case = _case()
    baseline = rolling_predictive_skill_readout(**case)
    changed = dict(case)
    changed_observations = case["observations"].copy()
    changed_observations[12:] = 1e12
    changed["observations"] = changed_observations

    result = rolling_predictive_skill_readout(**changed)

    np.testing.assert_array_equal(result.predictions, baseline.predictions)
    np.testing.assert_array_equal(
        result.historical_mean_squared_errors,
        baseline.historical_mean_squared_errors,
    )


def test_ties_choose_the_first_candidate():
    case = _case()
    targets = case["target_indices"]
    observations = case["observations"]
    case["historical_candidate_predictions"][:, 1, 0] = observations[
        targets[:, 1]
    ]
    case["historical_candidate_predictions"][:, 1, 1] = observations[
        targets[:, 1]
    ]

    result = rolling_predictive_skill_readout(**case)

    assert result.selected_candidate_indices[1] == 0


def test_inputs_and_outputs_are_not_mutated_or_writeable():
    case = _case()
    snapshots = {
        key: value.copy()
        for key, value in case.items()
        if isinstance(value, np.ndarray)
    }

    result = rolling_predictive_skill_readout(**case)

    for key, expected in snapshots.items():
        np.testing.assert_array_equal(case[key], expected)
    for value in (
        result.lead_days,
        result.predictions,
        result.weights,
        result.historical_mean_squared_errors,
        result.selected_candidate_indices,
        result.history_origin_indices,
    ):
        assert not value.flags.writeable


def test_insufficient_completed_history_is_rejected():
    case = _case(window=6)

    with pytest.raises(ValueError, match="completed"):
        rolling_predictive_skill_readout(**case)


@pytest.mark.parametrize(
    ("mutation", "match"),
    [
        (
            lambda case: case.__setitem__(
                "origin_indices",
                case["origin_indices"].astype(np.float64),
            ),
            "origin indices",
        ),
        (
            lambda case: case["target_indices"].__setitem__((0, 1), 99),
            "target indices",
        ),
        (
            lambda case: case["historical_candidate_predictions"].__setitem__(
                (0, 0, 0),
                np.nan,
            ),
            "finite",
        ),
        (
            lambda case: case["final_probabilities"].__setitem__(0, -0.1),
            "probabilities",
        ),
        (
            lambda case: case.__setitem__("lead_days", [1, 2, 7]),
            "1, 3, and 7",
        ),
    ],
)
def test_invalid_contracts_are_rejected(mutation, match):
    case = _case()
    mutation(case)

    with pytest.raises(ValueError, match=match):
        rolling_predictive_skill_readout(**case)

import sys
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import pytest


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "src"))

from hbv_joint_uncertainty.candidates import CandidateDefinition  # noqa: E402
from hbv_joint_uncertainty.imm import InteractingMultipleModel  # noqa: E402
from hbv_joint_uncertainty.preflight import CandidateBank  # noqa: E402
from hbv_joint_uncertainty.sigma_filter import ModifiedUnscentedFilter  # noqa: E402
from hbv_multilead_joint_uncertainty.forecast import (  # noqa: E402
    forecast_from_posterior,
    origin_target_indices,
    run_multilead_assimilation,
)


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


@dataclass(frozen=True)
class ScalarBankFixture:
    bank: CandidateBank
    transition: ScalarForcingTransition


def _scalar_bank(state=10.0, process_variance=0.0, observation_variance=1e-6):
    transition = ScalarForcingTransition()
    sigma_filter = ModifiedUnscentedFilter(
        state=np.array([state], dtype=np.float64),
        covariance=np.array([[0.01]], dtype=np.float64),
        transition=transition,
        observation=lambda values: np.asarray(values, dtype=np.float64),
        process_covariance=np.array([[process_variance]], dtype=np.float64),
        observation_covariance=np.array([[observation_variance]], dtype=np.float64),
        alpha=0.5,
        beta=2.0,
        kappa=0.0,
    )
    estimator = InteractingMultipleModel(
        filters=[sigma_filter],
        transition_matrix=np.ones((1, 1), dtype=np.float64),
        initial_probabilities=np.ones(1, dtype=np.float64),
        parameter_groups=["only"],
    )
    definition = CandidateDefinition(
        candidate_id="only",
        parameter_id="only",
        noise_variance_scale=1.0,
        parameters={},
        parameter_group=(0.0,),
    )
    return ScalarBankFixture(
        bank=CandidateBank(estimator=estimator, transitions=(transition,), definitions=(definition,)),
        transition=transition,
    )


def _two_parameter_group_identity_bank():
    transitions = (ScalarForcingTransition(), ScalarForcingTransition())
    filters = [
        ModifiedUnscentedFilter(
            state=np.array([state], dtype=np.float64),
            covariance=np.array([[0.01]], dtype=np.float64),
            transition=transition,
            observation=lambda values: np.asarray(values, dtype=np.float64),
            process_covariance=np.zeros((1, 1), dtype=np.float64),
            observation_covariance=np.array([[1e-6]], dtype=np.float64),
            alpha=0.5,
            beta=2.0,
            kappa=0.0,
        )
        for state, transition in zip((0.0, 10.0), transitions)
    ]
    estimator = InteractingMultipleModel(
        filters=filters,
        transition_matrix=np.array([[0.9, 0.1], [0.2, 0.8]], dtype=np.float64),
        initial_probabilities=np.array([0.8, 0.2], dtype=np.float64),
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


def test_common_origins_align_one_three_and_seven_day_targets():
    origins, targets = origin_target_indices(n_days=10, lead_days=(1, 3, 7))

    np.testing.assert_array_equal(origins, np.array([0, 1, 2]))
    np.testing.assert_array_equal(
        targets,
        np.array(
            [
                [1, 3, 7],
                [2, 4, 8],
                [3, 5, 9],
            ]
        ),
    )


@pytest.mark.parametrize("leads", [(), (0,), (1, 1), (3, 1), (8,)])
def test_origin_target_indices_reject_invalid_leads(leads):
    with pytest.raises(ValueError):
        origin_target_indices(n_days=8, lead_days=leads)


def test_forecast_starts_from_posterior_and_uses_forcing_t_plus_one():
    fixture = _scalar_bank(state=10.0)
    future = np.column_stack(
        (
            np.arange(1.0, 8.0),
            np.zeros(7),
            np.zeros(7),
        )
    )

    result = forecast_from_posterior(fixture.bank, future, lead_days=(1, 3, 7))

    np.testing.assert_allclose(result.combined_predictions, np.array([11.0, 16.0, 38.0]), atol=1e-12)
    np.testing.assert_allclose(result.candidate_predictions[:, 0], result.combined_predictions, atol=1e-12)
    np.testing.assert_allclose(result.probabilities, np.ones((3, 1)), atol=1e-12)


def test_forecast_branch_does_not_mutate_continuing_filter_bank():
    fixture = _scalar_bank(state=10.0, process_variance=0.2)
    state_before = fixture.bank.estimator.filters[0].state.copy()
    covariance_before = fixture.bank.estimator.filters[0].covariance.copy()
    probabilities_before = fixture.bank.estimator.probabilities.copy()
    future = np.column_stack((np.ones(7), np.zeros(7), np.zeros(7)))

    forecast_from_posterior(fixture.bank, future, lead_days=(1, 3, 7))

    np.testing.assert_array_equal(fixture.bank.estimator.filters[0].state, state_before)
    np.testing.assert_array_equal(fixture.bank.estimator.filters[0].covariance, covariance_before)
    np.testing.assert_array_equal(fixture.bank.estimator.probabilities, probabilities_before)


def test_forecast_rejects_a_filter_bank_with_an_unupdated_prior():
    fixture = _scalar_bank(state=10.0)
    fixture.transition.set_forcing(0.0, 0.0, 0.0)
    fixture.bank.estimator.filters[0].predict()

    with pytest.raises(RuntimeError, match="posterior"):
        forecast_from_posterior(fixture.bank, np.zeros((1, 3)), lead_days=(1,))


def test_full_interaction_preserves_mixture_mean_under_identity_dynamics():
    bank = _two_parameter_group_identity_bank()
    future = np.zeros((3, 3), dtype=np.float64)

    result = forecast_from_posterior(bank, future, lead_days=(1, 2, 3))

    np.testing.assert_allclose(result.combined_predictions, np.full(3, 2.0), rtol=0.0, atol=1e-12)


def test_process_covariance_is_added_once_per_forecast_day():
    fixture = _scalar_bank(state=10.0, process_variance=0.2)

    result = forecast_from_posterior(fixture.bank, np.zeros((3, 3)), lead_days=(1, 2, 3))

    np.testing.assert_allclose(
        result.candidate_covariance_diagonals[:, 0, 0],
        np.array([0.21, 0.41, 0.61]),
        rtol=0.0,
        atol=1e-10,
    )


def test_future_discharge_cannot_change_an_already_issued_forecast():
    forcing = np.column_stack((np.arange(1.0, 11.0), np.zeros(10), np.zeros(10)))
    observations = np.arange(1.0, 11.0)
    changed_future = observations.copy()
    changed_future[1:] += 1000.0

    original = run_multilead_assimilation(
        forcing=forcing,
        observations=observations,
        bank=_scalar_bank(state=0.0).bank,
        lead_days=(1, 3, 7),
    )
    perturbed = run_multilead_assimilation(
        forcing=forcing,
        observations=changed_future,
        bank=_scalar_bank(state=0.0).bank,
        lead_days=(1, 3, 7),
    )

    np.testing.assert_array_equal(original.origin_indices, perturbed.origin_indices)
    np.testing.assert_array_equal(original.target_indices, perturbed.target_indices)
    np.testing.assert_allclose(original.predictions[0], perturbed.predictions[0], rtol=0.0, atol=0.0)


def test_every_issued_forecast_is_invariant_to_later_discharge():
    forcing = np.column_stack((np.arange(1.0, 11.0), np.zeros(10), np.zeros(10)))
    observations = np.arange(1.0, 11.0)
    reference = run_multilead_assimilation(
        forcing=forcing,
        observations=observations,
        bank=_scalar_bank(state=0.0).bank,
        lead_days=(1, 3, 7),
    )
    for row, origin in enumerate(reference.origin_indices):
        perturbed_observations = observations.copy()
        perturbed_observations[origin + 1:] += 1000.0
        perturbed = run_multilead_assimilation(
            forcing=forcing,
            observations=perturbed_observations,
            bank=_scalar_bank(state=0.0).bank,
            lead_days=(1, 3, 7),
        )
        np.testing.assert_allclose(reference.predictions[row], perturbed.predictions[row], rtol=0.0, atol=0.0)


def test_unread_future_discharge_availability_cannot_block_forecasts():
    forcing = np.column_stack((np.arange(1.0, 11.0), np.zeros(10), np.zeros(10)))
    observations = np.arange(1.0, 11.0)
    unavailable_future = observations.copy()
    unavailable_future[-7:] = np.nan

    reference = run_multilead_assimilation(
        forcing=forcing,
        observations=observations,
        bank=_scalar_bank(state=0.0).bank,
        lead_days=(1, 3, 7),
    )
    result = run_multilead_assimilation(
        forcing=forcing,
        observations=unavailable_future,
        bank=_scalar_bank(state=0.0).bank,
        lead_days=(1, 3, 7),
    )

    np.testing.assert_allclose(result.predictions, reference.predictions, rtol=0.0, atol=0.0)


def test_assimilation_forecasts_have_common_origins_and_do_not_contain_target_flow():
    forcing = np.column_stack((np.ones(10), np.zeros(10), np.zeros(10)))
    observations = np.arange(10, dtype=np.float64)

    result = run_multilead_assimilation(
        forcing=forcing,
        observations=observations,
        bank=_scalar_bank(state=0.0).bank,
        lead_days=(1, 3, 7),
    )

    assert result.predictions.shape == (3, 3)
    assert result.candidate_predictions.shape == (3, 3, 1)
    assert result.probabilities.shape == (3, 3, 1)
    assert result.candidate_covariance_diagonals.shape == (3, 3, 1, 1)
    np.testing.assert_array_equal(result.origin_indices, np.array([0, 1, 2]))
    np.testing.assert_array_equal(result.target_indices[0], np.array([1, 3, 7]))
    assert np.all(np.isfinite(result.predictions))

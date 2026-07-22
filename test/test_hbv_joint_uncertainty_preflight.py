import sys
from pathlib import Path

import numpy as np
import pandas as pd
import pytest


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "src"))

from hbv_joint_uncertainty.candidates import (  # noqa: E402
    build_candidate_definitions,
    extract_center_parameters,
    load_preflight_config,
    load_trained_parameter_table,
)
from hbv_joint_uncertainty.hbv_adapter import STATE_NAMES, initial_state_vector  # noqa: E402
from hbv_joint_uncertainty.preflight import (  # noqa: E402
    build_candidate_bank,
    build_process_covariance,
    build_transition_matrix,
    project_hbv_state,
    run_assimilation,
    run_basin_preflight,
    warm_parameter_states,
)


@pytest.fixture(scope="module")
def frozen_case():
    config = load_preflight_config(REPO_ROOT)
    table = load_trained_parameter_table(config, REPO_ROOT)
    center = extract_center_parameters(table, "12375900")
    candidates = build_candidate_definitions(center, config)
    return config, candidates


def test_hbv_state_projection_enforces_all_physical_ranges(frozen_case):
    _, candidates = frozen_case
    parameters = candidates[0].parameters
    raw = np.array([-2.0, 500.0, -8.0, -4.0, -3.0, *([-1.0] * 10)])
    projected = project_hbv_state(raw, parameters)

    assert projected.shape == (len(STATE_NAMES),)
    assert projected[0] == 0.0
    assert projected[1] == 0.0
    assert projected[2] == pytest.approx(1e-5)
    assert projected[3] == 0.0
    assert projected[4] == 0.0
    np.testing.assert_array_equal(projected[5:], np.zeros(10))

    high = project_hbv_state(np.full(15, 1e9), parameters)
    assert high[1] == pytest.approx(parameters["parCWH"] * high[0])
    assert high[2] == pytest.approx(parameters["parFC"])


def test_process_covariance_has_noise_only_on_five_hydrologic_states(frozen_case):
    _, candidates = frozen_case
    small = build_process_covariance(candidates[0].parameters, 1e-5)
    large = build_process_covariance(candidates[0].parameters, 1e-3)

    assert small.shape == (15, 15)
    assert np.all(np.diag(small)[:5] > 0.0)
    np.testing.assert_array_equal(small[5:, :], np.zeros((10, 15)))
    np.testing.assert_array_equal(small[:, 5:], np.zeros((15, 10)))
    np.testing.assert_allclose(large[:5, :5], 100.0 * small[:5, :5], rtol=1e-14, atol=0.0)


def test_nine_candidate_transition_matrix_matches_frozen_probabilities():
    matrix = build_transition_matrix(9, diagonal=0.98)
    np.testing.assert_allclose(np.diag(matrix), np.full(9, 0.98), rtol=0.0, atol=0.0)
    np.testing.assert_allclose(matrix[~np.eye(9, dtype=bool)], np.full(72, 0.0025), rtol=0.0, atol=1e-16)
    np.testing.assert_allclose(matrix.sum(axis=1), np.ones(9), rtol=0.0, atol=1e-15)


def test_candidate_bank_has_nine_fifteen_state_filters_and_thirty_one_sigma_points(frozen_case):
    config, candidates = frozen_case
    states = {
        candidate.parameter_id: initial_state_vector(candidate.parameters)
        for candidate in candidates
    }
    bank = build_candidate_bank(candidates, states, config)

    assert len(bank.estimator.filters) == 9
    assert len(bank.transitions) == 9
    assert all(candidate.n_state == 15 for candidate in bank.estimator.filters)
    assert all(candidate.sigma_generator.count == 31 for candidate in bank.estimator.filters)
    assert len(set(bank.estimator.parameter_groups)) == 3


def test_short_joint_assimilation_is_finite_physical_and_probability_normalized(frozen_case):
    config, candidates = frozen_case
    states = {
        candidate.parameter_id: initial_state_vector(candidate.parameters)
        for candidate in candidates
    }
    bank = build_candidate_bank(candidates, states, config)
    result = run_assimilation(
        rain=np.array([4.0, 0.0, 12.0, 1.0]),
        pet=np.array([1.0, 1.5, 1.2, 0.8]),
        temp=np.array([-1.0, 2.0, 5.0, 0.0]),
        observations=np.array([0.4, 0.7, 1.1, 0.8]),
        bank=bank,
    )

    assert result.prior_discharge.shape == (4,)
    assert result.candidate_prior_discharge.shape == (4, 9)
    assert result.prior_probabilities.shape == (4, 9)
    assert result.posterior_probabilities.shape == (4, 9)
    assert result.combined_states.shape == (4, 15)
    assert np.all(np.isfinite(result.prior_discharge))
    assert np.all(np.isfinite(result.candidate_prior_discharge))
    assert np.all(np.isfinite(result.prior_probabilities))
    assert np.all(np.isfinite(result.posterior_probabilities))
    assert np.all(result.posterior_probabilities >= 0.0)
    assert np.all(result.prior_probabilities >= 0.0)
    assert np.max(np.abs(result.prior_probabilities.sum(axis=1) - 1.0)) <= 1e-12
    assert np.max(np.abs(result.posterior_probabilities.sum(axis=1) - 1.0)) <= 1e-12
    assert np.all(result.combined_states >= 0.0)


def test_each_unique_parameter_vector_warmup_matches_authoritative_model_within_one_e_minus_eight(frozen_case):
    _, candidates = frozen_case
    states, audits = warm_parameter_states(
        rain=np.array([2.0, 0.0, 8.0, 1.0, 0.0]),
        pet=np.array([1.0, 1.5, 1.2, 0.8, 0.7]),
        temp=np.array([-2.0, 1.0, 4.0, 0.0, 3.0]),
        definitions=candidates,
        tolerance=1e-8,
    )

    assert set(states) == {candidate.parameter_id for candidate in candidates}
    assert len(audits) == 3
    assert max(audit.maximum_discharge_error for audit in audits) <= 1e-8
    assert max(audit.maximum_final_store_error for audit in audits) <= 1e-8


def test_warmup_equivalence_gate_rejects_independently_injected_mismatch(frozen_case):
    _, candidates = frozen_case

    def mismatching_simulator(rain, pet, temp, parameters):
        discharge = np.full(len(rain), 999.0)
        final_state = {
            "SNOWPACK": 0.0,
            "MELTWATER": 0.0,
            "SM": 1.0,
            "SUZ": 1.0,
            "SLZ": 1.0,
        }
        return discharge, final_state

    with pytest.raises(ValueError, match="adapter equivalence"):
        warm_parameter_states(
            rain=np.array([1.0, 0.0]),
            pet=np.array([0.5, 0.5]),
            temp=np.array([2.0, 2.0]),
            definitions=candidates,
            tolerance=1e-8,
            authoritative_simulator=mismatching_simulator,
        )


def test_warmup_gate_rejects_forcing_that_disagrees_with_saved_trained_state(frozen_case):
    _, candidates = frozen_case
    with pytest.raises(ValueError, match="saved warmup state"):
        warm_parameter_states(
            rain=np.zeros(3),
            pet=np.zeros(3),
            temp=np.zeros(3),
            definitions=candidates,
            tolerance=1e-8,
            expected_final_stores={"trained_center": np.full(5, 999.0)},
        )


def _short_config(config):
    result = dict(config)
    result.update(
        {
            "warmup_start": "1989-09-28",
            "warmup_end": "1989-09-30",
            "evaluation_start": "1989-10-01",
            "evaluation_end": "1989-10-04",
        }
    )
    return result


def _fake_loader(missing_observation=False):
    def load(basin_id, data_root, start_date, end_date, forcing, pet_method, keep_obs_nan_days):
        index = pd.date_range(start_date, end_date, freq="D")
        forcing_table = pd.DataFrame(
            {
                "prcp": np.linspace(0.0, 4.0, len(index)),
                "ep": np.full(len(index), 1.0),
                "tmean": np.full(len(index), 2.0),
            },
            index=index,
        )
        observations = pd.Series(np.linspace(0.5, 1.5, len(index)), index=index)
        if missing_observation and start_date == "1989-10-01":
            observations.iloc[1] = np.nan
        assert forcing == "maurer"
        assert pet_method == "priestley_taylor"
        assert keep_obs_nan_days is True
        return forcing_table, observations, 100.0

    return load


def test_basin_runner_enforces_contiguous_period_and_monitors_start_and_finish(frozen_case):
    config, candidates = frozen_case
    events = []
    result = run_basin_preflight(
        basin_id="12375900",
        definitions=candidates,
        config=_short_config(config),
        repo_root=REPO_ROOT,
        data_loader=_fake_loader(),
        monitor_callback=lambda completed, total: events.append((completed, total)),
    )

    assert result.basin_id == "12375900"
    assert result.dates.tolist() == ["1989-10-01", "1989-10-02", "1989-10-03", "1989-10-04"]
    assert events[0] == (0, 4)
    assert events[-1] == (4, 4)
    assert len(result.warmup_audits) == 3


def test_basin_runner_rejects_missing_evaluation_observation(frozen_case):
    config, candidates = frozen_case
    with pytest.raises(ValueError, match="missing evaluation observation"):
        run_basin_preflight(
            basin_id="12375900",
            definitions=candidates,
            config=_short_config(config),
            repo_root=REPO_ROOT,
            data_loader=_fake_loader(missing_observation=True),
        )

import sys
from pathlib import Path
from types import SimpleNamespace

import numpy as np
import pytest


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "src"))

from camels_switch_confirmation.g1_precheck import PARAM_KEYS  # noqa: E402
from camels_switch_confirmation.g2_switch_confirmation import (  # noqa: E402
    rising_routed_discharge,
)
from camels_switch_confirmation.run_day540_truth_state_counterfactual import (  # noqa: E402
    apply_truth_state_mean_intervention,
    replay_truth_with_states,
    validate_run_paths,
)
from hbv_joint_uncertainty.hbv_adapter import advance_state  # noqa: E402
from scl_hydro.hbv_lite_numpy import resolve_hbv_bounds  # noqa: E402


def _members():
    center = {
        "parTT": 0.0,
        "parCFMAX": 3.0,
        "parCFR": 0.05,
        "parCWH": 0.1,
        "parFC": 200.0,
        "parBETA": 2.0,
        "parLP": 0.7,
        "parK0": 0.2,
        "parK1": 0.1,
        "parUZL": 5.0,
        "parPERC": 1.0,
        "parK2": 0.05,
        "lag_time": 3.0,
    }
    return [
        center,
        {**center, "parFC": 100.0},
        {**center, "parFC": 400.0},
    ]


def test_truth_replay_exposes_exact_pre_step_and_post_step_fifteen_states():
    members = _members()
    rain = np.array([0.0, 2.0, 0.5], dtype=np.float64)
    pet = np.full(3, 0.1, dtype=np.float64)
    temperature = np.full(3, 5.0, dtype=np.float64)
    initial_hydrology = np.array([0.0, 0.0, 160.0, 20.0, 30.0])
    bounds = resolve_hbv_bounds("v5")
    replay_rng = np.random.default_rng(123)
    expected_rng = np.random.default_rng(123)

    replay = replay_truth_with_states(
        members,
        rain,
        pet,
        temperature,
        initial_hydrology,
        replay_rng,
        bounds,
    )

    state = np.zeros(15, dtype=np.float64)
    state[:5] = initial_hydrology
    for day in range(3):
        np.testing.assert_array_equal(replay.source_states[day], state)
        state = advance_state(
            state,
            rain[day],
            pet[day],
            temperature[day],
            members[0],
            bounds=bounds,
        )
        state[4] *= np.exp(expected_rng.normal(-0.5 * 0.02**2, 0.02))
        np.testing.assert_array_equal(replay.posterior_states[day], state)
        assert replay.discharge[day] == rising_routed_discharge(
            state,
            members[0]["lag_time"],
        )
    np.testing.assert_array_equal(replay.parfc, np.full(3, 200.0))
    assert replay.switch_days == ()
    assert replay.clip_count == 0


def test_intervention_changes_only_dominant_candidate_state_mean():
    states = np.arange(45, dtype=np.float64).reshape(3, 15)
    covariances = np.stack([np.eye(15) * value for value in (1.0, 2.0, 3.0)])
    probabilities = np.array([1.0e-20, 2.0e-30, 1.0 - 1.0e-20])
    estimator = SimpleNamespace(
        filters=[
            SimpleNamespace(state=state.copy(), covariance=covariance.copy())
            for state, covariance in zip(states, covariances)
        ],
        probabilities=probabilities.copy(),
        state=np.full(15, 7.0),
        covariance=np.eye(15) * 9.0,
    )
    truth_state = np.linspace(0.0, 1.0, 15)
    global_state_before = estimator.state.copy()
    global_covariance_before = estimator.covariance.copy()

    record = apply_truth_state_mean_intervention(
        estimator,
        truth_state,
        expected_source_index=2,
    )

    np.testing.assert_array_equal(estimator.filters[0].state, states[0])
    np.testing.assert_array_equal(estimator.filters[1].state, states[1])
    np.testing.assert_array_equal(estimator.filters[2].state, truth_state)
    for candidate, expected in zip(estimator.filters, covariances):
        np.testing.assert_array_equal(candidate.covariance, expected)
    np.testing.assert_array_equal(estimator.probabilities, probabilities)
    np.testing.assert_array_equal(estimator.state, global_state_before)
    np.testing.assert_array_equal(estimator.covariance, global_covariance_before)
    assert record.source_index == 2
    np.testing.assert_array_equal(record.state_before, states[2])
    np.testing.assert_array_equal(record.state_after, truth_state)
    np.testing.assert_array_equal(record.covariance_before, covariances[2])
    np.testing.assert_array_equal(record.covariance_after, covariances[2])


@pytest.mark.parametrize("probabilities", [
    np.array([0.2, 0.6, 0.2]),
    np.array([0.1, 0.45, 0.45]),
])
def test_intervention_rejects_wrong_or_nonunique_dominant_source(probabilities):
    estimator = SimpleNamespace(
        filters=[
            SimpleNamespace(state=np.zeros(15), covariance=np.eye(15))
            for _ in range(3)
        ],
        probabilities=probabilities,
        state=np.zeros(15),
        covariance=np.eye(15),
    )

    with pytest.raises(ValueError, match="dominant source candidate"):
        apply_truth_state_mean_intervention(
            estimator,
            np.ones(15),
            expected_source_index=2,
        )


def test_run_paths_reject_output_inside_frozen_root_without_writing(tmp_path):
    frozen_root = tmp_path / "frozen"
    frozen_root.mkdir()
    source_task = frozen_root / "source.npz"
    source_task.write_bytes(b"source")
    output_root = frozen_root / "new-output"

    with pytest.raises(ValueError, match="outside the frozen result root"):
        validate_run_paths(source_task, frozen_root, output_root)

    assert not output_root.exists()


def test_parameter_fixture_covers_registered_thirteen_parameters():
    assert tuple(_members()[0]) == tuple(PARAM_KEYS)

"""Tests for the NOISE-X1 noise-switch experiment runner.

Pins the pure decision logic the preregistration quotes -- rotation coverage,
the id23-verbatim event rule at both windows, the null-control false-alarm
counter, the per-candidate Q assignment, and the seed-stream separation from
the precheck -- without running any filter.
"""

import sys
from pathlib import Path

import numpy as np
import pytest

_SRC = Path(__file__).resolve().parents[1] / "src"
if str(_SRC) not in sys.path:
    sys.path.insert(0, str(_SRC))

from camels_switch_confirmation import run_noise_switch_experiment as experiment  # noqa: E402
from camels_switch_confirmation.noise_switch_precheck import (  # noqa: E402
    NOISE_CANDIDATES,
    ROTATION,
    SEED_ENTROPY,
    STAGE_DAYS,
    injection_sigma,
)


def test_switch_rotation_realises_all_six_directed_pairs_once():
    events = experiment.switch_events_from_rotation(ROTATION)
    pairs = [(f, t) for _, f, t in events]
    assert len(pairs) == 6
    assert len(set(pairs)) == 6
    assert [d for d, _, _ in events] == [180, 360, 540, 720, 900, 1080]


def test_null_rotation_produces_no_events():
    assert experiment.switch_events_from_rotation(experiment.NULL_ROTATION) == []
    assert experiment.SCENARIOS["null"] == (0,) * len(ROTATION)
    assert experiment.TRUE_NULL_INDEX == 0
    assert NOISE_CANDIDATES[experiment.TRUE_NULL_INDEX] == 1.0


def _probs_with_run(candidate, start, length, n_days=400, n_candidates=3):
    probabilities = np.full((n_days, n_candidates), 0.2)
    probabilities[:, 0] = 0.6
    probabilities[start:start + length] = 0.15
    probabilities[start:start + length, candidate] = 0.7
    return probabilities


def test_event_rule_passes_inside_window_and_fails_outside():
    events = [(180, 0, 1)]
    inside = _probs_with_run(candidate=1, start=250, length=5)
    outcome = experiment.evaluate_switch_events(inside, events, 90)[0]
    assert outcome["passed"] and outcome["response_start"] == 70
    assert outcome["type"] == "m1_to_m0.1"
    # same run is outside the tighter 30-day secondary window
    assert not experiment.evaluate_switch_events(inside, events, 30)[0]["passed"]
    # a 4-day run never passes
    short = _probs_with_run(candidate=1, start=250, length=4)
    assert not experiment.evaluate_switch_events(short, events, 90)[0]["passed"]


def test_event_rule_requires_margin():
    events = [(180, 0, 2)]
    probabilities = np.full((400, 3), 0.0)
    probabilities[:, 0] = 0.46
    probabilities[:, 2] = 0.54           # >0.5 but margin 0.08 < 0.1
    assert not experiment.evaluate_switch_events(
        probabilities, events, 90)[0]["passed"]


def test_false_alarm_counter_merges_consecutive_days_and_ignores_truth():
    quiet = np.full((300, 3), 0.15)
    quiet[:, 0] = 0.7                    # truth candidate dominant throughout
    assert experiment.count_false_alarms(quiet) == 0
    noisy = quiet.copy()
    noisy[50:60] = 0.1                   # one 10-day wrong run -> ONE alarm
    noisy[50:60, 2] = 0.8
    noisy[200:205] = 0.1                 # a second, separate 5-day run
    noisy[200:205, 1] = 0.8
    assert experiment.count_false_alarms(noisy) == 2


def test_candidate_q_assignment_scales_by_multiplier():
    class _Filter:
        process_covariance = None

    class _Estimator:
        filters = [_Filter(), _Filter(), _Filter()]

    estimator = _Estimator()
    experiment.assign_candidate_process_covariances(estimator, 100.0)
    variances = [f.process_covariance[4, 4] for f in estimator.filters]
    assert variances[0] > 0.0
    assert variances[1] / variances[0] == pytest.approx(0.1)
    assert variances[2] / variances[0] == pytest.approx(10.0)
    # negative predicted storage clamps to zero variance instead of raising
    experiment.assign_candidate_process_covariances(estimator, -1.0)
    assert all(f.process_covariance[4, 4] == 0.0 for f in estimator.filters)


def test_truth_generator_switches_noise_scale_at_stage_boundary():
    from scl_hydro.hbv_lite_numpy import resolve_hbv_bounds
    params = {"parTT": 0.0, "parCFMAX": 3.0, "parCFR": 0.05, "parCWH": 0.1,
              "parFC": 300.0, "parBETA": 2.0, "parLP": 0.6, "parK0": 0.5,
              "parK1": 0.1, "parUZL": 20.0, "parPERC": 2.0, "parK2": 1e-4,
              "lag_time": 1.0}
    stage = 120
    rotation = (1, 2)                    # low noise then high noise
    n_days = stage * len(rotation)
    rain = np.zeros(n_days)              # dry: SLZ changes only via noise+PERC
    pet = np.zeros(n_days)
    temp = np.full(n_days, 10.0)
    init = np.array([0.0, 0.0, 200.0, 0.0, 1000.0])
    rng = np.random.default_rng(1)
    truth_q, truth_index, clips = experiment.generate_truth(
        rotation, params, rain, pet, temp, init, rng, resolve_hbv_bounds("v5"),
        stage_days=stage)
    assert clips == 0
    assert list(np.unique(truth_index[:stage])) == [1]
    assert list(np.unique(truth_index[stage:])) == [2]
    # under dry forcing the discharge is groundwater-fed, so its day-to-day
    # log-jitter inherits the injected noise scale: the high-noise stage must
    # be far jumpier than the low-noise stage (x10 sigma; demand > x3 realised)
    log_steps = np.diff(np.log(truth_q))
    jitter_low = np.std(log_steps[20:stage - 1])
    jitter_high = np.std(log_steps[stage + 20:])
    assert jitter_high / jitter_low > 3.0


def test_seed_streams_do_not_collide_with_precheck():
    # precheck ensembles used (E, basin, cell_index) with cell_index in {0,1,2};
    # the experiment appends a stream tag so tuples can never coincide.
    assert experiment.TRUTH_STREAM_TAG not in (0, 1, 2)
    assert experiment.OBS_STREAM_TAG not in (0, 1, 2)
    assert experiment.TRUTH_STREAM_TAG != experiment.OBS_STREAM_TAG
    a = np.random.SeedSequence(
        (SEED_ENTROPY, 1013500, 0, experiment.TRUTH_STREAM_TAG))
    b = np.random.SeedSequence((SEED_ENTROPY, 1013500, 0))
    assert (np.random.default_rng(a).normal()
            != np.random.default_rng(b).normal())


def test_shortened_window_refuses_default_output_root():
    class _Args:
        basins = ["01013500"]
        seeds = [0]
        arms = ["C"]
        scenarios = ["null"]
        workers = 1
        window_days = 40
        output_root = str(experiment.OUTPUT_ROOT)

    with pytest.raises(ValueError):
        experiment.run_all(_Args())


def test_stage_constants_match_frozen_spec():
    assert STAGE_DAYS == 180
    assert experiment.PRIMARY_WINDOW_DAYS == 90
    assert experiment.SECONDARY_WINDOW_DAYS == 30
    assert experiment.SEEDS == (0, 1)
    assert NOISE_CANDIDATES == (1.0, 0.1, 10.0)

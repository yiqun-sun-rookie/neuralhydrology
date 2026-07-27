import numpy as np
import pytest

from hbv_multilead_joint_uncertainty.temporal_posterior_readout import (
    summarize_temporal_posterior_readout,
    temporal_posterior_readout,
)


def _history() -> np.ndarray:
    history = np.tile(np.array([0.10, 0.20, 0.70]), (30, 1))
    history[-1] = np.array([0.80, 0.15, 0.05])
    return history


def _candidate_forecasts() -> np.ndarray:
    return np.array(
        [
            [1.0, 2.0, 3.0],
            [4.0, 5.0, 6.0],
            [7.0, 8.0, 9.0],
        ]
    )


def test_temporal_readout_keeps_one_day_and_selects_temporal_mode():
    history = _history()
    candidates = _candidate_forecasts()
    history_before = history.copy()
    candidates_before = candidates.copy()

    result = temporal_posterior_readout(
        history,
        candidates,
        lead_days=(1, 3, 7),
        window_days=30,
    )

    np.testing.assert_allclose(result.weights[0], history[-1])
    np.testing.assert_array_equal(result.weights[1:], [[0.0, 0.0, 1.0]] * 2)
    np.testing.assert_allclose(
        result.predictions,
        [history[-1] @ candidates[0], candidates[1, 2], candidates[2, 2]],
    )
    assert result.selected_candidate_index == 2
    np.testing.assert_allclose(
        result.temporal_mean_probabilities,
        history.mean(axis=0),
    )
    np.testing.assert_array_equal(history, history_before)
    np.testing.assert_array_equal(candidates, candidates_before)
    assert not result.weights.flags.writeable
    assert not result.predictions.flags.writeable
    assert not result.temporal_mean_probabilities.flags.writeable


def test_temporal_readout_uses_only_the_last_thirty_days():
    history = np.vstack(
        [
            np.tile(np.array([1.0, 0.0, 0.0]), (10, 1)),
            np.tile(np.array([0.0, 1.0, 0.0]), (30, 1)),
        ]
    )
    result = temporal_posterior_readout(
        history,
        _candidate_forecasts(),
        (1, 3, 7),
        window_days=30,
    )
    assert result.selected_candidate_index == 1
    np.testing.assert_array_equal(result.weights[1:], [[0.0, 1.0, 0.0]] * 2)


def test_temporal_readout_tie_uses_first_candidate():
    history = np.tile(np.array([0.5, 0.5, 0.0]), (30, 1))
    result = temporal_posterior_readout(
        history,
        _candidate_forecasts(),
        (1, 3, 7),
        window_days=30,
    )
    assert result.selected_candidate_index == 0


@pytest.mark.parametrize(
    ("history", "forecasts", "leads", "window", "match"),
    [
        (np.ones((29, 3)) / 3, _candidate_forecasts(), (1, 3, 7), 30, "at least"),
        (np.ones((30, 3, 1)) / 3, _candidate_forecasts(), (1, 3, 7), 30, "two-dimensional"),
        (np.ones((30, 2)) / 2, _candidate_forecasts(), (1, 3, 7), 30, "candidate"),
        (_history(), np.ones((3, 3, 1)), (1, 3, 7), 30, "two-dimensional"),
        (_history(), _candidate_forecasts(), (1, 3), 30, "lead"),
        (_history(), _candidate_forecasts(), (1, 3, 6), 30, "exactly"),
        (_history(), _candidate_forecasts(), (1, 3, 7), 0, "positive integer"),
        (_history(), _candidate_forecasts(), (1, 3, 7), True, "positive integer"),
    ],
)
def test_temporal_readout_rejects_invalid_shapes_and_contracts(
    history,
    forecasts,
    leads,
    window,
    match,
):
    with pytest.raises(ValueError, match=match):
        temporal_posterior_readout(
            history,
            forecasts,
            leads,
            window_days=window,
        )


@pytest.mark.parametrize(
    ("mutator", "match"),
    [
        (lambda values: values.__setitem__((0, 0), np.nan), "finite"),
        (lambda values: values.__setitem__((0, 0), -0.1), "nonnegative"),
        (lambda values: values.__setitem__((0, slice(None)), [0.2, 0.2, 0.2]), "sum"),
    ],
)
def test_temporal_readout_rejects_invalid_probability_rows(mutator, match):
    history = _history()
    mutator(history)
    with pytest.raises(ValueError, match=match):
        temporal_posterior_readout(
            history,
            _candidate_forecasts(),
            (1, 3, 7),
            window_days=30,
        )


def _summary_inputs(blocks: int = 4):
    truth = np.zeros((blocks, 3, 3))
    full = np.ones_like(truth)
    none = np.full_like(truth, 2.0)
    temporal = full.copy()
    temporal[..., 1] = 0.8
    temporal[..., 2] = 0.7
    selected = np.tile(np.arange(3), (blocks, 1))
    true = selected.copy()
    return {
        "forecasts": {
            "temporal_posterior": temporal,
            "full_posterior": full,
            "none_posterior": none,
        },
        "truth_forecasts": truth,
        "selected_candidate_indices": selected,
        "true_candidate_indices": true,
        "lead_days": (1, 3, 7),
        "bootstrap_replicates": 200,
        "bootstrap_seed": 123,
        "minimum_meaningful_rmse_fraction": 0.01,
        "minimum_selection_accuracy": 0.95,
    }


def test_temporal_summary_enforces_exact_one_day_and_retention_gates():
    summary = summarize_temporal_posterior_readout(**_summary_inputs())

    np.testing.assert_array_equal(
        summary["forecasts"]["temporal_posterior"][..., 0],
        summary["forecasts"]["full_posterior"][..., 0],
    )
    assert summary["one_day_maximum_absolute_difference"] == 0.0
    assert summary["selection_accuracy"] == 1.0
    assert summary["retention_gates"] == {
        "one_day_exact": True,
        "selection_accuracy": True,
        "three_day_no_material_harm_vs_full": True,
        "seven_day_material_improvement_vs_full": True,
        "three_day_no_material_harm_vs_none": True,
        "seven_day_material_improvement_vs_none": True,
        "retain": True,
    }


def test_temporal_summary_rejects_one_day_drift():
    inputs = _summary_inputs()
    inputs["forecasts"]["temporal_posterior"][0, 0, 0] += 2e-12

    summary = summarize_temporal_posterior_readout(**inputs)

    assert summary["one_day_maximum_absolute_difference"] == pytest.approx(2e-12)
    assert not summary["retention_gates"]["one_day_exact"]
    assert not summary["retention_gates"]["retain"]


def test_temporal_summary_selection_threshold_is_strictly_ninety_five_percent():
    inputs = _summary_inputs(blocks=20)
    inputs["selected_candidate_indices"][0, 0] = 1
    summary = summarize_temporal_posterior_readout(**inputs)
    assert summary["selection_accuracy"] == pytest.approx(59 / 60)
    assert summary["retention_gates"]["selection_accuracy"]

    inputs["selected_candidate_indices"][0, 1] = 0
    inputs["selected_candidate_indices"][0, 2] = 0
    summary = summarize_temporal_posterior_readout(**inputs)
    assert summary["selection_accuracy"] == pytest.approx(57 / 60)
    assert summary["retention_gates"]["selection_accuracy"]

    inputs["selected_candidate_indices"][1, 0] = 1
    summary = summarize_temporal_posterior_readout(**inputs)
    assert summary["selection_accuracy"] == pytest.approx(56 / 60)
    assert not summary["retention_gates"]["selection_accuracy"]


def test_temporal_summary_is_deterministic_and_does_not_mutate_inputs():
    inputs = _summary_inputs()
    snapshots = {
        key: value.copy()
        for key, value in inputs["forecasts"].items()
    }
    first = summarize_temporal_posterior_readout(**inputs)
    second = summarize_temporal_posterior_readout(**inputs)

    np.testing.assert_array_equal(
        first["bootstrap_indices"],
        second["bootstrap_indices"],
    )
    for key, value in snapshots.items():
        np.testing.assert_array_equal(inputs["forecasts"][key], value)

"""Tests for the state-path by final-weight forecast compositor."""

from __future__ import annotations

from dataclasses import FrozenInstanceError
from types import SimpleNamespace

import numpy as np
import pytest

import hbv_multilead_joint_uncertainty.state_weight_factorial_diagnostic as diagnostic
from hbv_multilead_joint_uncertainty.state_weight_factorial_diagnostic import (
    combine_candidate_forecasts,
    state_weight_factorial_forecasts,
)


def test_combine_candidate_forecasts_returns_weighted_sum_by_lead():
    candidate_forecasts = np.asarray(
        [[1.0, 2.0, 4.0], [10.0, 20.0, 40.0]],
        dtype=np.float64,
    )
    probabilities = np.asarray([0.5, 0.25, 0.25], dtype=np.float64)

    combined = combine_candidate_forecasts(candidate_forecasts, probabilities)

    np.testing.assert_array_equal(combined, np.asarray([2.0, 20.0]))


def test_state_weight_factorial_forecasts_returns_all_combinations_and_interaction():
    full_candidate_forecasts = np.asarray(
        [[2.0, 6.0], [5.0, 9.0]],
        dtype=np.float64,
    )
    none_candidate_forecasts = np.asarray(
        [[1.0, 3.0], [4.0, 8.0]],
        dtype=np.float64,
    )
    full_probabilities = np.asarray([0.75, 0.25], dtype=np.float64)
    none_probabilities = np.asarray([0.25, 0.75], dtype=np.float64)

    result = state_weight_factorial_forecasts(
        full_candidate_forecasts,
        none_candidate_forecasts,
        full_probabilities,
        none_probabilities,
    )

    assert set(result) == {
        "full_states_full_weights",
        "full_states_none_weights",
        "none_states_full_weights",
        "none_states_none_weights",
        "prediction_nonadditivity",
    }
    np.testing.assert_array_equal(
        result["full_states_full_weights"], np.asarray([3.0, 6.0])
    )
    np.testing.assert_array_equal(
        result["full_states_none_weights"], np.asarray([5.0, 8.0])
    )
    np.testing.assert_array_equal(
        result["none_states_full_weights"], np.asarray([1.5, 5.0])
    )
    np.testing.assert_array_equal(
        result["none_states_none_weights"], np.asarray([2.5, 7.0])
    )
    np.testing.assert_array_equal(
        result["prediction_nonadditivity"], np.asarray([-1.0, 0.0])
    )


def test_state_weight_factorial_forecasts_does_not_modify_inputs():
    full_candidate_forecasts = np.asarray([[2.0, 6.0]], dtype=np.float64)
    none_candidate_forecasts = np.asarray([[1.0, 3.0]], dtype=np.float64)
    full_probabilities = np.asarray([0.75, 0.25], dtype=np.float64)
    none_probabilities = np.asarray([0.25, 0.75], dtype=np.float64)
    inputs = (
        full_candidate_forecasts,
        none_candidate_forecasts,
        full_probabilities,
        none_probabilities,
    )
    originals = tuple(value.copy() for value in inputs)

    state_weight_factorial_forecasts(*inputs)

    for value, original in zip(inputs, originals):
        np.testing.assert_array_equal(value, original)


@pytest.mark.parametrize(
    ("candidate_forecasts", "probabilities"),
    [
        (np.asarray([1.0, 2.0]), np.asarray([0.5, 0.5])),
        (np.asarray([[1.0, np.nan]]), np.asarray([0.5, 0.5])),
        (np.asarray([[1.0, np.inf]]), np.asarray([0.5, 0.5])),
        (np.asarray([[1.0, 2.0]]), np.asarray([[0.5, 0.5]])),
        (np.asarray([[1.0, 2.0]]), np.asarray([1.0])),
        (np.asarray([[1.0, 2.0]]), np.asarray([0.5, np.nan])),
        (np.asarray([[1.0, 2.0]]), np.asarray([0.5, np.inf])),
        (np.asarray([[1.0, 2.0]]), np.asarray([1.1, -0.1])),
        (np.asarray([[1.0, 2.0]]), np.asarray([0.6, 0.5])),
        (np.asarray([[1.0, 2.0]]), np.asarray([0.5, 0.5 + 2e-12])),
    ],
)
def test_combine_candidate_forecasts_rejects_invalid_inputs(
    candidate_forecasts,
    probabilities,
):
    with pytest.raises(ValueError):
        combine_candidate_forecasts(candidate_forecasts, probabilities)


def test_combine_candidate_forecasts_accepts_probability_sum_at_tolerance():
    candidate_forecasts = np.asarray([[1.0, 3.0]], dtype=np.float64)
    probabilities = np.asarray([0.5, 0.5 + 5e-13], dtype=np.float64)

    combined = combine_candidate_forecasts(candidate_forecasts, probabilities)

    np.testing.assert_allclose(
        combined,
        candidate_forecasts @ probabilities,
        rtol=0.0,
        atol=0.0,
    )


@pytest.mark.parametrize(
    ("candidate_forecasts", "probabilities"),
    [
        (
            np.asarray([[1.0 + 2.0j, 3.0 + 0.0j]], dtype=np.complex128),
            np.asarray([0.5, 0.5]),
        ),
        (
            np.asarray([[1.0, 3.0]]),
            np.asarray([0.5 + 0.25j, 0.5 - 0.25j], dtype=np.complex128),
        ),
    ],
)
def test_combine_candidate_forecasts_rejects_complex_inputs(
    candidate_forecasts,
    probabilities,
):
    with pytest.raises(ValueError):
        combine_candidate_forecasts(candidate_forecasts, probabilities)


@pytest.mark.parametrize(
    ("candidate_forecasts", "probabilities"),
    [
        (np.asarray([[object()]], dtype=object), np.asarray([1.0])),
        (np.asarray([[1.0]]), np.asarray([object()], dtype=object)),
    ],
)
def test_combine_candidate_forecasts_normalizes_conversion_type_error(
    candidate_forecasts,
    probabilities,
):
    with pytest.raises(ValueError):
        combine_candidate_forecasts(candidate_forecasts, probabilities)


@pytest.mark.parametrize(
    ("full_candidate_forecasts", "full_probabilities"),
    [
        (
            np.asarray([[1.0 + 2.0j]], dtype=np.complex128),
            np.asarray([1.0]),
        ),
        (
            np.asarray([[1.0]]),
            np.asarray([1.0 + 2.0j], dtype=np.complex128),
        ),
        (
            np.asarray([[object()]], dtype=object),
            np.asarray([1.0]),
        ),
    ],
)
def test_state_weight_factorial_forecasts_rejects_invalid_dtypes_as_value_error(
    full_candidate_forecasts,
    full_probabilities,
):
    with pytest.raises(ValueError):
        state_weight_factorial_forecasts(
            full_candidate_forecasts,
            np.asarray([[1.0]]),
            full_probabilities,
            np.asarray([1.0]),
        )


@pytest.mark.parametrize(
    ("full_candidate_forecasts", "none_candidate_forecasts"),
    [
        (
            np.asarray([[1.0, 2.0], [3.0, 4.0]]),
            np.asarray([[1.0, 2.0]]),
        ),
        (
            np.asarray([[1.0, 2.0]]),
            np.asarray([[1.0, 2.0, 3.0]]),
        ),
    ],
)
def test_state_weight_factorial_forecasts_rejects_mismatched_candidate_shapes(
    full_candidate_forecasts,
    none_candidate_forecasts,
):
    with pytest.raises(ValueError):
        state_weight_factorial_forecasts(
            full_candidate_forecasts,
            none_candidate_forecasts,
            np.full(full_candidate_forecasts.shape[1], 1.0 / full_candidate_forecasts.shape[1]),
            np.full(none_candidate_forecasts.shape[1], 1.0 / none_candidate_forecasts.shape[1]),
        )


class _RecordingTransition:

    def __init__(self, candidate_index, events):
        self.candidate_index = candidate_index
        self.events = events

    def set_forcing(self, rain, pet, temperature):
        self.events.append(
            ("forcing", self.candidate_index, (float(rain), float(pet), float(temperature)))
        )


class _RecordingEstimator:

    def __init__(self, filters, daily_probabilities, events):
        self.filters = filters
        self._daily_probabilities = daily_probabilities
        self._events = events
        self._day = 0
        self.probabilities = np.full(len(filters), 1.0 / len(filters), dtype=np.float64)

    def step(self, observation):
        self._events.append(("step", float(observation)))
        for candidate_index, candidate_filter in enumerate(self.filters):
            candidate_filter.state = np.full(
                15, 100.0 * (self._day + 1) + candidate_index, dtype=np.float64
            )
            candidate_filter.covariance = np.eye(15, dtype=np.float64) * (
                10.0 * (self._day + 1) + candidate_index
            )
        self.probabilities = self._daily_probabilities[self._day].copy()
        self._day += 1


def _terminal_inputs():
    candidates = (
        SimpleNamespace(parameter_id="parameter_a", payload=np.asarray([1.0])),
        SimpleNamespace(parameter_id="parameter_b", payload=np.asarray([2.0])),
    )
    initial_states = {
        candidate.parameter_id: np.arange(15, dtype=np.float64) + index
        for index, candidate in enumerate(candidates)
    }
    return {
        "candidates": candidates,
        "initial_states": initial_states,
        "initial_covariance": np.eye(15, dtype=np.float64),
        "active_forcing": np.arange(15, dtype=np.float64).reshape(5, 3) + 1.0,
        "observations": np.asarray([0.5, 0.75, np.nan], dtype=np.float64),
        "assimilation_days": 2,
        "leads": (1, 3),
        "observation_standard_deviation": 0.05,
        "factor_transition_stay_probability": 0.98,
        "interaction_mode": "full",
    }


def test_assimilate_terminal_forecast_captures_terminal_bank_before_one_frozen_forecast(
    monkeypatch,
):
    inputs = _terminal_inputs()
    events = []
    build_calls = []
    forecast_calls = []
    daily_probabilities = np.asarray([[0.6, 0.4], [0.25, 0.75]], dtype=np.float64)
    forecast_outputs = []

    def fake_build_method_bank(**kwargs):
        build_calls.append(kwargs)
        filters = [
            SimpleNamespace(
                state=np.full(15, candidate_index, dtype=np.float64),
                covariance=np.eye(15, dtype=np.float64),
            )
            for candidate_index in range(2)
        ]
        return SimpleNamespace(
            transitions=tuple(
                _RecordingTransition(candidate_index, events)
                for candidate_index in range(2)
            ),
            estimator=_RecordingEstimator(filters, daily_probabilities, events),
        )

    def fake_forecast_from_posterior(bank, future_forcing, lead_days, interaction_mode):
        forecast_calls.append(
            (np.asarray(future_forcing).copy(), tuple(lead_days), interaction_mode)
        )
        candidate_predictions = np.asarray([[2.0, 6.0], [10.0, 14.0]])
        probabilities = np.broadcast_to(
            daily_probabilities[-1], candidate_predictions.shape
        ).copy()
        output = SimpleNamespace(
            probabilities=probabilities,
            candidate_predictions=candidate_predictions,
            combined_predictions=candidate_predictions @ daily_probabilities[-1],
        )
        forecast_outputs.append(output)
        for candidate_filter in bank.estimator.filters:
            candidate_filter.state.fill(-999.0)
            candidate_filter.covariance.fill(-888.0)
        return output

    monkeypatch.setattr(diagnostic, "build_method_bank", fake_build_method_bank)
    monkeypatch.setattr(diagnostic, "forecast_from_posterior", fake_forecast_from_posterior)
    candidate_payloads = tuple(candidate.payload.copy() for candidate in inputs["candidates"])
    state_copies = {key: value.copy() for key, value in inputs["initial_states"].items()}
    covariance_copy = inputs["initial_covariance"].copy()
    forcing_copy = inputs["active_forcing"].copy()
    observation_copy = inputs["observations"].copy()

    result = diagnostic.assimilate_terminal_forecast(**inputs)

    assert len(build_calls) == 1
    assert len(forecast_calls) == 1
    assert events == [
        ("forcing", 0, (1.0, 2.0, 3.0)),
        ("forcing", 1, (1.0, 2.0, 3.0)),
        ("step", 0.5),
        ("forcing", 0, (4.0, 5.0, 6.0)),
        ("forcing", 1, (4.0, 5.0, 6.0)),
        ("step", 0.75),
    ]
    np.testing.assert_array_equal(forecast_calls[0][0], inputs["active_forcing"][2:5])
    assert forecast_calls[0][1:] == ((1, 3), "full")
    assert result.daily_probabilities.shape == (2, 2)
    assert result.final_candidate_states.shape == (2, 15)
    assert result.final_candidate_covariances.shape == (2, 15, 15)
    assert result.candidate_forecasts.shape == (2, 2)
    assert result.combined_forecast.shape == (2,)
    np.testing.assert_array_equal(result.daily_probabilities, daily_probabilities)
    np.testing.assert_array_equal(
        result.final_candidate_states,
        np.asarray([np.full(15, 200.0), np.full(15, 201.0)]),
    )
    np.testing.assert_array_equal(
        result.final_candidate_covariances,
        np.asarray([np.eye(15) * 20.0, np.eye(15) * 21.0]),
    )
    np.testing.assert_array_equal(result.candidate_forecasts, [[2.0, 6.0], [10.0, 14.0]])
    np.testing.assert_array_equal(result.combined_forecast, [5.0, 13.0])
    with pytest.raises(FrozenInstanceError):
        result.daily_probabilities = np.zeros((2, 2))

    forecast_outputs[0].probabilities.fill(-1.0)
    forecast_outputs[0].candidate_predictions.fill(-2.0)
    forecast_outputs[0].combined_predictions.fill(-3.0)
    np.testing.assert_array_equal(result.daily_probabilities, daily_probabilities)
    np.testing.assert_array_equal(result.candidate_forecasts, [[2.0, 6.0], [10.0, 14.0]])
    np.testing.assert_array_equal(result.combined_forecast, [5.0, 13.0])
    for candidate, payload in zip(inputs["candidates"], candidate_payloads):
        np.testing.assert_array_equal(candidate.payload, payload)
    for key, expected in state_copies.items():
        np.testing.assert_array_equal(inputs["initial_states"][key], expected)
    np.testing.assert_array_equal(inputs["initial_covariance"], covariance_copy)
    np.testing.assert_array_equal(inputs["active_forcing"], forcing_copy)
    np.testing.assert_array_equal(inputs["observations"], observation_copy)


@pytest.mark.parametrize(
    ("field", "invalid_value"),
    [
        ("interaction_mode", "parameter_grouped"),
        ("assimilation_days", True),
        ("assimilation_days", 0),
        ("assimilation_days", 1.5),
        ("leads", ()),
        ("leads", (True, 3)),
        ("leads", (1.0, 3)),
        ("leads", (0, 3)),
        ("leads", (3, 1)),
        ("leads", (1, 1)),
        ("active_forcing", np.zeros((5, 2))),
        ("active_forcing", np.full((5, 3), np.nan)),
        ("active_forcing", np.zeros((4, 3))),
        ("observations", np.zeros((2, 1))),
        ("observations", np.asarray([0.5])),
        ("observations", np.asarray([0.5, np.nan, 0.75])),
        ("initial_covariance", np.eye(14)),
        ("initial_covariance", np.full((15, 15), np.nan)),
        ("initial_covariance", np.eye(15) + np.diag(np.ones(14), k=1)),
        ("initial_states", {"parameter_a": np.zeros(14), "parameter_b": np.zeros(15)}),
        (
            "initial_states",
            {"parameter_a": np.full(15, np.nan), "parameter_b": np.zeros(15)},
        ),
        ("candidates", ()),
        ("observation_standard_deviation", 0.0),
        ("observation_standard_deviation", np.nan),
        ("factor_transition_stay_probability", -0.1),
        ("factor_transition_stay_probability", 1.1),
        ("factor_transition_stay_probability", np.inf),
    ],
)
def test_assimilate_terminal_forecast_rejects_invalid_inputs(
    monkeypatch, field, invalid_value
):
    monkeypatch.setattr(
        diagnostic,
        "build_method_bank",
        lambda **kwargs: pytest.fail("invalid input reached build_method_bank"),
    )
    inputs = _terminal_inputs()
    inputs[field] = invalid_value

    with pytest.raises(ValueError):
        diagnostic.assimilate_terminal_forecast(**inputs)


@pytest.mark.parametrize(
    "forecast_change", ["probabilities", "candidate_shape", "combined_weight"]
)
def test_assimilate_terminal_forecast_rejects_broken_frozen_forecast_contract(
    monkeypatch, forecast_change
):
    inputs = _terminal_inputs()
    daily_probabilities = np.asarray([[0.6, 0.4], [0.25, 0.75]], dtype=np.float64)
    filters = [
        SimpleNamespace(state=np.full(15, index), covariance=np.eye(15))
        for index in range(2)
    ]
    bank = SimpleNamespace(
        transitions=tuple(
            SimpleNamespace(set_forcing=lambda *forcing: None) for _ in range(2)
        ),
        estimator=_RecordingEstimator(filters, daily_probabilities, []),
    )
    monkeypatch.setattr(diagnostic, "build_method_bank", lambda **kwargs: bank)

    def broken_forecast(*args, **kwargs):
        probabilities = np.broadcast_to(daily_probabilities[-1], (2, 2)).copy()
        candidate_predictions = np.asarray([[2.0, 6.0], [10.0, 14.0]])
        combined_predictions = candidate_predictions @ daily_probabilities[-1]
        if forecast_change == "probabilities":
            probabilities[1] = np.asarray([0.5, 0.5])
        elif forecast_change == "candidate_shape":
            candidate_predictions = candidate_predictions[:, :1]
        else:
            combined_predictions[1] += 1e-6
        return SimpleNamespace(
            probabilities=probabilities,
            candidate_predictions=candidate_predictions,
            combined_predictions=combined_predictions,
        )

    monkeypatch.setattr(diagnostic, "forecast_from_posterior", broken_forecast)

    with pytest.raises((AssertionError, ValueError)):
        diagnostic.assimilate_terminal_forecast(**inputs)

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


@pytest.mark.parametrize("interaction_mode", ["full", "none"])
def test_assimilate_terminal_forecast_captures_terminal_bank_before_one_frozen_forecast(
    monkeypatch,
    interaction_mode,
):
    inputs = _terminal_inputs()
    inputs["interaction_mode"] = interaction_mode
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
    build_call = build_calls[0]
    assert build_call["interaction_mode"] == interaction_mode
    assert (
        build_call["observation_standard_deviation"]
        == inputs["observation_standard_deviation"]
    )
    assert build_call["factor_transition_stay_probability"] == inputs[
        "factor_transition_stay_probability"
    ]
    assert events == [
        ("forcing", 0, (1.0, 2.0, 3.0)),
        ("forcing", 1, (1.0, 2.0, 3.0)),
        ("step", 0.5),
        ("forcing", 0, (4.0, 5.0, 6.0)),
        ("forcing", 1, (4.0, 5.0, 6.0)),
        ("step", 0.75),
    ]
    np.testing.assert_array_equal(forecast_calls[0][0], inputs["active_forcing"][2:5])
    assert forecast_calls[0][1:] == ((1, 3), interaction_mode)
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
    for field_name in (
        "daily_probabilities",
        "final_candidate_states",
        "final_candidate_covariances",
        "candidate_forecasts",
        "combined_forecast",
    ):
        snapshot = getattr(result, field_name)
        assert not snapshot.flags.writeable
        with pytest.raises(ValueError, match="read-only"):
            snapshot.flat[0] = -123.0

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
    ("forecast_change", "expected_error"),
    [
        ("probabilities", RuntimeError),
        ("candidate_shape", ValueError),
        ("combined_weight", RuntimeError),
    ],
)
def test_assimilate_terminal_forecast_rejects_broken_frozen_forecast_contract(
    monkeypatch, forecast_change, expected_error
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

    with pytest.raises(expected_error):
        diagnostic.assimilate_terminal_forecast(**inputs)


def _sealed_driver_inputs():
    block_count = 2
    truth_count = 2
    parameter_count = 3
    assimilation_days = 3
    warmup_days = 2
    forecast_lead_days = np.asarray([1, 2], dtype=np.int64)
    total_days = warmup_days + assimilation_days + int(forecast_lead_days[-1])
    parameter_ids = np.asarray(
        ["parameter_b", "parameter_c", "parameter_a"],
        dtype=str,
    )
    candidates = (
        SimpleNamespace(
            candidate_id="candidate_a",
            parameter_id="parameter_a",
            payload=np.asarray([1.0]),
        ),
        SimpleNamespace(
            candidate_id="candidate_b",
            parameter_id="parameter_b",
            payload=np.asarray([2.0]),
        ),
        SimpleNamespace(
            candidate_id="candidate_c",
            parameter_id="parameter_c",
            payload=np.asarray([3.0]),
        ),
    )
    forcing_blocks = np.empty((block_count, total_days, 3), dtype=np.float64)
    for block in range(block_count):
        forcing_blocks[block] = (
            np.arange(total_days * 3, dtype=np.float64).reshape(total_days, 3)
            + 1000.0 * block
        )
    initial_parameter_states = np.empty(
        (block_count, parameter_count, 15),
        dtype=np.float64,
    )
    for block in range(block_count):
        for parameter_index in range(parameter_count):
            initial_parameter_states[block, parameter_index] = (
                100.0 * block + 10.0 * parameter_index + np.arange(15)
            )
    initial_covariances = np.asarray(
        [
            np.eye(15, dtype=np.float64) * (block + 1.0)
            for block in range(block_count)
        ]
    )
    observed_discharge = np.empty(
        (block_count, truth_count, assimilation_days + 1),
        dtype=np.float64,
    )
    for block in range(block_count):
        for truth in range(truth_count):
            observed_discharge[block, truth] = (
                1000.0 * block
                + 100.0 * truth
                + np.arange(assimilation_days + 1, dtype=np.float64)
            )
    truth_forecasts = np.asarray(
        [
            [[10.0, 11.0], [20.0, 21.0]],
            [[30.0, 31.0], [40.0, 41.0]],
        ],
        dtype=np.float64,
    )
    sealed_inputs = {
        "block_ids": np.asarray(["block_1", "block_2"], dtype=str),
        "forcing_blocks": forcing_blocks,
        "warmup_days": np.asarray(warmup_days, dtype=np.int64),
        "assimilation_days": np.asarray(assimilation_days, dtype=np.int64),
        "forecast_lead_days": forecast_lead_days,
        "initial_parameter_states": initial_parameter_states,
        "initial_covariances": initial_covariances,
        "observed_discharge": observed_discharge,
        "truth_forecast_discharge": truth_forecasts,
        "truth_primary_candidate_indices": np.asarray(
            [[0, 1, 2, 1], [1, 2, 0, 2]],
            dtype=np.int64,
        ),
        "parameter_ids": parameter_ids,
        "candidate_ids": np.asarray(
            ["candidate_a", "candidate_b", "candidate_c"],
            dtype=str,
        ),
    }
    return sealed_inputs, candidates


def test_compare_state_weight_factorial_uses_sealed_slices_and_only_two_paths(
    monkeypatch,
):
    sealed_inputs, candidates = _sealed_driver_inputs()
    sealed_copies = {
        key: np.asarray(value).copy()
        for key, value in sealed_inputs.items()
    }
    candidate_payloads = tuple(candidate.payload.copy() for candidate in candidates)
    assimilation_calls = []
    compositor_calls = []
    real_compositor = diagnostic.state_weight_factorial_forecasts

    def fake_assimilate_terminal_forecast(**kwargs):
        call_index = len(assimilation_calls)
        pair_index = call_index // 2
        block = pair_index // 2
        truth = pair_index % 2
        mode = ("full", "none")[call_index % 2]
        assert kwargs["interaction_mode"] == mode
        snapshot = {
            "candidate_ids": tuple(candidate.candidate_id for candidate in kwargs["candidates"]),
            "candidate_parameter_ids": tuple(
                candidate.parameter_id for candidate in kwargs["candidates"]
            ),
            "initial_states": {
                key: value.copy() for key, value in kwargs["initial_states"].items()
            },
            "active_forcing": kwargs["active_forcing"].copy(),
            "observations": kwargs["observations"].copy(),
            "assimilation_days": kwargs["assimilation_days"],
            "leads": tuple(kwargs["leads"]),
            "observation_standard_deviation": kwargs[
                "observation_standard_deviation"
            ],
            "factor_transition_stay_probability": kwargs[
                "factor_transition_stay_probability"
            ],
            "interaction_mode": mode,
        }
        assimilation_calls.append((kwargs, snapshot))

        mode_offset = 20.0 if mode == "full" else 0.0
        base = 100.0 * block + 10.0 * truth + mode_offset
        candidate_forecasts = (
            base
            + np.asarray(
                [[1.0, 2.0, 4.0], [10.0, 20.0, 40.0]],
                dtype=np.float64,
            )
        )
        final_probabilities = (
            np.asarray([0.6, 0.3, 0.1])
            if mode == "full"
            else np.asarray([0.2, 0.3, 0.5])
        )
        daily_probabilities = np.vstack(
            (
                np.full(3, 1.0 / 3.0),
                np.asarray([0.4, 0.35, 0.25]),
                final_probabilities,
            )
        )
        states = np.asarray(
            [
                np.full(15, base + candidate_index)
                for candidate_index in range(3)
            ]
        )
        covariances = np.asarray(
            [
                np.eye(15) * (base + candidate_index + 1.0)
                for candidate_index in range(3)
            ]
        )
        result = diagnostic.TerminalAssimilationForecast(
            daily_probabilities=daily_probabilities,
            final_candidate_states=states,
            final_candidate_covariances=covariances,
            candidate_forecasts=candidate_forecasts,
            combined_forecast=candidate_forecasts @ final_probabilities,
        )

        kwargs["candidates"][0].payload.fill(-1.0)
        next(iter(kwargs["initial_states"].values())).fill(-2.0)
        kwargs["initial_covariance"].fill(-3.0)
        kwargs["active_forcing"].fill(-4.0)
        kwargs["observations"].fill(-5.0)
        return result

    def recording_compositor(*args):
        compositor_calls.append(tuple(np.asarray(value).copy() for value in args))
        return real_compositor(*args)

    monkeypatch.setattr(
        diagnostic,
        "assimilate_terminal_forecast",
        fake_assimilate_terminal_forecast,
    )
    monkeypatch.setattr(
        diagnostic,
        "state_weight_factorial_forecasts",
        recording_compositor,
    )

    result = diagnostic.compare_state_weight_factorial(
        sealed_inputs=sealed_inputs,
        candidates=candidates,
        observation_standard_deviation=0.05,
        factor_transition_stay_probability=0.98,
    )

    assert len(assimilation_calls) == 8
    assert len(compositor_calls) == 4
    assert [call[1]["interaction_mode"] for call in assimilation_calls] == [
        "full", "none", "full", "none", "full", "none", "full", "none",
    ]
    assert set(result) == {
        "probabilities_full", "probabilities_none",
        "final_candidate_states_full", "final_candidate_states_none",
        "final_candidate_covariances_full", "final_candidate_covariances_none",
        "candidate_forecasts_full", "candidate_forecasts_none",
        "full_states_full_weights", "full_states_none_weights",
        "none_states_full_weights", "none_states_none_weights",
        "prediction_nonadditivity", "truth_forecasts",
        "final_true_candidate_indices", "final_true_candidate_ids",
        "candidate_ids", "parameter_ids", "block_ids", "forecast_lead_days",
        "assimilation_days",
    }
    assert result["probabilities_full"].shape == (2, 2, 3, 3)
    assert result["probabilities_none"].shape == (2, 2, 3, 3)
    assert result["final_candidate_states_full"].shape == (2, 2, 3, 15)
    assert result["final_candidate_states_none"].shape == (2, 2, 3, 15)
    assert result["final_candidate_covariances_full"].shape == (2, 2, 3, 15, 15)
    assert result["final_candidate_covariances_none"].shape == (2, 2, 3, 15, 15)
    assert result["candidate_forecasts_full"].shape == (2, 2, 2, 3)
    assert result["candidate_forecasts_none"].shape == (2, 2, 2, 3)
    for key in (
        "full_states_full_weights", "full_states_none_weights",
        "none_states_full_weights", "none_states_none_weights",
        "prediction_nonadditivity", "truth_forecasts",
    ):
        assert result[key].shape == (2, 2, 2)
        assert np.all(np.isfinite(result[key]))
    np.testing.assert_array_equal(result["final_true_candidate_indices"], [0, 1])
    np.testing.assert_array_equal(
        result["final_true_candidate_ids"], ["candidate_a", "candidate_b"]
    )
    for key in ("parameter_ids", "candidate_ids", "block_ids", "forecast_lead_days"):
        np.testing.assert_array_equal(result[key], sealed_inputs[key])
    assert result["assimilation_days"] == 3
    np.testing.assert_array_equal(
        result["truth_forecasts"], sealed_inputs["truth_forecast_discharge"]
    )

    parameter_axis = {
        parameter_id: index
        for index, parameter_id in enumerate(sealed_inputs["parameter_ids"])
    }
    for call_index, (objects, snapshot) in enumerate(assimilation_calls):
        pair_index = call_index // 2
        block = pair_index // 2
        truth = pair_index % 2
        np.testing.assert_array_equal(
            snapshot["active_forcing"], sealed_inputs["forcing_blocks"][block, 2:7]
        )
        np.testing.assert_array_equal(
            snapshot["observations"],
            sealed_inputs["observed_discharge"][block, truth, :3],
        )
        for candidate in candidates:
            np.testing.assert_array_equal(
                snapshot["initial_states"][candidate.parameter_id],
                sealed_inputs["initial_parameter_states"][
                    block, parameter_axis[candidate.parameter_id]
                ],
            )
        assert snapshot["candidate_ids"] == (
            "candidate_a", "candidate_b", "candidate_c"
        )
        assert snapshot["candidate_parameter_ids"] == (
            "parameter_a", "parameter_b", "parameter_c"
        )
        assert snapshot["assimilation_days"] == 3
        assert snapshot["leads"] == (1, 2)
        assert snapshot["observation_standard_deviation"] == 0.05
        assert snapshot["factor_transition_stay_probability"] == 0.98
        for original, copied in zip(candidates, objects["candidates"]):
            assert copied is not original

    for previous, current in zip(assimilation_calls, assimilation_calls[1:]):
        previous_objects = previous[0]
        current_objects = current[0]
        assert previous_objects["candidates"] is not current_objects["candidates"]
        assert previous_objects["initial_covariance"] is not current_objects["initial_covariance"]
        assert previous_objects["active_forcing"] is not current_objects["active_forcing"]
        assert previous_objects["observations"] is not current_objects["observations"]
        for parameter_id in ("parameter_a", "parameter_b", "parameter_c"):
            assert previous_objects["initial_states"][parameter_id] is not current_objects["initial_states"][parameter_id]

    for pair_index, compositor_call in enumerate(compositor_calls):
        block = pair_index // 2
        truth = pair_index % 2
        expected = real_compositor(*compositor_call)
        for key in (
            "full_states_full_weights", "full_states_none_weights",
            "none_states_full_weights", "none_states_none_weights",
            "prediction_nonadditivity",
        ):
            np.testing.assert_array_equal(result[key][block, truth], expected[key])

    for key, expected in sealed_copies.items():
        np.testing.assert_array_equal(sealed_inputs[key], expected)
    for candidate, expected in zip(candidates, candidate_payloads):
        np.testing.assert_array_equal(candidate.payload, expected)


@pytest.mark.parametrize(
    "case",
    ["missing_field", "candidate_order", "duplicate_parameter", "invalid_truth_label"],
)
def test_compare_state_weight_factorial_rejects_invalid_sealed_contract_before_work(
    monkeypatch,
    case,
):
    sealed_inputs, original_candidates = _sealed_driver_inputs()
    candidates = list(original_candidates)
    if case == "missing_field":
        sealed_inputs.pop("candidate_ids")
    elif case == "candidate_order":
        candidates[0], candidates[1] = candidates[1], candidates[0]
    elif case == "duplicate_parameter":
        candidates[1] = SimpleNamespace(
            candidate_id="candidate_b",
            parameter_id="parameter_a",
            payload=np.asarray([2.0]),
        )
    else:
        sealed_inputs["truth_primary_candidate_indices"][0, 2] = 3
    monkeypatch.setattr(
        diagnostic,
        "assimilate_terminal_forecast",
        lambda **kwargs: pytest.fail("invalid contract reached assimilation"),
    )

    with pytest.raises(ValueError):
        diagnostic.compare_state_weight_factorial(
            sealed_inputs,
            tuple(candidates),
            observation_standard_deviation=0.05,
            factor_transition_stay_probability=0.98,
        )


@pytest.mark.parametrize(
    ("argument", "invalid_value"),
    [
        ("observation_standard_deviation", np.nan),
        ("observation_standard_deviation", 0.0),
        ("factor_transition_stay_probability", np.inf),
        ("factor_transition_stay_probability", 1.1),
    ],
)
def test_compare_state_weight_factorial_rejects_invalid_controls_before_work(
    monkeypatch,
    argument,
    invalid_value,
):
    sealed_inputs, candidates = _sealed_driver_inputs()
    monkeypatch.setattr(
        diagnostic,
        "assimilate_terminal_forecast",
        lambda **kwargs: pytest.fail("invalid controls reached assimilation"),
    )
    controls = {
        "observation_standard_deviation": 0.05,
        "factor_transition_stay_probability": 0.98,
    }
    controls[argument] = invalid_value

    with pytest.raises(ValueError):
        diagnostic.compare_state_weight_factorial(
            sealed_inputs,
            candidates,
            **controls,
        )


@pytest.mark.parametrize(
    ("broken_field", "expected_error"),
    [
        ("states_shape", ValueError),
        ("candidate_forecasts_finite", ValueError),
        ("full_diagonal", RuntimeError),
        ("none_diagonal", RuntimeError),
    ],
)
def test_compare_state_weight_factorial_rejects_invalid_terminal_results(
    monkeypatch,
    broken_field,
    expected_error,
):
    sealed_inputs, candidates = _sealed_driver_inputs()

    def fake_assimilation(**kwargs):
        mode = kwargs["interaction_mode"]
        probabilities = np.vstack(
            [np.full(3, 1.0 / 3.0), np.full(3, 1.0 / 3.0), [0.6, 0.3, 0.1]]
        )
        candidate_forecasts = np.asarray([[1.0, 2.0, 4.0], [10.0, 20.0, 40.0]])
        states = np.zeros((3, 15))
        combined = candidate_forecasts @ probabilities[-1]
        if broken_field == "states_shape" and mode == "full":
            states = states[:, :14]
        if broken_field == "candidate_forecasts_finite" and mode == "full":
            candidate_forecasts[0, 0] = np.nan
        if broken_field == f"{mode}_diagonal":
            combined = combined.copy()
            combined[0] += 1e-6
        return diagnostic.TerminalAssimilationForecast(
            daily_probabilities=probabilities,
            final_candidate_states=states,
            final_candidate_covariances=np.broadcast_to(np.eye(15), (3, 15, 15)).copy(),
            candidate_forecasts=candidate_forecasts,
            combined_forecast=combined,
        )

    monkeypatch.setattr(diagnostic, "assimilate_terminal_forecast", fake_assimilation)

    with pytest.raises(expected_error):
        diagnostic.compare_state_weight_factorial(
            sealed_inputs,
            candidates,
            observation_standard_deviation=0.05,
            factor_transition_stay_probability=0.98,
        )


def _valid_driver_terminal_result(interaction_mode):
    probabilities = np.vstack(
        [
            np.full(3, 1.0 / 3.0),
            np.full(3, 1.0 / 3.0),
            [0.6, 0.3, 0.1],
        ]
    )
    offset = 10.0 if interaction_mode == "full" else 0.0
    candidate_forecasts = offset + np.asarray(
        [[1.0, 2.0, 4.0], [10.0, 20.0, 40.0]],
        dtype=np.float64,
    )
    return diagnostic.TerminalAssimilationForecast(
        daily_probabilities=probabilities,
        final_candidate_states=np.zeros((3, 15), dtype=np.float64),
        final_candidate_covariances=np.broadcast_to(
            np.eye(15),
            (3, 15, 15),
        ).copy(),
        candidate_forecasts=candidate_forecasts,
        combined_forecast=candidate_forecasts @ probabilities[-1],
    )


def test_compare_state_weight_factorial_allows_nonfinite_unused_segments(
    monkeypatch,
):
    sealed_inputs, candidates = _sealed_driver_inputs()
    block_count = len(sealed_inputs["block_ids"])
    unused_forcing_tail = np.full((block_count, 2, 3), np.nan)
    sealed_inputs["forcing_blocks"] = np.concatenate(
        [sealed_inputs["forcing_blocks"], unused_forcing_tail],
        axis=1,
    )
    sealed_inputs["forcing_blocks"][:, :2, :] = np.nan
    sealed_inputs["observed_discharge"][:, :, 3:] = np.nan
    sealed_inputs["truth_primary_candidate_indices"] = sealed_inputs[
        "truth_primary_candidate_indices"
    ].astype(np.float64)
    sealed_inputs["truth_primary_candidate_indices"][:, 3:] = np.nan
    calls = []

    def fake_assimilation(**kwargs):
        calls.append(kwargs)
        assert np.all(np.isfinite(kwargs["active_forcing"]))
        assert np.all(np.isfinite(kwargs["observations"]))
        return _valid_driver_terminal_result(kwargs["interaction_mode"])

    monkeypatch.setattr(diagnostic, "assimilate_terminal_forecast", fake_assimilation)

    result = diagnostic.compare_state_weight_factorial(
        sealed_inputs,
        candidates,
        observation_standard_deviation=0.05,
        factor_transition_stay_probability=0.98,
    )

    assert len(calls) == 8
    assert result["truth_forecasts"].shape == (2, 2, 2)
    for call in calls:
        assert call["active_forcing"].shape == (5, 3)
        assert call["observations"].shape == (3,)


@pytest.mark.parametrize(
    "invalid_consumed_value",
    [
        "forcing",
        "observation",
        "label_nonfinite",
        "label_fractional",
        "label_out_of_range",
    ],
)
def test_compare_state_weight_factorial_rejects_invalid_consumed_values(
    monkeypatch,
    invalid_consumed_value,
):
    sealed_inputs, candidates = _sealed_driver_inputs()
    if invalid_consumed_value == "forcing":
        sealed_inputs["forcing_blocks"][0, 2, 0] = np.nan
    elif invalid_consumed_value == "observation":
        sealed_inputs["observed_discharge"][0, 0, 2] = np.nan
    else:
        labels = sealed_inputs["truth_primary_candidate_indices"].astype(np.float64)
        labels[0, 2] = {
            "label_nonfinite": np.nan,
            "label_fractional": 1.5,
            "label_out_of_range": 3.0,
        }[invalid_consumed_value]
        sealed_inputs["truth_primary_candidate_indices"] = labels
    monkeypatch.setattr(
        diagnostic,
        "assimilate_terminal_forecast",
        lambda **kwargs: pytest.fail("invalid consumed input reached assimilation"),
    )

    with pytest.raises(ValueError):
        diagnostic.compare_state_weight_factorial(
            sealed_inputs,
            candidates,
            observation_standard_deviation=0.05,
            factor_transition_stay_probability=0.98,
        )


def test_compare_state_weight_factorial_rejects_zero_truth_trials(monkeypatch):
    sealed_inputs, candidates = _sealed_driver_inputs()
    sealed_inputs["observed_discharge"] = sealed_inputs["observed_discharge"][:, :0]
    sealed_inputs["truth_forecast_discharge"] = sealed_inputs[
        "truth_forecast_discharge"
    ][:, :0]
    sealed_inputs["truth_primary_candidate_indices"] = sealed_inputs[
        "truth_primary_candidate_indices"
    ][:0]
    monkeypatch.setattr(
        diagnostic,
        "assimilate_terminal_forecast",
        lambda **kwargs: pytest.fail("zero truth trials reached assimilation"),
    )

    with pytest.raises(ValueError):
        diagnostic.compare_state_weight_factorial(
            sealed_inputs,
            candidates,
            observation_standard_deviation=0.05,
            factor_transition_stay_probability=0.98,
        )

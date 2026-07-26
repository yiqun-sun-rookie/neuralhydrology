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
    assert result.forecast_probability_maximum_absolute_error == 0.0
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


def test_assimilate_terminal_forecast_accepts_and_records_probability_roundoff(
    monkeypatch,
):
    inputs = _terminal_inputs()
    daily_probabilities = np.asarray(
        [[0.6, 0.4], [0.25, 0.7499999999999999]],
        dtype=np.float64,
    )
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

    def rounded_forecast(*args, **kwargs):
        candidate_predictions = np.asarray([[2.0, 6.0], [10.0, 14.0]])
        normalized = daily_probabilities[-1] / daily_probabilities[-1].sum()
        probabilities = np.broadcast_to(normalized, (2, 2)).copy()
        return SimpleNamespace(
            probabilities=probabilities,
            candidate_predictions=candidate_predictions,
            combined_predictions=candidate_predictions @ normalized,
        )

    monkeypatch.setattr(
        diagnostic,
        "forecast_from_posterior",
        rounded_forecast,
    )

    result = diagnostic.assimilate_terminal_forecast(**inputs)

    assert (
        result.forecast_probability_maximum_absolute_error
        == 1.1102230246251565e-16
    )


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
        ("probabilities_threshold", RuntimeError),
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
        elif forecast_change == "probabilities_threshold":
            probabilities[1] += np.asarray([2e-12, -2e-12])
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
        "forecast_probability_maximum_absolute_error_full",
        "forecast_probability_maximum_absolute_error_none",
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
    for mode in ("full", "none"):
        errors = result[
            f"forecast_probability_maximum_absolute_error_{mode}"
        ]
        assert errors.shape == (2, 2)
        np.testing.assert_array_equal(errors, 0.0)
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


@pytest.mark.parametrize(
    ("lower", "upper", "expected"),
    [
        (-0.2, 0.2, "practically_equivalent"),
        (-0.5, -0.21, "material_improvement"),
        (0.21, 0.5, "material_harm"),
        (-0.3, 0.1, "unresolved"),
        (-0.5, -0.2, "unresolved"),
        (0.2, 0.5, "unresolved"),
    ],
)
def test_classify_effect_interval_uses_equivalence_first_and_strict_material_bounds(
    lower,
    upper,
    expected,
):
    assert (
        diagnostic.classify_effect_interval(
            lower=lower,
            upper=upper,
            equivalence_lower=-0.2,
            equivalence_upper=0.2,
        )
        == expected
    )


@pytest.mark.parametrize(
    ("lower", "upper", "equivalence_lower", "equivalence_upper"),
    [
        (np.nan, 0.0, -0.1, 0.1),
        (0.1, 0.0, -0.1, 0.1),
        (0.0, 0.1, 0.2, 0.1),
    ],
)
def test_classify_effect_interval_rejects_invalid_intervals(
    lower,
    upper,
    equivalence_lower,
    equivalence_upper,
):
    with pytest.raises(ValueError):
        diagnostic.classify_effect_interval(
            lower,
            upper,
            equivalence_lower,
            equivalence_upper,
        )


def _summary_driver_output():
    truth = np.zeros((2, 2, 1), dtype=np.float64)
    full_states_full_weights = np.asarray(
        [[[1.0], [5.0]], [[4.0], [2.0]]], dtype=np.float64
    )
    full_states_none_weights = np.asarray(
        [[[0.0], [4.0]], [[3.0], [3.0]]], dtype=np.float64
    )
    none_states_full_weights = np.asarray(
        [[[2.0], [3.0]], [[1.0], [5.0]]], dtype=np.float64
    )
    none_states_none_weights = np.asarray(
        [[[1.0], [3.0]], [[2.0], [4.0]]], dtype=np.float64
    )
    candidate_forecasts_none = np.asarray(
        [
            [[[1.0, 2.0, 4.0]], [[2.0, 3.0, 6.0]]],
            [[[2.0, 1.0, 4.0]], [[3.0, 4.0, 8.0]]],
        ],
        dtype=np.float64,
    )
    prediction_nonadditivity = (
        full_states_full_weights
        - full_states_none_weights
        - none_states_full_weights
        + none_states_none_weights
    )
    return {
        "full_states_full_weights": full_states_full_weights,
        "full_states_none_weights": full_states_none_weights,
        "none_states_full_weights": none_states_full_weights,
        "none_states_none_weights": none_states_none_weights,
        "truth_forecasts": truth,
        "candidate_forecasts_none": candidate_forecasts_none,
        "final_true_candidate_indices": np.asarray([0, 1], dtype=np.int64),
        "prediction_nonadditivity": prediction_nonadditivity,
    }


def test_summarize_state_weight_factorial_uses_named_differences_and_comparison_baselines():
    driver_output = _summary_driver_output()

    summary = diagnostic.summarize_state_weight_factorial(
        driver_output,
        bootstrap_replicates=20,
        bootstrap_seed=123,
        minimum_rmse_fraction=0.01,
    )

    assert {
        "combination_rmse",
        "squared_errors",
        "block_statistics",
        "effects",
        "wrong_candidate",
        "nonadditivity",
        "bootstrap",
    } <= set(summary)
    expected_rmse = {
        name: np.sqrt(np.mean(np.square(driver_output[name]), axis=(0, 1)))
        for name in (
            "full_states_full_weights",
            "full_states_none_weights",
            "none_states_full_weights",
            "none_states_none_weights",
        )
    }
    for name, expected in expected_rmse.items():
        np.testing.assert_allclose(summary["combination_rmse"][name], expected)
        np.testing.assert_array_equal(
            summary["squared_errors"][name], np.square(driver_output[name])
        )

    expected_effects = {
        "main_final_weight_replacement": {
            "per_block_difference": np.asarray([[1.5], [3.0]]),
            "baseline_per_block_mse": np.asarray([[5.0], [10.0]]),
            "baseline_mse": np.asarray([7.5]),
        },
        "final_weight_replacement_review": {
            "per_block_difference": np.asarray([[5.0], [1.0]]),
            "baseline_per_block_mse": np.asarray([[8.0], [9.0]]),
            "baseline_mse": np.asarray([8.5]),
        },
        "main_candidate_forecast_distribution_replacement": {
            "per_block_difference": np.asarray([[3.0], [-1.0]]),
            "baseline_per_block_mse": np.asarray([[5.0], [10.0]]),
            "baseline_mse": np.asarray([7.5]),
        },
        "candidate_forecast_distribution_replacement_review": {
            "per_block_difference": np.asarray([[6.5], [-3.0]]),
            "baseline_per_block_mse": np.asarray([[6.5], [13.0]]),
            "baseline_mse": np.asarray([9.75]),
        },
        "complete_full_minus_none": {
            "per_block_difference": np.asarray([[8.0], [0.0]]),
            "baseline_per_block_mse": np.asarray([[5.0], [10.0]]),
            "baseline_mse": np.asarray([7.5]),
        },
    }
    assert set(summary["effects"]) == set(expected_effects)
    for name, expected_fields in expected_effects.items():
        effect = summary["effects"][name]
        for field, expected in expected_fields.items():
            np.testing.assert_allclose(effect[field], expected)
        np.testing.assert_allclose(
            effect["mean"], expected_fields["per_block_difference"].mean(axis=0)
        )
        np.testing.assert_array_equal(
            summary["block_statistics"][name]["per_block_difference"],
            effect["per_block_difference"],
        )
        np.testing.assert_array_equal(
            summary["block_statistics"][name]["baseline_per_block_mse"],
            effect["baseline_per_block_mse"],
        )
        np.testing.assert_allclose(
            effect["equivalence_lower"],
            -0.0199 * expected_fields["baseline_mse"],
        )
        np.testing.assert_allclose(
            effect["equivalence_upper"],
            0.0201 * expected_fields["baseline_mse"],
        )


def test_summarize_state_weight_factorial_reuses_one_matched_block_bootstrap():
    driver_output = _summary_driver_output()
    replicates = 12
    seed = 8301

    summary = diagnostic.summarize_state_weight_factorial(
        driver_output,
        bootstrap_replicates=replicates,
        bootstrap_seed=seed,
        minimum_rmse_fraction=0.01,
    )

    expected_indices = np.random.default_rng(seed).integers(
        0, 2, size=(replicates, 2)
    )
    np.testing.assert_array_equal(summary["bootstrap"]["indices"], expected_indices)
    assert summary["bootstrap"]["replicates"] == replicates
    assert summary["bootstrap"]["seed"] == seed
    for effect in summary["effects"].values():
        expected_bootstrap = effect["per_block_difference"][expected_indices].mean(axis=1)
        np.testing.assert_allclose(effect["bootstrap_mean"], expected_bootstrap)
        np.testing.assert_allclose(
            effect["ci_low"], np.percentile(expected_bootstrap, 2.5, axis=0)
        )
        np.testing.assert_allclose(
            effect["ci_high"], np.percentile(expected_bootstrap, 97.5, axis=0)
        )


def _ratio_driver_output(true_predictions):
    true_predictions = np.asarray(true_predictions, dtype=np.float64)
    block_count = true_predictions.size
    truth = np.zeros((block_count, 1, 1), dtype=np.float64)
    candidate_forecasts_none = np.empty((block_count, 1, 1, 2), dtype=np.float64)
    candidate_forecasts_none[:, 0, 0, 0] = true_predictions
    candidate_forecasts_none[:, 0, 0, 1] = np.asarray(
        [2.0, 4.0][:block_count], dtype=np.float64
    )
    diagonal = true_predictions[:, None, None]
    return {
        "full_states_full_weights": diagonal + 0.1,
        "full_states_none_weights": diagonal + 0.2,
        "none_states_full_weights": diagonal + 0.3,
        "none_states_none_weights": diagonal.copy(),
        "truth_forecasts": truth,
        "candidate_forecasts_none": candidate_forecasts_none,
        "final_true_candidate_indices": np.asarray([0], dtype=np.int64),
    }


def test_wrong_candidate_ratio_is_ratio_of_resampled_root_mean_squares():
    driver_output = _ratio_driver_output([1.0, 1.0])

    summary = diagnostic.summarize_state_weight_factorial(
        driver_output,
        bootstrap_replicates=5,
        bootstrap_seed=7,
        minimum_rmse_fraction=0.01,
    )

    wrong = summary["wrong_candidate"]
    np.testing.assert_array_equal(wrong["wrong_candidate_indices"], [[1]])
    np.testing.assert_array_equal(wrong["num_sq_per_block"], [[1.0], [9.0]])
    np.testing.assert_array_equal(wrong["den_sq_per_block"], [[1.0], [1.0]])
    np.testing.assert_allclose(wrong["displacement_ratio"], [np.sqrt(5.0)])
    expected_bootstrap_ratios = np.asarray(
        [[3.0], [3.0], [3.0], [np.sqrt(5.0)], [1.0]]
    )
    np.testing.assert_allclose(
        wrong["displacement_ratio_bootstrap"], expected_bootstrap_ratios
    )
    np.testing.assert_allclose(
        wrong["displacement_ratio_ci_low"],
        np.percentile(expected_bootstrap_ratios, 2.5, axis=0),
    )
    np.testing.assert_allclose(
        wrong["displacement_ratio_ci_high"],
        np.percentile(expected_bootstrap_ratios, 97.5, axis=0),
    )
    np.testing.assert_array_equal(
        wrong["error_difference"]["baseline_per_block_mse"], [[1.0], [1.0]]
    )
    np.testing.assert_array_equal(
        wrong["error_difference"]["per_block_difference"], [[3.0], [15.0]]
    )
    np.testing.assert_allclose(
        wrong["error_difference"]["equivalence_lower"], [-0.0199]
    )
    np.testing.assert_allclose(
        wrong["error_difference"]["equivalence_upper"], [0.0201]
    )
    np.testing.assert_array_equal(wrong["equivalent"], [False])


def test_wrong_candidate_equivalence_requires_displacement_strictly_below_fraction():
    truth = np.zeros((2, 1, 1), dtype=np.float64)
    candidate_forecasts = np.broadcast_to(
        np.asarray([1.0, 1.125], dtype=np.float64), (2, 1, 1, 2)
    ).copy()
    diagonal = np.ones((2, 1, 1), dtype=np.float64)
    driver_output = {
        "full_states_full_weights": diagonal,
        "full_states_none_weights": diagonal,
        "none_states_full_weights": diagonal,
        "none_states_none_weights": diagonal,
        "truth_forecasts": truth,
        "candidate_forecasts_none": candidate_forecasts,
        "final_true_candidate_indices": np.asarray([0], dtype=np.int64),
    }

    summary = diagnostic.summarize_state_weight_factorial(
        driver_output,
        bootstrap_replicates=4,
        bootstrap_seed=3,
        minimum_rmse_fraction=0.125,
    )

    wrong = summary["wrong_candidate"]
    np.testing.assert_allclose(wrong["displacement_ratio_ci_high"], [0.125])
    np.testing.assert_array_equal(
        wrong["error_difference"]["classification"], ["practically_equivalent"]
    )
    np.testing.assert_array_equal(wrong["equivalent"], [False])


def test_summarize_state_weight_factorial_saves_both_nonadditivity_terms():
    driver_output = _summary_driver_output()

    summary = diagnostic.summarize_state_weight_factorial(
        driver_output,
        bootstrap_replicates=8,
        bootstrap_seed=14,
        minimum_rmse_fraction=0.01,
    )

    ff = driver_output["full_states_full_weights"]
    fn = driver_output["full_states_none_weights"]
    nf = driver_output["none_states_full_weights"]
    nn = driver_output["none_states_none_weights"]
    truth = driver_output["truth_forecasts"]
    expected_prediction = ff - fn - nf + nn
    expected_squared_error = (
        np.square(ff - truth)
        - np.square(fn - truth)
        - np.square(nf - truth)
        + np.square(nn - truth)
    )
    for name, expected in (
        ("prediction", expected_prediction),
        ("squared_error", expected_squared_error),
    ):
        term = summary["nonadditivity"][name]
        np.testing.assert_array_equal(term["raw"], expected)
        np.testing.assert_allclose(term["per_block"], expected.mean(axis=1))
        np.testing.assert_allclose(term["mean"], expected.mean(axis=(0, 1)))
        assert "classification" not in term
    assert summary["nonadditivity"]["squared_error_algebra_maximum_absolute_error"] == 0.0


def test_summarize_state_weight_factorial_rejects_mismatched_nonadditivity():
    driver_output = _summary_driver_output()
    driver_output["prediction_nonadditivity"] = driver_output[
        "prediction_nonadditivity"
    ].copy()
    driver_output["prediction_nonadditivity"][0, 0, 0] += 1e-12

    with pytest.raises(ValueError):
        diagnostic.summarize_state_weight_factorial(
            driver_output,
            bootstrap_replicates=8,
            bootstrap_seed=14,
            minimum_rmse_fraction=0.01,
        )


@pytest.mark.parametrize("zero_case", ["point", "bootstrap"])
def test_summarize_state_weight_factorial_rejects_zero_true_candidate_denominator(
    zero_case,
):
    true_predictions = [0.0, 0.0] if zero_case == "point" else [0.0, 1.0]
    driver_output = _ratio_driver_output(true_predictions)

    with pytest.raises(ValueError, match="denominator"):
        diagnostic.summarize_state_weight_factorial(
            driver_output,
            bootstrap_replicates=5,
            bootstrap_seed=7,
            minimum_rmse_fraction=0.01,
        )


@pytest.mark.parametrize(
    "invalid_case",
    [
        "missing_combination",
        "combination_shape",
        "nonfinite_truth",
        "candidate_shape",
        "one_candidate",
        "truth_index_shape",
        "truth_index_fractional",
        "truth_index_boolean",
        "truth_index_out_of_range",
        "zero_blocks",
        "zero_truths",
        "zero_leads",
    ],
)
def test_summarize_state_weight_factorial_rejects_invalid_driver_arrays(invalid_case):
    driver_output = _summary_driver_output()
    if invalid_case == "missing_combination":
        driver_output.pop("full_states_full_weights")
    elif invalid_case == "combination_shape":
        driver_output["full_states_full_weights"] = np.zeros((2, 2, 2))
    elif invalid_case == "nonfinite_truth":
        driver_output["truth_forecasts"][0, 0, 0] = np.nan
    elif invalid_case == "candidate_shape":
        driver_output["candidate_forecasts_none"] = np.zeros((2, 2, 1))
    elif invalid_case == "one_candidate":
        driver_output["candidate_forecasts_none"] = driver_output[
            "candidate_forecasts_none"
        ][..., :1]
    elif invalid_case == "truth_index_shape":
        driver_output["final_true_candidate_indices"] = np.asarray([[0, 1]])
    elif invalid_case == "truth_index_fractional":
        driver_output["final_true_candidate_indices"] = np.asarray([0.0, 1.5])
    elif invalid_case == "truth_index_boolean":
        driver_output["final_true_candidate_indices"] = np.asarray([False, True])
    elif invalid_case == "truth_index_out_of_range":
        driver_output["final_true_candidate_indices"] = np.asarray([0, 3])
    else:
        axis = {"zero_blocks": 0, "zero_truths": 1, "zero_leads": 2}[invalid_case]
        slicer = [slice(None), slice(None), slice(None)]
        slicer[axis] = slice(0, 0)
        for name in (
            "full_states_full_weights",
            "full_states_none_weights",
            "none_states_full_weights",
            "none_states_none_weights",
            "truth_forecasts",
            "prediction_nonadditivity",
        ):
            driver_output[name] = driver_output[name][tuple(slicer)]
        candidate_slicer = slicer + [slice(None)]
        driver_output["candidate_forecasts_none"] = driver_output[
            "candidate_forecasts_none"
        ][tuple(candidate_slicer)]
        if invalid_case == "zero_truths":
            driver_output["final_true_candidate_indices"] = np.asarray([], dtype=np.int64)

    with pytest.raises(ValueError):
        diagnostic.summarize_state_weight_factorial(
            driver_output,
            bootstrap_replicates=8,
            bootstrap_seed=14,
            minimum_rmse_fraction=0.01,
        )


@pytest.mark.parametrize(
    ("control", "invalid_value"),
    [
        ("bootstrap_replicates", 0),
        ("bootstrap_replicates", 1.5),
        ("bootstrap_replicates", True),
        ("bootstrap_seed", -1),
        ("bootstrap_seed", 1.5),
        ("bootstrap_seed", True),
        ("minimum_rmse_fraction", 0.0),
        ("minimum_rmse_fraction", 1.0),
        ("minimum_rmse_fraction", np.nan),
        ("minimum_rmse_fraction", True),
    ],
)
def test_summarize_state_weight_factorial_rejects_invalid_controls(
    control,
    invalid_value,
):
    controls = {
        "bootstrap_replicates": 8,
        "bootstrap_seed": 14,
        "minimum_rmse_fraction": 0.01,
    }
    controls[control] = invalid_value

    with pytest.raises(ValueError):
        diagnostic.summarize_state_weight_factorial(
            _summary_driver_output(),
            **controls,
        )


def test_summarize_state_weight_factorial_keys_do_not_claim_a_pure_state_effect():
    summary = diagnostic.summarize_state_weight_factorial(
        _summary_driver_output(),
        bootstrap_replicates=8,
        bootstrap_seed=14,
        minimum_rmse_fraction=0.01,
    )
    pending = [summary]
    keys = []
    while pending:
        current = pending.pop()
        if isinstance(current, dict):
            keys.extend(str(key) for key in current)
            pending.extend(current.values())

    assert not any("pure_state" in key or "state_effect" in key for key in keys)


@pytest.mark.parametrize(
    "existing_kind",
    ["final", "incomplete", "preregistered", "preregistered_incomplete"],
)
def test_state_weight_runner_refuses_existing_artifact_before_reading_config(
    tmp_path,
    existing_kind,
):
    from hbv_multilead_joint_uncertainty.scripts.run_g3_state_weight_factorial import (
        run,
    )

    output = tmp_path / "results" / "experiment"
    existing = {
        "final": output,
        "incomplete": output.with_name(output.name + ".incomplete"),
        "preregistered": output.with_name(output.name + ".preregistered.json"),
        "preregistered_incomplete": output.with_name(
            output.name + ".preregistered.json.incomplete"
        ),
    }[existing_kind]
    if existing_kind in {"preregistered", "preregistered_incomplete"}:
        existing.parent.mkdir(parents=True)
        existing.write_text("frozen", encoding="utf-8")
    else:
        existing.mkdir(parents=True)

    with pytest.raises(FileExistsError):
        run(
            repo_root=tmp_path,
            config_path=tmp_path / "missing-config.json",
            output_dir=output,
        )


def _state_weight_runner_case(tmp_path, monkeypatch):
    import hashlib
    import json

    from hbv_joint_uncertainty.hbv_adapter import PARAMETER_NAMES
    from hbv_multilead_joint_uncertainty.scripts import (
        run_g3_state_weight_factorial as runner,
    )

    root = tmp_path / "repo"
    root.mkdir()
    experiment_id = "state_weight_test"
    output = root / "results" / experiment_id
    block_ids = np.asarray(["block_b", "block_a"])
    parameter_ids = np.asarray(["parameter_a", "parameter_b"])
    process_ids = np.asarray(["process_a", "process_b"])
    candidate_ids = np.asarray(["parameter_a__process_a", "parameter_b__process_a"])
    method_names = np.asarray(["joint", "parameter_only", "fixed_filter"])
    method_candidate_ids = np.asarray(
        [
            ["unused_joint_0", "unused_joint_1"],
            candidate_ids,
            ["unused_fixed", ""],
        ]
    )
    method_candidate_counts = np.asarray([2, 2, 1], dtype=np.int64)
    parameter_array = np.asarray(
        [
            np.arange(1.0, len(PARAMETER_NAMES) + 1.0),
            np.arange(101.0, 101.0 + len(PARAMETER_NAMES)),
        ],
        dtype=np.float64,
    )
    process_covariance_array = np.asarray(
        [np.eye(15, dtype=np.float64), np.eye(15, dtype=np.float64) * 2.0]
    )
    observation_standard_deviation = 0.25
    warmup_days = 1
    assimilation_days = 2
    leads = np.asarray([1, 2], dtype=np.int64)
    active_days = assimilation_days + int(leads[-1])
    block_count = len(block_ids)
    truth_count = 2
    candidate_count = len(candidate_ids)
    forcing_blocks = np.arange(
        block_count * (warmup_days + active_days) * 3, dtype=np.float64
    ).reshape(block_count, warmup_days + active_days, 3)
    observed_discharge = (
        np.arange(block_count * truth_count * active_days, dtype=np.float64)
        .reshape(block_count, truth_count, active_days)
        + 10.0
    )
    truth_forecasts = np.asarray(
        [
            [[2.0, 4.0], [3.0, 6.0]],
            [[5.0, 7.0], [6.0, 9.0]],
        ],
        dtype=np.float64,
    )
    true_candidate_labels = np.asarray([[0, 0], [1, 1]], dtype=np.int64)
    truth_primary_candidate_indices = np.asarray(
        [[0, 0, 0, 0], [1, 1, 1, 1]], dtype=np.int64
    )
    initial_parameter_states = np.arange(
        block_count * len(parameter_ids) * 15, dtype=np.float64
    ).reshape(block_count, len(parameter_ids), 15)
    initial_covariances = np.broadcast_to(
        np.eye(15, dtype=np.float64), (block_count, 15, 15)
    ).copy()

    ideal_path = root / "sealed" / "ideal.npz"
    ideal_path.parent.mkdir(parents=True)
    np.savez_compressed(
        ideal_path,
        block_ids=block_ids,
        forcing_blocks=forcing_blocks,
        warmup_days=np.asarray(warmup_days, dtype=np.int64),
        assimilation_days=np.asarray(assimilation_days, dtype=np.int64),
        forecast_lead_days=leads,
        initial_parameter_states=initial_parameter_states,
        initial_covariances=initial_covariances,
        observed_discharge=observed_discharge,
        truth_forecast_discharge=truth_forecasts,
        truth_primary_candidate_indices=truth_primary_candidate_indices,
        method_names=method_names,
        method_candidate_ids=method_candidate_ids,
        method_candidate_counts=method_candidate_counts,
        parameter_ids=parameter_ids,
        process_ids=process_ids,
        parameter_vectors=parameter_array,
        process_covariances=process_covariance_array,
        observation_standard_deviation=np.asarray(
            observation_standard_deviation, dtype=np.float64
        ),
    )

    probabilities_full = np.asarray(
        [
            [
                [[0.6, 0.4], [0.8, 0.2]],
                [[0.3, 0.7], [0.1, 0.9]],
            ],
            [
                [[0.55, 0.45], [0.7, 0.3]],
                [[0.4, 0.6], [0.2, 0.8]],
            ],
        ],
        dtype=np.float64,
    )
    probabilities_none = np.asarray(
        [
            [
                [[0.5, 0.5], [0.65, 0.35]],
                [[0.45, 0.55], [0.25, 0.75]],
            ],
            [
                [[0.6, 0.4], [0.6, 0.4]],
                [[0.35, 0.65], [0.3, 0.7]],
            ],
        ],
        dtype=np.float64,
    )
    candidate_forecasts_none = np.asarray(
        [
            [
                [[1.0, 3.0], [3.0, 5.0]],
                [[2.0, 4.0], [5.0, 7.0]],
            ],
            [
                [[4.0, 6.0], [6.0, 8.0]],
                [[5.0, 7.0], [8.0, 10.0]],
            ],
        ],
        dtype=np.float64,
    )
    candidate_forecasts_full = candidate_forecasts_none + np.asarray(
        [0.25, -0.15], dtype=np.float64
    )
    full_combination = np.einsum(
        "btlc,btc->btl", candidate_forecasts_full, probabilities_full[:, :, -1]
    )
    none_combination = np.einsum(
        "btlc,btc->btl", candidate_forecasts_none, probabilities_none[:, :, -1]
    )
    full_none_combination = np.einsum(
        "btlc,btc->btl", candidate_forecasts_full, probabilities_none[:, :, -1]
    )
    none_full_combination = np.einsum(
        "btlc,btc->btl", candidate_forecasts_none, probabilities_full[:, :, -1]
    )

    reference_path = root / "sealed" / "reference.npz"
    np.savez_compressed(
        reference_path,
        block_ids=block_ids,
        leads=leads,
        assimilation_days=np.asarray(assimilation_days, dtype=np.int64),
        true_candidate_labels=true_candidate_labels,
        truth_forecasts=truth_forecasts,
        probabilities_full=probabilities_full,
        probabilities_none=probabilities_none,
        forecast_none_candidates=candidate_forecasts_none,
        forecast_full=full_combination + 5e-13,
        forecast_none=none_combination - 5e-13,
    )

    def sha256(path):
        return hashlib.sha256(path.read_bytes()).hexdigest()

    protected = root / "frozen" / "artifact.txt"
    protected.parent.mkdir()
    protected.write_text("immutable", encoding="utf-8")
    config = {
        "experiment_id": experiment_id,
        "scenario": "parameter_switch",
        "sealed_ideal_input_evidence": {
            "path": ideal_path.relative_to(root).as_posix(),
            "sha256": sha256(ideal_path),
        },
        "sealed_forecast_reference_evidence": {
            "path": reference_path.relative_to(root).as_posix(),
            "sha256": sha256(reference_path),
        },
        "primary_candidate_method_name": "parameter_only",
        "candidate_order": candidate_ids.tolist(),
        "matched_blocks": [
            {"block_id": str(block_id)} for block_id in block_ids
        ],
        "lead_days": leads.tolist(),
        "stage_lengths": [1, 1],
        "parameter_source": {"parameter_ids": parameter_ids.tolist()},
        "process_noise_source": {
            "process_ids": process_ids.tolist(),
            "selected_process_id": "process_a",
        },
        "observation_noise_source": {"source": "synthetic"},
        "factor_transition_stay_probability": 0.98,
        "bootstrap": {
            "replicates": 7,
            "seed": 77,
            "minimum_rmse_fraction": 0.01,
        },
        "resource_pilot": {"source": "synthetic"},
        "protected_paths": [protected.relative_to(root).as_posix()],
        "forecast_contract": {
            "transition": "identity",
            "probabilities": "fixed_final",
            "state_mixing": "none",
        },
        "scope_limit": "synthetic runner test",
    }
    config_path = root / "config.json"

    def write_config():
        config_path.write_text(
            json.dumps(config, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )

    write_config()
    parameter_vectors = {
        parameter_id: {
            name: float(parameter_array[index, column])
            for column, name in enumerate(PARAMETER_NAMES)
        }
        for index, parameter_id in enumerate(parameter_ids)
    }
    process_covariances = {
        process_id: process_covariance_array[index].copy()
        for index, process_id in enumerate(process_ids)
    }
    process_scales = {"process_a": 1.0, "process_b": 2.0}
    parameter_csv = b"parameter csv\n"
    process_csv = b"process csv\n"
    observation_csv = b"observation csv\n"
    monkeypatch.setattr(
        runner,
        "_load_parameter_vectors",
        lambda root_arg, config_arg: (
            parameter_vectors,
            parameter_csv,
            sha256_bytes(parameter_csv),
        ),
    )
    monkeypatch.setattr(
        runner,
        "_load_process_covariances",
        lambda root_arg, config_arg: (
            process_covariances,
            process_scales,
            process_csv,
            sha256_bytes(process_csv),
        ),
    )
    monkeypatch.setattr(
        runner,
        "_load_observation_noise",
        lambda root_arg, config_arg: (
            observation_standard_deviation,
            observation_csv,
            sha256_bytes(observation_csv),
        ),
    )
    monkeypatch.setattr(
        runner,
        "_resource_preflight",
        lambda config_arg, root_arg: {"safe_to_run": True, "test": True},
    )
    monkeypatch.setattr(
        runner,
        "_environment",
        lambda root_arg, started: {"started_at_utc": started, "test": True},
    )

    candidates = tuple(
        SimpleNamespace(
            candidate_id=candidate_id,
            parameter_id=parameter_id,
            process_id="process_a",
        )
        for candidate_id, parameter_id in zip(candidate_ids[::-1], parameter_ids[::-1])
    )
    methods = {
        "fixed_filter": (SimpleNamespace(candidate_id="unused_fixed"),),
        "parameter_only": candidates,
        "joint": (SimpleNamespace(candidate_id="unused_joint_0"),),
    }
    monkeypatch.setattr(
        runner,
        "build_method_definitions",
        lambda *args, **kwargs: methods,
    )
    calls = {"compare": 0, "summarize": 0, "candidate_order": None}
    driver = {
        "probabilities_full": probabilities_full,
        "probabilities_none": probabilities_none,
        "forecast_probability_maximum_absolute_error_full": np.zeros(
            (block_count, truth_count), dtype=np.float64
        ),
        "forecast_probability_maximum_absolute_error_none": np.full(
            (block_count, truth_count), 1.1102230246251565e-16, dtype=np.float64
        ),
        "final_candidate_states_full": np.ones(
            (block_count, truth_count, candidate_count, 15), dtype=np.float64
        ),
        "final_candidate_states_none": np.ones(
            (block_count, truth_count, candidate_count, 15), dtype=np.float64
        )
        * 2.0,
        "final_candidate_covariances_full": np.broadcast_to(
            np.eye(15), (block_count, truth_count, candidate_count, 15, 15)
        ).copy(),
        "final_candidate_covariances_none": np.broadcast_to(
            np.eye(15) * 2.0,
            (block_count, truth_count, candidate_count, 15, 15),
        ).copy(),
        "candidate_forecasts_full": candidate_forecasts_full,
        "candidate_forecasts_none": candidate_forecasts_none,
        "full_states_full_weights": full_combination,
        "full_states_none_weights": full_none_combination,
        "none_states_full_weights": none_full_combination,
        "none_states_none_weights": none_combination,
        "prediction_nonadditivity": (
            full_combination
            - full_none_combination
            - none_full_combination
            + none_combination
        ),
        "truth_forecasts": truth_forecasts,
        "final_true_candidate_indices": true_candidate_labels[:, -1],
        "final_true_candidate_ids": candidate_ids[true_candidate_labels[:, -1]],
        "candidate_ids": candidate_ids,
        "parameter_ids": parameter_ids,
        "block_ids": block_ids,
        "forecast_lead_days": leads,
        "assimilation_days": assimilation_days,
    }

    def fake_compare(sealed_inputs, ordered_candidates, observation_std, stay):
        calls["compare"] += 1
        calls["candidate_order"] = tuple(
            candidate.candidate_id for candidate in ordered_candidates
        )
        assert observation_std == observation_standard_deviation
        assert stay == 0.98
        np.testing.assert_array_equal(sealed_inputs["block_ids"], block_ids)
        return {key: np.asarray(value).copy() for key, value in driver.items()}

    statistics = {
        "combination_rmse": {
            "full_states_full_weights": np.asarray([1.0, 2.0]),
            "none_states_none_weights": np.asarray([1.1, 2.1]),
        },
        "squared_errors": {
            name: np.square(driver[name] - truth_forecasts)
            for name in (
                "full_states_full_weights",
                "full_states_none_weights",
                "none_states_full_weights",
                "none_states_none_weights",
            )
        },
        "block_statistics": {
            "complete_full_minus_none": {
                "per_block_difference": np.ones((block_count, len(leads))),
                "baseline_per_block_mse": np.ones((block_count, len(leads))) * 2.0,
            }
        },
        "effects": {
            "complete_full_minus_none": {
                "mean": np.asarray([0.1, 0.2]),
                "ci_low": np.asarray([-0.1, -0.2]),
                "ci_high": np.asarray([0.2, 0.3]),
                "baseline_mse": np.asarray([2.0, 3.0]),
                "equivalence_lower": np.asarray([-0.0398, -0.0597]),
                "equivalence_upper": np.asarray([0.0402, 0.0603]),
                "classification": np.asarray(["unresolved", "unresolved"]),
            }
        },
        "wrong_candidate": {
            "num_sq_per_block": np.ones((block_count, len(leads))),
            "den_sq_per_block": np.ones((block_count, len(leads))) * 2.0,
            "wrong_minus_true_squared_error": np.ones(
                (block_count, truth_count, len(leads), 1)
            ),
        },
        "nonadditivity": {
            "prediction": {"raw": driver["prediction_nonadditivity"]},
            "squared_error": {"raw": np.zeros_like(truth_forecasts)},
        },
        "bootstrap": {
            "indices": np.zeros((7, block_count), dtype=np.int64),
            "replicates": 7,
            "seed": 77,
            "minimum_rmse_fraction": 0.01,
        },
    }

    def fake_summarize(driver_arg, bootstrap_replicates, bootstrap_seed, minimum_rmse_fraction):
        calls["summarize"] += 1
        assert bootstrap_replicates == 7
        assert bootstrap_seed == 77
        assert minimum_rmse_fraction == 0.01
        return statistics

    monkeypatch.setattr(runner, "compare_state_weight_factorial", fake_compare)
    monkeypatch.setattr(runner, "summarize_state_weight_factorial", fake_summarize)
    for relative in runner._SOURCE_FILES:
        source = root / relative
        source.parent.mkdir(parents=True, exist_ok=True)
        source.write_text(f"snapshot: {relative}\n", encoding="utf-8")
    return SimpleNamespace(
        runner=runner,
        root=root,
        output=output,
        config=config,
        config_path=config_path,
        write_config=write_config,
        ideal_path=ideal_path,
        reference_path=reference_path,
        calls=calls,
        candidate_ids=candidate_ids,
        parameter_vectors=parameter_vectors,
        parameter_array=parameter_array,
        driver=driver,
        statistics=statistics,
    )


def sha256_bytes(value):
    import hashlib

    return hashlib.sha256(value).hexdigest()


def test_state_weight_runner_source_snapshot_contract_is_complete_and_not_flattened():
    from hbv_multilead_joint_uncertainty.scripts import (
        run_g3_state_weight_factorial as runner,
    )

    required = {
        "src/hbv_multilead_joint_uncertainty/state_weight_factorial_diagnostic.py",
        "src/hbv_multilead_joint_uncertainty/scripts/run_g3_state_weight_factorial.py",
        "test/test_hbv_state_weight_factorial_diagnostic.py",
        "test/test_hbv_state_weight_factorial_config_contract.py",
        "src/hbv_multilead_joint_uncertainty/methods.py",
        "src/hbv_multilead_joint_uncertainty/forecast.py",
        "src/hbv_joint_uncertainty/candidates.py",
        "src/hbv_joint_uncertainty/hbv_adapter.py",
        "src/hbv_joint_uncertainty/preflight.py",
        "src/hbv_joint_uncertainty/imm.py",
        "src/hbv_joint_uncertainty/sigma_filter.py",
        "src/scl_hydro/hbv_lite_numpy.py",
    }
    assert required <= set(runner._SOURCE_FILES)
    assert len(runner._SOURCE_FILES) == len(set(runner._SOURCE_FILES))


def test_state_weight_runner_rejects_output_name_before_preregistration(tmp_path):
    import json

    from hbv_multilead_joint_uncertainty.scripts.run_g3_state_weight_factorial import run

    config_path = tmp_path / "config.json"
    config_path.write_text(json.dumps({"experiment_id": "expected"}), encoding="utf-8")
    output = tmp_path / "wrong"

    with pytest.raises(ValueError, match="experiment_id"):
        run(tmp_path, config_path, output)

    assert not output.with_name(output.name + ".preregistered.json").exists()


def test_state_weight_runner_packages_auditable_evidence_and_refuses_second_run(
    tmp_path,
    monkeypatch,
):
    import hashlib
    import json

    case = _state_weight_runner_case(tmp_path, monkeypatch)

    summary = case.runner.run(case.root, case.config_path, case.output)

    assert case.calls["compare"] == 1
    assert case.calls["summarize"] == 1
    assert case.calls["candidate_order"] == tuple(case.candidate_ids)
    assert summary["integrity_status"] == "passed"
    assert summary["candidate_ids"] == case.candidate_ids.tolist()
    assert summary["candidate_parameter_ids"] == ["parameter_a", "parameter_b"]
    assert summary["result"]["forecast_lead_days"] == [1, 2]
    assert summary["forecast_probability_maximum_absolute_error"] == {
        "full": 0.0,
        "none": 1.1102230246251565e-16,
    }
    assert case.output.is_dir()
    assert case.output.with_name(case.output.name + ".preregistered.json").is_file()
    cross_checks = json.loads((case.output / "cross_checks.json").read_text(encoding="utf-8"))
    assert cross_checks["passed"] is True
    assert cross_checks["historical_full_combination"]["maximum_absolute_error"] <= 1e-12
    assert cross_checks["historical_none_combination"]["maximum_absolute_error"] <= 1e-12
    assert cross_checks["parameter_vectors_direct"]["maximum_absolute_error"] == 0.0
    assert cross_checks["forecast_probability_freezing_full"] == {
        "contract": "maximum_absolute_error<=1e-12",
        "maximum_absolute_error": 0.0,
        "passed": True,
    }
    assert cross_checks["forecast_probability_freezing_none"]["passed"] is True
    with np.load(case.output / "evidence.npz", allow_pickle=False) as evidence:
        required_keys = {
            "driver__candidate_forecasts_full",
            "driver__candidate_forecasts_none",
            "driver__final_probabilities_full",
            "driver__final_probabilities_none",
            "driver__forecast_probability_maximum_absolute_error_full",
            "driver__forecast_probability_maximum_absolute_error_none",
            "driver__final_candidate_states_full",
            "driver__final_candidate_covariances_none",
            "driver__full_states_full_weights",
            "driver__none_states_none_weights",
            "driver__prediction_nonadditivity",
            "driver__truth_forecasts",
            "statistics__squared_errors__full_states_full_weights",
            "statistics__block_statistics__complete_full_minus_none__per_block_difference",
            "statistics__effects__complete_full_minus_none__baseline_mse",
            "statistics__effects__complete_full_minus_none__equivalence_lower",
            "statistics__wrong_candidate__num_sq_per_block",
            "statistics__wrong_candidate__den_sq_per_block",
            "statistics__nonadditivity__squared_error__raw",
            "statistics__bootstrap__indices",
            "identity__candidate_ids",
            "identity__candidate_parameter_ids",
            "input_identity__sealed_ideal_input_evidence_sha256",
            "input_identity__sealed_forecast_reference_evidence_sha256",
            "cross_checks__historical_full_combination__maximum_absolute_error",
        }
        assert required_keys <= set(evidence.files)
        np.testing.assert_array_equal(
            evidence["identity__candidate_ids"], case.candidate_ids
        )
        np.testing.assert_array_equal(
            evidence["driver__final_probabilities_full"],
            case.driver["probabilities_full"][:, :, -1, :],
        )
        np.testing.assert_array_equal(
            evidence["driver__final_probabilities_none"],
            case.driver["probabilities_none"][:, :, -1, :],
        )
    snapshot = (
        case.output
        / "source_snapshot"
        / "src"
        / "hbv_multilead_joint_uncertainty"
        / "state_weight_factorial_diagnostic.py"
    )
    assert snapshot.is_file()
    checksums = json.loads((case.output / "checksums.json").read_text(encoding="utf-8"))
    for relative, expected in checksums.items():
        actual = hashlib.sha256((case.output / relative).read_bytes()).hexdigest()
        assert actual == expected

    with pytest.raises(FileExistsError):
        case.runner.run(case.root, case.config_path, case.output)
    assert case.calls["compare"] == 1


def test_state_weight_runner_rejects_bad_sealed_hash_before_scientific_work(
    tmp_path,
    monkeypatch,
):
    case = _state_weight_runner_case(tmp_path, monkeypatch)
    case.config["sealed_ideal_input_evidence"]["sha256"] = "0" * 64
    case.write_config()

    with pytest.raises(ValueError, match="checksum"):
        case.runner.run(case.root, case.config_path, case.output)

    assert case.calls["compare"] == 0


def test_state_weight_runner_rejects_protected_overlap_before_preregistration(
    tmp_path,
    monkeypatch,
):
    case = _state_weight_runner_case(tmp_path, monkeypatch)
    case.config["protected_paths"] = [case.output.parent.relative_to(case.root).as_posix()]
    case.write_config()

    with pytest.raises(ValueError, match="overlap"):
        case.runner.run(case.root, case.config_path, case.output)

    assert not case.output.with_name(case.output.name + ".preregistered.json").exists()
    assert case.calls["compare"] == 0


def test_state_weight_runner_stops_when_resource_preflight_is_unsafe(
    tmp_path,
    monkeypatch,
):
    case = _state_weight_runner_case(tmp_path, monkeypatch)
    monkeypatch.setattr(
        case.runner,
        "_resource_preflight",
        lambda config_arg, root_arg: {"safe_to_run": False},
    )

    with pytest.raises(MemoryError):
        case.runner.run(case.root, case.config_path, case.output)

    assert case.calls["compare"] == 0
    assert case.output.with_name(case.output.name + ".preregistered.json").is_file()


def test_state_weight_runner_direct_array_gate_is_bit_exact(
    tmp_path,
    monkeypatch,
):
    case = _state_weight_runner_case(tmp_path, monkeypatch)
    changed = {
        key: dict(value) for key, value in case.parameter_vectors.items()
    }
    first_name = next(iter(changed["parameter_a"]))
    changed["parameter_a"][first_name] += 1e-15
    monkeypatch.setattr(
        case.runner,
        "_load_parameter_vectors",
        lambda root_arg, config_arg: (
            changed,
            b"changed parameter csv\n",
            sha256_bytes(b"changed parameter csv\n"),
        ),
    )

    with pytest.raises(ValueError, match="parameter_vectors"):
        case.runner.run(case.root, case.config_path, case.output)

    assert case.calls["compare"] == 0


def test_state_weight_runner_locates_primary_method_by_name_and_rejects_identity_shift(
    tmp_path,
    monkeypatch,
):
    import hashlib

    case = _state_weight_runner_case(tmp_path, monkeypatch)
    with np.load(case.reference_path, allow_pickle=False) as sealed:
        values = {name: sealed[name].copy() for name in sealed.files}
    values["block_ids"] = values["block_ids"][::-1]
    np.savez_compressed(case.reference_path, **values)
    case.config["sealed_forecast_reference_evidence"]["sha256"] = hashlib.sha256(
        case.reference_path.read_bytes()
    ).hexdigest()
    case.write_config()

    with pytest.raises(ValueError, match="block_ids"):
        case.runner.run(case.root, case.config_path, case.output)


def test_state_weight_runner_summary_saves_leads_and_complete_wrong_candidate_effect():
    from hbv_multilead_joint_uncertainty.scripts import (
        run_g3_state_weight_factorial as runner,
    )

    error_difference = {
        "mean": np.asarray([0.4, 0.5]),
        "ci_low": np.asarray([0.1, 0.2]),
        "ci_high": np.asarray([0.7, 0.8]),
        "baseline_mse": np.asarray([2.5, 3.5]),
        "equivalence_lower": np.asarray([-0.04975, -0.06965]),
        "equivalence_upper": np.asarray([0.05025, 0.07035]),
        "classification": np.asarray(["material_harm", "material_harm"]),
    }
    statistics = {"wrong_candidate": {"error_difference": error_difference}}

    result = runner._statistics_summary(
        statistics,
        forecast_lead_days=np.asarray([1, 3]),
    )

    assert result["forecast_lead_days"] == [1, 3]
    assert result["wrong_candidate"]["error_difference"] == {
        key: value.tolist() for key, value in error_difference.items()
    }


def test_state_weight_runner_numeric_direct_check_rejects_equal_values_across_dtypes():
    from hbv_multilead_joint_uncertainty.scripts import (
        run_g3_state_weight_factorial as runner,
    )

    with pytest.raises(ValueError, match="dtype"):
        runner._bit_exact_check(
            "numeric dtype",
            np.asarray([1.0, 2.0], dtype=np.float32),
            np.asarray([1.0, 2.0], dtype=np.float64),
        )


@pytest.mark.parametrize(
    ("changed_field", "expected_error"),
    [
        ("candidate_order", "candidate_order"),
        ("matched_blocks", "block_ids"),
        ("lead_days", "lead_days"),
        ("stage_lengths", "stage_lengths"),
    ],
)
def test_state_weight_runner_binds_execution_config_before_preregistration(
    tmp_path,
    monkeypatch,
    changed_field,
    expected_error,
):
    case = _state_weight_runner_case(tmp_path, monkeypatch)
    if changed_field == "candidate_order":
        case.config[changed_field] = list(reversed(case.config[changed_field]))
    elif changed_field == "matched_blocks":
        case.config[changed_field][0]["block_id"] = "wrong_block"
    elif changed_field == "lead_days":
        case.config[changed_field] = [1, 7]
    else:
        case.config[changed_field] = [1, 2]
    case.write_config()

    with pytest.raises(ValueError, match=expected_error):
        case.runner.run(case.root, case.config_path, case.output)

    assert case.calls["compare"] == 0
    assert not case.output.with_name(case.output.name + ".preregistered.json").exists()


def test_state_weight_runner_rejects_probability_freezing_error_above_tolerance(
    tmp_path,
    monkeypatch,
):
    case = _state_weight_runner_case(tmp_path, monkeypatch)
    case.driver["forecast_probability_maximum_absolute_error_none"].fill(2e-12)

    with pytest.raises(RuntimeError, match="frozen-probability contract"):
        case.runner.run(case.root, case.config_path, case.output)

    assert case.calls["compare"] == 1
    assert not case.output.exists()
    assert not case.output.with_name(case.output.name + ".incomplete").exists()
    assert case.output.with_name(
        case.output.name + ".preregistered.json"
    ).exists()


def test_state_weight_runner_rejects_nonfinite_statistics_before_package(
    tmp_path,
    monkeypatch,
):
    case = _state_weight_runner_case(tmp_path, monkeypatch)
    original_summarize = case.runner.summarize_state_weight_factorial

    def nonfinite_summarize(*args, **kwargs):
        result = original_summarize(*args, **kwargs)
        result["effects"]["complete_full_minus_none"]["mean"] = np.asarray(
            [np.nan, 0.2]
        )
        return result

    monkeypatch.setattr(
        case.runner,
        "summarize_state_weight_factorial",
        nonfinite_summarize,
    )

    with pytest.raises(ValueError, match="non-finite"):
        case.runner.run(case.root, case.config_path, case.output)

    assert case.calls["compare"] == 1
    assert not case.output.exists()
    assert not case.output.with_name(case.output.name + ".incomplete").exists()

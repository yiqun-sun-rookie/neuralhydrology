"""Differentiable fifteen-state HBV-lite process and routed observation."""

from __future__ import annotations

from math import ceil
from typing import Mapping, Sequence

import torch

from scl_hydro.hbv_lite import DifferentiableHBVLite, PARAM_NAMES


STATE_COUNT = 15
ROUTING_LENGTH = 10


def _validated_parameters(parameters: Mapping[str, float]) -> dict[str, float]:
    if set(parameters) != set(PARAM_NAMES):
        raise ValueError("parameters must contain exactly the thirteen HBV-lite values")
    values = {name: float(parameters[name]) for name in PARAM_NAMES}
    if not all(torch.isfinite(torch.tensor(value)) for value in values.values()):
        raise ValueError("parameters must be finite")
    if values["lag_time"] < 1.0 or values["lag_time"] > ROUTING_LENGTH:
        raise ValueError("lag_time must be within the ten-state routing memory")
    return values


def recession_half_weights(
    lag_time: float,
    length: int,
    *,
    dtype: torch.dtype,
    device: torch.device,
) -> torch.Tensor:
    """Return newest-first recession-half triangular routing weights."""
    lag = float(lag_time)
    count = max(ceil(lag), 1)
    if count > int(length) or length <= 0:
        raise ValueError("routing length must cover ceil(lag_time)")
    index = torch.arange(int(length), dtype=dtype, device=device)
    weights = torch.clamp(
        torch.as_tensor(float(count), dtype=dtype, device=device) - index,
        min=0.0,
    )
    return weights / weights.sum()


def project_hbv15(state: torch.Tensor, parameters: Mapping[str, float]) -> torch.Tensor:
    """Project one or more states onto the frozen HBV-lite physical domain."""
    values = _validated_parameters(parameters)
    if state.shape[-1] != STATE_COUNT or not torch.isfinite(state).all():
        raise ValueError("state must be finite with fifteen components")
    snow = torch.clamp(state[..., 0:1], min=0.0)
    melt = torch.clamp(state[..., 1:2], min=0.0)
    melt = torch.minimum(melt, values["parCWH"] * snow)
    soil = torch.clamp(state[..., 2:3], min=1e-5, max=values["parFC"])
    remaining = torch.clamp(state[..., 3:], min=0.0)
    return torch.cat((snow, melt, soil, remaining), dim=-1)


class HBV15Model:
    """Frozen-parameter HBV-lite with ten newest-first runoff memories."""

    def __init__(self, parameters: Mapping[str, float], routing_length: int = ROUTING_LENGTH):
        self.parameters = _validated_parameters(parameters)
        self.routing_length = int(routing_length)
        if self.routing_length != ROUTING_LENGTH:
            raise ValueError("the current experiment requires ten routing-memory states")
        self.core = DifferentiableHBVLite()

    def _parameter_tensors(
        self,
        count: int,
        *,
        dtype: torch.dtype,
        device: torch.device,
    ) -> dict[str, torch.Tensor]:
        return {
            name: torch.full((count, 1), value, dtype=dtype, device=device)
            for name, value in self.parameters.items()
        }

    @staticmethod
    def _broadcast_forcing(forcing: torch.Tensor, leading_shape: torch.Size) -> torch.Tensor:
        if forcing.shape[-1] != 3 or not torch.isfinite(forcing).all():
            raise ValueError("forcing must be finite with rain, PET, and temperature")
        result = forcing
        while result.ndim - 1 < len(leading_shape):
            result = result.unsqueeze(-2)
        try:
            return torch.broadcast_to(result, (*leading_shape, 3))
        except RuntimeError as exc:
            raise ValueError("forcing cannot broadcast to the state batch") from exc

    def step(self, state: torch.Tensor, forcing: torch.Tensor) -> torch.Tensor:
        """Advance arbitrary leading state dimensions by one daily step."""
        current = project_hbv15(state, self.parameters)
        leading = current.shape[:-1]
        expanded_forcing = self._broadcast_forcing(forcing, leading)
        flat_state = current.reshape(-1, STATE_COUNT)
        flat_forcing = expanded_forcing.reshape(-1, 3)
        parameter_tensors = self._parameter_tensors(
            len(flat_state), dtype=state.dtype, device=state.device
        )
        next_stores, raw_discharge = self.core.forward_step(
            flat_state[:, :5],
            flat_forcing[:, 0:1],
            flat_forcing[:, 1:2],
            flat_forcing[:, 2:3],
            parameter_tensors,
        )
        next_routing = torch.cat((raw_discharge, flat_state[:, 5:14]), dim=-1)
        next_state = torch.cat((next_stores, next_routing), dim=-1).reshape(
            *leading, STATE_COUNT
        )
        return project_hbv15(next_state, self.parameters)

    def observe(self, state: torch.Tensor) -> torch.Tensor:
        """Map newest-first routing memories to routed discharge."""
        if state.shape[-1] != STATE_COUNT or not torch.isfinite(state).all():
            raise ValueError("state must be finite with fifteen components")
        weights = recession_half_weights(
            self.parameters["lag_time"],
            self.routing_length,
            dtype=state.dtype,
            device=state.device,
        )
        return torch.sum(state[..., 5:15] * weights, dim=-1)


def forecast_global_state(
    initial_state: torch.Tensor,
    future_forcing: torch.Tensor,
    model: HBV15Model,
    leads: Sequence[int],
) -> dict[int, torch.Tensor]:
    """Issue deterministic routed-flow forecasts from one global state."""
    requested = tuple(int(value) for value in leads)
    if not requested or min(requested) <= 0 or len(set(requested)) != len(requested):
        raise ValueError("leads must contain unique positive integers")
    if initial_state.ndim != 2 or initial_state.shape[-1] != STATE_COUNT:
        raise ValueError("initial_state must be [batch, 15]")
    if future_forcing.ndim != 3 or future_forcing.shape[0] != initial_state.shape[0]:
        raise ValueError("future_forcing must be [batch, lead, 3]")
    if future_forcing.shape[1] < max(requested):
        raise ValueError("future_forcing does not cover the maximum lead")
    state = initial_state
    output: dict[int, torch.Tensor] = {}
    for step_index in range(1, max(requested) + 1):
        state = model.step(state, future_forcing[:, step_index - 1])
        if step_index in requested:
            output[step_index] = model.observe(state)
    return output


def _project_hbv15_dynamic(
    state: torch.Tensor,
    parameters: Mapping[str, torch.Tensor],
) -> torch.Tensor:
    """Project batched states using one differentiable parameter vector per row."""

    if state.ndim != 2 or state.shape[-1] != STATE_COUNT:
        raise ValueError("dynamic state must have shape [batch, 15]")
    batch = state.shape[0]
    if set(parameters) != set(PARAM_NAMES):
        raise ValueError("dynamic parameters must contain all HBV-lite names")
    values: dict[str, torch.Tensor] = {}
    for name in PARAM_NAMES:
        value = parameters[name]
        if value.shape != (batch, 1) or not torch.isfinite(value).all():
            raise ValueError("each dynamic parameter must have shape [batch, 1]")
        values[name] = value
    snow = torch.clamp(state[:, 0:1], min=0.0)
    melt = torch.clamp(state[:, 1:2], min=0.0)
    melt = torch.minimum(melt, values["parCWH"] * snow)
    soil = torch.clamp(state[:, 2:3], min=1e-5)
    soil = torch.minimum(soil, values["parFC"])
    remaining = torch.clamp(state[:, 3:], min=0.0)
    return torch.cat((snow, melt, soil, remaining), dim=-1)


def forecast_global_state_weighted_parameters(
    initial_state: torch.Tensor,
    future_forcing: torch.Tensor,
    candidate_parameters: Mapping[str, Mapping[str, float]],
    posterior_probabilities: torch.Tensor,
    leads: Sequence[int],
) -> dict[int, torch.Tensor]:
    """Forecast one global state with one frozen posterior-weighted parameter vector."""

    requested = tuple(int(value) for value in leads)
    if not requested or min(requested) <= 0 or len(set(requested)) != len(requested):
        raise ValueError("leads must contain unique positive integers")
    if initial_state.ndim != 2 or initial_state.shape[-1] != STATE_COUNT:
        raise ValueError("initial_state must have shape [batch, 15]")
    batch = initial_state.shape[0]
    if (
        future_forcing.ndim != 3
        or future_forcing.shape[0] != batch
        or future_forcing.shape[1] < max(requested)
        or future_forcing.shape[2] != 3
    ):
        raise ValueError("future_forcing must cover [batch, maximum lead, 3]")
    identifiers = tuple(candidate_parameters)
    candidate_count = len(identifiers)
    if candidate_count == 0 or posterior_probabilities.shape != (
        batch,
        candidate_count,
    ):
        raise ValueError("posterior probabilities must match the candidate count")
    if (
        not torch.isfinite(posterior_probabilities).all()
        or torch.any(posterior_probabilities < 0.0)
        or torch.any(posterior_probabilities.sum(dim=-1) <= 0.0)
    ):
        raise ValueError("posterior probabilities must be finite and nonnegative")

    validated = [
        _validated_parameters(candidate_parameters[identifier])
        for identifier in identifiers
    ]
    lag_times = tuple(parameters["lag_time"] for parameters in validated)
    if max(lag_times) - min(lag_times) > 1e-12:
        raise ValueError("weighted-parameter forecast requires one common lag_time")
    candidate_matrix = torch.as_tensor(
        [[parameters[name] for name in PARAM_NAMES] for parameters in validated],
        dtype=initial_state.dtype,
        device=initial_state.device,
    )
    normalized_probabilities = posterior_probabilities / posterior_probabilities.sum(
        dim=-1, keepdim=True
    )
    weighted_matrix = normalized_probabilities @ candidate_matrix
    parameters = {
        name: weighted_matrix[:, index : index + 1]
        for index, name in enumerate(PARAM_NAMES)
    }
    state = _project_hbv15_dynamic(initial_state, parameters)
    core = DifferentiableHBVLite()
    routing_weights = recession_half_weights(
        lag_times[0],
        ROUTING_LENGTH,
        dtype=initial_state.dtype,
        device=initial_state.device,
    )
    output: dict[int, torch.Tensor] = {}
    for step_index in range(1, max(requested) + 1):
        forcing = future_forcing[:, step_index - 1]
        next_stores, raw_discharge = core.forward_step(
            state[:, :5],
            forcing[:, 0:1],
            forcing[:, 1:2],
            forcing[:, 2:3],
            parameters,
        )
        next_routing = torch.cat((raw_discharge, state[:, 5:14]), dim=-1)
        state = _project_hbv15_dynamic(
            torch.cat((next_stores, next_routing), dim=-1), parameters
        )
        if step_index in requested:
            output[step_index] = torch.sum(
                state[:, 5:15] * routing_weights, dim=-1
            )
    return output


def _validated_forecast_transitions(
    transition_matrix: torch.Tensor,
    batch: int,
    candidate_count: int,
    horizon: int,
    dtype: torch.dtype,
) -> torch.Tensor:
    """Normalize per-step forecast transition matrices to [batch, horizon, m, m]."""

    if transition_matrix.ndim == 3:
        expanded = transition_matrix.unsqueeze(1).expand(-1, horizon, -1, -1)
    elif transition_matrix.ndim == 4:
        expanded = transition_matrix
    else:
        raise ValueError("transition_matrix must be [batch, m, m] or [batch, k, m, m]")
    if expanded.shape[0] != batch or expanded.shape[-2:] != (
        candidate_count,
        candidate_count,
    ):
        raise ValueError("transition_matrix must match the batch and candidate count")
    if expanded.shape[1] < horizon:
        raise ValueError("transition_matrix must cover the maximum lead")
    expanded = expanded[:, :horizon]
    if not torch.isfinite(expanded).all() or torch.any(expanded < 0.0):
        raise ValueError("transition matrices must be finite and nonnegative")
    totals = expanded.sum(dim=-1, keepdim=True)
    if torch.any(totals <= 0.0):
        raise ValueError("every transition row must have positive mass")
    return (expanded / totals).to(dtype=dtype)


def forecast_global_state_mode_evolving(
    initial_state: torch.Tensor,
    future_forcing: torch.Tensor,
    candidate_parameters: Mapping[str, Mapping[str, float]],
    posterior_probabilities: torch.Tensor,
    transition_matrix: torch.Tensor,
    leads: Sequence[int],
) -> dict[int, torch.Tensor]:
    """Forecast one global state while the mode distribution evolves by the matrix.

    Identical to forecast_global_state_weighted_parameters except that the mode
    distribution is advanced one transition step before each forecast day, and
    the posterior-weighted parameter vector is recomputed from the advanced
    distribution.  The trajectory stays single: no candidate trajectories are
    propagated and no trajectory mixing occurs.

    With an identity transition matrix this reduces bit-for-bit to
    forecast_global_state_weighted_parameters; that equivalence is the
    implementation audit required by the H19 contract.
    """

    requested = tuple(int(value) for value in leads)
    if not requested or min(requested) <= 0 or len(set(requested)) != len(requested):
        raise ValueError("leads must contain unique positive integers")
    if initial_state.ndim != 2 or initial_state.shape[-1] != STATE_COUNT:
        raise ValueError("initial_state must have shape [batch, 15]")
    batch = initial_state.shape[0]
    horizon = max(requested)
    if (
        future_forcing.ndim != 3
        or future_forcing.shape[0] != batch
        or future_forcing.shape[1] < horizon
        or future_forcing.shape[2] != 3
    ):
        raise ValueError("future_forcing must cover [batch, maximum lead, 3]")
    identifiers = tuple(candidate_parameters)
    candidate_count = len(identifiers)
    if candidate_count == 0 or posterior_probabilities.shape != (
        batch,
        candidate_count,
    ):
        raise ValueError("posterior probabilities must match the candidate count")
    if (
        not torch.isfinite(posterior_probabilities).all()
        or torch.any(posterior_probabilities < 0.0)
        or torch.any(posterior_probabilities.sum(dim=-1) <= 0.0)
    ):
        raise ValueError("posterior probabilities must be finite and nonnegative")

    validated = [
        _validated_parameters(candidate_parameters[identifier])
        for identifier in identifiers
    ]
    lag_times = tuple(parameters["lag_time"] for parameters in validated)
    if max(lag_times) - min(lag_times) > 1e-12:
        raise ValueError("weighted-parameter forecast requires one common lag_time")
    candidate_matrix = torch.as_tensor(
        [[parameters[name] for name in PARAM_NAMES] for parameters in validated],
        dtype=initial_state.dtype,
        device=initial_state.device,
    )
    matrices = _validated_forecast_transitions(
        transition_matrix,
        batch,
        candidate_count,
        horizon,
        initial_state.dtype,
    )
    probabilities = posterior_probabilities / posterior_probabilities.sum(
        dim=-1, keepdim=True
    )

    def weighted(values: torch.Tensor) -> dict[str, torch.Tensor]:
        matrix = values @ candidate_matrix
        return {
            name: matrix[:, index : index + 1]
            for index, name in enumerate(PARAM_NAMES)
        }

    state = _project_hbv15_dynamic(initial_state, weighted(probabilities))
    core = DifferentiableHBVLite()
    routing_weights = recession_half_weights(
        lag_times[0],
        ROUTING_LENGTH,
        dtype=initial_state.dtype,
        device=initial_state.device,
    )
    output: dict[int, torch.Tensor] = {}
    for step_index in range(1, horizon + 1):
        probabilities = torch.einsum(
            "bm,bmn->bn", probabilities, matrices[:, step_index - 1]
        )
        parameters = weighted(probabilities)
        forcing = future_forcing[:, step_index - 1]
        next_stores, raw_discharge = core.forward_step(
            state[:, :5],
            forcing[:, 0:1],
            forcing[:, 1:2],
            forcing[:, 2:3],
            parameters,
        )
        next_routing = torch.cat((raw_discharge, state[:, 5:14]), dim=-1)
        state = _project_hbv15_dynamic(
            torch.cat((next_stores, next_routing), dim=-1), parameters
        )
        if step_index in requested:
            output[step_index] = torch.sum(
                state[:, 5:15] * routing_weights, dim=-1
            )
    return output

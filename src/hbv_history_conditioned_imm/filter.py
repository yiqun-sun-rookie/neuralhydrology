"""Differentiable modified unscented filters with full model interaction."""

from __future__ import annotations

from dataclasses import dataclass
from math import pi
from typing import Sequence

import torch
from torch import nn

from .hbv import HBV15Model, STATE_COUNT, project_hbv15


@dataclass(frozen=True)
class InteractionResult:
    prior_probabilities: torch.Tensor
    conditional_weights: torch.Tensor
    mixed_states: torch.Tensor
    mixed_covariances: torch.Tensor


@dataclass(frozen=True)
class InteractingStepResult:
    prior_probabilities: torch.Tensor
    posterior_probabilities: torch.Tensor
    prior_states: torch.Tensor
    prior_covariances: torch.Tensor
    prior_observations: torch.Tensor
    innovations: torch.Tensor
    innovation_variances: torch.Tensor
    posterior_states: torch.Tensor
    posterior_covariances: torch.Tensor
    log_likelihoods: torch.Tensor
    combined_prior_observation: torch.Tensor
    global_posterior_states: torch.Tensor
    global_posterior_covariances: torch.Tensor


def _require_finite(values: torch.Tensor, label: str) -> None:
    if not torch.isfinite(values).all():
        raise ValueError(f"{label} must be finite")


def interact_model_states(
    states: torch.Tensor,
    covariances: torch.Tensor,
    transition_matrix: torch.Tensor,
    current_probabilities: torch.Tensor,
) -> InteractionResult:
    """Condition batched source moments on every destination candidate."""
    if states.ndim != 3 or states.shape[-1] != STATE_COUNT:
        raise ValueError("states must have shape [batch, candidates, 15]")
    batch, candidates, dimensions = states.shape
    if covariances.shape != (batch, candidates, dimensions, dimensions):
        raise ValueError("covariances must have shape [batch, candidates, 15, 15]")
    if transition_matrix.shape != (batch, candidates, candidates):
        raise ValueError("transition_matrix must have shape [batch, candidates, candidates]")
    if current_probabilities.shape != (batch, candidates):
        raise ValueError("current_probabilities must have shape [batch, candidates]")
    for values, label in (
        (states, "states"),
        (covariances, "covariances"),
        (transition_matrix, "transition_matrix"),
        (current_probabilities, "current_probabilities"),
    ):
        _require_finite(values, label)
    if torch.any(transition_matrix < 0.0) or torch.any(current_probabilities < 0.0):
        raise ValueError("transition probabilities and candidate probabilities must be nonnegative")
    matrix_totals = transition_matrix.sum(dim=-1, keepdim=True)
    probability_totals = current_probabilities.sum(dim=-1, keepdim=True)
    if torch.any(matrix_totals <= 0.0) or torch.any(probability_totals <= 0.0):
        raise ValueError("probability rows must contain positive mass")
    matrix = transition_matrix / matrix_totals
    probabilities = current_probabilities / probability_totals

    incoming = probabilities.unsqueeze(-1) * matrix
    prior_probabilities = incoming.sum(dim=1)
    conditional_weights = (incoming / prior_probabilities.unsqueeze(1)).transpose(1, 2)
    mixed_states = torch.einsum("bji,bid->bjd", conditional_weights, states)
    deviations = states.unsqueeze(1) - mixed_states.unsqueeze(2)
    mixed_covariances = torch.einsum(
        "bji,bide->bjde", conditional_weights, covariances
    ) + torch.einsum(
        "bji,bjid,bjie->bjde", conditional_weights, deviations, deviations
    )
    mixed_covariances = 0.5 * (
        mixed_covariances + mixed_covariances.transpose(-1, -2)
    )
    return InteractionResult(
        prior_probabilities=prior_probabilities,
        conditional_weights=conditional_weights,
        mixed_states=mixed_states,
        mixed_covariances=mixed_covariances,
    )


class DifferentiableInteractingMultipleModel(nn.Module):
    """Three-stage differentiable calculation: interact, filter, combine."""

    def __init__(
        self,
        models: Sequence[HBV15Model],
        process_covariances: torch.Tensor,
        observation_variance: float,
        *,
        alpha: float = 0.6874,
        beta: float = 2.0,
        kappa: float = -2.0,
    ) -> None:
        super().__init__()
        self.models = tuple(models)
        if not self.models:
            raise ValueError("models must be nonempty")
        covariance = torch.as_tensor(process_covariances)
        expected = (len(self.models), STATE_COUNT, STATE_COUNT)
        if covariance.shape != expected or not torch.isfinite(covariance).all():
            raise ValueError(f"process_covariances must have shape {expected} and be finite")
        if observation_variance <= 0.0:
            raise ValueError("observation_variance must be positive")
        self.register_buffer("process_covariances", covariance.clone())
        self.register_buffer(
            "observation_variance",
            torch.as_tensor(float(observation_variance), dtype=covariance.dtype),
        )
        self.alpha = float(alpha)
        self.beta = float(beta)
        self.kappa = float(kappa)
        self.lambda_ = self.alpha**2 * (STATE_COUNT + self.kappa) - STATE_COUNT
        self.sigma_scale = STATE_COUNT + self.lambda_
        if self.sigma_scale <= 0.0:
            raise ValueError("sigma-point scale must be positive")

    def _weights(self, reference: torch.Tensor) -> tuple[torch.Tensor, torch.Tensor]:
        count = 2 * STATE_COUNT + 1
        mean = torch.full(
            (count,),
            1.0 / (2.0 * self.sigma_scale),
            dtype=reference.dtype,
            device=reference.device,
        )
        covariance = mean.clone()
        mean[0] = self.lambda_ / self.sigma_scale
        covariance[0] = mean[0] + 1.0 - self.alpha**2 + self.beta
        return mean, covariance

    def _sigma_points(self, mean: torch.Tensor, covariance: torch.Tensor) -> torch.Tensor:
        symmetric = 0.5 * (covariance + covariance.transpose(-1, -2))
        root, information = torch.linalg.cholesky_ex(self.sigma_scale * symmetric)
        if torch.any(information > 0):
            detached_eigenvalues = torch.linalg.eigvalsh(symmetric.detach())
            spectral_scale = torch.clamp(
                detached_eigenvalues.abs().amax(dim=-1), min=1.0
            )
            floor = (
                torch.finfo(mean.dtype).eps * STATE_COUNT * 100.0 * spectral_scale
            )
            jitter = torch.clamp(
                -detached_eigenvalues.amin(dim=-1) + floor,
                min=floor,
            )
            identity = torch.eye(
                STATE_COUNT, dtype=mean.dtype, device=mean.device
            )
            repaired = symmetric + jitter[..., None, None] * identity
            root = torch.linalg.cholesky(self.sigma_scale * repaired)
        offsets = root.transpose(-1, -2)
        return torch.cat(
            (mean.unsqueeze(-2), mean.unsqueeze(-2) + offsets, mean.unsqueeze(-2) - offsets),
            dim=-2,
        )

    @staticmethod
    def _unscented_state(
        sigmas: torch.Tensor,
        mean_weights: torch.Tensor,
        covariance_weights: torch.Tensor,
        additive_covariance: torch.Tensor,
    ) -> tuple[torch.Tensor, torch.Tensor]:
        mean = torch.einsum("s,bsd->bd", mean_weights, sigmas)
        deviations = sigmas - mean.unsqueeze(-2)
        covariance = torch.einsum(
            "s,bsd,bse->bde", covariance_weights, deviations, deviations
        ) + additive_covariance
        covariance = 0.5 * (covariance + covariance.transpose(-1, -2))
        return mean, covariance

    def _candidate_step(
        self,
        model: HBV15Model,
        state: torch.Tensor,
        covariance: torch.Tensor,
        process_covariance: torch.Tensor,
        forcing: torch.Tensor,
        observation: torch.Tensor,
    ) -> tuple[torch.Tensor, ...]:
        mean_weights, covariance_weights = self._weights(state)
        state_sigmas = self._sigma_points(state, covariance)
        transitioned = model.step(state_sigmas, forcing)
        prior_state, prior_covariance = self._unscented_state(
            transitioned,
            mean_weights,
            covariance_weights,
            process_covariance,
        )

        measurement_sigmas = self._sigma_points(prior_state, prior_covariance)
        routed_sigmas = model.observe(measurement_sigmas)
        prior_observation = torch.einsum("s,bs->b", mean_weights, routed_sigmas)
        observation_deviations = routed_sigmas - prior_observation.unsqueeze(-1)
        innovation_variance = torch.einsum(
            "s,bs,bs->b",
            covariance_weights,
            observation_deviations,
            observation_deviations,
        ) + self.observation_variance.to(dtype=state.dtype, device=state.device)
        state_deviations = measurement_sigmas - prior_state.unsqueeze(-2)
        cross_covariance = torch.einsum(
            "s,bsd,bs->bd",
            covariance_weights,
            state_deviations,
            observation_deviations,
        )
        gain = cross_covariance / innovation_variance.unsqueeze(-1)
        innovation = observation - prior_observation
        posterior_state = project_hbv15(
            prior_state + gain * innovation.unsqueeze(-1), model.parameters
        )
        posterior_covariance = prior_covariance - torch.einsum(
            "bd,b,be->bde", gain, innovation_variance, gain
        )
        posterior_covariance = 0.5 * (
            posterior_covariance + posterior_covariance.transpose(-1, -2)
        )
        log_likelihood = -0.5 * (
            torch.log(
                torch.as_tensor(2.0 * pi, dtype=state.dtype, device=state.device)
                * innovation_variance
            )
            + innovation.square() / innovation_variance
        )
        return (
            prior_state,
            prior_covariance,
            prior_observation,
            innovation,
            innovation_variance,
            posterior_state,
            posterior_covariance,
            log_likelihood,
        )

    def step(
        self,
        *,
        states: torch.Tensor,
        covariances: torch.Tensor,
        probabilities: torch.Tensor,
        transition_matrix: torch.Tensor,
        forcing: torch.Tensor,
        observation: torch.Tensor,
    ) -> InteractingStepResult:
        """Perform one fully interacting update and publish one global posterior."""
        interaction = interact_model_states(
            states, covariances, transition_matrix, probabilities
        )
        batch = states.shape[0]
        if forcing.shape != (batch, 3) or observation.shape != (batch,):
            raise ValueError("forcing must be [batch, 3] and observation must be [batch]")
        candidate_outputs = []
        for candidate_index, model in enumerate(self.models):
            candidate_outputs.append(
                self._candidate_step(
                    model,
                    interaction.mixed_states[:, candidate_index],
                    interaction.mixed_covariances[:, candidate_index],
                    self.process_covariances[candidate_index].to(
                        dtype=states.dtype, device=states.device
                    ),
                    forcing,
                    observation,
                )
            )
        stacked = tuple(
            torch.stack([output[field_index] for output in candidate_outputs], dim=1)
            for field_index in range(8)
        )
        (
            prior_states,
            prior_covariances,
            prior_observations,
            innovations,
            innovation_variances,
            posterior_states,
            posterior_covariances,
            log_likelihoods,
        ) = stacked
        log_prior = torch.where(
            interaction.prior_probabilities > 0.0,
            torch.log(interaction.prior_probabilities),
            torch.full_like(interaction.prior_probabilities, -torch.inf),
        )
        posterior_probabilities = torch.softmax(log_prior + log_likelihoods, dim=-1)
        combined_prior_observation = torch.sum(
            interaction.prior_probabilities * prior_observations, dim=-1
        )
        global_state = torch.sum(
            posterior_probabilities.unsqueeze(-1) * posterior_states, dim=1
        )
        global_deviations = posterior_states - global_state.unsqueeze(1)
        global_covariance = torch.einsum(
            "bm,bmde->bde", posterior_probabilities, posterior_covariances
        ) + torch.einsum(
            "bm,bmd,bme->bde",
            posterior_probabilities,
            global_deviations,
            global_deviations,
        )
        global_covariance = 0.5 * (
            global_covariance + global_covariance.transpose(-1, -2)
        )
        return InteractingStepResult(
            prior_probabilities=interaction.prior_probabilities,
            posterior_probabilities=posterior_probabilities,
            prior_states=prior_states,
            prior_covariances=prior_covariances,
            prior_observations=prior_observations,
            innovations=innovations,
            innovation_variances=innovation_variances,
            posterior_states=posterior_states,
            posterior_covariances=posterior_covariances,
            log_likelihoods=log_likelihoods,
            combined_prior_observation=combined_prior_observation,
            global_posterior_states=global_state,
            global_posterior_covariances=global_covariance,
        )

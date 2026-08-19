"""Causal semi-Markov transition probabilities from an elapsed-duration belief."""

from __future__ import annotations

from dataclasses import dataclass
import math

import torch
from torch import nn


_CANDIDATE_COUNT = 3


class _MonotonePiecewiseLinearAgeRisk(nn.Module):
    """Ordered logit-correction knots with fixed, uniform age coordinates."""

    def __init__(
        self,
        *,
        maximum_age: int,
        knot_count: int,
        maximum_correction: float,
        dtype: torch.dtype,
        device: torch.device,
    ) -> None:
        super().__init__()
        if knot_count < 2 or knot_count > maximum_age:
            raise ValueError(
                "piecewise knot count must be between two and maximum age"
            )
        if not math.isfinite(maximum_correction) or maximum_correction <= 0.0:
            raise ValueError("maximum piecewise correction must be positive")

        self.start_coordinate = 1.0 / float(maximum_age)
        self.knot_count = int(knot_count)
        self.maximum_correction = float(maximum_correction)
        self.start_raw = nn.Parameter(
            torch.zeros((), dtype=dtype, device=device)
        )
        self.span_raw = nn.Parameter(
            torch.full((), -2.0, dtype=dtype, device=device)
        )
        self.interval_logits = nn.Parameter(
            torch.empty(self.knot_count - 1, dtype=dtype, device=device)
        )
        nn.init.normal_(self.interval_logits, mean=0.0, std=0.01)

    def knot_corrections(self) -> torch.Tensor:
        """Return bounded, nondecreasing corrections at the frozen knots."""

        maximum = torch.as_tensor(
            self.maximum_correction,
            dtype=self.start_raw.dtype,
            device=self.start_raw.device,
        )
        start = maximum * (2.0 * torch.sigmoid(self.start_raw) - 1.0)
        span = (maximum - start) * torch.sigmoid(self.span_raw)
        allocation = torch.softmax(self.interval_logits, dim=0)
        increments = span * allocation
        return torch.cat(
            (start.reshape(1), start + torch.cumsum(increments, dim=0))
        )

    def forward(self, age_coordinates: torch.Tensor) -> torch.Tensor:
        coordinates = age_coordinates.squeeze(-1)
        scale = (coordinates - self.start_coordinate) / (
            1.0 - self.start_coordinate
        )
        locations = torch.clamp(scale, 0.0, 1.0) * float(
            self.knot_count - 1
        )
        left = torch.floor(locations).to(dtype=torch.long)
        left = torch.clamp(left, min=0, max=self.knot_count - 2)
        fraction = locations - left.to(dtype=locations.dtype)
        knots = self.knot_corrections()
        correction = knots[left] + fraction * (knots[left + 1] - knots[left])
        return correction.unsqueeze(-1)


@dataclass(frozen=True)
class ModeDurationState:
    """Posterior probability mass over candidate mode and elapsed age."""

    joint_probabilities: torch.Tensor


@dataclass(frozen=True)
class SemiMarkovPrediction:
    """One causal duration prediction before the current observation is used."""

    transition_matrix: torch.Tensor
    prior_joint_probabilities: torch.Tensor
    source_hazards: torch.Tensor
    age_hazards: torch.Tensor


class CausalSemiMarkovTransitionModule(nn.Module):
    """Predict three-mode transitions from a causal elapsed-duration belief.

    The module shares one learned hazard curve across source modes. A switch
    resets elapsed age to one, while a stay advances age by one. The final age
    bucket is an overflow bucket and therefore retains staying mass.
    """

    def __init__(
        self,
        *,
        base_transition: torch.Tensor,
        maximum_age: int,
        hazard_hidden_size: int = 16,
        maximum_logit_correction: float = 2.0,
        minimum_differentiable_mode_probability: float = 1e-12,
        age_risk_representation: str = "smooth_tanh_network",
        piecewise_knot_count: int = 31,
    ) -> None:
        super().__init__()
        base = torch.as_tensor(base_transition)
        if not base.is_floating_point():
            base = base.to(dtype=torch.get_default_dtype())
        if (
            base.shape != (_CANDIDATE_COUNT, _CANDIDATE_COUNT)
            or not torch.isfinite(base).all()
            or torch.any(base <= 0.0)
        ):
            raise ValueError("base transition must be a finite positive 3 by 3 matrix")
        if isinstance(maximum_age, bool) or int(maximum_age) != maximum_age or int(maximum_age) <= 0:
            raise ValueError("maximum age must be a positive integer")
        if (
            isinstance(hazard_hidden_size, bool)
            or int(hazard_hidden_size) != hazard_hidden_size
            or int(hazard_hidden_size) <= 0
        ):
            raise ValueError("hazard hidden size must be a positive integer")
        if (
            not math.isfinite(maximum_logit_correction)
            or maximum_logit_correction <= 0.0
        ):
            raise ValueError("maximum logit correction must be finite and positive")
        if age_risk_representation not in {
            "smooth_tanh_network",
            "monotone_piecewise_linear",
        }:
            raise ValueError("age risk representation is unsupported")
        if (
            age_risk_representation == "monotone_piecewise_linear"
            and (
                isinstance(piecewise_knot_count, bool)
                or int(piecewise_knot_count) != piecewise_knot_count
                or int(piecewise_knot_count) < 2
                or int(piecewise_knot_count) > int(maximum_age)
            )
        ):
            raise ValueError(
                "piecewise knot count must be between two and maximum age"
            )
        if (
            not math.isfinite(minimum_differentiable_mode_probability)
            or minimum_differentiable_mode_probability <= 0.0
            or minimum_differentiable_mode_probability >= 1.0
        ):
            raise ValueError(
                "minimum differentiable mode probability must be finite and "
                "strictly between zero and one"
            )

        base = base / base.sum(dim=-1, keepdim=True)
        common_stay = base[0, 0]
        expected_base = torch.full_like(base, (1.0 - common_stay) / 2.0)
        expected_base.fill_diagonal_(common_stay)
        tolerance = self._normalization_tolerance(base.dtype)
        if not torch.allclose(base, expected_base, atol=tolerance, rtol=0.0):
            raise ValueError(
                "causal duration requires one common stay probability and "
                "equal target-direction probabilities"
            )

        base_hazard = 1.0 - common_stay
        base_hazard_logit = torch.log(base_hazard / (1.0 - base_hazard))
        maximum_age = int(maximum_age)
        hazard_hidden_size = int(hazard_hidden_size)
        age_coordinates = torch.arange(
            1,
            maximum_age + 1,
            dtype=base.dtype,
            device=base.device,
        ).unsqueeze(-1) / float(maximum_age)

        self.register_buffer("base_transition", base.clone())
        self.register_buffer("base_hazard", base_hazard.clone())
        self.register_buffer("base_hazard_logit", base_hazard_logit.clone())
        self.register_buffer("age_coordinates", age_coordinates)
        self.maximum_age = maximum_age
        self.hazard_hidden_size = hazard_hidden_size
        self.maximum_logit_correction = float(maximum_logit_correction)
        self.age_risk_representation = str(age_risk_representation)
        self.piecewise_knot_count = int(piecewise_knot_count)
        self.minimum_differentiable_mode_probability = float(
            minimum_differentiable_mode_probability
        )
        if self.age_risk_representation == "smooth_tanh_network":
            self.age_risk_network = nn.Sequential(
                nn.Linear(
                    1,
                    hazard_hidden_size,
                    dtype=base.dtype,
                    device=base.device,
                ),
                nn.Tanh(),
                nn.Linear(
                    hazard_hidden_size,
                    1,
                    dtype=base.dtype,
                    device=base.device,
                ),
            )
            nn.init.zeros_(self.age_risk_network[-1].weight)
            nn.init.zeros_(self.age_risk_network[-1].bias)
        else:
            self.age_risk_network = _MonotonePiecewiseLinearAgeRisk(
                maximum_age=maximum_age,
                knot_count=self.piecewise_knot_count,
                maximum_correction=2.0 * self.maximum_logit_correction,
                dtype=base.dtype,
                device=base.device,
            )

    @staticmethod
    def _normalization_tolerance(dtype: torch.dtype) -> float:
        return max(1e-12, 100.0 * torch.finfo(dtype).eps)

    def _posterior_probabilities(
        self,
        posterior_probabilities: torch.Tensor,
        *,
        expected_blocks: int | None = None,
    ) -> torch.Tensor:
        posterior = torch.as_tensor(
            posterior_probabilities,
            dtype=self.base_transition.dtype,
            device=self.base_transition.device,
        )
        if posterior.ndim != 2 or posterior.shape[-1] != _CANDIDATE_COUNT:
            raise ValueError("posterior probabilities must have shape [block, candidate]")
        if expected_blocks is not None and posterior.shape[0] != expected_blocks:
            raise ValueError("posterior probabilities have the wrong block count")
        if not torch.isfinite(posterior).all() or torch.any(posterior < 0.0):
            raise ValueError("posterior probabilities must be finite and nonnegative")
        tolerance = self._normalization_tolerance(posterior.dtype)
        if not torch.allclose(
            posterior.sum(dim=-1),
            torch.ones(posterior.shape[0], dtype=posterior.dtype, device=posterior.device),
            atol=tolerance,
            rtol=0.0,
        ):
            raise ValueError("posterior probabilities must sum to one")
        return posterior

    def _joint_probabilities(self, state: ModeDurationState) -> torch.Tensor:
        if not isinstance(state, ModeDurationState):
            raise TypeError("state must be a ModeDurationState")
        joint = torch.as_tensor(
            state.joint_probabilities,
            dtype=self.base_transition.dtype,
            device=self.base_transition.device,
        )
        expected_tail = (_CANDIDATE_COUNT, self.maximum_age)
        if joint.ndim != 3 or joint.shape[1:] != expected_tail:
            raise ValueError(
                "joint probabilities must have shape [block, candidate, age]"
            )
        if not torch.isfinite(joint).all() or torch.any(joint < 0.0):
            raise ValueError("joint probabilities must be finite and nonnegative")
        tolerance = self._normalization_tolerance(joint.dtype)
        if not torch.allclose(
            joint.sum(dim=(-1, -2)),
            torch.ones(joint.shape[0], dtype=joint.dtype, device=joint.device),
            atol=tolerance,
            rtol=0.0,
        ):
            raise ValueError("joint probabilities must sum to one in every block")
        return joint

    def _conditional_age_probabilities(self, joint: torch.Tensor) -> torch.Tensor:
        """Normalize ages without unstable gradients from unsupported modes.

        Rows at or above the frozen probability floor use the exact
        differentiable quotient.  Rarer nonzero rows preserve that same exact
        forward value but detach the quotient from the duration recursion;
        gradients to the learned age hazards remain available.  Zero-mass rows
        use the age-one fallback.
        """

        mode_marginals = joint.sum(dim=-1, keepdim=True)
        floor = torch.as_tensor(
            self.minimum_differentiable_mode_probability,
            dtype=joint.dtype,
            device=joint.device,
        )
        differentiable = joint / mode_marginals.clamp_min(floor)

        supported = mode_marginals > 0.0
        detached_denominator = torch.where(
            supported,
            mode_marginals.detach(),
            torch.ones_like(mode_marginals),
        )
        exact_detached = joint.detach() / detached_denominator
        age_one = torch.zeros_like(joint)
        age_one[..., 0] = 1.0
        exact_detached = torch.where(supported, exact_detached, age_one)
        return torch.where(
            mode_marginals >= floor,
            differentiable,
            exact_detached,
        )

    def initial_state(
        self, posterior_probabilities: torch.Tensor
    ) -> ModeDurationState:
        """Put detached posterior mode mass at elapsed age one."""

        posterior = self._posterior_probabilities(posterior_probabilities).detach()
        older_ages = torch.zeros(
            (posterior.shape[0], _CANDIDATE_COUNT, self.maximum_age - 1),
            dtype=posterior.dtype,
            device=posterior.device,
        )
        joint = torch.cat((posterior.unsqueeze(-1), older_ages), dim=-1)
        return ModeDurationState(joint_probabilities=joint)

    def _age_hazards(self) -> tuple[torch.Tensor, torch.Tensor]:
        raw_correction = self.age_risk_network(self.age_coordinates).squeeze(-1)
        correction = (
            2.0 * self.maximum_logit_correction * torch.tanh(raw_correction)
            if self.age_risk_representation == "smooth_tanh_network"
            else raw_correction
        )
        calculated = torch.sigmoid(self.base_hazard_logit + correction)
        exact_base_with_gradient = calculated + (self.base_hazard - calculated).detach()
        hazards = torch.where(correction == 0.0, exact_base_with_gradient, calculated)
        return hazards, correction

    def forward(self, state: ModeDurationState) -> SemiMarkovPrediction:
        """Predict a transition matrix and the next joint prior."""

        joint = self._joint_probabilities(state)
        age_hazards, correction = self._age_hazards()
        conditional_ages = self._conditional_age_probabilities(joint)
        calculated_source_hazards = (
            conditional_ages * age_hazards.reshape(1, 1, -1)
        ).sum(dim=-1)

        all_corrections_zero = torch.all(correction == 0.0)
        exact_source_hazards = calculated_source_hazards + (
            self.base_hazard - calculated_source_hazards
        ).detach()
        source_hazards = torch.where(
            all_corrections_zero,
            exact_source_hazards,
            calculated_source_hazards,
        )

        identity = torch.eye(
            _CANDIDATE_COUNT,
            dtype=joint.dtype,
            device=joint.device,
        ).unsqueeze(0)
        hazard_rows = source_hazards.unsqueeze(-1)
        calculated_transition = identity * (1.0 - hazard_rows) + (
            1.0 - identity
        ) * (hazard_rows / float(_CANDIDATE_COUNT - 1))
        base = self.base_transition.expand(joint.shape[0], -1, -1)
        exact_base_with_gradient = calculated_transition + (
            base - calculated_transition
        ).detach()
        transition = torch.where(
            all_corrections_zero,
            exact_base_with_gradient,
            calculated_transition,
        )

        age_hazard_rows = age_hazards.reshape(1, 1, -1)
        stay_mass = joint * (1.0 - age_hazard_rows)
        age_one_zeros = torch.zeros_like(stay_mass[..., :1])
        advanced_stay_mass = torch.cat(
            (age_one_zeros, stay_mass[..., :-1]), dim=-1
        )
        overflow_zeros = torch.zeros_like(stay_mass[..., :-1])
        overflow_stay_mass = torch.cat(
            (overflow_zeros, stay_mass[..., -1:]), dim=-1
        )
        switch_mass_by_source = (joint * age_hazard_rows).sum(dim=-1)
        switch_mass_by_target = (
            switch_mass_by_source.sum(dim=-1, keepdim=True)
            - switch_mass_by_source
        ) / float(_CANDIDATE_COUNT - 1)
        reset_older_zeros = torch.zeros(
            (joint.shape[0], _CANDIDATE_COUNT, self.maximum_age - 1),
            dtype=joint.dtype,
            device=joint.device,
        )
        reset_mass = torch.cat(
            (switch_mass_by_target.unsqueeze(-1), reset_older_zeros), dim=-1
        )
        prior_joint = advanced_stay_mass + overflow_stay_mass + reset_mass

        return SemiMarkovPrediction(
            transition_matrix=transition,
            prior_joint_probabilities=prior_joint,
            source_hazards=source_hazards,
            age_hazards=age_hazards,
        )

    def condition(
        self,
        prediction: SemiMarkovPrediction,
        posterior_probabilities: torch.Tensor,
    ) -> ModeDurationState:
        """Condition duration ages on detached current filter mode probabilities."""

        if not isinstance(prediction, SemiMarkovPrediction):
            raise TypeError("prediction must be a SemiMarkovPrediction")
        prior_joint = self._joint_probabilities(
            ModeDurationState(
                joint_probabilities=prediction.prior_joint_probabilities
            )
        )
        posterior = self._posterior_probabilities(
            posterior_probabilities,
            expected_blocks=prior_joint.shape[0],
        ).detach()
        conditional_ages = self._conditional_age_probabilities(prior_joint)
        joint = posterior.unsqueeze(-1) * conditional_ages
        return ModeDurationState(joint_probabilities=joint)

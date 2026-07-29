"""Zero-tolerance same-environment nesting checks for formal version 09."""
from __future__ import annotations

import math

import torch
from torch import nn

from train_strict_v06 import (
    StrictNestingMismatch,
    _assert_gradients_equal,
    _assert_optimizer_states_equal,
    _assert_rng_state_equal,
    _rng_state,
    _set_rng_state,
    active_named_parameters,
    assert_batch_indices_equal,
    assert_exact_tensor,
    assert_parameter_sequence_equal,
)


class IndependentReproductionMismatch(RuntimeError):
    """Raised when independent-environment predictions exceed the frozen tolerance."""


def lockstep_train_step_v09(
    classic: nn.Module,
    nested: nn.Module,
    classic_optimizer: torch.optim.Optimizer,
    nested_optimizer: torch.optim.Optimizer,
    dynamic: dict[str, torch.Tensor],
    statics: torch.Tensor,
    target: torch.Tensor,
    loss_weights: torch.Tensor,
    *,
    basin_indices: tuple[torch.Tensor, torch.Tensor],
    target_indices: tuple[torch.Tensor, torch.Tensor],
    dropout_context: tuple[int, int, int],
    gradient_clip: float,
) -> dict:
    """Apply one paired keyed-dropout update and fail at the first non-exact value."""
    assert_batch_indices_equal(basin_indices, target_indices)
    if tuple(dynamic) != ("recent",):
        raise StrictNestingMismatch("strict nesting dynamic input must contain only the recent path")
    classic_parameters = active_named_parameters(classic)
    nested_parameters = active_named_parameters(nested)
    assert_parameter_sequence_equal(classic_parameters, nested_parameters)
    if not classic_parameters:
        raise StrictNestingMismatch("strict nesting requires active parameters")
    device = classic_parameters[0][1].device
    if nested_parameters[0][1].device != device:
        raise StrictNestingMismatch("model device mismatch")
    if target.shape != loss_weights.shape or target.ndim != 1:
        raise StrictNestingMismatch("target and loss weights must have one identical batch dimension")

    classic.train()
    nested.train()
    classic_optimizer.zero_grad(set_to_none=True)
    nested_optimizer.zero_grad(set_to_none=True)
    before = _rng_state(device)
    classic_prediction = classic(
        dynamic,
        statics,
        dropout_context=dropout_context,
    ).prediction
    classic_after = _rng_state(device)
    _set_rng_state(before, device)
    nested_prediction = nested(
        dynamic,
        statics,
        dropout_context=dropout_context,
    ).prediction
    nested_after = _rng_state(device)
    _assert_rng_state_equal(classic_after, nested_after)
    assert_exact_tensor("prediction", classic_prediction, nested_prediction)

    classic_loss = (loss_weights * torch.square(classic_prediction - target)).mean()
    nested_loss = (loss_weights * torch.square(nested_prediction - target)).mean()
    assert_exact_tensor("loss", classic_loss, nested_loss)
    classic_loss.backward()
    nested_loss.backward()
    _assert_gradients_equal(classic_parameters, nested_parameters, "unclipped")

    classic_norm = torch.nn.utils.clip_grad_norm_(
        [parameter for _, parameter in classic_parameters],
        float(gradient_clip),
    )
    nested_norm = torch.nn.utils.clip_grad_norm_(
        [parameter for _, parameter in nested_parameters],
        float(gradient_clip),
    )
    assert_exact_tensor("gradient norm", classic_norm, nested_norm)
    _assert_gradients_equal(classic_parameters, nested_parameters, "clipped")

    classic_optimizer.step()
    nested_optimizer.step()
    assert_parameter_sequence_equal(classic_parameters, nested_parameters)
    _assert_optimizer_states_equal(
        classic_optimizer,
        nested_optimizer,
        classic_parameters,
        nested_parameters,
    )
    return {
        "lockstep_exact": True,
        "prediction_equal": True,
        "loss_equal": True,
        "gradients_equal": True,
        "optimizer_state_equal": True,
        "parameters_equal": True,
        "loss": float(classic_loss.detach().cpu()),
        "gradient_norm": float(classic_norm.detach().cpu()),
    }


def assert_reproduced_predictions_v09(
    reference: torch.Tensor,
    reproduced: torch.Tensor,
) -> None:
    """Require finite, shape-identical predictions within absolute tolerance 1e-6."""
    if reference.shape != reproduced.shape:
        raise IndependentReproductionMismatch(
            f"prediction shape mismatch: {tuple(reference.shape)} != {tuple(reproduced.shape)}"
        )
    if reference.numel() == 0:
        raise IndependentReproductionMismatch("independent reproduction predictions must be nonempty")
    if not torch.isfinite(reference).all() or not torch.isfinite(reproduced).all():
        raise IndependentReproductionMismatch("independent reproduction contains nonfinite predictions")
    maximum = float((reference.to(torch.float64) - reproduced.to(torch.float64)).abs().max().cpu())
    scale = max(
        1.0,
        float(reference.to(torch.float64).abs().max().cpu()) if reference.numel() else 1.0,
    )
    boundary_roundoff = 8 * torch.finfo(torch.float64).eps * scale
    if not math.isfinite(maximum) or maximum > 1e-6 + boundary_roundoff:
        raise IndependentReproductionMismatch(
            f"independent reproduction max abs {maximum} exceeds 1e-06 with relative tolerance zero"
        )

"""Zero-tolerance lockstep training primitives for the strict nested control."""
from __future__ import annotations

from typing import Iterable

import torch
from torch import nn


class StrictNestingMismatch(RuntimeError):
    """Raised at the first component that differs between the paired runs."""


def active_named_parameters(model: nn.Module) -> list[tuple[str, nn.Parameter]]:
    return [(name, parameter) for name, parameter in model.named_parameters() if parameter.requires_grad]


def assert_exact_tensor(label: str, reference: torch.Tensor, candidate: torch.Tensor) -> None:
    if reference.shape != candidate.shape:
        raise StrictNestingMismatch(
            f"{label} shape mismatch: {tuple(reference.shape)} != {tuple(candidate.shape)}"
        )
    if reference.dtype != candidate.dtype:
        raise StrictNestingMismatch(f"{label} dtype mismatch: {reference.dtype} != {candidate.dtype}")
    if not torch.equal(reference, candidate):
        if reference.numel() and reference.is_floating_point():
            maximum = float((reference - candidate).abs().max().detach().cpu())
            detail = f"; max abs {maximum}"
        else:
            detail = ""
        raise StrictNestingMismatch(f"{label} mismatch{detail}")


def assert_batch_indices_equal(
    basin_indices: tuple[torch.Tensor, torch.Tensor],
    target_indices: tuple[torch.Tensor, torch.Tensor],
) -> None:
    assert_exact_tensor("basin batch indices", basin_indices[0], basin_indices[1])
    assert_exact_tensor("target batch indices", target_indices[0], target_indices[1])


def assert_parameter_sequence_equal(
    reference: Iterable[tuple[str, nn.Parameter]],
    candidate: Iterable[tuple[str, nn.Parameter]],
    compare_values: bool = True,
) -> None:
    reference = list(reference)
    candidate = list(candidate)
    reference_names = [name for name, _ in reference]
    candidate_names = [name for name, _ in candidate]
    if reference_names != candidate_names:
        raise StrictNestingMismatch(
            f"parameter order mismatch: {reference_names} != {candidate_names}"
        )
    for (name, reference_parameter), (_, candidate_parameter) in zip(reference, candidate):
        if reference_parameter.shape != candidate_parameter.shape:
            raise StrictNestingMismatch(f"parameter shape mismatch for {name}")
        if compare_values:
            assert_exact_tensor(f"parameter {name}", reference_parameter, candidate_parameter)


def _rng_state(device: torch.device) -> dict[str, torch.Tensor]:
    state = {"cpu": torch.get_rng_state().clone()}
    if device.type == "cuda":
        state["cuda"] = torch.cuda.get_rng_state(device).clone()
    return state


def _set_rng_state(state: dict[str, torch.Tensor], device: torch.device) -> None:
    torch.set_rng_state(state["cpu"])
    if device.type == "cuda":
        torch.cuda.set_rng_state(state["cuda"], device)


def _assert_rng_state_equal(
    reference: dict[str, torch.Tensor],
    candidate: dict[str, torch.Tensor],
) -> None:
    if tuple(reference) != tuple(candidate):
        raise StrictNestingMismatch("random-number state device set mismatch")
    for name in reference:
        assert_exact_tensor(f"{name} random-number state", reference[name], candidate[name])


def _assert_gradients_equal(
    reference: list[tuple[str, nn.Parameter]],
    candidate: list[tuple[str, nn.Parameter]],
    label: str,
) -> None:
    for (name, reference_parameter), (_, candidate_parameter) in zip(reference, candidate):
        if reference_parameter.grad is None or candidate_parameter.grad is None:
            if reference_parameter.grad is not candidate_parameter.grad:
                raise StrictNestingMismatch(f"{label} gradient presence mismatch for {name}")
            continue
        assert_exact_tensor(
            f"{label} gradient {name}",
            reference_parameter.grad,
            candidate_parameter.grad,
        )


def _assert_optimizer_states_equal(
    reference_optimizer: torch.optim.Optimizer,
    candidate_optimizer: torch.optim.Optimizer,
    reference_parameters: list[tuple[str, nn.Parameter]],
    candidate_parameters: list[tuple[str, nn.Parameter]],
) -> None:
    if len(reference_optimizer.param_groups) != len(candidate_optimizer.param_groups):
        raise StrictNestingMismatch("optimizer parameter-group count mismatch")
    for reference_group, candidate_group in zip(
        reference_optimizer.param_groups,
        candidate_optimizer.param_groups,
    ):
        reference_settings = {key: value for key, value in reference_group.items() if key != "params"}
        candidate_settings = {key: value for key, value in candidate_group.items() if key != "params"}
        if reference_settings != candidate_settings:
            raise StrictNestingMismatch("optimizer hyperparameter mismatch")
    for (name, reference_parameter), (_, candidate_parameter) in zip(
        reference_parameters,
        candidate_parameters,
    ):
        reference_state = reference_optimizer.state.get(reference_parameter, {})
        candidate_state = candidate_optimizer.state.get(candidate_parameter, {})
        if tuple(reference_state) != tuple(candidate_state):
            raise StrictNestingMismatch(f"optimizer state keys mismatch for {name}")
        for key in reference_state:
            reference_value = reference_state[key]
            candidate_value = candidate_state[key]
            if isinstance(reference_value, torch.Tensor):
                assert_exact_tensor(
                    f"optimizer state {name}.{key}",
                    reference_value,
                    candidate_value,
                )
            elif reference_value != candidate_value:
                raise StrictNestingMismatch(f"optimizer state mismatch for {name}.{key}")


def lockstep_train_step(
    classic: nn.Module,
    nested: nn.Module,
    classic_optimizer: torch.optim.Optimizer,
    nested_optimizer: torch.optim.Optimizer,
    dynamic: dict[str, torch.Tensor],
    statics: torch.Tensor,
    target: torch.Tensor,
    loss_weights: torch.Tensor,
    basin_indices: tuple[torch.Tensor, torch.Tensor],
    target_indices: tuple[torch.Tensor, torch.Tensor],
    gradient_clip: float,
) -> dict:
    """Apply one paired optimizer step and fail at the first non-exact component."""
    assert_batch_indices_equal(basin_indices, target_indices)
    classic_parameters = active_named_parameters(classic)
    nested_parameters = active_named_parameters(nested)
    assert_parameter_sequence_equal(classic_parameters, nested_parameters)
    device = classic_parameters[0][1].device
    if nested_parameters[0][1].device != device:
        raise StrictNestingMismatch("model device mismatch")

    classic.train()
    nested.train()
    classic_optimizer.zero_grad(set_to_none=True)
    nested_optimizer.zero_grad(set_to_none=True)
    before = _rng_state(device)
    classic_prediction = classic(dynamic, statics).prediction
    classic_after = _rng_state(device)
    _set_rng_state(before, device)
    nested_prediction = nested(dynamic, statics).prediction
    nested_after = _rng_state(device)
    _assert_rng_state_equal(classic_after, nested_after)
    assert_exact_tensor("prediction", classic_prediction, nested_prediction)

    classic_loss = (
        loss_weights * torch.square(classic_prediction - target)
    ).mean()
    nested_loss = (
        loss_weights * torch.square(nested_prediction - target)
    ).mean()
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
        "status": "exact",
        "prediction_equal": True,
        "loss_equal": True,
        "gradients_equal": True,
        "optimizer_state_equal": True,
        "parameters_equal": True,
        "loss": float(classic_loss.detach().cpu()),
        "gradient_norm": float(classic_norm.detach().cpu()),
    }


def exact_evaluation_predictions(
    classic: nn.Module,
    nested: nn.Module,
    batches: Iterable[tuple[dict[str, torch.Tensor], torch.Tensor]],
) -> tuple[torch.Tensor, torch.Tensor]:
    """Evaluate paired batches and require every prediction to be bitwise equal."""
    assert_parameter_sequence_equal(
        active_named_parameters(classic),
        active_named_parameters(nested),
    )
    classic.eval()
    nested.eval()
    classic_parts = []
    nested_parts = []
    with torch.no_grad():
        for batch_index, (dynamic, statics) in enumerate(batches):
            classic_prediction = classic(dynamic, statics).prediction
            nested_prediction = nested(dynamic, statics).prediction
            assert_exact_tensor(
                f"evaluation prediction batch {batch_index}",
                classic_prediction,
                nested_prediction,
            )
            classic_parts.append(classic_prediction)
            nested_parts.append(nested_prediction)
    if not classic_parts:
        raise ValueError("at least one evaluation batch is required")
    return torch.cat(classic_parts), torch.cat(nested_parts)

"""Strict post-training branch masks for the frozen version 05 model."""
from __future__ import annotations

from collections.abc import Mapping

import torch
from torch import nn


BRANCH_COMBINATIONS = (
    ("recent",),
    ("medium",),
    ("old",),
    ("recent", "medium"),
    ("recent", "old"),
    ("medium", "old"),
    ("recent", "medium", "old"),
)
DEFAULT_BRANCH_WIDTHS = {
    "recent": 256,
    "medium": 64,
    "old": 128,
}


def capture_fused_features(
    model: nn.Module,
    dynamic: Mapping[str, torch.Tensor],
    statics: torch.Tensor,
) -> tuple[torch.Tensor, torch.Tensor]:
    """Return the original prediction and the exact tensor entering its head."""
    if model.training:
        raise ValueError("branch masking requires evaluation mode")
    if not hasattr(model, "head"):
        raise TypeError("model must expose its final linear head")

    captured: list[torch.Tensor] = []

    def _capture(_module: nn.Module, inputs: tuple[torch.Tensor, ...]) -> None:
        if len(inputs) != 1:
            raise ValueError("final head must receive exactly one fused tensor")
        captured.append(inputs[0])

    hook = model.head.register_forward_pre_hook(_capture)
    try:
        output = model(dynamic, statics)
    finally:
        hook.remove()
    if len(captured) != 1:
        raise RuntimeError(f"expected one final-head call, captured {len(captured)}")
    return output.prediction, captured[0]


def masked_predictions_from_fused(
    model: nn.Module,
    fused: torch.Tensor,
    branch_widths: Mapping[str, int] = DEFAULT_BRANCH_WIDTHS,
) -> dict[tuple[str, ...], torch.Tensor]:
    """Apply all seven nonempty masks after encoding and before the frozen head."""
    if model.training:
        raise ValueError("branch masking requires evaluation mode")
    if fused.ndim != 2:
        raise ValueError("fused features must have shape [N,D]")
    ordered_names = tuple(branch_widths)
    if ordered_names != ("recent", "medium", "old"):
        raise ValueError("branch widths must be ordered as recent, medium, old")
    total_width = sum(int(width) for width in branch_widths.values())
    if fused.shape[1] != total_width:
        raise ValueError(f"fused features must have width {total_width}")
    if model.head.in_features != total_width or model.head.out_features != 1:
        raise ValueError("model head is not the frozen single-output version 05 head")

    slices = {}
    start = 0
    for name, width in branch_widths.items():
        stop = start + int(width)
        slices[name] = slice(start, stop)
        start = stop

    predictions = {}
    for combination in BRANCH_COMBINATIONS:
        masked = torch.zeros_like(fused)
        for name in combination:
            masked[:, slices[name]] = fused[:, slices[name]]
        predictions[combination] = model.head(masked)[:, 0]
    return predictions

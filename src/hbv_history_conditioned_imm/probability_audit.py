"""Known-hazard audit for history-conditioned transition probabilities."""

from __future__ import annotations

from dataclasses import asdict, dataclass

import torch
from torch.nn import functional as functional

from .synthetic import SyntheticBatch


@dataclass(frozen=True)
class ActiveRowOracle:
    source_indices: torch.Tensor
    destination_indices: torch.Tensor
    active_row_probabilities: torch.Tensor
    switch_hazard: torch.Tensor
    segment_age: torch.Tensor
    evaluation_mask: torch.Tensor
    switch_event_mask: torch.Tensor


@dataclass(frozen=True)
class TransitionRecoveryScores:
    evaluated_transition_count: int
    switch_event_count: int
    oracle_cross_entropy: float
    oracle_brier: float
    realized_transition_negative_log_score: float
    realized_transition_brier: float
    realized_destination_top_probability_accuracy: float
    switch_hazard_mean_absolute_error: float
    mean_predicted_switch_hazard: float
    mean_oracle_switch_hazard: float
    switch_day_hazard_mean_absolute_error: float
    mean_switch_day_new_destination_probability: float

    def to_dict(self) -> dict[str, int | float]:
        return asdict(self)


def build_active_row_oracle(
    batch: SyntheticBatch,
    minimum_duration: int,
    maximum_duration: int,
) -> ActiveRowOracle:
    """Build exact conditional probabilities for the realized source row."""
    minimum = int(minimum_duration)
    maximum = int(maximum_duration)
    if minimum <= 0 or maximum < minimum:
        raise ValueError("duration bounds are invalid")
    modes = batch.true_process_indices[:, : batch.assimilation_days]
    if modes.ndim != 2 or torch.any(modes < 0) or torch.any(modes > 2):
        raise ValueError("true process indices must be a batch-by-day array in zero through two")
    block_count, days = modes.shape
    if batch.switch_days.shape != (block_count, 2):
        raise ValueError("every block must contain exactly two switch days")

    source_indices = modes.clone()
    source_indices[:, 1:] = modes[:, :-1]
    destination_indices = modes.clone()
    active_rows = torch.zeros((block_count, days, 3), dtype=torch.float64)
    switch_hazard = torch.zeros((block_count, days), dtype=torch.float64)
    segment_age = torch.zeros((block_count, days), dtype=torch.int64)
    evaluation_mask = torch.zeros((block_count, days), dtype=torch.bool)

    for block in range(block_count):
        first_switch = int(batch.switch_days[block, 0])
        second_switch = int(batch.switch_days[block, 1])
        durations = (first_switch, second_switch - first_switch)
        if (
            first_switch <= 0
            or second_switch <= first_switch
            or second_switch >= days
            or any(duration < minimum or duration > maximum for duration in durations)
        ):
            raise ValueError("switch days do not satisfy the frozen duration contract")
        for start, stop in ((0, first_switch), (first_switch, second_switch)):
            for day in range(start + 1, stop + 1):
                age = day - start
                hazard = (
                    0.0
                    if age < minimum
                    else 1.0 / float(maximum - age + 1)
                )
                source = int(source_indices[block, day])
                row = torch.full((3,), hazard / 2.0, dtype=torch.float64)
                row[source] = 1.0 - hazard
                active_rows[block, day] = row
                switch_hazard[block, day] = hazard
                segment_age[block, day] = age
                evaluation_mask[block, day] = True

    switch_event_mask = evaluation_mask & (source_indices != destination_indices)
    return ActiveRowOracle(
        source_indices=source_indices,
        destination_indices=destination_indices,
        active_row_probabilities=active_rows,
        switch_hazard=switch_hazard,
        segment_age=segment_age,
        evaluation_mask=evaluation_mask,
        switch_event_mask=switch_event_mask,
    )


def active_transition_rows(
    transition_matrices: torch.Tensor,
    source_indices: torch.Tensor,
) -> torch.Tensor:
    """Gather matrix rows using source candidates, never destination columns."""
    if transition_matrices.ndim != 4 or transition_matrices.shape[-2:] != (3, 3):
        raise ValueError("transition_matrices must have shape [batch, day, 3, 3]")
    if source_indices.shape != transition_matrices.shape[:2]:
        raise ValueError("source_indices must match the batch and day dimensions")
    if torch.any(source_indices < 0) or torch.any(source_indices > 2):
        raise ValueError("source indices must lie between zero and two")
    gather_index = source_indices[..., None, None].expand(-1, -1, 1, 3)
    return torch.gather(transition_matrices, dim=2, index=gather_index).squeeze(2)


def balanced_active_row_oracle_brier(
    transition_matrices: torch.Tensor,
    oracle: ActiveRowOracle,
    minimum_duration: int,
) -> torch.Tensor:
    """Give pre-eligible and switch-eligible ages equal loss weight."""
    minimum = int(minimum_duration)
    if minimum <= 0:
        raise ValueError("minimum_duration must be positive")
    rows = active_transition_rows(transition_matrices, oracle.source_indices)
    if rows.shape != oracle.active_row_probabilities.shape:
        raise ValueError("oracle and predicted active rows must share one shape")
    squared_error = (
        rows - oracle.active_row_probabilities.to(
            dtype=rows.dtype, device=rows.device
        )
    ).square().sum(dim=-1)
    evaluation = oracle.evaluation_mask.to(device=rows.device)
    ages = oracle.segment_age.to(device=rows.device)
    pre_eligible = evaluation & (ages < minimum)
    switch_eligible = evaluation & (ages >= minimum)
    if not torch.any(pre_eligible) or not torch.any(switch_eligible):
        raise ValueError("both oracle age groups must contain evaluated transitions")
    return 0.5 * (
        squared_error[pre_eligible].mean()
        + squared_error[switch_eligible].mean()
    )


def score_transition_recovery(
    transition_matrices: torch.Tensor,
    oracle: ActiveRowOracle,
) -> TransitionRecoveryScores:
    """Score only identifiable active rows with proper probability scores."""
    rows = active_transition_rows(transition_matrices, oracle.source_indices)
    if rows.shape != oracle.active_row_probabilities.shape:
        raise ValueError("oracle and predicted active rows must share one shape")
    if not torch.isfinite(rows).all() or torch.any(rows < 0.0):
        raise ValueError("transition probabilities must be finite and nonnegative")
    if torch.max(torch.abs(rows.sum(dim=-1) - 1.0)) > 1e-12:
        raise ValueError("transition rows must sum to one within 1e-12")
    mask = oracle.evaluation_mask
    if not torch.any(mask):
        raise ValueError("oracle evaluation mask is empty")
    predicted = rows[mask]
    expected = oracle.active_row_probabilities[mask]
    destination = oracle.destination_indices[mask]
    source = oracle.source_indices[mask]
    tiny = torch.finfo(predicted.dtype).tiny

    oracle_cross_entropy_terms = torch.where(
        expected > 0.0,
        -expected * torch.log(torch.clamp(predicted, min=tiny)),
        torch.zeros_like(expected),
    )
    oracle_cross_entropy = oracle_cross_entropy_terms.sum(dim=-1).mean()
    oracle_brier = (predicted - expected).square().sum(dim=-1).mean()
    realized_probability = torch.gather(
        predicted, dim=-1, index=destination.unsqueeze(-1)
    ).squeeze(-1)
    realized_negative_log = -torch.log(
        torch.clamp(realized_probability, min=tiny)
    ).mean()
    realized_one_hot = functional.one_hot(destination, num_classes=3).to(
        dtype=predicted.dtype
    )
    realized_brier = (predicted - realized_one_hot).square().sum(dim=-1).mean()
    top_accuracy = (predicted.argmax(dim=-1) == destination).to(
        dtype=predicted.dtype
    ).mean()

    alternative_mask = 1.0 - functional.one_hot(source, num_classes=3).to(
        dtype=predicted.dtype
    )
    predicted_hazard = (predicted * alternative_mask).sum(dim=-1)
    oracle_hazard = oracle.switch_hazard[mask]
    hazard_error = torch.abs(predicted_hazard - oracle_hazard)

    event_mask = oracle.switch_event_mask[mask]
    event_count = int(torch.count_nonzero(event_mask))
    if event_count == 0:
        switch_day_hazard_error = torch.zeros((), dtype=predicted.dtype)
        mean_new_destination_probability = torch.zeros((), dtype=predicted.dtype)
    else:
        switch_day_hazard_error = hazard_error[event_mask].mean()
        mean_new_destination_probability = realized_probability[event_mask].mean()
    return TransitionRecoveryScores(
        evaluated_transition_count=int(torch.count_nonzero(mask)),
        switch_event_count=event_count,
        oracle_cross_entropy=float(oracle_cross_entropy),
        oracle_brier=float(oracle_brier),
        realized_transition_negative_log_score=float(realized_negative_log),
        realized_transition_brier=float(realized_brier),
        realized_destination_top_probability_accuracy=float(top_accuracy),
        switch_hazard_mean_absolute_error=float(hazard_error.mean()),
        mean_predicted_switch_hazard=float(predicted_hazard.mean()),
        mean_oracle_switch_hazard=float(oracle_hazard.mean()),
        switch_day_hazard_mean_absolute_error=float(switch_day_hazard_error),
        mean_switch_day_new_destination_probability=float(
            mean_new_destination_probability
        ),
    )

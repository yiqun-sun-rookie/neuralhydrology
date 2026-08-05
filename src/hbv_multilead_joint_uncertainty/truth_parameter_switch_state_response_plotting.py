"""Figures for the synthetic true-parameter switch state-response control."""

from __future__ import annotations

from pathlib import Path

import matplotlib
import numpy as np

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402


TRANSITION_COLORS = ("#0072B2", "#E69F00", "#009E73")


def _clean_label(label: str) -> str:
    return str(label).replace("_to_", " → ").replace("_", " ")


def plot_per_state_standardized_response(
    output_path: Path,
    *,
    leads,
    state_names,
    transition_labels,
    transition_state_response,
) -> None:
    """Plot each state's standardized causal response for all transitions."""
    lead_values = np.asarray(leads, dtype=np.int64)
    names = np.asarray(state_names).astype(str)
    labels = np.asarray(transition_labels).astype(str)
    response = np.asarray(transition_state_response, dtype=np.float64)
    if response.shape != (len(labels), len(lead_values), len(names)):
        raise ValueError("transition state response has an invalid shape")

    figure, axes = plt.subplots(5, 3, figsize=(15.5, 17.0), sharex=True)
    for state_index, axis in enumerate(axes.ravel()):
        for transition_index, label in enumerate(labels):
            axis.plot(
                lead_values,
                response[transition_index, :, state_index],
                color=TRANSITION_COLORS[transition_index % len(TRANSITION_COLORS)],
                linewidth=1.8,
                label=_clean_label(label),
            )
        axis.set_title(names[state_index], fontsize=10)
        axis.grid(alpha=0.25, linewidth=0.7)
        axis.set_xlim(int(lead_values[0]), int(lead_values[-1]))
        axis.tick_params(labelsize=8)
    for axis in axes[-1]:
        axis.set_xlabel("Days after true-parameter boundary")
    for axis in axes[:, 0]:
        axis.set_ylabel("Root-mean-square standardized\nnew-minus-old response")
    handles, legend_labels = axes[0, 0].get_legend_handles_labels()
    figure.legend(
        handles,
        legend_labels,
        loc="upper center",
        bbox_to_anchor=(0.5, 0.948),
        ncol=3,
        frameon=False,
        fontsize=8,
    )
    figure.suptitle(
        "Matched causal state response to each HBV synthetic true-parameter switch\n"
        "Curves are branch differences, not state-estimation or forecast errors",
        fontsize=13,
        y=0.995,
    )
    figure.tight_layout(rect=(0.02, 0.02, 0.98, 0.905))
    figure.savefig(output_path, dpi=180, bbox_inches="tight")
    plt.close(figure)


def plot_state_group_standardized_response(
    output_path: Path,
    *,
    leads,
    group_names,
    pooled_group_response,
    transition_labels,
    transition_group_response,
) -> None:
    """Plot pooled and transition-specific responses for both state groups."""
    lead_values = np.asarray(leads, dtype=np.int64)
    names = np.asarray(group_names).astype(str)
    labels = np.asarray(transition_labels).astype(str)
    pooled = np.asarray(pooled_group_response, dtype=np.float64)
    transition = np.asarray(transition_group_response, dtype=np.float64)
    if pooled.shape != (len(lead_values), len(names)):
        raise ValueError("pooled group response has an invalid shape")
    if transition.shape != (len(labels), len(lead_values), len(names)):
        raise ValueError("transition group response has an invalid shape")

    figure, axes = plt.subplots(1, len(names), figsize=(13.5, 5.2), sharex=True)
    axes = np.atleast_1d(axes)
    for group_index, axis in enumerate(axes):
        axis.plot(lead_values, pooled[:, group_index], color="#222222", linewidth=2.6, label="All 48 events")
        for transition_index, label in enumerate(labels):
            axis.plot(
                lead_values,
                transition[transition_index, :, group_index],
                color=TRANSITION_COLORS[transition_index % len(TRANSITION_COLORS)],
                linewidth=1.8,
                label=_clean_label(label),
            )
        axis.set_title(names[group_index].replace("_", " "))
        axis.set_xlabel("Days after true-parameter boundary")
        axis.set_ylabel("Root-mean-square standardized\nnew-minus-old response")
        axis.set_xlim(int(lead_values[0]), int(lead_values[-1]))
        axis.grid(alpha=0.25, linewidth=0.7)
    handles, legend_labels = axes[0].get_legend_handles_labels()
    figure.legend(
        handles,
        legend_labels,
        loc="upper center",
        bbox_to_anchor=(0.5, 0.90),
        ncol=2,
        frameon=False,
        fontsize=8,
    )
    figure.suptitle(
        "HBV synthetic state-group causal response (same state, forcing, and process perturbations)",
        fontsize=12,
        y=0.99,
    )
    figure.tight_layout(rect=(0.02, 0.02, 0.98, 0.78))
    figure.savefig(output_path, dpi=180, bbox_inches="tight")
    plt.close(figure)


def plot_initial_new_parameter_domain_projection(
    output_path: Path,
    *,
    standardized_projection_adjustments,
    state_names,
    event_transition_labels,
) -> None:
    """Plot event-state magnitude of the initial new-parameter-domain projection."""
    projection = np.abs(np.asarray(standardized_projection_adjustments, dtype=np.float64))
    names = np.asarray(state_names).astype(str)
    labels = np.asarray(event_transition_labels).astype(str)
    if projection.shape != (len(labels), len(names)):
        raise ValueError("initial standardized projection has an invalid shape")
    order = np.argsort(labels, kind="stable")
    ordered = projection[order]
    ordered_labels = labels[order]

    figure, axis = plt.subplots(figsize=(14.5, 9.0))
    image = axis.imshow(ordered, aspect="auto", interpolation="nearest", cmap="viridis")
    axis.set_xticks(np.arange(len(names)))
    axis.set_xticklabels(names, rotation=45, ha="right")
    axis.set_ylabel("Matched switch event, grouped by directed transition")
    axis.set_xlabel("State")
    boundaries = np.flatnonzero(ordered_labels[1:] != ordered_labels[:-1]) + 0.5
    for boundary in boundaries:
        axis.axhline(boundary, color="white", linewidth=1.5)
    starts = np.r_[0, boundaries + 0.5]
    ends = np.r_[boundaries - 0.5, len(ordered_labels) - 1]
    centers = (starts + ends) / 2.0
    group_labels = [ordered_labels[int(start)] for start in starts]
    axis.set_yticks(centers)
    axis.set_yticklabels([_clean_label(label) for label in group_labels], fontsize=9)
    colorbar = figure.colorbar(image, ax=axis, pad=0.015)
    colorbar.set_label("Absolute projection adjustment / frozen state standard deviation")
    axis.set_title(
        "Initial state change imposed by the new parameter domain before daily forcing\n"
        "This is a generator projection, not an observed or assimilated state update"
    )
    figure.tight_layout()
    figure.savefig(output_path, dpi=180, bbox_inches="tight")
    plt.close(figure)

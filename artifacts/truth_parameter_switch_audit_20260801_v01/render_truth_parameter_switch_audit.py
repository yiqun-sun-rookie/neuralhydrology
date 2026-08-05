from __future__ import annotations

import argparse
import csv
import hashlib
import json
from pathlib import Path

import matplotlib.pyplot as plt
from matplotlib.colors import BoundaryNorm, ListedColormap, PowerNorm
import numpy as np


AUDIT_ID = "truth_parameter_switch_audit_20260801_v01"
EXPECTED_EVIDENCE_SHA256 = (
    "77f84d793f18a72972e5af5f2ac4ed767645471e37da31c612ab995ecf4bbf67"
)
STATE_NAMES = (
    "SNOWPACK",
    "MELTWATER",
    "SM",
    "SUZ",
    "SLZ",
    "qraw_t_minus_0",
    "qraw_t_minus_1",
    "qraw_t_minus_2",
    "qraw_t_minus_3",
    "qraw_t_minus_4",
    "qraw_t_minus_5",
    "qraw_t_minus_6",
    "qraw_t_minus_7",
    "qraw_t_minus_8",
    "qraw_t_minus_9",
)
HYDRO_LABELS = (
    "Snowpack (SNOWPACK)",
    "Liquid water in snow (MELTWATER)",
    "Soil moisture (SM)",
    "Upper-zone storage (SUZ)",
    "Lower-zone storage (SLZ)",
)
PARAMETER_NAMES = (
    "parTT",
    "parCFMAX",
    "parCFR",
    "parCWH",
    "parFC",
    "parBETA",
    "parLP",
    "parK0",
    "parK1",
    "parUZL",
    "parPERC",
    "parK2",
    "lag_time",
)
PARAMETER_LABELS = {
    "equifinal_diverse_1": "Equal-fit alternative 1",
    "trained_center": "Calibrated center",
    "equifinal_diverse_2": "Equal-fit alternative 2",
}
PARAMETER_COLORS = {
    "equifinal_diverse_1": "#E69F00",
    "trained_center": "#0072B2",
    "equifinal_diverse_2": "#009E73",
}


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def ensure_targets_absent(paths: list[Path]) -> None:
    present = [str(path) for path in paths if path.exists()]
    if present:
        raise FileExistsError("Refusing to overwrite existing outputs: " + ", ".join(present))


def draw_switch_lines(axis: plt.Axes) -> None:
    for boundary in (180.5, 360.5):
        axis.axvline(boundary, color="#4D4D4D", linewidth=0.9, linestyle="--", alpha=0.8)


def stage_segments(parameter_indices: np.ndarray) -> list[tuple[int, int, int]]:
    changes = (np.flatnonzero(parameter_indices[1:] != parameter_indices[:-1]) + 1).tolist()
    starts = [0, *changes]
    ends = [*changes, len(parameter_indices)]
    return [(start, end, int(parameter_indices[start])) for start, end in zip(starts, ends)]


def set_stage_axis(
    axis: plt.Axes,
    parameter_indices: np.ndarray,
    parameter_ids: list[str],
    show_trial_title: str,
) -> None:
    cmap = ListedColormap([PARAMETER_COLORS[name] for name in parameter_ids])
    norm = BoundaryNorm(np.arange(-0.5, len(parameter_ids) + 0.5), cmap.N)
    axis.imshow(
        parameter_indices[np.newaxis, :],
        aspect="auto",
        interpolation="nearest",
        extent=(0.5, len(parameter_indices) + 0.5, 0.0, 1.0),
        cmap=cmap,
        norm=norm,
    )
    for stage_number, (start, end, index) in enumerate(stage_segments(parameter_indices), start=1):
        parameter_id = parameter_ids[index]
        axis.text(
            (start + end + 1) / 2,
            0.5,
            f"Stage {stage_number}: days {start + 1}-{end}\n{PARAMETER_LABELS[parameter_id]}",
            ha="center",
            va="center",
            fontsize=8.5,
            color="white",
            fontweight="bold",
            path_effects=[],
        )
    axis.set_title(show_trial_title, fontsize=12, fontweight="bold", pad=8)
    axis.set_xlim(0.5, len(parameter_indices) + 0.5)
    axis.set_yticks([])
    axis.tick_params(axis="x", labelbottom=False, bottom=False)
    for spine in axis.spines.values():
        spine.set_visible(False)


def set_common_time_axis(axis: plt.Axes, day_count: int, show_xlabels: bool) -> None:
    axis.set_xlim(0.5, day_count + 0.5)
    axis.set_xticks([1, 90, 180, 270, 360, 450, 540])
    axis.grid(axis="y", color="#D9D9D9", linewidth=0.5, alpha=0.8)
    draw_switch_lines(axis)
    if show_xlabels:
        axis.set_xlabel("Assimilation day")
    else:
        axis.tick_params(axis="x", labelbottom=False)


def draw_trial_column(
    axes: list[plt.Axes],
    days: np.ndarray,
    parameter_indices: np.ndarray,
    parameter_ids: list[str],
    truth_discharge: np.ndarray,
    observed_discharge: np.ndarray,
    truth_states: np.ndarray,
    trial_number: int,
    hydro_limits: list[tuple[float, float]],
    routing_norm: PowerNorm,
) -> object:
    set_stage_axis(
        axes[0],
        parameter_indices,
        parameter_ids,
        f"Truth trial {trial_number} | raw registered block 01",
    )

    axes[1].plot(days, observed_discharge, color="#56B4E9", linewidth=0.8, alpha=0.8, label="Noisy observed discharge")
    axes[1].plot(days, truth_discharge, color="#111111", linewidth=1.1, label="Truth discharge")
    axes[1].set_ylabel("Discharge")
    axes[1].legend(loc="upper right", fontsize=7.5, frameon=False)
    set_common_time_axis(axes[1], len(days), show_xlabels=False)

    for state_index, axis in enumerate(axes[2:7]):
        axis.plot(days, truth_states[:, state_index], color="#5B2C6F", linewidth=0.9)
        axis.set_ylabel(HYDRO_LABELS[state_index], fontsize=8.5)
        axis.set_ylim(*hydro_limits[state_index])
        set_common_time_axis(axis, len(days), show_xlabels=False)

    routing = truth_states[:, 5:].T
    image = axes[7].imshow(
        routing,
        aspect="auto",
        interpolation="nearest",
        origin="upper",
        extent=(0.5, len(days) + 0.5, 9.5, -0.5),
        cmap="magma",
        norm=routing_norm,
    )
    axes[7].set_yticks(range(10))
    axes[7].set_yticklabels([f"qraw lag {lag}" for lag in range(10)], fontsize=7.5)
    axes[7].set_ylabel("Routing-memory states", fontsize=8.5)
    set_common_time_axis(axes[7], len(days), show_xlabels=True)
    return image


def save_figure(path: Path, figure: plt.Figure) -> None:
    if path.exists():
        raise FileExistsError(f"Refusing to overwrite {path}")
    figure.savefig(path, dpi=220, bbox_inches="tight", facecolor="white")
    plt.close(figure)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()

    evidence = args.evidence.resolve()
    output_dir = args.output_dir.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    evidence_hash = sha256_file(evidence)
    if evidence_hash != EXPECTED_EVIDENCE_SHA256:
        raise RuntimeError(
            f"Evidence hash mismatch: expected {EXPECTED_EVIDENCE_SHA256}, got {evidence_hash}"
        )

    combined_path = output_dir / "truth_parameter_switch_audit_all_trials.png"
    individual_paths = [
        output_dir / f"truth_parameter_switch_audit_trial_{trial}.png"
        for trial in (1, 2, 3)
    ]
    schedule_path = output_dir / "stage_schedule.csv"
    parameter_path = output_dir / "true_parameter_vectors.csv"
    boundary_path = output_dir / "boundary_state_change_audit.csv"
    plotted_data_path = output_dir / "plotted_data.npz"
    render_summary_path = output_dir / "render_summary.json"
    targets = [
        combined_path,
        *individual_paths,
        schedule_path,
        parameter_path,
        boundary_path,
        plotted_data_path,
        render_summary_path,
    ]
    ensure_targets_absent(targets)

    with np.load(evidence, allow_pickle=False) as source:
        assimilation_days = int(source["assimilation_days"])
        if assimilation_days != 540:
            raise ValueError(f"Expected 540 assimilation days, got {assimilation_days}")
        parameter_ids = source["parameter_ids"].astype(str).tolist()
        parameter_vectors = source["parameter_vectors"].astype(np.float64)
        parameter_indices = source["truth_parameter_indices"][:, :assimilation_days].astype(np.int64)
        process_indices = source["truth_process_indices"][:, :assimilation_days].astype(np.int64)
        truth_states = source["truth_states"][0, :, :assimilation_days, :].astype(np.float64)
        truth_discharge = source["truth_discharge"][0, :, :assimilation_days].astype(np.float64)
        observed_discharge = source["observed_discharge"][0, :, :assimilation_days].astype(np.float64)
        observation_normals = source["observation_standard_normals"][0, :assimilation_days].astype(np.float64)
        observation_std = float(source["observation_standard_deviation"])
        registered_block_id = str(source["block_ids"][0])

    if truth_states.shape != (3, 540, 15):
        raise ValueError(f"Unexpected truth-state shape {truth_states.shape}")
    if not all(np.all(np.isfinite(array)) for array in (truth_states, truth_discharge, observed_discharge)):
        raise ValueError("Plotted truth arrays contain non-finite values")
    for trial_index in range(3):
        changes = (np.flatnonzero(parameter_indices[trial_index, 1:] != parameter_indices[trial_index, :-1]) + 1).tolist()
        if changes != [180, 360]:
            raise ValueError(f"Truth trial {trial_index + 1} has unexpected switch indices {changes}")
        if np.unique(process_indices[trial_index]).tolist() != [2]:
            raise ValueError(f"Truth trial {trial_index + 1} changes the process-noise candidate")
    observation_residual = observed_discharge - truth_discharge - observation_std * observation_normals[np.newaxis, :]
    maximum_observation_residual = float(np.max(np.abs(observation_residual)))
    if maximum_observation_residual > 1.0e-12:
        raise ValueError(f"Observation equation failed with residual {maximum_observation_residual}")

    with schedule_path.open("x", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=("truth_trial", "stage", "start_day", "end_day", "parameter_id", "parameter_label", "process_index"),
        )
        writer.writeheader()
        for trial_index in range(3):
            for stage_number, (start, end, parameter_index) in enumerate(stage_segments(parameter_indices[trial_index]), start=1):
                parameter_id = parameter_ids[parameter_index]
                writer.writerow(
                    {
                        "truth_trial": trial_index + 1,
                        "stage": stage_number,
                        "start_day": start + 1,
                        "end_day": end,
                        "parameter_id": parameter_id,
                        "parameter_label": PARAMETER_LABELS[parameter_id],
                        "process_index": int(process_indices[trial_index, start]),
                    }
                )

    with parameter_path.open("x", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(("parameter_name", *parameter_ids))
        for parameter_name, row in zip(PARAMETER_NAMES, parameter_vectors.T):
            writer.writerow((parameter_name, *(format(float(value), ".17g") for value in row)))

    boundary_rows: list[dict[str, object]] = []
    boundary_indices = (180, 360)
    for trial_index in range(3):
        daily_absolute_changes = np.abs(np.diff(truth_states[trial_index], axis=0))
        reference_mask = np.ones(daily_absolute_changes.shape[0], dtype=bool)
        reference_mask[[boundary - 1 for boundary in boundary_indices]] = False
        for boundary in boundary_indices:
            for state_index, state_name in enumerate(STATE_NAMES):
                reference = daily_absolute_changes[reference_mask, state_index]
                boundary_change = float(daily_absolute_changes[boundary - 1, state_index])
                median_change = float(np.median(reference))
                percentile_95 = float(np.percentile(reference, 95))
                boundary_rows.append(
                    {
                        "truth_trial": trial_index + 1,
                        "switch_between_days": f"{boundary}-{boundary + 1}",
                        "state_name": state_name,
                        "absolute_boundary_change": boundary_change,
                        "non_boundary_median_absolute_change": median_change,
                        "non_boundary_95th_percentile_absolute_change": percentile_95,
                        "boundary_to_non_boundary_95th_ratio": boundary_change / percentile_95 if percentile_95 > 0.0 else np.nan,
                    }
                )
    with boundary_path.open("x", newline="", encoding="utf-8") as handle:
        fieldnames = tuple(boundary_rows[0].keys())
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(boundary_rows)

    if plotted_data_path.exists():
        raise FileExistsError(f"Refusing to overwrite {plotted_data_path}")
    np.savez_compressed(
        plotted_data_path,
        registered_block_id=np.asarray(registered_block_id),
        parameter_ids=np.asarray(parameter_ids),
        parameter_indices=parameter_indices,
        process_indices=process_indices,
        truth_states=truth_states,
        truth_discharge=truth_discharge,
        observed_discharge=observed_discharge,
        observation_standard_normals=observation_normals,
        observation_standard_deviation=np.asarray(observation_std),
    )

    plt.rcParams.update(
        {
            "font.family": "sans-serif",
            "font.sans-serif": ["Arial", "DejaVu Sans"],
            "axes.spines.top": False,
            "axes.spines.right": False,
            "axes.labelsize": 9,
            "xtick.labelsize": 8,
            "ytick.labelsize": 8,
        }
    )
    days = np.arange(1, assimilation_days + 1)
    hydro_limits: list[tuple[float, float]] = []
    for state_index in range(5):
        values = truth_states[:, :, state_index]
        lower = float(np.min(values))
        upper = float(np.max(values))
        padding = max((upper - lower) * 0.05, 1.0e-6)
        hydro_limits.append((lower - padding, upper + padding))
    routing_max = float(np.max(truth_states[:, :, 5:]))
    routing_norm = PowerNorm(gamma=0.45, vmin=0.0, vmax=max(routing_max, 1.0e-12))

    figure, axis_grid = plt.subplots(
        8,
        3,
        figsize=(22, 20),
        gridspec_kw={"height_ratios": [0.58, 1.4, 1.0, 1.0, 1.0, 1.0, 1.0, 1.65], "hspace": 0.17, "wspace": 0.25},
    )
    route_image = None
    for trial_index in range(3):
        route_image = draw_trial_column(
            list(axis_grid[:, trial_index]),
            days,
            parameter_indices[trial_index],
            parameter_ids,
            truth_discharge[trial_index],
            observed_discharge[trial_index],
            truth_states[trial_index],
            trial_index + 1,
            hydro_limits,
            routing_norm,
        )
        if trial_index > 0:
            for row in range(1, 7):
                axis_grid[row, trial_index].set_ylabel("")
    figure.suptitle(
        "Synthetic truth generation audit: staged true parameters, discharge, and all 15 continuous states\n"
        "Registered block 01; 540 assimilation days; no cross-block aggregation; switches occur between days 180-181 and 360-361",
        fontsize=15,
        fontweight="bold",
        y=0.995,
    )
    colorbar = figure.colorbar(route_image, ax=axis_grid[7, :].tolist(), fraction=0.018, pad=0.012)
    colorbar.set_label("Routing-memory value (nonlinear color scale, gamma=0.45)", fontsize=8)
    figure.text(
        0.01,
        0.004,
        f"Source evidence SHA-256: {evidence_hash} | State values carry across switches; only the true parameter vector changes.",
        fontsize=7.5,
    )
    save_figure(combined_path, figure)

    for trial_index, individual_path in enumerate(individual_paths):
        figure, axis_grid = plt.subplots(
            8,
            1,
            figsize=(15, 20),
            gridspec_kw={"height_ratios": [0.58, 1.4, 1.0, 1.0, 1.0, 1.0, 1.0, 1.65], "hspace": 0.17},
        )
        route_image = draw_trial_column(
            list(axis_grid),
            days,
            parameter_indices[trial_index],
            parameter_ids,
            truth_discharge[trial_index],
            observed_discharge[trial_index],
            truth_states[trial_index],
            trial_index + 1,
            hydro_limits,
            routing_norm,
        )
        figure.suptitle(
            "Synthetic truth generation audit: staged true parameters, discharge, and all 15 continuous states\n"
            "Registered block 01; no cross-block aggregation",
            fontsize=15,
            fontweight="bold",
            y=0.995,
        )
        colorbar = figure.colorbar(route_image, ax=axis_grid[7], fraction=0.025, pad=0.012)
        colorbar.set_label("Routing-memory value (nonlinear color scale, gamma=0.45)", fontsize=8)
        figure.text(
            0.01,
            0.004,
            f"Source evidence SHA-256: {evidence_hash} | State values carry across switches; only the true parameter vector changes.",
            fontsize=7.5,
        )
        save_figure(individual_path, figure)

    summary = {
        "audit_id": AUDIT_ID,
        "status": "rendered",
        "source_evidence": str(evidence),
        "source_evidence_sha256": evidence_hash,
        "registered_block_index_zero_based": 0,
        "registered_block_id": registered_block_id,
        "assimilation_days": assimilation_days,
        "truth_trial_count": 3,
        "state_count": 15,
        "switch_boundaries_between_days": [180, 360],
        "process_indices_by_trial": [np.unique(row).tolist() for row in process_indices],
        "maximum_observation_equation_absolute_residual": maximum_observation_residual,
        "aggregation": "none",
        "outputs": [str(path) for path in targets if path != render_summary_path],
    }
    with render_summary_path.open("x", encoding="utf-8") as handle:
        json.dump(summary, handle, indent=2, ensure_ascii=False)
        handle.write("\n")


if __name__ == "__main__":
    main()

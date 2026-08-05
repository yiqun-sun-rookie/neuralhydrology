from __future__ import annotations

import argparse
import csv
import hashlib
import json
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np


AUDIT_ID = "state_parameter_stage_overlay_20260801_v01"
EXPECTED_STATE_HASH = "22f1b99ee0cf537e1aa7c9b414662c0b390510f2dc0d6b07bf538dd6dda33a04"
EXPECTED_TRUTH_HASH = "77f84d793f18a72972e5af5f2ac4ed767645471e37da31c612ab995ecf4bbf67"
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
STATE_LABELS = (
    "积雪状态（SNOWPACK）",
    "融雪水状态（MELTWATER）",
    "土壤水状态（SM）",
    "上层蓄水状态（SUZ）",
    "下层蓄水状态（SLZ）",
    "汇流记忆：当日原始出流",
    "汇流记忆：前1日原始出流",
    "汇流记忆：前2日原始出流",
    "汇流记忆：前3日原始出流",
    "汇流记忆：前4日原始出流",
    "汇流记忆：前5日原始出流",
    "汇流记忆：前6日原始出流",
    "汇流记忆：前7日原始出流",
    "汇流记忆：前8日原始出流",
    "汇流记忆：前9日原始出流",
)
PARAMETER_LABELS = {
    "equifinal_diverse_1": "等效异参方案1",
    "trained_center": "校准中心参数",
    "equifinal_diverse_2": "等效异参方案2",
}
PARAMETER_COLORS = {
    "equifinal_diverse_1": "#E69F00",
    "trained_center": "#0072B2",
    "equifinal_diverse_2": "#009E73",
}
LINE_STYLES = {
    "truth": {"color": "#111111", "linewidth": 1.45, "linestyle": "-", "label": "真实状态", "zorder": 5},
    "full": {"color": "#0072B2", "linewidth": 1.15, "linestyle": "-", "label": "同化前进行状态和协方差交互", "zorder": 4},
    "none": {"color": "#E69F00", "linewidth": 1.15, "linestyle": "--", "label": "同化前不进行状态和协方差交互", "zorder": 3},
    "open": {"color": "#8C8C8C", "linewidth": 1.0, "linestyle": (0, (4, 3)), "label": "完全不进行状态更新", "zorder": 2},
}


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def require_absent(paths: list[Path]) -> None:
    existing = [str(path) for path in paths if path.exists()]
    if existing:
        raise FileExistsError("Refusing to overwrite: " + ", ".join(existing))


def segments(parameter_indices: np.ndarray) -> list[tuple[int, int, int]]:
    changes = (np.flatnonzero(parameter_indices[1:] != parameter_indices[:-1]) + 1).tolist()
    starts = [0, *changes]
    ends = [*changes, len(parameter_indices)]
    return [(start, end, int(parameter_indices[start])) for start, end in zip(starts, ends)]


def add_stage_background(axis: plt.Axes, parameter_indices: np.ndarray, parameter_ids: list[str]) -> None:
    for start, end, parameter_index in segments(parameter_indices):
        parameter_id = parameter_ids[parameter_index]
        axis.axvspan(start + 0.5, end + 0.5, color=PARAMETER_COLORS[parameter_id], alpha=0.055, zorder=0)
    for boundary in (180.5, 360.5):
        axis.axvline(boundary, color="#555555", linewidth=0.85, linestyle=":", zorder=1)


def draw_stage_strip(axis: plt.Axes, parameter_indices: np.ndarray, parameter_ids: list[str], trial_number: int) -> None:
    for stage_number, (start, end, parameter_index) in enumerate(segments(parameter_indices), start=1):
        parameter_id = parameter_ids[parameter_index]
        axis.axvspan(start + 0.5, end + 0.5, color=PARAMETER_COLORS[parameter_id], alpha=1.0)
        axis.text(
            (start + end + 1) / 2,
            0.5,
            f"第{stage_number}阶段：第{start + 1}—{end}天\n{PARAMETER_LABELS[parameter_id]}",
            ha="center",
            va="center",
            fontsize=8.8,
            color="white",
            fontweight="bold",
        )
    axis.set_title(f"真实参数排列场景{trial_number}", fontsize=12, fontweight="bold", pad=7)
    axis.set_xlim(0.5, len(parameter_indices) + 0.5)
    axis.set_ylim(0.0, 1.0)
    axis.set_xticks([])
    axis.set_yticks([])
    for spine in axis.spines.values():
        spine.set_visible(False)


def draw_state_lines(
    axis: plt.Axes,
    days: np.ndarray,
    truth: np.ndarray,
    full: np.ndarray,
    none: np.ndarray,
    open_loop: np.ndarray,
    parameter_indices: np.ndarray,
    parameter_ids: list[str],
) -> None:
    add_stage_background(axis, parameter_indices, parameter_ids)
    axis.plot(days, truth, **LINE_STYLES["truth"])
    axis.plot(days, full, **LINE_STYLES["full"])
    axis.plot(days, none, **LINE_STYLES["none"])
    axis.plot(days, open_loop, **LINE_STYLES["open"])
    axis.set_xlim(0.5, len(days) + 0.5)
    axis.set_xticks([1, 90, 180, 270, 360, 450, 540])
    axis.grid(color="#D9D9D9", linewidth=0.45, alpha=0.8)


def padded_limits(values: np.ndarray) -> tuple[float, float]:
    lower = float(np.min(values))
    upper = float(np.max(values))
    padding = max((upper - lower) * 0.04, 1.0e-6)
    return lower - padding, upper + padding


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--state-evidence", type=Path, required=True)
    parser.add_argument("--truth-evidence", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    state_evidence = args.state_evidence.resolve()
    truth_evidence = args.truth_evidence.resolve()
    output_dir = args.output_dir.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    state_hash = sha256_file(state_evidence)
    truth_hash = sha256_file(truth_evidence)
    if state_hash != EXPECTED_STATE_HASH:
        raise RuntimeError(f"State evidence hash mismatch: {state_hash}")
    if truth_hash != EXPECTED_TRUTH_HASH:
        raise RuntimeError(f"Truth evidence hash mismatch: {truth_hash}")

    main_figure_path = output_dir / "five_hydrologic_states_with_true_parameter_stages.png"
    full_figure_paths = [
        output_dir / f"all_15_states_with_true_parameter_stages_trial_{trial}.png"
        for trial in (1, 2, 3)
    ]
    plotted_data_path = output_dir / "plotted_data.npz"
    schedule_path = output_dir / "stage_schedule.csv"
    summary_path = output_dir / "render_summary.json"
    targets = [main_figure_path, *full_figure_paths, plotted_data_path, schedule_path, summary_path]
    require_absent(targets)

    with np.load(state_evidence, allow_pickle=False) as state_source, np.load(truth_evidence, allow_pickle=False) as truth_source:
        state_names = state_source["state_names"].astype(str).tolist()
        if state_names != list(STATE_NAMES):
            raise ValueError(f"Unexpected state ordering: {state_names}")
        method_names = state_source["method_names"].astype(str).tolist()
        expected_methods = [
            "fully_interacting_multiple_model_global_posterior_state",
            "noninteracting_multiple_filter_global_posterior_state_control",
        ]
        if method_names != expected_methods:
            raise ValueError(f"Unexpected state methods: {method_names}")
        truth_method_names = truth_source["method_names"].astype(str).tolist()
        open_loop_index = truth_method_names.index("open_loop")
        assimilation_days = int(truth_source["assimilation_days"])
        if assimilation_days != 540:
            raise ValueError(f"Expected 540 assimilation days, got {assimilation_days}")
        truth_all = state_source["truth_states"].astype(np.float64)
        truth_reference = truth_source["truth_states"][:, :, :assimilation_days, :].astype(np.float64)
        truth_alignment_error = float(np.max(np.abs(truth_all - truth_reference)))
        if truth_alignment_error != 0.0:
            raise ValueError(f"Truth-state evidence files are not exactly aligned: {truth_alignment_error}")
        posteriors = state_source["global_posterior_states"].astype(np.float64)
        open_loop_all = truth_source["method_assimilation_states"][:, :, open_loop_index, :assimilation_days, :].astype(np.float64)
        parameter_ids = truth_source["parameter_ids"].astype(str).tolist()
        parameter_indices = truth_source["truth_parameter_indices"][:, :assimilation_days].astype(np.int64)
        registered_block_id = str(truth_source["block_ids"][0])

    if posteriors.shape != (8, 3, 2, 540, 15) or open_loop_all.shape != (8, 3, 540, 15):
        raise ValueError("State arrays have unexpected shapes")
    if not all(np.all(np.isfinite(array)) for array in (truth_all, posteriors, open_loop_all)):
        raise ValueError("State arrays contain non-finite values")
    for row in parameter_indices:
        switches = (np.flatnonzero(row[1:] != row[:-1]) + 1).tolist()
        if switches != [180, 360]:
            raise ValueError(f"Unexpected true-parameter switch indices {switches}")

    block = 0
    truth = truth_all[block]
    full = posteriors[block, :, 0]
    none = posteriors[block, :, 1]
    open_loop = open_loop_all[block]
    if plotted_data_path.exists():
        raise FileExistsError(f"Refusing to overwrite {plotted_data_path}")
    np.savez_compressed(
        plotted_data_path,
        registered_block_id=np.asarray(registered_block_id),
        state_names=np.asarray(STATE_NAMES),
        parameter_ids=np.asarray(parameter_ids),
        parameter_indices=parameter_indices,
        truth_states=truth,
        full_interaction_states=full,
        no_interaction_states=none,
        open_loop_states=open_loop,
    )

    with schedule_path.open("x", newline="", encoding="utf-8-sig") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=("truth_trial", "stage", "start_day", "end_day", "parameter_id", "parameter_label"),
        )
        writer.writeheader()
        for trial_index in range(3):
            for stage_number, (start, end, parameter_index) in enumerate(segments(parameter_indices[trial_index]), start=1):
                parameter_id = parameter_ids[parameter_index]
                writer.writerow(
                    {
                        "truth_trial": trial_index + 1,
                        "stage": stage_number,
                        "start_day": start + 1,
                        "end_day": end,
                        "parameter_id": parameter_id,
                        "parameter_label": PARAMETER_LABELS[parameter_id],
                    }
                )

    plt.rcParams.update(
        {
            "font.family": "sans-serif",
            "font.sans-serif": ["Microsoft YaHei", "DejaVu Sans"],
            "axes.unicode_minus": False,
            "axes.spines.top": False,
            "axes.spines.right": False,
            "xtick.labelsize": 8,
            "ytick.labelsize": 8,
        }
    )
    days = np.arange(1, assimilation_days + 1)

    figure = plt.figure(figsize=(22, 19))
    grid = figure.add_gridspec(6, 3, height_ratios=[0.55, 1, 1, 1, 1, 1], hspace=0.11, wspace=0.12)
    axes: list[list[plt.Axes]] = []
    for trial_index in range(3):
        stage_axis = figure.add_subplot(grid[0, trial_index])
        draw_stage_strip(stage_axis, parameter_indices[trial_index], parameter_ids, trial_index + 1)
        column_axes: list[plt.Axes] = []
        for state_index in range(5):
            axis = figure.add_subplot(grid[state_index + 1, trial_index])
            draw_state_lines(
                axis,
                days,
                truth[trial_index, :, state_index],
                full[trial_index, :, state_index],
                none[trial_index, :, state_index],
                open_loop[trial_index, :, state_index],
                parameter_indices[trial_index],
                parameter_ids,
            )
            comparison_values = np.concatenate(
                (
                    truth[:, :, state_index].ravel(),
                    full[:, :, state_index].ravel(),
                    none[:, :, state_index].ravel(),
                    open_loop[:, :, state_index].ravel(),
                )
            )
            axis.set_ylim(*padded_limits(comparison_values))
            if trial_index == 0:
                axis.set_ylabel(STATE_LABELS[state_index], fontsize=9, fontweight="bold")
            if state_index < 4:
                axis.tick_params(axis="x", labelbottom=False)
            else:
                axis.set_xlabel("同化时间（日）")
            column_axes.append(axis)
        axes.append(column_axes)

    handles = [plt.Line2D([], [], **LINE_STYLES[key]) for key in ("truth", "full", "none", "open")]
    figure.legend(handles=handles, labels=[handle.get_label() for handle in handles], loc="upper center", ncol=4, frameon=False, bbox_to_anchor=(0.5, 0.965), fontsize=9)
    figure.suptitle(
        "状态更新轨迹叠加三段真实参数（第一个预先登记区块，无跨区块汇总）\n"
        "彩色背景和顶部参数条表示生成真实状态与观测流量所使用的真实参数；虚线边界位于第180—181天和第360—361天之间",
        fontsize=16,
        fontweight="bold",
        y=0.995,
    )
    figure.text(0.01, 0.006, f"状态证据SHA-256：{state_hash} | 真值证据SHA-256：{truth_hash}", fontsize=7)
    figure.savefig(main_figure_path, dpi=220, bbox_inches="tight", facecolor="white")
    plt.close(figure)

    for trial_index, full_figure_path in enumerate(full_figure_paths):
        figure = plt.figure(figsize=(21, 18))
        grid = figure.add_gridspec(6, 3, height_ratios=[0.55, 1, 1, 1, 1, 1], hspace=0.24, wspace=0.18)
        stage_axis = figure.add_subplot(grid[0, :])
        draw_stage_strip(stage_axis, parameter_indices[trial_index], parameter_ids, trial_index + 1)
        for state_index in range(15):
            row = state_index // 3 + 1
            column = state_index % 3
            axis = figure.add_subplot(grid[row, column])
            draw_state_lines(
                axis,
                days,
                truth[trial_index, :, state_index],
                full[trial_index, :, state_index],
                none[trial_index, :, state_index],
                open_loop[trial_index, :, state_index],
                parameter_indices[trial_index],
                parameter_ids,
            )
            values = np.concatenate(
                (
                    truth[trial_index, :, state_index],
                    full[trial_index, :, state_index],
                    none[trial_index, :, state_index],
                    open_loop[trial_index, :, state_index],
                )
            )
            axis.set_ylim(*padded_limits(values))
            axis.set_title(STATE_LABELS[state_index], fontsize=9, fontweight="bold")
            if row < 5:
                axis.tick_params(axis="x", labelbottom=False)
            else:
                axis.set_xlabel("同化时间（日）", fontsize=8)
        handles = [plt.Line2D([], [], **LINE_STYLES[key]) for key in ("truth", "full", "none", "open")]
        figure.legend(handles=handles, labels=[handle.get_label() for handle in handles], loc="upper center", ncol=4, frameon=False, bbox_to_anchor=(0.5, 0.965), fontsize=9)
        figure.suptitle(
            f"全部15个状态叠加三段真实参数：真实参数排列场景{trial_index + 1}\n"
            "第一个预先登记区块；未平滑、未取中位数、未跨区块汇总",
            fontsize=16,
            fontweight="bold",
            y=0.995,
        )
        figure.text(0.01, 0.006, f"状态证据SHA-256：{state_hash} | 真值证据SHA-256：{truth_hash}", fontsize=7)
        figure.savefig(full_figure_path, dpi=220, bbox_inches="tight", facecolor="white")
        plt.close(figure)

    summary = {
        "audit_id": AUDIT_ID,
        "status": "rendered",
        "state_evidence": str(state_evidence),
        "state_evidence_sha256": state_hash,
        "truth_evidence": str(truth_evidence),
        "truth_evidence_sha256": truth_hash,
        "registered_block_index_zero_based": block,
        "registered_block_id": registered_block_id,
        "truth_alignment_maximum_absolute_error": truth_alignment_error,
        "assimilation_days": assimilation_days,
        "state_count": 15,
        "switch_boundaries_between_days": [180, 360],
        "aggregation": "none",
        "forecast_run": False,
        "outputs": [str(path) for path in targets if path != summary_path],
    }
    with summary_path.open("x", encoding="utf-8") as handle:
        json.dump(summary, handle, ensure_ascii=False, indent=2)
        handle.write("\n")


if __name__ == "__main__":
    main()

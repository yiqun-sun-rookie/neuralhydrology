"""Render an annotated true-target readout without changing sealed evidence."""

from __future__ import annotations

import hashlib
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from uuid import uuid4

import matplotlib
import matplotlib.image as matplotlib_image
import numpy as np


matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402


PROJECT_ROOT = Path(__file__).resolve().parents[3]
SRC_ROOT = PROJECT_ROOT / "src"
if str(SRC_ROOT) not in sys.path:
    sys.path.insert(0, str(SRC_ROOT))

from hbv_multilead_joint_uncertainty.state_domain_consistent_process_noise_switch import (  # noqa: E402
    build_probability_response_curves,
)


READOUT_ID = "g3_state_domain_consistent_process_noise_switch_v01_true_target_readout_v01"
SOURCE_RESULT = (
    PROJECT_ROOT
    / "results/23_hbv_multilead_joint_uncertainty"
    / "g3_state_domain_consistent_process_noise_switch_v01"
)
OUTPUT = (
    PROJECT_ROOT
    / "results/23_hbv_multilead_joint_uncertainty"
    / READOUT_ID
)
PROCESS_IDS = (
    "lower_groundwater_low",
    "lower_groundwater_medium",
    "lower_groundwater_high",
)
COLORS = {
    PROCESS_IDS[0]: "#0072B2",
    PROCESS_IDS[1]: "#E69F00",
    PROCESS_IDS[2]: "#009E73",
}
NAMES = {
    PROCESS_IDS[0]: "低噪声（蓝）",
    PROCESS_IDS[1]: "中噪声（橙）",
    PROCESS_IDS[2]: "高噪声（绿）",
}
TRANSITIONS = (
    (PROCESS_IDS[0], PROCESS_IDS[1]),
    (PROCESS_IDS[1], PROCESS_IDS[2]),
    (PROCESS_IDS[2], PROCESS_IDS[0]),
)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _transition_label(old_process_id: str, new_process_id: str) -> str:
    return f"{old_process_id}_to_{new_process_id}"


def _candidate_curve(rows: list[dict], transition: str, candidate: str):
    selected = sorted(
        (
            row
            for row in rows
            if row["transition_label"] == transition
            and row["candidate_process_id"] == candidate
        ),
        key=lambda row: row["relative_day"],
    )
    return (
        np.asarray([row["relative_day"] for row in selected], dtype=float),
        np.asarray([row["probability_p10"] for row in selected]),
        np.asarray([row["probability_median"] for row in selected]),
        np.asarray([row["probability_p90"] for row in selected]),
    )


def _set_fonts() -> None:
    matplotlib.rcParams["font.sans-serif"] = [
        "Microsoft YaHei",
        "SimHei",
        "Arial Unicode MS",
        "DejaVu Sans",
    ]
    matplotlib.rcParams["axes.unicode_minus"] = False


def _plot_all_transitions(
    rows: list[dict],
    summaries: list[dict],
    output_path: Path,
) -> None:
    _set_fonts()
    summary_by_transition = {
        row["transition_label"]: row for row in summaries
    }
    fig, axes = plt.subplots(3, 1, figsize=(11.5, 11.8), sharex=True)
    for axis, (old_process_id, new_process_id) in zip(axes, TRANSITIONS):
        transition = _transition_label(old_process_id, new_process_id)
        axis.axvspan(
            -15, 0, color=COLORS[old_process_id], alpha=0.055, zorder=0
        )
        axis.axvspan(
            0, 29, color=COLORS[new_process_id], alpha=0.085, zorder=0
        )
        curves = {}
        for candidate in PROCESS_IDS:
            x, p10, median, p90 = _candidate_curve(
                rows, transition, candidate
            )
            curves[candidate] = (x, median)
            axis.fill_between(
                x,
                p10,
                p90,
                color=COLORS[candidate],
                alpha=0.11,
                linewidth=0.0,
            )
            axis.plot(
                x,
                median,
                color=COLORS[candidate],
                linewidth=1.7,
                alpha=0.72,
                label=NAMES[candidate],
            )
        old_x, old_median = curves[old_process_id]
        new_x, new_median = curves[new_process_id]
        before = old_x < 0
        after = new_x >= 0
        axis.plot(
            old_x[before],
            old_median[before],
            color=COLORS[old_process_id],
            linewidth=4.0,
            label="切换前真实候选",
        )
        axis.plot(
            new_x[after],
            new_median[after],
            color=COLORS[new_process_id],
            linewidth=4.0,
            label="切换后真实候选",
        )
        axis.axvline(0, color="#222222", linestyle="--", linewidth=1.4)
        axis.text(
            0.23,
            1.02,
            f"切换前真值：{NAMES[old_process_id]}\n粗线应当占优",
            transform=axis.transAxes,
            ha="center",
            va="bottom",
            fontsize=10.5,
            bbox={
                "boxstyle": "round,pad=0.30",
                "facecolor": "white",
                "edgecolor": COLORS[old_process_id],
                "linewidth": 1.8,
            },
        )
        axis.text(
            0.76,
            1.02,
            f"切换后真值：{NAMES[new_process_id]}\n看这条粗线是否升为主导",
            transform=axis.transAxes,
            ha="center",
            va="bottom",
            fontsize=10.5,
            bbox={
                "boxstyle": "round,pad=0.30",
                "facecolor": "white",
                "edgecolor": COLORS[new_process_id],
                "linewidth": 1.8,
            },
        )
        summary = summary_by_transition[transition]
        status = "通过" if summary["criterion_passed"] else "未通过"
        axis.text(
            0.985,
            0.055,
            f"切换后真值：{NAMES[new_process_id]}\n"
            f"成功 {summary['successful_event_count']}/{summary['event_count']}，{status}",
            transform=axis.transAxes,
            ha="right",
            va="bottom",
            fontsize=10.5,
            bbox={
                "boxstyle": "round,pad=0.35",
                "facecolor": "white",
                "edgecolor": COLORS[new_process_id],
                "alpha": 0.94,
            },
        )
        axis.set_ylim(0.0, 1.0)
        axis.set_ylabel("后验概率")
        axis.grid(alpha=0.22)
    handles, labels = axes[0].get_legend_handles_labels()
    unique = dict(zip(labels[:3], handles[:3]))
    axes[0].legend(
        unique.values(), unique.keys(), ncol=3, loc="upper right"
    )
    axes[-1].set_xlabel("相对切换日（0 为新真实噪声开始）")
    fig.suptitle(
        "真实噪声候选已直接标在图上：粗线段就是当时应该跟随的真值",
        fontsize=15,
    )
    fig.tight_layout(rect=(0.0, 0.0, 1.0, 0.965), h_pad=3.0)
    fig.savefig(output_path, dpi=190, bbox_inches="tight")
    plt.close(fig)


def _plot_green_follow_zoom(
    rows: list[dict],
    summaries: list[dict],
    output_path: Path,
) -> None:
    _set_fonts()
    old_process_id = PROCESS_IDS[1]
    new_process_id = PROCESS_IDS[2]
    transition = _transition_label(old_process_id, new_process_id)
    summary = next(
        row for row in summaries if row["transition_label"] == transition
    )
    fig, axis = plt.subplots(figsize=(11.0, 6.4))
    axis.axvspan(
        -15, 0, color=COLORS[old_process_id], alpha=0.06, zorder=0
    )
    axis.axvspan(
        0, 29, color=COLORS[new_process_id], alpha=0.10, zorder=0
    )
    curves = {}
    for candidate in PROCESS_IDS:
        x, p10, median, p90 = _candidate_curve(rows, transition, candidate)
        curves[candidate] = (x, median)
        axis.fill_between(
            x, p10, p90, color=COLORS[candidate], alpha=0.12
        )
        axis.plot(
            x,
            median,
            color=COLORS[candidate],
            linewidth=2.2,
            alpha=0.78,
            label=NAMES[candidate],
        )
    old_x, old_median = curves[old_process_id]
    new_x, new_median = curves[new_process_id]
    axis.plot(
        old_x[old_x < 0],
        old_median[old_x < 0],
        color=COLORS[old_process_id],
        linewidth=4.8,
    )
    axis.plot(
        new_x[new_x >= 0],
        new_median[new_x >= 0],
        color=COLORS[new_process_id],
        linewidth=4.8,
    )
    axis.axvline(0, color="#222222", linestyle="--", linewidth=1.5)
    point_day = 9
    point_index = int(np.flatnonzero(new_x == point_day)[0])
    axis.annotate(
        "切换后真实应为高噪声：看绿色粗线\n绿色在切换后上升并成为最高概率",
        xy=(point_day, new_median[point_index]),
        xytext=(14.5, 0.60),
        arrowprops={
            "arrowstyle": "->",
            "color": COLORS[new_process_id],
            "linewidth": 2.0,
        },
        fontsize=12,
        bbox={
            "boxstyle": "round,pad=0.40",
            "facecolor": "white",
            "edgecolor": COLORS[new_process_id],
        },
    )
    axis.text(
        -7.5,
        0.96,
        "切换前真实：中噪声（橙）",
        ha="center",
        va="top",
        fontsize=12,
        weight="bold",
        color="#8A5A00",
    )
    axis.text(
        14.5,
        0.96,
        "切换后真实：高噪声（绿）",
        ha="center",
        va="top",
        fontsize=12,
        weight="bold",
        color="#006A4E",
    )
    axis.text(
        0.98,
        0.06,
        f"16 个事件中成功 {summary['successful_event_count']} 个\n"
        f"响应开始日中位数 {summary['median_response_start_day']}",
        transform=axis.transAxes,
        ha="right",
        va="bottom",
        fontsize=11.5,
        bbox={
            "boxstyle": "round,pad=0.38",
            "facecolor": "white",
            "edgecolor": COLORS[new_process_id],
        },
    )
    axis.set_xlim(-15, 29)
    axis.set_ylim(0.0, 1.0)
    axis.set_xlabel("相对切换日（0 为高噪声真值开始）")
    axis.set_ylabel("后验概率")
    axis.set_title("绿色高噪声候选有没有跟过去？——中噪声切换到高噪声的放大图")
    axis.grid(alpha=0.22)
    axis.legend(ncol=3, loc="upper center", bbox_to_anchor=(0.5, -0.13))
    fig.tight_layout()
    fig.savefig(output_path, dpi=190, bbox_inches="tight")
    plt.close(fig)


def _decode(path: Path) -> None:
    image = matplotlib_image.imread(path)
    if image.size == 0 or image.ndim not in (2, 3) or not np.all(
        np.isfinite(image)
    ):
        raise ValueError(f"cannot decode generated figure: {path}")


def main() -> None:
    if OUTPUT.exists():
        raise FileExistsError(f"readout output already exists: {OUTPUT}")
    evidence_path = SOURCE_RESULT / "evidence.npz"
    summary_path = SOURCE_RESULT / "summary.json"
    with np.load(evidence_path, allow_pickle=False) as archive:
        probabilities = archive["posterior_probabilities"]
        schedule = archive["process_schedule"]
        process_ids = archive["process_ids"]
    if tuple(process_ids.astype(str)) != PROCESS_IDS:
        raise ValueError("sealed process identifiers do not match the readout")
    summary = json.loads(summary_path.read_text(encoding="utf-8"))
    response_summaries = summary["directed_transition_results"]
    rows = build_probability_response_curves(
        probabilities, schedule, process_ids
    )

    staging = OUTPUT.with_name(f"{OUTPUT.name}.incomplete.{uuid4().hex}")
    staging.mkdir(parents=False)
    all_path = staging / "true_target_annotated_probability_response.png"
    green_path = staging / "medium_to_high_green_follow_zoom.png"
    _plot_all_transitions(rows, response_summaries, all_path)
    _plot_green_follow_zoom(rows, response_summaries, green_path)
    _decode(all_path)
    _decode(green_path)
    metadata = {
        "readout_id": READOUT_ID,
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "source_result": str(SOURCE_RESULT),
        "source_evidence_sha256": _sha256(evidence_path),
        "source_summary_sha256": _sha256(summary_path),
        "experiment_rerun": False,
        "sealed_result_modified": False,
        "visual_contract": {
            "background_before_switch": "old true candidate colour",
            "background_after_switch": "new true candidate colour",
            "thick_line_before_switch": "old true candidate",
            "thick_line_after_switch": "new true candidate",
        },
        "outputs": [all_path.name, green_path.name],
    }
    metadata_path = staging / "readout_metadata.json"
    metadata_path.write_text(
        json.dumps(metadata, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    checksums = {
        path.name: _sha256(path)
        for path in (all_path, green_path, metadata_path)
    }
    (staging / "checksums.json").write_text(
        json.dumps(checksums, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    staging.rename(OUTPUT)
    print(json.dumps(metadata, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()

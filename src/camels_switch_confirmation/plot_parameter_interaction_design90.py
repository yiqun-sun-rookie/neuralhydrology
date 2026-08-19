"""Plot the verified Design90 true-candidate probability trajectories."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd


ARM_STYLE = {
    "A": ("A  旧方法：候选状态不交互", "#5B5B5B"),
    "B": ("B  完整状态交互 + 旧式裁剪", "#D55E00"),
    "C": ("C  完整状态交互 + 物理守恒转换", "#0072B2"),
}
TRUTH_FACTOR = {0: 1.0, 1: 0.5, 2: 2.0}
TRUTH_LABEL = {0: "中心 1.0×", 1: "一半 0.5×", 2: "两倍 2.0×"}


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _load_arm(directory: Path, expected_files: int):
    paths = sorted(directory.glob("*.npz"))
    if len(paths) != expected_files:
        raise ValueError(
            f"expected {expected_files} files in {directory}, got {len(paths)}"
        )
    values = []
    reference_truth = None
    reference_rotation = None
    reference_stage_days = None
    for path in paths:
        with np.load(path, allow_pickle=False) as arrays:
            probabilities = np.asarray(arrays["probabilities"], dtype=np.float64)
            truth = np.asarray(arrays["true_candidate_indices"], dtype=np.int64)
            rotation = np.asarray(arrays["rotation"], dtype=np.int64)
            stage_days = int(arrays["stage_days"].item())
        if probabilities.shape != (1260, 3) or truth.shape != (1260,):
            raise ValueError(f"unexpected probability shape in {path}")
        if not np.all(np.isfinite(probabilities)):
            raise ValueError(f"non-finite probability in {path}")
        if np.max(np.abs(probabilities.sum(axis=1) - 1.0)) > 1e-12:
            raise ValueError(f"non-normalized probability in {path}")
        if reference_truth is None:
            reference_truth = truth.copy()
            reference_rotation = rotation.copy()
            reference_stage_days = stage_days
        elif (
            not np.array_equal(truth, reference_truth)
            or not np.array_equal(rotation, reference_rotation)
            or stage_days != reference_stage_days
        ):
            raise ValueError("truth schedule differs within an arm")
        values.append(probabilities[np.arange(len(truth)), truth])
    return np.asarray(values), reference_rotation, reference_stage_days, paths


def create_figure(output_root: str | Path) -> dict:
    root = Path(output_root).resolve()
    verification = root / "verification"
    report_path = verification / "comparison_summary.json"
    report = json.loads(report_path.read_text(encoding="utf-8"))
    if report.get("verification_status") != "passed":
        raise ValueError("independent verification has not passed")
    if report.get("task_count") != 540 or report.get("registered_basin_count") != 90:
        raise ValueError("this plot requires the verified 90-basin, 540-task design")

    figure_path = verification / "probability_trajectory_comparison_design90.png"
    csv_path = verification / "probability_trajectory_summary_design90.csv"
    manifest_path = verification / "probability_trajectory_figure_design90.json"
    for path in (figure_path, csv_path, manifest_path):
        if path.exists():
            raise FileExistsError(f"refusing to overwrite {path}")

    per_arm_tasks = report["task_count"] // 3
    matrices = {}
    probability_paths = []
    common_rotation = None
    common_stage_days = None
    rows = []
    for arm_id in ("A", "B", "C"):
        matrix, rotation, stage_days, paths = _load_arm(
            root / "arms" / arm_id / "probs", per_arm_tasks
        )
        if common_rotation is None:
            common_rotation = rotation
            common_stage_days = stage_days
        elif not np.array_equal(rotation, common_rotation) or stage_days != common_stage_days:
            raise ValueError("truth schedule differs across arms")
        matrices[arm_id] = matrix
        probability_paths.extend(paths)
        for day in range(matrix.shape[1]):
            daily = matrix[:, day]
            rows.append(
                {
                    "arm_id": arm_id,
                    "day": day + 1,
                    "stage": day // stage_days + 1,
                    "true_member": int(common_rotation[day // stage_days]),
                    "median_true_probability": float(np.median(daily)),
                    "q25_true_probability": float(np.quantile(daily, 0.25)),
                    "q75_true_probability": float(np.quantile(daily, 0.75)),
                }
            )
    pd.DataFrame(rows).to_csv(csv_path, index=False)

    plt.rcParams["font.sans-serif"] = [
        "Microsoft YaHei",
        "SimHei",
        "Arial Unicode MS",
        "DejaVu Sans",
    ]
    plt.rcParams["axes.unicode_minus"] = False
    fig, all_axes = plt.subplots(
        4,
        1,
        figsize=(15, 10.4),
        sharex=True,
        gridspec_kw={"height_ratios": [0.78, 2.2, 2.2, 2.2]},
    )
    truth_axis = all_axes[0]
    method_axes = all_axes[1:]
    x = np.arange(1, 1261)
    truth_line = np.repeat(
        [TRUTH_FACTOR[int(member)] for member in common_rotation],
        common_stage_days,
    )
    truth_axis.step(
        x,
        truth_line,
        where="post",
        color="#A5005A",
        linewidth=3.2,
        label="预设真实参数（不是方法）",
    )
    for stage_index, member in enumerate(common_rotation):
        start = stage_index * common_stage_days + 1
        end = (stage_index + 1) * common_stage_days
        midpoint = (start + end) / 2
        factor = TRUTH_FACTOR[int(member)]
        offset = -0.22 if factor == 2.0 else 0.16
        truth_axis.text(
            midpoint,
            factor + offset,
            TRUTH_LABEL[int(member)],
            ha="center",
            va="center",
            fontsize=9,
            fontweight="bold",
            color="#5A0031",
        )
        if stage_index:
            truth_axis.axvline(start, color="#666666", linestyle="--", linewidth=0.8)
    truth_axis.set_ylim(0.28, 2.28)
    truth_axis.set_yticks([0.5, 1.0, 2.0])
    truth_axis.set_ylabel("预设真实值\n容量倍数")
    truth_axis.set_title(
        "七阶段预设真实参数：中心 → 一半 → 两倍 → 中心 → 两倍 → 一半 → 中心",
        loc="left",
        fontsize=11,
        fontweight="bold",
    )
    truth_axis.legend(loc="upper right", frameon=False, fontsize=9)
    truth_axis.grid(axis="y", color="#D8D8D8", linewidth=0.6)

    arm_summary = {row["arm_id"]: row for row in report["arm_summary"]}
    for axis, arm_id in zip(method_axes, ("A", "B", "C")):
        title, color = ARM_STYLE[arm_id]
        matrix = matrices[arm_id]
        median = np.median(matrix, axis=0)
        lower = np.quantile(matrix, 0.25, axis=0)
        upper = np.quantile(matrix, 0.75, axis=0)
        for stage_index in range(len(common_rotation)):
            start = stage_index * common_stage_days + 1
            if stage_index:
                axis.axvline(start, color="#666666", linestyle="--", linewidth=0.8)
                axis.axvspan(start, start + 29, color="#BDBDBD", alpha=0.12)
        axis.fill_between(x, lower, upper, color=color, alpha=0.20, linewidth=0)
        axis.plot(x, median, color=color, linewidth=1.35)
        axis.axhline(0.5, color="#222222", linestyle=":", linewidth=0.9)
        axis.set_ylim(0.0, 1.0)
        axis.set_yticks(np.linspace(0.0, 1.0, 6))
        axis.set_ylabel("真实候选\n概率")
        axis.set_title(title, loc="left", fontsize=11, fontweight="bold")
        axis.grid(axis="y", color="#D8D8D8", linewidth=0.6)
        metrics = arm_summary[arm_id]
        rate = metrics["events_passed"] / 1080
        metric_text = (
            f"事件通过率 {rate:.2%}   "
            f"布里尔分数 {metrics['multiclass_brier']:.3f}"
        )
        if arm_id == "C":
            metric_text += "   典型走势最好，但概率校准 HOLD"
        axis.text(
            0.995,
            0.94,
            metric_text,
            transform=axis.transAxes,
            ha="right",
            va="top",
            fontsize=9,
            fontweight="bold" if arm_id == "C" else "normal",
            color="#8B0000" if arm_id == "C" else "#222222",
            bbox={"facecolor": "white", "edgecolor": "none", "alpha": 0.82},
        )

    method_axes[-1].set_xlabel("模拟日；灰色区域为每次切换后的 30 天响应窗口")
    fig.suptitle(
        "CAMELS-US 土壤最大蓄水容量切换：90 个流域 × 2 个设计种子",
        fontsize=14,
        fontweight="bold",
        y=0.995,
    )
    fig.text(
        0.5,
        0.958,
        "洋红色阶梯线是预设真实参数；A、B、C 才是待比较方法。曲线为 180 个任务的每日中位数，阴影为四分位范围。",
        ha="center",
        fontsize=10,
        fontweight="bold",
    )
    fig.text(
        0.5,
        0.012,
        "探索性设计种子 0、1。C 的典型概率轨迹最佳，但少数极端自信错误使预注册概率校准门槛未通过。",
        ha="center",
        fontsize=9,
        color="#444444",
    )
    fig.tight_layout(rect=(0.045, 0.045, 0.995, 0.94))
    fig.savefig(figure_path, dpi=190, bbox_inches="tight")
    plt.close(fig)

    collection = hashlib.sha256()
    for path in sorted(probability_paths):
        collection.update(path.relative_to(root).as_posix().encode("utf-8"))
        collection.update(b"\0")
        collection.update(_sha256(path).encode("ascii"))
        collection.update(b"\n")
    manifest = {
        "experiment_id": report["experiment_id"],
        "verification_status": report["verification_status"],
        "scope": "descriptive Design90 true-candidate probability trajectories",
        "tasks_per_arm": per_arm_tasks,
        "probability_file_count": len(probability_paths),
        "probability_file_set_sha256": collection.hexdigest(),
        "verification_summary_sha256": _sha256(report_path),
        "summary_csv": csv_path.name,
        "summary_csv_sha256": _sha256(csv_path),
        "figure": figure_path.name,
        "figure_sha256": _sha256(figure_path),
        "plot_script": Path(__file__).resolve().as_posix(),
        "plot_script_sha256": _sha256(Path(__file__).resolve()),
    }
    manifest_path.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return manifest


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-root", required=True)
    arguments = parser.parse_args(argv)
    print(json.dumps(create_figure(arguments.output_root), indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

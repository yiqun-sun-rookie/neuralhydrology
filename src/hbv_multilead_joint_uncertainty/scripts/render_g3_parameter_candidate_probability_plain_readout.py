"""Render plain-language parameter-scheme readouts from sealed G3 evidence.

This script is readout-only. It never changes the sealed experiment and refuses
to write into an existing output directory.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
from uuid import uuid4

import matplotlib
import matplotlib.image as matplotlib_image
import numpy as np

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
from matplotlib.patches import Patch  # noqa: E402


PROJECT_ROOT = Path(__file__).resolve().parents[3]
SOURCE_RESULT = (
    PROJECT_ROOT
    / "results/23_hbv_multilead_joint_uncertainty/g3_ideal_gate_param_switch_v01"
)
DEFAULT_OUTPUT = SOURCE_RESULT.with_name(
    "g3_ideal_gate_param_switch_v01_candidate_probability_plain_readout_v01"
)

EXPECTED_HASHES = {
    "evidence.npz": "77f84d793f18a72972e5af5f2ac4ed767645471e37da31c612ab995ecf4bbf67",
    "parameter_vectors.csv": "6c3080099ba1dce0e2ef0411fc585282f70760e9955c1c49f7b9c9892d8fa925",
    "config_snapshot.json": "435fc07dd68bc1a3de06b402824047189e52606372073827198cdb7d50392e0c",
    "summary.json": "74f77da08a1904fb33808bb4f6da308ca151d736cbcfe05dcfbbd8a3071236f7",
}

# The letters are deliberately neutral. They replace misleading internal IDs in
# the reader-facing figures while preserving the exact sealed vectors.
PARAMETER_ID_BY_SCHEME = {
    "A": "trained_center",
    "B": "equifinal_diverse_2",
    "C": "equifinal_diverse_1",
}
SCHEME_BY_PARAMETER_ID = {value: key for key, value in PARAMETER_ID_BY_SCHEME.items()}
SCHEME_ORDER = ("A", "B", "C")
SCHEME_COLORS = {
    "A": "#0072B2",
    "B": "#D55E00",
    "C": "#009E73",
}
METHODS = (
    ("parameter_only", "只让三套参数竞争\n（过程噪声固定）", 2),
    (
        "joint_parameter_marginal",
        "参数和过程噪声同时竞争\n（同一参数的三种噪声概率已相加）",
        4,
    ),
)
TRANSITIONS = (("A", "B"), ("B", "C"), ("C", "A"))

PARAMETER_DEFINITIONS = (
    ("parTT", "雨雪与融雪温度阈值", "摄氏度", 3),
    ("parCFMAX", "融雪度日因子", "毫米/(摄氏度·日)", 3),
    ("parCFR", "再冻结系数", "无量纲", 4),
    ("parCWH", "积雪持水比例", "无量纲", 5),
    ("parFC", "土壤最大蓄水容量", "毫米", 1),
    ("parBETA", "土壤产流非线性指数", "无量纲", 3),
    ("parLP", "蒸散达到潜在值的土壤湿度比例阈值", "无量纲", 3),
    ("parK0", "超阈值快速径流退水系数", "每日", 4),
    ("parK1", "上层水库退水系数", "每日", 4),
    ("parUZL", "快速径流启动的上层水库阈值", "毫米", 2),
    ("parPERC", "上层向下层最大渗漏量", "毫米/日", 3),
    ("parK2", "下层水库退水系数", "每日", 5),
    ("lag_time", "汇流滞后时间", "日", 3),
)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _verify_sources() -> tuple[dict, dict]:
    for filename, expected in EXPECTED_HASHES.items():
        actual = _sha256(SOURCE_RESULT / filename)
        if actual != expected:
            raise ValueError(f"sealed source hash changed for {filename}: {actual}")
    config = json.loads((SOURCE_RESULT / "config_snapshot.json").read_text(encoding="utf-8"))
    summary = json.loads((SOURCE_RESULT / "summary.json").read_text(encoding="utf-8"))
    if float(config["g3_ideal_gate"]["spacing_multiplier"]) != 8.0:
        raise ValueError("sealed spacing multiplier is no longer 8")
    if config["parameter_source"]["parameter_ids"] != [
        "equifinal_diverse_1",
        "trained_center",
        "equifinal_diverse_2",
    ]:
        raise ValueError("sealed parameter identifiers changed")
    if summary.get("scientific_status") != "not_passed":
        raise ValueError("sealed scientific status changed")
    return config, summary


def _load_parameter_values() -> dict[str, dict[str, float]]:
    rows = list(csv.DictReader((SOURCE_RESULT / "parameter_vectors.csv").open(encoding="utf-8")))
    by_id = {row["parameter_id"]: row for row in rows}
    if set(by_id) != set(PARAMETER_ID_BY_SCHEME.values()) or len(rows) != 3:
        raise ValueError("sealed parameter table does not contain the expected three vectors")
    values: dict[str, dict[str, float]] = {}
    for scheme in SCHEME_ORDER:
        row = by_id[PARAMETER_ID_BY_SCHEME[scheme]]
        values[scheme] = {}
        for parameter_name, _, _, _ in PARAMETER_DEFINITIONS:
            value = float(row[parameter_name])
            if not np.isfinite(value):
                raise ValueError(f"non-finite parameter {parameter_name} in scheme {scheme}")
            values[scheme][parameter_name] = value
    return values


def _extract_method_probabilities(probabilities: np.ndarray, method_index: int) -> np.ndarray:
    values = probabilities[:, :, method_index]
    if method_index == 2:
        values = values[..., :3]
    elif method_index == 4:
        values = values[..., :9].reshape(8, 3, 540, 3, 3).sum(axis=-1)
    else:
        raise ValueError("unsupported frozen method index")
    if values.shape != (8, 3, 540, 3):
        raise ValueError(f"unexpected method probability shape: {values.shape}")
    if not np.allclose(values.sum(axis=-1), 1.0, rtol=0.0, atol=1e-12):
        raise ValueError("parameter probabilities do not sum to one")
    return values


def _collect_transition_events(
    method_values: np.ndarray,
    schedule: np.ndarray,
    parameter_ids: np.ndarray,
) -> dict[tuple[str, str], np.ndarray]:
    collected: dict[tuple[str, str], list[np.ndarray]] = {transition: [] for transition in TRANSITIONS}
    for boundary in (180, 360):
        for truth_trial in range(schedule.shape[0]):
            old_id = str(parameter_ids[int(schedule[truth_trial, boundary - 1])])
            new_id = str(parameter_ids[int(schedule[truth_trial, boundary])])
            transition = (SCHEME_BY_PARAMETER_ID[old_id], SCHEME_BY_PARAMETER_ID[new_id])
            if transition not in collected:
                raise ValueError(f"unexpected directed transition: {transition}")
            for block in range(method_values.shape[0]):
                collected[transition].append(
                    method_values[block, truth_trial, boundary : boundary + 180].copy()
                )
    packed = {transition: np.stack(events) for transition, events in collected.items()}
    for transition, events in packed.items():
        if events.shape != (16, 180, 3):
            raise ValueError(f"unexpected event shape for {transition}: {events.shape}")
    return packed


def _summarize(events: np.ndarray, true_parameter_index: int) -> dict[str, float | int]:
    evaluated = events[:, 5:]
    true_probability = evaluated[..., true_parameter_index]
    correct = np.argmax(evaluated, axis=-1) == true_parameter_index
    event_coverage = correct.mean(axis=1)
    return {
        "evaluated_probability_count": int(true_probability.size),
        "true_scheme_argmax_coverage": float(correct.mean()),
        "true_scheme_probability_above_half_coverage": float((true_probability > 0.5).mean()),
        "true_scheme_probability_p10": float(np.quantile(true_probability, 0.10)),
        "true_scheme_probability_p25": float(np.quantile(true_probability, 0.25)),
        "true_scheme_probability_median": float(np.median(true_probability)),
        "true_scheme_probability_p75": float(np.quantile(true_probability, 0.75)),
        "true_scheme_probability_p90": float(np.quantile(true_probability, 0.90)),
        "events_with_majority_argmax_coverage": int(np.count_nonzero(event_coverage > 0.5)),
        "event_count": int(len(events)),
        "event_argmax_coverage_minimum": float(event_coverage.min()),
        "event_argmax_coverage_median": float(np.median(event_coverage)),
        "event_argmax_coverage_maximum": float(event_coverage.max()),
    }


def _format_value(value: float, decimals: int) -> str:
    if value != 0.0 and abs(value) < 0.0001:
        return f"{value:.2e}"
    return f"{value:.{decimals}f}"


def _write_csv(path: Path, rows: list[dict]) -> None:
    with path.open("w", newline="", encoding="utf-8-sig") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def _render_parameter_table(path: Path, parameter_values: dict[str, dict[str, float]]) -> None:
    figure, axis = plt.subplots(figsize=(13.5, 9.2))
    axis.axis("off")
    headers = ["完整参数含义", "单位", "方案 A", "方案 B", "方案 C"]
    cells = []
    for parameter_name, label, unit, decimals in PARAMETER_DEFINITIONS:
        cells.append(
            [
                label,
                unit,
                *[
                    _format_value(parameter_values[scheme][parameter_name], decimals)
                    for scheme in SCHEME_ORDER
                ],
            ]
        )
    table = axis.table(
        cellText=cells,
        colLabels=headers,
        cellLoc="center",
        colLoc="center",
        colWidths=(0.43, 0.16, 0.135, 0.135, 0.135),
        bbox=(0.02, 0.13, 0.96, 0.73),
    )
    table.auto_set_font_size(False)
    table.set_fontsize(10.2)
    table.scale(1.0, 1.42)
    header_colors = ("#E8E8E8", "#E8E8E8", "#D9ECF7", "#F8DED5", "#D8F0E7")
    for column in range(5):
        cell = table[(0, column)]
        cell.set_facecolor(header_colors[column])
        cell.set_text_props(weight="bold")
        cell.set_edgecolor("#888888")
    for row in range(1, len(cells) + 1):
        for column in range(5):
            cell = table[(row, column)]
            cell.set_facecolor("#FAFAFA" if row % 2 else "#F1F1F1")
            cell.set_edgecolor("#C5C5C5")
        table[(row, 0)].set_text_props(ha="left")

    figure.suptitle("三套用于生成合成流量的完整 HBV 参数方案", fontsize=18, y=0.975)
    axis.text(
        0.5,
        0.915,
        "A、B、C 只是中性标签。参数切换时，下表 13 个数作为一整套同时切换。",
        transform=axis.transAxes,
        ha="center",
        va="center",
        fontsize=12,
    )
    axis.text(
        0.02,
        0.085,
        "来源说明：方案 A 是封存的训练所得参数向量；方案 B、C 的原始方向曾满足开发期效率指标与 A 相差不超过 0.03，",
        transform=axis.transAxes,
        ha="left",
        va="center",
        fontsize=9.6,
    )
    axis.text(
        0.02,
        0.045,
        "但本压力试验已把 B、C 相对 A 的参数差异放大 8 倍。因此本图不再把 B、C 称为“等效参数组”。",
        transform=axis.transAxes,
        ha="left",
        va="center",
        fontsize=9.6,
        color="#8A2D1B",
        weight="bold",
    )
    figure.savefig(path, dpi=190, bbox_inches="tight", facecolor="white")
    plt.close(figure)


def _render_probability_figure(
    path: Path,
    method_events: dict[str, dict[tuple[str, str], np.ndarray]],
    summaries: dict[str, dict[tuple[str, str], dict]],
    parameter_ids: np.ndarray,
) -> None:
    figure, axes = plt.subplots(3, 2, figsize=(16, 12.6), sharex=True, sharey=True)
    days = np.arange(180)
    for row_index, transition in enumerate(TRANSITIONS):
        old_scheme, new_scheme = transition
        true_parameter_id = PARAMETER_ID_BY_SCHEME[new_scheme]
        true_parameter_index = int(np.flatnonzero(parameter_ids == true_parameter_id)[0])
        for column_index, (method_name, method_label, _) in enumerate(METHODS):
            axis = axes[row_index, column_index]
            events = method_events[method_name][transition]
            for scheme in SCHEME_ORDER:
                parameter_id = PARAMETER_ID_BY_SCHEME[scheme]
                parameter_index = int(np.flatnonzero(parameter_ids == parameter_id)[0])
                values = events[..., parameter_index]
                median = np.median(values, axis=0)
                is_true = scheme == new_scheme
                axis.plot(
                    days,
                    median,
                    color=SCHEME_COLORS[scheme],
                    linewidth=2.8 if is_true else 1.55,
                    label=f"算法给方案 {scheme} 的概率",
                    zorder=3 if is_true else 2,
                )
                if is_true:
                    lower, upper = np.quantile(values, (0.10, 0.90), axis=0)
                    axis.fill_between(
                        days,
                        lower,
                        upper,
                        color=SCHEME_COLORS[scheme],
                        alpha=0.16,
                        linewidth=0.0,
                        zorder=1,
                    )
            metrics = summaries[method_name][transition]
            axis.axhline(0.5, color="#686868", linestyle="--", linewidth=0.9, alpha=0.8)
            axis.axvspan(0, 5, color="#BDBDBD", alpha=0.24, zorder=0)
            axis.text(
                0.985,
                0.965,
                (
                    f"计分日中真实方案概率最高：{metrics['true_scheme_argmax_coverage']:.1%}\n"
                    f"真实方案概率中位数：{metrics['true_scheme_probability_median']:.3f}\n"
                    f"16 次切换事件中以真实方案为主："
                    f"{metrics['events_with_majority_argmax_coverage']}/16"
                ),
                transform=axis.transAxes,
                ha="right",
                va="top",
                fontsize=9.0,
                bbox={"facecolor": "white", "edgecolor": "#BBBBBB", "alpha": 0.92},
            )
            if row_index == 0:
                axis.set_title(method_label, fontsize=12.5, pad=10)
            if column_index == 0:
                axis.set_ylabel(
                    f"真实参数：{old_scheme} → {new_scheme}\n同化后候选概率",
                    fontsize=10.5,
                )
            if row_index == len(TRANSITIONS) - 1:
                axis.set_xlabel("真实参数切换后的天数", fontsize=10.5)
            axis.set_xlim(0, 179)
            axis.set_ylim(0, 1.02)
            axis.grid(alpha=0.20, linewidth=0.7)
    line_handles = [
        plt.Line2D([0], [0], color=SCHEME_COLORS[scheme], linewidth=2.5)
        for scheme in SCHEME_ORDER
    ]
    line_labels = [f"算法给方案 {scheme} 的概率" for scheme in SCHEME_ORDER]
    interval_handle = Patch(facecolor="#777777", alpha=0.16, edgecolor="none")
    figure.legend(
        [*line_handles, interval_handle],
        [*line_labels, "当前真实方案在 16 次事件中的 10%–90%范围"],
        loc="upper center",
        bbox_to_anchor=(0.5, 0.917),
        ncol=4,
        frameon=False,
        fontsize=10,
    )
    figure.suptitle(
        "每日流量同化后，滤波器认为哪套参数正在生成流量",
        fontsize=17,
        y=0.988,
    )
    figure.text(
        0.5,
        0.945,
        "每条线是 16 次匹配切换事件的中位数；粗线对应切换后的真实方案。A、B、C 的具体数值见参数表。",
        ha="center",
        fontsize=10.5,
    )
    figure.text(
        0.5,
        0.015,
        "灰色区域是切换后的前 5 天，按封存规则不计分；横向虚线只表示概率 50%，不是新的通过标准。",
        ha="center",
        fontsize=9.5,
    )
    figure.tight_layout(rect=(0.035, 0.05, 0.99, 0.885))
    figure.savefig(path, dpi=190, bbox_inches="tight", facecolor="white")
    plt.close(figure)


def _verify_image(path: Path) -> None:
    image = matplotlib_image.imread(path)
    if image.size == 0 or image.ndim not in (2, 3) or not np.all(np.isfinite(image)):
        raise ValueError(f"figure failed decoding: {path.name}")


def render(output_dir: Path) -> dict:
    output_dir = output_dir.resolve()
    if output_dir.exists():
        raise FileExistsError(f"plain-language readout already exists: {output_dir}")
    config, frozen_summary = _verify_sources()
    parameter_values = _load_parameter_values()

    with np.load(SOURCE_RESULT / "evidence.npz", allow_pickle=False) as archive:
        probabilities = np.asarray(archive["method_assimilation_probabilities"], dtype=np.float64)
        schedule = np.asarray(archive["truth_parameter_indices"], dtype=np.int64)
        parameter_ids = np.asarray(archive["parameter_ids"]).astype(str)
    if tuple(parameter_ids) != (
        "equifinal_diverse_1",
        "trained_center",
        "equifinal_diverse_2",
    ):
        raise ValueError("sealed parameter order changed")

    method_events: dict[str, dict[tuple[str, str], np.ndarray]] = {}
    summaries: dict[str, dict[tuple[str, str], dict]] = {}
    for method_name, _, method_index in METHODS:
        values = _extract_method_probabilities(probabilities, method_index)
        events = _collect_transition_events(values, schedule, parameter_ids)
        method_events[method_name] = events
        summaries[method_name] = {}
        for transition in TRANSITIONS:
            true_id = PARAMETER_ID_BY_SCHEME[transition[1]]
            true_index = int(np.flatnonzero(parameter_ids == true_id)[0])
            summaries[method_name][transition] = _summarize(events[transition], true_index)

    staging = output_dir.with_name(f"{output_dir.name}.incomplete.{uuid4().hex}")
    staging.mkdir(parents=True, exist_ok=False)

    parameter_rows = []
    for scheme in SCHEME_ORDER:
        for parameter_name, label, unit, _ in PARAMETER_DEFINITIONS:
            parameter_rows.append(
                {
                    "scheme": scheme,
                    "internal_parameter_id_for_traceability_only": PARAMETER_ID_BY_SCHEME[scheme],
                    "parameter_field": parameter_name,
                    "parameter_full_name_chinese": label,
                    "unit": unit,
                    "value": parameter_values[scheme][parameter_name],
                }
            )
    _write_csv(staging / "parameter_scheme_definition.csv", parameter_rows)

    summary_rows = []
    trajectory_rows = []
    for method_name, method_label, _ in METHODS:
        for old_scheme, new_scheme in TRANSITIONS:
            transition = (old_scheme, new_scheme)
            metrics = summaries[method_name][transition]
            summary_rows.append(
                {
                    "method": method_name,
                    "method_plain_label": method_label.replace("\n", " "),
                    "old_true_scheme": old_scheme,
                    "new_true_scheme": new_scheme,
                    **metrics,
                }
            )
            events = method_events[method_name][transition]
            for scheme in SCHEME_ORDER:
                parameter_index = int(
                    np.flatnonzero(parameter_ids == PARAMETER_ID_BY_SCHEME[scheme])[0]
                )
                values = events[..., parameter_index]
                quantiles = np.quantile(values, (0.10, 0.50, 0.90), axis=0)
                for day in range(180):
                    trajectory_rows.append(
                        {
                            "method": method_name,
                            "old_true_scheme": old_scheme,
                            "new_true_scheme": new_scheme,
                            "day_after_switch_zero_based": day,
                            "candidate_scheme": scheme,
                            "is_true_scheme": scheme == new_scheme,
                            "probability_p10": quantiles[0, day],
                            "probability_median": quantiles[1, day],
                            "probability_p90": quantiles[2, day],
                        }
                    )
    _write_csv(staging / "candidate_probability_summary_plain.csv", summary_rows)
    _write_csv(staging / "candidate_probability_trajectories_plain.csv", trajectory_rows)

    matplotlib.rcParams["font.sans-serif"] = ["Microsoft YaHei", "SimHei", "DejaVu Sans"]
    matplotlib.rcParams["axes.unicode_minus"] = False
    _render_parameter_table(staging / "parameter_scheme_values.png", parameter_values)
    _render_probability_figure(
        staging / "candidate_probability_plain_labels.png",
        method_events,
        summaries,
        parameter_ids,
    )
    _verify_image(staging / "parameter_scheme_values.png")
    _verify_image(staging / "candidate_probability_plain_labels.png")

    summary_json = {
        "classification": "readout_only_no_new_scientific_gate",
        "source_experiment": "g3_ideal_gate_param_switch_v01",
        "source_scientific_status": frozen_summary["scientific_status"],
        "spacing_multiplier": config["g3_ideal_gate"]["spacing_multiplier"],
        "scheme_mapping_for_traceability": PARAMETER_ID_BY_SCHEME,
        "plain_language_correction": (
            "Internal candidate identifiers are removed from reader-facing figures. "
            "Schemes B and C are not called equifinal because their deviations from A "
            "were multiplied by eight in this sealed stress test."
        ),
        "adaptation_days_excluded": 5,
        "matched_events_per_directed_transition": 16,
        "new_threshold_applied": False,
        "scope_limit": (
            "Posterior parameter-candidate probabilities in an HBV synthetic experiment only; "
            "not a state-accuracy, forecast, real-catchment, or other-model result."
        ),
        "metrics": {
            method_name: {
                f"{old_scheme}_to_{new_scheme}": summaries[method_name][
                    (old_scheme, new_scheme)
                ]
                for old_scheme, new_scheme in TRANSITIONS
            }
            for method_name, _, _ in METHODS
        },
    }
    (staging / "summary.json").write_text(
        json.dumps(summary_json, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    artifact_names = (
        "parameter_scheme_values.png",
        "candidate_probability_plain_labels.png",
        "parameter_scheme_definition.csv",
        "candidate_probability_summary_plain.csv",
        "candidate_probability_trajectories_plain.csv",
        "summary.json",
    )
    manifest = {
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "source_directory": str(SOURCE_RESULT),
        "source_hashes": EXPECTED_HASHES,
        "artifacts": {name: _sha256(staging / name) for name in artifact_names},
    }
    (staging / "readout_manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    if output_dir.exists():
        raise FileExistsError("plain-language readout directory appeared during rendering")
    staging.rename(output_dir)
    return {**summary_json, "output_directory": str(output_dir)}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    print(json.dumps(render(args.output_dir), ensure_ascii=False, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()

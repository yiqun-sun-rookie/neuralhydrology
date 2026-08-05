"""Render continuous and boundary-centered parameter-switch probability readouts.

The readout is derived only from sealed evidence. It does not rerun assimilation
or forecasting and refuses to write into an existing output directory.
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


PROJECT_ROOT = Path(__file__).resolve().parents[3]
SOURCE_RESULT = (
    PROJECT_ROOT
    / "results/23_hbv_multilead_joint_uncertainty/g3_ideal_gate_param_switch_v01"
)
G2_REFERENCE = (
    PROJECT_ROOT
    / "results/23_hbv_multilead_joint_uncertainty/g2_curve_param_switch_dev_m80_L180_v01"
)
DEFAULT_OUTPUT = SOURCE_RESULT.with_name(
    "g3_ideal_gate_param_switch_v01_continuous_switch_readout_v01"
)

EXPECTED_SOURCE_HASHES = {
    "evidence.npz": "77f84d793f18a72972e5af5f2ac4ed767645471e37da31c612ab995ecf4bbf67",
    "config_snapshot.json": "435fc07dd68bc1a3de06b402824047189e52606372073827198cdb7d50392e0c",
    "summary.json": "74f77da08a1904fb33808bb4f6da308ca151d736cbcfe05dcfbbd8a3071236f7",
    "stage_identification.csv": "fb17d3ae11fef44c838b2a151e21b55a71651f46dfefafbcf8a8667589413cf4",
}
EXPECTED_G2_HASHES = {
    "summary.json": "31ce1c36e9061d5284458af9aee43deb45bcd8aba43ee1d5f44ef0de3588b062",
    "scientific_evaluation.json": "0ae2f0270376d7ba2f0028d25ac1be74a3c8ae55cefec9fae31e6ee2c880d2e6",
    "config_snapshot.json": "fca91ecd48d5a6fd1430b89412f7e351a9dc940bd6827a29b3b844754c9d2bfc",
}

PARAMETER_ID_BY_SCHEME = {
    "A": "trained_center",
    "B": "equifinal_diverse_2",
    "C": "equifinal_diverse_1",
}
SCHEME_BY_PARAMETER_ID = {value: key for key, value in PARAMETER_ID_BY_SCHEME.items()}
SCHEME_ORDER = ("A", "B", "C")
SCHEME_COLORS = {"A": "#0072B2", "B": "#D55E00", "C": "#009E73"}
METHODS = (
    ("parameter_only", "只让三套参数竞争（过程噪声固定）", 2),
    (
        "joint_parameter_marginal",
        "参数和过程噪声同时竞争（同参数的噪声概率已相加）",
        4,
    ),
)
TRANSITIONS = (("A", "B"), ("B", "C"), ("C", "A"))
PRE_SWITCH_DAYS = 30
POST_SWITCH_DAYS = 45
STABLE_RUN_DAYS = 5


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _verify_hashes(directory: Path, expected_hashes: dict[str, str]) -> None:
    for filename, expected in expected_hashes.items():
        actual = _sha256(directory / filename)
        if actual != expected:
            raise ValueError(f"source hash changed for {directory.name}/{filename}: {actual}")


def _verify_sources() -> tuple[dict, dict, dict]:
    _verify_hashes(SOURCE_RESULT, EXPECTED_SOURCE_HASHES)
    _verify_hashes(G2_REFERENCE, EXPECTED_G2_HASHES)
    source_config = json.loads(
        (SOURCE_RESULT / "config_snapshot.json").read_text(encoding="utf-8")
    )
    source_summary = json.loads((SOURCE_RESULT / "summary.json").read_text(encoding="utf-8"))
    g2_config = json.loads((G2_REFERENCE / "config_snapshot.json").read_text(encoding="utf-8"))
    g2_summary = json.loads((G2_REFERENCE / "summary.json").read_text(encoding="utf-8"))
    g2_evaluation = json.loads(
        (G2_REFERENCE / "scientific_evaluation.json").read_text(encoding="utf-8")
    )
    if float(source_config["g3_ideal_gate"]["spacing_multiplier"]) != 8.0:
        raise ValueError("G3 spacing multiplier changed")
    if source_config["stage_lengths"] != [180, 180, 180]:
        raise ValueError("G3 stage lengths changed")
    if source_summary.get("scientific_status") != "not_passed":
        raise ValueError("G3 scientific status changed")
    diagnostic = g2_config["diagnostic_contract"]
    if any(
        bool(diagnostic[field])
        for field in (
            "candidate_state_interaction_used",
            "candidate_probability_transition_used",
            "candidate_probability_update_used",
        )
    ):
        raise ValueError("G2 reference is no longer an independent-likelihood diagnostic")
    if float(g2_config["g2_grid"]["spacing_multiplier"]) != 8.0:
        raise ValueError("G2 reference spacing multiplier changed")
    if int(g2_config["g2_grid"]["stage_length_days"]) != 180:
        raise ValueError("G2 reference stage length changed")
    if g2_summary.get("scientific_status") != "passed":
        raise ValueError("G2 reference no longer has the sealed passed status")
    return source_summary, g2_config, g2_evaluation


def _extract_method_probabilities(probabilities: np.ndarray, method_index: int) -> np.ndarray:
    values = probabilities[:, :, method_index]
    if method_index == 2:
        values = values[..., :3]
    elif method_index == 4:
        values = values[..., :9].reshape(8, 3, 540, 3, 3).sum(axis=-1)
    else:
        raise ValueError("unsupported method index")
    if values.shape != (8, 3, 540, 3):
        raise ValueError(f"unexpected probability shape: {values.shape}")
    if not np.allclose(values.sum(axis=-1), 1.0, rtol=0.0, atol=1e-12):
        raise ValueError("parameter probabilities do not sum to one")
    return values


def _collect_switch_events(
    method_values: np.ndarray,
    schedule: np.ndarray,
    parameter_ids: np.ndarray,
) -> tuple[dict[tuple[str, str], np.ndarray], dict[tuple[str, str], np.ndarray]]:
    zoom: dict[tuple[str, str], list[np.ndarray]] = {transition: [] for transition in TRANSITIONS}
    full_post: dict[tuple[str, str], list[np.ndarray]] = {
        transition: [] for transition in TRANSITIONS
    }
    for boundary in (180, 360):
        for trial in range(3):
            old_id = str(parameter_ids[int(schedule[trial, boundary - 1])])
            new_id = str(parameter_ids[int(schedule[trial, boundary])])
            transition = (SCHEME_BY_PARAMETER_ID[old_id], SCHEME_BY_PARAMETER_ID[new_id])
            if transition not in zoom:
                raise ValueError(f"unexpected transition {transition}")
            for block in range(8):
                zoom[transition].append(
                    method_values[
                        block,
                        trial,
                        boundary - PRE_SWITCH_DAYS : boundary + POST_SWITCH_DAYS,
                    ].copy()
                )
                full_post[transition].append(
                    method_values[block, trial, boundary : boundary + 180].copy()
                )
    packed_zoom = {transition: np.stack(events) for transition, events in zoom.items()}
    packed_post = {transition: np.stack(events) for transition, events in full_post.items()}
    for transition in TRANSITIONS:
        if packed_zoom[transition].shape != (16, PRE_SWITCH_DAYS + POST_SWITCH_DAYS, 3):
            raise ValueError(f"unexpected zoom event shape for {transition}")
        if packed_post[transition].shape != (16, 180, 3):
            raise ValueError(f"unexpected post-switch event shape for {transition}")
    return packed_zoom, packed_post


def _stable_response_summary(events: np.ndarray, true_index: int) -> dict[str, float | int]:
    delays: list[int | None] = []
    for event in events:
        top_ranked = np.argmax(event, axis=-1) == true_index
        delay = next(
            (
                day
                for day in range(len(event) - STABLE_RUN_DAYS + 1)
                if np.all(top_ranked[day : day + STABLE_RUN_DAYS])
            ),
            None,
        )
        delays.append(delay)
    successful = np.asarray([value for value in delays if value is not None], dtype=np.float64)
    if not len(successful):
        median_delay = np.nan
        maximum_delay = np.nan
    else:
        median_delay = float(np.median(successful))
        maximum_delay = float(np.max(successful))
    return {
        "event_count": len(delays),
        "events_with_five_consecutive_top_ranked_days_in_full_stage": len(successful),
        "events_with_five_consecutive_top_ranked_days_within_45_days": int(
            sum(value is not None and value < POST_SWITCH_DAYS for value in delays)
        ),
        "median_first_five_day_top_ranked_run_start_among_successes": median_delay,
        "maximum_first_five_day_top_ranked_run_start_among_successes": maximum_delay,
    }


def _write_csv(path: Path, rows: list[dict]) -> None:
    with path.open("w", newline="", encoding="utf-8-sig") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def _render_full_timeline(
    path: Path,
    method_values: dict[str, np.ndarray],
    schedule: np.ndarray,
    parameter_ids: np.ndarray,
) -> None:
    figure, axes = plt.subplots(3, 2, figsize=(16, 12.4), sharex=True, sharey=True)
    days = np.arange(1, 541)
    for trial in range(3):
        stage_schemes = []
        for start in (0, 180, 360):
            parameter_id = str(parameter_ids[int(schedule[trial, start])])
            stage_schemes.append(SCHEME_BY_PARAMETER_ID[parameter_id])
        for column, (method_name, method_label, _) in enumerate(METHODS):
            axis = axes[trial, column]
            values = method_values[method_name][:, trial]
            for start, end, truth_scheme in zip(
                (0, 180, 360), (180, 360, 540), stage_schemes
            ):
                axis.axvspan(
                    start + 1,
                    end,
                    color=SCHEME_COLORS[truth_scheme],
                    alpha=0.055,
                    linewidth=0.0,
                )
                axis.text(
                    (start + end + 1) / 2,
                    1.008,
                    f"真实方案 {truth_scheme}",
                    ha="center",
                    va="bottom",
                    fontsize=9.5,
                    color=SCHEME_COLORS[truth_scheme],
                    weight="bold",
                    clip_on=False,
                )
            for scheme in SCHEME_ORDER:
                parameter_id = PARAMETER_ID_BY_SCHEME[scheme]
                parameter_index = int(np.flatnonzero(parameter_ids == parameter_id)[0])
                axis.plot(
                    days,
                    np.median(values[..., parameter_index], axis=0),
                    color=SCHEME_COLORS[scheme],
                    linewidth=1.8,
                    label=f"算法给方案 {scheme} 的概率",
                )
            for boundary in (180.5, 360.5):
                axis.axvline(boundary, color="#222222", linestyle="--", linewidth=1.15)
            if trial == 0:
                axis.set_title(method_label, fontsize=12.3, pad=28)
            if column == 0:
                axis.set_ylabel(
                    f"真值顺序：{' → '.join(stage_schemes)}\n同化后候选概率",
                    fontsize=10.5,
                )
            if trial == 2:
                axis.set_xlabel("连续同化日", fontsize=10.5)
            axis.set_xlim(1, 540)
            axis.set_ylim(0, 1.0)
            axis.grid(alpha=0.18, linewidth=0.7)
    handles = [
        plt.Line2D([0], [0], color=SCHEME_COLORS[scheme], linewidth=2.5)
        for scheme in SCHEME_ORDER
    ]
    figure.legend(
        handles,
        [f"算法给方案 {scheme} 的概率" for scheme in SCHEME_ORDER],
        loc="upper center",
        bbox_to_anchor=(0.5, 0.925),
        ncol=3,
        frameon=False,
        fontsize=10,
    )
    figure.suptitle(
        "完整 540 天时间线上，候选概率怎样跨过两个真实参数切换点",
        fontsize=17,
        y=0.99,
    )
    figure.text(
        0.5,
        0.952,
        "虚线是第 180/181 天和第 360/361 天之间的真实切换边界；曲线是 8 个匹配区块的中位数。",
        ha="center",
        fontsize=10.5,
    )
    figure.text(
        0.5,
        0.014,
        "背景颜色表示当时真正用于生成合成流量的完整参数方案。该图显示响应过程，不是未知变点检测结果。",
        ha="center",
        fontsize=9.5,
    )
    figure.tight_layout(rect=(0.035, 0.05, 0.99, 0.89))
    figure.savefig(path, dpi=190, bbox_inches="tight", facecolor="white")
    plt.close(figure)


def _render_switch_zoom(
    path: Path,
    zoom_events: dict[str, dict[tuple[str, str], np.ndarray]],
    response_summaries: dict[str, dict[tuple[str, str], dict]],
    parameter_ids: np.ndarray,
) -> None:
    figure, axes = plt.subplots(3, 2, figsize=(16, 12.5), sharex=True, sharey=True)
    relative_days = np.arange(-PRE_SWITCH_DAYS, POST_SWITCH_DAYS)
    for row, transition in enumerate(TRANSITIONS):
        old_scheme, new_scheme = transition
        for column, (method_name, method_label, _) in enumerate(METHODS):
            axis = axes[row, column]
            events = zoom_events[method_name][transition]
            axis.axvspan(
                -PRE_SWITCH_DAYS,
                0,
                color=SCHEME_COLORS[old_scheme],
                alpha=0.065,
                linewidth=0.0,
            )
            axis.axvspan(
                0,
                POST_SWITCH_DAYS - 1,
                color=SCHEME_COLORS[new_scheme],
                alpha=0.065,
                linewidth=0.0,
            )
            for scheme in SCHEME_ORDER:
                parameter_index = int(
                    np.flatnonzero(parameter_ids == PARAMETER_ID_BY_SCHEME[scheme])[0]
                )
                axis.plot(
                    relative_days,
                    np.median(events[..., parameter_index], axis=0),
                    color=SCHEME_COLORS[scheme],
                    linewidth=2.4 if scheme in transition else 1.35,
                    label=f"方案 {scheme}",
                )
            axis.axvline(0, color="#111111", linestyle="--", linewidth=1.35)
            metrics = response_summaries[method_name][transition]
            median_delay = metrics[
                "median_first_five_day_top_ranked_run_start_among_successes"
            ]
            axis.text(
                0.985,
                0.965,
                (
                    "新方案首次连续 5 天概率最高：\n"
                    f"成功事件中位起点 = 切换后 {median_delay:.0f} 天\n"
                    "45 天内出现 = "
                    f"{metrics['events_with_five_consecutive_top_ranked_days_within_45_days']}/16"
                ),
                transform=axis.transAxes,
                ha="right",
                va="top",
                fontsize=9.0,
                bbox={"facecolor": "white", "edgecolor": "#BBBBBB", "alpha": 0.92},
            )
            axis.text(
                -PRE_SWITCH_DAYS / 2,
                1.008,
                f"切换前真实 = {old_scheme}",
                ha="center",
                va="bottom",
                color=SCHEME_COLORS[old_scheme],
                weight="bold",
                fontsize=9.5,
                clip_on=False,
            )
            axis.text(
                POST_SWITCH_DAYS / 2,
                1.008,
                f"切换后真实 = {new_scheme}",
                ha="center",
                va="bottom",
                color=SCHEME_COLORS[new_scheme],
                weight="bold",
                fontsize=9.5,
                clip_on=False,
            )
            if row == 0:
                axis.set_title(method_label, fontsize=12.3, pad=28)
            if column == 0:
                axis.set_ylabel(f"真实方案 {old_scheme} → {new_scheme}\n同化后候选概率")
            if row == 2:
                axis.set_xlabel("相对真实切换边界的天数（0 = 切换后的第一天）")
            axis.set_xlim(-PRE_SWITCH_DAYS, POST_SWITCH_DAYS - 1)
            axis.set_ylim(0, 1.0)
            axis.grid(alpha=0.18, linewidth=0.7)
    handles = [
        plt.Line2D([0], [0], color=SCHEME_COLORS[scheme], linewidth=2.5)
        for scheme in SCHEME_ORDER
    ]
    figure.legend(
        handles,
        [f"算法给方案 {scheme} 的概率" for scheme in SCHEME_ORDER],
        loc="upper center",
        bbox_to_anchor=(0.5, 0.927),
        ncol=3,
        frameon=False,
        fontsize=10,
    )
    figure.suptitle(
        "保留切换前 30 天：候选概率怎样从旧方案转向新方案",
        fontsize=17,
        y=0.99,
    )
    figure.text(
        0.5,
        0.952,
        "每条曲线是 16 次匹配切换事件的中位数；竖向虚线才是真实切换边界。",
        ha="center",
        fontsize=10.5,
    )
    figure.text(
        0.5,
        0.014,
        "连续 5 天占优仅是本次读图描述，不替代封存实验的整阶段识别标准，也不构成新的通过门槛。",
        ha="center",
        fontsize=9.5,
    )
    figure.tight_layout(rect=(0.035, 0.05, 0.99, 0.89))
    figure.savefig(path, dpi=190, bbox_inches="tight", facecolor="white")
    plt.close(figure)


def _verify_image(path: Path) -> None:
    image = matplotlib_image.imread(path)
    if image.size == 0 or image.ndim not in (2, 3) or not np.all(np.isfinite(image)):
        raise ValueError(f"image failed decoding: {path.name}")


def render(output_dir: Path) -> dict:
    output_dir = output_dir.resolve()
    if output_dir.exists():
        raise FileExistsError(f"continuous-switch readout already exists: {output_dir}")
    source_summary, g2_config, g2_evaluation = _verify_sources()

    with np.load(SOURCE_RESULT / "evidence.npz", allow_pickle=False) as archive:
        probabilities = np.asarray(archive["method_assimilation_probabilities"], dtype=np.float64)
        schedule = np.asarray(archive["truth_parameter_indices"], dtype=np.int64)[:, :540]
        parameter_ids = np.asarray(archive["parameter_ids"]).astype(str)
    if tuple(parameter_ids) != (
        "equifinal_diverse_1",
        "trained_center",
        "equifinal_diverse_2",
    ):
        raise ValueError("sealed parameter order changed")

    method_values: dict[str, np.ndarray] = {}
    zoom_events: dict[str, dict[tuple[str, str], np.ndarray]] = {}
    response_summaries: dict[str, dict[tuple[str, str], dict]] = {}
    for method_name, _, method_index in METHODS:
        values = _extract_method_probabilities(probabilities, method_index)
        method_values[method_name] = values
        zoom, post = _collect_switch_events(values, schedule, parameter_ids)
        zoom_events[method_name] = zoom
        response_summaries[method_name] = {}
        for transition in TRANSITIONS:
            true_index = int(
                np.flatnonzero(
                    parameter_ids == PARAMETER_ID_BY_SCHEME[transition[1]]
                )[0]
            )
            response_summaries[method_name][transition] = _stable_response_summary(
                post[transition], true_index
            )

    staging = output_dir.with_name(f"{output_dir.name}.incomplete.{uuid4().hex}")
    staging.mkdir(parents=True, exist_ok=False)

    response_rows = []
    for method_name, method_label, _ in METHODS:
        for old_scheme, new_scheme in TRANSITIONS:
            response_rows.append(
                {
                    "method": method_name,
                    "method_plain_label": method_label,
                    "old_true_scheme": old_scheme,
                    "new_true_scheme": new_scheme,
                    **response_summaries[method_name][(old_scheme, new_scheme)],
                }
            )
    _write_csv(staging / "switch_response_summary.csv", response_rows)

    timeline_rows = []
    for method_name, _, _ in METHODS:
        values = method_values[method_name]
        for trial in range(3):
            for day in range(540):
                true_id = str(parameter_ids[int(schedule[trial, day])])
                for scheme in SCHEME_ORDER:
                    parameter_index = int(
                        np.flatnonzero(
                            parameter_ids == PARAMETER_ID_BY_SCHEME[scheme]
                        )[0]
                    )
                    samples = values[:, trial, day, parameter_index]
                    timeline_rows.append(
                        {
                            "method": method_name,
                            "truth_trial": trial + 1,
                            "assimilation_day_one_based": day + 1,
                            "true_scheme": SCHEME_BY_PARAMETER_ID[true_id],
                            "candidate_scheme": scheme,
                            "probability_p10": float(np.quantile(samples, 0.10)),
                            "probability_median": float(np.median(samples)),
                            "probability_p90": float(np.quantile(samples, 0.90)),
                        }
                    )
    _write_csv(staging / "continuous_probability_trajectories.csv", timeline_rows)

    zoom_rows = []
    relative_days = np.arange(-PRE_SWITCH_DAYS, POST_SWITCH_DAYS)
    for method_name, _, _ in METHODS:
        for transition in TRANSITIONS:
            events = zoom_events[method_name][transition]
            for scheme in SCHEME_ORDER:
                parameter_index = int(
                    np.flatnonzero(parameter_ids == PARAMETER_ID_BY_SCHEME[scheme])[0]
                )
                samples = events[..., parameter_index]
                for index, relative_day in enumerate(relative_days):
                    zoom_rows.append(
                        {
                            "method": method_name,
                            "old_true_scheme": transition[0],
                            "new_true_scheme": transition[1],
                            "relative_day": int(relative_day),
                            "candidate_scheme": scheme,
                            "probability_p10": float(np.quantile(samples[:, index], 0.10)),
                            "probability_median": float(np.median(samples[:, index])),
                            "probability_p90": float(np.quantile(samples[:, index], 0.90)),
                        }
                    )
    _write_csv(staging / "switch_centered_probability_trajectories.csv", zoom_rows)

    matplotlib.rcParams["font.sans-serif"] = ["Microsoft YaHei", "SimHei", "DejaVu Sans"]
    matplotlib.rcParams["axes.unicode_minus"] = False
    _render_full_timeline(
        staging / "continuous_540_day_probability.png",
        method_values,
        schedule,
        parameter_ids,
    )
    _render_switch_zoom(
        staging / "switch_centered_probability.png",
        zoom_events,
        response_summaries,
        parameter_ids,
    )
    _verify_image(staging / "continuous_540_day_probability.png")
    _verify_image(staging / "switch_centered_probability.png")

    g2_switching_results = {
        str(item["stage_number"]): {
            "stable_identifiable_fraction": item["stable_identifiable_fraction"],
            "median_first_stable_cumulative_rank_one_day_among_successes": item[
                "median_first_stable_cumulative_rank_one_day_among_successes"
            ],
            "stage_passed": item["stage_passed"],
        }
        for item in g2_evaluation["stage_results"]
        if item["is_switching_stage"]
    }
    result_summary = {
        "classification": "readout_only_no_new_scientific_gate",
        "source_experiment": "g3_ideal_gate_param_switch_v01",
        "source_scientific_status": source_summary["scientific_status"],
        "scheme_mapping_for_traceability": PARAMETER_ID_BY_SCHEME,
        "switch_boundaries_between_days": ["180_and_181", "360_and_361"],
        "response_metric": (
            "First post-switch day starting five consecutive days on which the new true "
            "scheme has the largest posterior probability. Descriptive readout only."
        ),
        "response_metrics": {
            method_name: {
                f"{old_scheme}_to_{new_scheme}": response_summaries[method_name][
                    (old_scheme, new_scheme)
                ]
                for old_scheme, new_scheme in TRANSITIONS
            }
            for method_name, _, _ in METHODS
        },
        "previous_successful_diagnostic": {
            "experiment_id": g2_config["experiment_id"],
            "spacing_multiplier": g2_config["g2_grid"]["spacing_multiplier"],
            "stage_length_days": g2_config["g2_grid"]["stage_length_days"],
            "switching_stage_results": g2_switching_results,
            "important_difference": (
                "The G2 diagnostic knew the stage boundary and reset cumulative predictive "
                "log likelihood at the first scored day. It used independent candidate filters "
                "without state interaction, probability transition, or probability update; "
                "therefore it measured re-identification after a known switch and did not "
                "discover an unknown change point."
            ),
        },
        "interpretation": (
            "The G3 posterior usually turns toward the new scheme quickly, but rapid initial "
            "response is different from maintaining correct dominance across the full stage."
        ),
        "new_threshold_applied": False,
        "scope_limit": (
            "Synthetic parameter-scheme posterior readout only; not unknown change-point "
            "detection, state accuracy, forecast skill, or real-catchment evidence."
        ),
    }
    (staging / "summary.json").write_text(
        json.dumps(result_summary, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    artifact_names = (
        "continuous_540_day_probability.png",
        "switch_centered_probability.png",
        "switch_response_summary.csv",
        "continuous_probability_trajectories.csv",
        "switch_centered_probability_trajectories.csv",
        "summary.json",
    )
    manifest = {
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "source_directory": str(SOURCE_RESULT),
        "source_hashes": EXPECTED_SOURCE_HASHES,
        "g2_reference_directory": str(G2_REFERENCE),
        "g2_reference_hashes": EXPECTED_G2_HASHES,
        "artifacts": {name: _sha256(staging / name) for name in artifact_names},
    }
    (staging / "readout_manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    if output_dir.exists():
        raise FileExistsError("continuous-switch output appeared during rendering")
    staging.rename(output_dir)
    return {**result_summary, "output_directory": str(output_dir)}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    print(json.dumps(render(args.output_dir), ensure_ascii=False, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()

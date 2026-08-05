"""Post-hoc parameter-switch response assessment from sealed G3 evidence.

This analysis changes only the readout question and criterion. It does not rerun
the filter, alter the sealed decision, or write into an existing output root.
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
from scipy.stats import beta

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402


PROJECT_ROOT = Path(__file__).resolve().parents[3]
SOURCE_RESULT = (
    PROJECT_ROOT
    / "results/23_hbv_multilead_joint_uncertainty/g3_ideal_gate_param_switch_v01"
)
ANALYSIS_ID = "g3_parameter_switch_response_posthoc_v01"
DEFAULT_OUTPUT = (
    PROJECT_ROOT / "results/23_hbv_multilead_joint_uncertainty" / ANALYSIS_ID
)

EXPECTED_SOURCE_HASHES = {
    "evidence.npz": "77f84d793f18a72972e5af5f2ac4ed767645471e37da31c612ab995ecf4bbf67",
    "config_snapshot.json": "435fc07dd68bc1a3de06b402824047189e52606372073827198cdb7d50392e0c",
    "summary.json": "74f77da08a1904fb33808bb4f6da308ca151d736cbcfe05dcfbbd8a3071236f7",
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
    ("parameter_only", "只让三套参数竞争", 2, "#0072B2"),
    ("joint_parameter_marginal", "参数和过程噪声同时竞争", 4, "#D55E00"),
)
TRANSITIONS = (("A", "B"), ("B", "C"), ("C", "A"))

PRE_SWITCH_DAYS = 15
RESPONSE_WINDOW_DAYS = 30
CONSECUTIVE_TOP_DAYS = 5
MINIMUM_SUCCESSFUL_EVENTS = 13
EVENT_COUNT = 16
MINIMUM_OBSERVED_RESPONSE_FRACTION = MINIMUM_SUCCESSFUL_EVENTS / EVENT_COUNT
CONFIDENCE_LEVEL = 0.95
MINIMUM_EXACT_INTERVAL_LOWER_BOUND = 0.5


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _verify_sources() -> dict:
    for filename, expected in EXPECTED_SOURCE_HASHES.items():
        actual = _sha256(SOURCE_RESULT / filename)
        if actual != expected:
            raise ValueError(f"sealed source hash changed for {filename}: {actual}")
    source_config = json.loads(
        (SOURCE_RESULT / "config_snapshot.json").read_text(encoding="utf-8")
    )
    source_summary = json.loads((SOURCE_RESULT / "summary.json").read_text(encoding="utf-8"))
    if source_summary.get("scientific_status") != "not_passed":
        raise ValueError("sealed source scientific status changed")
    if source_config["stage_lengths"] != [180, 180, 180]:
        raise ValueError("sealed stage lengths changed")
    if source_config["decision_rules"]["candidate_argmax_accuracy_minimum"] != 0.9:
        raise ValueError("sealed original 0.90 gate changed")
    return source_summary


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


def _collect_events(
    values: np.ndarray,
    schedule: np.ndarray,
    parameter_ids: np.ndarray,
) -> tuple[dict[tuple[str, str], np.ndarray], dict[tuple[str, str], list[dict]]]:
    curves: dict[tuple[str, str], list[np.ndarray]] = {transition: [] for transition in TRANSITIONS}
    metadata: dict[tuple[str, str], list[dict]] = {transition: [] for transition in TRANSITIONS}
    for boundary in (180, 360):
        for trial in range(3):
            old_id = str(parameter_ids[int(schedule[trial, boundary - 1])])
            new_id = str(parameter_ids[int(schedule[trial, boundary])])
            transition = (SCHEME_BY_PARAMETER_ID[old_id], SCHEME_BY_PARAMETER_ID[new_id])
            if transition not in curves:
                raise ValueError(f"unexpected transition {transition}")
            for block in range(8):
                curves[transition].append(
                    values[
                        block,
                        trial,
                        boundary - PRE_SWITCH_DAYS : boundary + RESPONSE_WINDOW_DAYS,
                    ].copy()
                )
                metadata[transition].append(
                    {
                        "matched_block_one_based": block + 1,
                        "truth_trial_one_based": trial + 1,
                        "switch_boundary_after_assimilation_day": boundary,
                    }
                )
    packed = {transition: np.stack(events) for transition, events in curves.items()}
    expected_shape = (EVENT_COUNT, PRE_SWITCH_DAYS + RESPONSE_WINDOW_DAYS, 3)
    for transition in TRANSITIONS:
        if packed[transition].shape != expected_shape:
            raise ValueError(f"unexpected event shape for {transition}: {packed[transition].shape}")
        if len(metadata[transition]) != EVENT_COUNT:
            raise ValueError(f"unexpected event metadata count for {transition}")
    return packed, metadata


def _first_complete_stable_run(top_ranked: np.ndarray) -> int | None:
    maximum_start = RESPONSE_WINDOW_DAYS - CONSECUTIVE_TOP_DAYS
    return next(
        (
            day
            for day in range(maximum_start + 1)
            if np.all(top_ranked[day : day + CONSECUTIVE_TOP_DAYS])
        ),
        None,
    )


def _exact_binomial_interval(successes: int, total: int) -> tuple[float, float]:
    alpha = 1.0 - CONFIDENCE_LEVEL
    lower = 0.0 if successes == 0 else float(beta.ppf(alpha / 2.0, successes, total - successes + 1))
    upper = 1.0 if successes == total else float(
        beta.ppf(1.0 - alpha / 2.0, successes + 1, total - successes)
    )
    return lower, upper


def _assess_events(
    events: np.ndarray,
    true_index: int,
    metadata: list[dict],
) -> tuple[dict, list[dict]]:
    event_rows = []
    delays = []
    for event_index, (event, event_metadata) in enumerate(zip(events, metadata), start=1):
        post = event[PRE_SWITCH_DAYS:]
        top_ranked = np.argmax(post, axis=-1) == true_index
        delay = _first_complete_stable_run(top_ranked)
        success = delay is not None
        if success:
            delays.append(int(delay))
        event_rows.append(
            {
                "event_index_within_transition": event_index,
                **event_metadata,
                "response_supported_within_30_days": success,
                "first_five_day_top_ranked_run_start_zero_based": "" if delay is None else int(delay),
            }
        )
    successes = len(delays)
    lower, upper = _exact_binomial_interval(successes, len(events))
    fraction = successes / len(events)
    criterion_met = (
        successes >= MINIMUM_SUCCESSFUL_EVENTS
        and lower > MINIMUM_EXACT_INTERVAL_LOWER_BOUND
    )
    summary = {
        "event_count": len(events),
        "successful_event_count": successes,
        "observed_response_fraction": fraction,
        "exact_95_percent_interval_lower": lower,
        "exact_95_percent_interval_upper": upper,
        "median_response_day_among_successes": float(np.median(delays)) if delays else np.nan,
        "maximum_response_day_among_successes": float(np.max(delays)) if delays else np.nan,
        "post_hoc_response_criterion_met": criterion_met,
    }
    return summary, event_rows


def _write_csv(path: Path, rows: list[dict]) -> None:
    with path.open("w", newline="", encoding="utf-8-sig") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def _render_curves(
    path: Path,
    method_events: dict[str, dict[tuple[str, str], np.ndarray]],
    summaries: dict[str, dict[tuple[str, str], dict]],
    parameter_ids: np.ndarray,
) -> None:
    figure, axes = plt.subplots(3, 2, figsize=(16, 12.5), sharex=True, sharey=True)
    relative_days = np.arange(-PRE_SWITCH_DAYS, RESPONSE_WINDOW_DAYS)
    for row, transition in enumerate(TRANSITIONS):
        old_scheme, new_scheme = transition
        for column, (method_name, method_label, _, _) in enumerate(METHODS):
            axis = axes[row, column]
            events = method_events[method_name][transition]
            axis.axvspan(
                -PRE_SWITCH_DAYS,
                0,
                color=SCHEME_COLORS[old_scheme],
                alpha=0.065,
                linewidth=0.0,
            )
            axis.axvspan(
                0,
                RESPONSE_WINDOW_DAYS - 1,
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
                    linewidth=2.5 if scheme in transition else 1.35,
                )
            axis.axvline(0, color="#111111", linestyle="--", linewidth=1.35)
            metrics = summaries[method_name][transition]
            decision = "支持切换响应" if metrics["post_hoc_response_criterion_met"] else "不支持切换响应"
            axis.text(
                0.985,
                0.96,
                (
                    f"30天内完整出现连续5天占优：{metrics['successful_event_count']}/16\n"
                    f"响应率：{metrics['observed_response_fraction']:.1%} "
                    f"[95%区间 {metrics['exact_95_percent_interval_lower']:.1%}, "
                    f"{metrics['exact_95_percent_interval_upper']:.1%}]\n"
                    f"事后评价：{decision}"
                ),
                transform=axis.transAxes,
                ha="right",
                va="top",
                fontsize=9.0,
                color="#176B3A" if metrics["post_hoc_response_criterion_met"] else "#A11D1D",
                bbox={"facecolor": "white", "edgecolor": "#BBBBBB", "alpha": 0.94},
                weight="bold",
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
                RESPONSE_WINDOW_DAYS / 2,
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
            axis.set_xlim(-PRE_SWITCH_DAYS, RESPONSE_WINDOW_DAYS - 1)
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
        bbox_to_anchor=(0.5, 0.928),
        ncol=3,
        frameon=False,
        fontsize=10,
    )
    figure.suptitle("按“是否明确响应切换”重新评价（事后诊断）", fontsize=17, y=0.99)
    figure.text(
        0.5,
        0.954,
        "每条曲线是16个匹配事件的中位数；新方案需在切换后30天内完整出现一次连续5天概率最高。",
        ha="center",
        fontsize=10.5,
    )
    figure.text(
        0.5,
        0.014,
        "支持标准：至少13/16个事件成功，且精确95%区间下限高于50%。该标准在看过当前结果后制定，必须用新种子独立确认。",
        ha="center",
        fontsize=9.5,
    )
    figure.tight_layout(rect=(0.035, 0.05, 0.99, 0.89))
    figure.savefig(path, dpi=190, bbox_inches="tight", facecolor="white")
    plt.close(figure)


def _render_summary_bars(
    path: Path,
    summaries: dict[str, dict[tuple[str, str], dict]],
) -> None:
    figure, axis = plt.subplots(figsize=(12.5, 7.4))
    x = np.arange(len(TRANSITIONS), dtype=np.float64)
    width = 0.34
    for method_offset, (method_name, method_label, _, color) in enumerate(METHODS):
        positions = x + (method_offset - 0.5) * width
        values = np.asarray(
            [summaries[method_name][transition]["observed_response_fraction"] for transition in TRANSITIONS]
        )
        lowers = np.asarray(
            [summaries[method_name][transition]["exact_95_percent_interval_lower"] for transition in TRANSITIONS]
        )
        uppers = np.asarray(
            [summaries[method_name][transition]["exact_95_percent_interval_upper"] for transition in TRANSITIONS]
        )
        bars = axis.bar(
            positions,
            values,
            width=width * 0.90,
            color=color,
            alpha=0.84,
            label=method_label,
            yerr=np.vstack((values - lowers, uppers - values)),
            capsize=5,
            error_kw={"elinewidth": 1.2, "capthick": 1.2},
        )
        for bar, value in zip(bars, values):
            axis.text(
                bar.get_x() + bar.get_width() / 2,
                value + 0.025,
                f"{int(round(value * EVENT_COUNT))}/16",
                ha="center",
                va="bottom",
                fontsize=10,
                weight="bold",
            )
    axis.axhline(
        MINIMUM_OBSERVED_RESPONSE_FRACTION,
        color="#333333",
        linestyle="--",
        linewidth=1.4,
        label="事后标准：至少13/16",
    )
    axis.axhline(
        MINIMUM_EXACT_INTERVAL_LOWER_BOUND,
        color="#777777",
        linestyle=":",
        linewidth=1.2,
        label="精确区间下限要求：高于50%",
    )
    axis.set_xticks(x, [f"真实方案 {old} → {new}" for old, new in TRANSITIONS])
    axis.set_ylabel("30天内明确响应的事件比例")
    axis.set_ylim(0.45, 1.08)
    axis.grid(axis="y", alpha=0.22)
    axis.legend(loc="lower left", fontsize=9.5)
    figure.suptitle("六组比较均满足新的切换响应事后标准", fontsize=17, y=0.97)
    axis.set_title("误差线为精确95%二项分布区间；当前证据为15/16或16/16", fontsize=10.5, pad=12)
    figure.text(
        0.5,
        0.025,
        "这是对现有封存证据的事后重读，不改变原90%整阶段门槛的历史判定；正式采用前需用独立新种子确认。",
        ha="center",
        fontsize=9.5,
    )
    figure.tight_layout(rect=(0.04, 0.07, 0.99, 0.92))
    figure.savefig(path, dpi=190, bbox_inches="tight", facecolor="white")
    plt.close(figure)


def _verify_image(path: Path) -> None:
    image = matplotlib_image.imread(path)
    if image.size == 0 or image.ndim not in (2, 3) or not np.all(np.isfinite(image)):
        raise ValueError(f"image failed decoding: {path.name}")


def render(output_dir: Path) -> dict:
    output_dir = output_dir.resolve()
    if output_dir.exists():
        raise FileExistsError(f"post-hoc response output already exists: {output_dir}")
    source_summary = _verify_sources()
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

    method_events: dict[str, dict[tuple[str, str], np.ndarray]] = {}
    summaries: dict[str, dict[tuple[str, str], dict]] = {}
    all_event_rows = []
    for method_name, _, method_index, _ in METHODS:
        values = _extract_method_probabilities(probabilities, method_index)
        events, metadata = _collect_events(values, schedule, parameter_ids)
        method_events[method_name] = events
        summaries[method_name] = {}
        for transition in TRANSITIONS:
            true_index = int(
                np.flatnonzero(parameter_ids == PARAMETER_ID_BY_SCHEME[transition[1]])[0]
            )
            summary, event_rows = _assess_events(events[transition], true_index, metadata[transition])
            summaries[method_name][transition] = summary
            for row in event_rows:
                all_event_rows.append(
                    {
                        "method": method_name,
                        "old_true_scheme": transition[0],
                        "new_true_scheme": transition[1],
                        **row,
                    }
                )

    all_supported = all(
        summaries[method_name][transition]["post_hoc_response_criterion_met"]
        for method_name, _, _, _ in METHODS
        for transition in TRANSITIONS
    )
    staging = output_dir.with_name(f"{output_dir.name}.incomplete.{uuid4().hex}")
    staging.mkdir(parents=True, exist_ok=False)

    config_snapshot = {
        "analysis_id": ANALYSIS_ID,
        "analysis_type": "post_hoc_readout_no_model_rerun",
        "source_experiment": "g3_ideal_gate_param_switch_v01",
        "source_hashes": EXPECTED_SOURCE_HASHES,
        "question": "Does the posterior clearly respond to a known synthetic truth-parameter switch?",
        "response_definition": {
            "window_days_after_switch": RESPONSE_WINDOW_DAYS,
            "required_consecutive_days_new_true_scheme_is_top_ranked": CONSECUTIVE_TOP_DAYS,
            "the_complete_run_must_end_within_the_window": True,
        },
        "decision_rule": {
            "event_count_per_directed_transition": EVENT_COUNT,
            "minimum_successful_events": MINIMUM_SUCCESSFUL_EVENTS,
            "minimum_observed_response_fraction": MINIMUM_OBSERVED_RESPONSE_FRACTION,
            "confidence_interval": "two_sided_exact_clopper_pearson_95_percent",
            "minimum_exact_interval_lower_bound_strict": MINIMUM_EXACT_INTERVAL_LOWER_BOUND,
        },
        "selection_timing": (
            "Defined after inspecting the sealed probability trajectories; descriptive/post-hoc "
            "only and requires independent fresh-seed confirmation before formal adoption."
        ),
        "fixed_factors": (
            "All sealed states, parameters, forcing, observations, candidate probabilities, "
            "matched blocks, and switch boundaries are unchanged."
        ),
    }
    (staging / "analysis_config_snapshot.json").write_text(
        json.dumps(config_snapshot, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    summary_rows = []
    for method_name, method_label, _, _ in METHODS:
        for transition in TRANSITIONS:
            summary_rows.append(
                {
                    "method": method_name,
                    "method_plain_label": method_label,
                    "old_true_scheme": transition[0],
                    "new_true_scheme": transition[1],
                    **summaries[method_name][transition],
                }
            )
    _write_csv(staging / "posthoc_switch_response_summary.csv", summary_rows)
    _write_csv(staging / "posthoc_switch_response_events.csv", all_event_rows)

    curve_rows = []
    relative_days = np.arange(-PRE_SWITCH_DAYS, RESPONSE_WINDOW_DAYS)
    for method_name, _, _, _ in METHODS:
        for transition in TRANSITIONS:
            events = method_events[method_name][transition]
            for scheme in SCHEME_ORDER:
                parameter_index = int(
                    np.flatnonzero(parameter_ids == PARAMETER_ID_BY_SCHEME[scheme])[0]
                )
                samples = events[..., parameter_index]
                for index, relative_day in enumerate(relative_days):
                    curve_rows.append(
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
    _write_csv(staging / "posthoc_switch_response_curves.csv", curve_rows)

    matplotlib.rcParams["font.sans-serif"] = ["Microsoft YaHei", "SimHei", "DejaVu Sans"]
    matplotlib.rcParams["axes.unicode_minus"] = False
    _render_curves(
        staging / "posthoc_switch_response_curves.png",
        method_events,
        summaries,
        parameter_ids,
    )
    _render_summary_bars(staging / "posthoc_switch_response_summary.png", summaries)
    _verify_image(staging / "posthoc_switch_response_curves.png")
    _verify_image(staging / "posthoc_switch_response_summary.png")

    result_summary = {
        "analysis_id": ANALYSIS_ID,
        "classification": "post_hoc_descriptive_readout_requires_independent_confirmation",
        "source_experiment": "g3_ideal_gate_param_switch_v01",
        "source_scientific_status_unchanged": source_summary["scientific_status"],
        "original_0_90_gate_retroactively_changed": False,
        "new_question": "clear_switch_response_within_30_days",
        "all_six_method_transition_comparisons_supported": all_supported,
        "decision_rule": config_snapshot["decision_rule"],
        "response_definition": config_snapshot["response_definition"],
        "results": {
            method_name: {
                f"{transition[0]}_to_{transition[1]}": summaries[method_name][transition]
                for transition in TRANSITIONS
            }
            for method_name, _, _, _ in METHODS
        },
        "conclusion": (
            "The sealed synthetic evidence clearly supports rapid posterior response to each "
            "parameter-scheme switch under the post-hoc response definition. This does not "
            "establish persistent full-stage correctness or formal unknown change-point detection."
        ),
        "confirmation_requirement": (
            "Freeze this criterion prospectively and repeat it on independent fresh seeds before "
            "using it as a formal scientific gate."
        ),
        "scope_limit": (
            "Synthetic parameter-switch response only; not state accuracy, forecast skill, "
            "real-catchment evidence, or a change-point alarm evaluation."
        ),
    }
    (staging / "summary.json").write_text(
        json.dumps(result_summary, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    registry_entry = {
        "exp_id": ANALYSIS_ID,
        "type": "post_hoc_readout",
        "hypothesis": "The posterior clearly responds to each known truth-parameter switch within 30 days.",
        "base_config": "g3_ideal_gate_param_switch_v01 sealed evidence",
        "changed_factor": "evaluation question and post-hoc response criterion only",
        "fixed_factors": config_snapshot["fixed_factors"],
        "seeds": "no rerun; inherited sealed eight matched blocks",
        "status": "completed_post_hoc_requires_independent_confirmation",
        "run_dir": str(output_dir),
        "metrics_path": str(output_dir / "posthoc_switch_response_summary.csv"),
        "notes": "Original sealed 0.90 full-stage decision remains not_passed.",
    }
    (staging / "registry_entry.json").write_text(
        json.dumps(registry_entry, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    artifact_names = (
        "analysis_config_snapshot.json",
        "posthoc_switch_response_summary.csv",
        "posthoc_switch_response_events.csv",
        "posthoc_switch_response_curves.csv",
        "posthoc_switch_response_curves.png",
        "posthoc_switch_response_summary.png",
        "summary.json",
        "registry_entry.json",
    )
    manifest = {
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "source_directory": str(SOURCE_RESULT),
        "source_hashes": EXPECTED_SOURCE_HASHES,
        "artifacts": {name: _sha256(staging / name) for name in artifact_names},
    }
    (staging / "readout_manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    if output_dir.exists():
        raise FileExistsError("post-hoc response output appeared during rendering")
    staging.rename(output_dir)
    return {**result_summary, "output_directory": str(output_dir)}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    print(json.dumps(render(args.output_dir), ensure_ascii=False, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()

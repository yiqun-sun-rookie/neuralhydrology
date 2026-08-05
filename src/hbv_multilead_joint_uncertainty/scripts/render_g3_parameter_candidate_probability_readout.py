"""Render a traceable parameter-candidate probability readout for sealed G3 evidence."""

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
DEFAULT_OUTPUT = SOURCE_RESULT.with_name(
    "g3_ideal_gate_param_switch_v01_candidate_probability_readout_v01"
)
EXPECTED_EVIDENCE_SHA256 = (
    "77f84d793f18a72972e5af5f2ac4ed767645471e37da31c612ab995ecf4bbf67"
)
METHODS = (
    ("parameter_only", "Parameter uncertainty", 2),
    ("joint_parameter_marginal", "Joint parameter and process uncertainty", 4),
)
CANDIDATE_COLORS = ("#0072B2", "#E69F00", "#009E73")
CANDIDATE_LABELS = {
    "equifinal_diverse_1": "Equifinal parameter set 1",
    "trained_center": "Trained-center parameters",
    "equifinal_diverse_2": "Equifinal parameter set 2",
}


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _event_probabilities(
    probabilities: np.ndarray,
    schedule: np.ndarray,
    parameter_ids: np.ndarray,
    method_index: int,
) -> dict[str, dict[str, np.ndarray | int]]:
    method_values = probabilities[:, :, method_index]
    if method_index == 2:
        method_values = method_values[..., :3]
    elif method_index == 4:
        method_values = method_values[..., :9].reshape(8, 3, 540, 3, 3).sum(axis=-1)
    else:
        raise ValueError("unsupported frozen method index")
    result: dict[str, dict[str, list[np.ndarray] | int]] = {}
    for boundary in (180, 360):
        for truth_index in range(schedule.shape[0]):
            old_index = int(schedule[truth_index, boundary - 1])
            new_index = int(schedule[truth_index, boundary])
            label = f"{parameter_ids[old_index]}_to_{parameter_ids[new_index]}"
            entry = result.setdefault(label, {"true_parameter_index": new_index, "events": []})
            if entry["true_parameter_index"] != new_index:
                raise ValueError("directed transition maps to more than one true parameter")
            for block_index in range(method_values.shape[0]):
                entry["events"].append(
                    method_values[
                        block_index,
                        truth_index,
                        boundary:boundary + 180,
                    ].copy()
                )
    packed: dict[str, dict[str, np.ndarray | int]] = {}
    for label, entry in result.items():
        events = np.stack(entry["events"])
        if events.shape != (16, 180, 3):
            raise ValueError(f"unexpected probability-event shape for {label}: {events.shape}")
        if not np.allclose(np.sum(events, axis=-1), 1.0, atol=1e-12, rtol=0.0):
            raise ValueError(f"candidate probabilities do not sum to one for {label}")
        packed[label] = {
            "true_parameter_index": int(entry["true_parameter_index"]),
            "events": events,
        }
    return packed


def _summarize_events(events: np.ndarray, true_parameter_index: int) -> dict[str, float | int]:
    evaluated = events[:, 5:]
    true_probability = evaluated[..., true_parameter_index]
    other_probability = np.delete(evaluated, true_parameter_index, axis=-1)
    margin = true_probability - np.max(other_probability, axis=-1)
    correct = np.argmax(evaluated, axis=-1) == true_parameter_index
    event_coverage = np.mean(correct, axis=1)
    delay = []
    for event in events:
        event_correct = np.argmax(event, axis=-1) == true_parameter_index
        detected = 180
        for day in range(176):
            if np.all(event_correct[day:day + 5]):
                detected = day
                break
        delay.append(detected)
    return {
        "evaluated_probability_count": int(true_probability.size),
        "true_candidate_argmax_coverage": float(np.mean(correct)),
        "true_candidate_probability_above_half_coverage": float(
            np.mean(true_probability > 0.5)
        ),
        "true_candidate_probability_p10": float(np.quantile(true_probability, 0.10)),
        "true_candidate_probability_p25": float(np.quantile(true_probability, 0.25)),
        "true_candidate_probability_median": float(np.median(true_probability)),
        "true_candidate_probability_p75": float(np.quantile(true_probability, 0.75)),
        "true_candidate_probability_p90": float(np.quantile(true_probability, 0.90)),
        "true_candidate_probability_margin_p10": float(np.quantile(margin, 0.10)),
        "true_candidate_probability_margin_median": float(np.median(margin)),
        "events_with_majority_argmax_coverage": int(np.count_nonzero(event_coverage > 0.5)),
        "event_count": int(len(events)),
        "event_argmax_coverage_minimum": float(np.min(event_coverage)),
        "event_argmax_coverage_p25": float(np.quantile(event_coverage, 0.25)),
        "event_argmax_coverage_median": float(np.median(event_coverage)),
        "event_argmax_coverage_p75": float(np.quantile(event_coverage, 0.75)),
        "event_argmax_coverage_maximum": float(np.max(event_coverage)),
        "median_five_day_stable_detection_delay_days": float(np.median(delay)),
    }


def _write_csv(path: Path, rows: list[dict]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def render(output_dir: Path) -> dict:
    output_dir = output_dir.resolve()
    if output_dir.exists():
        raise FileExistsError(f"candidate-probability readout already exists: {output_dir}")
    evidence_path = SOURCE_RESULT / "evidence.npz"
    evidence_sha256 = _sha256(evidence_path)
    if evidence_sha256 != EXPECTED_EVIDENCE_SHA256:
        raise ValueError("sealed G3 evidence SHA-256 changed")
    frozen_summary = json.loads((SOURCE_RESULT / "summary.json").read_text(encoding="utf-8"))
    if frozen_summary.get("scientific_status") != "not_passed":
        raise ValueError("frozen scientific status differs from the sealed result")
    with np.load(evidence_path, allow_pickle=False) as archive:
        probabilities = np.asarray(archive["method_assimilation_probabilities"], dtype=np.float64)
        schedule = np.asarray(archive["truth_parameter_indices"], dtype=np.int64)
        parameter_ids = np.asarray(archive["parameter_ids"]).astype(str)
    if tuple(parameter_ids) != (
        "equifinal_diverse_1",
        "trained_center",
        "equifinal_diverse_2",
    ):
        raise ValueError("frozen parameter order changed")

    method_events = {
        method_name: _event_probabilities(
            probabilities,
            schedule,
            parameter_ids,
            method_index,
        )
        for method_name, _, method_index in METHODS
    }
    transition_order = tuple(method_events["parameter_only"])
    if any(tuple(method_events[name]) != transition_order for name, _, _ in METHODS):
        raise ValueError("method transition order differs")

    summary_rows = []
    trajectory_rows = []
    summary_by_method: dict[str, dict[str, dict]] = {}
    for method_name, method_label, _ in METHODS:
        summary_by_method[method_name] = {}
        for transition_label in transition_order:
            entry = method_events[method_name][transition_label]
            events = np.asarray(entry["events"], dtype=np.float64)
            true_index = int(entry["true_parameter_index"])
            metrics = _summarize_events(events, true_index)
            summary_by_method[method_name][transition_label] = metrics
            summary_rows.append(
                {
                    "method": method_name,
                    "method_label": method_label,
                    "directed_transition": transition_label,
                    "true_parameter": parameter_ids[true_index],
                    **metrics,
                }
            )
            for candidate_index, candidate_id in enumerate(parameter_ids):
                values = events[..., candidate_index]
                quantiles = np.quantile(values, (0.10, 0.25, 0.50, 0.75, 0.90), axis=0)
                for day in range(180):
                    trajectory_rows.append(
                        {
                            "method": method_name,
                            "directed_transition": transition_label,
                            "day_after_switch_zero_based": day,
                            "candidate": candidate_id,
                            "is_true_candidate": candidate_index == true_index,
                            "probability_p10": quantiles[0, day],
                            "probability_p25": quantiles[1, day],
                            "probability_median": quantiles[2, day],
                            "probability_p75": quantiles[3, day],
                            "probability_p90": quantiles[4, day],
                        }
                    )

    staging = output_dir.with_name(f"{output_dir.name}.incomplete.{uuid4().hex}")
    staging.mkdir(parents=True, exist_ok=False)
    _write_csv(staging / "candidate_probability_summary.csv", summary_rows)
    _write_csv(staging / "candidate_probability_trajectories.csv", trajectory_rows)

    figure, axes = plt.subplots(3, 2, figsize=(16, 12), sharex=True, sharey=True)
    days = np.arange(180)
    for row_index, transition_label in enumerate(transition_order):
        old_id, new_id = transition_label.split("_to_")
        for column_index, (method_name, method_label, _) in enumerate(METHODS):
            axis = axes[row_index, column_index]
            entry = method_events[method_name][transition_label]
            events = np.asarray(entry["events"], dtype=np.float64)
            true_index = int(entry["true_parameter_index"])
            for candidate_index, candidate_id in enumerate(parameter_ids):
                values = events[..., candidate_index]
                median = np.median(values, axis=0)
                linewidth = 2.6 if candidate_index == true_index else 1.5
                axis.plot(
                    days,
                    median,
                    color=CANDIDATE_COLORS[candidate_index],
                    linewidth=linewidth,
                    label=CANDIDATE_LABELS[candidate_id],
                )
                if candidate_index == true_index:
                    lower, upper = np.quantile(values, (0.10, 0.90), axis=0)
                    axis.fill_between(
                        days,
                        lower,
                        upper,
                        color=CANDIDATE_COLORS[candidate_index],
                        alpha=0.16,
                        linewidth=0.0,
                        label="True-candidate 10th–90th percentile",
                    )
            metrics = summary_by_method[method_name][transition_label]
            axis.axhline(0.5, color="#555555", linestyle="--", linewidth=0.9, alpha=0.7)
            axis.axvspan(0, 5, color="#BDBDBD", alpha=0.18)
            axis.text(
                0.985,
                0.965,
                (
                    f"True candidate is largest: {metrics['true_candidate_argmax_coverage']:.1%}\n"
                    f"True probability > 0.5: {metrics['true_candidate_probability_above_half_coverage']:.1%}\n"
                    f"Median true probability: {metrics['true_candidate_probability_median']:.3f}\n"
                    f"Majority-dominant events: {metrics['events_with_majority_argmax_coverage']}/16"
                ),
                transform=axis.transAxes,
                ha="right",
                va="top",
                fontsize=8.5,
                bbox={"facecolor": "white", "edgecolor": "#BBBBBB", "alpha": 0.90},
            )
            if row_index == 0:
                axis.set_title(method_label, fontsize=12)
            if column_index == 0:
                axis.set_ylabel(
                    f"{CANDIDATE_LABELS[old_id]} →\n{CANDIDATE_LABELS[new_id]}\nPosterior probability",
                    fontsize=10,
                )
            if row_index == 2:
                axis.set_xlabel("Days after the true-parameter switch")
            axis.set_xlim(0, 179)
            axis.set_ylim(0, 1.02)
            axis.grid(alpha=0.22, linewidth=0.7)
    handles, labels = axes[0, 0].get_legend_handles_labels()
    unique = dict(zip(labels, handles))
    figure.legend(
        unique.values(),
        unique.keys(),
        loc="upper center",
        bbox_to_anchor=(0.5, 0.935),
        ncol=4,
        frameon=False,
        fontsize=9,
    )
    figure.suptitle(
        "Sealed three-stage experiment: posterior probabilities of the three parameter candidates\n"
        "Lines are event-wise medians; shading is the true candidate's 10th–90th percentile",
        fontsize=14,
        y=0.992,
    )
    figure.text(
        0.5,
        0.015,
        "Grey interval: five adaptation days excluded by the frozen scoring rule. "
        "The 0.5 line is a majority-probability reference, not a new pass threshold.",
        ha="center",
        fontsize=9,
    )
    figure.tight_layout(rect=(0.03, 0.05, 0.99, 0.89))
    figure_path = staging / "candidate_probability_trajectories.png"
    figure.savefig(figure_path, dpi=190, bbox_inches="tight")
    plt.close(figure)
    image = matplotlib_image.imread(figure_path)
    if image.size == 0 or image.ndim not in (2, 3) or not np.all(np.isfinite(image)):
        raise ValueError("candidate probability figure failed decoding")

    result_summary = {
        "classification": "readout_only_no_new_scientific_gate",
        "source_experiment": "g3_ideal_gate_param_switch_v01",
        "source_scientific_status": frozen_summary["scientific_status"],
        "source_identification_passed_all_three_stages": frozen_summary[
            "identification_passed_all_three_stages"
        ],
        "evidence_sha256": evidence_sha256,
        "adaptation_days_excluded": 5,
        "evaluated_days_per_event": 175,
        "matched_events_per_directed_transition": 16,
        "new_threshold_applied": False,
        "interpretation": (
            "Continuous dominance readout only. The frozen 0.90 gate is not changed, "
            "and this readout does not convert the sealed not-passed decision into a pass."
        ),
        "metrics": summary_by_method,
    }
    (staging / "summary.json").write_text(
        json.dumps(result_summary, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    artifact_names = (
        "candidate_probability_trajectories.png",
        "candidate_probability_summary.csv",
        "candidate_probability_trajectories.csv",
        "summary.json",
    )
    manifest = {
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "source_evidence": str(evidence_path),
        "source_evidence_sha256": evidence_sha256,
        "source_summary": str(SOURCE_RESULT / "summary.json"),
        "source_summary_sha256": _sha256(SOURCE_RESULT / "summary.json"),
        "artifacts": {name: _sha256(staging / name) for name in artifact_names},
    }
    (staging / "readout_manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    if output_dir.exists():
        raise FileExistsError("candidate-probability readout directory appeared during rendering")
    staging.rename(output_dir)
    return {**result_summary, "output_directory": str(output_dir)}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    print(json.dumps(render(args.output_dir), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()

"""Plot auditable aggregate true-candidate probabilities for the 01A design."""

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
    "A": {
        "title": "METHOD A  Grouped states + direct clipping",
        "color": "#5B5B5B",
    },
    "B": {
        "title": "METHOD B  Full interaction + direct clipping",
        "color": "#D55E00",
    },
    "C": {
        "title": "METHOD C  Full interaction + conservative mapping",
        "color": "#0072B2",
    },
}
TRUTH_FACTORS = {
    0: 1.0,
    1: 0.5,
    2: 2.0,
}
TRUTH_LABELS = {
    0: "Center 1.0x",
    1: "Half 0.5x",
    2: "Double 2.0x",
}


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def combined_probability_hash(paths: list[Path], root: Path) -> str:
    digest = hashlib.sha256()
    for path in sorted(paths):
        digest.update(path.relative_to(root).as_posix().encode("utf-8"))
        digest.update(b"\0")
        with path.open("rb") as handle:
            for block in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(block)
    return digest.hexdigest()


def load_true_probability_matrix(
    probability_directory: Path,
) -> tuple[np.ndarray, np.ndarray, np.ndarray, list[Path]]:
    paths = sorted(probability_directory.glob("*.npz"))
    if len(paths) != 24:
        raise ValueError(
            f"expected 24 probability files in {probability_directory}, got {len(paths)}"
        )
    true_probabilities = []
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
            raise ValueError("truth-stage metadata differs within an arm")
        true_probabilities.append(
            probabilities[np.arange(len(probabilities)), truth]
        )
    return (
        np.asarray(true_probabilities),
        reference_rotation,
        np.array(reference_stage_days, dtype=np.int64),
        paths,
    )


def create_probability_figure(
    output_root: str | Path,
    artifact_tag: str = "",
) -> dict:
    root = Path(output_root).resolve()
    verification = root / "verification"
    if not verification.is_dir():
        raise FileNotFoundError("independent verification directory is missing")
    summary_path = verification / "comparison_summary.json"
    report = json.loads(summary_path.read_text(encoding="utf-8"))
    if report.get("verification_status") != "passed" or report.get("task_count") != 72:
        raise ValueError("independent verification did not pass all 72 tasks")

    if artifact_tag and not artifact_tag.replace("_", "").isalnum():
        raise ValueError("artifact_tag may contain only letters, digits, and underscores")
    suffix = f"_{artifact_tag}" if artifact_tag else ""
    csv_path = verification / f"probability_trajectory_summary{suffix}.csv"
    figure_path = verification / f"probability_trajectory_comparison{suffix}.png"
    manifest_path = verification / f"probability_trajectory_figure_manifest{suffix}.json"
    for path in (csv_path, figure_path, manifest_path):
        if path.exists():
            raise FileExistsError(f"figure artifact already exists: {path}")

    rows = []
    matrices: dict[str, np.ndarray] = {}
    all_probability_paths: list[Path] = []
    common_rotation = None
    common_stage_days = None
    for arm_id in ("A", "B", "C"):
        matrix, rotation, stage_days_array, paths = load_true_probability_matrix(
            root / "arms" / arm_id / "probs"
        )
        stage_days = int(stage_days_array.item())
        if common_rotation is None:
            common_rotation = rotation
            common_stage_days = stage_days
        elif not np.array_equal(rotation, common_rotation) or stage_days != common_stage_days:
            raise ValueError("truth-stage metadata differs across arms")
        matrices[arm_id] = matrix
        all_probability_paths.extend(paths)
        for day in range(matrix.shape[1]):
            values = matrix[:, day]
            rows.append(
                {
                    "arm_id": arm_id,
                    "day_index": day,
                    "stage_index": day // stage_days,
                    "stage_day": day % stage_days + 1,
                    "true_member": int(common_rotation[day // stage_days]),
                    "mean_true_probability": float(np.mean(values)),
                    "median_true_probability": float(np.median(values)),
                    "q25_true_probability": float(np.quantile(values, 0.25)),
                    "q75_true_probability": float(np.quantile(values, 0.75)),
                }
            )
    summary = pd.DataFrame(rows)
    summary.to_csv(csv_path, index=False)

    fig, all_axes = plt.subplots(
        4,
        1,
        figsize=(14, 10),
        sharex=True,
        gridspec_kw={"height_ratios": [0.72, 2.25, 2.25, 2.25]},
    )
    truth_axis = all_axes[0]
    axes = all_axes[1:]
    x = np.arange(1, matrices["A"].shape[1] + 1)

    truth_factors = np.repeat(
        [TRUTH_FACTORS[int(member)] for member in common_rotation],
        common_stage_days,
    )
    truth_axis.step(
        x,
        truth_factors,
        where="post",
        color="#8E0152",
        lw=2.8,
        label="Pre-set synthetic truth",
    )
    for stage_index, member in enumerate(common_rotation):
        start = stage_index * common_stage_days + 1
        end = (stage_index + 1) * common_stage_days
        midpoint = (start + end) / 2
        factor = TRUTH_FACTORS[int(member)]
        truth_axis.text(
            midpoint,
            factor + (-0.23 if factor == 2.0 else 0.16),
            TRUTH_LABELS[int(member)],
            ha="center",
            va="center",
            fontsize=8,
            fontweight="bold",
            color="#4A002B",
        )
        if stage_index > 0:
            truth_axis.axvline(start, color="#666666", lw=0.7, ls="--", alpha=0.7)
    truth_axis.set_ylim(0.28, 2.28)
    truth_axis.set_yticks([0.5, 1.0, 2.0])
    truth_axis.set_ylabel("Pre-set truth\nparFC factor")
    truth_axis.set_title(
        "PRE-SET SYNTHETIC TRUTH PARAMETER (line; not a method)",
        loc="left",
        fontsize=10,
        fontweight="bold",
    )
    truth_axis.grid(axis="y", color="#D9D9D9", lw=0.5, alpha=0.7)
    truth_axis.legend(loc="upper right", frameon=False, fontsize=8)

    for axis, arm_id in zip(axes, ("A", "B", "C")):
        matrix = matrices[arm_id]
        style = ARM_STYLE[arm_id]
        median = np.median(matrix, axis=0)
        lower = np.quantile(matrix, 0.25, axis=0)
        upper = np.quantile(matrix, 0.75, axis=0)
        for stage_index, member in enumerate(common_rotation):
            start = stage_index * common_stage_days + 1
            if stage_index > 0:
                axis.axvspan(start, start + 29, color="#BDBDBD", alpha=0.12, lw=0)
                axis.axvline(start, color="#666666", lw=0.7, ls="--", alpha=0.7)
        axis.fill_between(x, lower, upper, color=style["color"], alpha=0.18, lw=0)
        axis.plot(x, median, color=style["color"], lw=1.2)
        axis.axhline(0.5, color="#222222", lw=0.8, ls=":")
        axis.set_ylim(0.0, 1.0)
        axis.set_yticks(np.linspace(0.0, 1.0, 6))
        axis.set_ylabel("True-candidate\nprobability")
        axis.set_title(style["title"], loc="left", fontsize=11, fontweight="bold")
        axis.grid(axis="y", color="#D9D9D9", lw=0.5, alpha=0.7)
    axes[-1].set_xlabel("Simulation day; gray bands mark the registered 30-day response windows")
    fig.suptitle(
        "CAMELS-US parFC switch diagnostic: median and interquartile range across 24 basin-seed tasks",
        fontsize=13,
        fontweight="bold",
    )
    fig.text(
        0.5,
        0.947,
        "The magenta step line is the pre-set truth. A, B, and C are evaluated methods; none was pre-set as optimal.",
        ha="center",
        fontsize=10,
        fontweight="bold",
        color="#222222",
    )
    fig.text(
        0.5,
        0.01,
        "Exploratory 12-basin design sample, seeds 0-1. Aggregate curves are descriptive and are not the event pass rule.",
        ha="center",
        fontsize=9,
        color="#444444",
    )
    fig.tight_layout(rect=(0.04, 0.045, 0.995, 0.925))
    fig.savefig(figure_path, dpi=180, bbox_inches="tight")
    plt.close(fig)

    manifest = {
        "experiment_id": report["experiment_id"],
        "verification_status": report["verification_status"],
        "figure_scope": "descriptive exploratory probability trajectories only",
        "annotation_contract": {
            "magenta_step_line": "pre-set synthetic truth parFC multiplier",
            "method_panels": "evaluated methods; no method was pre-set as optimal",
        },
        "aggregation": "daily median and 25th-75th percentiles across 24 basin-seed tasks per arm",
        "probability_file_count": len(all_probability_paths),
        "probability_file_set_sha256": combined_probability_hash(
            all_probability_paths, root
        ),
        "verification_summary_sha256": sha256_file(summary_path),
        "summary_csv": csv_path.name,
        "summary_csv_sha256": sha256_file(csv_path),
        "figure": figure_path.name,
        "figure_sha256": sha256_file(figure_path),
        "plot_script": Path(__file__).resolve().relative_to(
            Path(__file__).resolve().parents[2]
        ).as_posix(),
        "plot_script_sha256": sha256_file(Path(__file__).resolve()),
    }
    manifest_path.write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return manifest


def _parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-root", required=True)
    parser.add_argument("--artifact-tag", default="")
    return parser.parse_args(argv)


def main(argv=None) -> int:
    arguments = _parse_args(argv)
    manifest = create_probability_figure(
        arguments.output_root,
        artifact_tag=arguments.artifact_tag,
    )
    print(json.dumps(manifest, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

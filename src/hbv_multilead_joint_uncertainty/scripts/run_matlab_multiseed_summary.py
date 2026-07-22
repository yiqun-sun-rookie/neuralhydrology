"""Summarize the multi-seed MATLAB rerun and seal matlab_multiseed_params_v01.

Reads every formal seed_<seed>.mat produced by multiseed_params_driver.m from
the staging directory, computes the six frozen anchor metrics per seed with the
alignment round's anchor implementation, reduces them under the pre-frozen
summary rules (quantiles + censoring + rng(1) position rule + stable<=10
bridge), writes the declared artifacts into the staging directory, and seals it.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import sys
from pathlib import Path

import numpy as np
import scipy.io as sio

REPO_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO_ROOT / "src"))

from hbv_multilead_joint_uncertainty.matlab_multiseed_summary import (  # noqa: E402
    bridge_fraction,
    seed_anchor_row,
    summarize_metric,
)
from hbv_multilead_joint_uncertainty.scripts.run_candidate_likelihood_identifiability import (  # noqa: E402
    _checksums_for_directory,
    _environment,
    _json_write,
)
from hbv_multilead_joint_uncertainty.scripts.run_three_stage_switching_validation import (  # noqa: E402
    _replace_directory_with_retries,
)
from hbv_multilead_joint_uncertainty.scripts.run_walrus_imm_alignment import (  # noqa: E402
    _anchor_metrics,
    _sha256,
)

FORMAL_SEEDS = list(range(3001001, 3001025))
BRIDGE_BUDGET = 10
METRIC_KEYS = [
    "phase1_true_filter_mean_prob",
    "phase1_first_top_cycle",
    "phase1_stable_top_cycle",
    "phase2_true_filter_mean_prob",
    "phase2_first_top_cycle",
    "phase2_stable_top_cycle",
]
PUBLISHED_MAT = Path(
    "G:/github/pycharm/projects/paper-imm-variable-params/synthetic/outputs/mukf/params/10/updated_results_params_10.mat"
)
PUBLISHED_MAT_SHA256 = "fd080ce0fa0f4b53ca61e19060dfba6995f94f9b53fd62cb0f8681169bec609f"


def _reference_anchors() -> dict:
    if _sha256(PUBLISHED_MAT) != PUBLISHED_MAT_SHA256:
        raise RuntimeError("published .mat hash mismatch")
    raw = sio.loadmat(str(PUBLISHED_MAT), variable_names=["imm_probs", "t1_2", "t2_3"])
    anchors = _anchor_metrics(
        np.asarray(raw["imm_probs"], dtype=np.float64),
        {
            "t1_2": int(np.asarray(raw["t1_2"]).reshape(-1)[0]),
            "t2_3": int(np.asarray(raw["t2_3"]).reshape(-1)[0]),
        },
    )
    return {
        f"{phase}_{metric}": anchors[phase][metric]
        for phase in ("phase1", "phase2")
        for metric in ("true_filter_mean_prob", "first_top_cycle", "stable_top_cycle")
    }


def _load_seed_rows(seeds_dir: Path) -> tuple[list[dict], list[dict]]:
    rows, issues = [], []
    for seed in FORMAL_SEEDS:
        mat_path = seeds_dir / f"seed_{seed}.mat"
        error_path = seeds_dir / f"seed_{seed}.error.txt"
        if error_path.exists():
            issues.append({"seed": seed, "issue": "driver_error", "detail": error_path.name})
        if not mat_path.exists():
            issues.append({"seed": seed, "issue": "missing_mat"})
            continue
        raw = sio.loadmat(str(mat_path), variable_names=["imm_probs", "t1_2", "t2_3", "seed"])
        stored_seed = int(np.asarray(raw["seed"]).reshape(-1)[0])
        if stored_seed != seed:
            raise RuntimeError(f"seed mismatch in {mat_path.name}: stored {stored_seed}")
        rows.append(
            seed_anchor_row(
                seed=seed,
                imm_probs=np.asarray(raw["imm_probs"], dtype=np.float64),
                t1_2=int(np.asarray(raw["t1_2"]).reshape(-1)[0]),
                t2_3=int(np.asarray(raw["t2_3"]).reshape(-1)[0]),
            )
        )
    return rows, issues


def run(config_path: Path, staging_dir: Path, output_dir: Path) -> dict:
    started_at = dt.datetime.now(dt.timezone.utc).isoformat()
    config_bytes = config_path.read_bytes()
    seeds_dir = staging_dir / "seeds"
    if output_dir.exists():
        raise RuntimeError(f"output already exists: {output_dir}")

    rows, issues = _load_seed_rows(seeds_dir)
    if not rows:
        raise RuntimeError("no formal seed outputs found")
    reference = _reference_anchors()
    divergent = [row for row in rows if row["divergent"]]

    summaries = {}
    for key in METRIC_KEYS:
        values = [row[key] for row in rows if not row["divergent"]]
        summaries[key] = summarize_metric(values, reference[key])
    bridges = {
        phase: bridge_fraction(
            [row[f"{phase}_stable_top_cycle"] for row in rows if not row["divergent"]],
            budget=BRIDGE_BUDGET,
        )
        for phase in ("phase1", "phase2")
    }

    with open(staging_dir / "per_seed_anchors.csv", "w", encoding="utf-8", newline="\n") as handle:
        header = ["seed", "divergent"] + METRIC_KEYS
        handle.write(",".join(header) + "\n")
        for row in rows:
            handle.write(",".join(str(row[column]) for column in header) + "\n")

    with open(staging_dir / "anchor_distribution_summary.csv", "w", encoding="utf-8", newline="\n") as handle:
        columns = [
            "metric", "n_total", "n_observed", "n_censored", "censored_fraction",
            "min", "q25", "median", "q75", "max",
            "reference", "reference_call", "reference_quantile_note",
        ]
        handle.write(",".join(columns) + "\n")
        for key in METRIC_KEYS:
            summary = summaries[key]
            values = [key] + [summary[column] for column in columns[1:-1]] + [
                (summary["reference_quantile_note"] or "").replace(",", ";")
            ]
            handle.write(",".join("" if value is None else str(value) for value in values) + "\n")

    report = {
        "experiment": "matlab_multiseed_params_v01",
        "n_formal_seeds_expected": len(FORMAL_SEEDS),
        "n_seed_files": len(rows),
        "n_divergent": len(divergent),
        "issues": issues,
        "reference_anchors_rng1": reference,
        "metric_summaries": summaries,
        "bridge_fraction_stable_top_within_10": bridges,
        "started_at": started_at,
        "ended_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "config_sha256": hashlib.sha256(config_bytes).hexdigest(),
    }
    _json_write(staging_dir / "summary.json", report)

    lines = [
        "# 多种子重跑结果：matlab_multiseed_params_v01",
        "",
        f"- 正式种子 {len(FORMAL_SEEDS)} 个，成功 {len(rows)} 个，发散 {len(divergent)} 个，异常项 {len(issues)} 条",
        f"- 稳定登顶循环 ≤ {BRIDGE_BUDGET} 的种子比例：阶段1 {bridges['phase1']:.3f}，阶段2 {bridges['phase2']:.3f}",
        "",
        "| 指标 | n | 删失 | min | 中位 | max | rng(1) 参考 | 位置判定 |",
        "|---|---|---|---|---|---|---|---|",
    ]
    for key in METRIC_KEYS:
        summary = summaries[key]
        fmt = (lambda v: "—" if v is None else (f"{v:.4f}" if isinstance(v, float) else str(v)))
        lines.append(
            f"| {key} | {summary['n_observed']} | {summary['n_censored']} | {fmt(summary['min'])} "
            f"| {fmt(summary['median'])} | {fmt(summary['max'])} | {fmt(summary['reference'])} "
            f"| {summary['reference_call']}{'；' + summary['reference_quantile_note'] if summary['reference_quantile_note'] else ''} |"
        )
    lines += ["", "分位数细节见 anchor_distribution_summary.csv；逐种子值见 per_seed_anchors.csv。"]
    (staging_dir / "final_report.md").write_text("\n".join(lines) + "\n", encoding="utf-8")

    (staging_dir / "config_snapshot.json").write_bytes(config_bytes)
    _json_write(staging_dir / "environment.json", _environment(REPO_ROOT, started_at))
    _json_write(staging_dir / "checksums.json", _checksums_for_directory(staging_dir))
    _replace_directory_with_retries(staging_dir, output_dir)
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--config",
        type=Path,
        default=REPO_ROOT / "src/hbv_multilead_joint_uncertainty/configs/matlab_multiseed_params_v01.json",
    )
    parser.add_argument(
        "--staging",
        type=Path,
        default=REPO_ROOT / "results/23_hbv_multilead_joint_uncertainty/matlab_multiseed_params_v01.incomplete",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=REPO_ROOT / "results/23_hbv_multilead_joint_uncertainty/matlab_multiseed_params_v01",
    )
    arguments = parser.parse_args()
    report = run(arguments.config, arguments.staging, arguments.output)
    print(json.dumps({
        "seeds": report["n_seed_files"],
        "bridge": report["bridge_fraction_stable_top_within_10"],
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()

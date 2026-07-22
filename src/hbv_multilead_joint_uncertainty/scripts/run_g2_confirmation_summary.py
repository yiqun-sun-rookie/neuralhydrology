"""Compare boundary-cell confirmations with the development curve and seal.

Frozen rules (design doc section 4): boundary cells were selected
deterministically; confirmation ran once on fresh seeds; a confirmation that
matches development finalizes the row boundary, a contradiction downgrades the
row to an interval ("目前无法确定"), and no reruns are permitted either way.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import sys
from pathlib import Path

import numpy as np

REPO_ROOT = Path(__file__).resolve().parents[3]
if str(REPO_ROOT / "src") not in sys.path:
    sys.path.insert(0, str(REPO_ROOT / "src"))

from hbv_multilead_joint_uncertainty.g2_curve_design import (  # noqa: E402
    ADAPTATION_DAYS,
    BUDGET_STAGE_LENGTHS,
    SPACING_MULTIPLIERS,
    confirmation_experiment_id,
)
from hbv_multilead_joint_uncertainty.g2_curve_summary import (  # noqa: E402
    identification_time_cycles,
    summarize_identification_times,
)
from hbv_multilead_joint_uncertainty.scripts.run_candidate_likelihood_identifiability import (  # noqa: E402
    _checksums_for_directory,
    _environment,
    _json_write,
)
from hbv_multilead_joint_uncertainty.scripts.run_synthetic_truth_validation import (  # noqa: E402
    _sha256,
)
from hbv_multilead_joint_uncertainty.scripts.run_three_stage_switching_validation import (  # noqa: E402
    _replace_directory_with_retries,
)

RESULTS_ROOT = REPO_ROOT / "results/23_hbv_multilead_joint_uncertainty"
CURVE_DIR = RESULTS_ROOT / "g2_identification_time_curve_dev_v01"


def _load_confirmation(stage_length: int, multiplier: float, selection_rule: str) -> dict:
    experiment_id = confirmation_experiment_id(multiplier, stage_length)
    directory = RESULTS_ROOT / experiment_id
    summary = json.loads((directory / "summary.json").read_text(encoding="utf-8"))
    evaluation = json.loads(
        (directory / "scientific_evaluation.json").read_text(encoding="utf-8")
    )
    config_path = (
        REPO_ROOT / "src/hbv_multilead_joint_uncertainty/configs" / f"{experiment_id}.json"
    )
    if summary["integrity_status"] != "passed":
        raise RuntimeError(f"{experiment_id}: integrity gate not passed")
    if summary["dataset_role"] != "confirmation":
        raise RuntimeError(f"{experiment_id}: dataset_role must be confirmation")
    if summary["config_sha256"] != hashlib.sha256(config_path.read_bytes()).hexdigest():
        raise RuntimeError(f"{experiment_id}: sealed config differs from configs/ file")
    with np.load(directory / "evidence.npz") as evidence:
        first_stable = np.asarray(
            evidence["first_stable_cumulative_rank_one_day"], dtype=np.int64
        )
        adaptation = int(evidence["adaptation_days"])
    if adaptation != ADAPTATION_DAYS:
        raise RuntimeError(f"{experiment_id}: unexpected adaptation days")
    pooled = np.concatenate(
        [
            identification_time_cycles(
                first_stable[:, :, stage_index], adaptation_days=adaptation
            ).reshape(-1)
            for stage_index in (1, 2)
        ]
    )
    return {
        "experiment_id": experiment_id,
        "stage_length": int(stage_length),
        "multiplier": float(multiplier),
        "selection_rule": selection_rule,
        "passed": bool(evaluation["switching_stages_passed"]),
        "identification_time_pooled": summarize_identification_times(pooled),
        "evidence_sha256": _sha256(directory / "evidence.npz"),
    }


def run(output_dir: Path) -> dict:
    started_at = dt.datetime.now(dt.timezone.utc).isoformat()
    output = output_dir.resolve()
    staging = output.with_name(output.name + ".incomplete")
    if output.exists() or staging.exists():
        raise FileExistsError("refusing to overwrite existing evidence")

    curve = json.loads((CURVE_DIR / "curve_summary.json").read_text(encoding="utf-8"))
    rows = {}
    confirmations = []
    for stage_length in BUDGET_STAGE_LENGTHS:
        development_row = curve["axis_checks"]["budget_rows"][str(stage_length)]
        boundary = development_row["boundary_cells"]
        row_confirmations = {}
        for rule, expected_passed in (
            ("smallest_passing_multiplier", True),
            ("largest_failing_multiplier", False),
        ):
            multiplier = boundary[rule]
            if multiplier is None:
                continue
            record = _load_confirmation(stage_length, float(multiplier), rule)
            record["development_verdict"] = expected_passed
            record["confirms_development"] = record["passed"] == expected_passed
            confirmations.append(record)
            row_confirmations[rule] = record
        contradictions = [
            record for record in row_confirmations.values() if not record["confirms_development"]
        ]
        smallest_passing = boundary["smallest_passing_multiplier"]
        largest_failing = boundary["largest_failing_multiplier"]
        if contradictions:
            conclusion = (
                "目前无法确定（确认与开发矛盾，按冻结规则只给区间，禁止重跑）："
                f"矛盾格 = {[record['experiment_id'] for record in contradictions]}"
            )
            status = "undetermined_interval_only"
        elif smallest_passing is None:
            conclusion = (
                f"该行网格内全失败已确认：最大倍率 m={largest_failing} 仍失败，"
                f"通过边界（若存在）在 m>{largest_failing}，网格外"
            )
            status = "confirmed_all_fail_within_grid"
        else:
            lower = largest_failing if largest_failing is not None else "网格下端外"
            conclusion = (
                f"边界已确认：最小通过 m={smallest_passing}，最大失败 m={lower}；"
                f"通过边界位于 ({lower}, {smallest_passing}] 区间"
            )
            status = "confirmed"
        rows[str(stage_length)] = {
            "development_boundary_cells": boundary,
            "confirmations": {
                rule: {
                    "experiment_id": record["experiment_id"],
                    "passed": record["passed"],
                    "confirms_development": record["confirms_development"],
                }
                for rule, record in row_confirmations.items()
            },
            "status": status,
            "conclusion": conclusion,
        }

    report = {
        "artifact": "g2_identification_time_curve_conf_v01",
        "design_doc": "docs/plans/2026-07-22-g2-identification-time-curve-design.md",
        "development_curve_sha256": _sha256(CURVE_DIR / "curve_summary.json"),
        "confirmation_cells": confirmations,
        "row_conclusions": rows,
        "all_confirmations_match_development": all(
            record["confirms_development"] for record in confirmations
        ),
        "started_at_utc": started_at,
        "ended_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
    }

    staging.mkdir(parents=True, exist_ok=False)
    _json_write(staging / "confirmation_summary.json", report)
    lines = [
        "# G2 边界格确认（最终）：g2_identification_time_curve_conf_v01",
        "",
        "确认种子只跑一次，结果无论方向均为最终（冻结规则）。",
        "",
        "| L | 确认格 | 开发判定 | 确认判定 | 一致 | 行结论 |",
        "|---|---|---|---|---|---|",
    ]
    for stage_length in BUDGET_STAGE_LENGTHS:
        row = rows[str(stage_length)]
        if not row["confirmations"]:
            lines.append(f"| {stage_length} | — | — | — | — | {row['conclusion']} |")
            continue
        for rule, record in row["confirmations"].items():
            full = next(
                r for r in confirmations if r["experiment_id"] == record["experiment_id"]
            )
            lines.append(
                f"| {stage_length} | m={full['multiplier']} ({rule.split('_')[0]}) "
                f"| {'PASS' if full['development_verdict'] else 'fail'} "
                f"| {'PASS' if record['passed'] else 'fail'} "
                f"| {'是' if record['confirms_development'] else '否'} "
                f"| {row['conclusion']} |"
            )
    (staging / "final_report.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    _json_write(staging / "environment.json", _environment(REPO_ROOT, started_at))
    _json_write(staging / "checksums.json", _checksums_for_directory(staging))
    _replace_directory_with_retries(staging, output)
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        type=Path,
        default=RESULTS_ROOT / "g2_identification_time_curve_conf_v01",
    )
    arguments = parser.parse_args()
    report = run(arguments.output)
    print(
        json.dumps(
            {
                "all_match": report["all_confirmations_match_development"],
                "rows": {
                    key: value["status"] for key, value in report["row_conclusions"].items()
                },
            },
            ensure_ascii=False,
            indent=2,
        )
    )


if __name__ == "__main__":
    main()

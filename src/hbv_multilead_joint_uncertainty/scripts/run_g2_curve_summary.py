"""Summarize the twenty sealed G2 development cells and seal the curve.

For every grid cell this reads the sealed evidence (first stable cumulative
rank-one day, three-criteria verdict, integrity status), reduces it under the
frozen rules (T = adaptation + first stable day with censoring, quantile
summary, per-row boundary cells, preregistered monotonicity checks on both
axes), and seals g2_identification_time_curve_dev_v01.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd

REPO_ROOT = Path(__file__).resolve().parents[3]
if str(REPO_ROOT / "src") not in sys.path:
    sys.path.insert(0, str(REPO_ROOT / "src"))

from hbv_multilead_joint_uncertainty.g2_curve_design import (  # noqa: E402
    ADAPTATION_DAYS,
    BUDGET_STAGE_LENGTHS,
    SPACING_MULTIPLIERS,
    development_experiment_id,
    grid_cells,
)
from hbv_multilead_joint_uncertainty.g2_curve_summary import (  # noqa: E402
    identification_time_cycles,
    monotonicity_violations,
    select_boundary_cells,
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
SWITCHING_STAGE_INDICES = (1, 2)


def _load_cell(cell: dict) -> dict:
    experiment_id = development_experiment_id(cell["multiplier"], cell["stage_length"])
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
    if summary["config_sha256"] != hashlib.sha256(config_path.read_bytes()).hexdigest():
        raise RuntimeError(f"{experiment_id}: sealed config differs from configs/ file")
    with np.load(directory / "evidence.npz") as evidence:
        first_stable = np.asarray(
            evidence["first_stable_cumulative_rank_one_day"], dtype=np.int64
        )
        adaptation = int(evidence["adaptation_days"])
    if adaptation != ADAPTATION_DAYS:
        raise RuntimeError(f"{experiment_id}: unexpected adaptation days {adaptation}")

    times = {}
    stage_arrays = []
    for stage_index in SWITCHING_STAGE_INDICES:
        values = identification_time_cycles(
            first_stable[:, :, stage_index], adaptation_days=adaptation
        )
        stage_arrays.append(values.reshape(-1))
        times[f"stage{stage_index + 1}"] = summarize_identification_times(values)
    times["pooled"] = summarize_identification_times(np.concatenate(stage_arrays))
    return {
        "experiment_id": experiment_id,
        "cell_number": int(cell["cell_number"]),
        "multiplier": float(cell["multiplier"]),
        "stage_length": int(cell["stage_length"]),
        "scoring_days": int(cell["stage_length"]) - ADAPTATION_DAYS,
        "passed": bool(evaluation["switching_stages_passed"]),
        "scientific_status": str(evaluation["scientific_status"]),
        "stage_criteria": [
            {
                "stage_number": row["stage_number"],
                "stable_identifiable_fraction": row["stable_identifiable_fraction"],
                "stable_fraction_block_bootstrap_lower": row[
                    "stable_fraction_block_bootstrap_lower"
                ],
                "median_final_margin": row[
                    "median_final_true_vs_best_wrong_cumulative_log_likelihood_margin"
                ],
                "stage_passed": row["stage_passed"],
            }
            for row in evaluation["stage_results"]
            if row["stage_number"] in (2, 3)
        ],
        "identification_time_cycles": times,
        "evidence_sha256": _sha256(directory / "evidence.npz"),
    }


def _axis_checks(cells: list[dict]) -> dict:
    rows = {}
    for stage_length in BUDGET_STAGE_LENGTHS:
        row = [cell for cell in cells if cell["stage_length"] == stage_length]
        rows[str(stage_length)] = {
            "verdicts": {str(cell["multiplier"]): cell["passed"] for cell in row},
            "boundary_cells": select_boundary_cells(row),
            "monotonicity_violations_in_multiplier": monotonicity_violations(row),
        }
    columns = {}
    for multiplier in SPACING_MULTIPLIERS:
        column = [
            {"multiplier": float(cell["stage_length"]), "passed": cell["passed"]}
            for cell in cells
            if cell["multiplier"] == multiplier
        ]
        columns[str(multiplier)] = {
            "monotonicity_violations_in_budget": [
                {
                    "from_stage_length": violation["from_multiplier"],
                    "to_stage_length": violation["to_multiplier"],
                }
                for violation in monotonicity_violations(column)
            ]
        }
    return {"budget_rows": rows, "multiplier_columns": columns}


def _curve_rows(cells: list[dict]) -> list[dict]:
    rows = []
    for cell in cells:
        for scope, summary in cell["identification_time_cycles"].items():
            rows.append(
                {
                    "experiment_id": cell["experiment_id"],
                    "cell_number": cell["cell_number"],
                    "spacing_multiplier": cell["multiplier"],
                    "stage_length_days": cell["stage_length"],
                    "scoring_days": cell["scoring_days"],
                    "scope": scope,
                    "passed_three_criteria": cell["passed"],
                    **summary,
                }
            )
    return rows


def run(output_dir: Path) -> dict:
    started_at = dt.datetime.now(dt.timezone.utc).isoformat()
    output = output_dir.resolve()
    staging = output.with_name(output.name + ".incomplete")
    if output.exists() or staging.exists():
        raise FileExistsError("refusing to overwrite existing evidence")

    cells = [_load_cell(cell) for cell in grid_cells()]
    axes = _axis_checks(cells)
    report = {
        "artifact": "g2_identification_time_curve_dev_v01",
        "design_doc": "docs/plans/2026-07-22-g2-identification-time-curve-design.md",
        "identification_time_definition": (
            "T = adaptation days (5) + first stable cumulative rank-one scoring day, "
            "in assimilation cycles after the switch; censored when never stably top"
        ),
        "cells": cells,
        "axis_checks": axes,
        "started_at_utc": started_at,
        "ended_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
    }

    staging.mkdir(parents=True, exist_ok=False)
    _json_write(staging / "curve_summary.json", report)
    pd.DataFrame(_curve_rows(cells)).to_csv(
        staging / "identification_time_curve.csv", index=False, lineterminator="\n"
    )
    lines = [
        "# G2 认出时间曲线（开发）：g2_identification_time_curve_dev_v01",
        "",
        "T = 切换后稳定登顶所需同化循环数（适应 5 日 + 首个稳定登顶评分日；从未稳定登顶记删失）。",
        "逐格判定 = 冻结三件套（阶段 2、3 同时通过）。",
        "",
        "| L\\m | " + " | ".join(str(m) for m in SPACING_MULTIPLIERS) + " |",
        "|---|" + "---|" * len(SPACING_MULTIPLIERS),
    ]
    for stage_length in BUDGET_STAGE_LENGTHS:
        entries = []
        for multiplier in SPACING_MULTIPLIERS:
            cell = next(
                c
                for c in cells
                if c["stage_length"] == stage_length and c["multiplier"] == multiplier
            )
            pooled = cell["identification_time_cycles"]["pooled"]
            median = "—" if pooled["median"] is None else f"{pooled['median']:.0f}"
            entries.append(
                f"{'PASS' if cell['passed'] else 'fail'} 中位T={median} "
                f"删失{pooled['censored_fraction']:.0%}"
            )
        lines.append(f"| {stage_length} | " + " | ".join(entries) + " |")
    lines += [
        "",
        "边界格（每行最小通过倍率 / 最大失败倍率）：",
    ]
    for stage_length, row in axes["budget_rows"].items():
        cells_row = row["boundary_cells"]
        lines.append(
            f"- L={stage_length}: 最小通过 m={cells_row['smallest_passing_multiplier']}, "
            f"最大失败 m={cells_row['largest_failing_multiplier']}, "
            f"倍率轴违背={row['monotonicity_violations_in_multiplier']}"
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
        default=RESULTS_ROOT / "g2_identification_time_curve_dev_v01",
    )
    arguments = parser.parse_args()
    report = run(arguments.output)
    verdicts = {
        stage_length: row["verdicts"]
        for stage_length, row in report["axis_checks"]["budget_rows"].items()
    }
    print(json.dumps(verdicts, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()

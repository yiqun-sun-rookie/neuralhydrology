"""Run the read-only re-identification timing analysis on frozen evidence."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd
import psutil


REPO_ROOT = Path(__file__).resolve().parents[3]
if str(REPO_ROOT / "src") not in sys.path:
    sys.path.insert(0, str(REPO_ROOT / "src"))

from hbv_multilead_joint_uncertainty.candidate_likelihood_reidentification import (  # noqa: E402
    agreement_call,
    analyze_reidentification_evidence,
    summarize_categories,
)
from hbv_multilead_joint_uncertainty.scripts.run_candidate_likelihood_decomposition import (  # noqa: E402
    _markdown_table,
    _npz_array_specs,
    _verify_input_run,
)
from hbv_multilead_joint_uncertainty.scripts.run_candidate_likelihood_identifiability import (  # noqa: E402
    _checksums_for_directory,
    _commit_memory,
    _environment,
    _json_write,
)
from hbv_multilead_joint_uncertainty.scripts.run_three_stage_switching_validation import (  # noqa: E402
    _replace_directory_with_retries,
    _validate_output_is_disjoint_from_protected_paths,
)


def _resource_preflight(root: Path, config: dict) -> dict:
    per_run = []
    keys = tuple(config["evidence_keys_used"])
    for run_entry in config["input_runs"]:
        specs = _npz_array_specs(
            (root / str(run_entry["results_dir"])).resolve() / "evidence.npz"
        )
        loaded = sum(
            int(np.prod(specs[key][0], dtype=np.int64)) * specs[key][1].itemsize
            for key in keys
            if key in specs
        )
        rank_shape = specs["true_candidate_cumulative_ranks"][0]
        derived = 6 * int(np.prod(rank_shape, dtype=np.int64)) * 8
        trial_rows = int(np.prod(rank_shape[:3], dtype=np.int64))
        table_bytes = trial_rows * 600
        per_run.append(
            {
                "results_dir": str(run_entry["results_dir"]),
                "loaded_array_bytes": loaded,
                "derived_array_bytes": derived,
                "trial_table_rows": trial_rows,
                "estimated_table_bytes": table_bytes,
                "estimated_run_peak_bytes": 2 * (loaded + derived) + table_bytes,
            }
        )
    estimated_peak = max(entry["estimated_run_peak_bytes"] for entry in per_run)
    current_process = int(psutil.Process().memory_info().rss)
    reserve = int(max(estimated_peak // 2, current_process // 4))
    required = estimated_peak + reserve
    available_physical = int(psutil.virtual_memory().available)
    commit = _commit_memory()
    available_commit = commit["available_commit_memory_bytes"]
    safe = available_physical >= required and (
        available_commit is None or available_commit >= required
    )
    result = {
        "checked_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "analysis_id": config["analysis_id"],
        "execution_parallelism": 1,
        "per_run_estimates": per_run,
        "estimated_peak_memory_bytes": estimated_peak,
        "current_process_resident_memory_bytes": current_process,
        "task_specific_reserve_bytes": reserve,
        "task_specific_required_available_bytes": required,
        "available_physical_memory_bytes": available_physical,
        **commit,
        "safe_to_run": bool(safe),
        "universal_memory_threshold_used": False,
        "estimation_basis": (
            "Exact npz header shapes for every loaded array, six derived rank-shaped "
            "work arrays, a generous per-row table buffer, a factor of two for "
            "transient copies, and a task-derived reserve."
        ),
    }
    if not safe:
        raise MemoryError(
            "task-specific physical or committed-memory estimate lacks a safe margin"
        )
    return result


def _load_evidence(results_dir: Path, keys) -> dict[str, np.ndarray]:
    with np.load(results_dir / "evidence.npz", allow_pickle=False) as archive:
        return {key: archive[key] for key in keys}


def _trial_rows(run_entry: dict, evidence: dict, analysis: dict) -> list[dict]:
    ranks = evidence["true_candidate_cumulative_ranks"]
    block_ids = [str(value) for value in evidence["block_ids"]]
    categories = analysis["categories"]
    rows = []
    for block_index, block_id in enumerate(block_ids):
        for truth_index in range(categories.shape[1]):
            for stage_index in range(categories.shape[2]):
                rows.append(
                    {
                        "dataset_role": run_entry["dataset_role"],
                        "scenario": run_entry["scenario"],
                        "block_id": block_id,
                        "truth_trial_index": truth_index,
                        "stage_number": stage_index + 1,
                        "is_switching_stage": stage_index > 0,
                        "first_cumulative_rank_one_day": int(
                            evidence["first_cumulative_rank_one_day"][
                                block_index, truth_index, stage_index
                            ]
                        ),
                        "first_stable_cumulative_rank_one_day": int(
                            evidence["first_stable_cumulative_rank_one_day"][
                                block_index, truth_index, stage_index
                            ]
                        ),
                        "final_cumulative_rank": int(
                            ranks[block_index, truth_index, stage_index, -1]
                        ),
                        "category": str(
                            categories[block_index, truth_index, stage_index]
                        ),
                    }
                )
    return rows


def _stage_summary_rows(run_entry: dict, evidence: dict, analysis: dict) -> list[dict]:
    categories = analysis["categories"]
    first = evidence["first_cumulative_rank_one_day"]
    first_stable = evidence["first_stable_cumulative_rank_one_day"]
    rows = []
    for stage_index in range(categories.shape[2]):
        stage_categories = categories[:, :, stage_index]
        summary = summarize_categories(
            stage_categories,
            first[:, :, stage_index],
            first_stable[:, :, stage_index],
        )
        block_stable_counts = np.sum(stage_categories == "stable", axis=1)
        rows.append(
            {
                "dataset_role": run_entry["dataset_role"],
                "scenario": run_entry["scenario"],
                "stage_number": stage_index + 1,
                "is_switching_stage": stage_index > 0,
                "block_count": int(stage_categories.shape[0]),
                **summary,
                "blocks_with_zero_stable": int(np.sum(block_stable_counts == 0)),
                "min_block_stable_count": int(np.min(block_stable_counts)),
                "max_block_stable_count": int(np.max(block_stable_counts)),
            }
        )
    return rows


def _daily_rows(run_entry: dict, analysis: dict) -> list[dict]:
    fractions = analysis["daily_rank_one_fraction"]
    medians = analysis["daily_median_rank"]
    rows = []
    for stage_index in range(fractions.shape[0]):
        for day_index in range(fractions.shape[1]):
            rows.append(
                {
                    "dataset_role": run_entry["dataset_role"],
                    "scenario": run_entry["scenario"],
                    "stage_number": stage_index + 1,
                    "scoring_day": day_index + 1,
                    "rank_one_fraction": float(fractions[stage_index, day_index]),
                    "median_cumulative_rank": float(medians[stage_index, day_index]),
                }
            )
    return rows


def _report_lines(config, summary_frame, consistency_rows, integrity_rows) -> list[str]:
    switching = summary_frame[summary_frame["is_switching_stage"]]
    lines = [
        "# 十五状态候选再识别时间刻画：确定性分析报告（v01）",
        "",
        "本报告由 `run_candidate_likelihood_reidentification.py` 按读数前冻结的规则自动生成；",
        "分类与判定规则见 `analysis_config_snapshot.json`。",
        "",
        "## 结论（按冻结一致性规则，仅切换阶段 2、3）",
        "",
    ]
    for row in consistency_rows:
        lines.append(
            f"- 场景 `{row['scenario']}` 阶段 {row['stage_number']}："
            f"开发主导失败模式 `{row['development_label']}`，"
            f"确认主导失败模式 `{row['confirmation_label']}`，"
            f"一致 = {row['consistent']}；结论：{row['conclusion']}。"
        )
    lines += [
        "",
        "## 切换阶段统计",
        "",
        _markdown_table(switching),
        "",
        "## 阶段 1（无切换，仅报告）",
        "",
        _markdown_table(summary_frame[~summary_frame["is_switching_stage"]]),
        "",
        "## 完整性",
        "",
    ]
    for row in integrity_rows:
        lines.append(
            f"- `{row['results_dir']}`：首次登顶日重算不符 {row['recomputed_first_day_mismatches']}，"
            f"首次稳定日重算不符 {row['recomputed_first_stable_day_mismatches']}，"
            f"稳定类别对冻结旗标不符 {row['stable_category_vs_frozen_flag_mismatches']}，"
            f"划分违例 {row['partition_violations']}，通过 = {row['integrity_passed']}"
        )
    lines += ["", "## 边界", "", str(config["scope_limit"]), ""]
    return lines


def run(repo_root: Path, config_path: Path, output_dir: Path) -> dict:
    root = repo_root.resolve()
    config_file = config_path.resolve()
    output = output_dir.resolve()
    incomplete = output.with_name(output.name + ".incomplete")
    if output.exists() or incomplete.exists():
        raise FileExistsError("refusing to overwrite existing analysis output")
    config_bytes = config_file.read_bytes()
    config_hash = hashlib.sha256(config_bytes).hexdigest()
    config = json.loads(config_bytes.decode("utf-8"))
    if output.name != str(config["analysis_id"]):
        raise ValueError("output directory name must equal analysis_id")
    if output != (root / str(config["output_directory"])).resolve():
        raise ValueError("output directory must match the frozen configuration")
    input_dirs = [
        (root / str(run_entry["results_dir"])).resolve()
        for run_entry in config["input_runs"]
    ]
    _validate_output_is_disjoint_from_protected_paths(output, input_dirs)
    _validate_output_is_disjoint_from_protected_paths(incomplete, input_dirs)

    started_at = dt.datetime.now(dt.timezone.utc).isoformat()
    integrity_before = {
        entry["results_dir"]: entry
        for entry in (
            _verify_input_run(root, run_entry) for run_entry in config["input_runs"]
        )
    }
    preflight = _resource_preflight(root, config)

    gates = config["integrity_gates"]
    latest = int(config["latest_qualifying_first_stable_day"])
    keys = tuple(config["evidence_keys_used"])
    trial_frames = {}
    daily_rows = []
    summary_rows = []
    integrity_rows = []
    labels: dict[tuple[str, str, int], str] = {}
    for run_entry in config["input_runs"]:
        results_dir = (root / str(run_entry["results_dir"])).resolve()
        evidence = _load_evidence(results_dir, keys)
        analysis = analyze_reidentification_evidence(evidence, gates, latest)
        trial_frames[results_dir.name] = pd.DataFrame(
            _trial_rows(run_entry, evidence, analysis)
        )
        daily_rows.extend(_daily_rows(run_entry, analysis))
        stage_rows = _stage_summary_rows(run_entry, evidence, analysis)
        summary_rows.extend(stage_rows)
        for row in stage_rows:
            labels[
                (run_entry["dataset_role"], run_entry["scenario"], row["stage_number"])
            ] = row["dominant_failure_label"]
        integrity_rows.append(
            {
                "results_dir": str(run_entry["results_dir"]),
                "dataset_role": run_entry["dataset_role"],
                "scenario": run_entry["scenario"],
                **analysis["integrity"],
            }
        )
    if not all(row["integrity_passed"] for row in integrity_rows):
        raise RuntimeError("re-identification gates failed against frozen evidence")

    consistency_rows = []
    scenarios = list(
        dict.fromkeys(run_entry["scenario"] for run_entry in config["input_runs"])
    )
    for scenario in scenarios:
        for stage_number in config["statistics_rules"]["decision_stages"]:
            call = agreement_call(
                labels[("development", scenario, stage_number)],
                labels[("confirmation", scenario, stage_number)],
            )
            consistency_rows.append(
                {"scenario": scenario, "stage_number": stage_number, **call}
            )

    integrity_after = {
        entry["results_dir"]: entry
        for entry in (
            _verify_input_run(root, run_entry) for run_entry in config["input_runs"]
        )
    }
    inputs_unchanged = {
        key: integrity_before[key]["checksums"] == integrity_after[key]["checksums"]
        for key in integrity_before
    }
    if not all(inputs_unchanged.values()):
        raise RuntimeError("frozen input evidence changed during the analysis")

    summary_frame = pd.DataFrame(summary_rows)
    summary = {
        "analysis_id": config["analysis_id"],
        "goal_item": config["goal_item"],
        "read_only_inputs": True,
        "frozen_experiments_rerun": False,
        "config_sha256": config_hash,
        "input_integrity_status": "verified_before_and_after_unchanged",
        "integrity_status": "passed",
        "conclusions": {
            f"{row['scenario']}__stage_{row['stage_number']}": row["conclusion"]
            for row in consistency_rows
        },
        "scope_limit": config["scope_limit"],
    }

    incomplete.mkdir(parents=True, exist_ok=False)
    try:
        (incomplete / "analysis_config_snapshot.json").write_bytes(config_bytes)
        _json_write(incomplete / "resource_preflight.json", preflight)
        _json_write(incomplete / "input_integrity_before.json", integrity_before)
        _json_write(
            incomplete / "input_integrity_after.json",
            {**integrity_after, "inputs_unchanged": inputs_unchanged},
        )
        _json_write(
            incomplete / "integrity_checks.json",
            {
                "per_run": integrity_rows,
                "all_passed": bool(
                    all(row["integrity_passed"] for row in integrity_rows)
                ),
            },
        )
        for run_key, frame in trial_frames.items():
            frame.to_csv(
                incomplete / f"trial_reidentification__{run_key}.csv",
                index=False,
                lineterminator="\n",
            )
        summary_frame.to_csv(
            incomplete / "stage_reidentification_summary.csv",
            index=False,
            lineterminator="\n",
        )
        pd.DataFrame(daily_rows).to_csv(
            incomplete / "daily_rank_summary.csv", index=False, lineterminator="\n"
        )
        pd.DataFrame(consistency_rows).to_csv(
            incomplete / "dominant_failure_consistency.csv",
            index=False,
            lineterminator="\n",
        )
        _json_write(incomplete / "environment.json", _environment(root, started_at))
        _json_write(incomplete / "summary.json", summary)
        (incomplete / "final_reidentification_report.md").write_text(
            "\n".join(
                _report_lines(config, summary_frame, consistency_rows, integrity_rows)
            ),
            encoding="utf-8",
        )
        checksums = _checksums_for_directory(incomplete)
        _json_write(incomplete / "checksums.json", checksums)
        _replace_directory_with_retries(incomplete, output)
    except Exception:
        raise
    return summary


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, required=True)
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    arguments = parser.parse_args()
    summary = run(arguments.repo_root, arguments.config, arguments.output_dir)
    print(json.dumps(summary, indent=2, sort_keys=True, ensure_ascii=False))


if __name__ == "__main__":
    main()

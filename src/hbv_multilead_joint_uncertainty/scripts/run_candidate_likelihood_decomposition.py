"""Run the read-only decomposition of frozen candidate likelihood evidence."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import sys
import zipfile
from pathlib import Path

import numpy as np
import pandas as pd
import psutil
from numpy.lib import format as npy_format


REPO_ROOT = Path(__file__).resolve().parents[3]
if str(REPO_ROOT / "src") not in sys.path:
    sys.path.insert(0, str(REPO_ROOT / "src"))

from hbv_multilead_joint_uncertainty.candidate_likelihood_decomposition import (  # noqa: E402
    analyze_evidence_arrays,
    attribute_stage,
    consistency_call,
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


EVIDENCE_KEYS = (
    "candidate_innovations",
    "candidate_innovation_variances",
    "candidate_daily_log_likelihoods",
    "cumulative_log_likelihoods",
    "true_candidate_cumulative_margins",
    "truth_candidate_indices",
    "stage_start_days",
    "stage_end_days",
    "adaptation_days",
    "candidate_ids",
    "block_ids",
)


def _npz_array_specs(path: Path) -> dict[str, tuple[tuple[int, ...], np.dtype]]:
    """Read array shapes and dtypes from one npz without materializing arrays."""

    specs: dict[str, tuple[tuple[int, ...], np.dtype]] = {}
    with zipfile.ZipFile(path) as archive:
        for name in archive.namelist():
            if not name.endswith(".npy"):
                continue
            with archive.open(name) as handle:
                version = npy_format.read_magic(handle)
                if version == (1, 0):
                    shape, _, dtype = npy_format.read_array_header_1_0(handle)
                elif version == (2, 0):
                    shape, _, dtype = npy_format.read_array_header_2_0(handle)
                else:
                    raise ValueError(f"unsupported npy header version {version}")
            specs[name[: -len(".npy")]] = (shape, dtype)
    return specs


def _verify_input_run(root: Path, run: dict) -> dict:
    """Check one frozen input run's config hash and full directory checksums."""

    config_path = (root / str(run["config_path"])).resolve()
    actual_config_hash = hashlib.sha256(config_path.read_bytes()).hexdigest()
    if actual_config_hash != str(run["config_sha256"]):
        raise ValueError(f"config hash mismatch for {run['config_path']}")
    results_dir = (root / str(run["results_dir"])).resolve()
    stored = json.loads((results_dir / "checksums.json").read_text(encoding="utf-8"))
    recomputed = _checksums_for_directory(results_dir)
    missing = sorted(set(stored) - set(recomputed))
    extra = sorted(set(recomputed) - set(stored))
    mismatched = sorted(
        name for name in set(stored) & set(recomputed) if stored[name] != recomputed[name]
    )
    if missing or extra or mismatched:
        raise ValueError(
            f"frozen evidence checksum gap for {run['results_dir']}: "
            f"missing={missing} extra={extra} mismatched={mismatched}"
        )
    return {
        "results_dir": str(run["results_dir"]),
        "config_path": str(run["config_path"]),
        "config_sha256": actual_config_hash,
        "file_count": len(recomputed),
        "checksums": recomputed,
    }


def _resource_preflight(root: Path, config: dict) -> dict:
    """Estimate peak memory from the actual evidence array shapes, no fixed threshold."""

    per_run = []
    for run in config["input_runs"]:
        specs = _npz_array_specs(
            (root / str(run["results_dir"])).resolve() / "evidence.npz"
        )
        loaded = sum(
            int(np.prod(specs[key][0], dtype=np.int64)) * specs[key][1].itemsize
            for key in EVIDENCE_KEYS
            if key in specs
        )
        daily_shape = specs["candidate_innovations"][0]
        cumulative_shape = specs["cumulative_log_likelihoods"][0]
        margin_shape = specs["true_candidate_cumulative_margins"][0]
        itemsize = np.dtype(np.float64).itemsize
        derived = (
            2 * int(np.prod(daily_shape, dtype=np.int64)) * itemsize
            + 5 * int(np.prod(cumulative_shape, dtype=np.int64)) * itemsize
            + 4 * int(np.prod(margin_shape, dtype=np.int64)) * itemsize
        )
        daily_rows = int(np.prod(daily_shape, dtype=np.int64))
        table_bytes = daily_rows * 700
        working = loaded + derived
        per_run.append(
            {
                "results_dir": str(run["results_dir"]),
                "loaded_array_bytes": loaded,
                "derived_array_bytes": derived,
                "daily_table_rows": daily_rows,
                "estimated_table_bytes": table_bytes,
                "estimated_run_peak_bytes": 2 * working + table_bytes,
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
        "runs_processed_sequentially": True,
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
            "Exact npz header shapes for every loaded array, derived component and "
            "cumulative arrays, one generous per-row table buffer, a factor of two for "
            "transient copies, and a reserve equal to the larger of half the peak or one "
            "quarter of current process memory. Runs are processed one at a time."
        ),
    }
    if not safe:
        raise MemoryError(
            "task-specific physical or committed-memory estimate lacks a safe margin"
        )
    return result


def _load_evidence(results_dir: Path) -> dict[str, np.ndarray]:
    with np.load(results_dir / "evidence.npz", allow_pickle=False) as archive:
        return {key: archive[key] for key in EVIDENCE_KEYS}


def _daily_component_rows(run: dict, evidence: dict, analysis: dict) -> list[dict]:
    components = analysis["components"]
    scores = analysis["scores"]
    stage_truth = analysis["stage_truth_candidate_indices"]
    block_ids = [str(value) for value in evidence["block_ids"]]
    candidate_ids = [str(value) for value in evidence["candidate_ids"]]
    starts = [int(value) for value in evidence["stage_start_days"]]
    ends = [int(value) for value in evidence["stage_end_days"]]
    adaptation = int(evidence["adaptation_days"])
    frozen_daily = evidence["candidate_daily_log_likelihoods"]
    frozen_cumulative = evidence["cumulative_log_likelihoods"]
    rows = []
    for block_index, block_id in enumerate(block_ids):
        for truth_index in range(stage_truth.shape[0]):
            for stage_index, (start, end) in enumerate(zip(starts, ends)):
                scoring_start = start + adaptation
                for day in range(start, end):
                    scoring_day = day - scoring_start + 1 if day >= scoring_start else 0
                    for candidate_index, candidate_id in enumerate(candidate_ids):
                        row = {
                            "dataset_role": run["dataset_role"],
                            "scenario": run["scenario"],
                            "block_id": block_id,
                            "truth_trial_index": truth_index,
                            "stage_number": stage_index + 1,
                            "assimilation_day_one_based": day + 1,
                            "is_scoring_day": day >= scoring_start,
                            "scoring_day_number": scoring_day,
                            "candidate_id": candidate_id,
                            "is_true_candidate": candidate_index
                            == int(stage_truth[truth_index, stage_index]),
                            "innovation": float(
                                evidence["candidate_innovations"][
                                    block_index, truth_index, day, candidate_index
                                ]
                            ),
                            "innovation_variance": float(
                                evidence["candidate_innovation_variances"][
                                    block_index, truth_index, day, candidate_index
                                ]
                            ),
                            "variance_penalty": float(
                                components.variance_penalty[
                                    block_index, truth_index, day, candidate_index
                                ]
                            ),
                            "innovation_penalty": float(
                                components.innovation_penalty[
                                    block_index, truth_index, day, candidate_index
                                ]
                            ),
                            "frozen_daily_log_likelihood": float(
                                frozen_daily[
                                    block_index, truth_index, day, candidate_index
                                ]
                            ),
                            "stage_cumulative_variance_penalty": None,
                            "stage_cumulative_innovation_penalty": None,
                            "stage_cumulative_total": None,
                            "frozen_stage_cumulative_log_likelihood": None,
                        }
                        if scoring_day > 0:
                            index = (
                                block_index,
                                truth_index,
                                stage_index,
                                scoring_day - 1,
                                candidate_index,
                            )
                            row["stage_cumulative_variance_penalty"] = float(
                                scores.cumulative_variance_penalty[index]
                            )
                            row["stage_cumulative_innovation_penalty"] = float(
                                scores.cumulative_innovation_penalty[index]
                            )
                            row["stage_cumulative_total"] = float(
                                scores.cumulative_total[index]
                            )
                            row["frozen_stage_cumulative_log_likelihood"] = float(
                                frozen_cumulative[index]
                            )
                        rows.append(row)
    return rows


def _trial_stage_rows(run: dict, evidence: dict, analysis: dict) -> list[dict]:
    scores = analysis["scores"]
    stage_truth = analysis["stage_truth_candidate_indices"]
    block_ids = [str(value) for value in evidence["block_ids"]]
    candidate_ids = [str(value) for value in evidence["candidate_ids"]]
    frozen_margins = evidence["true_candidate_cumulative_margins"]
    rows = []
    for block_index, block_id in enumerate(block_ids):
        for truth_index in range(stage_truth.shape[0]):
            for stage_index in range(stage_truth.shape[1]):
                frozen_margin = float(frozen_margins[block_index, truth_index, stage_index, -1])
                delta_total = float(
                    scores.final_delta_total[block_index, truth_index, stage_index]
                )
                rows.append(
                    {
                        "dataset_role": run["dataset_role"],
                        "scenario": run["scenario"],
                        "block_id": block_id,
                        "truth_trial_index": truth_index,
                        "stage_number": stage_index + 1,
                        "is_switching_stage": stage_index > 0,
                        "true_candidate_id": candidate_ids[
                            int(stage_truth[truth_index, stage_index])
                        ],
                        "best_wrong_candidate_id": candidate_ids[
                            int(
                                scores.best_wrong_candidate_indices[
                                    block_index, truth_index, stage_index
                                ]
                            )
                        ],
                        "best_wrong_tie_count": int(
                            scores.best_wrong_tie_counts[
                                block_index, truth_index, stage_index
                            ]
                        ),
                        "final_delta_variance_penalty": float(
                            scores.final_delta_variance[
                                block_index, truth_index, stage_index
                            ]
                        ),
                        "final_delta_innovation_penalty": float(
                            scores.final_delta_innovation[
                                block_index, truth_index, stage_index
                            ]
                        ),
                        "final_delta_total": delta_total,
                        "frozen_final_cumulative_margin": frozen_margin,
                        "margin_absolute_error": abs(delta_total - frozen_margin),
                    }
                )
    return rows


def _stage_summary_rows(run: dict, evidence: dict, analysis: dict) -> list[dict]:
    scores = analysis["scores"]
    block_count = scores.final_delta_total.shape[0]
    rows = []
    for stage_index in range(scores.final_delta_total.shape[2]):
        delta_variance = scores.final_delta_variance[:, :, stage_index]
        delta_innovation = scores.final_delta_innovation[:, :, stage_index]
        attribution = attribute_stage(delta_variance.ravel(), delta_innovation.ravel())
        block_median_variance = np.median(delta_variance, axis=1)
        block_median_innovation = np.median(delta_innovation, axis=1)
        block_median_total = np.median(delta_variance + delta_innovation, axis=1)
        rows.append(
            {
                "dataset_role": run["dataset_role"],
                "scenario": run["scenario"],
                "stage_number": stage_index + 1,
                "is_switching_stage": stage_index > 0,
                "block_count": int(block_count),
                **attribution,
                "blocks_with_negative_median_delta_variance": int(
                    np.sum(block_median_variance < 0.0)
                ),
                "blocks_with_negative_median_delta_innovation": int(
                    np.sum(block_median_innovation < 0.0)
                ),
                "blocks_with_negative_median_delta_total": int(
                    np.sum(block_median_total < 0.0)
                ),
                "total_best_wrong_tie_count": int(
                    np.sum(scores.best_wrong_tie_counts[:, :, stage_index])
                ),
            }
        )
    return rows


def _markdown_table(frame: pd.DataFrame) -> str:
    """Render one DataFrame as GitHub markdown without optional dependencies."""

    def _cell(value) -> str:
        if isinstance(value, float):
            return format(value, ".6g")
        return str(value)

    columns = [str(name) for name in frame.columns]
    lines = [
        "| " + " | ".join(columns) + " |",
        "| " + " | ".join("---" for _ in columns) + " |",
    ]
    for row in frame.itertuples(index=False):
        lines.append("| " + " | ".join(_cell(value) for value in row) + " |")
    return "\n".join(lines)


_CONCLUSION_TEXT = {
    "variance": "错误候选第十日累计优势主要来自预测方差惩罚项",
    "innovation": "错误候选第十日累计优势主要来自归一化平方创新惩罚项",
}


def _report_lines(config, summary_frame, consistency_rows, integrity) -> list[str]:
    lines = [
        "# 十五状态候选观测似然分解：确定性分析报告（v01）",
        "",
        "本报告由 `run_candidate_likelihood_decomposition.py` 按冻结规则自动生成，",
        "规则见 `analysis_config_snapshot.json` 与设计文档；判定只使用第十评分日。",
        "",
        "## 结论（按冻结一致性规则）",
        "",
    ]
    for row in consistency_rows:
        conclusion = row["conclusion"]
        text = _CONCLUSION_TEXT.get(conclusion, conclusion)
        lines.append(
            f"- 场景 `{row['scenario']}` 阶段 {row['stage_number']}："
            f"开发标签 `{row['development_label']}`，确认标签 `{row['confirmation_label']}`，"
            f"方向一致 = {row['consistent']}；结论：{text}。"
        )
    lines += [
        "",
        "## 阶段级统计（切换阶段 2、3 参与判定，阶段 1 只报告）",
        "",
        _markdown_table(summary_frame),
        "",
        "## 完整性",
        "",
        f"- 逐日分解恒等式最大绝对误差（六个运行的最大值）：{integrity['max_daily_identity_error']:.3e}",
        f"- 阶段累计恒等式最大绝对误差：{integrity['max_cumulative_identity_error']:.3e}",
        f"- 第十日边际分解最大绝对误差：{integrity['max_margin_error']:.3e}",
        f"- 最佳错误候选并列总数：{integrity['total_tie_count']}",
        f"- 全部完整性门槛通过：{integrity['all_passed']}",
        "",
        "## 边界",
        "",
        str(config["scope_limit"]),
        "",
    ]
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
    daily_frames = {}
    trial_frames = {}
    summary_rows = []
    integrity_rows = []
    labels: dict[tuple[str, str, int], str] = {}
    for run_entry in config["input_runs"]:
        results_dir = (root / str(run_entry["results_dir"])).resolve()
        evidence = _load_evidence(results_dir)
        analysis = analyze_evidence_arrays(evidence, gates)
        run_key = results_dir.name
        daily_frames[run_key] = pd.DataFrame(
            _daily_component_rows(run_entry, evidence, analysis)
        )
        trial_frames[run_key] = pd.DataFrame(
            _trial_stage_rows(run_entry, evidence, analysis)
        )
        stage_rows = _stage_summary_rows(run_entry, evidence, analysis)
        summary_rows.extend(stage_rows)
        for row in stage_rows:
            labels[(run_entry["dataset_role"], run_entry["scenario"], row["stage_number"])] = row[
                "label"
            ]
        integrity_rows.append(
            {
                "results_dir": str(run_entry["results_dir"]),
                "dataset_role": run_entry["dataset_role"],
                "scenario": run_entry["scenario"],
                **analysis["integrity"],
                "total_best_wrong_tie_count": int(
                    np.sum(analysis["scores"].best_wrong_tie_counts)
                ),
            }
        )

    consistency_rows = []
    scenarios = list(
        dict.fromkeys(run_entry["scenario"] for run_entry in config["input_runs"])
    )
    for scenario in scenarios:
        for stage_number in config["stages_that_decide"]:
            development_label = labels[("development", scenario, stage_number)]
            confirmation_label = labels[("confirmation", scenario, stage_number)]
            call = consistency_call(development_label, confirmation_label)
            consistency_rows.append(
                {
                    "scenario": scenario,
                    "stage_number": stage_number,
                    "development_label": development_label,
                    "confirmation_label": confirmation_label,
                    **call,
                }
            )

    integrity_summary = {
        "max_daily_identity_error": max(
            row["daily_component_identity_maximum_absolute_error"]
            for row in integrity_rows
        ),
        "max_cumulative_identity_error": max(
            row["stage_cumulative_identity_maximum_absolute_error"]
            for row in integrity_rows
        ),
        "max_margin_error": max(
            row["final_margin_decomposition_maximum_absolute_error"]
            for row in integrity_rows
        ),
        "total_tie_count": sum(
            row["total_best_wrong_tie_count"] for row in integrity_rows
        ),
        "all_passed": bool(all(row["integrity_passed"] for row in integrity_rows)),
    }
    if not integrity_summary["all_passed"]:
        raise RuntimeError("component identity gates failed against frozen evidence")

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
    consistency_frame = pd.DataFrame(consistency_rows)
    summary = {
        "analysis_id": config["analysis_id"],
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
        _json_write(
            incomplete / "input_integrity_before.json",
            {
                key: {name: value for name, value in entry.items()}
                for key, entry in integrity_before.items()
            },
        )
        _json_write(
            incomplete / "input_integrity_after.json",
            {
                **{
                    key: {name: value for name, value in entry.items()}
                    for key, entry in integrity_after.items()
                },
                "inputs_unchanged": inputs_unchanged,
            },
        )
        _json_write(
            incomplete / "integrity_checks.json",
            {"per_run": integrity_rows, "summary": integrity_summary},
        )
        for run_key, frame in daily_frames.items():
            frame.to_csv(
                incomplete / f"daily_components__{run_key}.csv",
                index=False,
                lineterminator="\n",
            )
        for run_key, frame in trial_frames.items():
            frame.to_csv(
                incomplete / f"trial_stage_components__{run_key}.csv",
                index=False,
                lineterminator="\n",
            )
        summary_frame.to_csv(
            incomplete / "stage_component_summary.csv", index=False, lineterminator="\n"
        )
        consistency_frame.to_csv(
            incomplete / "development_confirmation_consistency.csv",
            index=False,
            lineterminator="\n",
        )
        _json_write(incomplete / "environment.json", _environment(root, started_at))
        _json_write(incomplete / "summary.json", summary)
        (incomplete / "final_decomposition_report.md").write_text(
            "\n".join(
                _report_lines(config, summary_frame, consistency_rows, integrity_summary)
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

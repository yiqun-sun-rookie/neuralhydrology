"""Verify two supervised real development loops against the milestone-four gates.

This checks, for each loop, the five admission gates (exit codes, artifact cardinality,
finite metrics, zero forbidden reads, registry integrity) and that every registered run was
actually supervised. It independently recounts denied access events from each run's raw
access log rather than trusting the loop's self-reported total, and the run gate depends on
that independent recount -- not on the loop's four self-declared safety flags, which are a
self-declaration of intent and are recorded for transparency only. Across the two loops it
confirms the deterministic scientific subset (eight score reports plus four candidate
summaries) is byte-for-byte identical, while acknowledging that live supervisor telemetry
legitimately differs. It also reports the measured peak process memory that calibrates the
peak-estimation method; it never opens sealed evaluation data and never claims any candidate
beats a baseline.

Example
-------
python src/unified_autoresearch/scripts/verify_supervised_real_loops.py \
    --loop-root runs/unified_autoresearch/supervised_development_loop_real_v1 \
    --loop-root runs/unified_autoresearch/supervised_development_loop_real_v2 \
    --report-path runs/unified_autoresearch/supervised_development_loop_real_v1/VERIFICATION.json
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import sys
from pathlib import Path
from typing import Any


MODULE_ROOT = Path(__file__).resolve().parents[1]
SRC_ROOT = MODULE_ROOT.parent
if str(SRC_ROOT) not in sys.path:
    sys.path.insert(0, str(SRC_ROOT))

from unified_autoresearch.registry.store import Registry  # noqa: E402

REFERENCE_CATEGORIES = ("deep_learning", "conceptual_rainfall_runoff", "fusion", "custom_python")
DECLARED_PEAK_MEMORY_GB = 0.35
DECLARED_MEMORY_RESERVE_GB = 0.25


def forbidden_access_count(records: list[dict[str, Any]]) -> int:
    """Count denied access events, independent of any total the loop reported about itself."""
    return sum(1 for record in records if record.get("decision") == "deny")


def milestone_gate_inputs(loop_verification: dict[str, Any]) -> dict[str, bool]:
    """The independently-verified booleans one loop contributes to the milestone run gate.

    This deliberately excludes the loop's self-declared safety flags: a self-declaration cannot
    verify itself, so the gate is built only from checks this verifier computed from raw evidence.
    """
    return {
        "five_gates_all_pass": bool(loop_verification["five_gates_all_pass"]),
        "fully_supervised": loop_verification["supervised_run_count"] == 16,
        "no_controlled_stop": loop_verification["controlled_stop_count"] == 0,
        "forbidden_access_independently_zero": loop_verification["independent_forbidden_access_count"] == 0,
    }


def _independent_denied_access_count(run_root: Path) -> int:
    """Recount denied access events from a run's raw access log, not from its summary record."""
    log_path = run_root / "logs" / "access.jsonl"
    if not log_path.is_file():
        return 0
    records = [json.loads(line) for line in log_path.read_text(encoding="utf-8").splitlines() if line]
    return forbidden_access_count(records)


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _subset_digest(root: Path, subdirectory: str) -> dict[str, str]:
    base = root / subdirectory
    return {
        path.relative_to(root).as_posix(): _sha256_file(path)
        for path in sorted(base.rglob("*"))
        if path.is_file()
    }


def _monitor_samples(run_root: Path) -> list[dict[str, Any]]:
    log_path = run_root / "logs" / "resource-monitor.jsonl"
    if not log_path.is_file():
        return []
    return [json.loads(line) for line in log_path.read_text(encoding="utf-8").splitlines() if line]


def _registered_run_dirs(loop_root: Path, summary: dict[str, Any]) -> list[tuple[str, Path]]:
    pairs: list[tuple[str, Path]] = []
    for candidate in summary["candidates"].values():
        for protocol in ("forward", "reverse"):
            protocol_result = candidate["protocols"][protocol]
            for mode in ("train", "predict"):
                pairs.append((protocol_result[f"{mode}_run_id"], loop_root / protocol_result[f"{mode}_run_root"]))
    return pairs


def _verify_single_loop(loop_root: Path) -> dict[str, Any]:
    summary = json.loads((loop_root / "LOOP_SUMMARY.json").read_text(encoding="utf-8"))

    cardinality_ok = (
        summary["candidate_count"] == 4
        and summary["registered_run_count"] == 16
        and summary["score_report_count"] == 8
        and summary["cell_count"] == 32
    )
    unique_cells = len({(cell["category"], cell["basin"]) for cell in summary["cells"]}) == 32
    finite_metrics = all(
        math.isfinite(float(cell[metric]))
        for cell in summary["cells"]
        for metric in ("forward_nse", "reverse_nse", "mean_nse")
    )

    run_records = [
        record
        for candidate in summary["candidates"].values()
        for protocol_result in candidate["protocols"].values()
        for record in (protocol_result["train"], protocol_result["predict"])
    ]
    exit_codes_ok = all(
        record["status"] == "succeeded"
        and record["normalized_exit_code"] == 0
        and record["process_exit_code"] == 0
        for record in run_records
    )
    total_denied = sum(int(record["denied_event_count"]) for record in run_records)

    registry_failures: list[str] = []
    supervised_runs = 0
    controlled_stops = 0
    independent_denied = 0
    peak_process_memory_gb = 0.0
    minimum_free_memory_gb = math.inf
    minimum_free_disk_gb = math.inf
    for run_id, run_root in _registered_run_dirs(loop_root, summary):
        registry = Registry(
            run_root / "registry" / "registry.sqlite",
            scheduler_lock_path=run_root / "registry" / "scheduler.lock",
            receipt_dir=run_root / "registry" / "receipts",
        )
        report = registry.verify()
        if report != {"record_count": 8, "failure_count": 0, "failures": []}:
            registry_failures.append(run_id)

        independent_denied += _independent_denied_access_count(run_root)

        samples = _monitor_samples(run_root)
        contiguous = [sample["sample_index"] for sample in samples] == list(range(len(samples)))
        if samples and contiguous:
            supervised_runs += 1
            peak_process_memory_gb = max(peak_process_memory_gb, *(s["process_memory_gb"] for s in samples))
            minimum_free_memory_gb = min(minimum_free_memory_gb, *(s["system_available_memory_gb"] for s in samples))
            minimum_free_disk_gb = min(minimum_free_disk_gb, *(s["free_disk_gb"] for s in samples))
        if (run_root / "control" / "STOP_REQUEST.json").is_file():
            controlled_stops += 1

    gates = {
        "exit_codes_all_succeeded": exit_codes_ok,
        "artifact_cardinality_16_8_32": cardinality_ok and unique_cells,
        "all_32_cells_finite": finite_metrics,
        "forbidden_reads_zero": total_denied == 0,
        "registry_integrity_all_pass": not registry_failures,
    }
    # The loop writes these four flags into its own summary as constants; they are a
    # self-declaration of intent, not verification. We record them for transparency but the run
    # gate never depends on them -- it depends on independent_forbidden_access_count, recounted
    # above from each run's raw access log.
    declared_safety_flags = {
        flag: summary[flag]
        for flag in (
            "sealed_final_evaluation_read_or_scored",
            "fair_benchmark_scoring_program_run",
            "formal_basin_search_run",
            "baseline_outperformance_claimed",
        )
    }
    return {
        "loop_root": loop_root.as_posix(),
        "independent_monitor_enabled": summary.get("independent_monitor_enabled"),
        "monitor_sample_interval_seconds": summary.get("monitor_sample_interval_seconds"),
        "five_gates": gates,
        "five_gates_all_pass": all(gates.values()),
        "declared_safety_flags": declared_safety_flags,
        "declared_safety_flags_all_false": not any(declared_safety_flags.values()),
        "supervised_run_count": supervised_runs,
        "controlled_stop_count": controlled_stops,
        "self_reported_denied_event_count": total_denied,
        "independent_forbidden_access_count": independent_denied,
        "denied_count_selfreport_matches_independent": total_denied == independent_denied,
        "registry_failures": registry_failures,
        "measured_peak_process_memory_gb": peak_process_memory_gb,
        "measured_minimum_free_memory_gb": None if minimum_free_memory_gb is math.inf else minimum_free_memory_gb,
        "measured_minimum_free_disk_gb": None if minimum_free_disk_gb is math.inf else minimum_free_disk_gb,
        "scientific_subset_digest": {
            **_subset_digest(loop_root, "scores"),
            **_subset_digest(loop_root, "summaries"),
        },
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--loop-root", type=Path, action="append", required=True, help="give exactly twice")
    parser.add_argument("--report-path", type=Path, default=None)
    arguments = parser.parse_args(argv)

    if len(arguments.loop_root) != 2:
        raise SystemExit("exactly two --loop-root values are required")

    loops = [_verify_single_loop(root.resolve()) for root in arguments.loop_root]
    first, second = loops
    scientific_identical = first["scientific_subset_digest"] == second["scientific_subset_digest"]
    peak = max(loop["measured_peak_process_memory_gb"] for loop in loops)

    gate_inputs = [milestone_gate_inputs(loop) for loop in loops]
    both_five = all(inputs["five_gates_all_pass"] for inputs in gate_inputs)
    both_supervised = all(inputs["fully_supervised"] for inputs in gate_inputs)
    no_stop = all(inputs["no_controlled_stop"] for inputs in gate_inputs)
    both_forbidden_zero = all(inputs["forbidden_access_independently_zero"] for inputs in gate_inputs)

    verdict = {
        "schema_version": "supervised_loop_verification_v2",
        "loops": loops,
        "both_loops_five_gates_pass": both_five,
        "both_loops_forbidden_access_independently_zero": both_forbidden_zero,
        "both_loops_fully_supervised": both_supervised,
        "no_controlled_stop_triggered": no_stop,
        "scientific_subset_byte_identical": scientific_identical,
        "scientific_subset_file_count": len(first["scientific_subset_digest"]),
        "measured_peak_process_memory_gb": peak,
        "declared_peak_plus_reserve_gb": DECLARED_PEAK_MEMORY_GB + DECLARED_MEMORY_RESERVE_GB,
        "declared_margin_over_measured": round((DECLARED_PEAK_MEMORY_GB + DECLARED_MEMORY_RESERVE_GB) / peak, 3)
        if peak > 0
        else None,
        # Recorded for transparency only -- the loops' own self-declarations, NOT gate inputs.
        "both_loops_declared_safety_flags_false": all(loop["declared_safety_flags_all_false"] for loop in loops),
        "both_loops_denied_count_selfreport_matches_independent": all(
            loop["denied_count_selfreport_matches_independent"] for loop in loops
        ),
    }
    verdict["milestone_four_run_gate_passed"] = (
        both_five
        and both_forbidden_zero
        and both_supervised
        and no_stop
        and scientific_identical
    )

    text = json.dumps(verdict, indent=2, sort_keys=True) + "\n"
    if arguments.report_path is not None:
        report_path = arguments.report_path.resolve()
        descriptor = os.open(report_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o444)
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as stream:
            stream.write(text)
            stream.flush()
            os.fsync(stream.fileno())
    print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

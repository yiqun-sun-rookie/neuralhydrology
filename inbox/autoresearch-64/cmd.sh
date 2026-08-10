#!/bin/bash
set -eo pipefail

ATTEMPT=/data1/home/sunyiq/autoresearch64/runs/unified_autoresearch/hbv_lite_64_hpc_reproduction_20260810_seq48
PYTHON=/data1/home/sunyiq/autoresearch64/.venv/bin/python

echo "=== EXACT JOB TERMINAL STATE ==="
sacct -j 202321 -X --format=JobID%12,JobName%20,NodeList%9,State%14,ExitCode%8,Elapsed%10

echo "=== INDEPENDENT MANIFEST CHECKS ==="
(
  cd "$ATTEMPT"
  sha256sum -c evidence/MANIFEST.sha256 >/dev/null
)
(
  cd "$ATTEMPT/snapshot"
  sha256sum -c "$ATTEMPT/evidence/SNAPSHOT_MANIFEST.sha256" >/dev/null
)
echo "manifest_check=ok"
echo "manifest_entries=$(wc -l < "$ATTEMPT/evidence/MANIFEST.sha256")"
echo "snapshot_manifest_check=ok"
echo "snapshot_manifest_entries=$(wc -l < "$ATTEMPT/evidence/SNAPSHOT_MANIFEST.sha256")"
sha256sum \
  "$ATTEMPT/evidence/REPRODUCTION_SUMMARY.json" \
  "$ATTEMPT/evidence/MANIFEST.sha256" \
  "$ATTEMPT/candidate_run/CANDIDATE_SUMMARY.json"

echo "=== INDEPENDENT CONTENT CHECK ==="
"$PYTHON" - "$ATTEMPT" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

attempt = Path(sys.argv[1])
summary = json.loads((attempt / "evidence" / "REPRODUCTION_SUMMARY.json").read_text(encoding="utf-8"))
candidate = json.loads((attempt / "candidate_run" / "CANDIDATE_SUMMARY.json").read_text(encoding="utf-8"))

assert summary["job_id"] == "202321"
assert summary["candidate_id"] == "hbv-lite-calibrated-v1"
assert summary["dependency_versions"] == {"numpy": "1.26.4", "pandas": "2.2.3", "pyarrow": "17.0.0"}
assert summary["targeted_test_gate"]["candidate_launch_allowed"] is True
assert summary["targeted_test_gate"]["passed"] == 26
assert summary["full_test_gate"]["candidate_launch_allowed"] is True
assert summary["full_test_gate"]["passed"] == 283
assert summary["full_test_gate"]["skipped"] == 8
assert summary["basin_count"] == summary["cell_count"] == 64
assert summary["runtime_count"] == summary["registered_run_count"] == 4
assert summary["score_report_count"] == 2
assert summary["independently_counted_denials"] == 0
assert summary["windows_reference_cells_exact_match"] is True
assert all(all(delta == 0 for delta in values.values()) for values in summary["metric_deltas_from_windows_reference"].values())
for name in (
    "sealed_final_evaluation_read_or_scored",
    "fair_benchmark_scoring_program_run",
    "formal_basin_search_run",
    "baseline_outperformance_claimed",
):
    assert summary[name] is False
    assert candidate[name] is False

runtime_paths = sorted((attempt / "candidate_run").rglob("runtime-result.json"))
assert len(runtime_paths) == 4
runtime_values = [json.loads(path.read_text(encoding="utf-8")) for path in runtime_paths]
assert all(value["status"] == "succeeded" for value in runtime_values)
assert all(value["process_exit_code"] == value["normalized_exit_code"] == 0 for value in runtime_values)
assert all(value["denied_event_count"] == 0 for value in runtime_values)
assert all(value["required_outputs_complete"] is True for value in runtime_values)

forbidden_terms = (
    "usgs_streamflow",
    "camels_hydro",
    "_obs_eval.parquet",
    "src/fair_benchmark/score.py",
)
access_paths = sorted((attempt / "candidate_run").rglob("access.jsonl"))
assert len(access_paths) == 4
access_event_count = 0
independent_denials = 0
for path in access_paths:
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line:
            continue
        access_event_count += 1
        event = json.loads(line)
        independent_denials += event.get("decision") == "deny"
        lowered = line.lower()
        assert not any(term in lowered for term in forbidden_terms)
assert independent_denials == 0

print(json.dumps({
    "job_id": summary["job_id"],
    "candidate_id": summary["candidate_id"],
    "basin_count": summary["basin_count"],
    "targeted_passed": summary["targeted_test_gate"]["passed"],
    "full_passed": summary["full_test_gate"]["passed"],
    "full_skipped": summary["full_test_gate"]["skipped"],
    "runtime_count": len(runtime_values),
    "process_exit_codes": [value["process_exit_code"] for value in runtime_values],
    "normalized_exit_codes": [value["normalized_exit_code"] for value in runtime_values],
    "required_outputs_complete": [value["required_outputs_complete"] for value in runtime_values],
    "access_log_count": len(access_paths),
    "access_event_count": access_event_count,
    "independent_denials": independent_denials,
    "forbidden_access_hits": 0,
    "windows_reference_cells_exact_match": summary["windows_reference_cells_exact_match"],
    "group_metrics": summary["group_metrics"],
}, sort_keys=True))
PY
exit 0

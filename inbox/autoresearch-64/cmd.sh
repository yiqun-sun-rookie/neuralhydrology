#!/bin/bash
set -o pipefail

ROOT=/data1/home/sunyiq/autoresearch64
PYTHON="$ROOT/.venv/bin/python"
ATTEMPT="$ROOT/runs/unified_autoresearch/automatic_rehearsal_8x3_20260811_seq59"
EVIDENCE="$ATTEMPT/evidence"
REHEARSAL="$ATTEMPT/rehearsal"

echo "=== COMPLETED JOB ==="
sacct -j 202556 -X --format=JobID%12,JobName%20,NodeList%9,State%14,ExitCode%8,Elapsed%10,Start%20,End%20

echo "=== IMMUTABLE EVIDENCE FILES ==="
for path in \
  "$EVIDENCE/FULL_GATE.json" \
  "$EVIDENCE/PACKAGE_GATE.json" \
  "$REHEARSAL/PROPOSAL_REGISTRY.json" \
  "$REHEARSAL/REHEARSAL_SUMMARY.json" \
  "$EVIDENCE/REHEARSAL_EVIDENCE.json" \
  "$EVIDENCE/MANIFEST.sha256"; do
  test -f "$path" || { echo "HOLD missing=$path"; exit 20; }
  stat -c '%n|bytes=%s|mtime=%y' "$path"
  sha256sum "$path"
done

echo "=== COMPLETE MANIFEST CHECK ==="
(cd "$ATTEMPT" && sha256sum -c evidence/MANIFEST.sha256 >/dev/null)
echo "manifest_check=ok entries=$(wc -l < "$EVIDENCE/MANIFEST.sha256")"

echo "=== INDEPENDENT SUMMARY ==="
"$PYTHON" - "$EVIDENCE/REHEARSAL_EVIDENCE.json" "$REHEARSAL/REHEARSAL_SUMMARY.json" <<'PY'
import json
import sys
from pathlib import Path

evidence = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
loop = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
assert evidence["job_id"] == "202556"
assert evidence["retry_of_job_id"] == "202551"
assert evidence["full_test_gate"] == {
    "candidate_launch_allowed": True,
    "errors": 0,
    "failures": 0,
    "passed": 291,
    "process_exit_code": 0,
    "schema_version": "unified_autoresearch_linux_test_gate_v1",
    "skipped": 8,
    "tests": 299,
}
assert evidence["candidate_count"] == 3
assert evidence["runtime_count"] == 12
assert evidence["score_report_count"] == 6
assert evidence["protocol_basin_metric_count"] == 48
assert evidence["cell_count"] == 24
assert evidence["independently_counted_denials"] == 0
assert all(row["status"] == "succeeded" for row in evidence["runtimes"])
assert all(row["process_exit_code"] == 0 for row in evidence["runtimes"])
assert all(row["normalized_exit_code"] == 0 for row in evidence["runtimes"])
assert all(row["required_outputs_complete"] is True for row in evidence["runtimes"])
assert loop["recommended_candidate_id"] == evidence["recommended_candidate_id"]
print(json.dumps({
    "experiment_id": evidence["experiment_id"],
    "job_id": evidence["job_id"],
    "retry_of_job_id": evidence["retry_of_job_id"],
    "full_test_gate": evidence["full_test_gate"],
    "candidate_count": evidence["candidate_count"],
    "runtime_count": evidence["runtime_count"],
    "score_report_count": evidence["score_report_count"],
    "protocol_basin_metric_count": evidence["protocol_basin_metric_count"],
    "cell_count": evidence["cell_count"],
    "process_exit_codes": [row["process_exit_code"] for row in evidence["runtimes"]],
    "normalized_exit_codes": [row["normalized_exit_code"] for row in evidence["runtimes"]],
    "required_outputs_complete": [row["required_outputs_complete"] for row in evidence["runtimes"]],
    "independently_counted_denials": evidence["independently_counted_denials"],
    "independently_recomputed_median_mean_nse": evidence["independently_recomputed_median_mean_nse"],
    "independently_recomputed_ranking": evidence["independently_recomputed_ranking"],
    "recommended_candidate_id": evidence["recommended_candidate_id"],
    "dependency_versions": evidence["dependency_versions"],
}, sort_keys=True))
PY
echo "GO read_only_reverification=pass"
exit 0

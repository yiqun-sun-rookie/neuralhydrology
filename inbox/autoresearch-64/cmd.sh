#!/bin/bash
set -eo pipefail

cd /data1/home/sunyiq/hpc_mailbox || exit 1

echo "=== SUBMIT MAILBOX-INDEPENDENT LOGGED 64-BASIN REPRODUCTION ==="
JID=$(sbatch --parsable inbox/autoresearch-64/hbv_lite_64_reproduction_seq48.slurm 2>&1)
echo "jobid=$JID"

echo "=== WAIT FOR THIS EXACT JOB ==="
for i in $(seq 1 400); do
  STATE=$(sacct -j "$JID" -X -n -o State 2>/dev/null | head -1 | tr -d ' ')
  case "$STATE" in
    COMPLETED|FAILED|CANCELLED|TIMEOUT|NODE_FAIL|OUT_OF_MEMORY)
      break
      ;;
  esac
  [ $((i % 6)) -eq 0 ] && echo "t=$((i * 10))s state=${STATE:-UNKNOWN}"
  sleep 10
done

echo "=== JOB ACCOUNTING ==="
sacct -j "$JID" -X --format=JobID%12,JobName%20,NodeList%9,State%14,ExitCode%8,Elapsed%10

echo "=== EXACT JOB STANDARD OUTPUT ==="
tail -120 "outbox/slurm_${JID}.out" 2>/dev/null || true

echo "=== EXACT JOB STANDARD ERROR ==="
tail -120 "outbox/slurm_${JID}.err" 2>/dev/null || true

ATTEMPT=/data1/home/sunyiq/autoresearch64/runs/unified_autoresearch/hbv_lite_64_hpc_reproduction_20260810_seq48
echo "=== STABLE ATTEMPT JOB OUTPUT ==="
tail -120 "$ATTEMPT/evidence/JOB_STDOUT.txt" 2>/dev/null || true
echo "=== STABLE ATTEMPT JOB ERROR ==="
tail -120 "$ATTEMPT/evidence/JOB_STDERR.txt" 2>/dev/null || true

echo "=== EVIDENCE STATUS ==="
for path in \
  "$ATTEMPT/evidence/JOB_STDOUT.txt" \
  "$ATTEMPT/evidence/JOB_STDERR.txt" \
  "$ATTEMPT/evidence/SNAPSHOT_MANIFEST.sha256" \
  "$ATTEMPT/evidence/SNAPSHOT_GIT_COMMIT.txt" \
  "$ATTEMPT/evidence/TARGETED_GATE.json" \
  "$ATTEMPT/evidence/FULL_GATE.json" \
  "$ATTEMPT/evidence/PACKAGE_GATE.json" \
  "$ATTEMPT/candidate_run/CANDIDATE_SUMMARY.json" \
  "$ATTEMPT/evidence/REPRODUCTION_SUMMARY.json" \
  "$ATTEMPT/evidence/MANIFEST.sha256"; do
  if [ -f "$path" ]; then
    echo "EXISTS $path"
  else
    echo "MISSING $path"
  fi
done

if [ -f "$ATTEMPT/evidence/TARGETED_GATE.json" ]; then
  echo "targeted_gate=$(tr -d '\n ' < "$ATTEMPT/evidence/TARGETED_GATE.json")"
fi
if [ -f "$ATTEMPT/evidence/FULL_GATE.json" ]; then
  echo "full_gate=$(tr -d '\n ' < "$ATTEMPT/evidence/FULL_GATE.json")"
fi
if [ -f "$ATTEMPT/evidence/REPRODUCTION_SUMMARY.json" ]; then
  /data1/home/sunyiq/autoresearch64/.venv/bin/python - "$ATTEMPT/evidence/REPRODUCTION_SUMMARY.json" <<'PY'
import json
import sys

summary = json.load(open(sys.argv[1], encoding="utf-8"))
print(json.dumps({
    "experiment_id": summary["experiment_id"],
    "job_id": summary["job_id"],
    "candidate_id": summary["candidate_id"],
    "targeted_test_gate": summary["targeted_test_gate"],
    "full_test_gate": summary["full_test_gate"],
    "basin_count": summary["basin_count"],
    "registered_run_count": summary["registered_run_count"],
    "score_report_count": summary["score_report_count"],
    "runtime_count": summary["runtime_count"],
    "process_exit_codes": [item["process_exit_code"] for item in summary["runtimes"]],
    "normalized_exit_codes": [item["normalized_exit_code"] for item in summary["runtimes"]],
    "runtime_statuses": [item["status"] for item in summary["runtimes"]],
    "required_outputs_complete": [item["required_outputs_complete"] for item in summary["runtimes"]],
    "independently_counted_denials": summary["independently_counted_denials"],
    "group_metrics": summary["group_metrics"],
    "metric_deltas_from_windows_reference": summary["metric_deltas_from_windows_reference"],
    "windows_reference_cells_exact_match": summary["windows_reference_cells_exact_match"],
    "dependency_versions": summary["dependency_versions"],
}, sort_keys=True))
PY
fi

if [ -f "$ATTEMPT/evidence/MANIFEST.sha256" ]; then
  (cd "$ATTEMPT" && sha256sum -c evidence/MANIFEST.sha256 >/dev/null)
  echo "manifest_check=ok"
  echo "manifest_entries=$(wc -l < "$ATTEMPT/evidence/MANIFEST.sha256")"
fi

echo "summary=$ATTEMPT/evidence/REPRODUCTION_SUMMARY.json"
echo "manifest=$ATTEMPT/evidence/MANIFEST.sha256"
exit 0

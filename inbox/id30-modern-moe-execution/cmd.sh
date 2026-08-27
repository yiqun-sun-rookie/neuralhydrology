#!/bin/bash
set -eo pipefail

TARGET=/data1/home/sunyiq/id30_modern_transformer_moe_20260827
ROOT="$TARGET/repo"
JOB_ID=$(tr -d '[:space:]' < "$TARGET/deployment/preselection_gates_job_id_v01.txt")
JOB_NUM=$(printf '%s' "$JOB_ID" | cut -d';' -f1)

echo "=== PRESELECTION GATE STATUS ==="
date -Is
hostname
echo "job_id=$JOB_NUM"
squeue -j "$JOB_NUM" -o '%.18i %.12P %.28j %.8T %.10M %.30R' || true
sacct -j "$JOB_NUM" --format=JobID,JobName,Partition,State,ExitCode,Elapsed,NodeList,MaxRSS -n -P || true

echo "=== LOG TAILS ==="
for log in "$ROOT"/logs/30_modern_transformer_moe/preselection-gates-"$JOB_NUM".out \
           "$ROOT"/logs/30_modern_transformer_moe/preselection-gates-"$JOB_NUM".err; do
  echo "--- $log"
  if [ -f "$log" ]; then
    tail -260 "$log"
  else
    echo "NOT_CREATED"
  fi
done

echo "=== RESOURCE REPORT SUMMARY ==="
python - "$ROOT" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
report_root = root / "results/30_modern_transformer_moe/_gpu_resource_probes"
reports = sorted(report_root.glob("id30_*_s100_slurm*/probe_report.json"))
if not reports:
    print("NO_PROBE_REPORTS")
for path in reports:
    report = json.loads(path.read_text(encoding="utf-8"))
    summary = {
        "path": str(path.relative_to(root)),
        "experiment_id": report.get("experiment_id"),
        "status": report.get("status"),
        "overall_status": report.get("overall_status"),
        "failure_stage": report.get("failure_stage"),
        "error_type": report.get("error_type"),
        "error": report.get("error"),
        "peak_reserved_bytes": report.get("memory", {}).get("peak_reserved_bytes"),
        "total_parameters": report.get("actual", {}).get("total_parameters"),
        "checks": report.get("checks"),
    }
    print(json.dumps(summary, sort_keys=True))
PY

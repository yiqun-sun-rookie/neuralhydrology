#!/bin/bash
set -o pipefail

JID=202243
ATTEMPT=/data1/home/sunyiq/autoresearch64/runs/unified_autoresearch/hbv_lite_8_hpc_smoke_20260810_seq36

echo "=== JOB ACCOUNTING ==="
squeue -j "$JID" -h -o 'job=%i state=%T elapsed=%M node=%N' 2>&1 || true
sacct -j "$JID" -X --format=JobID%12,JobName%20,State%14,ExitCode%8,Elapsed%10,NodeList%12 2>&1 || true

echo "=== EXACT JOB LOGS ==="
tail -120 "outbox/slurm_${JID}.out" 2>/dev/null || true
tail -120 "outbox/slurm_${JID}.err" 2>/dev/null || true

echo "=== EVIDENCE STATUS ==="
for path in \
  "$ATTEMPT/candidate_run/CANDIDATE_SUMMARY.json" \
  "$ATTEMPT/evidence/SMOKE_SUMMARY.json" \
  "$ATTEMPT/evidence/MANIFEST.sha256"
do
  if [ -f "$path" ]; then echo "EXISTS $path"; else echo "MISSING $path"; fi
done

if [ -f "$ATTEMPT/evidence/SMOKE_SUMMARY.json" ]; then
  /data1/home/sunyiq/autoresearch64/.venv/bin/python - "$ATTEMPT/evidence/SMOKE_SUMMARY.json" <<'PY'
import json
import sys
from pathlib import Path

value = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
print(json.dumps({
    "experiment_id": value["experiment_id"],
    "job_id": value["job_id"],
    "candidate_id": value["candidate_id"],
    "basin_count": value["basin_count"],
    "cell_count": value["cell_count"],
    "runtime_count": value["runtime_count"],
    "independently_counted_denials": value["independently_counted_denials"],
    "dependency_versions": value["dependency_versions"],
    "runtime_statuses": [runtime["status"] for runtime in value["runtimes"]],
    "process_exit_codes": [runtime["process_exit_code"] for runtime in value["runtimes"]],
    "normalized_exit_codes": [runtime["normalized_exit_code"] for runtime in value["runtimes"]],
    "required_outputs_complete": [runtime["required_outputs_complete"] for runtime in value["runtimes"]],
}, sort_keys=True))
PY
fi

if [ -f "$ATTEMPT/evidence/MANIFEST.sha256" ]; then
  (cd "$ATTEMPT" && sha256sum -c evidence/MANIFEST.sha256 >/dev/null) && echo "manifest_check=ok" || echo "manifest_check=failed"
  echo "manifest_entries=$(wc -l < "$ATTEMPT/evidence/MANIFEST.sha256")"
fi
exit 0

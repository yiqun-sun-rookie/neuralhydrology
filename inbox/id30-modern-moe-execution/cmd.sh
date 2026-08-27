#!/bin/bash
set -eo pipefail

TARGET=/data1/home/sunyiq/id30_modern_transformer_moe_20260827
ROOT="$TARGET/repo"
JOB_ID=$(tr -d '[:space:]' < "$TARGET/deployment/development_B01_s100_job_id_v01.txt")
JOB_NUM=$(printf '%s' "$JOB_ID" | cut -d';' -f1)

echo "=== B01 DEVELOPMENT STATUS ==="
date -Is
hostname
echo "job_id=$JOB_NUM"
squeue -j "$JOB_NUM" -o '%.18i %.12P %.28j %.8T %.10M %.30R' || true
sacct -j "$JOB_NUM" --format=JobID,JobName,Partition,State,ExitCode,Elapsed,NodeList,MaxRSS -n -P || true

echo "=== SLURM LOG TAILS ==="
for log in "$ROOT"/logs/30_modern_transformer_moe/development-"$JOB_NUM".out \
           "$ROOT"/logs/30_modern_transformer_moe/development-"$JOB_NUM".err; do
  echo "--- $log"
  if [ -f "$log" ]; then
    tail -120 "$log"
  else
    echo "NOT_CREATED"
  fi
done

echo "=== B01 RUN STATE ==="
python - "$ROOT" "$JOB_NUM" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
job_id = sys.argv[2]
run_id = f"id30_B01_s100_slurm{job_id}"

bindings_path = root / "src/modern_transformer_moe/registry/development_run_bindings.json"
bindings = json.loads(bindings_path.read_text(encoding="utf-8"))
records = [record for record in bindings["records"] if record["role"] == "B01" and record["seed"] == 100]
print(json.dumps({"matching_binding_count": len(records), "records": records}, sort_keys=True))

invocation_path = root / "results/30_modern_transformer_moe/_development_invocations" / run_id / "run_manifest.json"
if invocation_path.is_file():
    manifest = json.loads(invocation_path.read_text(encoding="utf-8"))
    keys = (
        "run_id",
        "role",
        "seed",
        "status",
        "failure_stage",
        "failure_reason",
        "created_at_utc",
        "updated_at_utc",
        "last_heartbeat_at_utc",
        "child_process",
        "run_dir",
        "metrics_artifact_path",
    )
    print(json.dumps({key: manifest.get(key) for key in keys}, sort_keys=True))
    for name in ("training_stdout.log", "training_stderr.log"):
        path = invocation_path.parent / name
        print(json.dumps({"path": str(path.relative_to(root)), "exists": path.is_file(), "bytes": path.stat().st_size if path.is_file() else 0}))
else:
    print(json.dumps({"invocation_manifest": "NOT_CREATED", "expected_run_id": run_id}))
PY

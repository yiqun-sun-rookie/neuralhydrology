#!/bin/bash
set -eo pipefail

TARGET=/data1/home/sunyiq/id30_modern_transformer_moe_20260827
ROOT="$TARGET/repo"

declare -A RECORDS=(
  [B01]="$TARGET/deployment/development_B01_s100_job_id_v01.txt"
  [D01]="$TARGET/deployment/development_D01_s100_job_id_v01.txt"
  [D02]="$TARGET/deployment/development_D02_s100_job_id_v01.txt"
  [D03]="$TARGET/deployment/development_D03_s100_job_id_v01.txt"
  [SELECT]="$TARGET/deployment/dense_selection_job_id_v01.txt"
  [M01]="$TARGET/deployment/development_M01_s100_job_id_v01.txt"
)

echo "=== ID30 SEED-100 CHAIN STATUS ==="
date -Is
hostname
JOB_LIST=
for role in B01 D01 D02 D03 SELECT M01; do
  submission=$(tr -d '[:space:]' < "${RECORDS[$role]}")
  job_id=$(printf '%s' "$submission" | cut -d';' -f1)
  echo "$role=$job_id"
  if [ -z "$JOB_LIST" ]; then JOB_LIST=$job_id; else JOB_LIST="$JOB_LIST,$job_id"; fi
done
squeue -j "$JOB_LIST" -o '%.18i %.12P %.28j %.8T %.10M %.30R' || true
sacct -j "$JOB_LIST" --format=JobID,JobName,Partition,State,ExitCode,Elapsed,NodeList,MaxRSS -n -P || true

echo "=== REGISTRY, HEARTBEAT, AND MILESTONES ==="
python - "$ROOT" <<'PY'
import json
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
bindings_path = root / "src/modern_transformer_moe/registry/development_run_bindings.json"
bindings = json.loads(bindings_path.read_text(encoding="utf-8"))
summary = []
for record in bindings["records"]:
    if record["seed"] != 100 or record["role"] not in {"B01", "D01", "D02", "D03", "M01"}:
        continue
    item = {
        "role": record["role"],
        "seed": record["seed"],
        "run_id": record["run_id"],
        "status": record["status"],
        "run_dir": record["run_dir"],
        "metrics_artifact_path": record["metrics_artifact_path"],
        "failure_stage": record["failure_stage"],
        "failure_reason": record["failure_reason"],
    }
    manifest_path = root / record["invocation_manifest_path"]
    if manifest_path.is_file():
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        item["manifest_status"] = manifest.get("status")
        item["last_heartbeat_at_utc"] = manifest.get("last_heartbeat_at_utc")
        item["child_process"] = manifest.get("child_process")
        stdout_path = manifest_path.parent / "training_stdout.log"
        stderr_path = manifest_path.parent / "training_stderr.log"
        item["training_stdout_bytes"] = stdout_path.stat().st_size if stdout_path.is_file() else 0
        item["training_stderr_bytes"] = stderr_path.stat().st_size if stderr_path.is_file() else 0
        if stdout_path.is_file():
            text = stdout_path.read_text(encoding="utf-8", errors="replace").replace("\r", "\n")
            ansi = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]")
            milestones = []
            for raw_line in text.splitlines():
                line = ansi.sub("", raw_line).strip()
                if not line or re.search(r"\d+%\|", line):
                    continue
                lowered = line.lower()
                if any(token in lowered for token in ("epoch", "average loss", "median nse", "starting training", "finished training", "validation metrics")):
                    milestones.append(line[:600])
            item["latest_milestones"] = milestones[-20:]
    summary.append(item)
print(json.dumps({"records": sorted(summary, key=lambda item: item["role"])}, indent=2, sort_keys=True))

checkpoints = sorted((root / "results/30_modern_transformer_moe/B01").glob("**/model_epoch*.pt"))
print(json.dumps({
    "b01_checkpoint_count": len(checkpoints),
    "latest_b01_checkpoints": [str(path.relative_to(root)) for path in checkpoints[-5:]],
}, indent=2, sort_keys=True))
PY

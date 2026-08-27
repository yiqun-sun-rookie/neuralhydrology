#!/bin/bash
set -eo pipefail
umask 077

TARGET=/data1/home/sunyiq/id30_modern_transformer_moe_20260827
ROOT="$TARGET/repo"
PAYLOAD="$HOME/hpc_mailbox/payload/id30-modern-moe-execution/id30_probe_cli_overlay_20260827_v06.tar.gz"
EXPECTED=c0cd9ba0a536cc0bd81285d1beff69629a68e2a553c00afa5164278262766abb
EXPECTED_BASE=230a81f3f6c59e9c680263ec2bec586f0195cac1
FAILED_JOB=$(tr -d '[:space:]' < "$TARGET/deployment/preselection_gates_job_id_v03.txt")
FAILED_JOB_NUM=$(printf '%s' "$FAILED_JOB" | cut -d';' -f1)
NEW_JOB_RECORD="$TARGET/deployment/preselection_gates_job_id_v04.txt"

echo "=== VERIFY THIRD CONTROLLED RETRY PRECONDITIONS ==="
date -Is
hostname
FAILED_STATE=$(sacct -j "$FAILED_JOB_NUM" --format=State -n -P | head -1)
echo "failed_job_id=$FAILED_JOB_NUM failed_state=$FAILED_STATE"
test "$FAILED_STATE" = "FAILED"
test ! -e "$NEW_JOB_RECORD"
PASS_REPORT="$ROOT/results/30_modern_transformer_moe/_gpu_resource_probes/id30_B01_s100_slurm$FAILED_JOB_NUM/probe_report.json"
python - "$PASS_REPORT" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
report = json.loads(path.read_text(encoding="utf-8"))
assert report["experiment_id"] == "B01"
assert report["status"] == "COMPLETE"
assert report["overall_status"] == "PASS"
assert all(report["checks"].values())
print("PRESERVED_B01_PASS", path.stat().st_size)
PY
echo "preserved_b01_report=$(sha256sum "$PASS_REPORT" | awk '{print $1}') $PASS_REPORT"
ACTUAL=$(sha256sum "$PAYLOAD" | awk '{print $1}')
echo "expected_payload=$EXPECTED"
echo "actual_payload=$ACTUAL"
test "$ACTUAL" = "$EXPECTED"
cd "$ROOT"
ACTUAL_BASE=$(git rev-parse HEAD)
echo "expected_base=$EXPECTED_BASE"
echo "actual_base=$ACTUAL_BASE"
test "$ACTUAL_BASE" = "$EXPECTED_BASE"
git diff --quiet
git diff --cached --quiet

echo "=== INSTALL AND FREEZE V06 PROBE-CLI OVERLAY ==="
cp "$PAYLOAD" "$TARGET/deployment/"
tar -xzf "$PAYLOAD" -C "$ROOT"
git add -- \
  src/modern_transformer_moe/scripts/run_full_size_gpu_probe.py \
  test/test_modern_transformer_moe_gpu_probe.py
git diff --cached --quiet && { echo "V06 overlay produced no source change"; exit 30; }
git commit -q -m "Freeze ID30 probe CLI overlay v06"
NEW_COMMIT=$(git rev-parse HEAD)
echo "v06_commit=$NEW_COMMIT"
printf '%s  %s\n' "$EXPECTED" "id30_probe_cli_overlay_20260827_v06.tar.gz" > \
  "$TARGET/deployment/probe_cli_overlay_v06.sha256"
printf '%s\n' "$NEW_COMMIT" > "$TARGET/deployment/repository_commit_v06.txt"

echo "=== SUBMIT THIRD CONTROLLED PRESELECTION RETRY ==="
NEW_JOB=$(sbatch --parsable src/modern_transformer_moe/hpc/submit_preselection_gates.slurm)
printf '%s\n' "$NEW_JOB" | tee "$NEW_JOB_RECORD"
NEW_JOB_NUM=$(printf '%s' "$NEW_JOB" | cut -d';' -f1)
scontrol update jobid="$NEW_JOB_NUM" partition=hgpu2
sleep 2
squeue -j "$NEW_JOB_NUM" -o '%.18i %.12P %.28j %.8T %.10M %.30R' || true
echo "=== COMPLETE ==="
date -Is

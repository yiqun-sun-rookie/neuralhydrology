#!/bin/bash
set -eo pipefail
umask 077

TARGET=/data1/home/sunyiq/id30_modern_transformer_moe_20260827
ROOT="$TARGET/repo"
PAYLOAD="$HOME/hpc_mailbox/payload/id30-modern-moe-execution/id30_probe_json_overlay_20260827_v05.tar.gz"
EXPECTED=0fe843d535fad7ab7a471b3ef38a7a1e5ec01982675965b19231840308722583
EXPECTED_BASE=457d3ac08eb1f4afe1cb7e8d0d18f588646bfb41
FAILED_JOB=$(tr -d '[:space:]' < "$TARGET/deployment/preselection_gates_job_id_v02.txt")
FAILED_JOB_NUM=$(printf '%s' "$FAILED_JOB" | cut -d';' -f1)
NEW_JOB_RECORD="$TARGET/deployment/preselection_gates_job_id_v03.txt"

echo "=== VERIFY SECOND CONTROLLED RETRY PRECONDITIONS ==="
date -Is
hostname
FAILED_STATE=$(sacct -j "$FAILED_JOB_NUM" --format=State -n -P | head -1)
echo "failed_job_id=$FAILED_JOB_NUM failed_state=$FAILED_STATE"
test "$FAILED_STATE" = "FAILED"
test ! -e "$NEW_JOB_RECORD"
CORRUPT_REPORT="$ROOT/results/30_modern_transformer_moe/_gpu_resource_probes/id30_B01_s100_slurm$FAILED_JOB_NUM/probe_report.json"
test -f "$CORRUPT_REPORT"
echo "preserved_failed_report=$(stat -c '%s' "$CORRUPT_REPORT") $(sha256sum "$CORRUPT_REPORT" | awk '{print $1}') $CORRUPT_REPORT"
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

echo "=== INSTALL AND FREEZE V05 PROBE-JSON OVERLAY ==="
cp "$PAYLOAD" "$TARGET/deployment/"
tar -xzf "$PAYLOAD" -C "$ROOT"
git add -- \
  src/modern_transformer_moe/scripts/run_full_size_gpu_probe.py \
  test/test_modern_transformer_moe_gpu_probe.py
git diff --cached --quiet && { echo "V05 overlay produced no source change"; exit 30; }
git commit -q -m "Freeze ID30 probe JSON overlay v05"
NEW_COMMIT=$(git rev-parse HEAD)
echo "v05_commit=$NEW_COMMIT"
printf '%s  %s\n' "$EXPECTED" "id30_probe_json_overlay_20260827_v05.tar.gz" > \
  "$TARGET/deployment/probe_json_overlay_v05.sha256"
printf '%s\n' "$NEW_COMMIT" > "$TARGET/deployment/repository_commit_v05.txt"

echo "=== SUBMIT SECOND CONTROLLED PRESELECTION RETRY ==="
NEW_JOB=$(sbatch --parsable src/modern_transformer_moe/hpc/submit_preselection_gates.slurm)
printf '%s\n' "$NEW_JOB" | tee "$NEW_JOB_RECORD"
NEW_JOB_NUM=$(printf '%s' "$NEW_JOB" | cut -d';' -f1)
scontrol update jobid="$NEW_JOB_NUM" partition=hgpu2
sleep 2
squeue -j "$NEW_JOB_NUM" -o '%.18i %.12P %.28j %.8T %.10M %.30R' || true
echo "=== COMPLETE ==="
date -Is

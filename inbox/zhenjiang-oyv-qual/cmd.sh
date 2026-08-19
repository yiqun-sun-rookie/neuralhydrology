#!/usr/bin/env bash
# zhenjiang out-of-year validation :: step 8, submit the formal training array
#
# Every gate the preregistration names is satisfied: the owner decisions are
# accepted, the digest chain verified on this cluster with zero mismatches, the
# static audit passed as batch job 205645 with zero findings, the smoke task
# completed, and the execution authorisation has been given.
#
# This script only submits and reports. It does not compute.
set -o pipefail

ROOT=/data1/home/sunyiq/zhenjiang_oyv_v1

echo "=== A. GUARDS ==="
if [ -d "$ROOT/tasks" ] && [ -n "$(ls -A "$ROOT/tasks" 2>/dev/null)" ]; then
    echo "FORMAL_TASK_ROOT_NOT_EMPTY"
    ls -1 "$ROOT/tasks" | head -5
    echo "ABORT: refusing to write into an existing formal task root"
    exit 1
fi
cd "$ROOT/repo" || { echo "REPO_MISSING"; exit 1; }
echo "bundle_commit=$(git rev-parse HEAD)"
df -h /data1 2>&1 | tail -1

echo "=== B. SUBMIT THE 480 TASK ARRAY ==="
JID=$(sbatch --parsable scripts/modeling/hpc/submit_zhenjiang_oyv_v1.slurm 2>&1)
echo "training_array_job=$JID"
case "$JID" in
    ''|*[!0-9]*) echo "SBATCH_FAILED"; exit 1 ;;
esac
printf '%s\n' "$JID" > "$ROOT/training_array_jobid"

echo "=== C. EARLY PROGRESS (20 min window) ==="
for i in $(seq 1 120); do
    LEFT=$(squeue -j "$JID" -h -o "%i" 2>/dev/null | wc -l)
    DONE=$(ls -1 "$ROOT/tasks" 2>/dev/null | wc -l)
    [ $((i % 12)) -eq 0 ] && echo "t=$((i * 10))s queue_entries=$LEFT completed_task_dirs=$DONE"
    [ "$LEFT" -eq 0 ] && break
    sleep 10
done

echo "=== D. SNAPSHOT ==="
squeue -j "$JID" -h -o '%.14i %.9T %.8M %.10R' 2>/dev/null | head -8 || true
echo "queue_entries=$(squeue -j "$JID" -h -o '%i' 2>/dev/null | wc -l)"
echo "completed_task_dirs=$(ls -1 "$ROOT/tasks" 2>/dev/null | wc -l)"
sacct -j "$JID" -X --format=State%14 --noheader 2>/dev/null | sort | uniq -c | head -10 || true

echo "=== E. FIRST FINISHED TASK ==="
FIRST=$(ls -1 "$ROOT/tasks" 2>/dev/null | head -1)
if [ -n "$FIRST" ]; then
    echo "task=$FIRST"
    grep -E '"best_epoch"|"completed_epochs"|"elapsed_seconds"|"node_name"|"test_sample_count"' \
        "$ROOT/tasks/$FIRST/run_identity.json" 2>/dev/null | head -8 || true
fi
echo "=== END ==="

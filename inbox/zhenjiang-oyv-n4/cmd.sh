#!/bin/bash
# Four-target ladder: queue the formal array behind the already-queued smoke job.
#
# Why both are queued rather than one after the other: hgpu2p is fully occupied
# and the smoke job's estimated start is three days out, so waiting for it before
# submitting would stall the family for three days at no benefit. The smoke job
# was submitted first and asks for identical resources, so it keeps its priority
# ahead of every array task. The gate is preserved in order, not abandoned: if the
# smoke fails, the array is cancelled before it can consume anything.
set -o pipefail

ROOT=/data1/home/sunyiq/zhenjiang_oyv_v1
SMOKE=212898

echo "=== A. HOST ==="
hostname; date -u +%Y-%m-%dT%H:%M:%SZ

echo "=== B. PRE-SUBMIT GUARDS ==="
if [ -e "$ROOT/n4_tasks" ]; then echo "  n4_tasks exists -> stop condition"; echo "STATUS=OUTPUT_ROOT_EXISTS"; exit 1; fi
echo "  n4_tasks absent -> ok"
SST=$(sacct -j "$SMOKE" -X -n -o State 2>/dev/null | head -1 | awk '{print $1}')
echo "  smoke ${SMOKE} state=${SST:-unknown}"
case "$SST" in
  FAILED|CANCELLED*|TIMEOUT|NODE_FAIL|OUT_OF_MEMORY)
    echo "  smoke already failed -> refusing to submit"; echo "STATUS=SMOKE_FAILED"; exit 1;;
esac

echo "=== C. SUBMIT THE FORMAL ARRAY ==="
cd "$ROOT/repo" || exit 1
echo "  repo head: $(git log --oneline -1)"
sed -i 's/\r$//' scripts/modeling/hpc/submit_zhenjiang_oyv_n4.slurm
out=$(sbatch scripts/modeling/hpc/submit_zhenjiang_oyv_n4.slurm 2>&1); echo "$out"
AID=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+' || true)
[ -n "$AID" ] || { echo "SUBMIT_FAILED"; echo "STATUS=SUBMIT_FAILED"; exit 1; }
echo "  array job id = $AID"

echo "=== D. QUEUE AFTER SUBMIT ==="
sleep 20
echo "  my entries: $(squeue -u "$USER" -h -o '%i' 2>/dev/null | wc -l)"
squeue -u "$USER" -h -o "%.18i %.14j %.9T %.9r" 2>/dev/null | head -12 || true
echo "  smoke est start: $(squeue -j "$SMOKE" -h --start -o '%S' 2>/dev/null)"
echo "ARRAY_JOB_ID=$AID"
echo "SMOKE_JOB_ID=$SMOKE"
echo "STATUS=ARRAY_QUEUED"

echo "=== E. DONE ==="

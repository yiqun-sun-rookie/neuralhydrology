#!/bin/bash
# Four-target ladder: sync the split-array launcher, then submit both halves.
set -o pipefail

ROOT=/data1/home/sunyiq/zhenjiang_oyv_v1
SMOKE=212898
EXPECT_SLURM=360e6248ade646bc805f203e9378e81035c487eb9b442a8e22e9b784c85f126b

echo "=== A. HOST AND SCHEDULER LIMIT ==="
hostname; date -u +%Y-%m-%dT%H:%M:%SZ
scontrol show config 2>/dev/null | grep -i -E 'MaxArraySize|MaxJobCount|MaxSubmitJobs' || echo "  (limits not readable)"

echo "=== B. SYNC ==="
cd "$ROOT/repo" || exit 1
TRACKED_DIRTY=$(git status --porcelain | grep -v '^?? ' | head -5)
if [ -n "$TRACKED_DIRTY" ]; then echo "  tracked files modified, refusing:"; echo "$TRACKED_DIRTY"; exit 1; fi
echo "before: $(git log --oneline -1)"
timeout 180 git fetch -q origin "+refs/heads/main:refs/remotes/origin/main" || { echo "FETCH_FAILED"; exit 1; }
git reset -q --hard refs/remotes/origin/main
echo "after : $(git log --oneline -1)"
sed -i 's/\r$//' scripts/modeling/hpc/submit_zhenjiang_oyv_n4.slurm
GOT=$(sha256sum scripts/modeling/hpc/submit_zhenjiang_oyv_n4.slurm | cut -d' ' -f1)
if [ "$GOT" = "$EXPECT_SLURM" ]; then echo "  launcher identity ok"; else echo "  launcher MISMATCH"; echo "    expected $EXPECT_SLURM"; echo "    observed $GOT"; exit 1; fi
grep -E '^#SBATCH --array' scripts/modeling/hpc/submit_zhenjiang_oyv_n4.slurm || true

echo "=== C. GUARDS ==="
if [ -e "$ROOT/n4_tasks" ]; then echo "  n4_tasks exists -> stop"; echo "STATUS=OUTPUT_ROOT_EXISTS"; exit 1; fi
echo "  n4_tasks absent -> ok"
SST=$(sacct -j "$SMOKE" -X -n -o State 2>/dev/null | head -1 | awk '{print $1}')
echo "  smoke ${SMOKE} state=${SST:-unknown}"
case "$SST" in
  FAILED|CANCELLED*|TIMEOUT|NODE_FAIL|OUT_OF_MEMORY) echo "  smoke failed -> refusing"; echo "STATUS=SMOKE_FAILED"; exit 1;;
esac

echo "=== D. SUBMIT HALF ONE (offset 0) ==="
o1=$(sbatch --export=ALL,N4_INDEX_OFFSET=0 scripts/modeling/hpc/submit_zhenjiang_oyv_n4.slurm 2>&1); echo "$o1"
A1=$(echo "$o1" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+' || true)
[ -n "$A1" ] || { echo "SUBMIT_FAILED_HALF_1"; echo "STATUS=SUBMIT_FAILED"; exit 1; }
echo "  half one array id = $A1"

echo "=== E. SUBMIT HALF TWO (offset 720) ==="
o2=$(sbatch --export=ALL,N4_INDEX_OFFSET=720 scripts/modeling/hpc/submit_zhenjiang_oyv_n4.slurm 2>&1); echo "$o2"
A2=$(echo "$o2" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+' || true)
if [ -z "$A2" ]; then
  echo "SUBMIT_FAILED_HALF_2 - cancelling half one to keep the family all-or-nothing"
  scancel "$A1" 2>&1 || true
  echo "STATUS=SUBMIT_FAILED"; exit 1
fi
echo "  half two array id = $A2"

echo "=== F. QUEUE ==="
sleep 20
echo "  my entries: $(squeue -u "$USER" -h -o '%i' 2>/dev/null | wc -l)"
squeue -u "$USER" -h -o "%.20i %.12j %.9T %.10r" 2>/dev/null | head -10 || true
echo "  smoke est start: $(squeue -j "$SMOKE" -h --start -o '%S' 2>/dev/null)"
echo "ARRAY_HALF_1=$A1"
echo "ARRAY_HALF_2=$A2"
echo "SMOKE_JOB_ID=$SMOKE"
echo "STATUS=ARRAYS_QUEUED"

echo "=== G. DONE ==="

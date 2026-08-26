#!/bin/bash
# Move the family to hgpu8. Cancel the 3090 arrays, set their 51 runs aside so the
# family is uniform on one card, and resubmit all 1440 on the A800 nodes.
set -o pipefail
ROOT=/data1/home/sunyiq/zhenjiang_oyv_v1

echo "=== A. SYNC ==="
cd "$ROOT/repo" || exit 1
D=$(git status --porcelain | grep -v '^?? ' | head -3); [ -n "$D" ] && { echo "dirty"; echo "$D"; exit 1; }
timeout 180 git fetch -q origin "+refs/heads/main:refs/remotes/origin/main" || { echo FETCH_FAILED; exit 1; }
git reset -q --hard refs/remotes/origin/main
echo "  head: $(git log --oneline -1)"
FAIL=0
chk() { g=$(sha256sum "$1"|cut -d' ' -f1); [ "$g" = "$2" ] && echo "  ok  $1" || { echo "  MISMATCH $1"; echo "    want $2"; echo "    got  $g"; FAIL=1; }; }
chk scripts/analysis/zhenjiang_oyv_n4_contract.py 407ab9f0d67720628aba766914380c4c3cbab399af79f38d186b6ec039af9536
chk scripts/modeling/hpc/submit_zhenjiang_oyv_n4.slurm b9c880537755dc2e9ebb87195ffee14db5fa0b21eae2201e2b46f5b9efe3330f
chk docs/records/ZHENJIANG_OYV_N4_LADDER_V3_PREREGISTRATION.json 3771dfd0e2b6f9acca1288eab53b0b04062203fdfa60fd8e1b739470d14cfbed
[ "$FAIL" -eq 0 ] || { echo IDENTITY_FAILED; exit 1; }
grep -E '^#SBATCH -(p|t) ' scripts/modeling/hpc/submit_zhenjiang_oyv_n4.slurm

echo "=== B. CONTRACT SELF-CHECK UNDER THE A800 PIN ==="
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh 2>/dev/null || source $HOME/miniconda3/etc/profile.d/conda.sh
conda activate nh_final || { echo CONDA_FAILED; exit 1; }
export PYTHONPATH="$ROOT/pysite:${PYTHONPATH:-}"
python -u scripts/analysis/zhenjiang_oyv_n4_contract.py 2>&1 | tail -6

echo "=== C. CANCEL THE 3090 ARRAYS (both mine) ==="
for j in 212932 212933; do
  echo "  $j states: $(sacct -j "$j" -X -n -o State 2>/dev/null | sort -u | tr '\n' ' ')"
  scancel "$j" 2>&1 || true
done
sleep 10
echo "  still mine in queue:"
squeue -u "$USER" -h -o "%.20i %.12j %.9T" 2>/dev/null | grep zj_oyv_n4 || echo "    none"

echo "=== D. SET THE 3090 RUNS ASIDE ==="
N=$(ls -1 "$ROOT/n4_tasks" 2>/dev/null | wc -l)
echo "  n4_tasks held $N runs, all RTX 3090; the family must be uniform"
mv "$ROOT/n4_tasks" "$ROOT/n4_tasks_discarded_3090_$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
[ -e "$ROOT/n4_tasks" ] && { echo "  could not move it aside"; exit 1; } || echo "  moved aside, not deleted"

echo "=== E. SUBMIT BOTH HALVES ON hgpu8 ==="
o1=$(sbatch --export=ALL,N4_INDEX_OFFSET=0 scripts/modeling/hpc/submit_zhenjiang_oyv_n4.slurm 2>&1); echo "$o1"
A1=$(echo "$o1" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+' || true)
[ -n "$A1" ] || { echo SUBMIT_FAILED_1; exit 1; }
o2=$(sbatch --export=ALL,N4_INDEX_OFFSET=720 scripts/modeling/hpc/submit_zhenjiang_oyv_n4.slurm 2>&1); echo "$o2"
A2=$(echo "$o2" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+' || true)
[ -n "$A2" ] || { echo "SUBMIT_FAILED_2, cancelling $A1"; scancel "$A1" 2>&1 || true; exit 1; }
echo "  half one = $A1   half two = $A2"

echo "=== F. STATE ==="
sleep 45
sacct -j "$A1" -X -n -P -o State 2>/dev/null | sort | uniq -c | sed "s/^/    $A1 /"
sacct -j "$A2" -X -n -P -o State 2>/dev/null | sort | uniq -c | sed "s/^/    $A2 /"
echo "  running now: $(squeue -u "$USER" -h -t RUNNING -o '%i' 2>/dev/null | wc -l)"
echo "  n4_tasks   : $(ls -1 "$ROOT/n4_tasks" 2>/dev/null | wc -l) / 1440"
echo "N4_HALF_1=$A1"
echo "N4_HALF_2=$A2"
echo "STATUS=RUNNING_ON_A800"
echo "=== DONE ==="

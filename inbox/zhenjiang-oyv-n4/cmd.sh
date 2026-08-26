#!/bin/bash
# Replace the hgpu2p-only submission with one that may also land on hgpu2.
set -o pipefail
ROOT=/data1/home/sunyiq/zhenjiang_oyv_v1

echo "=== A. SYNC ==="
cd "$ROOT/repo" || exit 1
D=$(git status --porcelain | grep -v '^?? ' | head -3)
[ -n "$D" ] && { echo "tracked dirty:"; echo "$D"; exit 1; }
timeout 180 git fetch -q origin "+refs/heads/main:refs/remotes/origin/main" || { echo FETCH_FAILED; exit 1; }
git reset -q --hard refs/remotes/origin/main
echo "  head: $(git log --oneline -1)"
FAIL=0
chk() { g=$(sha256sum "$1" | cut -d' ' -f1); if [ "$g" = "$2" ]; then echo "  ok  $1"; else echo "  MISMATCH $1"; echo "    want $2"; echo "    got  $g"; FAIL=1; fi; }
chk scripts/analysis/zhenjiang_oyv_n4_contract.py 05f708683bd480ea51fc5c89b9af84964e11bae65cb3847747b0dff50445e766
chk scripts/modeling/hpc/submit_zhenjiang_oyv_n4.slurm fece098729a70e2bced9f58c930a47bc78822499b54ffa0ffe5640b77fe377a1
chk docs/records/ZHENJIANG_OYV_N4_LADDER_V2_PREREGISTRATION.json e3218ab0900901df7f60704084a3b66c2eb45f20f808ca911fbce1457568cb54
[ "$FAIL" -eq 0 ] || { echo IDENTITY_FAILED; exit 1; }
grep -E '^#SBATCH -p' scripts/modeling/hpc/submit_zhenjiang_oyv_n4.slurm

echo "=== B. CONTRACT SELF-CHECK UNDER THE NARROWED SET ==="
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh 2>/dev/null || source $HOME/miniconda3/etc/profile.d/conda.sh
conda activate nh_final || { echo CONDA_FAILED; exit 1; }
export PYTHONPATH="$ROOT/pysite:${PYTHONPATH:-}"
python -u scripts/analysis/zhenjiang_oyv_n4_contract.py 2>&1 | tail -12

echo "=== C. CANCEL THE OLD, hgpu2p-ONLY SUBMISSIONS (all mine) ==="
for j in 212898 212901 212902; do
  st=$(sacct -j "$j" -X -n -o State 2>/dev/null | head -1 | awk '{print $1}')
  echo "  $j was $st"
  scancel "$j" 2>&1 || true
done
sleep 8
echo "  after cancel, my queue:"
squeue -u "$USER" -h -o "%.20i %.12j %.9T" 2>/dev/null | head -12 || true

echo "=== D. GUARD ==="
if [ -e "$ROOT/n4_tasks" ]; then echo "  n4_tasks exists -> stop"; exit 1; fi
echo "  n4_tasks absent -> ok"
rm -rf "$ROOT/n4_smoke"

echo "=== E. RESUBMIT BOTH HALVES ON hgpu2p,hgpu2 ==="
o1=$(sbatch --export=ALL,N4_INDEX_OFFSET=0 scripts/modeling/hpc/submit_zhenjiang_oyv_n4.slurm 2>&1); echo "$o1"
A1=$(echo "$o1" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+' || true)
[ -n "$A1" ] || { echo SUBMIT_FAILED_1; exit 1; }
o2=$(sbatch --export=ALL,N4_INDEX_OFFSET=720 scripts/modeling/hpc/submit_zhenjiang_oyv_n4.slurm 2>&1); echo "$o2"
A2=$(echo "$o2" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+' || true)
[ -n "$A2" ] || { echo "SUBMIT_FAILED_2, cancelling $A1"; scancel "$A1" 2>&1 || true; exit 1; }
echo "  half one = $A1   half two = $A2"

echo "=== F. QUEUE AND ESTIMATE ==="
sleep 25
squeue -u "$USER" -h -o "%.20i %.12j %.14P %.9T %.11r" 2>/dev/null | head -12 || true
echo "  half one est start: $(squeue -j "$A1" -h --start -o '%S' 2>/dev/null | head -1)"
echo "  running now: $(squeue -u "$USER" -h -t RUNNING -o '%i' 2>/dev/null | wc -l)"
echo "ARRAY_HALF_1=$A1"
echo "ARRAY_HALF_2=$A2"
echo "STATUS=RESUBMITTED_TWO_PARTITIONS"

echo "=== G. TIDY MY OWN SCRATCH ==="
rm -rf "$ROOT"/equiv_scratch_* 2>/dev/null
echo "  equivalence scratch cleared"
echo "=== DONE ==="

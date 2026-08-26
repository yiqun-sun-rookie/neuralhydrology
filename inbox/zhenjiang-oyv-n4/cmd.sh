#!/bin/bash
# Four-target ladder: sync, verify identity, then smoke test one task.
# The smoke test is only submitted if every check above it passes.
set -o pipefail

ROOT=/data1/home/sunyiq/zhenjiang_oyv_v1
MAILBOX=/data1/home/sunyiq/hpc_mailbox

echo "=== A. HOST ==="
hostname; date -u +%Y-%m-%dT%H:%M:%SZ

echo "=== B. REPO WORKING TREE ==="
cd "$ROOT/repo" || exit 1
UNTRACKED=$(git status --porcelain | grep '^?? ' | head -10)
TRACKED_DIRTY=$(git status --porcelain | grep -v '^?? ' | head -10)
echo "  untracked (tolerated; git reset --hard never touches these):"
if [ -n "$UNTRACKED" ]; then echo "$UNTRACKED" | sed 's/^/    /'; else echo "    none"; fi
if [ -n "$TRACKED_DIRTY" ]; then
  echo "  TRACKED FILES MODIFIED - refusing to reset:"
  echo "$TRACKED_DIRTY" | sed 's/^/    /'
  exit 1
fi
echo "  no tracked modifications -> safe to sync"

echo "=== C. SYNC ==="
echo "before: $(git log --oneline -1)"
timeout 180 git fetch -q origin "+refs/heads/main:refs/remotes/origin/main" || { echo "FETCH_FAILED"; exit 1; }
git reset -q --hard refs/remotes/origin/main
echo "after : $(git log --oneline -1)"

echo "=== D. IDENTITY OF THE NEW FILES ==="
FAIL=0
check() {
  if [ ! -f "$1" ]; then echo "  MISSING  $1"; FAIL=1; return; fi
  got=$(sha256sum "$1" | cut -d' ' -f1)
  if [ "$got" = "$2" ]; then echo "  ok       $1"; else echo "  MISMATCH $1"; echo "    expected $2"; echo "    observed $got"; FAIL=1; fi
}
check scripts/analysis/zhenjiang_oyv_n4_contract.py b153de57c487c309d2a22b103582031b1b46ebca3560a36c1e96c595139f5526
check scripts/analysis/zhenjiang_oyv_n4_impact.py   57a7bf00f26a04a9a90f18d97c76e9e5fa647fcacdd148a614b05893c1a353e9
check scripts/modeling/zhenjiang_oyv_n4_training.py b6b69a4e55bed730043a79be38c8c53f462607a215934d5788de6c7d451ea15b
check docs/records/ZHENJIANG_OYV_N4_LADDER_V1_PREREGISTRATION.json 1212cdd9701c99f3b60532f2fcce5d4cceb214d1e6b92b55e5adf01b43d0c204
[ "$FAIL" -eq 0 ] || { echo "IDENTITY_FAILED"; exit 1; }

echo "=== E. OUTPUT ROOTS MUST NOT EXIST ==="
for d in "$ROOT/n4_tasks" "$ROOT/n4_smoke"; do
  if [ -e "$d" ]; then echo "  PRESENT $d -> stop condition"; FAIL=1; else echo "  absent  $d"; fi
done
[ "$FAIL" -eq 0 ] || { echo "OUTPUT_ROOT_EXISTS"; exit 1; }

echo "=== F. CERTIFIED INPUT ==="
IN=data/processed/water_level_model_input_v7_beijing_realtime_verified
for s in datong nanjing zhenjiang jiangyin xuliujing wusongkou; do
  if [ -f "$IN/realtime_features/${s}_realtime_features.csv" ] && [ -f "$IN/retrospective_targets/${s}_retrospective_targets.csv" ]; then
    echo "  ok   $s"
  else echo "  MISSING $s"; FAIL=1; fi
done
[ "$FAIL" -eq 0 ] || { echo "INPUT_MISSING"; exit 1; }

echo "=== G. ENVIRONMENT AND CONTRACT ==="
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh 2>/dev/null || \
source $HOME/miniconda3/etc/profile.d/conda.sh
conda activate nh_final || { echo "CONDA_FAILED"; exit 1; }
export PYTHONPATH="$ROOT/pysite:${PYTHONPATH:-}"
python -c "import sys,torch,numpy,pandas,sklearn;print('  py',sys.version.split()[0],'torch',torch.__version__,'numpy',numpy.__version__,'pandas',pandas.__version__,'sklearn',sklearn.__version__)" || exit 1
python -u scripts/analysis/zhenjiang_oyv_n4_contract.py 2>&1 | tail -14
python - <<'PYEOF' 2>&1 | tail -8
import sys
sys.path.insert(0, "scripts/analysis"); sys.path.insert(0, "scripts/modeling")
import zhenjiang_oyv_n4_contract as c
t = c.enumerate_tasks()
print("  task_count", len(t))
print("  index 0   ", t[0]["task_id"])
print("  index 1439", t[-1]["task_id"])
PYEOF

echo "=== H. SMOKE TEST SUBMIT ==="
cd "$MAILBOX" || exit 1
sed -i 's/\r$//' inbox/zhenjiang-oyv-n4/n4_smoke.slurm
out=$(sbatch inbox/zhenjiang-oyv-n4/n4_smoke.slurm 2>&1); echo "$out"
JID=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+' || true)
[ -n "$JID" ] || { echo "SUBMIT_FAILED"; exit 1; }
echo "  jobid=$JID"

echo "=== I. WAIT (max 12 min) ==="
for i in $(seq 1 72); do
  STATE=$(sacct -j "$JID" -X -n -o State 2>/dev/null | head -1 | tr -d ' ')
  case "$STATE" in RUNNING|PENDING|"") sleep 10;; *) echo "  settled at t=${i}0s state=$STATE"; break;; esac
done

echo "=== J. RESULT ==="
sacct -j "$JID" -X --format=JobID%12,JobName%12,NodeList%9,State%12,ExitCode%8,Elapsed%10 2>&1 || true
echo "--- log tail ---"
tail -30 "$ROOT/logs/n4_smoke_${JID}.out" 2>/dev/null || echo "  (no stdout log)"
echo "--- err tail ---"
tail -15 "$ROOT/logs/n4_smoke_${JID}.err" 2>/dev/null || echo "  (no stderr log)"
echo "--- artefacts ---"
ls -1 "$ROOT/n4_smoke/"*/ 2>/dev/null | head -10 || echo "  (none)"

echo "=== K. DONE ==="

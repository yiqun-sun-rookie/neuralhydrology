#!/bin/bash
# Four-target ladder (Nanjing, Xuliujing): pre-flight only. No job is submitted.
set -o pipefail

ROOT=/data1/home/sunyiq/zhenjiang_oyv_v1

echo "=== A. HOST ==="
hostname
date -u +%Y-%m-%dT%H:%M:%SZ

echo "=== B. LANDING ZONE ==="
for d in "$ROOT" "$ROOT/repo" "$ROOT/pysite" "$ROOT/logs"; do
  [ -d "$d" ] && echo "  ok   $d" || echo "  MISSING $d"
done
if [ -e "$ROOT/n4_tasks" ]; then echo "  n4_tasks PRESENT -> stop condition"; else echo "  n4_tasks absent -> ok"; fi

echo "=== C. REPO WORKING TREE ==="
cd "$ROOT/repo" || exit 1
git rev-parse --abbrev-ref HEAD
echo "before: $(git log --oneline -1)"
DIRTY=$(git status --porcelain | head -5)
if [ -n "$DIRTY" ]; then
  echo "  WORKING TREE NOT CLEAN, refusing to reset:"
  echo "$DIRTY"
  exit 1
fi
echo "  working tree clean"

echo "=== D. SYNC ==="
timeout 180 git fetch -q origin "+refs/heads/main:refs/remotes/origin/main" || echo "  FETCH_FAILED"
git reset -q --hard refs/remotes/origin/main
echo "after : $(git log --oneline -1)"

echo "=== E. NEW FILE IDENTITY ==="
for f in scripts/analysis/zhenjiang_oyv_n4_contract.py \
         scripts/analysis/zhenjiang_oyv_n4_impact.py \
         scripts/modeling/zhenjiang_oyv_n4_training.py \
         scripts/modeling/hpc/submit_zhenjiang_oyv_n4.slurm \
         docs/records/ZHENJIANG_OYV_N4_LADDER_V1_PREREGISTRATION.json; do
  if [ -f "$f" ]; then sha256sum "$f"; else echo "MISSING $f"; fi
done

echo "=== F. CERTIFIED INPUT PRESENT ==="
IN=data/processed/water_level_model_input_v7_beijing_realtime_verified
for s in datong nanjing zhenjiang jiangyin xuliujing wusongkou; do
  a="$IN/realtime_features/${s}_realtime_features.csv"
  b="$IN/retrospective_targets/${s}_retrospective_targets.csv"
  [ -f "$a" ] && [ -f "$b" ] && echo "  ok   $s" || echo "  MISSING $s"
done

echo "=== G. ENVIRONMENT ==="
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh 2>/dev/null || \
source $HOME/miniconda3/etc/profile.d/conda.sh
conda activate nh_final || { echo "CONDA_FAILED"; exit 1; }
export PYTHONPATH="$ROOT/pysite:${PYTHONPATH:-}"
python -c "import sys,torch,numpy,pandas,sklearn;print('py',sys.version.split()[0],'torch',torch.__version__,'numpy',numpy.__version__,'pandas',pandas.__version__,'sklearn',sklearn.__version__)"

echo "=== H. CONTRACT SELF-CHECK ==="
python -u scripts/analysis/zhenjiang_oyv_n4_contract.py 2>&1 | tail -20

echo "=== I. TASK ENUMERATION SPOT CHECK ==="
python - <<'PYEOF' 2>&1 | tail -12
import sys
sys.path.insert(0, "scripts/analysis"); sys.path.insert(0, "scripts/modeling")
import zhenjiang_oyv_n4_contract as c
t = c.enumerate_tasks()
print("task_count", len(t))
print("index    0:", t[0]["task_id"])
print("index 1439:", t[-1]["task_id"])
for tgt in c.TARGETS:
    print(tgt, "->", c.CONTROL_TYPE[tgt], "| rungs", len(c.conditions(tgt)))
PYEOF

echo "=== J. QUEUE AND PARTITION (read only) ==="
squeue -u "$USER" -h -o "%.12i %.14j %.9T" 2>&1 | head -15 || true
echo "  my running/pending count: $(squeue -u "$USER" -h -o '%i' 2>/dev/null | wc -l)"
sinfo -p hgpu2p -o "%.10P %.6a %.24N %.10T" 2>&1 | head -8 || true

echo "=== K. DONE ==="

#!/bin/bash
# =============================================================================
# Deploy & Submit: sync project to HPC and submit MTSMamba Phase 2v2
#
# 使用方法（在 WSL 终端中运行，需先 ssh hpc 建立 ControlMaster 连接）:
#   cd /mnt/g/github/pycharm/projects/neuralhydrology
#   bash src/mts_mamba_global_transfer/hpc/deploy_and_submit.sh
#
# 如果不需要自动提交，加 --no-submit:
#   bash src/mts_mamba_global_transfer/hpc/deploy_and_submit.sh --no-submit
# =============================================================================
set -euo pipefail

HPC="hpc"
R="~/neuralhydrology"
LOCAL_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "${LOCAL_ROOT}"
AUTO_SUBMIT=true
[[ "${1:-}" == "--no-submit" ]] && AUTO_SUBMIT=false

IDEA_NAME="41_mts_mamba_global_transfer"
TASK_ROOT="src/mts_mamba_global_transfer"

echo "==========================================="
echo " MTSMamba Phase 2v2 — Deploy to HPC"
echo "==========================================="
echo "[INFO] Local root: ${LOCAL_ROOT}"
echo "[INFO] Remote:     ${HPC}:${R}"
echo ""

# =============================================================================
# Step 0: Verify remote project exists
# =============================================================================
echo "=== [0/4] Checking remote project ==="
ssh -T $HPC "[ -d $R ] && echo '[OK] Remote project exists: $R' || { echo '[FAIL] $R not found'; exit 1; }"
ssh -T $HPC "[ -f $R/setup.py ] && echo '[OK] setup.py found (editable install likely)' || echo '[WARN] No setup.py — may need pip install -e . after sync'"

# =============================================================================
# Step 1: Create remote directories
# =============================================================================
echo ""
echo "=== [1/5] Creating remote directories ==="
ssh -T $HPC "mkdir -p $R/{logs/${IDEA_NAME},results/${IDEA_NAME}} \
  $R/${TASK_ROOT}/{configs,data,hpc,scripts}"

# =============================================================================
# Step 2: Sync neuralhydrology/ package (full rsync)
# =============================================================================
echo ""
echo "=== [2/5] Syncing neuralhydrology/ package ==="
echo "[INFO] Incremental sync — adds/updates files, keeps untouched files intact"
rsync -avz --progress \
  --exclude='__pycache__/' \
  --exclude='*.pyc' \
  --exclude='*.egg-info/' \
  neuralhydrology/ $HPC:$R/neuralhydrology/

# =============================================================================
# Step 3: Sync task-specific files
# =============================================================================
echo ""
echo "=== [3/5] Syncing task files: ${TASK_ROOT}/ ==="
rsync -avz --progress \
  --exclude='__pycache__/' \
  --exclude='*.pyc' \
  ${TASK_ROOT}/ $HPC:$R/${TASK_ROOT}/

# Also sync setup.py/setup.cfg for editable install if needed
for f in setup.py setup.cfg pyproject.toml; do
  [ -f "$f" ] && scp "$f" $HPC:$R/
done

# =============================================================================
# Step 4: Clean stale bytecode cache on HPC
# =============================================================================
echo ""
echo "=== [4/5] Cleaning __pycache__ on HPC ==="
ssh -T $HPC "find $R/neuralhydrology -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null; echo '[OK] Cache cleaned'"

# =============================================================================
# Step 5: Pre-flight dependency check
# =============================================================================
echo ""
echo "=== [5/5] Running dependency check on HPC ==="
ssh -T $HPC "cd $R && bash ${TASK_ROOT}/hpc/check_mamba_deps.sh"

DEP_EXIT=$?
echo ""
if [ $DEP_EXIT -ne 0 ]; then
  echo "=== [FAIL] Dependency check failed. Fix issues above before submitting. ==="
  exit 1
fi

# =============================================================================
# Submit or print instructions
# =============================================================================
echo ""
if $AUTO_SUBMIT; then
  echo "=== Submitting job ==="
  ssh -T $HPC "cd $R && sbatch ${TASK_ROOT}/hpc/submit_phase2v2_mtsmamba.slurm"
  echo ""
  echo "=== Job submitted! Monitor with: ==="
  echo "  ssh hpc 'squeue -u \$USER'"
  echo "  ssh hpc 'tail -f $R/logs/${IDEA_NAME}/phase2v2-mtsmamba-*.out'"
else
  echo "=== All synced. To submit manually: ==="
  echo "  ssh hpc 'cd $R && sbatch ${TASK_ROOT}/hpc/submit_phase2v2_mtsmamba.slurm'"
fi

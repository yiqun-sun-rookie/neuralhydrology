#!/bin/bash
# Run the aggregation-level platform control on the idle A800 cards: one complete
# arm pair, 160 runs, then the cost comparison.
set -o pipefail
ROOT=/data1/home/sunyiq/zhenjiang_oyv_v1

echo "=== A. SYNC ==="
cd "$ROOT/repo" || exit 1
D=$(git status --porcelain | grep -v '^?? ' | head -3); [ -n "$D" ] && { echo "dirty"; echo "$D"; exit 1; }
timeout 180 git fetch -q origin "+refs/heads/main:refs/remotes/origin/main" || { echo FETCH_FAILED; exit 1; }
git reset -q --hard refs/remotes/origin/main
echo "  head: $(git log --oneline -1)"
G=$(sha256sum scripts/analysis/platform_control_ladder_v1.py | cut -d' ' -f1)
[ "$G" = "131bac0c89c94dd6cf5ed8b4342e7fddeb602add18ac71c58c437c3cc3439fb8" ] && echo "  ok" || { echo "MISMATCH $G"; exit 1; }

echo "=== B. LAUNCHER ==="
mkdir -p "$ROOT/probe"
cat > "$ROOT/probe/pfctl.slurm" <<'SLURMEOF'
#!/usr/bin/env bash
#SBATCH -J zj_pfctl
#SBATCH -p hgpu8
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH --array=0-159%16
#SBATCH -t 00:40:00
#SBATCH -o /data1/home/sunyiq/zhenjiang_oyv_v1/probe/pfctl_%A_%a.out
#SBATCH -e /data1/home/sunyiq/zhenjiang_oyv_v1/probe/pfctl_%A_%a.err
set -eo pipefail
ROOT=/data1/home/sunyiq/zhenjiang_oyv_v1
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh || source $HOME/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1
export PYTHONPATH="${ROOT}/pysite:${PYTHONPATH:-}"
echo "[INFO] node=$(hostname) index=${SLURM_ARRAY_TASK_ID}"
nvidia-smi --query-gpu=name --format=csv,noheader --id=0
cd "${ROOT}/repo"
python -u scripts/analysis/platform_control_ladder_v1.py \
  --mode train --task-index "${SLURM_ARRAY_TASK_ID}" \
  --scratch-root "${ROOT}/platform_control_a800" --device cuda:0
SLURMEOF
sed -i 's/\r$//' "$ROOT/probe/pfctl.slurm"

echo "=== C. SUBMIT ==="
out=$(sbatch "$ROOT/probe/pfctl.slurm" 2>&1); echo "$out"
AID=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+' || true)
[ -n "$AID" ] || { echo SUBMIT_FAILED; exit 1; }
echo "PLATFORM_CONTROL_ARRAY=$AID"

echo "=== D. STATE ==="
sleep 40
sacct -j "$AID" -X -n -P -o State 2>/dev/null | sort | uniq -c | sed 's/^/    /'
echo "  scratch dirs: $(ls -1 "$ROOT/platform_control_a800" 2>/dev/null | wc -l) / 160"
echo "  n4_tasks    : $(ls -1 "$ROOT/n4_tasks" 2>/dev/null | wc -l) / 1440"
echo "=== DONE ==="

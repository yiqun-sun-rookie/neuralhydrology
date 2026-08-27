#!/bin/bash
# Bitwise replay of all 1440 checkpoints, sharded sixteen ways across the A800s.
set -o pipefail
ROOT=/data1/home/sunyiq/zhenjiang_oyv_v1

echo "=== A. SYNC ==="
cd "$ROOT/repo" || exit 1
D=$(git status --porcelain | grep -v '^?? ' | head -3); [ -n "$D" ] && { echo dirty; echo "$D"; exit 1; }
timeout 180 git fetch -q origin "+refs/heads/main:refs/remotes/origin/main" || { echo FETCH_FAILED; exit 1; }
git reset -q --hard refs/remotes/origin/main
echo "  head: $(git log --oneline -1)"
G=$(sha256sum scripts/analysis/independent_audit_zhenjiang_oyv_n4.py | cut -d' ' -f1)
[ "$G" = "bf172503348debbac4e42ff6db36455eaed9352233bb24b3425922d2853f50d3" ] && echo "  audit identity ok" || { echo "MISMATCH $G"; exit 1; }

echo "=== B. LAUNCHER ==="
mkdir -p "$ROOT/probe"
cat > "$ROOT/probe/replay.slurm" <<'SLURMEOF'
#!/usr/bin/env bash
#SBATCH -J zj_n4_replay
#SBATCH -p hgpu8
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH --array=0-15
#SBATCH -t 00:50:00
#SBATCH -o /data1/home/sunyiq/zhenjiang_oyv_v1/probe/replay_%A_%a.out
#SBATCH -e /data1/home/sunyiq/zhenjiang_oyv_v1/probe/replay_%A_%a.err
set -eo pipefail
ROOT=/data1/home/sunyiq/zhenjiang_oyv_v1
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh || source $HOME/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1
export PYTHONPATH="${ROOT}/pysite:${PYTHONPATH:-}"
echo "[INFO] node=$(hostname) shard=${SLURM_ARRAY_TASK_ID}/16"
cd "${ROOT}/repo"
python -u scripts/analysis/independent_audit_zhenjiang_oyv_n4.py \
  --task-root "${ROOT}/n4_tasks" \
  --output-root "${ROOT}/n4_audit_replay_${SLURM_ARRAY_TASK_ID}" \
  --replay --replay-slice "${SLURM_ARRAY_TASK_ID}/16" \
  --device cuda:0
SLURMEOF
sed -i 's/\r$//' "$ROOT/probe/replay.slurm"
rm -rf "$ROOT"/n4_audit_replay_* 2>/dev/null

echo "=== C. SUBMIT ==="
out=$(sbatch "$ROOT/probe/replay.slurm" 2>&1); echo "$out"
AID=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+' || true)
[ -n "$AID" ] || { echo SUBMIT_FAILED; exit 1; }
echo "REPLAY_ARRAY=$AID"
sleep 30
sacct -j "$AID" -X -n -P -o State 2>/dev/null | sort | uniq -c | sed 's/^/    /'
echo "=== DONE ==="

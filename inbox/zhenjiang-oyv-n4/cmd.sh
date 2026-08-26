#!/bin/bash
# Run the node-family equivalence test on hgpu2 (RTX 3090, CentOS 7, driver 535).
set -o pipefail
ROOT=/data1/home/sunyiq/zhenjiang_oyv_v1

echo "=== A. SYNC ==="
cd "$ROOT/repo" || exit 1
D=$(git status --porcelain | grep -v '^?? ' | head -3)
[ -n "$D" ] && { echo "tracked dirty:"; echo "$D"; exit 1; }
timeout 180 git fetch -q origin "+refs/heads/main:refs/remotes/origin/main" || { echo FETCH_FAILED; exit 1; }
git reset -q --hard refs/remotes/origin/main
echo "  head: $(git log --oneline -1)"
G=$(sha256sum scripts/analysis/verify_node_family_equivalence_v1.py | cut -d' ' -f1)
[ "$G" = "d253ef3256f8e89c57d2237e8c8394a769ee4cf9cbb3784f17588682b1e287e0" ] && echo "  verifier identity ok" || { echo "  verifier MISMATCH $G"; exit 1; }

echo "=== B. PICK A FINISHED LADDER TASK ==="
REF="$ROOT/ladder_tasks"
TASK=zhenjiang_ladder_v2__fold_2017__zhenjiang__complete_observation__seed_17
if [ -f "$REF/$TASK/best_state.pt" ]; then
  echo "  reference exists: $TASK"
  echo "  reference sha256: $(sha256sum "$REF/$TASK/best_state.pt" | cut -d' ' -f1)"
else
  echo "  reference MISSING at $REF/$TASK"; ls -1 "$REF" 2>/dev/null | head -3; exit 1
fi

echo "=== C. WRITE THE EQUIVALENCE LAUNCHER ==="
mkdir -p "$ROOT/probe"
cat > "$ROOT/probe/equiv.slurm" <<'SLURMEOF'
#!/usr/bin/env bash
#SBATCH -J zj_equiv
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH -t 00:25:00
#SBATCH -o /data1/home/sunyiq/zhenjiang_oyv_v1/probe/equiv_%j.out
#SBATCH -e /data1/home/sunyiq/zhenjiang_oyv_v1/probe/equiv_%j.err
set -eo pipefail
ROOT=/data1/home/sunyiq/zhenjiang_oyv_v1
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh || source $HOME/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1
export PYTHONPATH="${ROOT}/pysite:${PYTHONPATH:-}"
echo "NODE=$(hostname)"
nvidia-smi --query-gpu=name,driver_version --format=csv,noheader
cd "${ROOT}/repo"
python -u scripts/analysis/verify_node_family_equivalence_v1.py \
  --test-year 2017 --target zhenjiang --condition complete_observation --seed 17 \
  --reference-root "${ROOT}/ladder_tasks" \
  --scratch-root "${ROOT}/equiv_scratch_$(hostname)_${SLURM_JOB_ID}" \
  --device cuda:0
SLURMEOF
sed -i 's/\r$//' "$ROOT/probe/equiv.slurm"
echo "  written"

echo "=== D. SUBMIT TO hgpu2 NODES ==="
IDS=""
for n in ngu009 ngu003; do
  out=$(sbatch --parsable -p hgpu2 --nodelist="$n" --job-name="eq_$n" -t 00:25:00 "$ROOT/probe/equiv.slurm" 2>&1)
  jid=$(echo "$out" | grep -oE '^[0-9]+' || true)
  if [ -n "$jid" ]; then echo "  $n -> $jid"; IDS="$IDS $jid"; else echo "  $n -> FAILED: $out"; fi
done
[ -n "$IDS" ] || { echo NONE_SUBMITTED; exit 1; }
echo "EQUIV_JOB_IDS=$IDS"
echo "  (not waiting here; a long wait loop gets killed by runner restarts)"

echo "=== E. IMMEDIATE STATE ==="
sleep 15
for j in $IDS; do sacct -j "$j" -X --format=JobID%9,JobName%9,NodeList%8,State%11 2>&1 | tail -1; done
echo "=== DONE ==="

#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/v09_strict
FORMAL=$ROOT/codetest/neuralhydrology/results/26_historical_band_experts/formal_v09

echo "=== A PREDICT CODE AREA ==="
mkdir -p $ROOT/predict_v09
cd $ROOT/predict_v09 || exit 1
if [ -d neuralhydrology/.git ]; then
  cd neuralhydrology || exit 1
  git fetch origin "+codex/historical-band-experts-pilot:refs/remotes/origin/codex/historical-band-experts-pilot" -q
  git reset -q --hard refs/remotes/origin/codex/historical-band-experts-pilot
  echo "mode=updated_existing"
else
  git clone -q --depth 1 --branch codex/historical-band-experts-pilot --single-branch \
    git@github.com:yiqun-sun-rookie/neuralhydrology.git neuralhydrology
  cd neuralhydrology || exit 1
  echo "mode=fresh_clone"
fi
echo "head=$(git rev-parse HEAD)"
echo "clean=[$(git status --porcelain --untracked-files=all)]"

echo "=== B LINE ENDINGS ==="
sed -i 's/\r$//' src/26_historical_band_experts/hpc/predict_formal_v09.slurm
echo "predictor_bytes=$(wc -c < src/26_historical_band_experts/predict_formal_v09.py)"
echo "slurm_bytes=$(wc -c < src/26_historical_band_experts/hpc/predict_formal_v09.slurm)"

echo "=== C PRECONDITIONS ==="
for p in predictions predictions.building; do
  if [ -e "$FORMAL/$p" ]; then echo "$p=PRESENT_BLOCKER"; else echo "$p=absent_ok"; fi
done
for f in training_external_audit.json state_diagnostics_external_audit.json; do
  if [ -f "$FORMAL/$f" ]; then echo "$f=present"; else echo "$f=MISSING_BLOCKER"; fi
done
for d in state_diagnostics input_attempt_01; do
  if [ -d "$FORMAL/$d" ]; then echo "$d=present"; else echo "$d=MISSING_BLOCKER"; fi
done
echo "final_checkpoints=$(ls $FORMAL/*/seed_*/checkpoint_epoch030.pt 2>/dev/null | wc -l)"

echo "=== D FROZEN AREAS UNTOUCHED ==="
cd $ROOT/codetest/neuralhydrology && echo "codetest_head=$(git rev-parse HEAD)"
cd $ROOT/audit_v09/neuralhydrology && echo "audit_head=$(git rev-parse HEAD)"

echo "=== E RESOURCES ==="
df -h /data1 | tail -1
sinfo -o "%.10P %.6a %.6D %.6t %.28N" -p hgpu2p
echo "=== END ==="

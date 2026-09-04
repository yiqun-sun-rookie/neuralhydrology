#!/usr/bin/env bash
# ID33 seq=1 : isolated root, deploy, verify. No training, no sbatch.
set -o pipefail
ID30=/data1/home/sunyiq/id30_modern_transformer_moe_20260827/repo
ID32=/data1/home/sunyiq/id32_transformer_inductive_bias_20260902/repo
ID33=/data1/home/sunyiq/id33_transformer_recipe_repair_20260904/repo
PKG=~/hpc_mailbox/payload/id33-transformer-recipe-repair/id33_deploy_v01.tar.gz
EXPECT=8d64699deab8a91e4f3373419d5f006affe33bfa7a69c69b96913b3c1791a5c4

echo "=== A. PRECONDITIONS ==="; date -Is
df -h /data1 2>&1 | tail -1
test "$(sha256sum "$PKG" 2>/dev/null | cut -d' ' -f1)" = "$EXPECT" && echo PAYLOAD_HASH_OK || { echo PAYLOAD_HASH_MISMATCH; exit 1; }
if test -e "$ID33"; then echo "ID33_ROOT_ALREADY_EXISTS"; exit 1; fi

echo "=== B. CREATE ISOLATED ROOT FROM THE ID32 SKELETON ==="
mkdir -p "$ID33"
tar -C "$ID32" -cf - --exclude='results' --exclude='logs' --exclude='.git' --exclude='__pycache__'   --exclude='*.pt' --exclude='*.p' --exclude='data' . 2>/dev/null | tar -C "$ID33" -xf - 2>&1
mkdir -p "$ID33/data"
for n in camels_us_track0_development_forcing_v01 camels_us_track0_supervision_v01; do
  ln -s "$ID30/data/$n" "$ID33/data/$n" && echo "  linked $n"
done

echo "=== C. OVERLAY PAYLOAD ==="
tar -C "$ID33" -xzf "$PKG" && echo extracted
mkdir -p "$ID33/results/33_transformer_recipe_repair/_reports" "$ID33/logs/33_transformer_recipe_repair"
rm -rf "$ID33/src/transformer_inductive_bias" 2>/dev/null
ls -1 "$ID33/src"

echo "=== D. HASHES ==="
cd "$ID33"
for f in neuralhydrology/modelzoo/recipe_fixed_transformer.py          src/transformer_recipe_repair/scripts/audit_configs.py          src/transformer_recipe_repair/registry/experiments.csv; do sha256sum "$f" 2>&1; done
sed -i 's/\r$//' src/transformer_recipe_repair/hpc/submit_repair_arm.slurm

echo "=== E. AUDIT + PLAN UNDER nh_final ==="
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh; conda activate nh_final
export MKL_THREADING_LAYER=GNU
python -m src.transformer_recipe_repair.scripts.audit_configs 2>&1 || true
python -m src.transformer_recipe_repair.scripts.run_development T2 --run-id deploy_check 2>&1 | head -6 || true

echo "=== F. UNTOUCHED CHECK ==="
sha256sum "$ID30/results/30_modern_transformer_moe/D01/modern_transformer_moe_D01_dense_d128_l4_s100_2026_0827_1955_ep30/validation/model_epoch030/validation_metrics.csv" 2>&1 | cut -c1-64
test -d "$ID32" && echo "ID32 root intact" || echo "ID32 MISSING"
echo ID33_DEPLOY_SEQ1_COMPLETE

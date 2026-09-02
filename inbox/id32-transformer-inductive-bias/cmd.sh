#!/usr/bin/env bash
# ID32 seq=1 : create an isolated root, deploy the payload, verify. No training, no sbatch.
set -o pipefail
ID30=/data1/home/sunyiq/id30_modern_transformer_moe_20260827/repo
ID31=/data1/home/sunyiq/id31_hydrologic_dynamic_tokens_20260828/repo
ID32=/data1/home/sunyiq/id32_transformer_inductive_bias_20260902/repo
PKG=~/hpc_mailbox/payload/id32-transformer-inductive-bias/id32_deploy_v01.tar.gz
EXPECT=f864492c2d162855fab1cdd8820d0ae78ef820e82bd12e79bed855d0c0157a9d

echo "=== A. PRECONDITIONS ==="
date -Is
df -h /data1 2>&1 | tail -1
echo "payload:"; sha256sum "$PKG" 2>&1 || true
test "$(sha256sum "$PKG" 2>/dev/null | cut -d' ' -f1)" = "$EXPECT" \
  && echo "PAYLOAD_HASH_OK" || { echo "PAYLOAD_HASH_MISMATCH"; exit 1; }
if test -e "$ID32"; then echo "ID32_ROOT_ALREADY_EXISTS $ID32"; exit 1; fi

echo "=== B. HOW ID31 GETS ITS DATA (to copy the same arrangement) ==="
ls -la "$ID31/data" 2>&1 | head -6 || true
echo "-- is data a symlink? --"
readlink -f "$ID31/data" 2>&1 || true
readlink -f "$ID31/data/camels_us_track0_development_forcing_v01" 2>&1 || true

echo "=== C. CREATE THE ISOLATED ID32 ROOT ==="
mkdir -p "$ID32"
# Copy the ID31 deployment's code skeleton only. Results, logs, checkpoints and git state stay behind.
tar -C "$ID31" -cf - \
  --exclude='results' --exclude='logs' --exclude='.git' --exclude='__pycache__' \
  --exclude='*.pt' --exclude='*.p' --exclude='data' \
  . 2>/dev/null | tar -C "$ID32" -xf - 2>&1
echo "copied skeleton; top level:"
ls -1 "$ID32" | head -20

echo "=== D. LINK THE AUDITED DATA BUNDLE (read-only, shared with ID30) ==="
mkdir -p "$ID32/data"
for name in camels_us_track0_development_forcing_v01 camels_us_track0_supervision_v01; do
  if test -e "$ID30/data/$name"; then
    ln -s "$ID30/data/$name" "$ID32/data/$name" && echo "  linked $name"
  else
    echo "  MISSING_IN_ID30 $name"
  fi
done
ls -la "$ID32/data" 2>&1 | head -5

echo "=== E. OVERLAY THE ID32 PAYLOAD ==="
tar -C "$ID32" -xzf "$PKG" 2>&1 && echo "payload extracted"
mkdir -p "$ID32/results/32_transformer_inductive_bias/_reports" "$ID32/logs/32_transformer_inductive_bias"
# ID31 and ID30 experiment code is not needed here except the shared safe-data helper and baselines.
rm -rf "$ID32/src/hydrologic_dynamic_tokens" 2>/dev/null
ls -1 "$ID32/src" | head -20

echo "=== F. VERIFY DEPLOYED HASHES ==="
cd "$ID32"
for f in neuralhydrology/modelzoo/recency_biased_transformer.py \
         src/transformer_inductive_bias/scripts/audit_configs.py \
         src/transformer_inductive_bias/scripts/run_development.py \
         src/transformer_inductive_bias/registry/experiments.csv \
         src/transformer_inductive_bias/hpc/submit_ablation_arm.slurm; do
  sha256sum "$f" 2>&1 || echo "MISSING $f"
done
sed -i 's/\r$//' src/transformer_inductive_bias/hpc/submit_ablation_arm.slurm

echo "=== G. AUDIT AND TESTS UNDER nh_final ==="
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
export MKL_THREADING_LAYER=GNU
python -m src.transformer_inductive_bias.scripts.audit_configs 2>&1 || true
python -m pytest test/test_recency_biased_transformer.py -q 2>&1 | tail -6 || true
echo "-- plan mode, read only --"
python -m src.transformer_inductive_bias.scripts.run_development R01 --run-id deploy_check 2>&1 | head -12 || true

echo "=== H. UNTOUCHED CHECK ==="
echo -n "ID30 root still present: "; test -d "$ID30" && echo yes || echo NO
echo -n "ID31 root still present: "; test -d "$ID31" && echo yes || echo NO
echo -n "ID31 DL01 epoch30 checkpoint intact: "
sha256sum "$ID31/results/31_hydrologic_dynamic_tokens/DL01/hydrologic_dynamic_tokens_DL01_learned_end_to_end_s100_2026_0831_1223_ep30/model_epoch030.pt" 2>&1 | cut -c1-64
echo "ID32_DEPLOY_SEQ1_COMPLETE"

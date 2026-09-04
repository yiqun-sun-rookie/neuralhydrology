#!/usr/bin/env bash
# ID33 seq=9 : (1) pin down exactly which source files changed under the running arms,
# (2) return L33 epoch-030 per-basin NSE, (3) return the D01/B01 ID30 baseline per-basin NSE (READ ONLY).
set -o pipefail
ID33=/data1/home/sunyiq/id33_transformer_recipe_repair_20260904/repo
ID30=/data1/home/sunyiq/id30_modern_transformer_moe_20260827/repo
cd "$ID33" 2>/dev/null || { echo NO_LANDING; exit 0; }
echo "=== A. STAMP ==="; date -Is
echo "=== B. WHICH SOURCE FILES DIFFER (L33 before vs after) ==="
python - <<'PY' 2>&1 || true
import json,glob
p=glob.glob('results/33_transformer_recipe_repair/_invocations/id33_L33_s100_slurm220495/run_manifest.json')
d=json.load(open(p[0]))
b=d.get('source_integrity_before',{}); a=d.get('source_integrity_after',{})
bf=b.get('files',{}); af=a.get('files',{})
for k in sorted(set(bf)|set(af)):
    if bf.get(k)!=af.get(k):
        print('DIFF', k); print('   before',bf.get(k)); print('   after ',af.get(k))
print('config_file before',b.get('config_file'))
print('config_file after ',a.get('config_file'))
PY
echo "=== C. GIT STATE OF LANDING REPO (read only) ==="
git -C "$ID33" status --porcelain 2>&1 | head -30 || true
echo "=== D. L33 EPOCH 030 PER-BASIN NSE ==="
F=$(ls results/33_transformer_recipe_repair/L33/*/validation/model_epoch030/validation_metrics.csv 2>/dev/null | head -1)
echo "file=$F"; sha256sum "$F" 2>&1 || true; wc -l "$F" 2>&1 || true
echo "--BEGIN_L33--"; cat "$F" 2>/dev/null || true; echo "--END_L33--"
echo "=== E. ID30 BASELINE TABLES (read only) ==="
for ARM in B01 D01; do
  G=$(ls "$ID30"/results/30_modern_transformer_moe/$ARM/*/validation/model_epoch030/validation_metrics.csv 2>/dev/null | head -1)
  echo "arm=$ARM file=$G"; sha256sum "$G" 2>&1 || true; wc -l "$G" 2>&1 || true
  echo "--BEGIN_$ARM--"; cat "$G" 2>/dev/null || true; echo "--END_$ARM--"
done
echo ID33_SEQ9_COMPLETE

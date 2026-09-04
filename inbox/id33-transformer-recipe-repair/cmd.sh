#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/id33_transformer_recipe_repair_20260904/repo
ID30=/data1/home/sunyiq/id30_modern_transformer_moe_20260827/repo
echo "=== STAMP ==="; date -Is
echo "=== A. INTEGRITY BEFORE/AFTER FOR T2 (registry + config) ==="
python - <<'PY' 2>&1 || true
import json,glob
for a in ["T1","T2","T3","T4","L33"]:
    for p in glob.glob("/data1/home/sunyiq/id33_transformer_recipe_repair_20260904/repo/results/33_transformer_recipe_repair/_invocations/id33_%s_*/run_manifest.json"%a):
        d=json.load(open(p))
        b=d.get("source_integrity_before",{}).get("implementation_files",{})
        af=d.get("source_integrity_after",{}).get("implementation_files",{})
        diff=[k for k in b if af and b[k]!=af.get(k)]
        print(a,"changed_files=",diff if af else "NO_AFTER_BLOCK", "keys_after=",list(d.keys())[-6:])
PY
echo "=== A2. CURRENT REGISTRY SHA ==="
sha256sum $ROOT/src/transformer_recipe_repair/registry/experiments.csv || true
echo "=== B. NSE DUMPS (basin,NSE) ==="
dump () { echo "###ARM $1"; awk -F, 'NR==1{for(i=1;i<=NF;i++){if($i=="basin")b=i;if($i=="NSE")n=i};next}{print $b","$n}' "$2" 2>/dev/null | head -540; }
dump D01 $(ls -1 $ID30/results/*/D01/*/validation/model_epoch030/validation_metrics.csv 2>/dev/null | head -1)
dump B01 $(ls -1 $ID30/results/*/B01/*/validation/model_epoch030/validation_metrics.csv 2>/dev/null | head -1)
for a in T1 T2 T3 T4 L33; do
  dump $a $(ls -1 $ROOT/results/33_transformer_recipe_repair/$a/*/validation/model_epoch030/validation_metrics.csv 2>/dev/null | head -1)
done
echo "ID33_DUMP_COMPLETE"

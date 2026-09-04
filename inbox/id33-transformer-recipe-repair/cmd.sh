#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/id33_transformer_recipe_repair_20260904/repo
cd $ROOT || exit 1
echo "=== STAMP ==="; date -Is
echo "=== A. C1/C2 MANIFEST ==="
for A in C1 C2; do
  echo "--- $A"
  m=$(ls -1 results/33_transformer_recipe_repair/_invocations/id33_${A}_slurm*/run_manifest.json 2>/dev/null | head -1)
  echo "manifest=$m"
  [ -n "$m" ] && grep -E '"(status|training_return_code|seed|experiment_name|arm)"' "$m" | head -20 || true
  [ -n "$m" ] && python3 -c "
import json,sys
d=json.load(open('$m'))
print('status',d.get('status'))
print('trc',d.get('training_return_code'))
da=d.get('data_access',{})
print('data_access',da.get('status') if isinstance(da,dict) else da)
sh=d.get('source_hashes') or d.get('source_integrity')
print('src_keys',list(sh)[:5] if isinstance(sh,dict) else type(sh))
" 2>&1 | head -20 || true
done
echo "=== B. C1/C2 CONFIG DIFF VS T5 ==="
for A in C1 C2 T5; do
  c=$(ls -1 src/transformer_recipe_repair/configs/*${A}*.yml 2>/dev/null | head -1)
  echo "--- $A cfg=$c"
  [ -n "$c" ] && grep -E '^(seed|model|experiment_name|predict_last_n|optimizer|batch_size|transformer_init_scheme|statics_embedding|dynamics_embedding)' "$c" || true
done
echo "=== C. PER-EPOCH MEDIANS ==="
for A in C1 C2; do
  echo "--- $A"
  f=$(ls -1 results/33_transformer_recipe_repair/$A/*/output.log 2>/dev/null | head -1)
  [ -n "$f" ] && grep -E 'Median validation metrics' "$f" | tail -30 || true
done
echo "=== D. EPOCH30 PER-BASIN ==="
for A in C1 C2 T5; do
  g=$(ls -1 results/33_transformer_recipe_repair/$A/*/validation/model_epoch030/validation_metrics.csv 2>/dev/null | head -1)
  echo "### BEGIN $A $g"
  [ -n "$g" ] && python3 -c "
import csv,sys
r=list(csv.DictReader(open('$g')))
k=[x for x in r[0] if x.strip().upper()=='NSE'][0]
b=[x for x in r[0] if 'basin' in x.lower()][0]
print(len(r))
for row in r: print(row[b],row[k])
" 2>&1 || true
  echo "### END $A"
done
echo "ID33_WATCH_COMPLETE"

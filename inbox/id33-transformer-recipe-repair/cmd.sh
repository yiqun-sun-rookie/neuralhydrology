#!/usr/bin/env bash
# ID33 seq=7 : read-only status sweep of the six treatment arms (+ C1/C2 calibration arms).
set -o pipefail
ID33=/data1/home/sunyiq/id33_transformer_recipe_repair_20260904/repo
echo "=== A. STAMP ==="; date -Is
echo "=== B. QUEUE ==="
squeue -u "$USER" -o "%.9i %.10j %.14P %.2t %.11M %.16R" 2>&1 | grep -E 'JOBID|id33' || true
echo "=== C. SACCT ==="
sacct -j 220490,220491,220492,220493,220494,220495,220658,220659 -X -o JobID,JobName%12,State,ExitCode,Elapsed,NodeList 2>&1 || true
echo "=== D. PER-ARM EPOCH PROGRESS ==="
cd "$ID33" 2>/dev/null || { echo NO_LANDING; exit 0; }
for INV in $(ls -d results/33_transformer_recipe_repair/_invocations/*/ 2>/dev/null); do
  echo "--- $INV"
  python - "$INV" <<'PY' 2>&1 || true
import json,sys,pathlib
p=pathlib.Path(sys.argv[1])/'run_manifest.json'
if p.exists():
    d=json.load(open(p))
    print('  status=',d.get('status'),'rc=',d.get('training_return_code'),'data=',(d.get('data_access') or {}).get('status'))
else:
    print('  no manifest yet')
PY
  LOG=$(ls "$INV"/../../*/*/output.log 2>/dev/null | head -0); true
done
echo "=== E. MEDIAN VALIDATION PER EPOCH (all arms) ==="
for D in $(ls -d results/33_transformer_recipe_repair/*/ 2>/dev/null | grep -v _invocations | grep -v _reports); do
  echo "--- $D"
  for R in $(ls -d "$D"*/ 2>/dev/null); do
    grep -oE 'Epoch [0-9]+ average loss.*|Median validation metrics.*' "$R/output.log" 2>/dev/null | tail -40 || true
    echo "  epochdirs: $(ls -d "$R"validation/model_epoch* 2>/dev/null | wc -l)"
  done
done
echo ID33_SEQ7_COMPLETE

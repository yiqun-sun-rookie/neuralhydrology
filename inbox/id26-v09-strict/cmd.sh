#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/v09_strict
FORMAL=$ROOT/codetest/neuralhydrology/results/26_historical_band_experts/formal_v09
JID=$(cat $ROOT/predict_v09/predict_attempt_01_jobid.txt 2>/dev/null || echo "")

echo "=== A JOB ==="
sacct -j "$JID" -X -P --format=JobID,State,ExitCode,Elapsed,NodeList 2>&1 | head -3

echo "=== B OUTPUT STATE ==="
for p in predictions predictions.building; do
  if [ -e "$FORMAL/$p" ]; then echo "$p=present"; else echo "$p=absent"; fi
done
echo "seed_csv=$(ls $FORMAL/predictions/seeds/*.csv 2>/dev/null | wc -l)"
echo "ens_csv=$(ls $FORMAL/predictions/ensembles/*.csv 2>/dev/null | wc -l)"
echo "building_seed_csv=$(ls $FORMAL/predictions.building/seeds/*.csv 2>/dev/null | wc -l)"

echo "=== C ERR TAIL ==="
e=$ROOT/logs/predict_${JID}.err
if [ -f "$e" ]; then echo "err_bytes=$(wc -c < $e)"; tail -15 "$e"; else echo "err absent"; fi

echo "=== D MANIFEST KEY FIELDS ==="
M=$FORMAL/predictions/manifest.json
if [ -f "$M" ]; then
  echo "manifest_sha256=$(sha256sum $M | cut -d' ' -f1)"
  python - "$M" <<'PY'
import json,sys
m=json.load(open(sys.argv[1]))
print("status",m.get("status"))
print("eval",json.dumps(m.get("evaluation_period"),sort_keys=True))
print("seed_records",len(m.get("seed_predictions",[])))
for e in m.get("ensembles",[]):
    print("ens",e["family"],"rows",e["rows"],"sha",e["sha256"][:16],"seeds",len(e["seed_order"]))
for k in ("training_target_reads","formal_evaluation_observation_reads","official_score_called",
          "holdout_nonce_drawn","score_ledger_appended"):
    print(k,m.get(k))
print("denorm",json.dumps(m.get("target_denormalization"),sort_keys=True))
print("device",m["environment"].get("device_name"),m["environment"].get("driver_version"))
PY
else
  echo "manifest absent"
fi
echo "=== END ==="

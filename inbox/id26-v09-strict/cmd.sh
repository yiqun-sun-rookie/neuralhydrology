#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/v09_strict
SCORING=$ROOT/diagnostic_scoring
JID=$(cat $SCORING/score_jobid.txt 2>/dev/null || echo "")

echo "=== A WAIT (max 3 min, short on purpose so the push lock is not held) ==="
for i in $(seq 1 9); do
  st=$(sacct -j "$JID" -X -n -o State 2>/dev/null | head -1 | tr -d ' ')
  case "$st" in COMPLETED|FAILED|TIMEOUT|CANCELLED*|NODE_FAIL) echo "terminal=$st at t=$((i*20))s"; break;; esac
  sleep 20
done
sacct -j "$JID" -X -P --format=JobID,State,ExitCode,Elapsed,NodeList 2>&1 | head -3

echo "=== B ERR ==="
e=$ROOT/logs/diagnostic_score_${JID}.err
if [ -f "$e" ]; then echo "err_bytes=$(wc -c < $e)"; tail -12 "$e"; else echo "err absent"; fi

echo "=== C REPORT ==="
R=$SCORING/diagnostic_score.json
if [ -f "$R" ]; then
  echo "report_sha256=$(sha256sum $R | cut -d' ' -f1)"
  python - "$R" <<'PY'
import json,sys
r=json.load(open(sys.argv[1]))
print("status",r["status"],"diagnostic_only",r["diagnostic_only"],"qualifying",r["qualifying"])
print("median_nse",json.dumps(r["median_nse"],sort_keys=True))
print("coverage",json.dumps(r["coverage"],sort_keys=True))
for k in ("primary_comparison_challenger_vs_capacity",
          "descriptive_challenger_vs_classic",
          "descriptive_capacity_vs_classic"):
    print(k,json.dumps(r[k],sort_keys=True))
print("gate_checks",json.dumps(r["primary_gate_checks"],sort_keys=True))
print("all_pass",r["all_primary_gate_checks_pass"])
for k in ("official_score_called","postseal_holdout_drawn","score_ledger_appended",
          "one_call_authorization_consumed"):
    print(k,r[k])
PY
else
  echo "report absent"
  o=$ROOT/logs/diagnostic_score_${JID}.out
  if [ -f "$o" ]; then tail -20 "$o"; fi
fi
echo "=== END ==="

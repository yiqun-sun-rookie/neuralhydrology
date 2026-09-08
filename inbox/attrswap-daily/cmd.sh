#!/bin/bash
# forcing-swap -- READ-ONLY: capture the passing gate's evidence (determinism, V6 exception note, smoke, report).
set -o pipefail
date "+wallclock %F %T %z"
R=/data1/home/sunyiq/forcing_swap_daily_2026_09
f=$(ls -t "$R"/logs/slurm_fswap_gate_*.out 2>/dev/null | head -1) || true
echo "=== A. GATE LOG ($(basename ${f:-none})) ==="
[ -n "$f" ] && grep -vE '%\|' "$f" | head -60
echo "=== B. CONVERSION REPORT (new) ==="
cat "$R/logs/convert_verify.json" 2>/dev/null
echo
echo "=== C. IS IT BYTE-IDENTICAL TO ATTEMPT 1? (the only expected differences are the V6 fields) ==="
diff <(python -c "
import json,sys
d=json.load(open('$R/logs/convert_verify.attempt1.json'))
for k in ('failures','notes','v6_min_lag0_share','v6_exceptions'): d.pop(k,None)
print(json.dumps(d,indent=1,sort_keys=True))" 2>/dev/null) \
     <(python -c "
import json,sys
d=json.load(open('$R/logs/convert_verify.json'))
for k in ('failures','notes','v6_min_lag0_share','v6_exceptions'): d.pop(k,None)
print(json.dumps(d,indent=1,sort_keys=True))" 2>/dev/null) && echo "  identical apart from the V6 fields"
echo "=== D. ARM PROGRESS ==="
for g in "$R"/logs/slurm_fswap_armE*.out; do
  [ -f "$g" ] || continue
  e=$(grep -oE "Epoch [0-9]+ average loss" "$g" 2>/dev/null | tail -1) || true
  echo "  $(basename $g): ${e:-starting}"
done
echo "=== DONE ==="

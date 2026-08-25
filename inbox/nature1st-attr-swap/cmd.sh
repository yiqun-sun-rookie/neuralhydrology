#!/bin/bash
# nature1st-attr-swap seq=94 -- READ-ONLY status of armI (job 211317).
set -o pipefail
RUN=/data1/home/sunyiq/nature_1st
J=211317
cd "$RUN" || { echo RUN_DIR_MISSING; exit 1; }
date "+wallclock %F %T %z"
echo "=== A. STATE ==="
squeue -j $J -o '%.10i %.24j %.10T %.10M %.22R' 2>&1
sacct -j $J -X --format=JobID%10,JobName%22,State%12,ExitCode%8,Elapsed%11,NodeList%9 2>&1

echo "=== B. GUARD (must say 16 attributes) ==="
f=logs/attr_swap/armI_no_neardam-${J}.out
e=logs/attr_swap/armI_no_neardam-${J}.err
if [ ! -f "$f" ]; then echo "(no stdout log)"; else
  grep -E "\[guard\]" "$f" 2>/dev/null | head -3 || true
  echo "log bytes: $(stat -c%s "$f")  last touched: $(stat -c%y "$f" | cut -c1-19)"
fi

echo "=== C. ERRORS ==="
for g in "$f" "$e"; do [ -f "$g" ] && { echo "-- $g ($(stat -c%s "$g") bytes) --"; grep -E "RuntimeError|Traceback|CUDA|FATAL|Error|refusing|Killed|out of memory" "$g" 2>/dev/null | head -10 || true; }; done

echo "=== D. PROGRESS ==="
[ -f "$f" ] && { grep -E "^Epoch|Best val median NSE|Done\." "$f" 2>/dev/null | tail -10 || true; }

echo "=== E. RESULT? ==="
if [ -f models/q_lstm_armI_hpc_s42/best_metrics.json ]; then cat models/q_lstm_armI_hpc_s42/best_metrics.json 2>&1; echo; else echo '(not finished)'; fi
ls -la models/q_lstm_armI_hpc_s42/eval_val_per_station.csv 2>&1 | head -2

echo "=== F. WHOLE CAMPAIGN ROLL CALL ==="
for d in q_lstm_control_hpc_s42 q_lstm_hydroatlas_hpc_s42 q_lstm_usminus4_hpc_s42 \
         q_lstm_globalplus4_hpc_s42 q_lstm_armE_hpc_s42 q_lstm_armF_hpc_s42 \
         q_lstm_armG_hpc_s42 q_lstm_armI_hpc_s42 ; do
  if [ -f models/$d/best_metrics.json ]; then
    m=$(python -c "import json,sys;print(f'{json.load(open(sys.argv[1]))[\"median_nse\"]:.4f}')" models/$d/best_metrics.json 2>/dev/null)
    printf '  %-30s %s
' "$d" "$m"
  else printf '  %-30s (running or absent)
' "$d"; fi
done
echo "=== END seq=94 ==="

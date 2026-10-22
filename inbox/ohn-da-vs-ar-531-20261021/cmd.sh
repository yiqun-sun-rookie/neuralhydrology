#!/bin/bash
# OHN DA-vs-AR seq8: shorten time limits of OWN pending jobs to realistic values so backfill can use gaps
# (P1 smoke: grid task ~25 min, DA arm ~3 h on RTX 3090; original id18_nse training 10-12.6 h). No other jobs touched.
set -o pipefail
date --iso-8601=seconds
upd() {  # upd <jobid> <limit>
  local st; st=$(squeue -j "$1" -h -o '%T' 2>/dev/null | sort -u | tr '\n' ' ')
  echo "job $1 states: ${st:-GONE}"
  case "$st" in *PENDING*) scontrol update jobid="$1" TimeLimit="$2" 2>&1 && echo "  -> TimeLimit=$2" ;; *) echo "  not pending, unchanged" ;; esac
}
upd 246239 01:30:00
upd 246243 06:00:00
upd 246244 06:00:00
upd 246242 1-00:00:00
echo "=== NEW LIMITS / START ESTIMATES ==="
squeue -j 246239,246240,246242,246243,246244,246245 -h -o '%i|%T|%l|%R|%S' 2>&1 | head -12
squeue -j 246201 -h -o '%i|%T|%M|%R' 2>&1
grep -hE 'A1_TRAIN|SMOKE_A1|Traceback|Error' /data1/home/sunyiq/ohn_da_vs_ar_531_20261021/logs/ohn_a1_smoke-246201.* 2>/dev/null | tail -4
echo "SEQ8_DONE"

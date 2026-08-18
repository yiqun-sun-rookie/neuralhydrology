#!/bin/bash
# ID29 seq=282: read-only. (a) per-running-job epoch/step for walltime projection,
# (b) everything needed to repair the 202226 broken dependency and the three TIMEOUT jobs,
# (c) entry-gate audit payloads for 202510/202511. No writes, no sbatch.
set -eo pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
CL="$ROOT/closure_20260810"

echo "=== SNAPSHOT TIME ==="
date --iso-8601=seconds

echo "=== RUNNING JOB PROGRESS (epoch/step from logs) ==="
for J in 202215_15 202215_16 202215_17; do
  echo "--- job $J ---"
  scontrol show job "${J}" 2>/dev/null | tr ' ' '\n' | grep -E '^(StdOut|TimeLimit|RunTime|NumNodes)=' || echo "  scontrol unavailable"
  SO=$(scontrol show job "${J}" 2>/dev/null | tr ' ' '\n' | sed -n 's/^StdOut=//p' | head -1)
  if [ -n "$SO" ] && [ -f "$SO" ]; then
    echo "  logfile=$SO bytes=$(stat -c %s "$SO")"
    tail -c 300000 "$SO" | tr '\r' '\n' | grep -oE 'Epoch [0-9]+ .*?([0-9]+)/([0-9]+)' | tail -3
    tail -c 300000 "$SO" | tr '\r' '\n' | grep -E '^# Epoch|Epoch [0-9]+' | tail -3
  else
    echo "  no stdout file resolved"
  fi
done

echo "=== 202226 SUBMISSION DETAILS ==="
scontrol show job 202226 2>/dev/null | tr ' ' '\n' | grep -E '^(JobId|ArrayJobId|ArrayTaskId|JobName|Dependency|Command|StdOut|StdErr|TimeLimit|Partition|Reason|WorkDir)=' || echo 'no scontrol record'

echo "=== 202214 / 202215 SUBMISSION DETAILS ==="
for J in 202214 202215; do
  echo "--- $J ---"
  scontrol show job "$J" 2>/dev/null | tr ' ' '\n' | grep -E '^(JobId|JobName|Dependency|Command|TimeLimit|Partition|Reason)=' || echo '  no live record'
  sacct -X -n -P -j "$J" --format=JobID,State,Timelimit,Elapsed,End | head -30
done

echo "=== SLURM SCRIPTS PRESENT ==="
find "$CL" -maxdepth 3 -name '*.slurm' -printf '%p|%s bytes|%TY-%Tm-%Td\n' 2>/dev/null | sort | head -30

echo "=== DEPENDENCY WIRING OF PENDING JOBS ==="
for J in 202226 202229 202230 202294 202315; do
  printf '%s -> ' "$J"
  scontrol show job "$J" 2>/dev/null | tr ' ' '\n' | sed -n 's/^Dependency=//p' | head -1 || echo 'n/a'
done

echo "=== ENTRY-GATE AUDIT PAYLOADS ==="
for D in author_v13_training_data_port_all531_v2 author_v13_warmup_isolation_all531_v2; do
  P="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics/$D"
  echo "--- $D ---"
  [ -f "$P/diagnostic_receipt.json" ] && cat "$P/diagnostic_receipt.json"
  [ -f "$P/audit.json" ] && { echo "  audit.json sha256=$(sha256sum "$P/audit.json" | cut -d' ' -f1) bytes=$(stat -c %s "$P/audit.json")"; head -c 1800 "$P/audit.json"; echo; }
done

echo "=== END seq=282 read_only=true ==="
date --iso-8601=seconds
exit 0

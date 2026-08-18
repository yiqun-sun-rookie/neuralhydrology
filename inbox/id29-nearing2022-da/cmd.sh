#!/bin/bash
# ID29 seq=283: read-only repair intel. seq=282 died because a non-matching grep under
# `set -eo pipefail` aborts the script; every grep/tail here is guarded with `|| true`.
set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
CL="$ROOT/closure_20260810"

echo "=== SNAPSHOT TIME ==="; date --iso-8601=seconds

echo "=== RUNNING JOB PROGRESS ==="
for J in 202215_15 202215_16 202215_17; do
  echo "--- job $J ---"
  scontrol show job "$J" 2>/dev/null | tr ' ' '\n' | grep -E '^(StdOut|TimeLimit|RunTime)=' || true
  SO=$(scontrol show job "$J" 2>/dev/null | tr ' ' '\n' | sed -n 's/^StdOut=//p' | head -1)
  if [ -n "$SO" ] && [ -f "$SO" ]; then
    echo "  bytes=$(stat -c %s "$SO")"
    tail -c 400000 "$SO" 2>/dev/null | tr '\r' '\n' | grep -iE 'epoch' | tail -4 || true
  fi
done

echo "=== 202226 SCONTROL ==="
scontrol show job 202226 2>/dev/null | tr ' ' '\n' | grep -E '^(JobId|ArrayJobId|ArrayTaskId|JobName|Dependency|Command|StdOut|TimeLimit|Partition|Reason|WorkDir|NumCPUs|Gres)=' || echo 'no record'

echo "=== 202214 / 202215 SCONTROL + SACCT ==="
for J in 202214 202215; do
  echo "--- $J ---"
  scontrol show job "$J" 2>/dev/null | tr ' ' '\n' | grep -E '^(JobId|JobName|Dependency|Command|TimeLimit|Partition|Reason)=' || echo '  no live record'
  sacct -X -n -P -j "$J" --format=JobID,State,Timelimit,Elapsed,End 2>/dev/null | head -30 || true
done

echo "=== DEPENDENCY WIRING ==="
for J in 202226 202229 202230 202294 202315; do
  printf '%s -> %s\n' "$J" "$(scontrol show job "$J" 2>/dev/null | tr ' ' '\n' | sed -n 's/^Dependency=//p' | head -1)"
done

echo "=== SLURM SCRIPTS ==="
find "$CL" -maxdepth 3 -name '*.slurm' -printf '%p|%s\n' 2>/dev/null | sort | head -30 || true

echo "=== ENTRY-GATE PAYLOADS ==="
for D in author_v13_training_data_port_all531_v2 author_v13_warmup_isolation_all531_v2; do
  P="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics/$D"
  echo "--- $D ---"
  [ -f "$P/diagnostic_receipt.json" ] && cat "$P/diagnostic_receipt.json" || true
  echo
  [ -f "$P/audit.json" ] && { echo "audit.json sha256=$(sha256sum "$P/audit.json" | cut -d' ' -f1) bytes=$(stat -c %s "$P/audit.json")"; head -c 1500 "$P/audit.json"; echo; } || true
done

echo "=== END seq=283 read_only=true ==="; date --iso-8601=seconds
exit 0

#!/bin/bash
# seq=38 scheduled watch: state of the determinism probe jobs 223971/223972
set -o pipefail
ROOT=/data1/home/sunyiq/id33_transformer_recipe_repair_20260904/repo
echo "=== STAMP ==="; date -Iseconds
echo "=== A. JOB STATES ==="
sacct -j 223971,223972,222800,222801 -X --format=JobID%10,JobName%18,State%12,ExitCode%8,Elapsed%10,NodeList%10 2>&1 || true
echo "=== B. ID33 IN FLIGHT ==="
squeue -u "$USER" -h -o "%i %j %T %M" 2>/dev/null | grep '^.*id33' || echo "none"
echo "=== C. 223971 tail ==="
tail -n 40 "$ROOT"/logs/33_transformer_recipe_repair/*223971*.out 2>&1 || true
echo "-- err --"
tail -n 8 "$ROOT"/logs/33_transformer_recipe_repair/*223971*.err 2>&1 || true
echo "=== D. 223972 tail ==="
tail -n 40 "$ROOT"/logs/33_transformer_recipe_repair/*223972*.out 2>&1 || true
echo "-- err --"
tail -n 8 "$ROOT"/logs/33_transformer_recipe_repair/*223972*.err 2>&1 || true

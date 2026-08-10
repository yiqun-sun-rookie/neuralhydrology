#!/bin/bash
# ID29 seq=85: diagnose the seq=84 fail-closed pre-submission guard without submitting or changing jobs.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
IDEA="$ROOT/src/29_nearing2022_da_ar"
GATE_SLURM="$IDEA/hpc/run_registered_numerical_gate.slurm"
EVAL_SCRIPT="$IDEA/scripts/evaluate_full_reproduction.py"
ACCEPTANCE="$IDEA/reference/reproduction_acceptance.json"
GATE_OUTPUT="$ROOT/closure_20260810/aggregation/final_reproduction_gate.json"
GATE_DETAILS="$ROOT/closure_20260810/aggregation/final_reproduction_differences.csv"

echo "=== INSTALLED FILES ==="
sha256sum "$GATE_SLURM" "$EVAL_SCRIPT" "$ACCEPTANCE"
bash -n "$GATE_SLURM"

echo "=== PRE-SUBMISSION PATH GUARDS ==="
for path in "$GATE_OUTPUT" "$GATE_DETAILS"; do
  if test -e "$path"; then
    stat -c 'exists=YES|path=%n|bytes=%s|mtime=%y' "$path"
    sha256sum "$path"
  else
    echo "exists=NO|path=$path"
  fi
done

echo "=== EXISTING NUMERICAL-GATE JOBS ==="
squeue -h -u "$USER" -n N22-gate -o '%i|%T|%r|%j' || true
sacct -n -P -S 2026-08-10 -u "$USER" --name N22-gate --format=JobID,JobName,State,ExitCode,Submit,Start,End | sed '/^[[:space:]]*$/d' || true

echo "=== DEPENDENCIES AND CANDIDATE HOLD ==="
for job in 202229 202230 202293 202294; do
  scontrol show job -o "$job" | sed -n "s/.*Dependency=\([^ ]*\).*/$job|\1/p"
done
HELD_STATE=$(squeue -h -j 202293 -o '%i|%T|%r|%j')
echo "held_manifest=$HELD_STATE"
test "$HELD_STATE" = "202293|PENDING|JobHeldUser|N22-manifest"

echo "diagnostic_complete=YES"

#!/bin/bash
# ID29 seq=105: submit the unchanged formal preclosure validator on ngu003, where system Git was directly observed.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
VALIDATION="$ROOT/src/29_nearing2022_da_ar/hpc/run_preclosure_validation.slurm"
JOB_RECEIPT="$ROOT/closure_20260810/provenance/preclosure_validation_seq105_job.txt"

echo "=== PRECONDITIONS ==="
test "$(sacct -n -P -j 202370 --format=JobIDRaw,State | awk -F'|' '$1 == "202370" {print $2; exit}')" = "FAILED"
test -z "$(squeue -h -n N22-preclosure-check -o '%i')"
test -f "$VALIDATION"
test ! -e "$JOB_RECEIPT"
grep -q '^ngu003$' "$ROOT/closure_20260810/provenance/git_executable_compute_probe_seq103.out"
grep -q '^/usr/bin/git$' "$ROOT/closure_20260810/provenance/git_executable_compute_probe_seq103.out"
grep -q '^git version 1.8.3.1$' "$ROOT/closure_20260810/provenance/git_executable_compute_probe_seq103.out"

echo "=== SUBMIT UNCHANGED VALIDATOR ON VERIFIED NODE ==="
VALIDATION_JOB_ID=$(sbatch --parsable --nodelist=ngu003 "$VALIDATION" | cut -d';' -f1)
test -n "$VALIDATION_JOB_ID"
printf '%s\n' "$VALIDATION_JOB_ID" > "$JOB_RECEIPT"
echo "validation_job_id=$VALIDATION_JOB_ID"
scontrol show job -o "$VALIDATION_JOB_ID"

echo "=== SAFETY BOUNDARY ==="
test "$(squeue -h -j 202293 -o '%i|%T|%r|%j')" = "202293|PENDING|JobHeldUser|N22-manifest"
test "$(squeue -h -j 202315 -o '%i|%T|%r|%j')" = "202315|PENDING|Dependency|N22-gate"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_gate.json"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_differences.csv"
sha256sum "$VALIDATION" "$JOB_RECEIPT"

#!/bin/bash
set -o pipefail
ROOT=~/kuwei_paired
echo "=== gate job ==="
J=$(grep -oE '[0-9]+' $ROOT/gate/gate_jobid.txt 2>/dev/null | tail -1); echo "jobid=$J"
sacct -j $J --format=JobID,State,ExitCode,Elapsed,NodeList%10 2>&1 | head -4 || true
echo "=== gate stdout tail ==="
G=$(ls -t $ROOT/gate/kuwei-gate-*.out 2>/dev/null | head -1)
[ -n "$G" ] && { echo "file=$G size=$(stat -c%s $G)"; tail -25 "$G"; } || echo "(none)"
echo "=== gate json ==="
[ -f $ROOT/gate/out/determinism_gate.json ] && grep -E 'all_identical|trace_digest|population_sha256|objective_calls|seconds_per' $ROOT/gate/out/determinism_gate.json || echo "(no json yet)"
echo "=== formal job (if launched) ==="
squeue -u ${USER} -n kuwei-formal -o "%.10i %.12j %.8T %.10M %R" 2>&1 | head -4 || true
[ -f $ROOT/formal/formal_jobid.txt ] && cat $ROOT/formal/formal_jobid.txt || echo "(not launched yet)"
echo "=== DONE ==="

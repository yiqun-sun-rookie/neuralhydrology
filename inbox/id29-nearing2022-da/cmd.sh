#!/bin/bash
# ID29 seq=150: monitor the all-531-basin author-v1.3 same-checkpoint diagnostic.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
JOB=202505
FINAL="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics/author_v13_same_checkpoint_te100_all531"
STDOUT="$ROOT/closure_20260810/logs/N22-author-v13-full_202505.out"
STDERR="$ROOT/closure_20260810/logs/N22-author-v13-full_202505.err"

echo "=== ALL-531 AUTHOR V1.3 EVALUATOR ==="
sacct -n -P -j "$JOB" --format=JobID,JobName,State,ExitCode,Elapsed,Start,End,NodeList
STATE=$(sacct -n -P -j "$JOB" --format=JobID,State | awk -F'|' '$1 == "202505" {print $2; exit}')
test -n "$STATE"
echo "parent_state=$STATE"
if [ "$STATE" = COMPLETED ]; then
  test -f "$FINAL/diagnostic_receipt.json"
  test -f "$FINAL/test/model_epoch030/test_results.p"
  test -f "$STDOUT"
  test -f "$STDERR"
  echo "--- diagnostic receipt ---"
  cat "$FINAL/diagnostic_receipt.json"
  echo "--- diagnostic artifact hashes ---"
  sha256sum "$FINAL/diagnostic_receipt.json" "$FINAL/test/model_epoch030/test_results.p" "$STDOUT" "$STDERR"
elif [[ "$STATE" =~ ^(FAILED|TIMEOUT|OUT_OF_MEMORY|NODE_FAIL|PREEMPTED|BOOT_FAIL|DEADLINE)$ ]]; then
  echo "--- diagnostic stdout tail ---"
  test -f "$STDOUT" && tail -160 "$STDOUT" || true
  echo "--- diagnostic stderr tail ---"
  test -f "$STDERR" && tail -160 "$STDERR" || true
else
  squeue -h -j "$JOB" -o '%i|%T|%M|%l|%R|%j'
  echo "--- diagnostic stdout tail if started ---"
  test -f "$STDOUT" && tail -c 32768 "$STDOUT" || true
  echo "--- diagnostic stderr tail if started ---"
  test -f "$STDERR" && tail -80 "$STDERR" || true
fi

echo "=== REGISTERED ARTIFACT SAFETY ==="
test "$(squeue -h -j 202293 -o '%i|%T|%r|%j')" = "202293|PENDING|JobHeldUser|N22-manifest"
test "$(squeue -h -j 202315 -o '%i|%T|%r|%j')" = "202315|PENDING|Dependency|N22-gate"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_gate.json"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_differences.csv"

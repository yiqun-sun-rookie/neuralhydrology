#!/bin/bash
# ID29 seq=189: read-only proof that seq 188 deployed only the verifier wrapper payload.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
DIAGNOSTIC_ROOT="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics"
FINAL="$DIAGNOSTIC_ROOT/warmup_target_replacement_verification_v1"

echo "=== SNAPSHOT TIME ==="
date --iso-8601=seconds

echo "=== SEQ 188 DEPLOYED PAYLOAD ==="
while IFS='|' read -r expected_bytes expected_sha path; do
  test -f "$path"
  test ! -L "$path"
  actual_bytes=$(stat -c '%s' "$path")
  actual_sha=$(sha256sum "$path" | awk '{print $1}')
  echo "$actual_bytes|$actual_sha|$path"
  test "$actual_bytes" = "$expected_bytes"
  test "$actual_sha" = "$expected_sha"
done <<EOF
6299|ad013f8b8618d4762a092a0a0b28f92248a7c3c8dd6b00679e633055338c24a2|$ROOT/src/29_nearing2022_da_ar/hpc/run_warmup_target_replacement_verifier.slurm
1571|c078681dbd82573c2ea2a5585cfe2fb3103fbfa5cf2449643317aea91ca9992c|$ROOT/test/test_nearing2022_replacement_verifier_slurm.py
3231|f537464bcfefe1899ebced35362526504ad8398af48b2260b2bb5833aa53c634|$ROOT/results/29_nearing2022_da_ar/formal_closure/warmup_target_replacement_verifier_slurm_preflight_20260811.json
EOF
bash -n "$ROOT/src/29_nearing2022_da_ar/hpc/run_warmup_target_replacement_verifier.slurm"
test "$(sha256sum "$ROOT/src/29_nearing2022_da_ar/scripts/verify_warmup_target_replacement_chain.py" | awk '{print $1}')" = \
  0bcabc96f9e702f2317464f1f0123c29d49d5f7f0f972a10ea3e01bbf18fe987
echo "seq188_exact_payload_gate=passed"

echo "=== PAIRED TRAINING PAYLOAD INVENTORY ==="
PAIR_PRESENT=0
for relative in \
  src/29_nearing2022_da_ar/scripts/prepare_warmup_target_pair.py \
  src/29_nearing2022_da_ar/scripts/analyze_warmup_target_pair.py \
  src/29_nearing2022_da_ar/hpc/run_warmup_target_pair.slurm \
  src/29_nearing2022_da_ar/hpc/analyze_warmup_target_pair.slurm \
  test/test_nearing2022_warmup_pair.py; do
  path="$ROOT/$relative"
  if test -e "$path"; then
    test -f "$path"
    test ! -L "$path"
    echo "PRESENT|$(stat -c '%s' "$path")|$(sha256sum "$path" | awk '{print $1}')|$relative"
    PAIR_PRESENT=$((PAIR_PRESENT + 1))
  else
    echo "ABSENT|$relative"
  fi
done
echo "paired_training_payload_present=$PAIR_PRESENT"

echo "=== UNSUBMITTED EXECUTION BOUNDARY ==="
QUEUE_ROWS=$(squeue -h -n N22-repl-verify,N22-warm-pair,N22-warm-analysis -o '%i|%j|%T|%M|%R')
printf '%s\n' "$QUEUE_ROWS"
test -z "$QUEUE_ROWS"
test ! -e "$FINAL"
test "$(find "$DIAGNOSTIC_ROOT" -maxdepth 1 -name 'warmup_target_replacement_verification_v1.preparing-*' -print -quit)" = ""
test "$(squeue -h -j 202293 -o '%i|%T|%r|%j')" = '202293|PENDING|JobHeldUser|N22-manifest'
echo "verification_job_submitted=false"
echo "pair_training_submitted=false"
echo "registered_matrix_modified=false"

echo "=== REPLACEMENT JOB STATES ==="
sacct -n -X -P -j 202510,202511 --format=JobIDRaw,JobName,State,ExitCode,Elapsed,Start,End,NodeList
squeue -h -j 202510,202511 -o '%i|%j|%T|%M|%R|%E' | sort

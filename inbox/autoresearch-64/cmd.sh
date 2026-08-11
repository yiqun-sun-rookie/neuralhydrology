#!/bin/bash
set -o pipefail

ATTEMPT=/data1/home/sunyiq/autoresearch64/runs/unified_autoresearch/automatic_rehearsal_8x3_20260811_seq57
SNAPSHOT="$ATTEMPT/snapshot"
EVIDENCE="$ATTEMPT/evidence"
PAYLOAD=/data1/home/sunyiq/hpc_mailbox/inbox/autoresearch-64/payload/automatic_rehearsal_source_65b31c82.tar.gz

echo "=== FAILED JOB ACCOUNTING ==="
sacct -j 202551 -X --format=JobID%12,JobName%20,NodeList%9,State%14,ExitCode%8,Elapsed%10,Start%20,End%20

echo "=== PRESERVED LOGS ==="
for path in \
  /data1/home/sunyiq/hpc_mailbox/outbox/slurm_202551.out \
  /data1/home/sunyiq/hpc_mailbox/outbox/slurm_202551.err \
  "$EVIDENCE/JOB_STDOUT.txt" \
  "$EVIDENCE/JOB_STDERR.txt"; do
  if [ -f "$path" ]; then
    stat -c '%n|bytes=%s|mtime=%y' "$path"
    tail -80 "$path"
  else
    echo "MISSING $path"
  fi
done

echo "=== FAILED VERIFY-STAGE FACTS ==="
echo "payload_sha256=$(sha256sum "$PAYLOAD" | awk '{print $1}')"
for path in \
  "$SNAPSHOT/src/fair_benchmark/frozen/bundle/track0_statics.csv" \
  "$SNAPSHOT/examples/06-Finetuning/531_basin_list.txt" \
  "$SNAPSHOT/.gitignore" \
  "$EVIDENCE/SOURCE_COMMIT.txt" \
  "$EVIDENCE/SNAPSHOT_MANIFEST.sha256"; do
  if [ -f "$path" ]; then
    stat -c '%n|bytes=%s|mtime=%y' "$path"
    sha256sum "$path"
  else
    echo "MISSING $path"
  fi
done
echo "snapshot_file_count=$(find "$SNAPSHOT" -type f 2>/dev/null | wc -l)"
if [ -f "$EVIDENCE/SNAPSHOT_MANIFEST.sha256" ]; then
  (cd "$SNAPSHOT" && sha256sum -c "$EVIDENCE/SNAPSHOT_MANIFEST.sha256" 2>&1 | tail -30)
  echo "snapshot_manifest_exit=${PIPESTATUS[0]}"
fi

echo "=== DOWNSTREAM ABSENCE ==="
for path in \
  "$EVIDENCE/FULL_GATE.json" \
  "$EVIDENCE/PACKAGE_GATE.json" \
  "$ATTEMPT/rehearsal/PROPOSAL_REGISTRY.json" \
  "$ATTEMPT/rehearsal/REHEARSAL_SUMMARY.json" \
  "$EVIDENCE/REHEARSAL_EVIDENCE.json"; do
  [ -e "$path" ] && echo "UNEXPECTED_PRESENT $path" || echo "ABSENT $path"
done
exit 0

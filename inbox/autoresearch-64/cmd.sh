#!/bin/bash
set -o pipefail

EVIDENCE=~/autoresearch64/runs/unified_autoresearch/dlopen_dependency_probe_20260809_seq19
[ -f "$EVIDENCE/SUMMARY.json" ] || { echo "SUMMARY_MISSING"; exit 1; }

echo "=== THREE SANDBOX DENIAL RECORDS ==="
for PACKAGE in numpy pandas pyarrow; do
  echo "--- $PACKAGE ---"
  grep '"event":"ctypes.dlopen"' "$EVIDENCE/runs/$PACKAGE/logs/access.jsonl"
  grep -E '"decision"|"declaration"|"active_version"|"active_module_path"|"initialization_probe_error"' \
    "$EVIDENCE/runs/$PACKAGE/logs/dependency-preflight.json"
done

echo "=== THREE NON-BLOCKING AUDIT STACKS ==="
for PACKAGE in numpy pandas pyarrow; do
  echo "--- $PACKAGE ---"
  cat "$EVIDENCE/supporting_traces/$PACKAGE.stdout.txt"
  echo "stderr_bytes=$(wc -c < "$EVIDENCE/supporting_traces/$PACKAGE.stderr.txt")"
done

echo "=== PROVENANCE ==="
grep -A 8 '"runtime_source_sha256"' "$EVIDENCE/SUMMARY.json"
echo "summary=$EVIDENCE/SUMMARY.json"
echo "manifest=$EVIDENCE/MANIFEST.sha256"

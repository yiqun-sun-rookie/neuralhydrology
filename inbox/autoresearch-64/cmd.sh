#!/bin/bash
set -o pipefail

# Read-only status query for the seq=67 prospective unseen-64 confirmation.
# Submits nothing, writes nothing into the attempt directory.

JOB=202585
ROOT=/data1/home/sunyiq/autoresearch64
ATTEMPT="$ROOT/runs/unified_autoresearch/hbv_lite_unseen_64_confirmation_20260811_seq67"
EVIDENCE="$ATTEMPT/evidence"
CANDIDATE_RUN="$ATTEMPT/candidate_run"
PYTHON="$ROOT/.venv/bin/python"
if [ ! -x "$PYTHON" ]; then PYTHON=$(command -v python3); fi

echo "=== JOB $JOB ==="
squeue -j "$JOB" -o '%.18i %.20j %.12T %.10M %.10l %.20R' 2>&1
sacct -j "$JOB" -X --format=JobID%12,JobName%20,NodeList%9,State%14,ExitCode%8,Elapsed%10,Start%20,End%20 2>&1
echo "--- steps (memory) ---"
sacct -j "$JOB" --format=JobID%16,JobName%16,State%14,ExitCode%8,Elapsed%10,MaxRSS%12,MaxVMSize%12,ReqMem%10 2>&1

echo "=== ATTEMPT DIR ==="
if [ -d "$ATTEMPT" ]; then
  stat -c 'EXISTS %n mtime=%y' "$ATTEMPT"
else
  echo "MISSING $ATTEMPT"
fi

echo "=== EVIDENCE STATUS ==="
for path in \
  "$EVIDENCE/PREFLIGHT.json" \
  "$EVIDENCE/BUILDER_SNAPSHOT_MANIFEST.sha256" \
  "$EVIDENCE/RUNTIME_SNAPSHOT_MANIFEST.sha256" \
  "$EVIDENCE/BUILDER_TESTS.xml" \
  "$EVIDENCE/BUILDER_TESTS_STDOUT.txt" \
  "$EVIDENCE/BUILD_SOURCE_STDOUT.txt" \
  "$EVIDENCE/BUILD_PACKAGES_STDOUT.txt" \
  "$EVIDENCE/CLASSIFY_BASINS_STDOUT.txt" \
  "$ATTEMPT/BASIN_ELIGIBILITY.json" \
  "$EVIDENCE/PACKAGE_GATE.json" \
  "$EVIDENCE/CANDIDATE_COMMAND_STDOUT.txt" \
  "$CANDIDATE_RUN/CANDIDATE_SUMMARY.json" \
  "$EVIDENCE/CONFIRMATION_SUMMARY.json" \
  "$EVIDENCE/MANIFEST.sha256"; do
  if [ -e "$path" ]; then
    stat -c 'EXISTS %n bytes=%s mtime=%y' "$path"
  else
    echo "PENDING $path"
  fi
done

echo "=== CONFIRMATION SUMMARY ==="
if [ -f "$EVIDENCE/CONFIRMATION_SUMMARY.json" ]; then
  cat "$EVIDENCE/CONFIRMATION_SUMMARY.json"
else
  echo "PENDING $EVIDENCE/CONFIRMATION_SUMMARY.json"
fi

echo "=== BUILDER TEST GATE ==="
if [ -f "$EVIDENCE/BUILDER_TESTS.xml" ]; then
  grep -o '<testsuite [^>]*>' "$EVIDENCE/BUILDER_TESTS.xml" | head -5
else
  echo "PENDING $EVIDENCE/BUILDER_TESTS.xml"
fi
if [ -f "$EVIDENCE/BUILDER_TESTS_STDOUT.txt" ]; then
  echo "--- BUILDER_TESTS_STDOUT.txt (tail)"
  tail -15 "$EVIDENCE/BUILDER_TESTS_STDOUT.txt"
fi

echo "=== MONITOR / PEAK MEMORY ==="
if [ -d "$CANDIDATE_RUN" ]; then
  "$PYTHON" - "$CANDIDATE_RUN" <<'PY' 2>&1
import json, sys
from pathlib import Path

root = Path(sys.argv[1])
paths = sorted(root.rglob("runtime-result.json"))
print(f"runtime_result_count={len(paths)}")
WANT = ("monitor", "peak", "sample", "memory", "rss", "_gb", "denied", "status", "exit")
for path in paths:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        print(f"--- {path.relative_to(root)} UNREADABLE {exc}")
        continue
    print(f"--- {path.relative_to(root)}")
    for key in sorted(value):
        if any(token in key.lower() for token in WANT):
            print(f"    {key}={json.dumps(value[key])[:300]}")
PY
else
  echo "PENDING $CANDIDATE_RUN"
fi

echo "=== ACCESS LOGS ==="
if [ -d "$CANDIDATE_RUN" ]; then
  find "$CANDIDATE_RUN" -name access.jsonl -printf '%p lines=' -exec sh -c 'wc -l < "$1"' _ {} \; 2>&1 | head -10
  echo "--- deny events ---"
  find "$CANDIDATE_RUN" -name access.jsonl -exec grep -h '"decision": *"deny"' {} \; 2>/dev/null | head -20
  echo "(end deny events)"
fi

echo "=== LOG TAILS ==="
for path in "$EVIDENCE/JOB_STDOUT.txt" "$EVIDENCE/JOB_STDERR.txt"; do
  if [ -f "$path" ]; then
    echo "--- $path"
    tail -40 "$path"
  else
    echo "--- $path MISSING"
  fi
done

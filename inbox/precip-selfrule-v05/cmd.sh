#!/bin/bash
# precip-selfrule-v05 seq=21: pin concurrency-probe references and audit consumed GPU wall time.
set -eo pipefail

TECH=/data1/home/sunyiq/precip_input_selfrule_time_v05_20260929_r03/technical_8/run01
REF=/data1/home/sunyiq/precip_input_selfrule_time_v05_batch384_probe_20260929/reference_batch128/run01

date "+wallclock %F %T %z"
echo "=== PINNED REFERENCE HASHES ==="
sha256sum \
  "$TECH/technical_summary.json" \
  "$REF/RUN_MANIFEST.json" \
  "$REF/fit/02137727.json" \
  "$REF/predictions/02137727.npz" \
  "$TECH/fit/02245500.json" \
  "$TECH/fit/09404450.json"
echo "=== GPU JOB RECEIPTS ==="
sacct -j 231221,231258,231259,231273,231323 \
  --format=JobID,JobName%24,State,ExitCode,Elapsed,ElapsedRaw,AllocTRES%40,NodeList%14 -P || true

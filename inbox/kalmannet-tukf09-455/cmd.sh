#!/bin/bash
# TUKF09-455 v2r9: create the cluster technical admission only. No training job here.
set -o pipefail

ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r9_20260904
PROJECT="$ROOT/bundle/kalmannet"
TOOL="$PROJECT/hpc/tukf09_455_basin_revision_a800_exclusive_v2r9/stage_and_train.py"
PYSITE="$ROOT/runtime_v2r9/pysite"
PROBE="$ROOT/status/preparation_probe.json"
PRIVATE="$ROOT/runtime_v2r9/evidence/private_runtime_manifest.json"
OUT="$ROOT/status/hpc_technical_admission.json"

echo "TIME=$(date -Is)"
echo "=== PRECONDITIONS ==="
test -f "$PROBE" || { echo PREPARATION_PROBE_MISSING; exit 1; }
test -f "$PRIVATE" || { echo PRIVATE_RUNTIME_MANIFEST_MISSING; exit 1; }
test ! -e "$ROOT/status/PREPARATION_FAILED.json" || { echo ROOT_FROZEN; exit 1; }
if [ -e "$OUT" ]; then echo ADMISSION_ALREADY_PRESENT; sha256sum "$OUT"; exit 0; fi
echo "PREPARATION_PROBE_SHA256=$(sha256sum "$PROBE" | cut -d" " -f1)"
echo "PRIVATE_RUNTIME_MANIFEST_SHA256=$(sha256sum "$PRIVATE" | cut -d" " -f1)"

echo "=== CREATE TECHNICAL ADMISSION ONLY ==="
export PYTHONNOUSERSITE=1
export PYTHONDONTWRITEBYTECODE=1
export PYTHONPATH="$PYSITE:$PROJECT"
"$PYSITE/../bin/python" -V 2>/dev/null || true
PY=/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python
"$PY" -B "$TOOL" admit \
  --project-root "$PROJECT" \
  --probe "$PROBE" \
  --private-manifest "$PRIVATE" \
  --output "$OUT" \
  --authorize-hpc-technical-execution 2>&1
RC=$?
echo "ADMIT_RETURN_CODE=$RC"
if [ "$RC" -ne 0 ]; then echo ADMISSION_NOT_CREATED; exit "$RC"; fi

echo "=== ADMISSION EVIDENCE ==="
ls -l "$OUT" 2>&1
sha256sum "$OUT" 2>&1

echo "=== STILL NO TRAINING ==="
test ! -e "$ROOT/status/training_job_id.txt" && echo NO_TRAINING_JOB_YET || echo TRAINING_JOB_ALREADY_RECORDED
RR="$PROJECT/results/tukf09_455_basin_zero_validation_target_variance_revision_v1"
echo "FILTER_UNITS=$(ls "$RR/filter" 2>/dev/null | wc -l) NEURAL_UNITS=$(ls "$RR/neural" 2>/dev/null | wc -l)"
echo TUKF09_455_V2R9_TECHNICAL_ADMISSION_CREATED_TRAINING_NOT_SUBMITTED

#!/bin/bash
# TUKF09-455: issue the v2r14 technical admission, then submit the training job.
set -eo pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r14_20260909
P="$ROOT/bundle/kalmannet"
S="$ROOT/status"
RT="$ROOT/runtime_v2r14"
echo "TIME=$(date -Is)"

echo "=== PRECONDITIONS ==="
test ! -f "$S/PREPARATION_FAILED.json" || { echo PREPARATION_FAILED_PRESENT; exit 20; }
test -f "$S/preparation_probe.json" || { echo PROBE_MISSING; exit 21; }
test -f "$S/staged_training_sources.json" || { echo STAGED_MISSING; exit 22; }
test -f "$S/initial_bundle_verification.json" || { echo BUNDLE_VERIFICATION_MISSING; exit 23; }
test -f "$RT/evidence/private_runtime_manifest.json" || { echo PRIVATE_MANIFEST_MISSING; exit 24; }
test ! -e "$S/hpc_technical_admission.json" || { echo ADMISSION_ALREADY_EXISTS; exit 25; }
test ! -e "$S/training_job_id.txt" || { echo TRAINING_ALREADY_SUBMITTED; exit 26; }
echo "PREP_JOB=$(cat "$S/preparation_job_id.txt")"
echo PRECONDITIONS_OK

echo "=== ISSUE THE TECHNICAL ADMISSION ==="
source "/data1/home/${USER}/miniconda3/etc/profile.d/conda.sh" || source "${HOME}/miniconda3/etc/profile.d/conda.sh"
conda activate nh_final || { echo CONDA_FAILED; exit 27; }
export PYTHONNOUSERSITE=1
export PYTHONDONTWRITEBYTECODE=1
python -X utf8 -B "$P/hpc/tukf09_455_basin_revision_a800_exclusive_v2r14/stage_and_train.py" admit \
  --project-root "$P" \
  --probe "$S/preparation_probe.json" \
  --private-manifest "$RT/evidence/private_runtime_manifest.json" \
  --output "$S/hpc_technical_admission.json" \
  --authorize-hpc-technical-execution > /dev/null
python -X utf8 - "$S/hpc_technical_admission.json" <<'PYEOF'
import json, sys
a = json.load(open(sys.argv[1]))
for k in sorted(a):
    v = a[k]
    if not isinstance(v, (list, dict)):
        print(f"{k}={v}")
PYEOF

echo "=== THE FOUR-CARD PARTITION RIGHT NOW ==="
sinfo -p hgpu4 -N -O NodeHost,StateLong,Gres,GresUsed,CPUsState 2>&1 | head -6

echo "=== SUBMIT THE TRAINING JOB ==="
JOB=$(sbatch --parsable "$P/hpc/tukf09_455_basin_revision_a800_exclusive_v2r14/submit_training_gpu.slurm")
echo "$JOB" > "$S/training_job_id.txt"
echo "TRAINING_JOB=$JOB"
sleep 30
squeue -j "$JOB" -o "%.10i %.24j %.9P %.8T %.10M %.6D %R" 2>&1 | head -4
echo "--- training stderr, first moments ---"
tail -n 12 "$ROOT/logs/training-$JOB.err" 2>/dev/null | cut -c1-300 || echo "(nothing yet)"

echo TUKF09_455_V2R14_TRAINING_SUBMITTED

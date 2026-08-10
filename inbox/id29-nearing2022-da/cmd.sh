#!/bin/bash
# ID29 seq=72: install the fail-closed final manifest verifier and schedule it after both aggregations.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
PAYLOAD=/data1/home/sunyiq/hpc_mailbox/payload/id29-nearing2022-da/closure_v8.tar.gz
EXPECTED_PAYLOAD_SHA=62a5dd6beeb7cf1b6b9e5fbd75d8d7f371d82c1bcad3b246d70b543cb3d8a80d
VERIFIER="$ROOT/src/29_nearing2022_da_ar/scripts/verify_registered_closure.py"
JOB_SCRIPT="$ROOT/src/29_nearing2022_da_ar/hpc/run_registered_closure_manifest.slurm"

echo "=== INSTALL ==="
echo "$EXPECTED_PAYLOAD_SHA  $PAYLOAD" | sha256sum -c -
test "$(tar -tzf "$PAYLOAD" | wc -l)" -eq 2
tar -xzf "$PAYLOAD" -C "$ROOT"
echo "aa1b1b302c3deca3d2dc5f95fda340b42cefc4852752197d734c3b07a3e04160  $VERIFIER" | sha256sum -c -
echo "38fa0a67b6d82471db57345ed7010cdff390ba911a8dc2d5532ea20012395217  $JOB_SCRIPT" | sha256sum -c -

echo "=== FAIL-CLOSED PREFLIGHT ==="
source ~/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
cd "$ROOT"
export PYTHONPATH="$ROOT${PYTHONPATH:+:$PYTHONPATH}"
PREFLIGHT=$(mktemp)
set +e
python "$VERIFIER" \
  --repo-root "$ROOT" \
  --training-registry "$ROOT/src/29_nearing2022_da_ar/registry/experiment_registry.csv" \
  --evaluation-registry "$ROOT/src/29_nearing2022_da_ar/registry/evaluation_registry.csv" \
  --hyperparameter-registry "$ROOT/src/29_nearing2022_da_ar/registry/assimilation_hyperparameter_registry.csv" \
  --evaluation-aggregation-dir "$ROOT/closure_20260810/aggregation/evaluations" \
  --hyperparameter-aggregation-dir "$ROOT/closure_20260810/aggregation/hyperparameters" > "$PREFLIGHT"
PREFLIGHT_RC=$?
set -e
test "$PREFLIGHT_RC" -eq 2
grep -q '"complete": false' "$PREFLIGHT"
grep -q '"training": 46' "$PREFLIGHT"
grep -q '"evaluations": 180' "$PREFLIGHT"
grep -q '"hyperparameters": 660' "$PREFLIGHT"
sed -n '1,30p' "$PREFLIGHT"
rm -f "$PREFLIGHT"

if squeue -h -u "$USER" -n N22-manifest | grep -q .; then
  echo "Refusing duplicate final manifest submission" >&2
  squeue -u "$USER" -n N22-manifest
  exit 3
fi

echo "=== SUBMIT ==="
MANIFEST_JOB=$(sbatch --parsable --dependency=afterok:202229:202230 "$JOB_SCRIPT")
echo "final_manifest_job_id=$MANIFEST_JOB dependency=afterok:202229:202230"
squeue -j "$MANIFEST_JOB,202229,202230" -o '%.18i %.24j %.2t %.10M %.6D %R'
scontrol show job -o "$MANIFEST_JOB" | sed -n 's/.*Dependency=\([^ ]*\).*/manifest_dependency=\1/p'

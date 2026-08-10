#!/bin/bash
# ID29 seq=74: install the frozen full-matrix gate, replace the pending manifest job, and schedule export.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
IDEA="$ROOT/src/29_nearing2022_da_ar"
PAYLOAD=/data1/home/sunyiq/hpc_mailbox/payload/id29-nearing2022-da/closure_v11.tar.gz
EXPECTED_PAYLOAD_SHA=dd1b2016af3e01486b608793b6c6f9de64b96d1533c819cf35fa8f9fafa30065
AGGREGATOR="$IDEA/scripts/aggregate_registered_results.py"
VERIFIER="$IDEA/scripts/verify_registered_closure.py"
GATE="$IDEA/scripts/evaluate_full_reproduction.py"
ACCEPTANCE="$IDEA/reference/reproduction_acceptance.json"
MANIFEST_SCRIPT="$IDEA/hpc/run_registered_closure_manifest.slurm"
EXPORT_SCRIPT="$IDEA/hpc/run_registered_closure_export.slurm"
AGGREGATION_ROOT="$ROOT/closure_20260810/aggregation"

echo "=== INSTALL V11 ==="
echo "$EXPECTED_PAYLOAD_SHA  $PAYLOAD" | sha256sum -c -
test "$(tar -tzf "$PAYLOAD" | wc -l)" -eq 6
tar -xzf "$PAYLOAD" -C "$ROOT"
echo "1f612fa2fc160180fc624488e7724e39aa4f6413388133d0199d2b758ea8cbb3  $AGGREGATOR" | sha256sum -c -
echo "c4ec4b204d68d347f53c28b34a43ac253418d219c4b117a52be9a93e51b8be16  $VERIFIER" | sha256sum -c -
echo "61568c78e7e8cfe6abf62bc19c10a0c9c3777ce52e1a628db8758eda15192e64  $GATE" | sha256sum -c -
echo "618c3fa3542a93589631add810855d3fa821c013267257857feb6eea3fd7f098  $ACCEPTANCE" | sha256sum -c -
echo "e0650254fae73c33fccd3254c992cbcbf7e07070581e987512669bff33d1b602  $MANIFEST_SCRIPT" | sha256sum -c -
echo "2f052610bf8e2364b440f8e7397effa2e5d7f56cc96757d5fb2330b3003ef209  $EXPORT_SCRIPT" | sha256sum -c -
bash -n "$MANIFEST_SCRIPT"
bash -n "$EXPORT_SCRIPT"

source ~/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
cd "$ROOT"
export PYTHONPATH="$ROOT${PYTHONPATH:+:$PYTHONPATH}"
python -m py_compile "$AGGREGATOR" "$VERIFIER" "$GATE"
python - "$ACCEPTANCE" <<'PY'
import json
from pathlib import Path
import sys

payload = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8'))
assert payload['schema'] == 'nearing2022-reproduction-acceptance-v1'
assert payload['frozen_before_full_matrix_results'] is True
assert payload['expected'] == {
    'time_comparison_rows': 1057,
    'basin_comparison_rows': 21,
    'hyperparameter_coordinates': 660,
}
print('acceptance_contract=OK')
PY

echo "=== VERIFY UPSTREAM JOBS ARE STILL PENDING ==="
test "$(squeue -h -j 202229 -o '%T|%j')" = "PENDING|N22-agg-eval"
test "$(squeue -h -j 202230 -o '%T|%j')" = "PENDING|N22-agg-hyper"
test "$(squeue -h -j 202242 -o '%T|%j')" = "PENDING|N22-manifest"
test ! -e "$AGGREGATION_ROOT/final_artifact_manifest.json"
test ! -e "$AGGREGATION_ROOT/final_reproduction_gate.json"
test ! -e "$AGGREGATION_ROOT/final_reproduction_differences.csv"
test ! -e "$ROOT/closure_20260810/export/nearing2022_final_closure.tar.gz"

echo "=== FAIL-CLOSED PREFLIGHT ==="
STATUS=$(mktemp)
set +e
python "$VERIFIER" \
  --repo-root "$ROOT" \
  --training-registry "$IDEA/registry/experiment_registry.csv" \
  --evaluation-registry "$IDEA/registry/evaluation_registry.csv" \
  --hyperparameter-registry "$IDEA/registry/assimilation_hyperparameter_registry.csv" \
  --evaluation-aggregation-dir "$AGGREGATION_ROOT/evaluations" \
  --hyperparameter-aggregation-dir "$AGGREGATION_ROOT/hyperparameters" > "$STATUS"
STATUS_RC=$?
set -e
test "$STATUS_RC" -eq 2
grep -q '"complete": false' "$STATUS"
grep -q '"training": 46' "$STATUS"
grep -q '"evaluations": 180' "$STATUS"
grep -q '"hyperparameters": 660' "$STATUS"
sed -n '1,16p' "$STATUS"
rm -f "$STATUS"

echo "=== REPLACE OBSOLETE PENDING MANIFEST JOB ==="
scancel 202242
for _ in $(seq 1 20); do
  test -z "$(squeue -h -j 202242 -o '%i' 2>/dev/null || true)" && break
  sleep 1
done
test -z "$(squeue -h -j 202242 -o '%i' 2>/dev/null || true)"
test -z "$(squeue -h -u "$USER" -n N22-manifest -o '%i' 2>/dev/null || true)"
test -z "$(squeue -h -u "$USER" -n N22-export -o '%i' 2>/dev/null || true)"

MANIFEST_JOB=$(sbatch --parsable --dependency=afterok:202229:202230 "$MANIFEST_SCRIPT")
MANIFEST_JOB=${MANIFEST_JOB%%;*}
test -n "$MANIFEST_JOB"
EXPORT_JOB=$(sbatch --parsable --dependency="afterok:$MANIFEST_JOB" "$EXPORT_SCRIPT")
EXPORT_JOB=${EXPORT_JOB%%;*}
test -n "$EXPORT_JOB"
echo "replacement_manifest_job=$MANIFEST_JOB"
echo "export_job=$EXPORT_JOB"
squeue -j "202229,202230,$MANIFEST_JOB,$EXPORT_JOB" -o '%.18i %.24j %.2t %.10M %.6D %R'
scontrol show job -o "$MANIFEST_JOB" | sed -n 's/.*Dependency=\([^ ]*\).*/manifest_dependency=\1/p'
scontrol show job -o "$EXPORT_JOB" | sed -n 's/.*Dependency=\([^ ]*\).*/export_dependency=\1/p'

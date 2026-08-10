#!/bin/bash
# ID29 seq=77: locate the content-addressed closure v12 payload and replace the still-pending final chain.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
IDEA="$ROOT/src/29_nearing2022_da_ar"
PAYLOAD_DIR=/data1/home/sunyiq/hpc_mailbox/payload/id29-nearing2022-da
EXPECTED_PAYLOAD_SHA=e4daf4ab87d42e9ba9ad4ac1f4c40c824f44b5e58a98324fba3737d8b0bf616c
README="$IDEA/README.md"
AGGREGATOR="$IDEA/scripts/aggregate_registered_results.py"
VERIFIER="$IDEA/scripts/verify_registered_closure.py"
GATE="$IDEA/scripts/evaluate_full_reproduction.py"
ACCEPTANCE="$IDEA/reference/reproduction_acceptance.json"
PROTOCOL="$IDEA/reference/released_protocol.json"
MANIFEST_SCRIPT="$IDEA/hpc/run_registered_closure_manifest.slurm"
EXPORT_SCRIPT="$IDEA/hpc/run_registered_closure_export.slurm"
CONTRACT_TEST="$ROOT/test/test_nearing2022_reproduction_contract.py"
AGGREGATION_ROOT="$ROOT/closure_20260810/aggregation"

echo "=== INSTALL V12 ==="
PAYLOAD=
for _ in $(seq 1 25); do
  for CANDIDATE in "$PAYLOAD_DIR"/*; do
    test -f "$CANDIDATE" || continue
    CANDIDATE_SHA=$(sha256sum "$CANDIDATE" | awk '{print $1}')
    if test "$CANDIDATE_SHA" = "$EXPECTED_PAYLOAD_SHA"; then
      PAYLOAD=$CANDIDATE
      break 2
    fi
  done
  sleep 2
done
if test -z "$PAYLOAD"; then
  echo "Expected content-addressed payload was not synchronized" >&2
  find "$PAYLOAD_DIR" -maxdepth 1 -type f -printf '%f|%s\n' | sort >&2 || true
  exit 2
fi
echo "resolved_payload=$PAYLOAD"
echo "$EXPECTED_PAYLOAD_SHA  $PAYLOAD" | sha256sum -c -
test "$(tar -tzf "$PAYLOAD" | wc -l)" -eq 9
tar -xzf "$PAYLOAD" -C "$ROOT"
echo "c4696b70af3597b9eee28f740e5aeef4844ab17f92a95742a5124a085f7e4cb3  $README" | sha256sum -c -
echo "54d9c52818235cf83075b35d51b32c3f7fa4a014374649d6d24ac3a702e48a4a  $AGGREGATOR" | sha256sum -c -
echo "e70a49668b46119bcd41b887df9506a53d389b42c66038a9f59b02d08f948e6e  $VERIFIER" | sha256sum -c -
echo "f6548d2c1935093266ddbfcced8f66b5a540a02ce4e52216001526a34d6b4082  $GATE" | sha256sum -c -
echo "6125cab8935c3ad0ab498865c661c47ea83c837c7627dff2534ba5a5b9185895  $ACCEPTANCE" | sha256sum -c -
echo "2f532baecbe275074111934a5de02c0a3f0ca6b77c81beb739e469b46df1b931  $PROTOCOL" | sha256sum -c -
echo "fa8a50ee433ee19b47d71e4870afa6302dbbe35634f7de2d8c7c1c868a671e9f  $MANIFEST_SCRIPT" | sha256sum -c -
echo "954dd4a6b068070020ec00f126c97fec8adff04cc271db4592ac5bf5eb0f81e0  $EXPORT_SCRIPT" | sha256sum -c -
echo "4b133ba23257b22da7e60b06cbe12249d3fd4dcef3f1d10aa3cca65e38f2ee2c  $CONTRACT_TEST" | sha256sum -c -
bash -n "$MANIFEST_SCRIPT"
bash -n "$EXPORT_SCRIPT"

source ~/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
cd "$ROOT"
export PYTHONPATH="$ROOT${PYTHONPATH:+:$PYTHONPATH}"
python -m py_compile "$AGGREGATOR" "$VERIFIER" "$GATE"
python - "$ACCEPTANCE" "$PROTOCOL" <<'PY'
import json
from pathlib import Path
import sys

acceptance = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8'))
protocol = json.loads(Path(sys.argv[2]).read_text(encoding='utf-8'))
assert acceptance['schema'] == 'nearing2022-reproduction-acceptance-v1'
assert acceptance['frozen_before_full_matrix_results'] is True
assert acceptance['scope'] == {
    'numerical_target': 'released_code',
    'hyperparameter_evaluation_period': 'test',
    'paper_text_hyperparameter_evaluation_period': 'validation',
}
assert acceptance['expected'] == {
    'time_comparison_rows': 1057,
    'basin_comparison_rows': 21,
    'hyperparameter_coordinates': 660,
}
assert protocol['released_experiment_code']['commit'] == 'b254529deb75d950f6417b67e51a7292b7aed430'
assert protocol['released_model_code']['commit'] == 'a3f8bfc0781af44bfee4ed3b4fdfae5ec5aa9a70'
assert protocol['assimilation_hyperparameter_grid']['released_code_evaluation_period'] == 'test'
assert protocol['assimilation_hyperparameter_grid']['paper_text_evaluation_period'] == 'validation'
assert protocol['assimilation_hyperparameter_grid']['expected_runs'] == 660
print('frozen_contracts=OK')
PY

echo "=== VERIFY UPSTREAM AND REPLACED JOBS ARE STILL PENDING ==="
test "$(squeue -h -j 202229 -o '%T|%j')" = "PENDING|N22-agg-eval"
test "$(squeue -h -j 202230 -o '%T|%j')" = "PENDING|N22-agg-hyper"
test "$(squeue -h -j 202280 -o '%T|%j')" = "PENDING|N22-manifest"
test "$(squeue -h -j 202281 -o '%T|%j')" = "PENDING|N22-export"
test ! -e "$AGGREGATION_ROOT/final_artifact_manifest.json"
test ! -e "$AGGREGATION_ROOT/final_reproduction_gate.json"
test ! -e "$AGGREGATION_ROOT/final_reproduction_differences.csv"
test ! -e "$ROOT/closure_20260810/provenance/execution_environment.json"
test ! -e "$ROOT/closure_20260810/provenance/pip_freeze.txt"
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

echo "=== REPLACE PENDING V11 FINAL CHAIN ==="
scancel 202281 202280
for _ in $(seq 1 20); do
  ACTIVE=$(squeue -h -j 202280,202281 -o '%i' 2>/dev/null || true)
  test -z "$ACTIVE" && break
  sleep 1
done
test -z "$(squeue -h -j 202280,202281 -o '%i' 2>/dev/null || true)"
test -z "$(squeue -h -u "$USER" -n N22-manifest -o '%i' 2>/dev/null || true)"
test -z "$(squeue -h -u "$USER" -n N22-export -o '%i' 2>/dev/null || true)"

MANIFEST_JOB=$(sbatch --parsable --dependency=afterok:202229:202230 "$MANIFEST_SCRIPT")
MANIFEST_JOB=${MANIFEST_JOB%%;*}
test -n "$MANIFEST_JOB"
EXPORT_JOB=$(sbatch --parsable --dependency="afterok:$MANIFEST_JOB" "$EXPORT_SCRIPT")
EXPORT_JOB=${EXPORT_JOB%%;*}
test -n "$EXPORT_JOB"
echo "replacement_manifest_job=$MANIFEST_JOB"
echo "replacement_export_job=$EXPORT_JOB"
squeue -j "202229,202230,$MANIFEST_JOB,$EXPORT_JOB" -o '%.18i %.24j %.2t %.10M %.6D %R'
scontrol show job -o "$MANIFEST_JOB" | sed -n 's/.*Dependency=\([^ ]*\).*/manifest_dependency=\1/p'
scontrol show job -o "$EXPORT_JOB" | sed -n 's/.*Dependency=\([^ ]*\).*/export_dependency=\1/p'

echo "=== SUPERSEDED JOB ACCOUNTING ==="
sacct -n -P -j 202280,202281 --format=JobID,JobName,State,ExitCode | sed '/^[[:space:]]*$/d'

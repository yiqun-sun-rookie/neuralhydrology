#!/bin/bash
# ID29 seq=91: bind every numerical-gate input hash before pending job 202315 can start; preserve numerical logic and keep candidate manifest 202293 held.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
IDEA="$ROOT/src/29_nearing2022_da_ar"
PAYLOAD="$HOME/hpc_mailbox/inbox/id29-nearing2022-da/payload.tar.gz"
EVALUATOR="$IDEA/scripts/evaluate_full_reproduction.py"
PROVENANCE="$IDEA/reference/numerical_gate_input_binding_update.json"
BACKUP="$ROOT/closure_20260810/provenance/evaluate_full_reproduction_pre_input_binding_820ce3cb.py"
RECEIPT="$ROOT/closure_20260810/provenance/numerical_gate_input_binding_receipt.json"
GATE_OUTPUT="$ROOT/closure_20260810/aggregation/final_reproduction_gate.json"
GATE_DETAILS="$ROOT/closure_20260810/aggregation/final_reproduction_differences.csv"
PAYLOAD_SHA=eac508deae72ccd0f8259c19c0f917f2b7ff91bda021d39b0fb1591db8515d62
OLD_SHA=820ce3cb543270edd439afcd5b26d21de8867c2560d5be4addc86be80c098276
NEW_SHA=784e5b8d1c5be6db87788e3b62d6ae0f599a0efc2db3d3cbedb5b398c7c5a53b
PROVENANCE_SHA=af30a6d66905aa82f29566af66a9acb8463c935c12acbeb34a432642656612c8

echo "=== PRE-INSTALL SAFETY BOUNDARY ==="
test -f "$PAYLOAD"
echo "$PAYLOAD_SHA  $PAYLOAD" | sha256sum -c -
mapfile -t PAYLOAD_MEMBERS < <(tar -tzf "$PAYLOAD")
test "${#PAYLOAD_MEMBERS[@]}" -eq 2
test "${PAYLOAD_MEMBERS[0]}" = "src/29_nearing2022_da_ar/scripts/evaluate_full_reproduction.py"
test "${PAYLOAD_MEMBERS[1]}" = "src/29_nearing2022_da_ar/reference/numerical_gate_input_binding_update.json"
GATE_STATE=$(squeue -h -j 202315 -o '%i|%T|%r|%j')
echo "gate_state_before=$GATE_STATE"
test "$GATE_STATE" = "202315|PENDING|Dependency|N22-gate"
test ! -e "$GATE_OUTPUT"
test ! -e "$GATE_DETAILS"
test "$(squeue -h -j 202293 -o '%i|%T|%r|%j')" = "202293|PENDING|JobHeldUser|N22-manifest"

echo "=== PRESERVE AND INSTALL ==="
mkdir -p "$(dirname "$BACKUP")"
CURRENT_SHA=$(sha256sum "$EVALUATOR" | awk '{print $1}')
case "$CURRENT_SHA" in
  "$OLD_SHA")
    if [ -e "$BACKUP" ]; then
      echo "$OLD_SHA  $BACKUP" | sha256sum -c -
    else
      install -m 0644 "$EVALUATOR" "$BACKUP"
      echo "$OLD_SHA  $BACKUP" | sha256sum -c -
    fi
    tar -xzf "$PAYLOAD" -C "$ROOT"
    ;;
  "$NEW_SHA")
    echo "$OLD_SHA  $BACKUP" | sha256sum -c -
    echo "install_status=ALREADY_INSTALLED"
    ;;
  *)
    echo "Unexpected evaluator SHA-256 before install: $CURRENT_SHA" >&2
    exit 3
    ;;
esac

echo "$NEW_SHA  $EVALUATOR" | sha256sum -c -
echo "$PROVENANCE_SHA  $PROVENANCE" | sha256sum -c -
python -m py_compile "$EVALUATOR"
python - "$PROVENANCE" "$BACKUP" "$EVALUATOR" "$RECEIPT" "$OLD_SHA" "$NEW_SHA" <<'PY'
import ast
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import sys

provenance_path, backup_path, evaluator_path, receipt_path = map(Path, sys.argv[1:5])
old_sha, new_sha = sys.argv[5:7]
provenance = json.loads(provenance_path.read_text(encoding='utf-8'))
assert provenance['schema'] == 'nearing2022-numerical-gate-input-binding-update-v1'
assert provenance['slurm_job_id'] == '202315'
assert provenance['numerical_logic_changed'] is False
assert provenance['previous_evaluator_sha256'] == old_sha
assert provenance['replacement_evaluator_sha256'] == new_sha

function_names = (
    '_require_columns',
    '_validate_acceptance',
    '_comparison_details',
    '_validate_time_shape',
    '_validate_basin_shape',
    '_hyperparameter_gate',
    'evaluate_reproduction_gate',
    '_atomic_json',
    '_atomic_csv',
    '_build_parser',
)


def function_dumps(path):
    tree = ast.parse(path.read_text(encoding='utf-8'))
    functions = {node.name: node for node in tree.body if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))}
    assert set(function_names) <= set(functions)
    return {name: ast.dump(functions[name], include_attributes=False) for name in function_names}


old_functions = function_dumps(backup_path)
new_functions = function_dumps(evaluator_path)
assert old_functions == new_functions
logic_bytes = json.dumps(new_functions, sort_keys=True, separators=(',', ':')).encode('utf-8')
logic_sha = hashlib.sha256(logic_bytes).hexdigest()
new_source = evaluator_path.read_text(encoding='utf-8')
assert 'gate["input_artifacts"]' in new_source
for label in ('time_comparisons', 'basin_comparisons', 'hyperparameter_scores', 'acceptance'):
    assert f'"{label}": _artifact_fingerprint' in new_source

payload = {
    'schema': 'nearing2022-numerical-gate-input-binding-receipt-v1',
    'mailbox_seq': 91,
    'slurm_job_id': '202315',
    'installed_at': datetime.now(timezone.utc).isoformat(),
    'previous_evaluator_backup': str(backup_path),
    'previous_evaluator_sha256': hashlib.sha256(backup_path.read_bytes()).hexdigest(),
    'installed_evaluator_sha256': new_sha,
    'numerical_logic_changed': False,
    'numerical_function_ast_sha256': logic_sha,
    'bound_inputs': ['time_comparisons', 'basin_comparisons', 'hyperparameter_scores', 'acceptance'],
}
receipt_path.parent.mkdir(parents=True, exist_ok=True)
if receipt_path.exists():
    existing = json.loads(receipt_path.read_text(encoding='utf-8'))
    for key in payload.keys() - {'installed_at'}:
        assert existing[key] == payload[key]
else:
    temporary = receipt_path.with_suffix(receipt_path.suffix + '.tmp')
    temporary.write_text(json.dumps(payload, indent=2, sort_keys=True) + '\n', encoding='utf-8', newline='\n')
    temporary.replace(receipt_path)
print(json.dumps(json.loads(receipt_path.read_text(encoding='utf-8')), sort_keys=True))
PY

echo "=== POST-INSTALL SAFETY BOUNDARY ==="
GATE_STATE=$(squeue -h -j 202315 -o '%i|%T|%r|%j')
echo "gate_state_after=$GATE_STATE"
test "$GATE_STATE" = "202315|PENDING|Dependency|N22-gate"
test ! -e "$GATE_OUTPUT"
test ! -e "$GATE_DETAILS"
test "$(squeue -h -j 202293 -o '%i|%T|%r|%j')" = "202293|PENDING|JobHeldUser|N22-manifest"
sha256sum "$EVALUATOR" "$PROVENANCE" "$BACKUP" "$RECEIPT"

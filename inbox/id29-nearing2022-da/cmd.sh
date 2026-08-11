#!/bin/bash
# ID29 seq=233: recover the role snapshot and traceback from failed role-recorded audit 202728.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
JOB_ID=202728
FINAL="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics/partial_numerical_audit_seq231_v1"
STDOUT="$ROOT/closure_20260810/logs/N22-part-audit6_${JOB_ID}.out"
STDERR="$ROOT/closure_20260810/logs/N22-part-audit6_${JOB_ID}.err"

echo "=== JOB RECORD ==="
sacct -n -X -P -j "$JOB_ID" --format=JobIDRaw,JobName,State,ExitCode,Elapsed,Start,End,NodeList,Reason

echo "=== OUTPUT PATHS ==="
for path in "$STDOUT" "$STDERR"; do
  if test -f "$path"; then
    stat -c '%n|%s|%y' "$path"
    sha256sum "$path"
  else
    echo "missing=$path"
  fi
done

echo "=== STDOUT ==="
test -f "$STDOUT" && cat "$STDOUT"
echo "=== STDERR ==="
test -f "$STDERR" && cat "$STDERR"

echo "=== FINAL AND STAGING INVENTORY ==="
if test -e "$FINAL"; then
  find "$FINAL" -maxdepth 3 -printf '%p|%y|%s\n' | sort
else
  echo "final_exists=false"
fi
find "$(dirname "$FINAL")" -maxdepth 1 -name 'partial_numerical_audit_seq231_v1.preparing-*' -printf '%p|%y\n' | sort
for staging in "$(dirname "$FINAL")"/partial_numerical_audit_seq231_v1.preparing-*; do
  if test -d "$staging"; then
    find "$staging" -maxdepth 2 -type f -printf '%p|%s\n' -exec sha256sum {} \;
    if test -f "$staging/role_snapshot.json"; then
      echo "=== ROLE SNAPSHOT ==="
      cat "$staging/role_snapshot.json"
    fi
  fi
done

echo "=== CURRENT LOGIN-NODE TARGET ROLES ==="
source ~/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
cd "$ROOT"
export PYTHONPATH="$ROOT${PYTHONPATH:+:$PYTHONPATH}"
python - "$ROOT" <<'PY'
import json
from pathlib import Path
import sys

import pandas as pd

root = Path(sys.argv[1]).resolve()
idea = root / "src/29_nearing2022_da_ar"
sys.path.insert(0, str(idea / "scripts"))
from aggregate_registered_results import _registered_run
from audit_partial_registered_results import _complete_roles
from prepare_evaluation_run import resolve_source_run
from verify_registered_closure import _metrics_path

training = pd.read_csv(idea / "registry/experiment_registry.csv", keep_default_na=False, dtype=str)
evaluations = pd.read_csv(idea / "registry/evaluation_registry.csv", keep_default_na=False, dtype=str)
target = "N22-EVAL-TS-DA-L04-TE050-S0"
row = evaluations.loc[evaluations["eval_id"] == target].iloc[0]
run = _registered_run(root, training, row)
result = run / row["result_file"]
reference = resolve_source_run(root, training, row["reference_exp_id"]) / "test/model_epoch030/test_results.p"
roles = {
    "candidate_config": run / "config.yml",
    "candidate_checkpoint": run / "model_epoch030.pt",
    "candidate_log": run / "output.log",
    "candidate_prediction": result,
    "candidate_metrics": _metrics_path(result),
    "reference_prediction": reference,
    "reference_metrics": _metrics_path(reference),
}
complete = {str(item[0]["eval_id"]) for item in _complete_roles(root, training, evaluations)}
print(json.dumps({
    "complete_coordinates": len(complete),
    "target_complete": target in complete,
    "target_roles": {
        name: {
            "path": str(path),
            "exists": path.exists(),
            "is_file": path.is_file(),
            "bytes": path.stat().st_size if path.exists() else None,
            "mtime_ns": path.stat().st_mtime_ns if path.exists() else None,
        }
        for name, path in roles.items()
    },
}, indent=2, sort_keys=True))
PY

echo "=== BOUNDARY ==="
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_gate.json"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_differences.csv"
echo "registered_matrix_modified=false"
echo "frozen_acceptance_modified=false"
echo "failed_staging_preserved=true"
echo "diagnostic_only=true"

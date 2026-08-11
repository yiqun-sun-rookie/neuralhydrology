#!/bin/bash
# ID29 seq=230: read-only role-level diagnosis of the 18-versus-17 evaluation-count discrepancy.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
IDEA="$ROOT/src/29_nearing2022_da_ar"
REGISTRY="$IDEA/registry"
AGGREGATION="$ROOT/closure_20260810/aggregation"
TARGET=N22-EVAL-TS-DA-L04-TE050-S0

echo "=== SNAPSHOT TIME ==="
date --iso-8601=seconds

source ~/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
cd "$ROOT"
export PYTHONPATH="$ROOT${PYTHONPATH:+:$PYTHONPATH}"

echo "=== ROLE-LEVEL COMPARISON ==="
python - "$ROOT" "$IDEA" "$REGISTRY" "$AGGREGATION" "$TARGET" <<'PY'
from __future__ import annotations

import json
from pathlib import Path
import sys

import pandas as pd

root = Path(sys.argv[1]).resolve()
idea = Path(sys.argv[2]).resolve()
registry = Path(sys.argv[3]).resolve()
aggregation = Path(sys.argv[4]).resolve()
target = sys.argv[5]
sys.path.insert(0, str(idea / "scripts"))

from aggregate_registered_results import _registered_run
from audit_partial_registered_results import _complete_roles
from prepare_evaluation_run import resolve_source_run
from verify_registered_closure import _metrics_path, audit_registered_closure

training = pd.read_csv(registry / "experiment_registry.csv", keep_default_na=False, dtype=str)
evaluations = pd.read_csv(registry / "evaluation_registry.csv", keep_default_na=False, dtype=str)
hyperparameters = pd.read_csv(
    registry / "assimilation_hyperparameter_registry.csv", keep_default_na=False, dtype=str
)

previous = {
    "N22-EVAL-TS-AR-L01-TR000-TE000-S0",
    "N22-EVAL-TS-AR-L01-TR000-TE025-S0",
    "N22-EVAL-TS-AR-L01-TR000-TE050-S0",
    "N22-EVAL-TS-AR-L01-TR000-TE075-S0",
    "N22-EVAL-TS-AR-L01-TR000-TE100-S0",
    "N22-EVAL-TS-DA-L01-TE000-S0",
    "N22-EVAL-TS-DA-L01-TE025-S0",
    "N22-EVAL-TS-DA-L01-TE050-S0",
    "N22-EVAL-TS-DA-L01-TE075-S0",
    "N22-EVAL-TS-DA-L01-TE100-S0",
    "N22-EVAL-TS-DA-L02-TE000-S0",
    "N22-EVAL-TS-DA-L02-TE025-S0",
    "N22-EVAL-TS-DA-L02-TE050-S0",
    "N22-EVAL-TS-DA-L02-TE075-S0",
    "N22-EVAL-TS-DA-L02-TE100-S0",
    "N22-EVAL-TS-DA-L04-TE000-S0",
    "N22-EVAL-TS-DA-L04-TE025-S0",
}

partial = _complete_roles(root, training, evaluations)
partial_ids = {str(item[0]["eval_id"]) for item in partial}
closure = audit_registered_closure(
    root,
    registry / "experiment_registry.csv",
    registry / "evaluation_registry.csv",
    registry / "assimilation_hyperparameter_registry.csv",
    aggregation / "evaluations",
    aggregation / "hyperparameters",
)
closure_missing_rows = [
    item for item in closure["missing"] if item["coordinate_type"] == "evaluation"
]
closure_missing_ids = {item["coordinate_id"] for item in closure_missing_rows}
all_ids = set(evaluations["eval_id"])
closure_complete_ids = all_ids - closure_missing_ids

selected = evaluations.loc[evaluations["eval_id"] == target]
if len(selected) != 1:
    raise ValueError(f"Expected one target registry row, found {len(selected)}")
row = selected.iloc[0]
run = _registered_run(root, training, row)
result = run / row["result_file"]
reference_run = resolve_source_run(root, training, row["reference_exp_id"])
reference = reference_run / "test/model_epoch030/test_results.p"
roles = {
    "candidate_config": run / "config.yml",
    "candidate_checkpoint": run / "model_epoch030.pt",
    "candidate_log": run / "output.log",
    "candidate_prediction": result,
    "candidate_metrics": _metrics_path(result),
    "reference_prediction": reference,
    "reference_metrics": _metrics_path(reference),
}


def describe(path: Path) -> dict[str, object]:
    payload: dict[str, object] = {
        "path": str(path),
        "exists": path.exists(),
        "is_file": path.is_file(),
        "is_dir": path.is_dir(),
        "is_symlink": path.is_symlink(),
    }
    if path.exists() or path.is_symlink():
        stat = path.stat()
        payload.update({"bytes": stat.st_size, "mtime_ns": stat.st_mtime_ns})
    return payload


payload = {
    "target": target,
    "registry_row": row.to_dict(),
    "partial_complete_count": len(partial_ids),
    "closure_complete_count": len(closure_complete_ids),
    "partial_minus_closure": sorted(partial_ids - closure_complete_ids),
    "closure_minus_partial": sorted(closure_complete_ids - partial_ids),
    "new_since_verified_17_partial": sorted(partial_ids - previous),
    "missing_from_verified_17_partial": sorted(previous - partial_ids),
    "new_since_verified_17_closure": sorted(closure_complete_ids - previous),
    "missing_from_verified_17_closure": sorted(previous - closure_complete_ids),
    "target_partial_complete": target in partial_ids,
    "target_closure_complete": target in closure_complete_ids,
    "target_closure_missing_rows": [
        item for item in closure_missing_rows if item["coordinate_id"] == target
    ],
    "target_roles": {name: describe(path) for name, path in roles.items()},
    "run_directory": describe(run),
    "reference_run_directory": describe(reference_run),
    "all_current_partial_complete_ids": sorted(partial_ids),
}
print(json.dumps(payload, indent=2, sort_keys=True))

print("=== TARGET RUN INVENTORY ===")
if run.is_dir():
    for path in sorted(run.rglob("*"), key=lambda item: item.as_posix()):
        relative = path.relative_to(run)
        if len(relative.parts) <= 4:
            info = describe(path)
            print(json.dumps({"relative": relative.as_posix(), **info}, sort_keys=True))
PY

echo "=== TARGET SLURM TASK ==="
sacct -n -X -P -j 202222_17 --format=JobIDRaw,JobName,State,ExitCode,Elapsed,Start,End,NodeList,Reason
scontrol show job -o 202222_17 || true

echo "=== TARGET SLURM LOGS ==="
for path in \
  "$ROOT/closure_20260810/logs/N22-eval_202222_17.out" \
  "$ROOT/closure_20260810/logs/N22-eval_202222_17.err"; do
  if test -f "$path"; then
    stat -c '%n|%s|%y' "$path"
    sha256sum "$path"
    tail -n 120 "$path"
  else
    echo "missing=$path"
  fi
done

echo "=== BOUNDARY ==="
test ! -e "$AGGREGATION/final_reproduction_gate.json"
test ! -e "$AGGREGATION/final_reproduction_differences.csv"
echo "registered_matrix_modified=false"
echo "frozen_acceptance_modified=false"
echo "diagnostic_only=true"

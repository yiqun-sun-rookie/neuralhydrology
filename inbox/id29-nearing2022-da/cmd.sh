#!/bin/bash
# ID29 seq=216: add the two static final-provenance root files without overwrite and re-audit scope.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
IDEA="$ROOT/src/29_nearing2022_da_ar"
REGISTRY="$IDEA/registry"
AGGREGATION="$ROOT/closure_20260810/aggregation"
VERIFY_SCRIPT="$IDEA/scripts/verify_registered_closure.py"

test -d "$ROOT"
test ! -L "$ROOT"
test -f "$VERIFY_SCRIPT"
test ! -L "$VERIFY_SCRIPT"
test "$(sha256sum "$VERIFY_SCRIPT" | awk '{print $1}')" = 3b0caef6076d457e303864227e6748ab947e39da01c0c1faea15795807ce8945

source ~/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
cd "$ROOT"
export PYTHONPATH="$ROOT${PYTHONPATH:+:$PYTHONPATH}"

python - "$ROOT" "$IDEA" "$REGISTRY" "$AGGREGATION" "$VERIFY_SCRIPT" <<'PY'
import base64
from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile

import pandas as pd

root = Path(sys.argv[1]).resolve()
idea = Path(sys.argv[2]).resolve()
registry = Path(sys.argv[3]).resolve()
aggregation = Path(sys.argv[4]).resolve()
verify_script = Path(sys.argv[5]).resolve()

payloads = [
    {
        "path": "requirements-gpu.txt",
        "bytes": 183,
        "sha256": "fda6511f52ecb74d81b28fd4082d2326b2686f019558932276edf544cb593e23",
        "base64": "IyBHUFUgZGVwZW5kZW5jeSBlbnRyeXBvaW50IChDVURBIDExLjggd2hlZWxzKQ0KDQotciByZXF1aXJlbWVudHMudHh0DQotLWV4dHJhLWluZGV4LXVybCBodHRwczovL2Rvd25sb2FkLnB5dG9yY2gub3JnL3dobC9jdTExOA0KdG9yY2g+PTIuMC4wDQp0b3JjaHZpc2lvbj49MC4xNS4wDQp0b3JjaGF1ZGlvPj0yLjAuMA0K",
    },
    {
        "path": "setup.cfg",
        "bytes": 123,
        "sha256": "762b42fcd4c93bbe04edd8dcd96fb612e26bb97313f4172e5182ce4a3d5ce539",
        "base64": "W3Rvb2w6cHl0ZXN0XQ0KdGVzdHBhdGhzID0gdGVzdA0KY29sbGVjdF9pZ25vcmVfZ2xvYiA9DQogICAgcmVzdWx0cy8qDQogICAgc3JjLyoNCiAgICBkcmFmdC8qDQogICAgZG9jcy8qDQogICAgZXhhbXBsZXMvKg0K",
    },
]

if not root.is_dir() or root.is_symlink():
    raise SystemExit(f"unsafe root: {root}")
stage_parent = root / "results/29_nearing2022_da_ar/formal_closure"
if not stage_parent.is_dir() or stage_parent.is_symlink():
    raise SystemExit(f"unsafe staging parent: {stage_parent}")

stage = Path(tempfile.mkdtemp(prefix=".seq216_static_provenance_", dir=stage_parent))
entries = []
pending = []
try:
    for index, item in enumerate(payloads):
        rel = Path(item["path"])
        if rel.is_absolute() or len(rel.parts) != 1 or ".." in rel.parts:
            raise SystemExit(f"unsafe payload path: {rel}")
        target = root / rel
        data = base64.b64decode(item["base64"], validate=True)
        actual_hash = hashlib.sha256(data).hexdigest()
        if len(data) != item["bytes"] or actual_hash != item["sha256"]:
            raise SystemExit(f"embedded payload mismatch: {rel}")
        if target.exists() or target.is_symlink():
            if target.is_symlink() or not target.is_file():
                raise SystemExit(f"unsafe existing target: {rel}")
            existing = target.read_bytes()
            existing_hash = hashlib.sha256(existing).hexdigest()
            if len(existing) != item["bytes"] or existing_hash != item["sha256"]:
                raise SystemExit(
                    f"refusing different existing target: {rel} "
                    f"bytes={len(existing)} sha256={existing_hash}"
                )
            entries.append({
                "path": rel.as_posix(),
                "bytes": len(existing),
                "sha256": existing_hash,
                "action": "already_matching",
            })
            continue

        staged = stage / f"{index:02d}.payload"
        with staged.open("xb") as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(staged, 0o644)
        pending.append((rel, target, staged, item))

    for rel, target, staged, item in pending:
        os.link(staged, target)
        deployed = target.read_bytes()
        deployed_hash = hashlib.sha256(deployed).hexdigest()
        if len(deployed) != item["bytes"] or deployed_hash != item["sha256"]:
            raise SystemExit(f"post-deployment mismatch: {rel}")
        entries.append({
            "path": rel.as_posix(),
            "bytes": len(deployed),
            "sha256": deployed_hash,
            "action": "deployed_additively",
        })
finally:
    shutil.rmtree(stage)

by_path = {entry["path"]: entry for entry in entries}
ordered = [by_path[item["path"]] for item in payloads]

sys.path.insert(0, str(verify_script.parent))
from verify_registered_closure import audit_registered_closure, extra_tree_files

training_path = registry / "experiment_registry.csv"
evaluation_path = registry / "evaluation_registry.csv"
hyperparameter_path = registry / "assimilation_hyperparameter_registry.csv"


def run(extra_files=()):
    return audit_registered_closure(
        root,
        training_path,
        evaluation_path,
        hyperparameter_path,
        aggregation / "evaluations",
        aggregation / "hyperparameters",
        extra_files=extra_files,
    )


def missing_signature(payload):
    return sorted(
        (
            row["coordinate_type"],
            row["coordinate_id"],
            row["role"],
            row.get("path", ""),
            row.get("error", ""),
        )
        for row in payload["missing"]
    )


core_first = run()
core_second = run()
if missing_signature(core_first) != missing_signature(core_second):
    raise ValueError("Two immediate core audits disagree")

extra_files = [
    *extra_tree_files(idea),
    *extra_tree_files(root / "neuralhydrology"),
    *extra_tree_files(root / "closure_20260810" / "provenance"),
    root / "test" / "test_assimilation.py",
    root / "test" / "test_nearing2022_reproduction_contract.py",
    root / "setup.cfg",
    root / "requirements-gpu.txt",
]
missing_extra_files = [str(path.resolve()) for path in extra_files if not path.is_file()]
if missing_extra_files:
    raise ValueError(f"Final-provenance files remain missing: {missing_extra_files}")

with_extras = run(extra_files)
if missing_signature(core_first) != missing_signature(with_extras):
    raise ValueError("Complete provenance extras changed the core missing-role set")

missing_ids = {
    kind: {
        row["coordinate_id"]
        for row in core_first["missing"]
        if row["coordinate_type"] == kind
    }
    for kind in ("training", "evaluation", "hyperparameter")
}
evaluations = pd.read_csv(evaluation_path, keep_default_na=False, dtype=str)
complete_evaluation_ids = sorted(set(evaluations["eval_id"]) - missing_ids["evaluation"])

receipt = {
    "schema": "nearing2022-static-final-provenance-deployment-v1",
    "mailbox_seq": 216,
    "status": "exact_static_provenance_present_and_audited",
    "root": str(root),
    "files": len(ordered),
    "deployed": sum(row["action"] == "deployed_additively" for row in ordered),
    "already_matching": sum(row["action"] == "already_matching" for row in ordered),
    "entries": ordered,
    "requested_extra_files": len(extra_files),
    "existing_extra_files": sum(path.is_file() for path in extra_files),
    "missing_extra_files": missing_extra_files,
    "core_missing_roles": len(core_first["missing"]),
    "missing_roles_with_requested_provenance": len(with_extras["missing"]),
    "missing_by_coordinate_type": dict(sorted(Counter(
        row["coordinate_type"] for row in core_first["missing"]
    ).items())),
    "training_complete": core_first["counts"]["training"] - len(missing_ids["training"]),
    "evaluation_complete": len(complete_evaluation_ids),
    "time_split_complete": sum(row.startswith("N22-EVAL-TS-") for row in complete_evaluation_ids),
    "hyperparameter_complete": (
        core_first["counts"]["hyperparameters"] - len(missing_ids["hyperparameter"])
    ),
    "immediate_repeated_core_audits_identical": True,
    "core_vs_complete_extras_missing_set_identical": True,
    "registered_matrix_modified": False,
    "paired_runner_modified_or_deployed": False,
    "slurm_job_modified_or_submitted": False,
    "final_manifest_generated": False,
}
print(json.dumps(receipt, indent=2, sort_keys=True))
PY

echo "=== FROZEN STATES ==="
sacct -n -X -P -j 202510,202511 --format=JobIDRaw,JobName,State,ExitCode,Elapsed,Reason
test "$(squeue -h -j 202293 -o '%i|%T|%r|%j')" = '202293|PENDING|JobHeldUser|N22-manifest'
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_gate.json"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_differences.csv"
for path in \
  "$IDEA/scripts/prepare_warmup_target_pair.py" \
  "$IDEA/hpc/run_warmup_target_pair.slurm" \
  "$IDEA/hpc/run_warmup_target_pair_analysis.slurm"; do
  test ! -e "$path"
done
echo "registered_matrix_modified=false"
echo "paired_runner_modified_or_deployed=false"
echo "slurm_job_modified_or_submitted=false"
echo "final_manifest_generated=false"

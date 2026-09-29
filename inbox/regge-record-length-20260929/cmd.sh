#!/bin/bash
set -eo pipefail

sequence=16
BASE=/data1/home/sunyiq/regge_record_length_20260929_001
CAPSULE=$BASE/deploy/formal_calibration_capsule_001
RUNTIME=$BASE/runtime_stage_005/venv

export PYTHONDONTWRITEBYTECODE=1

test -d "$CAPSULE"
test -x "$RUNTIME/bin/python"

"$RUNTIME/bin/python" -B - "$CAPSULE" <<'PY'
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import sys

root = Path(sys.argv[1])
manifest = json.loads((root / "capsule_manifest.json").read_text(encoding="utf-8"))
expected = manifest["files"]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


actual = {
    path.relative_to(root).as_posix(): sha256(path)
    for path in sorted(root.rglob("*"))
    if path.is_file() and path.name != "capsule_manifest.json"
}
extras = sorted(set(actual) - set(expected))
missing = sorted(set(expected) - set(actual))
mismatches = sorted(
    name for name in set(actual) & set(expected)
    if actual[name] != expected[name]
)
cache_extras = [
    name for name in extras
    if "/__pycache__/" in f"/{name}" and name.endswith((".pyc", ".pyo"))
]
report = {
    "schema": "regge_record_length_failed_deployment_diagnosis_v01",
    "sequence": 16,
    "capsule": str(root),
    "expected_file_count": len(expected),
    "actual_file_count": len(actual),
    "extras": extras,
    "missing": missing,
    "hash_mismatches": mismatches,
    "cache_only_contamination": bool(extras) and extras == cache_extras,
}
print(json.dumps(report, indent=2, sort_keys=True))
if not report["cache_only_contamination"] or missing or mismatches:
    raise SystemExit("failed capsule differs for a reason other than Python bytecode caches")
print("DIAGNOSIS_CONFIRMED=PYTHON_BYTECODE_CACHE_ONLY")
PY

test ! -e "$BASE/formal_calibration_001"
test ! -e "$BASE/transport_package_001"

echo "NO_FORMAL_OUTPUT_OR_PACKAGE=1"
echo "NO_JOB_SUBMITTED_BY_THIS_DIAGNOSTIC=1"

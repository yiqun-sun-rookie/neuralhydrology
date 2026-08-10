#!/bin/bash
set -eo pipefail

ROOT=/data1/home/sunyiq/autoresearch64
PYTHON="$ROOT/.venv/bin/python"
RUNS="$ROOT/runs/unified_autoresearch"

echo "=== CHANNEL INVENTORY ==="
for name in \
  development_packages_real_v1 \
  milestone3_round12_development_packages \
  development_packages_real_64_hpc \
  dlopen_timezone_fix_validation_20260809_seq24
do
  path="$RUNS/$name"
  if [ -d "$path" ]; then
    echo "EXISTS $path"
  else
    echo "MISSING $path"
  fi
done

echo "=== DEVELOPMENT PACKAGE MANIFESTS ==="
"$PYTHON" - "$RUNS" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

runs = Path(sys.argv[1])
for name in (
    "development_packages_real_v1",
    "milestone3_round12_development_packages",
    "development_packages_real_64_hpc",
):
    path = runs / name / "PACKAGE_MANIFEST.json"
    if not path.is_file():
        continue
    raw = path.read_bytes()
    value = json.loads(raw)
    print(json.dumps({
        "name": name,
        "path": str(path),
        "sha256": hashlib.sha256(raw).hexdigest(),
        "schema_version": value.get("schema_version"),
        "basin_count": len(value.get("basins", [])),
        "protocols": sorted(value.get("protocols", {})),
        "source_manifest_sha256": value.get("source_manifest_sha256"),
    }, sort_keys=True))
PY

echo "=== VALIDATED SOURCE SNAPSHOT ==="
EVIDENCE="$RUNS/dlopen_timezone_fix_validation_20260809_seq24/evidence"
if [ -f "$EVIDENCE/SUMMARY.json" ]; then
  "$PYTHON" - "$EVIDENCE/SUMMARY.json" <<'PY'
import json
import sys
from pathlib import Path

summary = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
for key in sorted(summary):
    if "source" in key or "snapshot" in key or "root" in key:
        print(f"{key}={summary[key]}")
PY
fi
find "$RUNS/dlopen_timezone_fix_validation_20260809_seq24" -maxdepth 3 -type d -print 2>/dev/null | sort | head -80

echo "=== JOB 202085 ==="
sacct -j 202085 -X --format=JobID%12,JobName%20,State%14,ExitCode%8,Elapsed%10

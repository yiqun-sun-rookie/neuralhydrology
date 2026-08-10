#!/bin/bash
set -eo pipefail

ROOT=/data1/home/sunyiq/autoresearch64
RUNS="$ROOT/runs/unified_autoresearch"
SNAPSHOT="$RUNS/dlopen_timezone_fix_validation_20260809_seq24"
SOURCE64="$RUNS/development_source_real_64_hpc"
OUTPUT="$RUNS/hbv_lite_8_hpc_smoke_20260810_seq36"

echo "=== REPOSITORY ROOT ==="
if [ -d "$ROOT/.git" ]; then
  echo "git_repository=true"
  cd "$ROOT"
  git rev-parse --verify HEAD 2>/dev/null || true
  git status --porcelain | head -80
else
  echo "git_repository=false"
fi

echo "=== DEVELOPMENT-ONLY SOURCE ==="
if [ -d "$SOURCE64" ]; then
  echo "source_exists=true"
  find "$SOURCE64" -maxdepth 1 -type f -printf '%f %s\n' | sort
  "$ROOT/.venv/bin/python" - "$SOURCE64/SOURCE_MANIFEST.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
value = json.loads(path.read_text(encoding="utf-8"))
print(json.dumps({
    "schema_version": value.get("schema_version"),
    "source_kind": value.get("source_kind"),
    "date_bounds": value.get("date_bounds"),
    "sealed_final_evaluation_present": value.get("sealed_final_evaluation_present"),
    "file_names": sorted(value.get("files", {})),
}, sort_keys=True))
PY
else
  echo "source_exists=false"
fi

echo "=== SNAPSHOT FILE HASHES ==="
cd "$SNAPSHOT"
for relative in \
  src/unified_autoresearch/candidates/catalog.py \
  src/unified_autoresearch/candidates/implementations/hbv_lite.py \
  src/unified_autoresearch/data/packages.py \
  src/unified_autoresearch/runtime/bootstrap.py \
  src/unified_autoresearch/runtime/dependencies.py \
  src/unified_autoresearch/runtime/runner.py \
  src/unified_autoresearch/scripts/run_single_candidate.py \
  src/unified_autoresearch/selection/development_basins_v1.json \
  src/unified_autoresearch/workflow/candidate_development.py
do
  if [ -f "$relative" ]; then sha256sum "$relative"; else echo "MISSING $relative"; fi
done
find src/unified_autoresearch/protocols -maxdepth 1 -type f -printf '%f\n' | sort

echo "=== OUTPUT COLLISION CHECK ==="
if [ -e "$OUTPUT" ]; then echo "output_exists=true"; else echo "output_exists=false"; fi

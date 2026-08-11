#!/bin/bash
# id26-v09-strict seq=50 : inspect bounded upstream evidence schemas and one completed run.
export LC_ALL=C
FORMAL=/data1/home/sunyiq/v09_strict/codetest/neuralhydrology/results/26_historical_band_experts/formal_v09
export FORMAL
find "$FORMAL" -maxdepth 2 -type f -printf '%P\n'
python - <<'PY'
import json
import os
from pathlib import Path

root = Path(os.environ["FORMAL"])
rows = []
for path in root.rglob("*.json"):
    relative = path.relative_to(root)
    if len(relative.parts) > 2:
        continue
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
        rows.append({
            "path": relative.as_posix(),
            "schema": value.get("schema"),
            "status": value.get("status"),
            "top_level_keys": sorted(value),
        })
    except Exception as exc:
        rows.append({"path": relative.as_posix(), "parse_error": str(exc)})

sample = {}
for relative in (
    "continuous/seed_100/manifest.json",
    "continuous/seed_100/seal.json",
):
    path = root / relative
    value = json.loads(path.read_text(encoding="utf-8"))
    sample[relative] = {
        "schema": value.get("schema"),
        "status": value.get("status"),
        "top_level_keys": sorted(value),
        "sealed_files": value.get("sealed_files"),
        "input_bindings": value.get("input_bindings"),
        "dropout_rng_binding": value.get("dropout_rng_binding"),
        "checkpoint_files": value.get("checkpoint_files"),
    }
print(json.dumps({"root_json": rows, "sample": sample}, indent=2, sort_keys=True))
PY

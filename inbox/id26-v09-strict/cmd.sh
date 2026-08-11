#!/bin/bash
# id26-v09-strict seq=51 : locate strict-stage evidence and inspect the completed suite launcher.
export LC_ALL=C
STRICT=/data1/home/sunyiq/v09_strict/neuralhydrology/results/26_historical_band_experts/formal_v09
BASE=/data1/home/sunyiq/v09_strict
export STRICT
find "$STRICT" -maxdepth 3 -type f -printf '%P\n'
find "$BASE" -maxdepth 2 -type f -name '*.json' -printf '%P\n'
tail -n 160 "$BASE/jobs/suite_remaining_21.slurm"
python - <<'PY'
import json
import os
from pathlib import Path

root = Path(os.environ["STRICT"])
rows = []
for path in root.rglob("*.json"):
    relative = path.relative_to(root)
    if len(relative.parts) > 3:
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
print(json.dumps({"strict_root_json": rows}, indent=2, sort_keys=True))
PY

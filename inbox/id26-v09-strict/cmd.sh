#!/bin/bash
# id26-v09-strict seq=52 : locate all resource and determinism preflight evidence.
export LC_ALL=C
BASE=/data1/home/sunyiq/v09_strict
export BASE
find "$BASE" -maxdepth 9 -type f \( -iname '*preflight*.json' -o -iname '*resource*.json' \) -printf '%P\n'
python - <<'PY'
import json
import os
from pathlib import Path

root = Path(os.environ["BASE"])
rows = []
for path in root.rglob("*.json"):
    lowered = path.name.lower()
    if "preflight" not in lowered and "resource" not in lowered:
        continue
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
        rows.append({
            "path": path.relative_to(root).as_posix(),
            "schema": value.get("schema"),
            "status": value.get("status"),
            "device": value.get("device"),
            "workload_count": value.get("workload_count"),
            "opened_formal_inputs": value.get("opened_formal_inputs"),
            "wrote_formal_outputs": value.get("wrote_formal_outputs"),
            "top_level_keys": sorted(value),
        })
    except Exception as exc:
        rows.append({"path": path.relative_to(root).as_posix(), "parse_error": str(exc)})
print(json.dumps({"preflight_reports": rows}, indent=2, sort_keys=True))
PY

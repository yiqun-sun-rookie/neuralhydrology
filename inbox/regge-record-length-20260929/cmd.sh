#!/bin/bash
set -eo pipefail
sequence=31
ROOT=/data1/home/sunyiq/regge_record_length_20260929_001
export PYTHONDONTWRITEBYTECODE=1
"$ROOT/runtime_probe_005/bin/python" -B - "$ROOT/formal_calibration_004/calibration/RL-E1-M06" <<'PY'
from pathlib import Path
from datetime import datetime, timezone
import hashlib
import json
import sys

root = Path(sys.argv[1])
result_path = root / "result.json"
result = json.loads(result_path.read_text(encoding="utf-8"))
receipt = json.loads((root / "receipt.json").read_text(encoding="utf-8"))
process = json.loads((root / "process.json").read_text(encoding="utf-8"))
digest = hashlib.sha256(result_path.read_bytes()).hexdigest()
assert digest == "a715b735fc401a51a7cc1837bef8b045fb72039f39f46878113695f90dd6cb2f"
assert digest == receipt["files"]["result.json"]
print("BINDING_DIAGNOSIS_BEGIN")
print(json.dumps({
    "schema": "regge_record_length_readonly_design_binding_v01",
    "observed_utc": datetime.now(timezone.utc).isoformat(),
    "formal_attempt": "20260929-004",
    "job_id": "232312",
    "exp_id": result["exp_id"],
    "result_sha256": digest,
    "worker_status": receipt["status"],
    "worker_exit_code": process["exit_code"],
    "design_binding": result["design_binding"],
    "design_array_metadata": {name: result["array_hashes"][name]
                              for name in ("parameter_values", "noise_design")},
    "read_only": True,
}, indent=2, allow_nan=False))
print("BINDING_DIAGNOSIS_END")
PY

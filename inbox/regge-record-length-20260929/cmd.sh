#!/bin/bash
set -eo pipefail
sequence=44
ROOT=/data1/home/sunyiq/regge_record_length_20260929_001
PAYLOAD=inbox/regge-record-length-20260929/payload/private_return_upload_001.py
export PYTHONDONTWRITEBYTECODE=1
"$ROOT/runtime_probe_005/bin/python" -B - "$PAYLOAD" <<'PY'
import hashlib
from pathlib import Path
import sys
path = Path(sys.argv[1])
if path.is_symlink() or hashlib.sha256(path.read_bytes()).hexdigest() != "16d61a2977381b728e708f3f1557087d74e18f855da1255ca537d5c4eeb4ad66":
    raise RuntimeError("private_upload_payload_changed")
PY
"$ROOT/runtime_probe_005/bin/python" -B "$PAYLOAD" --launch
echo FIFTH_ATTEMPT_PRIVATE_RETURN_LAUNCHED

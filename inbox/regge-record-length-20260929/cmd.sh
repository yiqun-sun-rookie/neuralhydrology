#!/bin/bash
set -eo pipefail
sequence=41
ROOT=/data1/home/sunyiq/regge_record_length_20260929_001
export PYTHONDONTWRITEBYTECODE=1
"$ROOT/runtime_probe_005/bin/python" -B - "$ROOT/transport_package_005" <<'PY'
import base64
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
import sys
from urllib.parse import urlsplit
package = Path(sys.argv[1])
expected = {"transport_manifest.json": ("16623d80f4bd283ca11ca2beacd8e4fa6594d8113dddf4ecf1529c5b49a02aba", 1140), "transport_manifest.sig": ("3faa17a3c168ad5782704c34abc1ec945d7623d321a1eb6b035725d38870dc8a", 384)}
files = {}
for name, (digest, size) in expected.items():
    data = (package / name).read_bytes()
    if len(data) != size or hashlib.sha256(data).hexdigest() != digest:
        raise RuntimeError("signed return metadata differs")
    files[name] = {"bytes": len(data), "sha256": digest, "base64": base64.b64encode(data).decode("ascii")}
capability = {}
try:
    completed = subprocess.run(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=25", "git@github.com", "git-lfs-authenticate", "yiqun-sun-rookie/neuralhydrology.git", "upload"], capture_output=True, text=True, timeout=120)
    capability["ssh_exit_code"] = completed.returncode
    if completed.returncode == 0:
        auth = json.loads(completed.stdout)
        url = urlsplit(auth.get("href", ""))
        capability.update(authentication_available=bool(auth.get("header")), endpoint_scheme=url.scheme, endpoint_host=url.hostname, endpoint_path=url.path, expires_in=auth.get("expires_in"))
    else:
        capability.update(authentication_available=False, diagnostic="ssh_lfs_authentication_failed")
except Exception as error:
    capability.update(authentication_available=False, error_type=type(error).__name__)
observation = {"schema": "regge_record_length_return_metadata_v01", "formal_attempt": "20260930-005", "mailbox_sequence": 41, "observed_utc": datetime.now(timezone.utc).isoformat(), "remote_package": str(package), "files": files, "lfs_authentication_probe": capability, "payload_uploaded": False, "credential_values_recorded": False}
print("RETURN_METADATA_BEGIN")
print(json.dumps(observation, separators=(",", ":")))
print("RETURN_METADATA_END")
PY
echo FIFTH_ATTEMPT_RETURN_METADATA_COMPLETE

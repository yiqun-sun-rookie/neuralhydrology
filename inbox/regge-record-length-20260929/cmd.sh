#!/bin/bash
set -eo pipefail
sequence=43
ROOT=/data1/home/sunyiq/regge_record_length_20260929_001
export PYTHONDONTWRITEBYTECODE=1
"$ROOT/runtime_probe_005/bin/python" -B - <<'PY'
from datetime import datetime, timezone
import hashlib
import json
import re
import subprocess
from urllib.error import HTTPError
from urllib.request import Request, build_opener, HTTPRedirectHandler
class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None
authentication = subprocess.run(["ssh","-o","BatchMode=yes","-o","ConnectTimeout=25","git@github.com","git-lfs-authenticate","yiqun-sun-rookie/neuralhydrology.git","upload"],capture_output=True,text=True,timeout=120)
if authentication.returncode:
    raise RuntimeError("read_only_authentication_failed")
auth = json.loads(authentication.stdout)
endpoint = auth["href"].rstrip("/") + "/objects/batch"
if endpoint != "https://lfs.github.com/yiqun-sun-rookie/neuralhydrology/objects/batch":
    raise RuntimeError("endpoint_changed")
request_data = {"operation":"upload","transfers":["basic"],"ref":{"name":"refs/heads/hpc-mailbox"},"objects":[{"oid":"3a635659d6f7d4a9740da1b0080006f354db926d6bffe951d5ba8808ffcd4579","size":731826948}]}
headers = {"Accept":"application/vnd.git-lfs+json","Content-Type":"application/vnd.git-lfs+json"}
headers.update(auth["header"])
request = Request(endpoint,data=json.dumps(request_data).encode(),headers=headers,method="POST")
diagnostic = {"schema":"regge_encrypted_return_read_only_diagnosis_v01","formal_attempt":"20260930-005","sequence":43,"observed_utc":datetime.now(timezone.utc).isoformat(),"payload_uploaded":False,"billing_configuration_changed":False}
try:
    with build_opener(NoRedirect()).open(request,timeout=120) as response:
        data = response.read(65537)
        body = json.loads(data)
        obj = body.get("objects", [{}])[0]
        diagnostic.update(http_status=response.status,object_error=obj.get("error"),upload_action_available="upload" in obj.get("actions",{}))
except HTTPError as error:
    data = error.read(65537)
    diagnostic.update(http_status=error.code,error_body_bytes=len(data),error_body_sha256=hashlib.sha256(data).hexdigest())
    try:
        body = json.loads(data)
        message = str(body.get("message",body.get("error","unknown_server_error")))
    except ValueError:
        message = data.decode("utf-8",errors="replace")
    for secret in auth["header"].values():
        message = message.replace(secret,"[REDACTED]")
        for word in secret.split():
            if len(word) > 12:
                message = message.replace(word,"[REDACTED]")
    message = re.sub(r"(https?://\S+|gh[pousr]_[A-Za-z0-9_]+|github_pat_[A-Za-z0-9_]+)", "[REDACTED_URL_OR_CREDENTIAL]", message)
    diagnostic["server_message_redacted"] = message[:1200]
print("RETURN_DIAGNOSIS_BEGIN")
print(json.dumps(diagnostic,separators=(",",":")))
print("RETURN_DIAGNOSIS_END")
PY
echo FIFTH_ATTEMPT_RETURN_DIAGNOSIS_COMPLETE

#!/bin/bash
set -eo pipefail
sequence=42
ROOT=/data1/home/sunyiq/regge_record_length_20260929_001
export PYTHONDONTWRITEBYTECODE=1
"$ROOT/runtime_probe_005/bin/python" -B - "$ROOT" <<'PY'
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
import sys
from urllib.error import HTTPError
from urllib.parse import urlsplit
from urllib.request import build_opener, HTTPRedirectHandler, Request

root = Path(sys.argv[1])
package = root / "transport_package_005"
payload = package / "formal_calibration_005.tar.zst.cms"
receipt_root = root / "return_transfer_005"
oid = "3a635659d6f7d4a9740da1b0080006f354db926d6bffe951d5ba8808ffcd4579"
size = 731826948
started = datetime.now(timezone.utc).isoformat()
receipt_root.mkdir(mode=0o700, exist_ok=False)
def write_new(name, value):
    with (receipt_root / name).open("x", encoding="utf-8") as stream:
        json.dump(value, stream, indent=2, allow_nan=False)
        stream.write("\n")
write_new("seq42.requested.json", {"formal_attempt":"20260930-005", "sequence":42, "started_utc":started, "oid":oid, "bytes":size, "upload_only_ciphertext":True, "billing_configuration_change":False, "automatic_retry":False})

class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None
opener = build_opener(NoRedirect())
def validate_url(url):
    parsed = urlsplit(url)
    host = parsed.hostname or ""
    allowed = host == "lfs.github.com" or host == "github.com" or host.endswith(".githubusercontent.com") or host.endswith(".amazonaws.com")
    if parsed.scheme != "https" or not allowed or parsed.username or parsed.password or parsed.port not in (None,443):
        raise RuntimeError("untrusted_transfer_endpoint")
    return parsed
def validate_headers(headers):
    if not isinstance(headers, dict) or any(not isinstance(k,str) or not isinstance(v,str) or "\r" in k+v or "\n" in k+v for k,v in headers.items()):
        raise RuntimeError("invalid_transfer_headers")
    return headers
def json_post(url, value, headers):
    validate_url(url)
    request_headers = {"Accept":"application/vnd.git-lfs+json", "Content-Type":"application/vnd.git-lfs+json"}
    request_headers.update(validate_headers(headers))
    request = Request(url, data=json.dumps(value).encode("utf-8"), headers=request_headers, method="POST")
    with opener.open(request, timeout=120) as response:
        data = response.read(1048577)
        if len(data) > 1048576:
            raise RuntimeError("oversized_metadata_response")
        return json.loads(data or b"{}"), response.status
def object_from_batch(result):
    objects = result.get("objects", [])
    if len(objects) != 1 or objects[0].get("oid") != oid or objects[0].get("size") != size:
        raise RuntimeError("batch_object_identity_differs")
    obj = objects[0]
    if "error" in obj:
        raise RuntimeError("lfs_object_error_code_" + str(obj["error"].get("code")))
    if result.get("transfer", "basic") != "basic":
        raise RuntimeError("unexpected_transfer_protocol")
    return obj
try:
    manifest_data = (package / "transport_manifest.json").read_bytes()
    if hashlib.sha256(manifest_data).hexdigest() != "16623d80f4bd283ca11ca2beacd8e4fa6594d8113dddf4ecf1529c5b49a02aba":
        raise RuntimeError("signed_manifest_changed")
    manifest = json.loads(manifest_data)
    if manifest["files"][payload.name] != {"sha256":oid,"bytes":size} or payload.stat().st_size != size or payload.is_symlink():
        raise RuntimeError("encrypted_source_identity_differs")
    auth_process = subprocess.run(["ssh","-o","BatchMode=yes","-o","ConnectTimeout=25","git@github.com","git-lfs-authenticate","yiqun-sun-rookie/neuralhydrology.git","upload"], capture_output=True, text=True, timeout=120)
    if auth_process.returncode != 0:
        raise RuntimeError("lfs_authentication_failed")
    auth = json.loads(auth_process.stdout)
    endpoint = auth["href"].rstrip("/") + "/objects/batch"
    if endpoint != "https://lfs.github.com/yiqun-sun-rookie/neuralhydrology/objects/batch":
        raise RuntimeError("repository_endpoint_differs")
    batch_request = {"operation":"upload","transfers":["basic"],"ref":{"name":"refs/heads/hpc-mailbox"},"objects":[{"oid":oid,"size":size}]}
    batch, batch_status = json_post(endpoint, batch_request, auth["header"])
    obj = object_from_batch(batch)
    actions = obj.get("actions", {})
    upload = actions.get("upload")
    upload_status = None
    if upload:
        upload_url = validate_url(upload["href"])
        upload_headers = validate_headers(upload.get("header", {}))
        config = "url = " + json.dumps(upload["href"]) + "\nrequest = \"PUT\"\nupload-file = " + json.dumps(str(payload)) + "\nheader = \"Content-Type: application/octet-stream\"\n"
        for key, value in upload_headers.items():
            config += "header = " + json.dumps(key + ": " + value) + "\n"
        transferred = subprocess.run(["curl","--config","-","--fail","--silent","--show-error","--connect-timeout","120","--max-time","3600","--output","/dev/null","--write-out","%{http_code}"], input=config, text=True, capture_output=True, timeout=3660)
        if transferred.returncode != 0:
            raise RuntimeError("encrypted_upload_curl_exit_" + str(transferred.returncode))
        upload_status = int(transferred.stdout.strip())
        if upload_status not in (200,201,202,204):
            raise RuntimeError("unexpected_upload_http_status")
    verify_status = None
    if "verify" in actions:
        _, verify_status = json_post(actions["verify"]["href"], {"oid":oid,"size":size}, actions["verify"].get("header",{}))
    auth_download_process = subprocess.run(["ssh","-o","BatchMode=yes","-o","ConnectTimeout=25","git@github.com","git-lfs-authenticate","yiqun-sun-rookie/neuralhydrology.git","download"], capture_output=True, text=True, timeout=120)
    if auth_download_process.returncode != 0:
        raise RuntimeError("download_authentication_failed")
    download_auth = json.loads(auth_download_process.stdout)
    if download_auth["href"].rstrip("/") + "/objects/batch" != endpoint:
        raise RuntimeError("download_repository_differs")
    download_request = dict(batch_request, operation="download")
    download_batch, download_status = json_post(endpoint, download_request, download_auth["header"])
    downloaded_obj = object_from_batch(download_batch)
    download_action = downloaded_obj.get("actions", {}).get("download")
    if not download_action:
        raise RuntimeError("uploaded_object_not_downloadable")
    validate_url(download_action["href"])
    receipt = {"schema":"regge_record_length_encrypted_return_upload_v01","formal_attempt":"20260930-005","sequence":42,"status":"complete","started_utc":started,"finished_utc":datetime.now(timezone.utc).isoformat(),"repository":"yiqun-sun-rookie/neuralhydrology","ref":"refs/heads/hpc-mailbox","oid":oid,"bytes":size,"batch_http_status":batch_status,"upload_http_status":upload_status,"verify_http_status":verify_status,"download_batch_http_status":download_status,"download_action_available":True,"ciphertext_only":True,"credentials_recorded":False,"shared_environment_changed":False,"billing_configuration_changed":False,"packaging_resubmitted":False,"calibration_resubmitted":False}
    write_new("seq42.complete.json", receipt)
    print("RETURN_UPLOAD_RECEIPT_BEGIN")
    print(json.dumps(receipt,separators=(",",":")))
    print("RETURN_UPLOAD_RECEIPT_END")
except Exception as error:
    receipt = {"schema":"regge_record_length_encrypted_return_upload_failure_v01","formal_attempt":"20260930-005","sequence":42,"status":"failed","started_utc":started,"finished_utc":datetime.now(timezone.utc).isoformat(),"oid":oid,"bytes":size,"error_type":type(error).__name__,"http_status":error.code if isinstance(error,HTTPError) else None,"diagnostic":str(error) if isinstance(error,RuntimeError) else "transport_exception_redacted","automatic_retry":False,"science_failed":False,"credentials_recorded":False,"packaging_resubmitted":False,"calibration_resubmitted":False}
    write_new("seq42.failed.json", receipt)
    print("RETURN_UPLOAD_RECEIPT_BEGIN")
    print(json.dumps(receipt,separators=(",",":")))
    print("RETURN_UPLOAD_RECEIPT_END")
    sys.exit(1)
PY
echo FIFTH_ATTEMPT_ENCRYPTED_UPLOAD_COMPLETE

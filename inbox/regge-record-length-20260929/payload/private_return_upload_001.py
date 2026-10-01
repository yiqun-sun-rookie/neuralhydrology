"""One bounded ciphertext upload; credentials remain in process memory."""
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
from urllib.error import HTTPError
from urllib.parse import urlsplit
from urllib.request import build_opener, HTTPRedirectHandler, Request

ROOT = Path("/data1/home/sunyiq/regge_record_length_20260929_001")
STATE = ROOT / "return_transfer_private_001"
PACKAGE = ROOT / "transport_package_005"
PAYLOAD = PACKAGE / "formal_calibration_005.tar.zst.cms"
REPOSITORY = "yiqun-sun-rookie/regge-record-length-return-20260930-005"
REPOSITORY_ID = 1400121358
REF = "refs/heads/main"
OID = "3a635659d6f7d4a9740da1b0080006f354db926d6bffe951d5ba8808ffcd4579"
SIZE = 731826948
MANIFEST_SHA = "16623d80f4bd283ca11ca2beacd8e4fa6594d8113dddf4ecf1529c5b49a02aba"
SIGNATURE_SHA = "3faa17a3c168ad5782704c34abc1ec945d7623d321a1eb6b035725d38870dc8a"
ENDPOINT = "https://lfs.github.com/" + REPOSITORY + "/objects/batch"


def utc_now():
    return datetime.now(timezone.utc).isoformat()


def write_new(directory, name, value):
    with (directory / name).open("x", encoding="utf-8") as stream:
        json.dump(value, stream, indent=2, allow_nan=False)
        stream.write("\n")


def claim_directory(directory):
    directory.mkdir(mode=0o700, exist_ok=False)


def validate_url(url):
    if not isinstance(url, str) or any(ord(c) <= 32 or ord(c) == 127 for c in url) or "\\" in url:
        raise RuntimeError("invalid_transfer_url")
    try:
        parsed = urlsplit(url)
        host = parsed.hostname or ""
        allowed = host in ("lfs.github.com", "github.com") or host.endswith(".githubusercontent.com") or host.endswith(".amazonaws.com")
        if parsed.scheme != "https" or not allowed or parsed.username or parsed.password or parsed.port not in (None, 443) or parsed.fragment:
            raise RuntimeError("untrusted_transfer_endpoint")
    except ValueError:
        raise RuntimeError("invalid_transfer_url") from None
    return url


def validate_headers(headers):
    if not isinstance(headers, dict):
        raise RuntimeError("invalid_transfer_headers")
    for key, value in headers.items():
        if not isinstance(key, str) or not isinstance(value, str) or not re.fullmatch(r"[!#$%&'*+.^_`|~0-9A-Za-z-]+", key) or any(ord(c) < 32 or ord(c) == 127 for c in value):
            raise RuntimeError("invalid_transfer_headers")
    return headers


def object_from_batch(result, oid, size):
    if not isinstance(result, dict):
        raise RuntimeError("invalid_batch_response")
    objects = result.get("objects")
    if not isinstance(objects, list) or len(objects) != 1 or not isinstance(objects[0], dict):
        raise RuntimeError("batch_object_identity_differs")
    obj = objects[0]
    if obj.get("oid") != oid or type(obj.get("size")) is not int or obj["size"] != size:
        raise RuntimeError("batch_object_identity_differs")
    if "error" in obj:
        raise RuntimeError("lfs_object_error")
    if result.get("transfer", "basic") != "basic":
        raise RuntimeError("unexpected_transfer_protocol")
    return obj


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def json_post(url, value, headers):
    validate_url(url)
    request_headers = {"Accept": "application/vnd.git-lfs+json", "Content-Type": "application/vnd.git-lfs+json"}
    request_headers.update(validate_headers(headers))
    request = Request(url, data=json.dumps(value).encode("utf-8"), headers=request_headers, method="POST")
    with build_opener(NoRedirect()).open(request, timeout=120) as response:
        data = response.read(1048577)
        if len(data) > 1048576:
            raise RuntimeError("oversized_metadata_response")
        return json.loads(data or b"{}"), response.status


def authenticate(operation):
    result = subprocess.run(
        ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=25", "git@github.com", "git-lfs-authenticate", REPOSITORY + ".git", operation],
        capture_output=True, text=True, timeout=120,
    )
    if result.returncode:
        raise RuntimeError("lfs_authentication_failed")
    auth = json.loads(result.stdout)
    if auth["href"].rstrip("/") + "/objects/batch" != ENDPOINT:
        raise RuntimeError("repository_endpoint_differs")
    validate_headers(auth["header"])
    return auth


def sha256_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def event(stage, **extra):
    value = {"stage": stage, "utc": utc_now(), "pid": os.getpid(), **extra}
    with (STATE / "events.jsonl").open("a", encoding="utf-8") as stream:
        stream.write(json.dumps(value, separators=(",", ":")) + "\n")
    print(json.dumps(value, separators=(",", ":")), flush=True)


def upload_ciphertext(action):
    validate_url(action["href"])
    headers = validate_headers(action.get("header", {}))
    config = "url = " + json.dumps(action["href"]) + '\nrequest = "PUT"\nupload-file = ' + json.dumps(str(PAYLOAD)) + '\nheader = "Content-Type: application/octet-stream"\n'
    for key, value in headers.items():
        config += "header = " + json.dumps(key + ": " + value) + "\n"
    result = subprocess.run(
        ["curl", "-q", "--config", "-", "--proto", "=https", "--max-redirs", "0", "--fail", "--silent", "--show-error", "--connect-timeout", "120", "--max-time", "3600", "--output", "/dev/null", "--write-out", "%{http_code} %{size_upload} %{speed_upload} %{time_total}"],
        input=config, text=True, capture_output=True, timeout=3660,
    )
    if result.returncode:
        raise RuntimeError("encrypted_upload_curl_exit_" + str(result.returncode))
    fields = result.stdout.strip().split()
    if len(fields) != 4 or int(fields[0]) not in (200, 201, 202, 204) or int(float(fields[1])) != SIZE:
        raise RuntimeError("unexpected_upload_response_or_bytes")
    return {"http_status": int(fields[0]), "bytes_uploaded": int(float(fields[1])), "bytes_per_second": float(fields[2]), "elapsed_seconds": float(fields[3])}


def check_source():
    for name, digest in (("transport_manifest.json", MANIFEST_SHA), ("transport_manifest.sig", SIGNATURE_SHA)):
        path = PACKAGE / name
        if path.is_symlink() or sha256_file(path) != digest:
            raise RuntimeError("signed_package_metadata_changed")
    manifest = json.loads((PACKAGE / "transport_manifest.json").read_bytes())
    if PAYLOAD.is_symlink() or not PAYLOAD.is_file() or PAYLOAD.stat().st_size != SIZE or manifest["files"][PAYLOAD.name] != {"sha256": OID, "bytes": SIZE}:
        raise RuntimeError("encrypted_source_identity_differs")
    if sha256_file(PAYLOAD) != OID:
        raise RuntimeError("encrypted_source_hash_differs")


def worker():
    started = utc_now()
    write_new(STATE, "worker.started.json", {"started_utc": started, "pid": os.getpid(), "repository": REPOSITORY, "oid": OID, "bytes": SIZE})
    def expired(signum, frame):
        raise RuntimeError("bounded_transfer_deadline_exceeded")
    signal.signal(signal.SIGALRM, expired)
    signal.alarm(4500)
    try:
        event("source_verification_started")
        check_source()
        event("source_verified", bytes=SIZE)
        auth = authenticate("upload")
        request = {"operation": "upload", "transfers": ["basic"], "ref": {"name": REF}, "objects": [{"oid": OID, "size": SIZE}]}
        batch, batch_status = json_post(ENDPOINT, request, auth["header"])
        obj = object_from_batch(batch, OID, SIZE)
        actions = obj.get("actions", {})
        if not isinstance(actions, dict):
            raise RuntimeError("invalid_object_actions")
        event("upload_metadata_accepted", http_status=batch_status, upload_required="upload" in actions)
        upload = None
        if "upload" in actions:
            event("ciphertext_upload_started", bytes=SIZE)
            upload = upload_ciphertext(actions["upload"])
            event("ciphertext_uploaded", **upload)
        verify_status = None
        if "verify" in actions:
            action = actions["verify"]
            _, verify_status = json_post(action["href"], {"oid": OID, "size": SIZE}, action.get("header", {}))
        download_auth = authenticate("download")
        download_batch, download_status = json_post(ENDPOINT, dict(request, operation="download"), download_auth["header"])
        download_object = object_from_batch(download_batch, OID, SIZE)
        download_action = download_object.get("actions", {}).get("download")
        if not isinstance(download_action, dict):
            raise RuntimeError("uploaded_object_not_downloadable")
        validate_url(download_action["href"])
        validate_headers(download_action.get("header", {}))
        check_source()
        receipt = {"schema": "regge_record_length_encrypted_private_return_upload_v01", "formal_attempt": "20260930-005", "sequence": 44, "status": "complete", "started_utc": started, "finished_utc": utc_now(), "repository": REPOSITORY, "repository_id": REPOSITORY_ID, "ref": REF, "oid": OID, "bytes": SIZE, "manifest_sha256": MANIFEST_SHA, "batch_http_status": batch_status, "upload": upload, "verify_http_status": verify_status, "download_batch_http_status": download_status, "download_action_available": True, "ciphertext_only": True, "credentials_recorded": False, "billing_configuration_changed": False, "packaging_resubmitted": False, "calibration_resubmitted": False}
        write_new(STATE, "upload.complete.json", receipt)
        event("complete", bytes=SIZE)
    except Exception as error:
        receipt = {"schema": "regge_record_length_encrypted_private_return_upload_failure_v01", "formal_attempt": "20260930-005", "sequence": 44, "status": "failed", "started_utc": started, "finished_utc": utc_now(), "repository": REPOSITORY, "repository_id": REPOSITORY_ID, "oid": OID, "bytes": SIZE, "error_type": type(error).__name__, "http_status": error.code if isinstance(error, HTTPError) else None, "diagnostic": str(error) if isinstance(error, RuntimeError) else "transport_exception_redacted", "automatic_retry": False, "science_failed": False, "credentials_recorded": False}
        write_new(STATE, "upload.failed.json", receipt)
        event("failed", error_type=receipt["error_type"], http_status=receipt["http_status"], diagnostic=receipt["diagnostic"])
        return 1
    finally:
        signal.alarm(0)
    return 0


def launch():
    os.umask(0o077)
    claim_directory(STATE)
    own_source = STATE / "encrypted_upload.py"
    source = Path(__file__).read_bytes()
    with own_source.open("xb") as stream:
        stream.write(source)
    write_new(STATE, "launch.requested.json", {"schema": "regge_private_return_launch_request_v01", "formal_attempt": "20260930-005", "sequence": 44, "requested_utc": utc_now(), "repository": REPOSITORY, "repository_id": REPOSITORY_ID, "source_sha256": hashlib.sha256(source).hexdigest(), "oid": OID, "bytes": SIZE, "launch_count": 1, "automatic_retry": False})
    try:
        with (STATE / "worker.log").open("xb") as log:
            process = subprocess.Popen([sys.executable, "-B", str(own_source), "--worker"], stdin=subprocess.DEVNULL, stdout=log, stderr=log, cwd=STATE, start_new_session=True)
        receipt = {"schema": "regge_private_return_launch_receipt_v01", "formal_attempt": "20260930-005", "sequence": 44, "status": "launched", "pid": process.pid, "launched_utc": utc_now(), "state_directory": str(STATE), "repository": REPOSITORY, "repository_id": REPOSITORY_ID, "oid": OID, "bytes": SIZE, "source_sha256": hashlib.sha256(source).hexdigest(), "bounded_deadline_seconds": 4500, "launch_count": 1}
        write_new(STATE, "launch.complete.json", receipt)
        print("PRIVATE_RETURN_LAUNCH_RECEIPT_BEGIN")
        print(json.dumps(receipt, separators=(",", ":")))
        print("PRIVATE_RETURN_LAUNCH_RECEIPT_END", flush=True)
    except Exception as error:
        write_new(STATE, "launch.failed.json", {"error_type": type(error).__name__, "utc": utc_now(), "automatic_retry": False})
        raise RuntimeError("private_return_launch_failed") from None
    return 0


if __name__ == "__main__":
    if sys.argv[1:] == ["--launch"]:
        sys.exit(launch())
    if sys.argv[1:] == ["--worker"]:
        sys.exit(worker())
    raise SystemExit("expected --launch or --worker")

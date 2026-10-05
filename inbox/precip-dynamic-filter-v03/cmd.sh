#!/usr/bin/env bash
set -euo pipefail
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'EIGHT_INVENTORY_V02'
import sys, re
from pathlib import PurePosixPath
EXCLUSION_TECHNICAL_GATE_SHA256 = '4f993b8baedc8f05e96738d12f784b99433ae80100811be393143285eee50622'
SCRATCH_RELATIVE = 'runtime/synthetic/synthetic_tmp'
sys.argv = ['eight_basin_inventory_v02', 'inventory-remote', '--request', 'eyJhbGxvd19pbmNvbXBsZXRlIjpmYWxzZSwiam9iX2lkIjoyMzYzNTYsInJvb3QiOiIvZGF0YTEvaG9tZS9zdW55aXEvcHJlY2lwX2R5bmFtaWNfZWlnaHRfYmFzaW5zXzIwMjYxMDAzL2VpZ2h0X2Jhc2luX2ZpeGVkX3JlY2lwZV92MDFfMjAyNjEwMDNfMjMwMDAwX2Q1MDI4ZDcxIn0=']
"""Generate read-only mailbox commands and restore bounded raw result fragments.

No mailbox/network client, model, metric, compression or remote whole-file hash is
used. Runtime locks supply some original SHA256 values; missing original digests
are explicitly reported and require a separate scientific reconstruction.
"""

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shlex
import stat
import subprocess
import sys


SCHEMA = "eight-basin-results-raw-transport-v1"
CHANNEL = "precip-dynamic-filter-v03"
REMOTE_PARENT = "/data1/home/sunyiq/precip_dynamic_eight_basins_20261003"
MAX_CHUNK = 4 * 1024 * 1024
MAX_BATCH_FILES = 256
MAX_METADATA = 16 * 1024 * 1024
BEGIN, END = "EIGHT_RESULT_TRANSPORT_BEGIN", "EIGHT_RESULT_TRANSPORT_END"
BASINS = ("01487000", "12040500", "09312600", "08198500", "03078000", "05362000", "08267500", "07145700")
HEX64, HEX40 = re.compile(r"[0-9a-f]{64}\Z"), re.compile(r"[0-9a-f]{40}\Z")


def digest(value):
    return hashlib.sha256(value).hexdigest()


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True, allow_nan=False).encode()


def reject_duplicate_keys(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("Duplicate JSON field")
        result[key] = value
    return result


def parse_json(value):
    return json.loads(value, object_pairs_hook=reject_duplicate_keys)


def relative_name(value):
    if (not isinstance(value, str) or not value or "\\" in value or ":" in value or "\x00" in value or
            any(part in ("", ".", "..") or part.casefold() == ".worktrees" for part in value.split("/"))):
        raise PermissionError("Unsafe relative artifact path")
    path = PurePosixPath(value)
    if path.is_absolute() or path.as_posix() != value:
        raise PermissionError("Absolute or noncanonical artifact path")
    for part in path.parts:
        if (part.rstrip(" .") != part or any(ord(character) < 32 or character in '<>"|?*' for character in part) or
                re.fullmatch(r"(?:CON|PRN|AUX|NUL|COM[1-9¹²³]|LPT[1-9¹²³])(?:\..*)?", part, re.I)):
            raise PermissionError("Artifact has an unsafe Windows filename alias")
    return value


def _is_link(path):
    info = path.lstat()
    return stat.S_ISLNK(info.st_mode) or bool(getattr(info, "st_file_attributes", 0) & 0x400)


def extended_path(path):
    """Use Windows extended paths without resolving any link or junction first."""
    value = os.path.abspath(os.fspath(path))
    if os.name == "nt" and not value.startswith("\\\\?\\"):
        value = "\\\\?\\UNC\\" + value[2:] if value.startswith("\\\\") else "\\\\?\\" + value
    return Path(value)


def display_path(path):
    value = str(path)
    if value.startswith("\\\\?\\UNC\\"):
        value = "\\\\" + value[8:]
    elif value.startswith("\\\\?\\"):
        value = value[4:]
    return Path(value)


def no_link_ancestors(path):
    path = extended_path(path)
    for candidate in (path, *path.parents):
        try:
            if _is_link(candidate) or (hasattr(candidate, "is_junction") and candidate.is_junction()):
                raise PermissionError("Links and directory junctions are forbidden")
        except (FileNotFoundError, NotADirectoryError):
            pass
        if any(part.casefold() == ".worktrees" for part in candidate.parts):
            raise PermissionError("Worktree paths are forbidden")
    return path


def safe_path(root, name, exists=True):
    relative_name(name)
    root = no_link_ancestors(root).resolve(strict=True)
    target = no_link_ancestors(root / name)
    if not target.resolve(strict=exists).is_relative_to(root):
        raise PermissionError("Artifact path escaped its registered root")
    if exists and not stat.S_ISREG(target.stat().st_mode):
        raise PermissionError("Artifact is not a regular file")
    return target


def registered_root_name(value):
    """Validate a registered POSIX run name without accessing remote files."""
    value = str(value)
    prefix = REMOTE_PARENT.rstrip("/") + "/"
    if not value.startswith(prefix) or not re.fullmatch(r"[A-Za-z0-9_-]{1,120}", value[len(prefix):]):
        raise PermissionError("Only one registered eight-basin run directory may be read")
    return value


def remote_root(value):
    value = registered_root_name(value)
    path = no_link_ancestors(value)
    if display_path(path.resolve(strict=True)).as_posix() != value or not path.is_dir():
        raise PermissionError("Remote run path is not canonical")
    return display_path(path)


def file_stat(path):
    info = path.stat()
    return {"bytes": info.st_size, "mtime_ns": info.st_mtime_ns, "ctime_ns": info.st_ctime_ns,
            "device": info.st_dev, "inode": info.st_ino}


def read_bounded(root, name):
    path = safe_path(root, name)
    before = file_stat(path)
    if before["bytes"] > MAX_METADATA:
        raise ValueError("Metadata exceeds the bounded read limit")
    value = path.read_bytes()
    if file_stat(safe_path(root, name)) != before:
        raise RuntimeError("Metadata changed during its bounded read")
    return value


def read_metadata(root, name, expected_sha256=None):
    raw = read_bounded(root, name)
    if expected_sha256 is not None and digest(raw) != expected_sha256:
        raise ValueError("Bounded metadata differs from its existing original SHA256")
    return parse_json(raw)


def accounting(job_id):
    text = subprocess.check_output(["sacct", "-X", "-n", "-P", "-j", str(job_id),
                                   "--format=JobID,State,ExitCode,ElapsedRaw,End"], text=True)
    lines = [line for line in text.splitlines() if line.strip()]
    if len(lines) != 1:
        raise RuntimeError("One unambiguous final scheduler record is required")
    fields = lines[0].split("|")
    if fields[0] != str(job_id) or len(fields) < 5:
        raise PermissionError("Scheduler record belongs to another job")
    record = {"job_id": job_id, "state": fields[1], "exit_code": fields[2],
              "elapsed_seconds": int(fields[3]), "end": fields[4], "raw": lines[0]}
    if fields[1].split()[0] not in {"COMPLETED", "FAILED", "CANCELLED", "TIMEOUT", "OUT_OF_MEMORY", "NODE_FAIL", "PREEMPTED"}:
        raise PermissionError("Results cannot be inventoried while the job is still active")
    return record


def source_bindings(root):
    """Collect existing expected hashes; do not recompute result files on login."""
    bindings = {}

    def add(name, identity, evidence):
        relative_name(name)
        if not isinstance(identity, str) or not HEX64.fullmatch(identity):
            raise ValueError("An existing artifact hash is malformed")
        if name in bindings and bindings[name]["sha256"] != identity:
            raise RuntimeError("Existing runtime bindings disagree")
        bindings[name] = {"sha256": identity, "evidence": evidence}

    manifest = root / "payload/manifest.sha256"
    if manifest.exists():
        for line in read_bounded(root, "payload/manifest.sha256").decode("utf-8").splitlines():
            fields = line.split(maxsplit=1)
            if len(fields) != 2:
                raise ValueError("Malformed frozen payload hash manifest")
            add("payload/" + fields[1].lstrip("*"), fields[0], "payload/manifest.sha256")
    lock_name = "runtime/locked/global_selection_locked.json"
    if (root / lock_name).exists():
        lock = read_metadata(root, lock_name)
        for item in lock["selections"]:
            if item["training_root"] != (root / "runtime/training").as_posix():
                raise PermissionError("Selection artifact root differs from the registered run")
            name = "runtime/training/" + relative_name(item["selection_file"])
            add(name, item["selection_sha256"], lock_name)
            selection = read_metadata(root, name, expected_sha256=item["selection_sha256"])
            if selection["training_root"] != (root / "runtime/training").as_posix():
                raise PermissionError("Selection metadata names a different training root")
            add("runtime/training/" + relative_name(selection["input_gate"]),
                selection["input_gate_sha256"], name)
            for fitted in selection["selected"]:
                add("runtime/training/" + relative_name(fitted["checkpoint"]),
                    fitted["checkpoint_sha256"], name)
    preflight_name = "runtime/preflight/preflight_gate.json"
    if (root / preflight_name).exists():
        for item in read_metadata(root, preflight_name)["inputs"]:
            add("runtime/preflight/" + relative_name(item["input_gate"]),
                item["input_gate_sha256"], preflight_name)
    audit_name = "runtime/scoring/independent_reconstruction.json"
    if (root / audit_name).exists():
        for basin, item in read_metadata(root, audit_name)["details"].items():
            if basin not in BASINS:
                raise PermissionError("Unexpected basin in reconstruction evidence")
            add(f"runtime/scoring/basins/{basin}/score_observations.csv", item["observations_sha256"], audit_name)
    return bindings



def scratch_exclusion(root, technical_sha256):
    """Describe test-only links without following them or reading fixture bytes."""
    scratch = root / SCRATCH_RELATIVE
    candidate = root
    for part in SCRATCH_RELATIVE.split("/"):
        candidate = candidate / part
        try:
            info = candidate.lstat()
        except FileNotFoundError:
            return None
        if _is_link(candidate) or not stat.S_ISDIR(info.st_mode):
            raise PermissionError("The scratch root or its ancestor is linked or non-directory")
    raw = read_bounded(root, "runtime/synthetic/technical_gate.json")
    if not re.fullmatch(r"[0-9a-f]{64}", technical_sha256 or "") or digest(raw) != technical_sha256:
        raise PermissionError("Scratch exclusion lacks its fixed successful technical certificate")
    gate = parse_json(raw)
    command = gate.get("command")
    if (gate.get("success") is not True or gate.get("kind") != "synthetic" or
            not isinstance(command, list) or command.count("--basetemp") != 1):
        raise PermissionError("Only the successful synthetic test certificate may authorize scratch omission")
    position = command.index("--basetemp")
    if position + 1 >= len(command) or not isinstance(command[position + 1], str):
        raise PermissionError("Missing certified pytest scratch path")
    pytest_root = command[position + 1]
    prefix = scratch.as_posix() + "/"
    if (not pytest_root.startswith(prefix) or PurePosixPath(pytest_root).as_posix() != pytest_root or
            not re.fullmatch(r"eight_[0-9a-f]{32}/pytest", pytest_root[len(prefix):])):
        raise PermissionError("Synthetic scratch path is outside the exact certified subtree")
    before = file_stat(scratch)
    links, entries = [], 0
    for current, directories, files in os.walk(scratch, topdown=True, followlinks=False):
        for name in directories + files:
            path = Path(current) / name
            entries += 1
            if entries > 50000:
                raise RuntimeError("Synthetic scratch metadata limit exceeded")
            if _is_link(path):
                if len(links) >= 256:
                    raise RuntimeError("Synthetic scratch link metadata limit exceeded")
                links.append({"path": display_path(path).relative_to(root).as_posix(),
                              "target": os.readlink(path), "lstat_mode": path.lstat().st_mode})
        directories[:] = [name for name in directories if not _is_link(Path(current) / name)]
    if file_stat(scratch) != before:
        raise RuntimeError("Synthetic scratch root changed during metadata enumeration")
    return {"path": SCRATCH_RELATIVE, "reason": "Certified synthetic pytest scratch; no fixture bytes recovered",
            "technical_gate_sha256": technical_sha256, "pytest_basetemp": pytest_root,
            "stat": before, "entries_metadata_only": entries, "links": links, "links_followed": False}

def artifact_members(root, technical_sha256):
    exclusion = scratch_exclusion(root, technical_sha256)
    names = {"submission_receipt.txt"}
    scratch = root / SCRATCH_RELATIVE
    for directory in ("runtime", "logs"):
        base = no_link_ancestors(root / directory)
        if not base.exists():
            continue
        for current, directories, files in os.walk(base, topdown=True, followlinks=False):
            retained = []
            for name in directories:
                path = Path(current) / name
                if display_path(path) == scratch and exclusion is not None:
                    continue
                if _is_link(path):
                    raise PermissionError("Result inventory contains a linked directory: " + str(display_path(path).relative_to(root)))
                retained.append(name)
            directories[:] = retained
            for name in files:
                path = Path(current) / name
                if _is_link(path):
                    raise PermissionError("Result inventory contains a linked file: " + str(display_path(path).relative_to(root)))
                if path.is_file():
                    names.add(display_path(path).relative_to(root).as_posix())
    return names, [exclusion] if exclusion is not None else []

def inventory(root, job_id, job_record=None, allow_incomplete=False):
    root = remote_root(root)
    if type(job_id) is not int or job_id <= 0:
        raise ValueError("An explicit positive job identifier is required")
    job = accounting(job_id) if job_record is None else job_record
    if job["job_id"] != job_id or job["state"].split()[0] not in {
            "COMPLETED", "FAILED", "CANCELLED", "TIMEOUT", "OUT_OF_MEMORY", "NODE_FAIL", "PREEMPTED"}:
        raise PermissionError("The job has no matching terminal state")
    receipt = read_bounded(root, "submission_receipt.txt").decode("utf-8").strip()
    if receipt not in (str(job_id), "Submitted batch job " + str(job_id)):
        raise PermissionError("Submission receipt does not bind this job")
    finished = (root / "runtime/job_complete.json").is_file() and read_metadata(
        root, "runtime/job_complete.json").get("success") is True
    if not finished and not allow_incomplete:
        raise PermissionError("The full job did not complete; use explicit incomplete preservation")
    names, exclusions = artifact_members(root, EXCLUSION_TECHNICAL_GATE_SHA256)
    controls = ("submission.slurm", "offline_acceptance.json", "payload/bundle_manifest.json",
                "payload/manifest.sha256", "payload/source_manifest.json", "payload/records/roster_locked.json",
                "payload/records/budget_snapshot.json",
                "payload/code/src/precip_input_assimilation/configs/dynamic_filter_eight_basins_v01.json",
                "payload/code/docs/plans/2026-10-03-precip-dynamic-neural-filter-eight-basin-plan-v0.2.md",
                "payload/code/docs/plans/2026-10-03-precip-dynamic-neural-filter-eight-basin-roster-v0.1.json")
    names.update(name for name in controls if (root / name).exists())
    bindings = source_bindings(root)
    files = {name: dict(file_stat(safe_path(root, name)), source_binding=bindings.get(name))
             for name in sorted(names)}
    counts = {"predictions": sum(name.startswith("runtime/scoring/basins/") and name.endswith("/predictions.csv") for name in files),
              "rain_ledgers": sum(name.startswith("runtime/scoring/basins/") and name.endswith("/rain_versions.csv") for name in files),
              "selected_checkpoints": sum(name.startswith("runtime/training/basins/") and name.endswith("/selected.pt") for name in files)}
    full = finished and job["state"] == "COMPLETED" and job["exit_code"] == "0:0" and counts == {
        "predictions": 88, "rain_ledgers": 48, "selected_checkpoints": 72}
    if not full and not allow_incomplete:
        raise RuntimeError("The required 88 trajectories, 48 rain ledgers and 72 selections are incomplete")
    value = {"schema": SCHEMA, "kind": "inventory", "root": root.as_posix(), "job": job,
             "expected_file_counts_complete": full, "science_verified": False, "counts": counts, "files": files,
             "unbound_files": [name for name, item in files.items() if item["source_binding"] is None],
             "binding_limit": "Stage manifests do not bind all result-file SHA256 values. Unbound files have transport integrity only and require independent scientific reconstruction.",
             "local_path_mapping": {"logical_training_root": (root / "runtime/training").as_posix(),
                                    "local_training_root_relative": "runtime/training"},
             "excluded_subtrees": exclusions}
    value["inventory_sha256"] = digest(canonical(value))
    if any(file_stat(safe_path(root, name)) != {key: info[key] for key in (
            "bytes", "mtime_ns", "ctime_ns", "device", "inode")} for name, info in files.items()):
        raise RuntimeError("Source stat changed during inventory; preserve evidence and stop")
    return value


def validate_inventory(value):
    if value.get("schema") != SCHEMA or value.get("kind") != "inventory":
        raise ValueError("Unsupported inventory")
    registered_root_name(value["root"])
    if type(value["job"]["job_id"]) is not int or value["job"]["job_id"] <= 0:
        raise ValueError("Inventory has an invalid job identifier")
    original = dict(value)
    identity = original.pop("inventory_sha256")
    if not HEX64.fullmatch(identity) or digest(canonical(original)) != identity:
        raise ValueError("Inventory identity differs")
    seen = set()
    for name, item in value["files"].items():
        relative_name(name)
        if (name.casefold() in seen or any(type(item[key]) is not int or item[key] < 0 for key in (
                "bytes", "mtime_ns", "ctime_ns", "device", "inode"))):
            raise ValueError("Ambiguous file names or invalid byte lengths")
        seen.add(name.casefold())
        if item["source_binding"] is not None and not HEX64.fullmatch(item["source_binding"]["sha256"]):
            raise ValueError("Malformed original source binding")
    return value


def requests_for(value):
    validate_inventory(value)
    batches, batch, size = [], [], 0

    def finish():
        nonlocal batch, size
        if batch:
            batches.append(batch)
            batch, size = [], 0

    for name, info in value["files"].items():
        count = info["bytes"]
        if count > MAX_CHUNK:
            finish()
            for offset in range(0, count, MAX_CHUNK):
                batches.append([{"name": name, "offset": offset, "length": min(MAX_CHUNK, count - offset), "stat": info}])
        else:
            if size + count > MAX_CHUNK or len(batch) >= MAX_BATCH_FILES:
                finish()
            batch.append({"name": name, "offset": 0, "length": count, "stat": info})
            size += count
    finish()
    result = []
    for index, members in enumerate(batches):
        request = {"schema": SCHEMA, "root": value["root"], "job_id": value["job"]["job_id"],
                   "inventory_sha256": value["inventory_sha256"], "index": index, "members": members}
        request["request_sha256"] = digest(canonical(request))
        result.append(request)
    return result


def validate_request(request):
    original = dict(request)
    identity = original.pop("request_sha256")
    if request.get("schema") != SCHEMA or digest(canonical(original)) != identity:
        raise ValueError("Fragment request identity differs")
    registered_root_name(request["root"])
    if type(request["job_id"]) is not int or request["job_id"] <= 0 or not HEX64.fullmatch(request["inventory_sha256"]):
        raise ValueError("Fragment request has an invalid run/inventory identity")
    members, found = request["members"], set()
    if not 1 <= len(members) <= MAX_BATCH_FILES or sum(item["length"] for item in members) > MAX_CHUNK:
        raise ValueError("Fragment request exceeds its bounded byte/file limit")
    for item in members:
        relative_name(item["name"])
        offset, length, count = item["offset"], item["length"], item["stat"]["bytes"]
        if (type(offset) is not int or type(length) is not int or type(count) is not int or count < 0 or
                offset < 0 or length < 0 or offset % MAX_CHUNK or offset > count or
                length != min(MAX_CHUNK, count - offset) or (count > 0 and length == 0)):
            raise ValueError("Illegal fragment offset or length")
        key = (item["name"].casefold(), offset)
        if key in found:
            raise ValueError("Duplicated fragment")
        found.add(key)
    return request


def read_fragments(request, inventory_value):
    # A self-signed request alone cannot authorize a path. Reconstruct it from
    # the entire fixed inventory and compare before any result byte is read.
    expected_requests = requests_for(inventory_value)
    index = request.get("index")
    if type(index) is not int or not 0 <= index < len(expected_requests) or request != expected_requests[index]:
        raise PermissionError("Fragment request differs from its complete fixed inventory")
    validate_request(request)
    root = remote_root(request["root"])
    receipt = read_bounded(root, "submission_receipt.txt").decode("utf-8").strip()
    if receipt not in (str(request["job_id"]), "Submitted batch job " + str(request["job_id"])):
        raise PermissionError("Fragment request has a different job")
    result = []
    for item in request["members"]:
        path = safe_path(root, item["name"])
        expected = {key: item["stat"][key] for key in ("bytes", "mtime_ns", "ctime_ns", "device", "inode")}
        if file_stat(path) != expected:
            raise RuntimeError("Source stat changed; preserve received pieces and stop")
        descriptor = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_BINARY", 0))
        with os.fdopen(descriptor, "rb") as handle:
            opened = os.fstat(handle.fileno())
            if (opened.st_dev, opened.st_ino, opened.st_size) != (expected["device"], expected["inode"], expected["bytes"]):
                raise RuntimeError("Opened file identity differs from the frozen inventory")
            handle.seek(item["offset"])
            raw = handle.read(item["length"])
        if len(raw) != item["length"] or file_stat(safe_path(root, item["name"])) != expected:
            raise RuntimeError("Source changed during a fragment read")
        result.append(dict(item, chunk_sha256=digest(raw), base64=base64.b64encode(raw).decode("ascii")))
    return {"schema": SCHEMA, "kind": "fragments", "request_sha256": request["request_sha256"],
            "inventory_sha256": request["inventory_sha256"], "root": request["root"], "job_id": request["job_id"],
            "index": request["index"], "members": result}


def _emit(value):
    print(BEGIN)
    print(canonical(value).decode())
    print(END)


def remote_command(mode, request, python):
    if (mode not in ("inventory-remote", "fragments-remote") or not re.fullmatch(r"/[A-Za-z0-9_./-]+", python) or
            PurePosixPath(python).as_posix() != python or any(part in ("", ".", "..") for part in python.split("/")[1:])):
        raise ValueError("Explicit canonical remote Python and read-only command mode are required")
    encoded = base64.b64encode(canonical(request)).decode("ascii")
    source = Path(__file__).read_text(encoding="utf-8")
    # Requests may contain hundreds of long paths. Keep them in stdin rather
    # than one argv element, which can exceed Linux's per-argument size limit.
    preamble = "import sys\nsys.argv = " + repr(["eight_basin_transport", mode, "--request", encoded]) + "\n"
    return "#!/usr/bin/env bash\nset -euo pipefail\n" + shlex.join([
        python, "-B", "-"]) + " <<'EIGHT_TRANSPORT_PY'\n" + preamble + source + "\nEIGHT_TRANSPORT_PY\n"


def immutable_bytes(path, raw):
    path = no_link_ancestors(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        if not path.is_file() or path.read_bytes() != raw:
            raise FileExistsError("Existing recovery bytes differ; refusing overwrite")
        return
    with path.open("xb") as handle:
        handle.write(raw)


def json_write(path, value):
    immutable_bytes(path, canonical(value) + b"\n")


def extract_receipt(path, sequence, blob_sha, commit):
    if not HEX40.fullmatch(blob_sha) or not HEX40.fullmatch(commit) or type(sequence) is not int or sequence <= 0:
        raise ValueError("Pinned receipt Git object, commit and sequence are required")
    path = no_link_ancestors(path)
    if not path.is_file() or path.stat().st_size > 12 * 1024 * 1024:
        raise ValueError("Receipt exceeds the bounded transport size")
    raw = path.read_bytes()
    if hashlib.sha1(b"blob " + str(len(raw)).encode() + b"\0" + raw).hexdigest() != blob_sha:
        raise ValueError("Receipt Git blob identity differs")
    text = raw.decode("utf-8")
    if re.findall(r"^### channel=([^ ]+) seq=([0-9]+)\r?$", text, re.M) != [(CHANNEL, str(sequence))]:
        raise ValueError("Receipt channel or sequence differs")
    if not re.search(r"### ---------- end ----------\r?\n### exit_code=0\r?\n### finished=[^\r\n]+\r?\n?\Z", text):
        raise ValueError("Receipt has no complete successful footer")
    lines = text.splitlines()
    if lines.count(BEGIN) != 1 or lines.count(END) != 1 or lines.index(END) != lines.index(BEGIN) + 2:
        raise ValueError("Transport envelope is missing, duplicated or truncated")
    value = parse_json(lines[lines.index(BEGIN) + 1])
    return value, {"sequence": sequence, "mailbox_commit": commit, "git_blob_sha1": blob_sha,
                   "receipt_sha256": digest(raw), "bytes": len(raw),
                   "commit_binding": "Caller supplies the commit-pinned blob identity; this offline tool verifies blob bytes, not Git tree membership."}


def load_manifest(path):
    wrapper = parse_json(no_link_ancestors(path).read_bytes())
    value = validate_inventory(wrapper["inventory"])
    provenance = wrapper["receipt_identity"]
    receipt = no_link_ancestors(Path(path).with_suffix(".receipt.txt"))
    actual, verified = extract_receipt(receipt, provenance["sequence"], provenance["git_blob_sha1"], provenance["mailbox_commit"])
    if actual != value or verified != provenance:
        raise PermissionError("Inventory manifest differs from its preserved pinned Git receipt")
    return wrapper


def load_inventory(path):
    return load_manifest(path)["inventory"]


def accept_inventory(receipt, output, sequence, blob_sha, commit, expected_root, job_id):
    value, provenance = extract_receipt(receipt, sequence, blob_sha, commit)
    validate_inventory(value)
    registered_root_name(expected_root)
    if value["root"] != expected_root or value["job"]["job_id"] != job_id:
        raise PermissionError("Inventory belongs to another registered run/job")
    immutable_bytes(Path(output).with_suffix(".receipt.txt"), no_link_ancestors(receipt).read_bytes())
    json_write(output, {"inventory": value, "receipt_identity": provenance})
    return value


def accept_fragments(receipt, value, storage, sequence, blob_sha, commit):
    envelope, provenance = extract_receipt(receipt, sequence, blob_sha, commit)
    requests = requests_for(value)
    index = envelope.get("index")
    if type(index) is not int or not 0 <= index < len(requests):
        raise ValueError("Receipt has an unknown fragment request index")
    request = requests[index]
    for key in ("root", "job_id", "inventory_sha256", "request_sha256"):
        if envelope.get(key) != request[key]:
            raise PermissionError("Fragment receipt differs from its fixed inventory/request")
    if (envelope.get("schema") != SCHEMA or envelope.get("kind") != "fragments" or
            len(envelope["members"]) != len(request["members"])):
        raise ValueError("Fragment receipt member count differs")
    decoded = []
    for item, expected in zip(envelope["members"], request["members"], strict=True):
        if any(item[key] != expected[key] for key in ("name", "offset", "length", "stat")):
            raise ValueError("Duplicated, reordered or different fragment member")
        raw = base64.b64decode(item["base64"], validate=True)
        if len(raw) != item["length"] or digest(raw) != item["chunk_sha256"]:
            raise ValueError("Fragment bytes or SHA256 differs")
        decoded.append((item, raw))
    storage = no_link_ancestors(storage)
    storage.mkdir(parents=True, exist_ok=True)
    json_write(storage / "inventory.json", value)
    members = [{key: item[key] for key in ("name", "offset", "length", "stat", "chunk_sha256")} for item, _ in decoded]
    # Fix bytes independently of the receipt commit, allowing a byte-identical
    # retransmission while preserving every caller-pinned provenance record.
    json_write(storage / "requests" / f"{index:06d}.json", {"request_sha256": request["request_sha256"], "members": members})
    immutable_bytes(storage / "receipt_blobs" / f"{blob_sha}.txt", no_link_ancestors(receipt).read_bytes())
    for item, raw in decoded:
        stem = storage / "pieces" / digest(item["name"].encode()) / f"{item['offset']:016d}"
        immutable_bytes(stem.with_suffix(".bin"), raw)
        json_write(stem.with_suffix(".json"), {key: item[key] for key in ("name", "offset", "length", "stat", "chunk_sha256")})
    json_write(storage / "receipts" / f"{index:06d}_{commit}_{sequence}_{blob_sha}.json", provenance)
    return {"request_index": index, "accepted": len(decoded), "receipt_identity": provenance}


def finalize(value, storage, output, manifest_path=None):
    validate_inventory(value)
    anchor = None
    if manifest_path is not None:
        manifest = load_manifest(manifest_path)
        if manifest["inventory"] != value:
            raise PermissionError("Recovery inventory differs from its externally supplied pinned manifest")
        anchor = manifest["receipt_identity"]
    storage, output = no_link_ancestors(storage), no_link_ancestors(output)
    resolved_storage, resolved_output = storage.resolve(strict=True), output.resolve()
    if resolved_output.is_relative_to(resolved_storage) or resolved_storage.is_relative_to(resolved_output):
        raise PermissionError("Piece storage and reconstructed output must have separate roots")
    no_link_ancestors(storage / "inventory.json")
    if parse_json((storage / "inventory.json").read_bytes()) != value:
        raise PermissionError("Stored pieces belong to another inventory")
    fragments = {}
    for request in requests_for(value):
        index = request["index"]
        accepted = parse_json(safe_path(storage, f"requests/{index:06d}.json").read_bytes())
        if accepted["request_sha256"] != request["request_sha256"] or len(accepted["members"]) != len(request["members"]):
            raise ValueError("Accepted request differs from the fixed inventory")
        receipts = no_link_ancestors(storage / "receipts")
        proofs = sorted(receipts.glob(f"{index:06d}_*.json"))
        if not proofs:
            raise ValueError("Accepted fragments have no preserved pinned receipt proof")
        for proof in proofs:
            evidence = parse_json(safe_path(storage, "receipts/" + proof.name).read_bytes())
            name = f"{index:06d}_{evidence['mailbox_commit']}_{evidence['sequence']}_{evidence['git_blob_sha1']}.json"
            if proof.name != name:
                raise ValueError("Receipt proof file and pinned identity differ")
            raw_receipt = safe_path(storage, f"receipt_blobs/{evidence['git_blob_sha1']}.txt")
            envelope, verified = extract_receipt(raw_receipt, evidence["sequence"], evidence["git_blob_sha1"], evidence["mailbox_commit"])
            if verified != evidence or any(envelope.get(key) != request[key] for key in (
                    "schema", "root", "job_id", "inventory_sha256", "request_sha256", "index")):
                raise ValueError("Preserved receipt proof differs from the fixed request")
            receipt_members = [{key: item[key] for key in ("name", "offset", "length", "stat", "chunk_sha256")}
                               for item in envelope["members"]]
            if envelope.get("kind") != "fragments" or receipt_members != accepted["members"]:
                raise ValueError("Accepted fragment hashes differ from preserved receipt bytes")
        for item, stored in zip(request["members"], accepted["members"], strict=True):
            if any(stored[key] != item[key] for key in ("name", "offset", "length", "stat")):
                raise ValueError("Accepted fragment metadata differs from inventory")
            fragments.setdefault(item["name"], []).append(stored)
    piece_root = no_link_ancestors(storage / "pieces")
    if {path.name for path in piece_root.iterdir()} != {digest(name.encode()) for name in fragments}:
        raise ValueError("Missing or extra artifact piece directories")
    # Check the entire fixed file population for missing/extra pieces before producing outputs.
    for name, members in fragments.items():
        directory = safe_path(storage, "pieces/" + digest(name.encode()) + "/" + f"{members[0]['offset']:016d}.json").parent
        expected_names = {f"{item['offset']:016d}" + suffix for item in members for suffix in (".json", ".bin")}
        if {path.name for path in directory.iterdir()} != expected_names:
            raise ValueError("Missing or duplicated/extra fragment files")
        for item in members:
            record = parse_json(safe_path(storage, f"pieces/{digest(name.encode())}/{item['offset']:016d}.json").read_bytes())
            if any(record[key] != item[key] for key in ("name", "offset", "length", "stat", "chunk_sha256")):
                raise ValueError("Stored fragment metadata differs from its inventory")
            piece = safe_path(storage, f"pieces/{digest(name.encode())}/{item['offset']:016d}.bin")
            raw = piece.read_bytes()
            if len(raw) != item["length"] or digest(raw) != record["chunk_sha256"]:
                raise ValueError("Stored fragment was changed after acceptance")
    output.mkdir(parents=True, exist_ok=True)
    recovered = {}
    for name, members in fragments.items():
        target = safe_path(output, name, exists=False)
        accumulated = hashlib.sha256()
        for item in members:
            accumulated.update(safe_path(storage, f"pieces/{digest(name.encode())}/{item['offset']:016d}.bin").read_bytes())
        actual = accumulated.hexdigest()
        binding = value["files"][name]["source_binding"]
        if binding is not None and actual != binding["sha256"]:
            raise ValueError("Recovered file differs from its existing original runtime/payload SHA256")
        if target.exists():
            existing = hashlib.sha256()
            with target.open("rb") as handle:
                for chunk in iter(lambda: handle.read(MAX_CHUNK), b""):
                    existing.update(chunk)
            if target.stat().st_size != value["files"][name]["bytes"] or existing.hexdigest() != actual:
                raise FileExistsError("Existing recovered file differs; no overwrite is permitted")
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            with target.open("xb") as handle:
                for item in members:
                    handle.write(safe_path(storage, f"pieces/{digest(name.encode())}/{item['offset']:016d}.bin").read_bytes())
        recovered[name] = {"bytes": value["files"][name]["bytes"], "reassembled_sha256": actual,
                           "original_sha256_verified": binding is not None,
                           "scientific_reconstruction_required": binding is None}
    locks = {}
    for name, item in recovered.items():
        if name.endswith("_locked.json") or name.endswith("_lock.json"):
            binding = value["files"][name]["source_binding"]
            locks[name] = {"expected_sha256": binding["sha256"] if binding else None,
                           "actual_sha256": item["reassembled_sha256"], "original_digest_evidence": binding,
                           "pinned_inventory_receipt": anchor,
                           "status": ("verified_against_existing_digest_and_pinned_inventory_receipt" if binding and anchor else
                                      "digest_matches_but_external_anchor_unchecked" if binding else "original_digest_unavailable")}
    record = {"schema": SCHEMA, "inventory_sha256": value["inventory_sha256"], "files": recovered,
              "source_binding_limit": value["binding_limit"], "path_mapping": value["local_path_mapping"],
              "lock_integrity": locks, "pinned_inventory_receipt": anchor, "science_verified": False}
    json_write(output / "transport_reconstruction.json", record)
    return record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_subparsers(dest="mode", required=True)
    make = modes.add_parser("command-inventory")
    make.add_argument("--root", required=True)
    make.add_argument("--job-id", required=True, type=int)
    make.add_argument("--python", required=True)
    make.add_argument("--allow-incomplete", action="store_true")
    make.add_argument("--output", required=True, type=Path)
    plan = modes.add_parser("commands-fragments")
    plan.add_argument("--manifest", required=True, type=Path)
    plan.add_argument("--python", required=True)
    plan.add_argument("--output", required=True, type=Path)
    for mode in ("accept-inventory", "accept-fragments"):
        accept = modes.add_parser(mode)
        accept.add_argument("--receipt", required=True, type=Path)
        accept.add_argument("--sequence", required=True, type=int)
        accept.add_argument("--blob-sha1", required=True)
        accept.add_argument("--commit", required=True)
        if mode == "accept-inventory":
            accept.add_argument("--root", required=True)
            accept.add_argument("--job-id", required=True, type=int)
            accept.add_argument("--output", required=True, type=Path)
        else:
            accept.add_argument("--manifest", required=True, type=Path)
            accept.add_argument("--storage", required=True, type=Path)
    finish = modes.add_parser("finalize")
    finish.add_argument("--manifest", required=True, type=Path)
    finish.add_argument("--storage", required=True, type=Path)
    finish.add_argument("--output", required=True, type=Path)
    for mode in ("inventory-remote", "fragments-remote"):
        remote = modes.add_parser(mode, help=argparse.SUPPRESS)
        remote.add_argument("--request", required=True)
    args = parser.parse_args()
    if args.mode == "command-inventory":
        # Pure command generation: no remote input/path access.
        registered_root_name(args.root)
        if args.job_id <= 0:
            raise ValueError("An explicit positive job identifier is required")
        request = {"root": args.root, "job_id": args.job_id, "allow_incomplete": args.allow_incomplete}
        immutable_bytes(args.output, remote_command("inventory-remote", request, args.python).encode())
    elif args.mode == "commands-fragments":
        value = load_inventory(args.manifest)
        output = no_link_ancestors(args.output)
        output.mkdir(parents=True, exist_ok=False)
        requests = requests_for(value)
        for request in requests:
            immutable_bytes(output / f"command_{request['index']:06d}.sh", remote_command("fragments-remote",
                            {"inventory": value, "request": request}, args.python).encode())
        json_write(output / "plan.json", {"inventory_sha256": value["inventory_sha256"], "requests": requests})
        print(json.dumps({"requests": len(requests), "unbound_file_count": len(value["unbound_files"])}))
    elif args.mode == "accept-inventory":
        accept_inventory(args.receipt, args.output, args.sequence, args.blob_sha1, args.commit, args.root, args.job_id)
    elif args.mode == "accept-fragments":
        print(json.dumps(accept_fragments(args.receipt, load_inventory(args.manifest), args.storage,
                                         args.sequence, args.blob_sha1, args.commit)))
    elif args.mode == "finalize":
        result = finalize(load_inventory(args.manifest), args.storage, args.output, manifest_path=args.manifest)
        print(json.dumps({"files": len(result["files"]), "science_verified": False}))
    else:
        request = parse_json(base64.b64decode(args.request, validate=True))
        if args.mode == "inventory-remote":
            _emit(inventory(request["root"], request["job_id"], allow_incomplete=request["allow_incomplete"]))
        else:
            _emit(read_fragments(request["request"], request["inventory"]))



main()
EIGHT_INVENTORY_V02

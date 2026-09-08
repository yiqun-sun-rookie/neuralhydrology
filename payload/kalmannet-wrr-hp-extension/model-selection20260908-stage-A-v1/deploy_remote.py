"""Fail-closed, one-attempt stage-A deployment. Importing does not touch disk."""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
import platform
import re
import subprocess
import tarfile
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath

import launch_once as guard
from study_config import REMOTE_FAMILY_ROOT, make_combos

INPUT_HASHES = {
    "AUTHORIZATION.json": "2e6b6353f9019c59deb024d2e870154cf07bdcbcf101d30d179150bde83dc78e",
    "AUTHORIZED_PROTOCOL.md": "0707cad4661f83d03c71e483184d91f197b7b9ac29015c077e6075aad5dc6b06",
    "REMOTE_BASELINE.json": "6314f746fce9f31d55687b35858736c4013bd5369e5b6a538bea155bd1b7c5ce",
    "STAGE_A_MANIFEST.json": "d920b7a629ba97d6a2edd0ec0fd6d876142888d0d504af631a86c8898b8ae291",
}
PROTECTED_ROOTS = (
    "/data1/home/sunyiq/kalmannet_wrr_hp_extension_20260902",
    "/data1/home/sunyiq/kalmannet_wrr_finalist_replication_20260907",
)
DATA_ROOT = "/data1/home/sunyiq/knet_project/data/processed/high_flow_aug"
DATA_NAMES = {"train": "train_win800_19990101_01-20070527_03.pt", "val": "val_win800_20070527_04-20090314_13.pt"}
CACHE_NAMES = ("MPLCONFIGDIR", "TORCH_HOME", "XDG_CACHE_HOME")
ACTIVATION = "source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh\nconda activate knet_clean || { echo CONDA_FAILED; exit 1; }\n"


def remote_path(value):
    """Filesystem seam for isolated tests; production has no root override option."""
    return Path(value)


def digest(data):
    return hashlib.sha256(data).hexdigest()


sha256 = guard.sha256_path


def safe_relative(name):
    if not isinstance(name, str) or not name or "\\" in name or ":" in name or name.startswith("/") or any(part in ("", ".", "..") for part in name.split("/")):
        raise ValueError(f"Unsafe relative path: {name!r}")
    return PurePosixPath(name)


def absolute_name(name):
    if not isinstance(name, str) or not name.startswith("/"):
        raise ValueError("Expected absolute remote path")
    safe_relative(name[1:])
    return PurePosixPath(name)


def ordinary(path, root):
    if path.is_symlink() or not path.is_file() or not path.resolve().is_relative_to(root.resolve()):
        raise ValueError(f"Unsafe or non-regular file: {path}")
    for parent in path.parents:
        if parent == root:
            break
        if parent.is_symlink():
            raise ValueError(f"Symlink parent: {parent}")
    if root.is_symlink() or root.resolve() != root.absolute():
        raise ValueError(f"Unsafe root: {root}")


def write_new(path, data):
    with path.open("xb") as stream:
        stream.write(data)
        stream.flush()
        os.fsync(stream.fileno())
    sync_directory(path.parent)


def sync_directory(path):
    """Persist directory entries before an irreversible scheduler call on Linux."""
    if os.name == "posix":
        descriptor = os.open(path, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(descriptor)
        finally:
            os.close(descriptor)


def write_json(path, value):
    write_new(path, (json.dumps(value, indent=2, sort_keys=True) + "\n").encode())


def now():
    return datetime.now(timezone.utc).isoformat()


def read_archive(data, expected):
    files = {}
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as archive:
        for member in archive.getmembers():
            safe_relative(member.name)
            if not member.isfile() or member.name in files:
                raise ValueError(f"Non-regular or duplicate archive member: {member.name}")
            stream = archive.extractfile(member)
            if stream is None:
                raise ValueError("Unreadable archive member")
            files[member.name] = stream.read()
    if set(files) != set(expected):
        raise ValueError("Archive member set differs from frozen manifest")
    for name, value in files.items():
        if digest(value) != expected[name]:
            raise ValueError(f"Static archive hash mismatch: {name}")
    return files


def validate_baseline(baseline):
    required = {"probe", "new_family_root", "new_family_absent", "references", "failed_runs", "protected_files", "data", "current_environment", "source_manifests", "prior_replication_accounting", "data_tensors_loaded", "new_jobs_submitted"}
    if not required.issubset(baseline) or baseline["probe"] != "PASS" or baseline["new_family_root"] != REMOTE_FAMILY_ROOT or baseline["new_family_absent"] is not True:
        raise ValueError("Baseline admission fields mismatch")
    if baseline["data_tensors_loaded"] is not False or baseline["new_jobs_submitted"] != 0:
        raise ValueError("Baseline scope mismatch")
    if baseline["prior_replication_accounting"] != [[f"223697_{i}", "COMPLETED", "0:0"] for i in range(6)]:
        raise ValueError("Prior accounting mismatch")
    protected = baseline["protected_files"]
    if len(protected) != 252 or len(baseline["references"]) != 30 or len(baseline["failed_runs"]) != 2 or set(baseline["data"]) != {"train", "val"}:
        raise ValueError("Baseline record counts mismatch")
    for name, value in protected.items():
        path = absolute_name(name)
        if not any(path.is_relative_to(PurePosixPath(root)) for root in PROTECTED_ROOTS) or not re.fullmatch("[0-9a-f]{64}", value):
            raise ValueError("Protected path/hash outside approved contract")
    for split, row in baseline["data"].items():
        source = f"{PROTECTED_ROOTS[0]}/repo/data/processed/high_flow_aug/{DATA_NAMES[split]}"
        resolved = f"{DATA_ROOT}/{DATA_NAMES[split]}"
        if row["path"] != source or row["resolved_path"] != resolved or protected.get(source) != row["sha256"] or type(row["bytes"]) is not int or row["bytes"] <= 0:
            raise ValueError("Data identity mismatch")
    identities = set()
    for row in baseline["references"]:
        for key in ("cell", "audit", "config", "checkpoint"):
            if protected.get(row[key + "_path"]) != row[key + "_sha256"]:
                raise ValueError("Reference chain not in protected baseline")
        combo = row["combo"]
        identities.add(tuple(combo[key] for key in ("hidden_size", "num_layers", "in_out_mult", "lr", "seed")))
    if len(identities) != 30 or any(tuple(row[key] for key in ("hidden_size", "num_layers", "in_out_mult", "lr", "seed")) in identities for row in make_combos("A")):
        raise ValueError("Reference identities overlap or duplicate")
    for row in baseline["failed_runs"]:
        marker = str(PurePosixPath(row["error_path"]).with_name("FAILED"))
        if row["retry_authorized"] is not False or row["classification"] != "numeric_recovery_limit" or protected.get(row["error_path"]) != row["error_sha256"] or protected.get(marker) != row["failed_marker_sha256"]:
            raise ValueError("Failed-run evidence mismatch")
    if set(baseline["source_manifests"]) != {"extension", "replication"}:
        raise ValueError("Source manifest inventory mismatch")
    for row in baseline["source_manifests"].values():
        if protected.get(row["path"]) != row["sha256"] or row["source_count"] != 62:
            raise ValueError("Source manifest baseline mismatch")


def verify_protected(baseline):
    checked = {}
    approved_links = {row["path"]: row for row in baseline["data"].values()}
    for name, expected in baseline["protected_files"].items():
        lexical = absolute_name(name)
        roots = [root for root in PROTECTED_ROOTS if lexical.is_relative_to(PurePosixPath(root))]
        if len(roots) != 1:
            raise ValueError("Unapproved protected root")
        root, path = remote_path(roots[0]), remote_path(name)
        if name in approved_links:
            row = approved_links[name]
            target = remote_path(row["resolved_path"])
            if not path.is_symlink() or path.parent.resolve() != path.parent.absolute() or root.is_symlink() or path.resolve() != target.absolute():
                raise ValueError("Approved source data link changed")
            ordinary(target, remote_path(DATA_ROOT))
            if path.stat().st_size != row["bytes"]:
                raise ValueError("Data size mismatch")
        else:
            ordinary(path, root)
        checked[name] = sha256(path)
        if checked[name] != expected:
            raise ValueError(f"Protected SHA256 mismatch: {name}")
    return checked


def validate_payload(payload):
    values = {}
    for name, expected in INPUT_HASHES.items():
        path = payload / name
        ordinary(path, payload)
        values[name] = path.read_bytes()
        if digest(values[name]) != expected:
            raise ValueError(f"Frozen input SHA256 mismatch: {name}")
    auth = json.loads(values["AUTHORIZATION.json"])
    if auth["protocol_sha256"] != digest(values["AUTHORIZED_PROTOCOL.md"]) or auth["remote_family_root"] != REMOTE_FAMILY_ROOT or auth["new_training_runs"] != {"A": 18, "B": 21, "C": 15, "total": 54} or auth["max_concurrent_training_gpus"] != 6 or auth["per_training_wall_clock_hours"] != 24 or auth["retry_resume_cancel_delete_authorized"] is not False:
        raise ValueError("Authorization mismatch")
    manifest = json.loads(values["STAGE_A_MANIFEST.json"])
    guard.verify_manifest_contract("A", manifest)
    if manifest["remote_root"] != REMOTE_FAMILY_ROOT + "/stages/A" or manifest["held_out_test_data_included"] is not False:
        raise ValueError("Stage root or held-out-data mismatch")
    archive = payload / str(safe_relative(manifest["archive"]["relative_path"]))
    ordinary(archive, payload)
    data = archive.read_bytes()
    if len(data) != manifest["archive"]["size_bytes"] or digest(data) != manifest["archive"]["sha256"]:
        raise ValueError("Archive identity mismatch")
    files = read_archive(data, manifest["static_files"])
    script = files["hpc_array.slurm"].decode()
    if script.count("#SBATCH --array=0-17%6\n") != 1 or "#SBATCH --no-requeue\n" not in script or "#SBATCH -t 1-00:00:00\n" not in script or "#SBATCH --gres=gpu:1\n" not in script or ACTIVATION.splitlines()[0] not in script or "conda activate knet_clean" not in script:
        raise ValueError("Fixed Slurm script mismatch")
    rows = [json.loads(line) for line in files[f"repo/{guard.EXPERIMENT_REL.as_posix()}/combos.jsonl"].decode().splitlines()]
    if rows != make_combos("A"):
        raise ValueError("Exact stage-A registration mismatch")
    source = json.loads(files[manifest["packaged_source_manifest"]["path"]])
    for name, expected in source["source_sha256"].items():
        safe_relative(name)
        if digest(files["repo/" + name]) != expected:
            raise ValueError("Inner source identity mismatch")
    runtime = json.loads(files[manifest["expected_runtime"]["path"]])
    baseline = json.loads(values["REMOTE_BASELINE.json"])
    validate_baseline(baseline)
    for key in ("python_version", "numpy_version", "torch_version"):
        if baseline["current_environment"].get(key) != runtime.get(key):
            raise ValueError("Baseline package-version mismatch")
    return values, manifest, files, baseline, runtime


def submission_environment(stage):
    env = {key: value for key, value in os.environ.items() if not key.startswith("SBATCH_")}
    for key in CACHE_NAMES:
        env[key] = str(stage / "runtime_cache" / key.lower())
    return env


def environment_preflight(env, expected):
    # Matches the frozen job's activation; stdlib metadata does not import Torch/NumPy.
    program = "import importlib.metadata as m,json,os,platform; print(json.dumps({'python_version':platform.python_version(),'numpy_version':m.version('numpy'),'torch_version':m.version('torch'),'caches':{k:os.environ.get(k) for k in ('MPLCONFIGDIR','TORCH_HOME','XDG_CACHE_HOME')}}))"
    command = ["bash", "-c", "set -eo pipefail\n" + ACTIVATION + "python -B -c \"" + program + "\""]
    response = subprocess.run(command, env=env, capture_output=True, text=True, check=False, timeout=60)
    if response.returncode:
        raise ValueError("Conda cache/version preflight failed")
    snapshot = json.loads(response.stdout)
    if snapshot.get("caches") != {key: env[key] for key in CACHE_NAMES} or any(snapshot.get(key) != expected[key] for key in ("python_version", "numpy_version", "torch_version")):
        raise ValueError("Conda cache/version preflight mismatch")
    return {"command": command, "returncode": response.returncode, "stdout": response.stdout, "stderr": response.stderr, "snapshot": snapshot}


def _text(value):
    return value.decode("utf-8", errors="replace") if isinstance(value, bytes) else (value or "")


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--payload", type=Path, required=True)
    parser.add_argument("--stage", required=True)
    parser.add_argument("--submit", action="store_true")
    args = parser.parse_args(argv)
    if not args.submit or args.stage != "A":
        raise ValueError("Only explicit --stage A --submit is admitted; B/C blocked")
    if platform.system() != "Linux":
        raise ValueError("Actual deployment requires Linux")
    payload = args.payload.absolute()
    root = remote_path(REMOTE_FAMILY_ROOT)
    if os.path.lexists(root):
        raise FileExistsError(f"Existing family consumes attempt; no retry: {root}")
    if not root.parent.is_dir() or root.parent.resolve() != root.parent.absolute():
        raise ValueError("Unsafe or missing remote parent")
    values, manifest, files, baseline, runtime = validate_payload(payload)
    before = verify_protected(baseline)
    stage = root / "stages/A"
    env = submission_environment(stage)
    preflight = environment_preflight(env, runtime)
    root.mkdir()  # Exclusive family ownership is the durable no-retry boundary.
    sync_directory(root.parent)
    (root / "stages").mkdir()
    sync_directory(root)
    stage.mkdir()
    sync_directory(root / "stages")
    for name, data in files.items():
        path = stage / str(safe_relative(name))
        path.parent.mkdir(parents=True, exist_ok=True)
        write_new(path, data)
    for name, data in values.items():
        write_new(stage / name, data)
    (stage / "logs").mkdir()
    for key in CACHE_NAMES:
        Path(env[key]).mkdir(parents=True, exist_ok=False)
    data_dir = stage / "repo/data/processed/high_flow_aug"
    data_dir.mkdir(parents=True)
    for row in baseline["data"].values():
        link = data_dir / PurePosixPath(row["path"]).name
        link.symlink_to(remote_path(row["path"]))
        if link.resolve() != remote_path(row["resolved_path"]).absolute() or link.stat().st_size != row["bytes"] or sha256(link) != row["sha256"]:
            raise ValueError("Deployed data link mismatch")
    guard.verify_static_files(stage, manifest)
    guard.verify_source_hashes(stage, manifest)
    after = verify_protected(baseline)
    if before != after:
        raise ValueError("Protected evidence changed during deployment")
    write_json(stage / "CACHE_ENVIRONMENT_PREFLIGHT.json", preflight)
    write_json(stage / "PROTECTED_FILES_BEFORE.json", before)
    write_json(stage / "PROTECTED_FILES_AFTER.json", after)
    receipt = {"stage": "A", "status": "DEPLOYMENT_PASS", "root": REMOTE_FAMILY_ROOT, "stage_root": manifest["remote_root"], "array": "0-17%6", "archive_sha256": manifest["archive"]["sha256"], "authorization_sha256": INPUT_HASHES["AUTHORIZATION.json"], "protected_files_verified": len(after), "time_utc": now(), "retry_authorized": False}
    write_json(stage / "DEPLOYMENT_RECEIPT.json", receipt)
    command = ["sbatch", "--parsable", "--export=ALL", str(stage / "hpc_array.slurm")]
    intent = dict(receipt, command=command, script_sha256=sha256(stage / "hpc_array.slurm"), cache_overrides={key: env[key] for key in CACHE_NAMES}, removed_sbatch_options=sorted(key for key in os.environ if key.startswith("SBATCH_")))
    write_json(stage / "SUBMISSION_INTENT.json", intent)
    try:
        response = subprocess.run(command, cwd=stage, env=env, capture_output=True, text=True, check=False, timeout=60)
        result = {"returncode": response.returncode, "stdout": response.stdout, "stderr": response.stderr, "exception": None}
    except Exception as exc:
        result = {"returncode": None, "stdout": _text(getattr(exc, "stdout", "")), "stderr": _text(getattr(exc, "stderr", "")), "exception": f"{type(exc).__name__}: {exc}"}
    write_json(stage / "SUBMISSION_RESPONSE.json", dict(result, time_utc=now()))
    match = re.fullmatch(r"([0-9]+)(?:;[^\s;]+)?", result["stdout"].strip())
    if result["returncode"] != 0 or result["exception"] is not None or match is None:
        raise RuntimeError("Submission failed or uncertain; attempt retained, no retry")
    write_new(stage / "array_job_id.txt", match.group(1).encode("ascii"))
    receipt = dict(receipt, status="SUBMITTED", job_id=match.group(1), training_entry_verified=False)
    write_json(stage / "SUBMISSION_RECEIPT.json", receipt)
    print(json.dumps(receipt), flush=True)
    return receipt


if __name__ == "__main__":
    main()

"""Explicit frozen payload construction and safe, data-free offline acceptance.

Frozen Python, model and pytest dependencies come only from the successful
single-basin payload. This module intentionally imports only the standard library.
"""

import argparse
import gzip
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile

REPO = Path(__file__).resolve().parents[3]
PREFIX = "src/precip_input_assimilation/"
FROZEN_PAYLOAD_SHA256 = "abed02753942025babf4a892c579c44b9c0a3718c156c91ee35fa36abe2ee668"
PLAN = "docs/plans/2026-10-03-precip-dynamic-neural-filter-eight-basin-plan-v0.2.md"
ROSTER = "docs/plans/2026-10-03-precip-dynamic-neural-filter-eight-basin-roster-v0.1.json"
CONTRACT = PREFIX + "configs/dynamic_filter_eight_basins_v01.json"
STATIC_TABLES = ("camels_topo.txt", "camels_clim.txt", "camels_name.txt",
                 "camels_vege.txt", "camels_soil.txt", "camels_geol.txt")
NEW_FILES = tuple(PREFIX + name for name in (
    "dynamic_filter_multibasin/__init__.py", "dynamic_filter_multibasin/contract.py",
    "dynamic_filter_multibasin/data.py", "dynamic_filter_multibasin/hydro.py",
    "dynamic_filter_multibasin/identity.py", "dynamic_filter_multibasin/controller.py",
    "dynamic_filter_multibasin/audit.py", "scripts/run_dynamic_filter_eight_basins.py",
    "scripts/audit_dynamic_filter_recovery.py",
    "scripts/run_dynamic_filter_eight_basins_technical.py", "tests/test_dynamic_filter_multibasin_boundary.py",
    "tests/test_dynamic_filter_multibasin_isolation.py", "tests/test_dynamic_filter_multibasin_summary.py",
    "tests/test_dynamic_filter_multibasin_bundle.py", "hpc/dynamic_filter_eight_basins_bundle.py",
    "hpc/dynamic_filter_eight_basins_deploy.sh", "hpc/dynamic_filter_eight_basins_v01.slurm",
    "hpc/dynamic_filter_eight_basins_mailbox.py", "hpc/dynamic_filter_eight_basins_status_v01.sh",
    "configs/dynamic_filter_eight_basins_v01.json"))
REQUIRED = tuple("code/" + name for name in NEW_FILES + (PLAN, ROSTER)) + (
    "artifacts/frozen_model/model_epoch030.pt", "artifacts/frozen_model/config.yml",
    "artifacts/frozen_model/train_data/train_data_scaler.yml", "vendor/pytest/__init__.py",
    "vendor/_pytest/__init__.py", "vendor/py.py", "records/roster_locked.json",
    "records/budget_snapshot.json", "provenance/frozen_bundle_manifest.json", "source_manifest.json",
    "code/src/fair_benchmark/frozen/track0_forcing_only_basins.txt",
    "provenance/metadata/camels_topo.txt", "provenance/metadata/camels_clim.txt",
    "provenance/metadata/camels_name.txt", "provenance/metadata/camels_vege.txt",
    "provenance/metadata/camels_soil.txt", "provenance/metadata/camels_geol.txt")
MAX_MEMBER_BYTES = 128 * 1024 * 1024
MAX_PAYLOAD_BYTES = 512 * 1024 * 1024


def digest(value):
    return hashlib.sha256(value).hexdigest()


def fs_path(path):
    """Use Windows' explicit long-path form for deeply nested offline snapshots."""
    path = Path(path)
    if os.name == "nt" and path.is_absolute() and not path.as_posix().startswith("//?/"):
        return Path("//?/" + path.resolve().as_posix())
    return path


def json_bytes(value):
    return (json.dumps(value, sort_keys=True, indent=2, ensure_ascii=False, allow_nan=False) + "\n").encode("utf-8")


def member_name(name):
    """Reject platform-dependent escapes before any filesystem operation."""
    if not isinstance(name, str) or not name or "\\" in name or ":" in name or "\x00" in name:
        raise ValueError("Unsafe payload member name")
    path = PurePosixPath(name)
    if path.is_absolute() or any(part in ("", ".", "..", ".worktrees") for part in name.split("/")):
        raise ValueError(f"Unsafe payload member: {name}")
    if path.as_posix() != name:
        raise ValueError(f"Noncanonical payload member: {name}")
    return name


def archive_files(path, expected_sha256=None):
    """Read ordinary archive files; reject links, duplicates and undeclared types."""
    raw = Path(path).read_bytes()
    if expected_sha256 is not None and digest(raw) != expected_sha256:
        raise RuntimeError("Outer archive identity mismatch")
    result, seen, size = {}, set(), 0
    with tarfile.open(fileobj=io.BytesIO(raw), mode="r:gz") as archive:
        for info in archive:
            name = member_name(info.name)
            folded = name.casefold()
            if folded in seen or not info.isfile() or info.size < 0 or info.size > MAX_MEMBER_BYTES:
                raise RuntimeError(f"Duplicate, linked, oversized or non-file member: {name}")
            seen.add(folded)
            size += info.size
            if size > MAX_PAYLOAD_BYTES:
                raise RuntimeError("Unpacked payload exceeds the explicit byte limit")
            handle = archive.extractfile(info)
            content = handle.read() if handle is not None else None
            if content is None or len(content) != info.size:
                raise RuntimeError(f"Truncated member: {name}")
            result[name] = content
    return result


def require_legacy(files):
    manifest = json.loads(files["bundle_manifest.json"])
    expected = manifest["files"]
    if set(files) != set(expected) | {"bundle_manifest.json"}:
        raise RuntimeError("Frozen payload contains missing or undeclared members")
    for name, value in expected.items():
        member_name(name)
        if digest(files[name]) != value:
            raise RuntimeError(f"Frozen payload changed: {name}")
    return manifest


def read_source(path, boundary):
    path, boundary = Path(path), Path(boundary).resolve()
    if ".worktrees" in path.parts or not path.resolve().is_relative_to(boundary):
        raise PermissionError(f"Source outside registered boundary: {path}")
    cursor = path
    while cursor != boundary and cursor != cursor.parent:
        if cursor.is_symlink() or (hasattr(cursor, "is_junction") and cursor.is_junction()):
            raise PermissionError(f"Linked source is forbidden: {path}")
        cursor = cursor.parent
    return path.read_bytes()


def budget_remaining(snapshot):
    total = snapshot.get("budget_total_seconds")
    used = snapshot.get("used_gpu_seconds")
    reserved = snapshot.get("unsettled_reserved_seconds")
    if total != 259200 or not isinstance(used, (int, float)) or used < 24378:
        raise RuntimeError("Budget snapshot omits or understates cumulative GPU use")
    if not isinstance(reserved, (int, float)) or reserved < 0 or snapshot.get("unsettled_jobs") != []:
        raise RuntimeError("Unsettled jobs or reservations prevent a new submission")
    remaining = total - used - reserved
    if remaining <= 300 or snapshot.get("remaining_gpu_seconds") != remaining:
        raise RuntimeError("Budget remainder mismatch or no exit reserve")
    return remaining


def seal_files(files, metadata):
    """Seal an explicit member dictionary; useful to test adversarial archives."""
    files = dict(files)
    if "manifest.sha256" in files or "bundle_manifest.json" in files:
        raise RuntimeError("Sealing metadata must be generated, never supplied")
    for name in files:
        member_name(name)
    manifest = dict(metadata, files={name: digest(value) for name, value in sorted(files.items())})
    files["bundle_manifest.json"] = json_bytes(manifest)
    files["manifest.sha256"] = "".join(f"{digest(value)}  {name}\n" for name, value in sorted(files.items())).encode()
    return files


def verify_files(files, require_members=True):
    """Verify all ordinary files, including exact set equality and the JSON seal."""
    if len({name.casefold() for name in files}) != len(files):
        raise RuntimeError("Case-colliding payload members")
    for name in files:
        member_name(name)
    listed = {}
    for row in files["manifest.sha256"].decode("utf-8").splitlines():
        if len(row) < 67 or row[64:66] != "  ":
            raise RuntimeError("Invalid manifest.sha256 row")
        expected, name = row[:64], member_name(row[66:])
        if not re.fullmatch("[0-9a-f]{64}", expected) or name in listed:
            raise RuntimeError("Invalid or duplicated digest row")
        listed[name] = expected
    if set(files) != set(listed) | {"manifest.sha256"}:
        raise RuntimeError("Missing or undeclared payload member")
    for name, expected in listed.items():
        if digest(files[name]) != expected:
            raise RuntimeError(f"Payload identity mismatch: {name}")
    manifest = json.loads(files["bundle_manifest.json"])
    if set(manifest["files"]) != set(files) - {"manifest.sha256", "bundle_manifest.json"}:
        raise RuntimeError("JSON manifest member set mismatch")
    for name, expected in manifest["files"].items():
        if listed[name] != expected:
            raise RuntimeError(f"Manifest disagreement: {name}")
    if require_members:
        missing = sorted(set(REQUIRED) - set(files))
        if missing:
            raise RuntimeError(f"Required files omitted: {missing}")
        source = json.loads(files["source_manifest.json"])
        wanted = {name[5:]: digest(value) for name, value in files.items()
                  if name.startswith("code/") and PurePosixPath(name).suffix in (".py", ".sh", ".slurm")}
        if source != wanted:
            raise RuntimeError("Incomplete source identity manifest")
        identities = {"contract_sha256": "code/" + CONTRACT, "roster_sha256": "code/" + ROSTER,
                      "plan_sha256": "code/" + PLAN, "roster_lock_sha256": "records/roster_locked.json",
                      "budget_snapshot_sha256": "records/budget_snapshot.json"}
        for key, name in identities.items():
            if manifest.get(key) != digest(files[name]):
                raise RuntimeError(f"Bound identity differs: {key}")
        if manifest.get("remaining_gpu_seconds") != budget_remaining(json.loads(files["records/budget_snapshot.json"])):
            raise RuntimeError("Sealed budget mismatch")
    return manifest


def write_archive(files, output):
    stream = io.BytesIO()
    with tarfile.open(fileobj=stream, mode="w") as archive:
        for name, value in sorted(files.items()):
            info = tarfile.TarInfo(member_name(name))
            info.size, info.mtime, info.uid, info.gid, info.mode = len(value), 0, 0, 0, 0o444
            archive.addfile(info, io.BytesIO(value))
    value = gzip.compress(stream.getvalue(), mtime=0)
    with Path(output).open("xb") as handle:
        handle.write(value)
    return {"payload": str(output), "sha256": digest(value), "bytes": len(value), "files": len(files)}


def pack(repo, output, frozen_payload, contract, roster_lock, budget_snapshot, run_id):
    repo = Path(repo).resolve()
    local_free = shutil.disk_usage(Path(output).parent).free
    if local_free < 5 * 1024 ** 3:
        raise RuntimeError("Local free space is below the fixed 5 GiB gate")
    if not re.fullmatch("[A-Za-z0-9_-]{1,120}", run_id):
        raise ValueError("Invalid run identity")
    frozen = archive_files(frozen_payload, FROZEN_PAYLOAD_SHA256)
    prior_manifest = require_legacy(frozen)
    files = {name: value for name, value in frozen.items() if name != "bundle_manifest.json"}
    files["provenance/frozen_bundle_manifest.json"] = frozen["bundle_manifest.json"]
    for name in NEW_FILES + (PLAN, ROSTER):
        target = "code/" + name
        if target in files:
            raise RuntimeError(f"A new file collides with a frozen dependency: {name}")
        source_path = Path(contract) if name == CONTRACT else repo / name
        files[target] = read_source(source_path, repo)
    roster = json.loads(files["code/" + ROSTER])
    for name, expected in roster["input_sha256"].items():
        if name.startswith("data/camels_us/camels_attributes_v2.0/"):
            target = "provenance/metadata/" + PurePosixPath(name).name
        else:
            target = "code/" + member_name(name)
        value = files.get(target)
        if value is None:
            value = read_source(repo / name, repo)
        if digest(value) != expected:
            raise RuntimeError(f"Selection provenance changed: {name}")
        files[target] = value
    # The other three permitted static tables are needed by synthetic static/area
    # identity tests. These are metadata snapshots, never real daily input files.
    for name in STATIC_TABLES:
        target = "provenance/metadata/" + name
        if target not in files:
            files[target] = read_source(repo / "data/camels_us/camels_attributes_v2.0" / name, repo)
    files["records/roster_locked.json"] = Path(roster_lock).read_bytes()
    files["records/budget_snapshot.json"] = Path(budget_snapshot).read_bytes()
    remaining = budget_remaining(json.loads(files["records/budget_snapshot.json"]))
    files["source_manifest.json"] = json_bytes({name[5:]: digest(value) for name, value in sorted(files.items())
        if name.startswith("code/") and PurePosixPath(name).suffix in (".py", ".sh", ".slurm")})
    metadata = {"schema": "dynamic-filter-eight-basins-bundle-v1", "run_id": run_id,
        "channel": "precip-dynamic-filter-v03", "experiment_family": "eight_basin_fixed_recipe_v01",
        "gpu_count": 1, "cpus": 2, "remaining_gpu_seconds": remaining,
        "local_free_bytes_at_pack": local_free,
        "frozen_payload_sha256": FROZEN_PAYLOAD_SHA256, "frozen_run_id": prior_manifest["run_id"],
        "contract_sha256": digest(files["code/" + CONTRACT]), "roster_sha256": digest(files["code/" + ROSTER]),
        "plan_sha256": digest(files["code/" + PLAN]), "roster_lock_sha256": digest(files["records/roster_locked.json"]),
        "budget_snapshot_sha256": digest(files["records/budget_snapshot.json"]),
        "source_manifest_sha256": digest(files["source_manifest.json"]),
        "frozen_source": "verified successful immutable archive; no current shared core/vendor substitution"}
    files = seal_files(files, metadata)
    verify_files(files)
    return write_archive(files, output)


def safe_extract(payload, output, expected_sha256, require_members=True):
    files = archive_files(payload, expected_sha256)
    manifest = verify_files(files, require_members)
    output = Path(output)
    if ".worktrees" in output.parts or ".worktrees" in output.resolve().parts:
        raise PermissionError("Extraction into a worktree is forbidden")
    for ancestor in (output, *output.parents):
        if ancestor.is_symlink() or (hasattr(ancestor, "is_junction") and ancestor.is_junction()):
            raise PermissionError("Linked extraction directories are forbidden")
    output.mkdir(parents=True, exist_ok=False)
    boundary = output.resolve()
    for name, value in sorted(files.items()):
        target = boundary / member_name(name)
        fs_path(target.parent).mkdir(parents=True, exist_ok=True)
        if not target.resolve().is_relative_to(boundary):
            raise PermissionError("Extraction target escaped output")
        with fs_path(target).open("xb") as handle:
            handle.write(value)
    return manifest


def verify(root):
    root = fs_path(Path(root).resolve())
    files = {}
    for path in root.rglob("*"):
        if path.is_symlink() or (hasattr(path, "is_junction") and path.is_junction()):
            raise RuntimeError(f"Linked payload path: {path}")
        if path.is_file():
            files[path.relative_to(root).as_posix()] = path.read_bytes()
    return verify_files(files)


def offline(payload, output, expected_sha256, python=sys.executable):
    manifest = safe_extract(payload, output, expected_sha256)
    root, checks = fs_path(Path(output).resolve()), []
    code = root / "code"
    environment = dict(os.environ, PYTHONDONTWRITEBYTECODE="1", PYTEST_DISABLE_PLUGIN_AUTOLOAD="1",
                       PYTHONPATH=os.pathsep.join((str(code / "src"), str(code), str(root / "vendor"))))
    for entry in ("scripts/run_dynamic_filter_eight_basins.py",
                  "scripts/run_dynamic_filter_eight_basins_technical.py",
                  "hpc/dynamic_filter_eight_basins_bundle.py"):
        command = [str(python), "-B", str(code / PREFIX / entry), "--help"]
        result = subprocess.run(command, cwd=code, env=environment, capture_output=True, text=True, timeout=30)
        checks.append({"command": command, "returncode": result.returncode, "stdout": result.stdout,
                       "stderr": result.stderr})
        if result.returncode:
            raise RuntimeError(f"Data-free entry help failed: {entry}: {result.stderr}")
    verify(root)
    return {"success": True, "scope": "ordinary files, manifest and --help; no real data/model loading",
            "manifest_sha256": digest((root / "manifest.sha256").read_bytes()), "run_id": manifest["run_id"],
            "checks": checks}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_subparsers(dest="mode", required=True)
    pack_parser = modes.add_parser("pack")
    pack_parser.add_argument("--repo", type=Path, default=REPO)
    for flag in ("output", "frozen-payload", "contract", "roster-lock", "budget-snapshot"):
        pack_parser.add_argument("--" + flag, type=Path, required=True)
    pack_parser.add_argument("--run-id", required=True)
    for mode in ("verify", "offline", "extract"):
        command = modes.add_parser(mode)
        if mode == "verify":
            command.add_argument("--root", type=Path, required=True)
        else:
            command.add_argument("--payload", type=Path, required=True)
            command.add_argument("--output", type=Path, required=True)
            command.add_argument("--sha256", required=True)
    args = parser.parse_args()
    if args.mode == "pack":
        result = pack(args.repo, args.output, args.frozen_payload, args.contract, args.roster_lock,
                      args.budget_snapshot, args.run_id)
    elif args.mode == "verify":
        manifest = verify(args.root)
        result = {"verified": len(manifest["files"]), "run_id": manifest["run_id"]}
    elif args.mode == "offline":
        result = offline(args.payload, args.output, args.sha256)
    else:
        result = safe_extract(args.payload, args.output, args.sha256)
        result = {"run_id": result["run_id"], "verified": True}
    print(json.dumps(result, ensure_ascii=False, allow_nan=False))


if __name__ == "__main__":
    main()

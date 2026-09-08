"""Read-only, chunked export of original and recovered receiver evidence."""
from __future__ import annotations

import argparse
import base64
import gzip
import hashlib
import io
import json
import re
import subprocess
import tarfile
from pathlib import Path, PurePosixPath

ORIGINAL_ROOT = Path("/data1/home/sunyiq/id29_xinanjiang_transfer_20260907_v01")
RECOVERY_ROOT = Path("/data1/home/sunyiq/id29_xinanjiang_transfer_20260907_v01_recovery_01")
SOURCE_JOB = "223833"
RECOVERED_BASINS = ["05120500", "09492400"]
EXPECTED_ARMS = [f"uniform_{i}" for i in range(5)] + ["pooled_ratio", "pooled_absolute", "open_loop"]
EXPECTED_SOURCE_SUMMARY = "0d01d9643f7725432a89dade8a4854b008f6f015baf0edc6c0f847f9d0264da9"
EXPECTED_RECOVERY_SUMMARY = "fe69f16fba468b6721126ffad3ccd1c6782268b744d657390a3766adc744d5a6"
EXPECTED_TRANSFER = "5f644f707c9b67eacf89562e7484cfc42f859dfcdad597b1eeb58584a99a2d04"
EXPECTED_BUNDLE = "59a8f8b50776086c5b1263e441cfc9cf80299b80feca24a60919d582d5d21545"
MAX_ARCHIVE = 48 * 1024 * 1024


def require(condition, message):
    if not condition:
        raise ValueError(message)


def read_json(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def digest_file(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def digest_bytes(value):
    return hashlib.sha256(value).hexdigest()


def json_bytes(value):
    return (json.dumps(value, sort_keys=True, indent=2, allow_nan=False) + "\n").encode("utf-8")


def assign_chunk(name, basins, chunk_count):
    """Assign basin directories round-robin; administrative evidence stays in chunk zero."""
    require(isinstance(chunk_count, int) and chunk_count > 0, "invalid chunk count")
    parts = PurePosixPath(name).parts
    if len(parts) >= 5 and parts[0] in {"original", "recovery"} and parts[1:3] == ("receiver", "evaluation"):
        basin = parts[3]
        require(basin in basins, "unknown receiver basin in export path")
        return basins.index(basin) % chunk_count
    return 0


def terminal_identity(job_id, state, exit_code):
    require(re.fullmatch(r"[0-9]+", job_id) is not None, "invalid Slurm job id")
    rows = subprocess.run(
        ["sacct", "-j", job_id, "-n", "-P", "--format=JobIDRaw,State,ExitCode"],
        check=True, capture_output=True, text=True, timeout=40,
    ).stdout.splitlines()
    require(any(row.split("|")[:3] == [job_id, state, exit_code] for row in rows),
            "Slurm job terminal identity")


def validate_result(result, basin, success):
    require(result.get("basin_id") == basin and len(result.get("arms", [])) == 8,
            "receiver result identity/count")
    require([arm.get("arm") for arm in result["arms"]] == EXPECTED_ARMS,
            "receiver arm identities/order")
    if success:
        require(result.get("status") == "success"
                and all(arm.get("status") == "success" for arm in result["arms"]),
                "successful receiver result is incomplete")
    else:
        require(result.get("status") == "failed"
                and all(arm.get("status") == "not_run"
                        and arm.get("error") == "basin stage failed: HPC raw input differs from local frozen source"
                        for arm in result["arms"]), "unexpected source failure")


def inventory(original_root=ORIGINAL_ROOT, recovery_root=RECOVERY_ROOT, chunk_count=4):
    """Validate both immutable roots and return logical export paths with stable chunk assignments."""
    require(digest_file(original_root / "receiver/summary.json") == EXPECTED_SOURCE_SUMMARY,
            "source summary changed")
    require(digest_file(original_root / "development/frozen_transfer.json") == EXPECTED_TRANSFER,
            "source transfer changed")
    require(digest_file(original_root / "bundle/MANIFEST.json") == EXPECTED_BUNDLE,
            "source bundle changed")
    require(digest_file(recovery_root / "receiver/summary.json") == EXPECTED_RECOVERY_SUMMARY,
            "recovery summary changed")
    require(digest_file(recovery_root / "development/frozen_transfer.json") == EXPECTED_TRANSFER,
            "recovery transfer changed")

    require((original_root / "receiver_job_id.txt").read_text(encoding="utf-8").strip().split(";", 1)[0]
            == SOURCE_JOB, "source receiver job id")
    recovery_job = (recovery_root / "job_id.txt").read_text(encoding="utf-8").strip().split(";", 1)[0]
    terminal_identity(SOURCE_JOB, "FAILED", "1:0")
    terminal_identity(recovery_job, "COMPLETED", "0:0")
    basins = read_json(original_root / "bundle/inputs/receiver_basins.json")
    require(len(basins) == len(set(basins)) == 360, "receiver basin identity/count")

    source_manifest = read_json(recovery_root / "source_receiver_manifest.json")
    current_source = {path.relative_to(original_root).as_posix(): digest_file(path)
                      for path in sorted((original_root / "receiver").rglob("*")) if path.is_file()}
    require(len(source_manifest) == 6465 and current_source == source_manifest,
            "source receiver path set or content changed")
    evaluation_dirs = sorted(path.name for path in (original_root / "receiver/evaluation").iterdir()
                             if path.is_dir())
    require(evaluation_dirs == sorted(basins), "source receiver basin directories")
    source_results = {}
    for basin in basins:
        result = read_json(original_root / "receiver/evaluation" / basin / "result.json")
        validate_result(result, basin, basin not in RECOVERED_BASINS)
        source_results[basin] = result
    require(sum(result["status"] == "success" for result in source_results.values()) == 358,
            "source receiver successful basin count")
    source_summary = read_json(original_root / "receiver/summary.json")
    require(source_summary.get("status") == "failed"
            and source_summary.get("successful_arm_basins") == 2864
            and source_summary.get("main_comparison", {}).get("finite_pairs") == 358,
            "source receiver summary counts")

    recovery_summary = read_json(recovery_root / "receiver/summary.json")
    require(recovery_summary.get("status") == "success"
            and recovery_summary.get("recovered_basins") == RECOVERED_BASINS
            and recovery_summary.get("successful_basins") == 2
            and recovery_summary.get("successful_arms") == 16
            and recovery_summary.get("source_summary_sha256") == EXPECTED_SOURCE_SUMMARY
            and recovery_summary.get("transfer_sha256") == EXPECTED_TRANSFER,
            "recovery summary counts/identity")
    require([row.get("basin_id") for row in recovery_summary.get("results", [])] == RECOVERED_BASINS,
            "recovery summary basin order")
    recovery_files = sorted(path for path in (recovery_root / "receiver").rglob("*") if path.is_file())
    require(len(recovery_files) == 37, "recovery receiver file count")
    for row in recovery_summary["results"]:
        basin = row["basin_id"]
        saved = read_json(recovery_root / "receiver/evaluation" / basin / "result.json")
        require(saved == row, "recovery aggregate differs from saved basin result")
        validate_result(saved, basin, True)

    package_manifest = read_json(recovery_root / "MANIFEST.json")
    require(len(package_manifest) == 14, "recovery package manifest count")
    for name, expected in package_manifest.items():
        require(digest_file(recovery_root / name) == expected, "recovery package file changed: " + name)

    original_extras = [
        "receiver_job_id.txt", "approve_receiver.json", "receiver_submission_receipt.json",
        f"logs/id29-xaj-receive_{SOURCE_JOB}.out", f"logs/id29-xaj-receive_{SOURCE_JOB}.err",
    ]
    recovery_generated = [
        "source_receiver_manifest.json", "approve_recovery.json", "submission_receipt.json",
        "job_id.txt", "execution.json", f"logs/id29-xaj-rec2_{recovery_job}.out",
        f"logs/id29-xaj-rec2_{recovery_job}.err",
    ]
    allowed_recovery = set(package_manifest) | {"MANIFEST.json"} | set(recovery_generated)
    allowed_recovery |= {path.relative_to(recovery_root).as_posix() for path in recovery_files}
    actual_recovery = {path.relative_to(recovery_root).as_posix()
                       for path in recovery_root.rglob("*") if path.is_file()
                       if not path.relative_to(recovery_root).parts[0] == "numba_cache"}
    require(actual_recovery == allowed_recovery, "recovery path set changed outside cache")

    paths = {}
    for relative in sorted(source_manifest):
        paths["original/" + relative] = (original_root / relative,
                                         assign_chunk("original/" + relative, basins, chunk_count))
    for relative in original_extras:
        path = original_root / relative
        require(path.is_file() and not path.is_symlink(), "missing or unsafe source administrative evidence")
        paths["original/" + relative] = (path, 0)
    for relative in sorted(allowed_recovery):
        path = recovery_root / relative
        require(path.is_file() and not path.is_symlink(), "missing or unsafe recovery evidence")
        logical = "recovery/" + relative
        paths[logical] = (path, assign_chunk(logical, basins, chunk_count))
    require(all(not path.is_symlink() for path, _ in paths.values()), "symlink in receiver export")

    files = {name: {"sha256": digest_file(path), "bytes": path.stat().st_size, "chunk": chunk}
             for name, (path, chunk) in sorted(paths.items())}
    global_manifest = {
        "stage": "receiver_combined", "chunk_count": chunk_count,
        "source_job": SOURCE_JOB, "recovery_job": recovery_job,
        "source_summary_sha256": EXPECTED_SOURCE_SUMMARY,
        "recovery_summary_sha256": EXPECTED_RECOVERY_SUMMARY,
        "transfer_sha256": EXPECTED_TRANSFER, "bundle_manifest_sha256": EXPECTED_BUNDLE,
        "receiver_basins": basins, "files": files,
    }
    return paths, global_manifest


def add_bytes(archive, name, value):
    info = tarfile.TarInfo(name)
    info.size = len(value)
    info.mtime = 0
    info.mode = 0o444
    archive.addfile(info, io.BytesIO(value))


def make_chunk(paths, global_manifest, chunk_index, chunk_count):
    require(global_manifest.get("stage") == "receiver_combined"
            and global_manifest.get("chunk_count") == chunk_count,
            "global export manifest identity")
    require(isinstance(chunk_index, int) and 0 <= chunk_index < chunk_count, "invalid chunk index")
    selected = {name: item for name, item in sorted(paths.items()) if item[1] == chunk_index}
    expected_files = global_manifest.get("files", {})
    require(set(paths) == set(expected_files), "global export file set")
    for name, (path, chunk) in paths.items():
        record = expected_files[name]
        require(record == {"sha256": digest_file(path), "bytes": path.stat().st_size, "chunk": chunk},
                "global export file identity: " + name)
    chunk_manifest = {name: {"sha256": expected_files[name]["sha256"], "bytes": expected_files[name]["bytes"]}
                      for name in selected}
    global_value = json_bytes(global_manifest)
    chunk_value = json_bytes(chunk_manifest)
    raw = io.BytesIO()
    with gzip.GzipFile(fileobj=raw, mode="wb", mtime=0) as compressed:
        with tarfile.open(fileobj=compressed, mode="w") as archive:
            for name, (path, _) in selected.items():
                add_bytes(archive, name, path.read_bytes())
            add_bytes(archive, f"EXPORT_CHUNK_{chunk_index}_MANIFEST.json", chunk_value)
            if chunk_index == 0:
                add_bytes(archive, "EXPORT_GLOBAL_MANIFEST.json", global_value)
    payload = raw.getvalue()
    require(len(payload) <= MAX_ARCHIVE, "receiver chunk exceeds transfer limit")
    metadata = {
        "stage": "receiver_combined", "chunk_index": chunk_index, "chunk_count": chunk_count,
        "files": len(selected), "expanded_bytes": sum(v["bytes"] for v in chunk_manifest.values()),
        "archive_bytes": len(payload), "archive_sha256": digest_bytes(payload),
        "global_manifest_sha256": digest_bytes(global_value),
        "source_job": global_manifest.get("source_job"),
        "recovery_job": global_manifest.get("recovery_job"),
        "source_summary_sha256": global_manifest.get("source_summary_sha256"),
        "recovery_summary_sha256": global_manifest.get("recovery_summary_sha256"),
        "transfer_sha256": global_manifest.get("transfer_sha256"),
    }
    return payload, metadata


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--chunk-index", type=int, required=True)
    parser.add_argument("--chunk-count", type=int, required=True)
    args = parser.parse_args()
    require(args.chunk_count == 4, "released receiver export uses exactly four chunks")
    paths, global_manifest = inventory(chunk_count=args.chunk_count)
    payload, metadata = make_chunk(paths, global_manifest, args.chunk_index, args.chunk_count)
    print("EXPORT_METADATA", json.dumps(metadata, sort_keys=True, allow_nan=False))
    print("BEGIN_BASE64_RECEIVER_CHUNK")
    print(base64.b64encode(payload).decode("ascii"))
    print("END_BASE64_RECEIVER_CHUNK")


if __name__ == "__main__":
    main()

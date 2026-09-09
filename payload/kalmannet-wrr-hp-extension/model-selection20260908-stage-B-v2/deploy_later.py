"""B/C-only deployment extension. No A reattempt path; original A code untouched."""
from __future__ import annotations

import argparse
import json
import os
import platform
import re
import subprocess
from pathlib import Path, PurePosixPath

import build_package as package
import deploy_remote as old
import launch_once as guard
from audit_stage import load_admission, scheduler_snapshot
from evidence_contract import REMOTE, canonical, digest, file_hash, read_json, require, verify_seal
from stage_c import combos_from_lock
from study_config import make_combos

A_RECEIPTS = {
    "DEPLOYMENT_RECEIPT.json": "57afb26a2e896ea930cb6b9df8236884e83b259b2d82c0d11e942d4166392621",
    "SUBMISSION_INTENT.json": "993aea2e7e21ff9c64a38f1721f99fce54e0d236b42684c500464c086987c0bf",
    "SUBMISSION_RECEIPT.json": "32429fb041d3ec653f23da15b2290bb17558592c6e279be1c2c45eef2945ed0e",
    "SUBMISSION_RESPONSE.json": "42f062f6731bbb9b8da6c3f9f3eb7fc38cfe1dae9e2388a4a4cd34d4959e5701",
}
B_MANIFEST_SHA256 = "c5f8d56480510729dd14d44cb00d5e703425ebdeb837b059b674998b425784b1"
# Exact result of build_c_package's four permitted substitutions on the frozen
# A script (SHA256 5ee0db7f2da590117a4494892668943d80813d6466d3c8449c1eb371313bb1e2).
# Pinning the complete resulting bytes also excludes conflicting extra directives.
C_SCHEDULER_SHA256 = "da255097e13855cc89af45ed623ff773c23adaaac92ee996c23f51770d01b296"


def advancement_gate(payload, stage, *, live=True):
    require(stage in ("B", "C"), "A can never be attempted through later deployment")
    payload = Path(payload)
    root = old.remote_path(REMOTE)
    require(root.is_dir() and not root.is_symlink(), "Original A family must exist")
    target = root / "stages" / stage
    require(not os.path.lexists(target), "Later stage already exists; attempt consumed")
    for name, sha in dict(A_RECEIPTS, **{k: v for k, v in old.INPUT_HASHES.items() if k != "STAGE_A_MANIFEST.json"}).items():
        path = root / "stages/A" / name
        old.ordinary(path, root)
        require(file_hash(path) == sha, "Original A deployment/authorization identity changed")
    pins = None
    if stage == "C":
        lock = verify_seal(read_json(payload / "TOP_THREE_LOCK.json"), kind="TOP_THREE_LOCK")
        combos_from_lock(lock)
        pins = lock["admissions"]
    certificates = {}
    for earlier in (("A",) if stage == "B" else ("A", "B")):
        path = payload / f"STAGE_{earlier}_ADMISSION.json"
        cert, evidence = load_admission(path, earlier, expected_hash=pins[earlier] if pins else None, recheck_files=live)
        certificates[earlier] = file_hash(path)
        remote_receipt = root / "stages" / earlier / "SUBMISSION_RECEIPT.json"
        require(read_json(remote_receipt) == evidence["submission_receipt"], "Admission submitted-parent mismatch")
        if live:
            _, active, _ = scheduler_snapshot(evidence["submission_receipt"]["job_id"])
            require(not active, "Earlier family jobs still active")
    if stage == "C":
        from selection import admitted_records, reference_records, screen
        references, _ = reference_records(payload / "REMOTE_BASELINE.json")
        ranking = screen(references + admitted_records(payload / "STAGE_A_ADMISSION.json", "A")
                         + admitted_records(payload / "STAGE_B_ADMISSION.json", "B"))
        require(ranking["status"] == "READY" and ranking == lock["screening"], "C lock ranking does not reproduce")
        for rank, row in enumerate(lock["top_three"], 1):
            require(row["rank"] == rank and {k: v for k, v in row.items() if k not in ("rank", "parameters")} == ranking["ranking"][rank-1], "C top-three selection differs from admitted ranking")
    return certificates


def validate_later_payload(payload, stage):
    require(stage in ("B", "C"), "Only B/C payloads")
    payload = Path(payload)
    values = {}
    for name, sha in old.INPUT_HASHES.items():
        if name == "STAGE_A_MANIFEST.json":
            continue
        old.ordinary(payload / name, payload)
        data = (payload / name).read_bytes()
        require(digest(data) == sha, "Frozen authorization/baseline mismatch")
        values[name] = data
    manifest_path = payload / f"STAGE_{stage}_MANIFEST.json"
    old.ordinary(manifest_path, payload)
    manifest = read_json(manifest_path)
    values[manifest_path.name] = manifest_path.read_bytes()
    require(manifest["stage"] == stage and manifest["remote_root"] == REMOTE + "/stages/" + stage, "Later-stage manifest mismatch")
    require(manifest["held_out_test_data_included"] is False, "Test payload forbidden")
    require(manifest["archive"]["relative_path"] == f"payload/stage_{stage}.tar.gz", "Archive stage mismatch")
    if stage == "B":
        require(file_hash(manifest_path) == B_MANIFEST_SHA256, "Frozen B manifest changed")
        guard.verify_manifest_contract(stage, manifest)
        expected = make_combos("B")
    else:
        lock_data = (payload / "TOP_THREE_LOCK.json").read_bytes()
        require(digest(lock_data) == manifest["top_three_lock_sha256"], "C lock hash mismatch")
        lock = verify_seal(json.loads(lock_data), kind="TOP_THREE_LOCK")
        expected = combos_from_lock(lock)
        values["TOP_THREE_LOCK.json"] = lock_data
        require(file_hash(payload / "STAGE_B_MANIFEST.json") == B_MANIFEST_SHA256, "C requires original B source anchor")
        b_manifest = read_json(payload / "STAGE_B_MANIFEST.json")
        for name, sha in b_manifest["static_files"].items():
            if name not in package.REPLACED_REPO_MEMBERS and name != "hpc_array.slurm":
                require(manifest["static_files"].get(name) == sha, "C frozen numerical/guard bytes changed")
    require(manifest["candidate_count"] == len(expected) and manifest["allowed_indices"] == list(range(len(expected))), "Later stage count mismatch")
    archive_path = payload / str(old.safe_relative(manifest["archive"]["relative_path"]))
    old.ordinary(archive_path, payload)
    archive = archive_path.read_bytes()
    require(digest(archive) == manifest["archive"]["sha256"] and len(archive) == manifest["archive"]["size_bytes"], "Later-stage archive hash mismatch")
    files = old.read_archive(archive, manifest["static_files"])
    if stage == "C":
        require(files["TOP_THREE_LOCK.json"] == values["TOP_THREE_LOCK.json"], "C archive/external lock mismatch")
        require(digest(files["hpc_array.slurm"]) == C_SCHEDULER_SHA256, "C scheduler template byte mismatch")
    rows = [json.loads(line) for line in files[package.COMBOS_MEMBER].splitlines()]
    require(rows == expected, "Later-stage registration mismatch")
    package.validate_inner_source_hashes(files, json.loads(files[package.SOURCE_MANIFEST_MEMBER]))
    require(digest(files[package.BASE_CONFIG_MEMBER]) == package.BASE_CONFIG_SHA256
            and digest(files[package.ORIGINAL_LAUNCHER_MEMBER]) == package.ORIGINAL_LAUNCHER_SHA256
            and digest(files["expected_runtime.json"]) == package.EXPECTED_RUNTIME_SHA256, "Numerical source anchors changed")
    script = files["hpc_array.slurm"].decode()
    for text in (f"#SBATCH --array=0-{len(expected)-1}%6\n", "#SBATCH --no-requeue\n", "#SBATCH -t 1-00:00:00\n",
                 "#SBATCH --gres=gpu:1\n", "#SBATCH --cpus-per-task=4\n", "#SBATCH -p hgpu2p\n"):
        require(script.count(text) == 1, "Resource/array policy mismatch")
    baseline = json.loads(values["REMOTE_BASELINE.json"])
    old.validate_baseline(baseline)
    return values, manifest, files, baseline, json.loads(files["expected_runtime.json"])


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--payload", type=Path, required=True)
    parser.add_argument("--stage", choices=("B", "C"), required=True)
    parser.add_argument("--submit", action="store_true")
    args = parser.parse_args(argv)
    require(args.submit and platform.system() == "Linux", "Explicit Linux later-stage submission required")
    payload = args.payload.absolute()
    admissions = advancement_gate(payload, args.stage)
    values, manifest, files, baseline, runtime = validate_later_payload(payload, args.stage)
    before = old.verify_protected(baseline)
    root = old.remote_path(REMOTE)
    target = root / "stages" / args.stage
    env = old.submission_environment(target)
    preflight = old.environment_preflight(env, runtime)
    # Recheck after potentially slow input hashing, before the exclusive write.
    require(advancement_gate(payload, args.stage) == admissions, "Admission changed during deployment gate")
    target.mkdir()
    old.sync_directory(target.parent)
    for name, data in dict(files, **values).items():
        path = target / str(old.safe_relative(name))
        path.parent.mkdir(parents=True, exist_ok=True)
        old.write_new(path, data)
    for earlier in admissions:
        for name in (f"STAGE_{earlier}_ADMISSION.json", f"stage_{earlier}_evidence.json.gz"):
            old.write_new(target / name, (payload / name).read_bytes())
    (target / "logs").mkdir()
    for key in old.CACHE_NAMES:
        Path(env[key]).mkdir(parents=True, exist_ok=False)
    data_dir = target / "repo/data/processed/high_flow_aug"
    data_dir.mkdir(parents=True)
    for row in baseline["data"].values():
        link = data_dir / PurePosixPath(row["path"]).name
        link.symlink_to(old.remote_path(row["path"]))
        require(str(link.resolve()) == row["resolved_path"] and file_hash(link) == row["sha256"], "Later data link mismatch")
    if args.stage == "C":
        from launch_c import configure_guard
        configure_guard(target)
    guard.verify_static_files(target, manifest)
    guard.verify_source_hashes(target, manifest)
    require(old.verify_protected(baseline) == before, "Reference hashes changed")
    old.write_json(target / "CACHE_ENVIRONMENT_PREFLIGHT.json", preflight)
    receipt = {"stage": args.stage, "status": "DEPLOYMENT_PASS", "root": REMOTE, "stage_root": manifest["remote_root"],
               "array": f"0-{manifest['candidate_count']-1}%6", "archive_sha256": manifest["archive"]["sha256"],
               "authorization_sha256": old.INPUT_HASHES["AUTHORIZATION.json"], "admissions": admissions,
               "time_utc": old.now(), "retry_authorized": False, "protected_files_verified": len(before)}
    old.write_json(target / "DEPLOYMENT_RECEIPT.json", receipt)
    command = ["sbatch", "--parsable", "--export=ALL", str(target / "hpc_array.slurm")]
    old.write_json(target / "SUBMISSION_INTENT.json", dict(receipt, command=command, script_sha256=file_hash(target / "hpc_array.slurm"),
                   cache_overrides={key: env[key] for key in old.CACHE_NAMES}))
    # The stage exists now and cannot be attempted again, even if this final
    # fresh check fails. Never turn an earlier certificate into a stale permit.
    for earlier, sha in admissions.items():
        load_admission(payload / f"STAGE_{earlier}_ADMISSION.json", earlier, expected_hash=sha, recheck_files=True)
    try:
        response = subprocess.run(command, cwd=target, env=env, capture_output=True, text=True, check=False, timeout=60)
        result = {"returncode": response.returncode, "stdout": response.stdout, "stderr": response.stderr, "exception": None}
    except Exception as exc:
        result = {"returncode": None, "stdout": old._text(getattr(exc, "stdout", "")), "stderr": old._text(getattr(exc, "stderr", "")), "exception": f"{type(exc).__name__}: {exc}"}
    old.write_json(target / "SUBMISSION_RESPONSE.json", dict(result, time_utc=old.now()))
    match = re.fullmatch(r"([0-9]+)(?:;[^\s;]+)?", result["stdout"].strip())
    require(result["returncode"] == 0 and result["exception"] is None and match, "Uncertain submission; consumed attempt, no retry")
    old.write_new(target / "array_job_id.txt", match[1].encode())
    receipt.update(status="SUBMITTED", job_id=match[1], training_entry_verified=False)
    old.write_json(target / "SUBMISSION_RECEIPT.json", receipt)
    print(json.dumps(receipt), flush=True)
    return receipt


if __name__ == "__main__":
    main()

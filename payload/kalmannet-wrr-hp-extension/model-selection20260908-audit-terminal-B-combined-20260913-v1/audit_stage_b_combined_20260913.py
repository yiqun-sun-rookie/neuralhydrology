"""Combined stage-B terminal admission: original array 224255 + resource retries 224389 (A800) and 225178 (A40).

Read-only collector (cluster) and pure audit (anywhere). Frozen numerical source, data, seeds and selection
rules are only *verified* here, never changed. No weights are deserialized. The original stage-B evidence is
collected and audited by the unchanged ``audit_stage`` module; it necessarily yields STOP_INFRASTRUCTURE because
twelve original cells failed on 24 GB GPUs. This module maps every one of those twelve cells to exactly one
user-authorized retry attempt, audits that attempt with the same identity/config/score chain, keeps the original
failures and the six per-task cancellations of duplicate retry1 tasks as explicit records, and admits the stage
only when all 21 planned cells are terminal with either a SUCCESS or a NUMERIC_FAILURE outcome.
"""
from __future__ import annotations

import argparse
import ast
import base64
import copy
import csv
import gzip
import io
import json
import re
import subprocess
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation
from pathlib import Path, PurePosixPath

import audit_stage as audit
import build_package as package
import deploy_remote as deploy
import launch_once as guard
from study_config import make_combos
from evidence_contract import (REMOTE, METRIC, canonical, compressed, digest, file_hash, immutable, read_json,
                               require, sealed, verify_seal)

ORIGINAL_JOB = "224255"
ORIGINAL_MANIFEST_SHA256 = "c5f8d56480510729dd14d44cb00d5e703425ebdeb837b059b674998b425784b1"
MEMORY_ERROR = "torch.OutOfMemoryError: CUDA out of memory."
RETRY_EVENT = "RESOURCE_RETRY_ENTERING_UNCHANGED_TRAINING"
KIND = "STAGE_B_COMBINED_ADMISSION"

ATTEMPTS = {
    "retry1": {
        "root": REMOTE + "/resource_recovery_20260909/B_retry1", "job_id": "224389",
        "attempt_id": "B_memory_20260909_retry1",
        "manifest_sha256": "567471e0b43fc924176d93e18d3c880b5f45db131378b1c46dc194a6e6002e2a",
        "slurm_sha256": "4c60d0e95e37cd521209e208b5427fd842ecbbedcc2681a5e360db5143f4f478",
        "partition": "hgpu8", "gpu": "NVIDIA A800-SXM4-80GB", "min_gpu_memory_bytes": 75 * 1024 ** 3,
        "admitted_indices": [0, 1, 2, 6, 7, 8], "cancelled_indices": [3, 4, 5, 9, 10, 11],
        "launcher": "launch_B_memory_retry_20260909.py",
        "controls": ["RESOURCE_RETRY_AUTHORIZATION_20260909.md"],
        "array": "0-11%6", "dependency": "afterany:224255", "max_concurrent_training": 6,
    },
    "retry2": {
        "root": REMOTE + "/resource_recovery_20260911/B_retry2", "job_id": "225178",
        "attempt_id": "B_memory_20260911_retry2",
        "manifest_sha256": "407043f71edebe0536491e0f8cfa82609e181d04d11ca34aead2ad13090c37c3",
        "slurm_sha256": "73211deb6984e63150352b4c6d9f8de1197bea2bebeae241244fa663a5f7d45a",
        "partition": "hgpu4", "gpu": "NVIDIA A40", "min_gpu_memory_bytes": 40 * 1024 ** 3,
        "admitted_indices": [3, 4, 5, 9, 10, 11], "cancelled_indices": [],
        "launcher": "launch_B_memory_retry2_20260911.py",
        "controls": ["RESOURCE_RETRY_AUTHORIZATION_20260909.md", "RETRY2_A40_AUTHORIZATION_20260911.md"],
        "array": "3-5,9-11%3", "dependency": None, "max_concurrent_training": 3,
    },
}
SUPERSEDED_BY = {i: name for name, spec in ATTEMPTS.items() for i in spec["admitted_indices"]}
MEMORY_FAILED_INDICES = list(range(12))
# Local, byte-retained mailbox receipts that document the per-task cancellations of duplicate retry1 tasks.
CANCELLATION_RECEIPTS = ("mailbox_result_83.txt", "mailbox_result_90.txt", "mailbox_result_93.txt")
OPERATION_RECEIPTS = ("mailbox_result_77.txt", "mailbox_result_80.txt", "mailbox_result_99.txt")


def _ordinary_read(root, hashes, raw):
    """Same retention discipline as audit_stage._collect: hash every file, retain text bytes as base64."""
    def read(path, *, text=True):
        deploy.ordinary(path, root)
        hashes[str(path)] = file_hash(path)
        if text:
            value = path.read_bytes()
            require(digest(value) == hashes[str(path)], "Evidence changed during read")
            raw[str(path)] = base64.b64encode(value).decode("ascii")
            return value.decode("utf-8")
    return read


def collect_attempt(name, spec, *, run=subprocess.run):
    """Exact deployed retry root only; mirrors the original collector's per-task evidence inventory."""
    import yaml
    root = Path(spec["root"])
    require(root.resolve() == root and not root.is_symlink() and root.is_dir(), "Unsafe retry root")
    hashes, raw = {}, {}
    read = _ordinary_read(root, hashes, raw)
    manifest = json.loads(read(root / "RETRY_MANIFEST.json"))
    require(hashes[str(root / "RETRY_MANIFEST.json")] == spec["manifest_sha256"], "Retry manifest pin mismatch")
    stage_manifest = json.loads(read(root / "STAGE_B_MANIFEST.json"))
    require(hashes[str(root / "STAGE_B_MANIFEST.json")] == ORIGINAL_MANIFEST_SHA256, "Retry copy of original manifest changed")
    read(root / "retry.slurm")
    require(hashes[str(root / "retry.slurm")] == spec["slurm_sha256"], "Retry batch script pin mismatch")
    receipt = json.loads(read(root / "SUBMISSION_RECEIPT.json"))
    for control in ("SUBMISSION_INTENT.json", "SUBMISSION_RESPONSE.json", "array_job_id.txt",
                    "ORIGINAL_ACCOUNTING_AT_DEPLOYMENT.json", "ORIGINAL_QUEUE_AT_DEPLOYMENT.json",
                    "PROTECTED_FILES_BEFORE.json", "PROTECTED_FILES_AFTER.json", "INITIAL_QUEUE_OBSERVATION.json"):
        read(root / control)
    optional_controls = {}
    for control in ("RETRY1_THROTTLE_UPDATE.json",):
        path = root / control
        if path.exists():
            optional_controls[control] = json.loads(read(path))
    for extra in manifest["extra_static_files"]:
        read(root / str(deploy.safe_relative(extra)), text=False)
    static = {}
    for rel in stage_manifest["static_files"]:
        path = root / str(deploy.safe_relative(rel))
        read(path, text=False)
        static[rel] = hashes[str(path)]
    experiment = root / "repo" / guard.EXPERIMENT_REL
    combos_text = read(experiment / "combos.jsonl")
    combos = [json.loads(line) for line in combos_text.splitlines()]
    registry = list(csv.DictReader(io.StringIO(read(experiment / "registry.csv"))))
    source = json.loads(read(root / stage_manifest["packaged_source_manifest"]["path"]))
    runtime = json.loads(read(root / "expected_runtime.json"))
    base = yaml.safe_load(read(experiment / "base_config.yaml"))
    data_dir = root / "repo/data/processed/high_flow_aug"
    links = {}
    for path in sorted(data_dir.iterdir()):
        require(path.is_symlink(), "Unexpected non-link data entry in retry root")
        links[path.name] = {"resolved": str(path.resolve()), "sha256": file_hash(path), "bytes": path.stat().st_size}
    accounting, active, queries = audit.scheduler_snapshot(spec["job_id"], run)
    e = {"attempt": name, "root": str(root), "job_id": spec["job_id"], "manifest": manifest, "stage_manifest": stage_manifest,
         "submission_receipt": receipt, "optional_controls": optional_controls, "static_hashes": static, "combos": combos,
         "registry": registry, "source": source, "runtime": runtime, "base_config": base, "data_links": links,
         "accounting_stdout": accounting, "active_family_jobs": active, "scheduler_queries": queries,
         "tasks": {}, "absent": {}, "file_hashes": hashes, "metadata_base64": raw, "absent_paths": [],
         "collected_at_utc": datetime.now(timezone.utc).isoformat()}
    claims_dir = root / "claims"
    actual_claims = {p.name for p in claims_dir.iterdir()} if claims_dir.exists() else set()
    require(actual_claims <= {f"index{i:04d}.json" for i in spec["admitted_indices"]}, "Unexpected retry claims")

    def optional(path):
        if path.exists():
            return read(path)
        e["absent_paths"].append(str(path))
        return None
    for index in spec["admitted_indices"]:
        combo = combos[index]
        run_dir = audit.expected_run(root, combo)
        audits = list((experiment / "audits").glob(combo["run_id"] + "_formal_*.json"))
        require(len(audits) == 1, "Missing or duplicate retry launcher audit")
        audit_json = json.loads(read(audits[0]))
        config = yaml.safe_load(read(run_dir / "config_used.yaml"))
        cell_text = optional(run_dir / "cell_metrics.json")
        optional(run_dir / "metrics.json")
        checkpoint = run_dir / "results/best_model.pt"
        if checkpoint.exists():
            read(checkpoint, text=False)
        epoch_text = optional(run_dir / "results/epoch_log.jsonl")
        e["tasks"][str(index)] = {
            "audit": audit_json, "claim": json.loads(read(claims_dir / f"index{index:04d}.json")),
            "config": config, "cell": json.loads(cell_text) if cell_text else None,
            "metrics_present": (run_dir / "metrics.json").exists(),
            "epochs": audit.parse_epoch_log(epoch_text) if epoch_text else [],
            "checkpoint_sha256": hashes.get(str(checkpoint)),
            "run_dirs": sorted(str(p) for p in (experiment / "runs").glob(f"*/idx{index:04d}_*")),
            "combos_sha256": digest(combos_text.encode()),
            "failed_marker": optional(run_dir / "FAILED"), "success_marker": optional(run_dir / "SUCCESS"),
            "error_text": optional(run_dir / "error.txt") or "",
            "launcher_log": read(experiment / "logs" / f"{combo['run_id']}_formal.stdout.log"),
            "slurm_stdout": read(root / "logs" / f"slurm-{spec['job_id']}_{index}.out"),
            "provenance": {"audit_path": str(audits[0]), "cell_path": str(run_dir / "cell_metrics.json"),
                           "config_path": str(run_dir / "config_used.yaml"), "checkpoint_path": str(checkpoint)}}
        optional(root / "logs" / f"slurm-{spec['job_id']}_{index}.err")
    for index in spec["cancelled_indices"]:
        combo = combos[index]
        e["absent"][str(index)] = {
            "claim": (claims_dir / f"index{index:04d}.json").exists(),
            "run_dirs": sorted(str(p) for p in (experiment / "runs").glob(f"*/idx{index:04d}_*")),
            "audits": sorted(str(p) for p in (experiment / "audits").glob(combo["run_id"] + "_formal_*.json")),
            "slurm_logs": sorted(str(p) for p in (root / "logs").glob(f"slurm-{spec['job_id']}_{index}.*")),
            "launcher_log": (experiment / "logs" / f"{combo['run_id']}_formal.stdout.log").exists()}
    require(all(file_hash(Path(path)) == value for path, value in hashes.items()), "Retry evidence changed during collection")
    return e


def collect_combined(*, run=subprocess.run):
    original = audit.collect("B", Path(REMOTE) / "stages/B/SUBMISSION_RECEIPT.json", run=run)
    attempts = {name: collect_attempt(name, spec, run=run) for name, spec in ATTEMPTS.items()}
    return {"kind": "STAGE_B_COMBINED_EVIDENCE", "evidence_origin": "REMOTE_READ_ONLY_COLLECTOR", "stage": "B",
            "original": original, "attempts": attempts, "operations": [],
            "collected_at_utc": datetime.now(timezone.utc).isoformat()}


# ----------------------------------------------------------------------------------------------------------------
# Local attachment of byte-retained operation receipts (cancellations, throttle changes, node-pin relaxation).
# ----------------------------------------------------------------------------------------------------------------

def attach_operations(evidence, family):
    family = Path(family)
    ops = []
    for name in CANCELLATION_RECEIPTS + OPERATION_RECEIPTS:
        data = (family / name).read_bytes()
        ops.append({"name": name, "sha256": digest(data), "base64": base64.b64encode(data).decode("ascii"),
                    "role": "cancellation" if name in CANCELLATION_RECEIPTS else "operation"})
    evidence["operations"] = ops
    return evidence


def decode_receipt_payload(text, marker):
    match = re.findall(r"^" + re.escape(marker) + r"=(\S+)\s*$", text, re.M)
    require(len(match) == 1, f"Receipt lacks exactly one {marker}")
    return json.loads(gzip.decompress(base64.b64decode(match[0], validate=True)))


def cancellations_from_operations(operations):
    """Return {index: receipt_name} for every retry1 task the retained receipts show as cancelled under guards."""
    cancelled = {}
    for op in operations:
        if op.get("role") != "cancellation":
            continue
        data = base64.b64decode(op["base64"], validate=True)
        require(digest(data) == op["sha256"], "Cancellation receipt bytes/hash mismatch")
        text = data.decode("utf-8")
        require(re.findall(r"^### exit_code=(\d+)\s*$", text, re.M) == ["0"], "Cancellation receipt did not complete")
        payload = decode_receipt_payload(text, "CANCEL_SUPERSEDED_GZIP_BASE64")
        require(payload["kind"] == "USER_AUTHORIZED_CANCEL_SUPERSEDED_RETRY1_TASKS" and payload["new_jobs_submitted"] == 0, "Wrong cancellation receipt kind")
        for action in payload["actions"]:
            if not action["cancelled"]:
                continue
            cond = action["conditions"]
            require(cond["retry2_running"] is True and cond["retry2_claimed"] is True and cond["retry2_failed_marker"] is False
                    and cond["retry1_pending"] is True, "Cancellation executed without its guards")
            require(action["scancel"]["command"] == ["scancel", f"224389_{action['index']}"] and action["scancel"]["returncode"] == 0,
                    "Cancellation was not a per-task scancel of retry1")
            require(action["index"] not in cancelled, "Duplicate cancellation record")
            cancelled[action["index"]] = op["name"]
    return cancelled


# ----------------------------------------------------------------------------------------------------------------
# Pure audit.
# ----------------------------------------------------------------------------------------------------------------

def verify_config_at(cfg, base, combo, root):
    """audit_stage.verify_config with the attempt root substituted for the original stage root."""
    expected = copy.deepcopy(base)
    expected["training"]["learning_rate"] = combo["lr"]
    expected["model"]["knet"].update(hidden_size=combo["hidden_size"], num_layers=combo["num_layers"],
                                        in_mult=combo["in_out_mult"], out_mult=combo["in_out_mult"])
    for section in ("training", "model", "loss", "system_model", "dataloader", "runtime", "instrumentation"):
        require(cfg.get(section) == expected[section], f"Config {section} mismatch")
    require(set(cfg["data"]["dataset_path"]) == {"train", "val"}, "Unexpected data split")
    repo = root + "/repo"
    for split, configured in cfg["data"]["dataset_path"].items():
        require(str(configured) == repo + "/data/processed/high_flow_aug/" + deploy.DATA_NAMES[split], "YAML dataset path mismatch")
    if "__config_file__" in cfg:
        require(cfg["__config_file__"] == repo + "/" + guard.EXPERIMENT_REL.as_posix() + "/base_config.yaml", "YAML base config provenance mismatch")
    return cfg["runtime"].get("seed")


def _retry_identity(task, combo, account, spec, e):
    root = PurePosixPath(e["root"])
    audit_json, claim = task["audit"], task["claim"]
    require(audit_json["combo"] == combo and audit_json["run_id"] == combo["run_id"] and audit_json["mode"] == "formal", "Retry audit configuration identity mismatch")
    require(claim["attempt_id"] == spec["attempt_id"] and claim["index"] == combo["index"]
            and claim["array_task_id"] == combo["index"] and claim["combo"] == combo
            and claim["original_run_id"] == combo["run_id"] and claim["original_job_id"] == ORIGINAL_JOB
            and claim["retry_manifest_sha256"] == spec["manifest_sha256"], "Retry claim identity mismatch")
    require(claim["job_id"] == account["JobIDRaw"] and claim["array_job_id"] == spec["job_id"], "Retry claim scheduler identity mismatch")
    require(claim["runtime"].get("gpu") == spec["gpu"] and claim["gpu_total_memory_bytes"] >= spec["min_gpu_memory_bytes"], "Retry claim hardware mismatch")
    require(audit_json.get("slurm_job_id") == account["JobIDRaw"] and audit_json.get("slurm_array_task_id") == str(combo["index"]), "Retry audit scheduler identity mismatch")
    require(audit_json.get("expected_run_dir") == str(audit.expected_run(root, combo)), "Retry run directory identity mismatch")
    require(task["run_dirs"] == [str(audit.expected_run(root, combo))], "Missing or duplicate retry run directory")
    require(audit_json.get("held_out_test_loaded") is False, "Held-out test flag mismatch")
    require(audit_json.get("config_sha256") == package.BASE_CONFIG_SHA256, "Retry audit base configuration hash mismatch")
    require(audit_json.get("combos_sha256") == task["combos_sha256"], "Retry audit combos hash mismatch")
    require(audit_json.get("verified_source") == e["source"]["source_sha256"], "Retry audit source hash mismatch")
    for key, value in e["runtime"].items():
        if key in ("python_version", "numpy_version", "provenance_note"):
            continue
        expected = spec["gpu"] if key == "gpu" else value
        require(audit_json["runtime"].get(key) == expected, f"Retry audit runtime {key} mismatch")
    require(audit_json["runtime"].get("gpu") == spec["gpu"], "Retry audit GPU identity mismatch")
    require(audit_json["runtime"].get("seed") == combo["seed"], "Retry effective seed mismatch")
    events = [json.loads(line) for line in task["slurm_stdout"].splitlines() if line.startswith("{") and RETRY_EVENT in line]
    require(len(events) == 1 and events[0]["event"] == RETRY_EVENT and events[0]["job_id"] == account["JobIDRaw"]
            and events[0]["index"] == combo["index"] and events[0]["attempt_id"] == spec["attempt_id"]
            and events[0]["array_job_id"] == spec["job_id"], "Missing retry scheduler stdout identity")
    launcher = f"[Launcher] run_id={combo['run_id']} mode=formal seed={combo['seed']} combo="
    lines = [line[len(launcher):] for line in task["launcher_log"].splitlines() if line.startswith(launcher)]
    require(len(lines) == 1 and ast.literal_eval(lines[0]) == combo, "Retry launcher log combo identity mismatch")


def _success_record(task, combo, account, root, base):
    """SUCCESS branch of audit_stage.audit_task, unchanged in substance, parameterised by the attempt root."""
    require(account["ExitCode"] == "0:0", "COMPLETED exit mismatch")
    require(task["audit"].get("launcher_status") == "ok", "Completed launcher status mismatch")
    require(task["failed_marker"] is None and task["success_marker"] is not None, "Success/failure marker mismatch")
    cell = task["cell"]
    require(cell is not None and cell["combo"] == combo, "Cell combo mismatch")
    require(all(cell.get(k) == combo[k] for k in ("run_id", "index", "seed")) and cell.get("mode") == "formal", "Cell identity mismatch")
    metrics = cell["grid_metrics"]
    require(metrics.get("status") == "ok" and metrics.get("global_index") == combo["index"]
            and all(metrics.get(k) == combo[k] for k in ("lr", "hidden_size", "num_layers", "in_out_mult")), "Grid metrics identity mismatch")
    score = cell["validation_scoring"]
    checkpoint = str(audit.expected_run(root, combo) / "results/best_model.pt")
    require(metrics["model_path"] == checkpoint and metrics["config_path"] == str(audit.expected_run(root, combo) / "config_used.yaml"), "Grid config/checkpoint path mismatch")
    require(score["best_checkpoint"] == checkpoint and score["best_checkpoint_sha256"] == task["checkpoint_sha256"], "Checkpoint identity mismatch")
    require(score["eval_lead_time"] == 13 and len(score["pooled_nse_slot_0_to_12"]) == 13, "Forecast scoring slots mismatch")
    require(score["best_epoch_zero_based"] == cell["epoch_log_summary"]["best_epoch_zero_based_from_log"], "Selected epoch mismatch")
    epochs = task["epochs"]
    require(epochs and [r["epoch_zero_based"] for r in epochs] == list(range(len(epochs))), "Incomplete/duplicate completed epoch log")
    improved = [r for r in epochs if r["improved"]]
    require(improved and improved[-1]["epoch_zero_based"] == score["best_epoch_zero_based"], "Checkpoint selected-epoch log mismatch")
    require(all(r["monitor"] == "val_bp_loss" and r["forecast_leads_start_at_one"] is True for r in epochs), "Training checkpoint monitor/lead policy mismatch")
    summary = cell["epoch_log_summary"]
    require(summary["epochs_run"] == len(epochs)
            and summary["grad_explosion_rollbacks_total"] == sum(r["grad_explosion_rollbacks"] for r in epochs)
            and summary["nan_inf_skips_total"] == sum(r["nan_inf_skips"] for r in epochs), "Epoch/rollback summary mismatch")
    key = METRIC.split(".")[-1]
    require(Decimal(str(score[key])).is_finite(), "Nonfinite validation score")
    require(cell["train_seconds"] > 0, "Missing measured training duration")
    return dict(base, outcome="SUCCESS", score=str(score[key]), metric=METRIC, checkpoint_path=checkpoint,
                checkpoint_sha256=task["checkpoint_sha256"], train_seconds=cell["train_seconds"],
                epoch_log_summary=cell["epoch_log_summary"])


def verify_attempt_anchors(e, spec):
    """Bind parsed retry views to retained bytes and to the frozen original stage manifest."""
    import yaml
    root = PurePosixPath(e["root"])
    raw, hashes = e["metadata_base64"], e["file_hashes"]
    absent = e["absent_paths"]
    require(isinstance(absent, list) and len(absent) == len(set(absent)), "Malformed retry absence evidence")
    absent = set(absent)
    require(absent.isdisjoint(raw) and absent.isdisjoint(hashes), "Retained retry file also declared absent")

    def content(path):
        name = str(path)
        data = base64.b64decode(raw[name], validate=True)
        require(digest(data) == hashes[name], "Retry parsed evidence byte hash mismatch")
        return data

    def parsed(path, value, parser=json.loads):
        data = content(path)
        require(parser(data) == value, "Retry parsed evidence differs from retained bytes")
        return digest(data)
    require(parsed(root / "RETRY_MANIFEST.json", e["manifest"]) == spec["manifest_sha256"], "Retry manifest bytes not pinned")
    require(parsed(root / "STAGE_B_MANIFEST.json", e["stage_manifest"]) == ORIGINAL_MANIFEST_SHA256, "Retry stage manifest bytes not pinned")
    require(hashes[str(root / "retry.slurm")] == spec["slurm_sha256"] and digest(content(root / "retry.slurm")) == spec["slurm_sha256"], "Retry batch script bytes not pinned")
    receipt_hash = parsed(root / "SUBMISSION_RECEIPT.json", e["submission_receipt"])
    for extra, sha in e["manifest"]["extra_static_files"].items():
        require(hashes.get(str(root / extra)) == sha, f"Retry control file hash mismatch: {extra}")
    require(spec["launcher"] in e["manifest"]["extra_static_files"] and all(c in e["manifest"]["extra_static_files"] for c in spec["controls"]), "Retry launcher/authorization not pinned by manifest")
    require(e["static_hashes"] == e["stage_manifest"]["static_files"], "Retry frozen static files differ from original stage manifest")
    experiment = root / "repo" / guard.EXPERIMENT_REL
    require(parsed(experiment / "base_config.yaml", e["base_config"], yaml.safe_load) == package.BASE_CONFIG_SHA256, "Retry frozen base config changed")
    require(parsed(root / "expected_runtime.json", e["runtime"]) == package.EXPECTED_RUNTIME_SHA256, "Retry frozen runtime changed")
    source_hash = parsed(experiment / "source_manifest.json", e["source"])
    require(source_hash == e["stage_manifest"]["packaged_source_manifest"]["sha256"], "Retry source manifest changed")
    for rel, sha in e["source"]["source_sha256"].items():
        require(e["static_hashes"].get("repo/" + rel) == sha, "Retry source/static manifest mismatch")
    parsed(experiment / "combos.jsonl", e["combos"], lambda data: [json.loads(x) for x in data.splitlines()])
    require(e["combos"] == make_combos("B"), "Retry registration mismatch")
    for row, combo in zip(e["registry"], e["combos"]):
        for key, value in combo.items():
            require(row["initial_learning_rate" if key == "lr" else key] == str(value), "Retry registry identity mismatch")
    require(len(e["registry"]) == len(e["combos"]), "Retry registry count mismatch")
    response = json.loads(content(root / "SUBMISSION_RESPONSE.json"))
    require(response["returncode"] == 0 and response["exception"] is None
            and re.fullmatch(r"Submitted batch job " + re.escape(spec["job_id"]) + r"\s*", response["stdout"]), "Retry submission response mismatch")
    require(content(root / "array_job_id.txt").decode().strip() == spec["job_id"], "Retry array parent record mismatch")
    intent = json.loads(content(root / "SUBMISSION_INTENT.json"))
    require(intent["manifest_sha256"] == spec["manifest_sha256"] and intent["script_sha256"] == spec["slurm_sha256"]
            and intent["retry_indices"] == sorted(spec["admitted_indices"] + spec["cancelled_indices"]), "Retry submission intent mismatch")
    for task in e["tasks"].values():
        provenance = task["provenance"]
        parsed(PurePosixPath(provenance["audit_path"]), task["audit"])
        parsed(PurePosixPath(provenance["config_path"]), task["config"], yaml.safe_load)
        run_dir = PurePosixPath(provenance["config_path"]).parent
        combo = task["audit"]["combo"]
        parsed(root / "claims" / f"index{combo['index']:04d}.json", task["claim"])
        require(type(task["metrics_present"]) is bool, "Malformed retry metrics presence flag")
        for name, present in (("cell_metrics.json", task["cell"] is not None), ("metrics.json", task["metrics_present"]),
                              ("SUCCESS", task["success_marker"] is not None)):
            key = str(run_dir / name)
            require((key in raw) == (key in hashes), "Retry success evidence bytes/hash presence mismatch")
            require((key in raw) == present and (key in absent) == (not present), "Retry success evidence flag/bytes/absence mismatch")
            if present:
                content(run_dir / name)
        if task["cell"] is not None:
            parsed(PurePosixPath(provenance["cell_path"]), task["cell"])
            parsed(run_dir / "metrics.json", task["cell"]["grid_metrics"])
        epoch_path = run_dir / "results/epoch_log.jsonl"
        if str(epoch_path) in raw:
            parsed(epoch_path, task["epochs"], audit.parse_epoch_log)
        else:
            require(task["epochs"] == [], "Unretained retry epoch log")
        require(task["checkpoint_sha256"] == hashes.get(provenance["checkpoint_path"]), "Retry checkpoint hash envelope mismatch")
        for key, path in (("launcher_log", experiment / "logs" / f"{combo['run_id']}_formal.stdout.log"),
                          ("slurm_stdout", root / "logs" / f"slurm-{spec['job_id']}_{combo['index']}.out"),
                          ("failed_marker", run_dir / "FAILED"), ("success_marker", run_dir / "SUCCESS"), ("error_text", run_dir / "error.txt")):
            if str(path) in raw:
                require(content(path).decode("utf-8") == task[key], "Retry log/marker parsed bytes mismatch")
            else:
                require(task[key] in (None, ""), "Unretained retry marker/log")
    return receipt_hash


def audit_attempt(e, spec, baseline, verified_data):
    """Records for one retry attempt: SUCCESS for admitted cells, CANCELLED_BEFORE_START for the duplicates."""
    verify_attempt_anchors(e, spec)
    receipt = e["submission_receipt"]
    require(receipt["status"] == "SUBMITTED" and receipt["job_id"] == spec["job_id"] and receipt["attempt_id"] == spec["attempt_id"]
            and receipt["root"] == e["root"] and receipt["partition"] == spec["partition"] and receipt["gpu"] == spec["gpu"]
            and receipt["array"] == spec["array"] and receipt["dependency"] == spec["dependency"]
            and receipt["original_job_id"] == ORIGINAL_JOB and receipt["manifest_sha256"] == spec["manifest_sha256"]
            and receipt["script_sha256"] == spec["slurm_sha256"]
            and sorted(receipt["retry_indices"]) == sorted(spec["admitted_indices"] + spec["cancelled_indices"]), "Retry receipt contract mismatch")
    m = e["manifest"]
    require(m["attempt_id"] == spec["attempt_id"] and m["original_job_id"] == ORIGINAL_JOB and m["original_manifest_sha256"] == ORIGINAL_MANIFEST_SHA256
            and sorted(m["allowed_indices"]) == sorted(spec["admitted_indices"] + spec["cancelled_indices"])
            and m["gpu"] == spec["gpu"] and m["min_gpu_memory_bytes"] == spec["min_gpu_memory_bytes"] and m["partition"] == spec["partition"]
            and m["batch_size"] == 2048 and m["max_epochs"] == 200 and m["time_limit_hours"] == 24
            and m["max_concurrent_training"] == spec["max_concurrent_training"] and m["dependency"] == spec["dependency"]
            and m["scientific_source_changed"] is False, "Retry manifest contract mismatch")
    expected_runtime = dict(e["runtime"], gpu=spec["gpu"])
    require(m["runtime_expected"] == expected_runtime, "Retry manifest runtime expectation mismatch")
    # Data identity: the retry root links the very same frozen train/validation files.
    expected_links = {PurePosixPath(r["path"]).name: {"resolved": r["resolved_path"], "sha256": r["sha256"], "bytes": r["bytes"]} for r in baseline["data"].values()}
    require(e["data_links"] == expected_links, "Retry data identity differs from frozen baseline")
    for index_str, failure in m["failures"].items():
        require(int(index_str) in spec["admitted_indices"] + spec["cancelled_indices"], "Retry manifest failure index outside attempt")
    expanded, ranges = audit.accounting_rows(e["accounting_stdout"], spec["job_id"], len(e["combos"]))
    require(not ranges and not e["active_family_jobs"] and all(row["State"] not in audit.ACTIVE for row in expanded.values()), "Retry attempt not terminal")
    root = PurePosixPath(e["root"])
    records = {}
    for index in spec["admitted_indices"]:
        combo = e["combos"][index]
        account = expanded.get(index)
        require(account is not None and account["State"] == "COMPLETED", f"Retry admitted cell {index} not COMPLETED in accounting")
        task = e["tasks"][str(index)]
        _retry_identity(task, combo, account, spec, e)
        require(task["audit"].get("verified_data") == verified_data, "Retry audit data hash/path mismatch")
        unused = verify_config_at(task["config"], e["base_config"], combo, e["root"])
        base = {"combo": combo, "job_id_raw": account["JobIDRaw"], "array_identity": account["JobID"],
                "accounting_seconds": account["ElapsedRaw"], "unused_yaml_runtime_seed": unused, "provenance": task["provenance"],
                "attempt": e["attempt"], "attempt_id": spec["attempt_id"], "attempt_root": e["root"], "attempt_job_id": spec["job_id"],
                "hardware": {"gpu": task["audit"]["runtime"]["gpu"], "partition": spec["partition"],
                             "gpu_total_memory_bytes": task["claim"]["gpu_total_memory_bytes"]}}
        records[index] = _success_record(task, combo, account, root, base)
    for index in spec["cancelled_indices"]:
        combo = e["combos"][index]
        require(index not in expanded, f"Cancelled retry cell {index} has an accounting element")
        gap = e["absent"][str(index)]
        require(gap["claim"] is False and gap["run_dirs"] == [] and gap["audits"] == [] and gap["slurm_logs"] == [] and gap["launcher_log"] is False,
                f"Cancelled retry cell {index} left training evidence")
        records[index] = {"combo": combo, "outcome": "CANCELLED_BEFORE_START", "attempt": e["attempt"], "attempt_id": spec["attempt_id"],
                          "attempt_job_id": spec["job_id"], "array_identity": f"{spec['job_id']}_{index}", "superseded_by": SUPERSEDED_BY[index]}
    require(set(expanded) == set(spec["admitted_indices"]), "Retry accounting elements differ from admitted cells")
    return records


def _resource_failure(task, combo, record):
    require(record["outcome"] == "STOP" and record["reason"] == "LAUNCH_OR_EXECUTION_FAILURE", "Original memory-failed cell has unexpected outcome")
    require(MEMORY_ERROR in task["error_text"] and task["failed_marker"] is not None and task["cell"] is None
            and task["metrics_present"] is False and task["success_marker"] is None, "Original failure is not the retained GPU-memory failure")
    expected = f"failed: RuntimeError: Run returned without metrics.json: {audit.expected_run(PurePosixPath(REMOTE + '/stages/B'), combo)}/metrics.json"
    require(task["audit"].get("launcher_status") == expected, "Original memory failure launcher status mismatch")
    return {"combo": combo, "outcome": "RESOURCE_FAILURE_GPU_MEMORY", "attempt": "original", "attempt_job_id": ORIGINAL_JOB,
            "array_identity": record["array_identity"], "job_id_raw": record["job_id_raw"],
            "accounting_seconds": record["accounting_seconds"], "hardware": {"gpu_total_capacity_hint": "23.56 GiB (RTX 3090 class)"},
            "provenance": task["provenance"], "superseded_by": SUPERSEDED_BY[combo["index"]]}


def audit_combined(evidence):
    try:
        return _audit_combined(evidence)
    except (ValueError, KeyError, TypeError, IndexError, SyntaxError, InvalidOperation, AttributeError) as exc:
        return {"status": "STOP_INTEGRITY", "reason": str(exc), "stage": "B", "records": []}


def _audit_combined(ev):
    require(ev.get("kind") == "STAGE_B_COMBINED_EVIDENCE" and ev.get("stage") == "B", "Wrong combined evidence kind")
    original = ev["original"]
    o = audit.audit_evidence(original)
    require(o["status"] in ("STOP_INFRASTRUCTURE", "TERMINAL_ADMITTED"), f"Original stage B is not terminal: {o.get('status')}: {o.get('reason')}")
    require(o["stage"] == "B" and o["job_id"] == ORIGINAL_JOB and len(o["records"]) == 21, "Original stage B audit shape mismatch")
    combos = make_combos("B")
    baseline, verified_data = original["baseline"], original["verified_data"]
    records, superseded = [None] * 21, []
    for index, record in enumerate(o["records"]):
        require(record["combo"] == combos[index], "Original record order mismatch")
        if index in MEMORY_FAILED_INDICES:
            superseded.append(_resource_failure(original["tasks"][str(index)], combos[index], record))
        else:
            require(record["outcome"] in ("SUCCESS", "NUMERIC_FAILURE"), f"Original cell {index} is neither success nor numeric failure")
            records[index] = dict(record, attempt="original", attempt_id="stage_B_original", attempt_job_id=ORIGINAL_JOB,
                                  attempt_root=original["root"],
                                  hardware={"gpu": original["tasks"][str(index)]["audit"]["runtime"].get("gpu")} if record["outcome"] == "SUCCESS" else None)
    require([r["combo"]["index"] for r in superseded] == MEMORY_FAILED_INDICES, "Not all twelve memory failures are accounted")
    cancelled = cancellations_from_operations(ev.get("operations", []))
    attempt_records = {}
    for name, spec in ATTEMPTS.items():
        e = ev["attempts"][name]
        require(e["attempt"] == name and e["root"] == spec["root"] and e["job_id"] == spec["job_id"], "Attempt evidence identity mismatch")
        require(e["source"] == original["source"] and e["runtime"] == original["runtime"] and e["base_config"] == original["base_config"], "Attempt frozen source/runtime/config differ from original stage")
        attempt_records[name] = audit_attempt(e, spec, baseline, verified_data)
    for index in MEMORY_FAILED_INDICES:
        owner = SUPERSEDED_BY[index]
        winner = attempt_records[owner][index]
        require(winner["outcome"] == "SUCCESS", f"Superseding attempt for cell {index} is not SUCCESS")
        others = [attempt_records[n][index] for n in ATTEMPTS if n != owner and index in attempt_records[n]]
        for other in others:
            require(other["outcome"] == "CANCELLED_BEFORE_START" and other["superseded_by"] == owner, f"Cell {index} has a second live attempt")
            require(cancelled.get(index) is not None, f"Cell {index} duplicate retry task lacks a retained cancellation receipt")
            other["cancellation_receipt"] = cancelled[index]
            superseded.append(other)
        records[index] = winner
    require(set(cancelled) == set(ATTEMPTS["retry1"]["cancelled_indices"]), "Cancellation receipts do not match the cancelled retry1 cells")
    require(all(r is not None for r in records), "Unassigned planned cell")
    outcomes = [r["outcome"] for r in records]
    require(all(x in ("SUCCESS", "NUMERIC_FAILURE") for x in outcomes), "Combined records still contain non-terminal or stop outcomes")
    hardware = sorted({r["hardware"]["gpu"] for r in records if r["outcome"] == "SUCCESS"})
    return {"status": "TERMINAL_ADMITTED", "stage": "B", "kind": KIND, "metric": METRIC,
            "job_ids": {"original": ORIGINAL_JOB, **{n: s["job_id"] for n, s in ATTEMPTS.items()}},
            "records": records, "superseded_attempts": superseded,
            "counts": {"SUCCESS": outcomes.count("SUCCESS"), "NUMERIC_FAILURE": outcomes.count("NUMERIC_FAILURE"),
                       "resource_failures_superseded": len([s for s in superseded if s["outcome"] == "RESOURCE_FAILURE_GPU_MEMORY"]),
                       "duplicate_tasks_cancelled": len([s for s in superseded if s["outcome"] == "CANCELLED_BEFORE_START"])},
            "hardware_classes_among_successes": hardware,
            "original_stage_audit_status": o["status"], "active_family_jobs": [], "stop_reasons": []}


# ----------------------------------------------------------------------------------------------------------------
# Certificate.
# ----------------------------------------------------------------------------------------------------------------

def write_combined_certificate(evidence, directory):
    directory = Path(directory)
    report = audit_combined(evidence)
    require(report["status"] == "TERMINAL_ADMITTED", f"Combined stage B not admitted: {report.get('reason')}")
    bundle = compressed(evidence)
    cert = sealed({"kind": KIND, "stage": "B", "report": report, "evidence_sha256": digest(bundle),
                   "bundle_name": "stage_B_combined_evidence.json.gz",
                   "original_submission_receipt_sha256": digest(canonical(evidence["original"]["submission_receipt"])),
                   "attempt_receipt_sha256": {n: digest(canonical(evidence["attempts"][n]["submission_receipt"])) for n in ATTEMPTS}})
    immutable(directory / cert["bundle_name"], bundle)
    immutable(directory / "STAGE_B_COMBINED_ADMISSION.json", canonical(cert))
    return cert


def load_combined_admission(path, *, expected_hash=None):
    path = Path(path)
    if expected_hash:
        require(file_hash(path) == expected_hash, "Combined admission external hash mismatch")
    cert = verify_seal(read_json(path), kind=KIND)
    require(cert["stage"] == "B" and cert["bundle_name"] == "stage_B_combined_evidence.json.gz", "Wrong combined admission")
    bundle = (path.parent / cert["bundle_name"]).read_bytes()
    require(digest(bundle) == cert["evidence_sha256"], "Combined admission evidence bundle modified")
    evidence = json.loads(gzip.decompress(bundle))
    report = audit_combined(evidence)
    require(report == cert["report"] and report["status"] == "TERMINAL_ADMITTED", "Combined admission does not reproduce")
    require(cert["original_submission_receipt_sha256"] == digest(canonical(evidence["original"]["submission_receipt"])), "Combined admission receipt anchor mismatch")
    return cert, evidence


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--family", choices=(REMOTE,), required=True)
    parser.add_argument("--collect", action="store_true", help="cluster: collect three roots and print report + evidence")
    args = parser.parse_args(argv)
    require(args.collect, "Only --collect is available on the cluster; certificates are written locally")
    try:
        evidence = collect_combined()
    except (audit.SchedulerSnapshotError, OSError, ValueError, KeyError, subprocess.SubprocessError) as exc:
        status = exc.status if isinstance(exc, audit.SchedulerSnapshotError) else (
            "STOP_INFRASTRUCTURE" if isinstance(exc, (OSError, subprocess.SubprocessError)) else "STOP_INTEGRITY")
        print(json.dumps({"report": {"status": status, "stage": "B", "reason": f"Collector did not complete: {type(exc).__name__}: {exc}", "records": []},
                          "admission_written": False, "scheduler_queries": getattr(exc, "scheduler_queries", [])}, sort_keys=True))
        raise SystemExit(2) from exc
    # Cancellation receipts live only in the local family; the remote report therefore stops at the
    # duplicate-task check by design and the complete audit is reproduced locally after attachment.
    report = audit_combined(evidence)
    print(json.dumps({"report": report, "complete_evidence_gzip_base64": base64.b64encode(compressed(evidence)).decode("ascii")}, sort_keys=True))


if __name__ == "__main__":
    main()

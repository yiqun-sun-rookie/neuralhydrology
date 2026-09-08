"""Read-only Slurm/filesystem collector and pure terminal admission audit.

Invoke on the cluster only after controller review. No weights are deserialized.
The complete transport includes metadata/log bytes and checkpoint/data hashes.
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
from pathlib import Path, PurePosixPath

import build_package as package
import deploy_remote as deploy
import launch_once as guard
from study_config import make_combos
from evidence_contract import (REMOTE, METRIC, NUMERIC_ERROR, canonical, compressed,
                               digest, file_hash, immutable, read_json, require, sealed, verify_seal)

ACTIVE = {"PENDING", "RUNNING", "CONFIGURING", "COMPLETING", "SUSPENDED", "REQUEUED", "RESIZING"}
TERMINAL = {"COMPLETED", "FAILED", "CANCELLED", "TIMEOUT", "OUT_OF_MEMORY", "NODE_FAIL", "BOOT_FAIL", "PREEMPTED", "DEADLINE", "REVOKED"}
FIELDS = ("JobID", "JobIDRaw", "State", "ExitCode", "ElapsedRaw")
IDENTITY_FIELDS = ("run_id", "index", "seed", "effective_seed")


def accounting_rows(text, parent, count):
    """Retain compressed nonterminal rows; terminal rows need real element mapping."""
    require(re.fullmatch(r"[1-9][0-9]*", str(parent)), "Invalid submitted parent")
    expanded, ranges, seen_raw = {}, [], set()
    for line in text.splitlines():
        if not line.strip():
            continue
        parts = line.rstrip("|").split("|")
        require(len(parts) == len(FIELDS), "Accounting field count mismatch")
        row = dict(zip(FIELDS, parts))
        state = row["State"].split()[0]
        require(state in ACTIVE | TERMINAL, f"Unknown scheduler state {state}")
        row["State"] = state
        match = re.fullmatch(re.escape(str(parent)) + r"_([0-9]+)", row["JobID"])
        if not match:
            pending = re.fullmatch(re.escape(str(parent)) + r"_\[([0-9,-]+)(?:%[0-9]+)?\]", row["JobID"])
            require(pending and state in ACTIVE, "Unrelated or unexpanded terminal accounting row")
            indices = []
            for piece in pending[1].split(","):
                endpoints = [int(x) for x in piece.split("-")]
                require(len(endpoints) in (1, 2), "Malformed pending range")
                indices.extend(range(endpoints[0], endpoints[-1] + 1))
            require(indices and len(set(indices)) == len(indices) and all(0 <= i < count for i in indices), "Pending range outside registered tasks")
            require(not any(set(indices) & set(r["indices"]) for r in ranges), "Duplicate pending range")
            row["indices"] = indices
            ranges.append(row)
            continue
        index = int(match[1])
        require(0 <= index < count and index not in expanded, "Duplicate or unexpected array task")
        require(re.fullmatch(r"[1-9][0-9]*", row["JobIDRaw"]), "Missing numeric element identity")
        require(row["JobIDRaw"] not in seen_raw, "Duplicate numeric element identity")
        seen_raw.add(row["JobIDRaw"])
        require(re.fullmatch(r"[0-9]+:[0-9]+", row["ExitCode"]), "Malformed exit code")
        require(row["ElapsedRaw"].isdigit(), "Missing accounting duration")
        expanded[index] = row
    for row in ranges:
        require(not set(row["indices"]) & set(expanded), "Overlapping accounting elements and ranges")
    return expanded, ranges


def expected_run(root, combo):
    lr = combo["lr"]
    label = (f"{lr:.4f}".rstrip("0").rstrip(".").replace(".", "p") if lr >= .01 else f"{lr:.0e}")
    return (root / "repo" / guard.EXPERIMENT_REL / "runs" / f"formal_seed{combo['seed']}_gpu"
            / f"idx{combo['index']:04d}_lr{label}_hs{combo['hidden_size']}_nl{combo['num_layers']}_mult{combo['in_out_mult']}")


def verify_config(cfg, base, combo):
    """Compare all scientific settings; runtime.seed=42 is explicitly unused."""
    expected = copy.deepcopy(base)
    expected["training"]["learning_rate"] = combo["lr"]
    expected["model"]["knet"].update(hidden_size=combo["hidden_size"], num_layers=combo["num_layers"],
                                        in_mult=combo["in_out_mult"], out_mult=combo["in_out_mult"])
    for section in ("training", "model", "loss", "system_model", "dataloader", "runtime", "instrumentation"):
        require(cfg.get(section) == expected[section], f"Config {section} mismatch")
    require(set(cfg["data"]["dataset_path"]) == {"train", "val"}, "Unexpected data split")
    for split, configured in cfg["data"]["dataset_path"].items():
        required = deploy.DATA_NAMES[split]
        repo = REMOTE + "/stages/" + combo["stage"] + "/repo"
        require(str(configured) == repo + "/data/processed/high_flow_aug/" + required, "YAML dataset path mismatch")
    if "__config_file__" in cfg:
        require(cfg["__config_file__"] == repo + "/" + guard.EXPERIMENT_REL.as_posix() + "/base_config.yaml", "YAML base config provenance mismatch")
    return cfg["runtime"].get("seed")


def _identity(task, combo, account, root, source, runtime):
    audit, claim = task["audit"], task["claim"]
    require(audit["combo"] == combo and audit["run_id"] == combo["run_id"] and audit["mode"] == "formal", "Audit configuration identity mismatch")
    for key in IDENTITY_FIELDS:
        require(claim.get(key) == combo[key], f"Claim {key} mismatch")
    require(claim.get("stage") == combo["stage"], "Claim stage mismatch")
    for record, job_key, task_key in ((claim, "job_id", "array_task_id"), (audit, "slurm_job_id", "slurm_array_task_id")):
        require(record.get(job_key) == account["JobIDRaw"] and record.get(task_key) == str(combo["index"]), "Numeric scheduler element identity mismatch")
    require(audit.get("expected_run_dir") == str(expected_run(root, combo)), "Run directory identity mismatch")
    require(task["run_dirs"] == [str(expected_run(root, combo))], "Missing or duplicate run directory")
    require(audit.get("held_out_test_loaded") is False, "Held-out test flag mismatch")
    require(audit.get("config_sha256") == package.BASE_CONFIG_SHA256, "Audit base configuration hash mismatch")
    require(audit.get("combos_sha256") == task["combos_sha256"], "Audit combos hash mismatch")
    require(audit.get("verified_source") == source["source_sha256"], "Audit source hash mismatch")
    for key, value in runtime.items():
        if key not in ("python_version", "numpy_version", "provenance_note"):
            require(audit["runtime"].get(key) == value, f"Audit runtime {key} mismatch")
    require(audit["runtime"].get("seed") == combo["seed"], "Effective seed mismatch")
    # The immutable wrapper has no separate runtime-guard JSON. Its claim, hashed
    # source, original audit, and Slurm stdout identity are the concrete schemas.
    marker = f"job_id={account['JobIDRaw']} array_task={combo['index']} "
    require(marker in task["slurm_stdout"], "Missing scheduler stdout identity")
    require(f"EXPECTED_RUNTIME_MATCH stage={combo['stage']}" in task["slurm_stdout"], "Wrapper environment preflight not evidenced")
    launcher = f"[Launcher] run_id={combo['run_id']} mode=formal seed={combo['seed']} combo="
    lines = [line[len(launcher):] for line in task["launcher_log"].splitlines() if line.startswith(launcher)]
    require(len(lines) == 1 and ast.literal_eval(lines[0]) == combo, "Launcher log combo identity mismatch")


def audit_task(task, combo, account, context):
    reasons = {"TIMEOUT": "BUDGET_LIMITED_NONCOMPLETION", "OUT_OF_MEMORY": "RESOURCE_LIMIT_FAILURE",
               "NODE_FAIL": "NODE_FAILURE", "BOOT_FAIL": "NODE_BOOT_FAILURE"}
    if account["State"] in reasons:
        return {"combo": combo, "outcome": "STOP", "reason": reasons[account["State"]],
                "array_identity": account["JobID"], "job_id_raw": account["JobIDRaw"],
                "accounting_seconds": account["ElapsedRaw"], "available_evidence": task}
    if task.get("launch_absent") is True:
        require(account["State"] == "FAILED" and account["ExitCode"] != "0:0", "Missing launch evidence without failed scheduler exit")
        return {"combo": combo, "outcome": "STOP", "reason": "LAUNCH_FAILURE", "available_evidence": task,
                "array_identity": account["JobID"], "job_id_raw": account["JobIDRaw"]}
    root = PurePosixPath(context["root"])
    _identity(task, combo, account, root, context["source"], context["runtime"])
    require(task["audit"].get("verified_data") == context["verified_data"], "Audit data hash/path mismatch")
    unused = verify_config(task["config"], context["base_config"], combo)
    status = account["State"]
    base = {"combo": combo, "job_id_raw": account["JobIDRaw"], "array_identity": account["JobID"],
            "accounting_seconds": account["ElapsedRaw"], "unused_yaml_runtime_seed": unused,
            "provenance": task["provenance"]}
    if status == "COMPLETED":
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
        checkpoint = str(expected_run(root, combo) / "results/best_model.pt")
        require(metrics["model_path"] == checkpoint and metrics["config_path"] == str(expected_run(root, combo) / "config_used.yaml"), "Grid config/checkpoint path mismatch")
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
        from decimal import Decimal
        require(Decimal(str(score[METRIC.split('.')[-1]])).is_finite(), "Nonfinite validation score")
        require(cell["train_seconds"] > 0, "Missing measured training duration")
        return dict(base, outcome="SUCCESS", score=str(score[METRIC.split('.')[-1]]), metric=METRIC,
                    checkpoint_path=checkpoint, checkpoint_sha256=task["checkpoint_sha256"],
                    train_seconds=cell["train_seconds"], epoch_log_summary=cell["epoch_log_summary"])
    require(account["ExitCode"] != "0:0" or status != "FAILED", "FAILED exit mismatch")
    if status == "FAILED" and task["failed_marker"] and NUMERIC_ERROR in task["failed_marker"]:
        require(task["cell"] is None and task["success_marker"] is None, "Numeric failure carries success evidence")
        exact = r"(?m)^RuntimeError: " + re.escape(NUMERIC_ERROR) + r"\s*$"
        require(re.search(exact, task["error_text"]) and re.search(exact, task["launcher_log"]), "Numeric failure error chain mismatch")
        require(re.search(r"(?m)^[^\n:]+:\s*" + re.escape(NUMERIC_ERROR) + r"\s*$", task["failed_marker"]), "Numeric FAILED error line mismatch")
        expected_error = f"failed: RuntimeError: Run returned without metrics.json: {expected_run(root, combo)}/metrics.json"
        require(task["audit"].get("launcher_status") == expected_error, "Numeric outer launcher error mismatch")
        require(task.get("metrics_present") is False, "Numeric failure carries grid metrics")
        require(re.search(r"(?m)^[^\n:]+:\s*" + str(combo["index"]) + r"\s*$", task["failed_marker"]), "FAILED marker index mismatch")
        return dict(base, outcome="NUMERIC_FAILURE", residual_checkpoint_excluded=True)
    reasons = {"TIMEOUT": "BUDGET_LIMITED_NONCOMPLETION", "OUT_OF_MEMORY": "RESOURCE_LIMIT_FAILURE",
               "NODE_FAIL": "NODE_FAILURE", "BOOT_FAIL": "NODE_BOOT_FAILURE", "FAILED": "LAUNCH_OR_EXECUTION_FAILURE"}
    return dict(base, outcome="STOP", reason=reasons.get(status, "SCHEDULER_" + status))


def audit_evidence(evidence):
    """Pure audit. Any malformed/incomplete input yields explicit integrity STOP."""
    try:
        return _audit_evidence(evidence)
    except (ValueError, KeyError, TypeError, IndexError, SyntaxError) as exc:
        return {"status": "STOP_INTEGRITY", "reason": str(exc), "stage": evidence.get("stage"), "records": []}


def _audit_evidence(e):
    stage = e["stage"]
    require(stage in ("A", "B", "C") and e["root"] == REMOTE + "/stages/" + stage, "Wrong stage root")
    rows = e["combos"]
    if stage in ("A", "B"):
        require(rows == make_combos(stage), "Registration mismatch")
    else:
        from stage_c import combos_from_lock
        require(rows == combos_from_lock(e["top_three_lock"]), "C registration mismatch")
    receipt = e["submission_receipt"]
    verify_anchors(e)
    require(receipt["stage"] == stage and receipt["stage_root"] == e["root"] and receipt["status"] == "SUBMITTED", "Submission receipt stage mismatch")
    require(receipt["array"] == f"0-{len(rows)-1}%6" and receipt["retry_authorized"] is False, "Submission policy mismatch")
    require(receipt["archive_sha256"] == e["manifest"]["archive"]["sha256"], "Submission archive mismatch")
    require(e["static_hashes"] == e["manifest"]["static_files"], "Static hash mismatch")
    require(e["protected_hashes"] == e["baseline"]["protected_files"], "Protected/reference hash mismatch")
    require(digest(canonical(e["baseline"])) == e["baseline_canonical_sha256"], "Baseline envelope mismatch")
    require(e["baseline_file_sha256"] == deploy.INPUT_HASHES["REMOTE_BASELINE.json"], "Unapproved baseline")
    require(e["data_links"] == e["expected_data_links"], "Unexpected test/data link")
    expected_links = {PurePosixPath(r["path"]).name: {"resolved": r["resolved_path"], "sha256": r["sha256"], "bytes": r["bytes"]} for r in e["baseline"]["data"].values()}
    require(e["data_links"] == expected_links, "Data identity differs from frozen baseline")
    require(e["verified_data"] == {split: {"path": r["resolved_path"], "sha256": r["sha256"]} for split, r in e["baseline"]["data"].items()}, "Verified data view differs from baseline")
    expanded, ranges = accounting_rows(e["accounting_stdout"], receipt["job_id"], len(rows))
    active = e["active_family_jobs"]
    if ranges or any(row["State"] in ACTIVE for row in expanded.values()) or active:
        states = [row["State"] for row in expanded.values()] + [row["State"] for row in ranges] + [row.get("state", "RUNNING") for row in active]
        return {"status": "RUNNING" if any(s != "PENDING" for s in states) else "PENDING",
                "stage": stage, "active_family_jobs": active, "compressed_accounting": ranges, "records": []}
    require(set(expanded) == set(range(len(rows))), "Missing terminal array tasks")
    require(set(e["tasks"]) == {str(i) for i in range(len(rows))}, "Missing/extra task evidence")
    records = [audit_task(e["tasks"][str(i)], combo, expanded[i], e) for i, combo in enumerate(rows)]
    stops = [r for r in records if r["outcome"] == "STOP"]
    return {"status": "STOP_INFRASTRUCTURE" if stops else "TERMINAL_ADMITTED", "stage": stage,
            "records": records, "stop_reasons": [r["reason"] for r in stops], "job_id": receipt["job_id"],
            "active_family_jobs": [], "metric": METRIC}


def verify_anchors(e):
    """Bind parsed views to retained original bytes and independently pinned roots."""
    import yaml
    root = PurePosixPath(e["root"])
    raw, hashes = e["metadata_base64"], e["file_hashes"]
    absent = e["absent_paths"]
    require(isinstance(absent, list) and all(isinstance(path, str) for path in absent)
            and len(absent) == len(set(absent)), "Malformed or duplicate absence evidence")
    absent = set(absent)
    require(absent.isdisjoint(raw) and absent.isdisjoint(hashes), "Retained file also declared absent")
    def content(path):
        name = str(path)
        data = base64.b64decode(raw[name], validate=True)
        require(digest(data) == hashes[name], "Parsed evidence byte hash mismatch")
        return data
    def parsed(path, value, parser=json.loads):
        data = content(path)
        require(parser(data) == value, "Parsed evidence differs from retained bytes")
        return digest(data)
    baseline_data = base64.b64decode(e["baseline_base64"], validate=True)
    require(digest(baseline_data) == deploy.INPUT_HASHES["REMOTE_BASELINE.json"] and json.loads(baseline_data) == e["baseline"], "Baseline provenance modified")
    stage = e["stage"]
    manifest_hash = parsed(root / f"STAGE_{stage}_MANIFEST.json", e["manifest"])
    pins = {"A": "d920b7a629ba97d6a2edd0ec0fd6d876142888d0d504af631a86c8898b8ae291",
            "B": "c5f8d56480510729dd14d44cb00d5e703425ebdeb837b059b674998b425784b1"}
    if stage in pins:
        require(manifest_hash == pins[stage], "Unapproved stage manifest")
    else:
        b_data = base64.b64decode(e["stage_b_manifest_base64"], validate=True)
        require(digest(b_data) == pins["B"], "C source anchor is not frozen B manifest")
        for name, sha in json.loads(b_data)["static_files"].items():
            if name not in package.REPLACED_REPO_MEMBERS and name != "hpc_array.slurm":
                require(e["static_hashes"].get(name) == sha, "C numerical or original guard bytes changed")
        require(e["manifest"].get("top_three_lock_sha256") == parsed(root / "TOP_THREE_LOCK.json", e["top_three_lock"]), "C lock differs from static manifest")
    experiment = root / "repo" / guard.EXPERIMENT_REL
    require(parsed(experiment / "base_config.yaml", e["base_config"], yaml.safe_load) == package.BASE_CONFIG_SHA256, "Frozen base config changed")
    require(parsed(root / "expected_runtime.json", e["runtime"]) == package.EXPECTED_RUNTIME_SHA256, "Frozen runtime changed")
    source_hash = parsed(experiment / "source_manifest.json", e["source"])
    require(source_hash == e["manifest"]["packaged_source_manifest"]["sha256"], "Source manifest changed")
    require(e["source"]["derived_from_archive_sha256"] == package.SOURCE_ARCHIVE_SHA256
            and e["source"]["derived_from_external_manifest_sha256"] == package.SOURCE_EXTERNAL_MANIFEST_SHA256, "Numerical source baseline mismatch")
    for rel, sha in e["source"]["source_sha256"].items():
        require(e["static_hashes"].get("repo/" + rel) == sha, "Source/static manifest mismatch")
    parsed(experiment / "combos.jsonl", e["combos"], lambda data: [json.loads(x) for x in data.splitlines()])
    receipt_hash = parsed(root / "SUBMISSION_RECEIPT.json", e["submission_receipt"])
    for name in ("AUTHORIZATION.json", "AUTHORIZED_PROTOCOL.md"):
        require(digest(content(root / name)) == deploy.INPUT_HASHES[name], "Stage authorization/protocol changed")
    controls = {name: json.loads(content(root / name)) for name in ("SUBMISSION_INTENT.json", "DEPLOYMENT_RECEIPT.json", "SUBMISSION_RESPONSE.json")}
    receipt = e["submission_receipt"]
    for name in ("SUBMISSION_INTENT.json", "DEPLOYMENT_RECEIPT.json"):
        for key in ("stage", "stage_root", "archive_sha256", "authorization_sha256", "array", "retry_authorized"):
            require(controls[name].get(key) == receipt.get(key), "Deployment intent/receipt identity mismatch")
    response = controls["SUBMISSION_RESPONSE.json"]
    require(response["returncode"] == 0 and response["exception"] is None
            and re.fullmatch(re.escape(receipt["job_id"]) + r"(?:;[^\s;]+)?", response["stdout"].strip()), "Unique submission response mismatch")
    require(content(root / "array_job_id.txt").decode().strip() == receipt["job_id"], "Array parent record mismatch")
    require(controls["SUBMISSION_INTENT.json"]["script_sha256"] == e["manifest"]["static_files"]["hpc_array.slurm"], "Submission script hash mismatch")
    if stage == "A":
        require(receipt_hash == "32429fb041d3ec653f23da15b2290bb17558592c6e279be1c2c45eef2945ed0e", "Original A unique receipt changed")
    for task in e["tasks"].values():
        if "audit" not in task:
            continue
        provenance = task["provenance"]
        parsed(PurePosixPath(provenance["audit_path"]), task["audit"])
        parsed(PurePosixPath(provenance["config_path"]), task["config"], yaml.safe_load)
        run_dir = PurePosixPath(provenance["config_path"]).parent
        combo = task["audit"]["combo"]
        parsed(root / "claims" / f"index{combo['index']:04d}.json", task["claim"])
        require(type(task["metrics_present"]) is bool, "Malformed metrics presence flag")
        for name, present in (("cell_metrics.json", task["cell"] is not None),
                              ("metrics.json", task["metrics_present"]),
                              ("SUCCESS", task["success_marker"] is not None)):
            path = run_dir / name
            key = str(path)
            require((key in raw) == (key in hashes), "Success evidence bytes/hash presence mismatch")
            require((key in raw) == present and (key in absent) == (not present),
                    "Success evidence flag/bytes/absence mismatch")
            if present:
                content(path)
        if task["cell"] is not None:
            parsed(PurePosixPath(provenance["cell_path"]), task["cell"])
            parsed(run_dir / "metrics.json", task["cell"]["grid_metrics"])
            parsed(run_dir / "results/epoch_log.jsonl", task["epochs"], lambda data: [json.loads(x) for x in data.splitlines() if x.strip()])
        require(task["checkpoint_sha256"] == hashes.get(provenance["checkpoint_path"]), "Checkpoint hash envelope mismatch")
        for key, path in (("launcher_log", experiment / "logs" / f"{combo['run_id']}_formal.stdout.log"),
                          ("slurm_stdout", root / "logs" / f"slurm-{e['submission_receipt']['job_id']}_{combo['index']}.out"),
                          ("failed_marker", run_dir / "FAILED"), ("success_marker", run_dir / "SUCCESS"), ("error_text", run_dir / "error.txt")):
            if str(path) in raw:
                require(content(path).decode("utf-8") == task[key], "Log/marker parsed bytes mismatch")
            else:
                require(task[key] in (None, ""), "Unretained marker/log")


def scheduler_snapshot(parent, run=subprocess.run):
    commands = []
    def call(args):
        response = run(args, capture_output=True, text=True, check=False, timeout=60)
        commands.append({"command": args, "returncode": response.returncode, "stdout": response.stdout, "stderr": response.stderr})
        require(response.returncode == 0, "Read-only scheduler query failed")
        return response.stdout
    fields = call(["sacct", "--helpformat"])
    require(all(re.search(r"\b" + name + r"\b", fields) for name in FIELDS), "Cluster lacks required accounting mapping fields")
    accounting = call(["sacct", "-X", "--array", "--noheader", "--parsable2", "--jobs", parent, "--format", "JobID%64,JobIDRaw%32,State%32,ExitCode,ElapsedRaw"])
    # WorkDir scopes active jobs across the entire family, not just one parent.
    queued = call(["squeue", "-r", "-h", "-u", "sunyiq", "-o", "%i|%T|%Z"])
    active = []
    for line in queued.splitlines():
        parts = line.split("|")
        require(len(parts) == 3, "Malformed queue identity/workdir")
        if parts[2] == REMOTE or parts[2].startswith(REMOTE + "/"):
            active.append({"job_id": parts[0], "state": parts[1], "workdir": parts[2]})
    return accounting, active, commands


def collect(stage, receipt_path, *, run=subprocess.run):
    """Exact deployed paths only; no arbitrary read roots or model imports."""
    import yaml
    require(stage in ("A", "B", "C"), "Invalid stage")
    root = Path(REMOTE) / "stages" / stage
    require(Path(receipt_path) == root / "SUBMISSION_RECEIPT.json", "Exact stage receipt path required")
    require(root.resolve() == root and not root.is_symlink(), "Unsafe deployed stage root")
    hashes, raw = {}, {}
    def read(path, *, text=True):
        deploy.ordinary(path, root)
        hashes[str(path)] = file_hash(path)
        if text:
            value = path.read_bytes()
            require(digest(value) == hashes[str(path)], "Evidence changed during read")
            raw[str(path)] = base64.b64encode(value).decode("ascii")
            return value.decode("utf-8")
    receipt = json.loads(read(Path(receipt_path)))
    for name in ("AUTHORIZATION.json", "AUTHORIZED_PROTOCOL.md", "SUBMISSION_INTENT.json", "DEPLOYMENT_RECEIPT.json", "SUBMISSION_RESPONSE.json", "array_job_id.txt"):
        read(root / name)
    manifest = json.loads(read(root / f"STAGE_{stage}_MANIFEST.json"))
    baseline_text = read(Path(REMOTE) / "stages/A/REMOTE_BASELINE.json") if stage == "A" else None
    if stage != "A":
        baseline_path = Path(REMOTE) / "stages/A/REMOTE_BASELINE.json"
        deploy.ordinary(baseline_path, Path(REMOTE))
        baseline_text = baseline_path.read_text(encoding="utf-8")
    require(digest(baseline_text.encode()) == deploy.INPUT_HASHES["REMOTE_BASELINE.json"], "Baseline bytes changed")
    baseline = json.loads(baseline_text)
    deploy.validate_baseline(baseline)
    protected = deploy.verify_protected(baseline)
    static = {}
    for name in manifest["static_files"]:
        path = root / str(deploy.safe_relative(name))
        read(path, text=False)
        static[name] = hashes[str(path)]
    experiment = root / "repo" / guard.EXPERIMENT_REL
    combos_text = read(experiment / "combos.jsonl")
    combos = [json.loads(line) for line in combos_text.splitlines()]
    registry = list(csv.DictReader(io.StringIO(read(experiment / "registry.csv"))))
    require(len(registry) == len(combos), "Registry count mismatch")
    for row, combo in zip(registry, combos):
        for key, value in combo.items():
            name = "initial_learning_rate" if key == "lr" else key
            require(row[name] == str(value), "Registry identity mismatch")
    source = json.loads(read(root / manifest["packaged_source_manifest"]["path"]))
    runtime = json.loads(read(root / "expected_runtime.json"))
    base = yaml.safe_load(read(experiment / "base_config.yaml"))
    links, expected_links, verified_data = {}, {}, {}
    data_dir = root / "repo/data/processed/high_flow_aug"
    for split, item in baseline["data"].items():
        path = data_dir / Path(item["path"]).name
        expected_links[path.name] = {"resolved": item["resolved_path"], "sha256": item["sha256"], "bytes": item["bytes"]}
        verified_data[split] = {"path": item["resolved_path"], "sha256": item["sha256"]}
    for path in data_dir.iterdir():
        require(path.is_symlink(), "Unexpected non-link data entry")
        links[path.name] = {"resolved": str(path.resolve()), "sha256": file_hash(path), "bytes": path.stat().st_size}
    accounting, active, queries = scheduler_snapshot(receipt["job_id"], run)
    e = {"evidence_origin": "REMOTE_READ_ONLY_COLLECTOR", "stage": stage, "root": str(root), "submission_receipt": receipt, "manifest": manifest,
         "baseline": baseline, "baseline_base64": base64.b64encode(baseline_text.encode()).decode(), "baseline_file_sha256": digest(baseline_text.encode()),
         "baseline_canonical_sha256": digest(canonical(baseline)), "protected_hashes": protected,
         "static_hashes": static, "combos": combos, "source": source, "runtime": runtime,
         "base_config": base, "data_links": links, "expected_data_links": expected_links,
         "verified_data": verified_data, "accounting_stdout": accounting, "active_family_jobs": active,
         "scheduler_queries": queries, "tasks": {}, "file_hashes": hashes, "metadata_base64": raw, "absent_paths": [],
         "collected_at_utc": datetime.now(timezone.utc).isoformat()}
    if stage == "C":
        e["top_three_lock"] = json.loads(read(root / "TOP_THREE_LOCK.json"))
        b_path = Path(REMOTE) / "stages/B/STAGE_B_MANIFEST.json"
        deploy.ordinary(b_path, Path(REMOTE))
        e["stage_b_manifest_base64"] = base64.b64encode(b_path.read_bytes()).decode()
    expanded, ranges = accounting_rows(accounting, receipt["job_id"], len(combos))
    if ranges or active or any(row["State"] in ACTIVE for row in expanded.values()):
        return e
    expected_claims = {f"index{i:04d}.json" for i in range(len(combos))}
    actual_claims = {p.name for p in (root / "claims").iterdir()} if (root / "claims").exists() else set()
    require(actual_claims <= expected_claims, "Unexpected claims")
    for combo in combos:
        index = combo["index"]
        if index in expanded and expanded[index]["State"] in {"TIMEOUT", "OUT_OF_MEMORY", "NODE_FAIL", "BOOT_FAIL"}:
            available = {}
            for suffix in ("out", "err"):
                path = root / "logs" / f"slurm-{receipt['job_id']}_{index}.{suffix}"
                if path.exists():
                    available[suffix] = read(path)
            e["tasks"][str(index)] = {"noncompletion": expanded[index]["State"], "slurm_logs": available}
            continue
        run_dir = expected_run(root, combo)
        audits = list((experiment / "audits").glob(combo["run_id"] + "_formal_*.json"))
        if not audits and not run_dir.exists() and not (root / "claims" / f"index{index:04d}.json").exists():
            available = {}
            for suffix in ("out", "err"):
                path = root / "logs" / f"slurm-{receipt['job_id']}_{index}.{suffix}"
                if path.exists():
                    available[suffix] = read(path)
            e["tasks"][str(index)] = {"launch_absent": True, "slurm_logs": available}
            continue
        require(len(audits) == 1, "Missing or duplicate launcher audits")
        def optional(path):
            if path.exists():
                return read(path)
            e["absent_paths"].append(str(path))
            return None
        audit = json.loads(read(audits[0]))
        config = yaml.safe_load(read(run_dir / "config_used.yaml"))
        cell_text = optional(run_dir / "cell_metrics.json")
        optional(run_dir / "metrics.json")
        checkpoint = run_dir / "results/best_model.pt"
        if checkpoint.exists():
            read(checkpoint, text=False)
        epoch_path = run_dir / "results/epoch_log.jsonl"
        epoch_text = optional(epoch_path)
        e["tasks"][str(index)] = {
            "audit": audit, "claim": json.loads(read(root / "claims" / f"index{index:04d}.json")),
            "config": config, "cell": json.loads(cell_text) if cell_text else None,
            "metrics_present": (run_dir / "metrics.json").exists(),
            "epochs": [json.loads(line) for line in epoch_text.splitlines() if line.strip()] if epoch_text else [],
            "checkpoint_sha256": hashes.get(str(checkpoint)),
            "run_dirs": sorted(str(p) for p in (experiment / "runs").glob(f"*/idx{index:04d}_*")),
            "combos_sha256": digest(combos_text.encode()),
            "failed_marker": optional(run_dir / "FAILED"), "success_marker": optional(run_dir / "SUCCESS"),
            "error_text": optional(run_dir / "error.txt") or "",
            "launcher_log": read(experiment / "logs" / f"{combo['run_id']}_formal.stdout.log"),
            "slurm_stdout": read(root / "logs" / f"slurm-{receipt['job_id']}_{index}.out"),
            "provenance": {"audit_path": str(audits[0]), "cell_path": str(run_dir / "cell_metrics.json"),
                           "config_path": str(run_dir / "config_used.yaml"), "checkpoint_path": str(checkpoint)}}
        optional(root / "logs" / f"slurm-{receipt['job_id']}_{index}.err")
    # Detect mutation while taking the snapshot; protected data are rechecked too.
    require(all(file_hash(Path(path)) == value for path, value in hashes.items()), "Stage evidence changed during collection")
    require(deploy.verify_protected(baseline) == protected, "Reference evidence changed during collection")
    return e


def write_certificate(evidence, directory):
    directory = Path(directory)
    report = audit_evidence(evidence)
    require(report["status"] == "TERMINAL_ADMITTED", "Stage not terminal admitted")
    bundle = compressed(evidence)
    cert = sealed({"kind": "STAGE_ADMISSION", "stage": evidence["stage"], "report": report,
                   "evidence_sha256": digest(bundle), "bundle_name": f"stage_{evidence['stage']}_evidence.json.gz",
                   "submission_receipt_sha256": digest(canonical(evidence["submission_receipt"]))})
    immutable(directory / cert["bundle_name"], bundle)
    immutable(directory / f"STAGE_{evidence['stage']}_ADMISSION.json", canonical(cert))
    return cert


def load_admission(path, stage, *, expected_hash=None, recheck_files=False):
    path = Path(path)
    if expected_hash:
        require(file_hash(path) == expected_hash, "Admission external hash mismatch")
    cert = verify_seal(read_json(path), kind="STAGE_ADMISSION")
    require(cert["stage"] == stage and cert["bundle_name"] == f"stage_{stage}_evidence.json.gz", "Wrong stage admission")
    bundle = (path.parent / cert["bundle_name"]).read_bytes()
    require(digest(bundle) == cert["evidence_sha256"], "Admission evidence bundle modified")
    evidence = json.loads(gzip.decompress(bundle))
    report = audit_evidence(evidence)
    require(report == cert["report"] and report["status"] == "TERMINAL_ADMITTED" and report["stage"] == stage, "Admission does not reproduce")
    require(cert["submission_receipt_sha256"] == digest(canonical(evidence["submission_receipt"])), "Admission receipt anchor mismatch")
    if recheck_files:
        require(evidence.get("evidence_origin") == "REMOTE_READ_ONLY_COLLECTOR", "Synthetic/offline evidence cannot authorize deployment")
        # Recollect identities and directory inventories as well as hashes.
        # Hashing just the old list would miss newly appeared duplicate runs.
        fresh = collect(stage, Path(REMOTE) / "stages" / stage / "SUBMISSION_RECEIPT.json")
        require(audit_evidence(fresh) == report, "Fresh remote audit differs; advancement paused")
        require(fresh["file_hashes"] == evidence["file_hashes"] and fresh["protected_hashes"] == evidence["protected_hashes"], "Stale admission file/reference hash")
        require(fresh["absent_paths"] == evidence["absent_paths"], "Previously absent evidence appeared")
    return cert, evidence


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--family", choices=(REMOTE,), required=True)
    parser.add_argument("--stage", choices=("A", "B", "C"), required=True)
    parser.add_argument("--receipt", type=Path, required=True)
    parser.add_argument("--certificate-directory", type=Path)
    args = parser.parse_args(argv)
    try:
        evidence = collect(args.stage, args.receipt)
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as exc:
        report = {"status": "STOP_INFRASTRUCTURE" if isinstance(exc, (OSError, subprocess.SubprocessError)) else "STOP_INTEGRITY",
                  "stage": args.stage, "reason": f"Collector did not complete: {type(exc).__name__}: {exc}", "records": []}
        print(json.dumps({"report": report, "admission_written": False}, sort_keys=True))
        raise SystemExit(2) from exc
    report = audit_evidence(evidence)
    print(json.dumps({"report": report, "complete_evidence_gzip_base64": base64.b64encode(compressed(evidence)).decode("ascii")}, sort_keys=True))
    if args.certificate_directory:
        write_certificate(evidence, args.certificate_directory)


if __name__ == "__main__":
    main()

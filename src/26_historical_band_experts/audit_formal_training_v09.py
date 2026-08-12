"""Independent integrity audit for the 24 formal version-09 training runs.

The auditor never opens meteorological arrays, training targets, formal-evaluation
observations, or a prediction service. It validates sealed bytes, training metadata,
and checkpoint structure only. Reports are written outside every sealed run.
"""
from __future__ import annotations

from collections import Counter, defaultdict
from collections.abc import Mapping, Sequence
import argparse
import json
import math
import os
from pathlib import Path
import re
import subprocess
import sys
from typing import Callable

import torch
from torch import nn

IDEA_ROOT = Path(__file__).resolve().parent
if str(IDEA_ROOT) not in sys.path:
    sys.path.insert(0, str(IDEA_ROOT))

from artifact_v09 import (  # noqa: E402
    assert_no_embedded_seal_entries,
    assert_no_reparse_tree,
    canonical_sha256,
    sha256_file,
    write_json_atomic,
)
from models_formal_v09 import build_model_v09  # noqa: E402
from train_formal_v09 import FormalRunSpecV09, load_run_order_v09  # noqa: E402

_RUN_SCHEMA = "historical_multiscale_formal_v09_main_run_v1"
_SEAL_SCHEMA = "historical_multiscale_formal_v09_main_run_seal_v1"
_CHECKPOINT_SCHEMA = "historical_multiscale_formal_v09_run_checkpoint_v1"
_AUDIT_SCHEMA = "historical_multiscale_formal_v09_training_external_audit_v1"
_CHECKPOINT_EPOCHS = (10, 20, 30)
_CHECKPOINT_FILES = tuple(f"checkpoint_epoch{epoch:03d}.pt" for epoch in _CHECKPOINT_EPOCHS)
_EXPECTED_GEOMETRY = {
    "epochs": 30,
    "batch_size": 256,
    "training_samples": 1_745_928,
    "optimizer_steps_per_epoch": 6_821,
    "optimizer_steps_total": 204_630,
}
_INPUT_BINDING_KEYS = (
    "input_seal_sha256",
    "input_external_audit_sha256",
    "trusted_source_audit_sha256",
)
_FAMILY_VARIANTS = {
    "B09-CLASSIC": "classic_lstm_256_clean",
    "B09-CAPACITY": "classic_lstm_369_capacity",
    "E09-CONTINUOUS": "continuous_multiscale_history",
}
_HISTORY_VARIANT = "continuous_multiscale_history"
_SHA256 = re.compile(r"^[0-9a-f]{64}$")
_EXPECTED_TRAINING_GIT_COMMIT = "bb519b8b9980725ac1d5f4e298d76ae80ea2c58d"
_FOUR_WORKLOAD_PREFLIGHT_JOB_ID = 201775
_FOUR_WORKLOAD_PREFLIGHT = {
    "strict_nesting_pair": (297_217, 297_217),
    "classic_lstm_256_clean": (297_217,),
    "classic_lstm_369_capacity": (595_198,),
    "continuous_multiscale_history": (596_737,),
}
_AUDIT_SOURCE_FILES = (
    "src/26_historical_band_experts/artifact_v09.py",
    "src/26_historical_band_experts/audit_formal_training_v09.py",
    "src/26_historical_band_experts/formal_training_data_v09.py",
    "src/26_historical_band_experts/models_formal_v09.py",
    "src/26_historical_band_experts/models_v03.py",
    "src/26_historical_band_experts/train_formal_v09.py",
    "src/26_historical_band_experts/configs/formal_v09_protocol.json",
    "src/26_historical_band_experts/configs/formal_v09_run_order.json",
)


class TrainingAuditError(ValueError):
    """Raised when sealed training evidence does not satisfy the frozen contract."""


def _load_json(path: Path) -> dict:
    def reject_constant(value: str):
        raise TrainingAuditError(f"non-finite JSON constant is forbidden: {value}")

    try:
        value = json.loads(path.read_text(encoding="utf-8"), parse_constant=reject_constant)
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise TrainingAuditError(f"invalid JSON artifact: {path}") from exc
    if not isinstance(value, dict):
        raise TrainingAuditError(f"JSON root must be an object: {path}")
    return value


def _require_sha256(value: object, label: str) -> str:
    if not isinstance(value, str) or _SHA256.fullmatch(value) is None:
        raise TrainingAuditError(f"{label} is not a lowercase SHA-256 digest")
    return value


def _expected_input_bindings(input_seal: Mapping) -> dict:
    if not isinstance(input_seal, Mapping):
        raise TrainingAuditError("input seal binding context must be an object")
    source = input_seal.get("input_bindings", input_seal)
    if not isinstance(source, Mapping) or set(source) != set(_INPUT_BINDING_KEYS):
        raise TrainingAuditError("input seal binding context is incomplete")
    return {key: _require_sha256(source[key], f"input binding {key}") for key in _INPUT_BINDING_KEYS}


def _validate_source_seal(source_seal: Mapping) -> dict:
    if not isinstance(source_seal, Mapping) or not source_seal:
        raise TrainingAuditError("source seal context must be a nonempty object")
    result = dict(source_seal)
    digest_fields = [key for key in result if key.endswith("sha256")]
    if not digest_fields:
        raise TrainingAuditError("source seal context contains no SHA-256 binding")
    for key in digest_fields:
        _require_sha256(result[key], f"source binding {key}")
    return result


def _verify_sealed_run(run_root: Path) -> tuple[dict, dict]:
    if not run_root.is_dir():
        raise FileNotFoundError(f"sealed training run is missing: {run_root}")
    assert_no_reparse_tree(run_root)
    seal_path = run_root / "seal.json"
    manifest_path = run_root / "manifest.json"
    if not seal_path.is_file() or not manifest_path.is_file():
        raise TrainingAuditError("training run is missing its seal or manifest")
    seal = _load_json(seal_path)
    if seal.get("schema") != _SEAL_SCHEMA or seal.get("status") != "sealed":
        raise TrainingAuditError("training run seal schema or status drift")
    sealed_files = seal.get("sealed_files")
    if not isinstance(sealed_files, list):
        raise TrainingAuditError("training run sealed-file inventory is missing")
    assert_no_embedded_seal_entries(sealed_files)
    if seal.get("sealed_files_sha256") != canonical_sha256(sealed_files):
        raise TrainingAuditError("training run sealed-file inventory hash drift")
    expected_names = (*_CHECKPOINT_FILES, "manifest.json")
    inventory_names = [item.get("relative_path") for item in sealed_files if isinstance(item, Mapping)]
    if len(inventory_names) != len(sealed_files) or set(inventory_names) != set(expected_names):
        raise TrainingAuditError("training run sealed-file inventory names drift")
    actual_names = {
        path.relative_to(run_root).as_posix()
        for path in run_root.rglob("*")
        if path.is_file() and path != seal_path
    }
    if actual_names != set(expected_names):
        raise TrainingAuditError("training run directory inventory drift")
    for entry in sealed_files:
        if set(entry) != {"relative_path", "size_bytes", "sha256"}:
            raise TrainingAuditError("training run sealed-file descriptor drift")
        relative = entry["relative_path"]
        path = run_root / relative
        if not path.is_file() or path.stat().st_size != entry["size_bytes"]:
            raise TrainingAuditError(f"sealed file drift (size): {relative}")
        if sha256_file(path) != entry["sha256"]:
            raise TrainingAuditError(f"sealed file drift: {relative}")
    if seal.get("manifest_sha256") != sha256_file(manifest_path):
        raise TrainingAuditError("training run manifest hash drift")
    return seal, _load_json(manifest_path)


def _finite_number(value: object, label: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(float(value)):
        raise TrainingAuditError(f"{label} must be finite")
    return float(value)


def _validate_epoch_trace(manifest: Mapping) -> tuple[list[dict], list[str]]:
    trace = manifest.get("epoch_trace")
    if not isinstance(trace, list) or len(trace) != _EXPECTED_GEOMETRY["epochs"]:
        raise TrainingAuditError("training epoch trace length drift")
    permutation_hashes = []
    losses = []
    for epoch, row in enumerate(trace, start=1):
        if not isinstance(row, Mapping) or row.get("epoch") != epoch:
            raise TrainingAuditError(f"training epoch trace numbering drift at epoch {epoch}")
        if row.get("optimizer_steps") != _EXPECTED_GEOMETRY["optimizer_steps_per_epoch"]:
            raise TrainingAuditError(f"training optimizer steps drift at epoch {epoch}")
        expected_learning_rate = 0.001 if epoch <= 10 else (0.0005 if epoch <= 20 else 0.0001)
        if row.get("learning_rate") != expected_learning_rate:
            raise TrainingAuditError(f"training learning-rate schedule drift at epoch {epoch}")
        losses.append(_finite_number(row.get("mean_training_loss"), f"training loss at epoch {epoch}"))
        permutation_hashes.append(
            _require_sha256(row.get("permutation_sha256"), f"permutation at epoch {epoch}"))
    if losses[-1] >= losses[0]:
        raise TrainingAuditError("final training loss is not below first-epoch training loss")
    return [dict(row) for row in trace], permutation_hashes


def _validate_history_health(manifest: Mapping, *, history_model: bool) -> None:
    trace = manifest.get("history_health_trace")
    awake = manifest.get("history_encoder_first_nonzero_gradient_step")
    if not history_model:
        if trace != [] or awake is not None:
            raise TrainingAuditError("recent-only run contains history-gradient evidence")
        return
    if not isinstance(trace, list) or len(trace) < 2:
        raise TrainingAuditError("continuous-history run is missing history-gradient evidence")
    first = trace[0]
    if not isinstance(first, Mapping) or first.get("step") != 1:
        raise TrainingAuditError("first history-gradient record is not optimizer step 1")
    if first.get("gate_absolute_maximum") != 0.0:
        raise TrainingAuditError("history gates are not exactly zero at optimizer step 1")
    if first.get("history_encoder_gradient_norm") != 0.0:
        raise TrainingAuditError("history encoder gradient is not exactly zero at optimizer step 1")
    gate_gradient = _finite_number(first.get("gate_gradient_norm"), "history gate gradient at step 1")
    if gate_gradient <= 0.0:
        raise TrainingAuditError("history gate gradient is not positive at optimizer step 1")
    if first.get("gate_gradients_present") is not True or first.get("history_encoder_gradients_present") is not True:
        raise TrainingAuditError("history gradient tensors were not recorded at optimizer step 1")
    if isinstance(awake, bool) or not isinstance(awake, int) or not 1 < awake <= 3:
        raise TrainingAuditError("history encoder did not receive a nonzero gradient by optimizer step 3")
    awake_records = [row for row in trace if isinstance(row, Mapping) and row.get("step") == awake]
    if not awake_records:
        raise TrainingAuditError("history wake-step evidence is absent")
    if _finite_number(
            awake_records[0].get("history_encoder_gradient_norm"), "history wake gradient") <= 0.0:
        raise TrainingAuditError("history wake gradient is not positive")
    for index, row in enumerate(trace):
        if not isinstance(row, Mapping):
            raise TrainingAuditError(f"history-gradient record {index} is not an object")
        for key, value in row.items():
            if key.endswith("norm") or key.endswith("maximum"):
                _finite_number(value, f"history-gradient record {index} field {key}")


def _validate_manifest(
    manifest: Mapping,
    expected_spec: FormalRunSpecV09,
    expected_bindings: Mapping,
) -> tuple[list[dict], list[str]]:
    if manifest.get("schema") != _RUN_SCHEMA or manifest.get("status") != "formal_training_complete":
        raise TrainingAuditError("training manifest schema or status drift")
    if manifest.get("formal_execution") is not True:
        raise TrainingAuditError("training manifest is not a formal execution")
    identity = {
        "variant": expected_spec.variant,
        "seed": expected_spec.seed,
        "trainable_parameters": expected_spec.trainable_parameters,
    }
    for key, expected in (*_EXPECTED_GEOMETRY.items(), *identity.items()):
        if manifest.get(key) != expected:
            raise TrainingAuditError(f"training manifest {key} drift")
    if manifest.get("checkpoint_epochs") != list(_CHECKPOINT_EPOCHS):
        raise TrainingAuditError("training checkpoint epochs drift")
    if manifest.get("checkpoint_files") != list(_CHECKPOINT_FILES):
        raise TrainingAuditError("training checkpoint file order drift")
    if manifest.get("validation_metrics_computed") is not False:
        raise TrainingAuditError("training validation metrics were computed prematurely")
    if manifest.get("formal_evaluation_observation_reads") != 0:
        raise TrainingAuditError("formal evaluation observation access occurred during training")
    if manifest.get("formal_period_predictions_generated") is not False:
        raise TrainingAuditError("formal-period prediction was generated during training")
    if manifest.get("input_bindings") != dict(expected_bindings):
        raise TrainingAuditError("training input binding drift")
    dropout = manifest.get("dropout_rng_binding")
    if not isinstance(dropout, Mapping):
        raise TrainingAuditError("training dropout random-state binding is missing")
    if dropout.get("dropout_seed") != expected_spec.seed * 1_000_003 + 900_001:
        raise TrainingAuditError("training dropout seed drift")
    _require_sha256(dropout.get("cpu_state_sha256"), "dropout CPU state")
    _require_sha256(dropout.get("cuda_state_sha256"), "dropout CUDA state")
    trace, permutations = _validate_epoch_trace(manifest)
    _validate_history_health(manifest, history_model=expected_spec.variant == _HISTORY_VARIANT)
    return trace, permutations


def _check_finite_tree(value: object, label: str) -> int:
    if isinstance(value, torch.Tensor):
        if not bool(torch.isfinite(value).all()):
            raise TrainingAuditError(f"checkpoint contains a non-finite tensor: {label}")
        return 1
    if isinstance(value, Mapping):
        return sum(_check_finite_tree(item, f"{label}.{key}") for key, item in value.items())
    if isinstance(value, (list, tuple)):
        return sum(_check_finite_tree(item, f"{label}[{index}]") for index, item in enumerate(value))
    if isinstance(value, float) and not math.isfinite(value):
        raise TrainingAuditError(f"checkpoint contains a non-finite scalar: {label}")
    return 0


def _audit_checkpoint(
    path: Path,
    *,
    epoch: int,
    permutation_sha256: str,
    expected_spec: FormalRunSpecV09,
    model_builder: Callable[[str, int], nn.Module],
) -> dict:
    try:
        checkpoint = torch.load(path, map_location="cpu", weights_only=False)
    except Exception as exc:
        raise TrainingAuditError(f"training checkpoint cannot be loaded: {path.name}") from exc
    expected_keys = {
        "schema",
        "epoch",
        "model_state_dict",
        "optimizer_state_dict",
        "permutation_sha256",
    }
    if not isinstance(checkpoint, Mapping) or set(checkpoint) != expected_keys:
        raise TrainingAuditError(f"training checkpoint structure drift at epoch {epoch}")
    if checkpoint.get("schema") != _CHECKPOINT_SCHEMA or checkpoint.get("epoch") != epoch:
        raise TrainingAuditError(f"training checkpoint identity drift at epoch {epoch}")
    if checkpoint.get("permutation_sha256") != permutation_sha256:
        raise TrainingAuditError(f"training checkpoint permutation drift at epoch {epoch}")
    tensor_count = _check_finite_tree(checkpoint, f"checkpoint_epoch{epoch:03d}")
    model = model_builder(expected_spec.variant, expected_spec.seed).cpu()
    trainable = sum(parameter.numel() for parameter in model.parameters() if parameter.requires_grad)
    if trainable != expected_spec.trainable_parameters:
        raise TrainingAuditError(f"rebuilt model parameter count drift at epoch {epoch}")
    try:
        model.load_state_dict(checkpoint["model_state_dict"], strict=True)
        optimizer = torch.optim.Adam(model.parameters(), lr=0.001)
        optimizer.load_state_dict(checkpoint["optimizer_state_dict"])
    except (KeyError, RuntimeError, ValueError) as exc:
        raise TrainingAuditError(f"training checkpoint model or optimizer structure drift at epoch {epoch}") from exc
    return {
        "epoch": epoch,
        "relative_path": path.name,
        "sha256": sha256_file(path),
        "size_bytes": path.stat().st_size,
        "finite_tensor_count": tensor_count,
        "not_eligible_for_formal_prediction": epoch != 30,
        "eligible_for_formal_prediction": epoch == 30,
    }


def audit_training_run_v09(
    run_root: str | Path,
    expected_spec: FormalRunSpecV09,
    input_seal: Mapping,
    source_seal: Mapping,
    *,
    model_builder: Callable[[str, int], nn.Module] = build_model_v09,
) -> dict:
    """Rehash one sealed run and validate all checkpoint bytes without inference."""
    run_root = Path(os.path.abspath(run_root)).resolve()
    if run_root.name.endswith((".building", ".failed")):
        raise TrainingAuditError("training audit cannot accept an unfinished run directory")
    expected_bindings = _expected_input_bindings(input_seal)
    source_context = _validate_source_seal(source_seal)
    seal, manifest = _verify_sealed_run(run_root)
    trace, permutations = _validate_manifest(manifest, expected_spec, expected_bindings)
    checkpoints = []
    trace_by_epoch = {row["epoch"]: row for row in trace}
    for epoch, filename in zip(_CHECKPOINT_EPOCHS, _CHECKPOINT_FILES):
        checkpoints.append(
            _audit_checkpoint(
                run_root / filename,
                epoch=epoch,
                permutation_sha256=trace_by_epoch[epoch]["permutation_sha256"],
                expected_spec=expected_spec,
                model_builder=model_builder,
            ))
    return {
        "schema": "historical_multiscale_formal_v09_training_run_audit_v1",
        "status": "training_run_audit_passed",
        "position": expected_spec.position,
        "run_id": expected_spec.run_id,
        "family": expected_spec.family,
        "variant": expected_spec.variant,
        "seed": expected_spec.seed,
        "run_root": str(run_root),
        "run_seal_sha256": sha256_file(run_root / "seal.json"),
        "run_manifest_sha256": sha256_file(run_root / "manifest.json"),
        "source_context_sha256": canonical_sha256(source_context),
        "input_bindings": expected_bindings,
        "dropout_rng_binding": dict(manifest["dropout_rng_binding"]),
        "permutation_sha256": permutations,
        "checkpoint_epochs_verified": list(_CHECKPOINT_EPOCHS),
        "checkpoints": checkpoints,
        "intermediate_checkpoints": checkpoints[:2],
        "final_checkpoint": checkpoints[2],
        "nonfinite_tensor_count": 0,
        "validation_metrics_computed": False,
        "formal_evaluation_observation_reads": 0,
        "formal_period_predictions_generated": False,
        "model_forward_executed": False,
    }


def validate_training_suite_records_v09(records: Sequence[Mapping]) -> dict:
    """Validate count, identities, paired random streams, and common input binding."""
    if not isinstance(records, Sequence) or isinstance(records, (str, bytes)) or len(records) != 24:
        raise TrainingAuditError("training suite must contain exactly 24 run records")
    records = [dict(record) for record in records]
    if [record.get("position") for record in records] != list(range(1, 25)):
        raise TrainingAuditError("training suite position order drift")
    run_ids = [record.get("run_id") for record in records]
    if any(not isinstance(run_id, str) for run_id in run_ids) or len(set(run_ids)) != 24:
        raise TrainingAuditError("training suite run identifier is missing or duplicated")
    family_counts = Counter(record.get("family") for record in records)
    seed_counts = Counter(record.get("seed") for record in records)
    if family_counts != Counter({family: 8 for family in _FAMILY_VARIANTS}):
        raise TrainingAuditError("training suite family coverage drift")
    if set(seed_counts.values()) != {3} or len(seed_counts) != 8:
        raise TrainingAuditError("training suite seed coverage drift")
    for record in records:
        family = record.get("family")
        if record.get("variant") != _FAMILY_VARIANTS.get(family):
            raise TrainingAuditError("training suite family and variant identity drift")
        if record.get("run_id") != f"{family}-S{record.get('seed')}":
            raise TrainingAuditError("training suite run identity drift")
        permutations = record.get("permutation_sha256")
        if not isinstance(permutations, list) or len(permutations) != 30:
            raise TrainingAuditError("training suite permutation coverage drift")
        for index, digest in enumerate(permutations, start=1):
            _require_sha256(digest, f"run permutation {index}")
        dropout = record.get("dropout_rng_binding")
        if not isinstance(dropout, Mapping):
            raise TrainingAuditError("training suite dropout binding is missing")
        _expected_input_bindings(record.get("input_bindings", {}))
        _require_sha256(record.get("run_seal_sha256"), "run seal")
    by_seed: dict[int, list[dict]] = defaultdict(list)
    for record in records:
        by_seed[int(record["seed"])].append(record)
    for seed, group in by_seed.items():
        if len(group) != 3:
            raise TrainingAuditError(f"training suite seed {seed} does not have three model families")
        if not all(record["permutation_sha256"] == group[0]["permutation_sha256"] for record in group[1:]):
            raise TrainingAuditError(f"training suite seed {seed} permutation hashes differ across families")
        if not all(record["dropout_rng_binding"] == group[0]["dropout_rng_binding"] for record in group[1:]):
            raise TrainingAuditError(f"training suite seed {seed} dropout random states differ across families")
    first_bindings = records[0]["input_bindings"]
    if not all(record["input_bindings"] == first_bindings for record in records[1:]):
        raise TrainingAuditError("training suite input bindings differ across runs")
    return {
        "run_count": 24,
        "family_counts": dict(sorted(family_counts.items())),
        "seed_counts": {str(key): seed_counts[key] for key in sorted(seed_counts)},
        "same_seed_permutations": True,
        "same_seed_dropout_rng": True,
        "all_input_bindings_identical": True,
    }


def _production_input_bindings(formal_root: Path) -> dict:
    seal_path = formal_root / "input_attempt_01/seal.json"
    external_path = formal_root / "input_attempt_01.external_audit.json"
    trusted_path = formal_root / "input_attempt_01.trusted_source_external_audit.json"
    seal = _load_json(seal_path)
    external = _load_json(external_path)
    trusted = _load_json(trusted_path)
    if seal.get("status") != "sealed":
        raise TrainingAuditError("complete input seal status drift")
    if external.get("status") != "complete_input_audit_passed":
        raise TrainingAuditError("complete input external audit status drift")
    if trusted.get("status") != "complete_trusted_training_target_audit":
        raise TrainingAuditError("trusted training-target source audit status drift")
    return {
        "input_seal_sha256": sha256_file(seal_path),
        "input_external_audit_sha256": sha256_file(external_path),
        "trusted_source_audit_sha256": sha256_file(trusted_path),
    }


def _run_git(repo_root: Path, *arguments: str) -> str:
    completed = subprocess.run(
        ["git", "-C", str(repo_root), *arguments],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="surrogateescape",
        check=False,
    )
    if completed.returncode != 0:
        raise TrainingAuditError(f"Git source query failed: {' '.join(arguments)}")
    return completed.stdout


def _tracked_git_files(repo_root: Path) -> tuple[str, ...]:
    return tuple(value for value in _run_git(repo_root, "ls-files", "-z").split("\0") if value)


def _audit_source_context() -> dict:
    """Bind the exact executable audit sources independently of the frozen training checkout."""
    repo_root = IDEA_ROOT.parents[1]
    descriptors = []
    for relative in _AUDIT_SOURCE_FILES:
        path = repo_root / relative
        if not path.is_file():
            raise TrainingAuditError(f"training audit source file is missing: {relative}")
        descriptors.append({
            "relative_path": relative,
            "size_bytes": path.stat().st_size,
            "sha256": sha256_file(path),
        })
    commit = _run_git(repo_root, "rev-parse", "HEAD").strip().lower()
    tree = _run_git(repo_root, "rev-parse", "HEAD^{tree}").strip().lower()
    tracked_status = _run_git(repo_root, "status", "--porcelain", "--untracked-files=no").strip()
    return {
        "schema": "historical_multiscale_formal_v09_training_audit_source_v1",
        "git_commit": commit,
        "git_tree": tree,
        "tracked_source_clean": tracked_status == "",
        "file_count": len(descriptors),
        "files": descriptors,
        "source_tree_sha256": canonical_sha256(descriptors),
    }


def _production_source_seal(formal_root: Path) -> dict:
    """Bind the unchanged training checkout and the environment used by the auditor."""
    from artifact_v09 import environment_fingerprint_v09

    repo_root = formal_root.parents[2]
    commit = _run_git(repo_root, "rev-parse", "HEAD").strip().lower()
    if commit != _EXPECTED_TRAINING_GIT_COMMIT:
        raise TrainingAuditError("frozen main-training Git commit drift")
    if _run_git(repo_root, "status", "--porcelain", "--untracked-files=no").strip():
        raise TrainingAuditError("frozen main-training checkout has tracked modifications")
    tracked = _tracked_git_files(repo_root)
    if not tracked:
        raise TrainingAuditError("frozen main-training checkout has no tracked files")
    descriptors = []
    for relative in tracked:
        path = repo_root / relative
        if not path.is_file():
            raise TrainingAuditError(f"tracked main-training source file is missing: {relative}")
        descriptors.append({
            "relative_path": Path(relative).as_posix(),
            "size_bytes": path.stat().st_size,
            "sha256": sha256_file(path),
        })
    environment = environment_fingerprint_v09(repo_root)
    if environment.get("git_head", "").lower() != commit or environment.get("git_clean") is not True:
        raise TrainingAuditError("frozen main-training checkout environment is not clean or commit-bound")
    return {
        "training_git_commit": commit,
        "tracked_file_count": len(descriptors),
        "source_tree_sha256": canonical_sha256(descriptors),
        "environment": environment,
        "environment_sha256": canonical_sha256(environment),
    }


def _resolve_specs(run_order: str | Path | Sequence[FormalRunSpecV09]) -> tuple[FormalRunSpecV09, ...]:
    if isinstance(run_order, (str, Path)):
        return load_run_order_v09(run_order)
    if not isinstance(run_order, Sequence) or isinstance(run_order, (str, bytes)):
        raise TrainingAuditError("training run order must be a path or a sequence")
    specs = tuple(run_order)
    if len(specs) != 24 or [getattr(spec, "position", None) for spec in specs] != list(range(1, 25)):
        raise TrainingAuditError("training run order must contain exactly 24 ordered specifications")
    run_ids = [getattr(spec, "run_id", None) for spec in specs]
    if len(set(run_ids)) != 24 or None in run_ids:
        raise TrainingAuditError("training run order identifiers are duplicated or missing")
    return specs


def _expected_run_dirs(formal_root: Path, specs: Sequence[FormalRunSpecV09]) -> dict[str, Path]:
    result = {}
    for spec in specs:
        family_directory = Path(spec.results_root).name
        run_dir = formal_root / family_directory / f"seed_{spec.seed}"
        if run_dir in result.values():
            raise TrainingAuditError("training run order maps two specifications to one directory")
        result[spec.run_id] = run_dir
    return result


def _verify_suite_directory_coverage(formal_root: Path, expected: Mapping[str, Path]) -> None:
    family_directories = {path.parent for path in expected.values()}
    actual = {
        path
        for family_root in family_directories
        if family_root.is_dir()
        for path in family_root.iterdir()
        if path.is_dir() and path.name.startswith("seed_")
    }
    if actual != set(expected.values()):
        raise TrainingAuditError("training run directory coverage has missing or extra entries")
    transient = [
        path
        for family_root in family_directories
        if family_root.is_dir()
        for path in family_root.iterdir()
        if path.name.endswith((".building", ".failed"))
    ]
    if transient:
        raise TrainingAuditError("unfinished or failed training run directory is present")
    if (formal_root / "training_attempt_01.failure.json").exists():
        raise TrainingAuditError("training failure receipt is present")


def _validate_training_progress(formal_root: Path, specs: Sequence[FormalRunSpecV09]) -> dict:
    path = formal_root / "training_progress.json"
    progress = _load_json(path)
    if progress.get("schema") != "historical_multiscale_formal_v09_training_progress_v1":
        raise TrainingAuditError("training progress ledger schema drift")
    state = progress.get("progress")
    expected_ids = [spec.run_id for spec in specs]
    if not isinstance(state, Mapping) or state.get("total") != 24:
        raise TrainingAuditError("training progress ledger total drift")
    if state.get("completed") != expected_ids or state.get("pending") != [] or state.get("dirty") != []:
        raise TrainingAuditError("training progress ledger is incomplete or order-bound evidence drifted")
    return {
        "path": str(path.resolve()),
        "sha256": sha256_file(path),
        "completed_run_count": len(expected_ids),
    }


def _reject_premature_downstream_artifacts(formal_root: Path, report_path: Path) -> None:
    if (formal_root / "training_seal.json").exists():
        raise TrainingAuditError("training seal exists before the external training audit")
    forbidden_exact = (
        "prediction_seal.json",
        "prediction_external_audit.json",
        "official_score.json",
        "scoring_authorization_consumed.json",
    )
    for name in forbidden_exact:
        if (formal_root / name).exists():
            raise TrainingAuditError(f"premature downstream artifact is present: {name}")
    if report_path.exists():
        raise FileExistsError(f"training external audit already exists: {report_path}")


def _recompute_permutation_hashes(records: Sequence[Mapping]) -> int:
    from formal_training_data_v09 import epoch_order_v09, permutation_sha256_v09

    representative = {}
    for record in records:
        representative.setdefault(int(record["seed"]), record)
    count = 0
    for seed, record in sorted(representative.items()):
        expected = [
            permutation_sha256_v09(epoch_order_v09(1_745_928, seed=seed, epoch=epoch))
            for epoch in range(1, 31)
        ]
        count += len(expected)
        if record["permutation_sha256"] != expected:
            raise TrainingAuditError(f"training permutation hashes do not reproduce for seed {seed}")
    return count


def audit_training_suite_v09(
    formal_root: str | Path,
    run_order: str | Path | Sequence[FormalRunSpecV09],
    report_path: str | Path,
    *,
    model_builder: Callable[[str, int], nn.Module] = build_model_v09,
    source_seal: Mapping | None = None,
    recompute_permutations: bool | None = None,
) -> dict:
    """Audit all 24 sealed runs and publish one report outside the run directories."""
    formal_root = Path(os.path.abspath(formal_root)).resolve()
    report_path = Path(os.path.abspath(report_path)).resolve()
    if not formal_root.is_dir():
        raise FileNotFoundError(f"formal training root is missing: {formal_root}")
    assert_no_reparse_tree(formal_root)
    if report_path.parent != formal_root:
        raise TrainingAuditError("training external audit must be a direct child outside every sealed run")
    if report_path.name != "training_external_audit.json":
        raise TrainingAuditError("training external audit filename drift")
    specs = _resolve_specs(run_order)
    expected_dirs = _expected_run_dirs(formal_root, specs)
    _reject_premature_downstream_artifacts(formal_root, report_path)
    _verify_suite_directory_coverage(formal_root, expected_dirs)
    progress = _validate_training_progress(formal_root, specs)
    input_bindings = _production_input_bindings(formal_root)
    source_context = _validate_source_seal(source_seal or _production_source_seal(formal_root))
    audit_source_context = _audit_source_context()
    if model_builder is build_model_v09 and audit_source_context["tracked_source_clean"] is not True:
        raise TrainingAuditError("training audit checkout has tracked source modifications")
    records = []
    for spec in specs:
        records.append(
            audit_training_run_v09(
                expected_dirs[spec.run_id],
                spec,
                input_bindings,
                source_context,
                model_builder=model_builder,
            ))
    if [record["run_id"] for record in records] != [spec.run_id for spec in specs]:
        raise TrainingAuditError("training audit run order drift")
    cross_run = validate_training_suite_records_v09(records)
    if recompute_permutations is None:
        recompute_permutations = model_builder is build_model_v09
    recomputed = _recompute_permutation_hashes(records) if recompute_permutations else 0
    spec_payload = [
        {
            "position": spec.position,
            "seed": spec.seed,
            "family": spec.family,
            "run_id": spec.run_id,
            "variant": spec.variant,
            "trainable_parameters": spec.trainable_parameters,
            "results_root": spec.results_root,
        }
        for spec in specs
    ]
    canonical_preflight_present = (
        formal_root / "training_resource_preflight.external_audit.json").is_file()
    report = {
        "schema": _AUDIT_SCHEMA,
        "status": "complete_training_audit",
        "formal_root": str(formal_root),
        "run_order_canonical_sha256": canonical_sha256(spec_payload),
        "input_bindings": input_bindings,
        "source_context": source_context,
        "source_context_sha256": canonical_sha256(source_context),
        "audit_source_context": audit_source_context,
        "audit_source_context_sha256": canonical_sha256(audit_source_context),
        "coverage": {"expected_runs": 24, "audited_runs": len(records), "passed_runs": len(records)},
        "training_progress": progress,
        "cross_run_checks": cross_run,
        "permutation_hashes_recomputed": recomputed,
        "pre_seal_evidence": {
            "canonical_four_workload_resource_preflight_report_present": canonical_preflight_present,
            "known_blockers": (
                []
                if canonical_preflight_present
                else ["canonical_four_workload_resource_preflight_report_missing"]
            ),
        },
        "runs": records,
        "all_checkpoint_tensors_finite": True,
        "validation_metrics_computed": False,
        "formal_evaluation_observation_reads": 0,
        "formal_period_predictions_generated": False,
        "official_score_called": False,
    }
    write_json_atomic(report_path, report)
    return report


def _artifact_record(path: Path, *, expected_status: str | None) -> dict:
    if not path.is_file():
        raise FileNotFoundError(f"required training-seal dependency is missing: {path}")
    record = {
        "path": str(path.resolve()),
        "sha256": sha256_file(path),
        "required_status": expected_status,
    }
    if expected_status is not None:
        payload = _load_json(path)
        if payload.get("status") != expected_status:
            raise TrainingAuditError(f"training-seal dependency status drift: {path.name}")
    return record


def _infer_upstream_root(formal_root: Path) -> Path:
    training_repo = formal_root.parents[2]
    base = training_repo.parent.parent
    return base / "neuralhydrology/results/26_historical_band_experts/formal_v09"


def _validate_four_workload_preflight_evidence(upstream_root: Path) -> dict:
    """Bind the original pre-training, two-process GPU evidence left by Slurm job 201775."""
    try:
        evidence_root = upstream_root.parents[3]
    except IndexError as exc:
        raise TrainingAuditError("four-workload resource preflight root cannot be inferred") from exc
    stdout_path = evidence_root / f"logs/preflight_{_FOUR_WORKLOAD_PREFLIGHT_JOB_ID}.out"
    stderr_path = evidence_root / f"logs/preflight_{_FOUR_WORKLOAD_PREFLIGHT_JOB_ID}.err"
    if not stdout_path.is_file() or not stderr_path.is_file():
        raise FileNotFoundError("four-workload resource preflight Slurm logs are missing")
    if stdout_path.stat().st_size > 1_000_000:
        raise TrainingAuditError("four-workload resource preflight log is unexpectedly large")
    if stderr_path.stat().st_size != 0:
        raise TrainingAuditError("four-workload resource preflight standard error is not empty")
    try:
        text = stdout_path.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as exc:
        raise TrainingAuditError("four-workload resource preflight log is not valid UTF-8") from exc
    required_lines = {
        "=== REAL GPU PREFLIGHT: 4 workloads x 2 fresh subprocesses, batch 256, window 3562 ===",
        (
            'profile: {"batch_size": 256, "features": 5, "recent_days": 270, '
            '"statics": 27, "window_days": 3562}'
        ),
        "ALL_WORKLOADS_IDENTICAL: True",
    }
    lines = text.splitlines()
    if not required_lines.issubset(set(lines)):
        raise TrainingAuditError("four-workload resource preflight completion markers drift")
    workload_rows = {}
    for name, parameters in _FOUR_WORKLOAD_PREFLIGHT.items():
        parameter_text = ", ".join(str(value) for value in parameters)
        pattern = re.compile(
            rf"^{re.escape(name)}\s+identical=True params=\[{re.escape(parameter_text)}\] "
            r"peak_alloc=(\d+)MiB peak_reserved=(\d+)MiB pids=\[(\d+), (\d+)\]$"
        )
        matches = [pattern.fullmatch(line) for line in lines]
        matches = [match for match in matches if match is not None]
        if len(matches) != 1:
            raise TrainingAuditError(f"four-workload resource preflight row drift: {name}")
        match = matches[0]
        workload_rows[name] = {
            "trainable_parameters": list(parameters),
            "arrays_identical": True,
            "peak_allocated_mib": int(match.group(1)),
            "peak_reserved_mib": int(match.group(2)),
            "process_ids": [int(match.group(3)), int(match.group(4))],
        }
    process_ids = [pid for row in workload_rows.values() for pid in row["process_ids"]]
    if len(set(process_ids)) != 8 or any(pid <= 0 for pid in process_ids):
        raise TrainingAuditError("four-workload resource preflight did not use eight distinct processes")
    maximum_reserved = max(row["peak_reserved_mib"] for row in workload_rows.values())
    if maximum_reserved != 1_610:
        raise TrainingAuditError("four-workload resource preflight memory evidence drift")
    determinism_lines = [line.removeprefix("determinism: ") for line in lines if line.startswith("determinism: ")]
    if len(determinism_lines) != 1:
        raise TrainingAuditError("four-workload resource preflight determinism evidence drift")
    try:
        determinism = json.loads(determinism_lines[0])
    except json.JSONDecodeError as exc:
        raise TrainingAuditError("four-workload resource preflight determinism JSON is invalid") from exc
    expected_determinism = {
        "cublas_workspace_config": ":4096:8",
        "cudnn_benchmark": False,
        "cudnn_deterministic": True,
        "deterministic_algorithms_requested": True,
    }
    if determinism != expected_determinism:
        raise TrainingAuditError("four-workload resource preflight determinism settings drift")
    completed = [line.removeprefix("done=") for line in lines if line.startswith("done=")]
    if completed != ["2026-08-07T21:41:20+08:00"]:
        raise TrainingAuditError("four-workload resource preflight completion time drift")
    return {
        "evidence_kind": "pre_training_synthetic_four_workload_two_process_gpu_check",
        "slurm_job_id": _FOUR_WORKLOAD_PREFLIGHT_JOB_ID,
        "completed_at": completed[0],
        "workload_count": 4,
        "process_count": 8,
        "all_arrays_identical": True,
        "maximum_peak_reserved_mib": maximum_reserved,
        "determinism": determinism,
        "workloads": workload_rows,
        "stdout": _artifact_record(stdout_path, expected_status=None),
        "stderr": _artifact_record(stderr_path, expected_status=None),
    }


def _validate_canonical_resource_preflight_report(formal_root: Path, protocol_path: Path) -> dict:
    """Require the pre-training report promised by the frozen implementation plan."""
    from formal_v09_protocol import load_protocol_v09

    path = formal_root / "training_resource_preflight.external_audit.json"
    report = _load_json(path)
    if (report.get("schema") != "historical_multiscale_formal_v09_resource_preflight_v1" or
            report.get("status") != "complete_resource_preflight"):
        raise TrainingAuditError("canonical four-workload resource preflight schema or status drift")
    expected_profile = {
        "batch_size": 256,
        "features": 5,
        "recent_days": 270,
        "statics": 27,
        "window_days": 3_562,
    }
    if (report.get("device") != "cuda:0" or report.get("profile") != expected_profile or
            report.get("workload_count") != 4 or report.get("opened_formal_inputs") is not False or
            report.get("wrote_formal_outputs") is not False):
        raise TrainingAuditError("canonical four-workload resource preflight contract drift")
    protocol = load_protocol_v09(protocol_path)
    if report.get("protocol_canonical_sha256") != canonical_sha256(protocol):
        raise TrainingAuditError("canonical four-workload resource preflight protocol binding drift")
    expected_models = {
        "strict_nesting_pair": (
            ("classic_lstm_256_clean", 297_217),
            ("nested_history_disabled", 297_217),
        ),
        "classic_lstm_256_clean": (("classic_lstm_256_clean", 297_217),),
        "classic_lstm_369_capacity": (("classic_lstm_369_capacity", 595_198),),
        "continuous_multiscale_history": (("continuous_multiscale_history", 596_737),),
    }
    workloads = report.get("workloads")
    if not isinstance(workloads, list) or [row.get("workload") for row in workloads] != list(expected_models):
        raise TrainingAuditError("canonical four-workload resource preflight workload order drift")
    expected_determinism = {
        "cublas_workspace_config": ":4096:8",
        "cuda_matmul_allow_tf32": False,
        "cudnn_allow_tf32": False,
        "cudnn_benchmark": False,
        "cudnn_deterministic": True,
        "deterministic_algorithms_requested": True,
    }
    process_ids = []
    for row in workloads:
        name = row["workload"]
        expected_shapes = (
            {"windows": [256, 3_562, 5]}
            if name == "continuous_multiscale_history"
            else {"recent": [256, 270, 5]}
        )
        if (row.get("input_shapes") != expected_shapes or row.get("arrays_identical") is not True or
                row.get("determinism") != expected_determinism):
            raise TrainingAuditError(f"canonical resource preflight workload evidence drift: {name}")
        _require_sha256(row.get("rng_state_sha256"), f"resource preflight random state for {name}")
        models = row.get("models")
        if not isinstance(models, list) or len(models) != len(expected_models[name]):
            raise TrainingAuditError(f"canonical resource preflight model coverage drift: {name}")
        for model, (variant, parameters) in zip(models, expected_models[name]):
            if model.get("variant") != variant or model.get("trainable_parameters") != parameters:
                raise TrainingAuditError(f"canonical resource preflight model identity drift: {name}")
            for key in ("loss_sha256", "gradient_norm_sha256", "parameter_sha256", "adam_state_sha256"):
                _require_sha256(model.get(key), f"resource preflight {name} {key}")
        if name == "continuous_multiscale_history":
            _require_sha256(row.get("state_array_sha256"), "resource preflight history-state array")
        runs = row.get("runs")
        if not isinstance(runs, list) or len(runs) != 2:
            raise TrainingAuditError(f"canonical resource preflight process coverage drift: {name}")
        for run in runs:
            if (run.get("exit_code") != 0 or isinstance(run.get("process_id"), bool) or
                    not isinstance(run.get("process_id"), int) or run["process_id"] <= 0):
                raise TrainingAuditError(f"canonical resource preflight process evidence drift: {name}")
            for key in ("peak_allocated_bytes", "peak_reserved_bytes"):
                if isinstance(run.get(key), bool) or not isinstance(run.get(key), int) or run[key] < 0:
                    raise TrainingAuditError(f"canonical resource preflight memory evidence drift: {name}")
            process_ids.append(run["process_id"])
    if len(set(process_ids)) != 8:
        raise TrainingAuditError("canonical resource preflight did not use eight fresh processes")
    return {
        "status": report["status"],
        "path": str(path.resolve()),
        "sha256": sha256_file(path),
        "workload_count": 4,
        "process_count": 8,
        "individual_array_hashes_persisted": True,
        "history_state_array_hash_persisted": True,
        "tf32_flags_recorded": True,
    }


def _validate_state_audit_for_seal(formal_root: Path) -> tuple[dict, dict]:
    root = formal_root / "state_diagnostics"
    root_manifest_path = root / "manifest.json"
    external_path = formal_root / "state_diagnostics_external_audit.json"
    root_manifest = _load_json(root_manifest_path)
    external = _load_json(external_path)
    if (root_manifest.get("schema") != "historical_multiscale_formal_v09_state_diagnostics_root_v1" or
            root_manifest.get("status") != "state_diagnostics_complete"):
        raise TrainingAuditError("state diagnostic root is not complete")
    if (external.get("schema") != "historical_multiscale_formal_v09_state_diagnostics_external_audit_v1" or
            external.get("status") != "state_diagnostics_external_audit_passed"):
        raise TrainingAuditError("state diagnostic independent replay has not passed")
    if external.get("diagnostic_root_manifest_sha256") != sha256_file(root_manifest_path):
        raise TrainingAuditError("state diagnostic external-audit root binding drift")
    if external.get("training_external_audit_sha256") != sha256_file(
            formal_root / "training_external_audit.json"):
        raise TrainingAuditError("state diagnostic external-audit training binding drift")
    if (external.get("seed_count") != 8 or external.get("array_count") != 64 or
            external.get("raw_array_sha256_matches") != 64 or
            external.get("npy_file_sha256_matches") != 64):
        raise TrainingAuditError("state diagnostic independent replay coverage drift")
    required_flags = {
        "training_target_reads": 0,
        "formal_evaluation_observation_reads": 0,
        "recent_path_executed": False,
        "flow_head_executed": False,
        "formal_period_predictions_generated": False,
        "official_score_called": False,
        "persistent_replay_output_written": False,
    }
    for key, expected in required_flags.items():
        if type(external.get(key)) is not type(expected) or external.get(key) != expected:
            raise TrainingAuditError(f"state diagnostic external-audit field drift: {key}")
    children = root_manifest.get("children")
    if (root_manifest.get("seed_count") != 8 or root_manifest.get("seeds") != list(range(100, 801, 100)) or
            not isinstance(children, list) or len(children) != 8):
        raise TrainingAuditError("state diagnostic root coverage drift")
    return root_manifest, external


def _validate_upstream_strict_evidence(upstream_root: Path) -> dict:
    requirements = {
        "legacy_reference_bridge_audit": (
            "R09-NEST-S100.legacy_checkpoint_bridge_external_audit.json",
            "legacy_checkpoint_bridge_external_audit_passed",
        ),
        "independent_resource_preflight": (
            "R09-NEST-S100.training_resource_preflight_external_audit.json",
            "resource_preflight_passed",
        ),
        "strict_nesting_seal": ("strict_nesting/R09-NEST-S100/seal.json", "sealed"),
        "strict_nesting_external_audit": (
            "R09-NEST-S100.strict_nesting_external_audit.json",
            "strict_nesting_checkpoint_prediction_replay_passed",
        ),
        "strict_stage_authorization": (
            "authorizations/A09-NEST-01.authorization.json",
            "authorized_once",
        ),
        "strict_stage_authorization_consumption": (
            "authorizations/A09-NEST-01.consumption.json",
            "consumed_once",
        ),
    }
    return {
        name: _artifact_record(upstream_root / relative, expected_status=status)
        for name, (relative, status) in requirements.items()
    }


def _checkpoint_seal_records(
    formal_root: Path,
    specs: Sequence[FormalRunSpecV09],
    audit_report: Mapping,
) -> tuple[list[dict], list[dict], list[dict]]:
    run_by_id = {
        record.get("run_id"): record
        for record in audit_report.get("runs", [])
        if isinstance(record, Mapping)
    }
    if len(run_by_id) != 24:
        raise TrainingAuditError("training external audit run records are incomplete")
    expected_dirs = _expected_run_dirs(formal_root, specs)
    runs = []
    intermediate = []
    final = []
    for spec in specs:
        record = run_by_id.get(spec.run_id)
        if not isinstance(record, Mapping):
            raise TrainingAuditError(f"training external audit is missing {spec.run_id}")
        run_dir = expected_dirs[spec.run_id]
        if record.get("run_seal_sha256") != sha256_file(run_dir / "seal.json"):
            raise TrainingAuditError(f"run seal changed after training audit: {spec.run_id}")
        if record.get("run_manifest_sha256") != sha256_file(run_dir / "manifest.json"):
            raise TrainingAuditError(f"run manifest changed after training audit: {spec.run_id}")
        checkpoints = record.get("checkpoints")
        if not isinstance(checkpoints, list) or len(checkpoints) != 3:
            raise TrainingAuditError(f"checkpoint audit coverage drift: {spec.run_id}")
        sealed_checkpoints = []
        for checkpoint in checkpoints:
            epoch = checkpoint.get("epoch")
            path = run_dir / str(checkpoint.get("relative_path"))
            if epoch not in _CHECKPOINT_EPOCHS or checkpoint.get("sha256") != sha256_file(path):
                raise TrainingAuditError(f"checkpoint changed after training audit: {spec.run_id}")
            is_final = epoch == 30
            if (checkpoint.get("eligible_for_formal_prediction") is not is_final or
                    checkpoint.get("not_eligible_for_formal_prediction") is not (not is_final)):
                raise TrainingAuditError(f"checkpoint prediction eligibility drift: {spec.run_id}")
            entry = {
                "role": spec.family,
                "experiment_id": spec.run_id,
                "seed": spec.seed,
                "epoch": epoch,
                "path": str(path.resolve()),
                "sha256": checkpoint["sha256"],
                "not_eligible_for_formal_prediction": not is_final,
                "eligible_for_formal_prediction": is_final,
            }
            sealed_checkpoints.append(entry)
            (final if is_final else intermediate).append(entry)
        runs.append({
            "position": spec.position,
            "run_id": spec.run_id,
            "family": spec.family,
            "variant": spec.variant,
            "seed": spec.seed,
            "trainable_parameters": spec.trainable_parameters,
            "run_root": str(run_dir.resolve()),
            "run_seal_sha256": record["run_seal_sha256"],
            "run_manifest_sha256": record["run_manifest_sha256"],
            "checkpoints": sealed_checkpoints,
        })
    return runs, intermediate, final


def seal_training_suite_v09(
    formal_root: str | Path,
    audit_report: Mapping,
    *,
    upstream_root: str | Path | None = None,
    run_order: str | Path | Sequence[FormalRunSpecV09] | None = None,
    verify_source_checkout: bool = True,
) -> dict:
    """Write the final training seal only after both independent audits pass."""
    import state_diagnostics_formal_v09 as state_diagnostics

    formal_root = Path(os.path.abspath(formal_root)).resolve()
    seal_path = formal_root / "training_seal.json"
    if seal_path.exists():
        raise FileExistsError(f"training seal already exists: {seal_path}")
    _reject_premature_downstream_artifacts(formal_root, formal_root / "unused_training_report.json")
    training_audit_path = formal_root / "training_external_audit.json"
    recorded_audit = _load_json(training_audit_path)
    if not isinstance(audit_report, Mapping) or recorded_audit != dict(audit_report):
        raise TrainingAuditError("training external audit argument differs from the recorded report")
    if (recorded_audit.get("schema") != _AUDIT_SCHEMA or
            recorded_audit.get("status") != "complete_training_audit" or
            recorded_audit.get("coverage") != {
                "expected_runs": 24,
                "audited_runs": 24,
                "passed_runs": 24,
            }):
        raise TrainingAuditError("training external audit is incomplete")
    training_repo_root = formal_root.parents[2]
    if run_order is None:
        run_order = training_repo_root / "src/26_historical_band_experts/configs/formal_v09_run_order.json"
    specs = _resolve_specs(run_order)
    spec_payload = [
        {
            "position": spec.position,
            "seed": spec.seed,
            "family": spec.family,
            "run_id": spec.run_id,
            "variant": spec.variant,
            "trainable_parameters": spec.trainable_parameters,
            "results_root": spec.results_root,
        }
        for spec in specs
    ]
    if recorded_audit.get("run_order_canonical_sha256") != canonical_sha256(spec_payload):
        raise TrainingAuditError("training external audit run-order binding drift")
    if verify_source_checkout:
        current_source = _production_source_seal(formal_root)
        if recorded_audit.get("source_context") != current_source:
            raise TrainingAuditError("main-training source or environment changed after the audit")
    current_audit_source = _audit_source_context()
    if recorded_audit.get("audit_source_context") != current_audit_source:
        raise TrainingAuditError("training audit executable source changed before sealing")
    if recorded_audit.get("audit_source_context_sha256") != canonical_sha256(current_audit_source):
        raise TrainingAuditError("training audit executable source SHA-256 drift")
    if verify_source_checkout and current_audit_source["tracked_source_clean"] is not True:
        raise TrainingAuditError("training audit checkout has tracked source modifications")
    root_manifest, state_audit = _validate_state_audit_for_seal(formal_root)
    diagnostic_records = []
    for child in root_manifest["children"]:
        child_root = formal_root / "state_diagnostics" / child["relative_path"]
        binding = state_diagnostics._directory_binding_v09(child_root)
        if (binding["file_count"] != child.get("directory_file_count") or
                binding["files_sha256"] != child.get("directory_files_sha256")):
            raise TrainingAuditError(f"state diagnostic directory changed for seed {child.get('seed')}")
        diagnostic_records.append({
            "seed": child["seed"],
            "run_id": child["run_id"],
            "path": str(child_root.resolve()),
            "manifest_sha256": child["manifest_sha256"],
            "directory_file_count": child["directory_file_count"],
            "directory_files_sha256": child["directory_files_sha256"],
            "checkpoint_sha256": dict(child.get("checkpoint_sha256", {})),
        })
    if len(diagnostic_records) != 8:
        raise TrainingAuditError("state diagnostic directory binding coverage drift")
    runs, intermediate, final = _checkpoint_seal_records(formal_root, specs, recorded_audit)
    if len(intermediate) != 48 or len(final) != 24:
        raise TrainingAuditError("training checkpoint seal coverage drift")
    upstream_root = Path(os.path.abspath(upstream_root or _infer_upstream_root(formal_root))).resolve()
    source_repo = training_repo_root if verify_source_checkout else IDEA_ROOT.parents[1]
    protocol_path = source_repo / "src/26_historical_band_experts/configs/formal_v09_protocol.json"
    run_order_path = source_repo / "src/26_historical_band_experts/configs/formal_v09_run_order.json"
    strict_evidence = _validate_upstream_strict_evidence(upstream_root)
    four_workload_preflight = _validate_four_workload_preflight_evidence(upstream_root)
    canonical_resource_preflight = _validate_canonical_resource_preflight_report(formal_root, protocol_path)
    preregistration_path = state_diagnostics._preregistration_path_v09()
    upstream_artifacts = {
        "protocol": _artifact_record(protocol_path, expected_status=None),
        "run_order": _artifact_record(run_order_path, expected_status=None),
        "input_seal": _artifact_record(formal_root / "input_attempt_01/seal.json", expected_status="sealed"),
        "input_external_audit": _artifact_record(
            formal_root / "input_attempt_01.external_audit.json",
            expected_status="complete_input_audit_passed",
        ),
        "trusted_target_source_audit": _artifact_record(
            formal_root / "input_attempt_01.trusted_source_external_audit.json",
            expected_status="complete_trusted_training_target_audit",
        ),
        **strict_evidence,
        "state_diagnostics_preregistration": _artifact_record(preregistration_path, expected_status=None),
        "training_external_audit": _artifact_record(
            training_audit_path,
            expected_status="complete_training_audit",
        ),
        "training_progress": _artifact_record(
            formal_root / "training_progress.json",
            expected_status=None,
        ),
        "state_diagnostics_root_manifest": _artifact_record(
            formal_root / "state_diagnostics/manifest.json",
            expected_status="state_diagnostics_complete",
        ),
        "state_diagnostics_external_audit": _artifact_record(
            formal_root / "state_diagnostics_external_audit.json",
            expected_status="state_diagnostics_external_audit_passed",
        ),
    }
    seal = {
        "schema": "historical_multiscale_formal_v09_training_seal_v1",
        "status": "formal_training_sealed",
        "formal_root": str(formal_root),
        "upstream_artifacts": upstream_artifacts,
        "source_context": dict(recorded_audit["source_context"]),
        "source_context_sha256": recorded_audit["source_context_sha256"],
        "audit_source_context": current_audit_source,
        "audit_source_context_sha256": recorded_audit["audit_source_context_sha256"],
        "run_order_canonical_sha256": recorded_audit["run_order_canonical_sha256"],
        "training_external_audit_sha256": sha256_file(training_audit_path),
        "state_diagnostics_external_audit_sha256": sha256_file(
            formal_root / "state_diagnostics_external_audit.json"),
        "runs": runs,
        "intermediate_checkpoints": intermediate,
        "final_checkpoints": final,
        "state_diagnostics": diagnostic_records,
        "four_workload_resource_preflight": four_workload_preflight,
        "canonical_resource_preflight": canonical_resource_preflight,
        "main_training_authorization": {
            "required": False,
            "receipt_created_or_consumed": False,
            "reason": (
                "approved resumable multi-job design; integrity is bound by protocol, inputs, order, source, and seals"
            ),
        },
        "strict_stage_authorization_bound": True,
        "validation_metrics_computed": False,
        "formal_evaluation_observation_reads": 0,
        "formal_prediction_generated": False,
        "official_score_called": False,
    }
    write_json_atomic(seal_path, seal)
    if _load_json(seal_path) != seal:
        raise TrainingAuditError("training seal bytes do not round-trip to the sealed payload")
    return seal


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="audit formal version-09 training runs")
    parser.add_argument("--mode", choices=("audit", "seal"), default="audit")
    parser.add_argument("--formal-root", required=True)
    parser.add_argument("--run-order", required=True)
    parser.add_argument("--report")
    parser.add_argument("--upstream-root")
    args = parser.parse_args(argv)
    specs = load_run_order_v09(args.run_order)
    if args.mode == "audit":
        if not args.report:
            parser.error("--report is required in audit mode")
        report = audit_training_suite_v09(args.formal_root, specs, args.report)
    else:
        audit_path = Path(args.formal_root) / "training_external_audit.json"
        report = seal_training_suite_v09(
            args.formal_root,
            _load_json(audit_path),
            upstream_root=args.upstream_root,
            run_order=specs,
        )
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

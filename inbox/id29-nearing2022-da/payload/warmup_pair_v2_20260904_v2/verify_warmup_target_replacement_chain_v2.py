"""Independently verify the amendment-bound all-531 warmup-target repair artifacts.

This verifier is intentionally separate from the two Slurm wrappers that create the
artifacts. It rehashes their published bytes, re-evaluates the decisive data gates,
and refuses any path other than the preregistered replacement chain. Scheduler state
is a separate live gate and is deliberately not inferred from artifact contents.

Version 2 corrects one integration-contract error exposed by Slurm job 220487: the
mask-isolation command intentionally prints only ``result["conclusion"]`` to its
standard-output JSON, while the data-port command prints its complete audit object.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
from typing import Any

import yaml


SCHEMA = "nearing2022-warmup-target-replacement-independent-verification-v2"
PROTOCOL_SHA256 = "16bdf57bcbf3afd335e91107bc908330e86ac7fa20db60cbf54ee30b1ab321c1"
AMENDMENT_SHA256 = "a21bae28a26f5797e96232628fdc139f5ffd1e54e31ee2032a7805acb0785ef5"
SUBMISSION_RECEIPT_SHA256 = "18e6aeeee3321427d0f851d68d2cbbfb02f8d13e477f6f96dd5f22eed1d4d2a1"

FORMAL = Path("results/29_nearing2022_da_ar/formal_closure")
DIAGNOSTICS = FORMAL / "diagnostics"
PROTOCOL = FORMAL / "warmup_target_paired_retraining_protocol.json"
AMENDMENT = FORMAL / "warmup_target_paired_retraining_protocol_amendment_01.json"
DEPLOYED_PROTOCOL = DIAGNOSTICS / PROTOCOL.name
DEPLOYED_AMENDMENT = DIAGNOSTICS / AMENDMENT.name
SUBMISSION_RECEIPT = DIAGNOSTICS / "warmup_target_repair_submission_01.json"
DATA_OUTPUT = DIAGNOSTICS / "author_v13_training_data_port_all531_v2"
MASK_OUTPUT = DIAGNOSTICS / "author_v13_warmup_isolation_all531_v2"
FAILED_OUTPUT = DIAGNOSTICS / "author_v13_training_data_port_all531.preparing-202506"
FAILED_AUDIT = FAILED_OUTPUT / "audit.json"
FAILED_STDOUT = FAILED_OUTPUT / "audit_stdout.json"
SOURCE_RUN = Path(
    "results/29_nearing2022_da_ar/"
    "nearing2022_autoregression_lead1_holdout0.0_seed0_2026_0808_1648_ep30"
)
SOURCE_CONFIG = SOURCE_RUN / "config.yml"
SOURCE_SCALER = SOURCE_RUN / "train_data/train_data_scaler.yml"
SOURCE_CHECKPOINT = SOURCE_RUN / "model_epoch030.pt"
FROZEN_CONFIG = Path(
    "src/29_nearing2022_da_ar/configs/full_reproduction/time_split/"
    "autoregression/lead_1_holdout_0.0_seed_0.yml"
)
FROZEN_BASINS = Path("src/29_nearing2022_da_ar/basin_lists/531_basin_list.txt")
TRAINING_REGISTRY = Path("src/29_nearing2022_da_ar/registry/experiment_registry.csv")
EVALUATION_REGISTRY = Path("src/29_nearing2022_da_ar/registry/evaluation_registry.csv")
BASEDATASET = Path("neuralhydrology/datasetzoo/basedataset.py")
V1_AUDIT = Path("src/29_nearing2022_da_ar/scripts/audit_training_data_port.py")
V2_AUDIT = Path("src/29_nearing2022_da_ar/scripts/audit_training_data_port_v2.py")
ISOLATION = Path("src/29_nearing2022_da_ar/scripts/audit_warmup_target_isolation.py")
DATA_SLURM = Path("src/29_nearing2022_da_ar/hpc/run_author_v13_training_data_port_all531_v2.slurm")
MASK_SLURM = Path("src/29_nearing2022_da_ar/hpc/run_author_v13_warmup_isolation_all531_v2.slurm")
ORIGINAL_VERIFIER = Path("src/29_nearing2022_da_ar/scripts/verify_warmup_target_replacement_chain.py")
VERIFIER = FORMAL / "warmup_pair_v2_20260904/verify_warmup_target_replacement_chain_v2.py"

FROZEN_SHA256_BY_RELATIVE = {
    PROTOCOL: PROTOCOL_SHA256,
    AMENDMENT: AMENDMENT_SHA256,
    V1_AUDIT: "5f7d49c4899aeb0ffb1d097cffd98cfe86393f86b5849a153d3074094744eb85",
    V2_AUDIT: "51b9091c928a8b514f0be6e81ab5afd304bda654e3dc63a6cb27746e3dee3233",
    ISOLATION: "9f898a80aafb4e207bb56fd095125e9d5d092ec8c96af4d6010bdaeb36a27f8c",
    DATA_SLURM: "7805e78942a9d512075deb1f546a230d4fe20f04a7efd837a8507ada9e4a493e",
    MASK_SLURM: "9d8d2c890e6ec8a28be30e674ea05c3c90a8926ba0e4e80bf088386879127053",
    ORIGINAL_VERIFIER: "0bcabc96f9e702f2317464f1f0123c29d49d5f7f0f972a10ea3e01bbf18fe987",
    FROZEN_CONFIG: "729985706faeb8c45480d3c485dbad72ae51eec94dff69b5c8964e2036591b1a",
    FROZEN_BASINS: "cd2d3d466aca736fcd32042d2b0bde3d0b58e42ba37fe552d97480bd914b9e85",
    TRAINING_REGISTRY: "6366d468d671a2af39c2a136b984ca4ee9ebfc1106618b945287bdaabe629d64",
    EVALUATION_REGISTRY: "37b312dbd362399a9771f2233d1e1139ea25d5339d1bbc7a806fa75be30b9215",
    BASEDATASET: "4658816ea3110a1c2efcf54c3dcf00d5c0982459dca4f7ac985beb983b12df0d",
    SOURCE_CHECKPOINT: "c2a6f260d555e323650103a84bc066d591fc8cc3e6bf8142a89f9ccd7f64661b",
}

DATA_MEMBERS = {
    "audit.json",
    "audit_stdout.json",
    "audit_training_data_port.py",
    "audit_training_data_port_v2.py",
    "diagnostic_receipt.json",
    "run_author_v13_training_data_port_all531_v2.slurm",
    "warmup_target_paired_retraining_protocol_amendment_01.json",
}
MASK_MEMBERS = {
    "audit.json",
    "audit_stdout.json",
    "audit_training_data_port.py",
    "audit_warmup_target_isolation.py",
    "diagnostic_receipt.json",
    "run_author_v13_warmup_isolation_all531_v2.slurm",
    "warmup_target_paired_retraining_protocol.json",
    "warmup_target_paired_retraining_protocol_amendment_01.json",
}


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _load_json(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError(f"Expected a JSON object: {path}")
    return payload


def _path(repo_root: Path, relative: Path, *, directory: bool = False) -> Path:
    repo_root = repo_root.resolve()
    candidate = (repo_root / relative).resolve()
    if candidate.relative_to(repo_root).as_posix() != relative.as_posix():
        raise ValueError(f"Non-canonical replacement-chain path: {relative.as_posix()}")
    if directory:
        if not candidate.is_dir():
            raise FileNotFoundError(f"Required replacement directory is missing: {relative.as_posix()}")
    elif not candidate.is_file():
        raise FileNotFoundError(f"Required replacement artifact is missing: {relative.as_posix()}")
    return candidate


def _nested(payload: dict[str, Any], keys: tuple[str, ...], label: str) -> Any:
    value: Any = payload
    for key in keys:
        if not isinstance(value, dict) or key not in value:
            raise ValueError(f"{label} lacks {'.'.join(keys)}")
        value = value[key]
    return value


def _require(payload: dict[str, Any], keys: tuple[str, ...], expected: Any, label: str) -> None:
    actual = _nested(payload, keys, label)
    if actual != expected:
        raise ValueError(f"{label} {'.'.join(keys)} is {actual!r}, expected {expected!r}")


def _require_hash(payload: dict[str, Any], key: str, path: Path, label: str) -> None:
    _require(payload, (key,), sha256_file(path), label)


def _require_exact_members(directory: Path, expected: set[str], label: str) -> None:
    members = tuple(directory.iterdir())
    actual = {path.name for path in members if path.is_file() and not path.is_symlink()}
    non_files = sorted(path.name for path in members if path.is_symlink() or not path.is_file())
    if non_files:
        raise ValueError(f"{label} contains non-file members: {non_files}")
    if actual != expected:
        raise ValueError(
            f"{label} member mismatch; missing={sorted(expected - actual)}, extra={sorted(actual - expected)}"
        )


def _require_same_bytes(left: Path, right: Path, label: str) -> None:
    left_sha256 = sha256_file(left)
    right_sha256 = sha256_file(right)
    if left_sha256 != right_sha256:
        raise ValueError(f"{label} byte mismatch: {left_sha256} != {right_sha256}")


def _registered_scaler_values(path: Path) -> tuple[float, float]:
    payload = yaml.safe_load(path.read_text(encoding="utf-8"))
    center = float(payload["xarray_feature_center"]["data_vars"]["QObs(mm/d)"]["data"])
    scale = float(payload["xarray_feature_scale"]["data_vars"]["QObs(mm/d)"]["data"])
    return center, scale


def _validate_protocol(protocol: dict[str, Any], paths: dict[str, Path]) -> None:
    _require(protocol, ("schema",), "nearing2022-warmup-target-paired-retraining-protocol-v1", "protocol")
    _require(protocol, ("status",), "preregistered_not_submitted", "protocol")
    _require(protocol, ("frozen_inputs", "configuration"), FROZEN_CONFIG.as_posix(), "protocol")
    _require(protocol, ("frozen_inputs", "configuration_sha256"), sha256_file(paths["frozen_config"]), "protocol")
    _require(protocol, ("frozen_inputs", "basin_list"), FROZEN_BASINS.as_posix(), "protocol")
    _require(protocol, ("frozen_inputs", "basin_list_sha256"), sha256_file(paths["frozen_basins"]), "protocol")
    _require(protocol, ("frozen_inputs", "basin_count"), 531, "protocol")
    _require(
        protocol,
        ("frozen_inputs", "training_registry_sha256"),
        sha256_file(paths["training_registry"]),
        "protocol",
    )
    _require(
        protocol,
        ("frozen_inputs", "evaluation_registry_sha256"),
        sha256_file(paths["evaluation_registry"]),
        "protocol",
    )
    _require(
        protocol,
        ("frozen_inputs", "current_basedataset_sha256"),
        sha256_file(paths["basedataset"]),
        "protocol",
    )
    _require(
        protocol,
        ("frozen_inputs", "registered_checkpoint_sha256"),
        sha256_file(paths["source_checkpoint"]),
        "protocol",
    )
    _require(protocol, ("frozen_inputs", "seed"), 0, "protocol")
    _require(protocol, ("frozen_inputs", "epochs"), 30, "protocol")
    _require(protocol, ("frozen_inputs", "test_holdout"), 1.0, "protocol")


def _validate_amendment(
    amendment: dict[str, Any],
    protocol_path: Path,
    failed_audit_path: Path,
    failed_stdout_path: Path,
    source_scaler_path: Path,
    registered_center: float,
    registered_scale: float,
) -> None:
    _require(amendment, ("schema",), "nearing2022-warmup-target-paired-retraining-amendment-v1", "amendment")
    _require(amendment, ("original_protocol_sha256",), sha256_file(protocol_path), "amendment")
    _require(amendment, ("failed_entry_job", "slurm_job_id"), "202506", "amendment")
    _require(amendment, ("failed_entry_job", "state"), "FAILED", "amendment")
    _require(amendment, ("failed_entry_job", "exit_code"), "1:0", "amendment")
    _require(amendment, ("failed_entry_job", "audit_sha256"), sha256_file(failed_audit_path), "amendment")
    _require(
        amendment,
        ("failed_entry_job", "audit_stdout_sha256"),
        sha256_file(failed_stdout_path),
        "amendment",
    )
    _require(
        amendment,
        ("failed_entry_job", "completed_scientific_checks", "registered_source_scaler_sha256"),
        sha256_file(source_scaler_path),
        "amendment",
    )
    _require(
        amendment,
        ("failed_entry_job", "completed_scientific_checks", "registered_source_target_center"),
        registered_center,
        "amendment",
    )
    _require(
        amendment,
        ("failed_entry_job", "completed_scientific_checks", "registered_source_target_scale"),
        registered_scale,
        "amendment",
    )
    _require(
        amendment,
        ("replacement_rule", "decisive_raw_target_gate"),
        "bitwise equality of common finite pre-normalization target values",
        "amendment",
    )
    _require(
        amendment,
        ("replacement_rule", "inverse_scaling_role"),
        "descriptive floating-point diagnostic only",
        "amendment",
    )
    _require(amendment, ("replacement_rule", "inverse_scaling_absolute_tolerance_changed"), False, "amendment")
    _require(amendment, ("replacement_rule", "registered_matrix_modified"), False, "amendment")


def _validate_submission_receipt(
    receipt: dict[str, Any],
    protocol_path: Path,
    amendment_path: Path,
    failed_audit: Path,
    failed_stdout: Path,
    data_slurm: Path,
    mask_slurm: Path,
) -> None:
    _require(receipt, ("schema",), "nearing2022-warmup-target-entry-repair-submission-v1", "submission")
    _require(receipt, ("registered_matrix_modified",), False, "submission")
    _require(receipt, ("preserved_failed_jobs", "202506"), "FAILED|1:0", "submission")
    _require(receipt, ("preserved_failed_jobs", "202507"), "PENDING|DependencyNeverSatisfied", "submission")
    _require(receipt, ("source_bindings", "original_protocol_sha256"), sha256_file(protocol_path), "submission")
    _require(receipt, ("source_bindings", "protocol_amendment_01_sha256"), sha256_file(amendment_path), "submission")
    _require(receipt, ("source_bindings", "preserved_failed_audit_sha256"), sha256_file(failed_audit), "submission")
    _require(receipt, ("source_bindings", "preserved_failed_stdout_sha256"), sha256_file(failed_stdout), "submission")
    source_scripts = data_slurm.parents[1] / "scripts"
    _require(
        receipt,
        ("source_bindings", "version_1_audit_sha256"),
        sha256_file(source_scripts / V1_AUDIT.name),
        "submission",
    )
    _require(
        receipt,
        ("source_bindings", "version_2_audit_sha256"),
        sha256_file(source_scripts / V2_AUDIT.name),
        "submission",
    )
    _require(receipt, ("resource_boundary", "additional_gpu_concurrency_before_202222_finishes"), 0, "submission")
    _require(receipt, ("resource_boundary", "data_audit_waits_for_complete_evaluation_array"), "202222", "submission")
    _require(receipt, ("resource_boundary", "mask_audit_waits_for_successful_data_audit"), "202510", "submission")

    jobs = (
        (
            "training_data_port_v2",
            "202510",
            "afterany:202222",
            DATA_OUTPUT.as_posix(),
            DATA_SLURM.as_posix(),
            sha256_file(data_slurm),
        ),
        (
            "warmup_target_isolation_v2",
            "202511",
            "afterok:202510",
            MASK_OUTPUT.as_posix(),
            MASK_SLURM.as_posix(),
            sha256_file(mask_slurm),
        ),
    )
    for name, job_id, dependency, output, script, script_hash in jobs:
        _require(receipt, ("jobs", name, "slurm_job_id"), job_id, "submission")
        _require(receipt, ("jobs", name, "dependency_requested"), dependency, "submission")
        _require(receipt, ("jobs", name, "output"), output, "submission")
        _require(
            receipt,
            ("jobs", name, "script"),
            f"/data1/home/sunyiq/nearing2022_da/{script}",
            "submission",
        )
        _require(receipt, ("jobs", name, "script_sha256"), script_hash, "submission")
        scheduler = _nested(receipt, ("jobs", name, "scheduler_record_at_submission"), "submission")
        if not isinstance(scheduler, str) or f"JobId={job_id}" not in scheduler:
            raise ValueError(f"submission scheduler record does not bind job {job_id}")
        if f"Dependency={dependency}_*" not in scheduler and f"Dependency={dependency}" not in scheduler:
            raise ValueError(f"submission scheduler record does not bind dependency {dependency}")
        if f"Command=/data1/home/sunyiq/nearing2022_da/{script}" not in scheduler:
            raise ValueError(f"submission scheduler record does not bind {script}")


def _validate_data_audit(
    audit: dict[str, Any], protocol: dict[str, Any], registered_center: float, registered_scale: float
) -> None:
    _require(audit, ("schema",), "nearing2022-author-v13-training-data-port-audit-v2", "data audit")
    _require(audit, ("scope", "basin_count"), 531, "data audit")
    _require(audit, ("scope", "registered_matrix_modified"), False, "data audit")
    _require(audit, ("inputs", "basins_with_bitwise_identical_normalized_dynamic_inputs"), 531, "data audit")
    _require(audit, ("inputs", "basins_with_bitwise_identical_static_attributes"), 531, "data audit")
    _require(audit, ("source", "author_masks_warmup_targets"), True, "data audit")
    _require(audit, ("source", "current_masks_warmup_targets"), False, "data audit")
    _require(
        audit,
        ("source", "current_basedataset_sha256"),
        _nested(protocol, ("frozen_inputs", "current_basedataset_sha256"), "protocol"),
        "data audit",
    )
    _require(audit, ("raw_targets_before_normalization", "common_values_bitwise_identical"), True, "data audit")
    _require(audit, ("raw_targets_before_normalization", "maximum_absolute_common_difference"), 0.0, "data audit")
    _require(audit, ("raw_targets_before_normalization", "current_finite_author_missing"), 193284, "data audit")
    _require(audit, ("raw_targets_before_normalization", "author_finite_current_missing"), 0, "data audit")
    inverse_maximum = _nested(
        audit, ("raw_targets_after_inverse_scaling", "maximum_absolute_common_difference"), "data audit"
    )
    if not isinstance(inverse_maximum, (int, float)) or inverse_maximum <= 1e-5:
        raise ValueError("data audit did not reproduce the inverse-roundtrip boundary")
    _require(audit, ("raw_targets_after_inverse_scaling", "common_values_within_1e_5"), False, "data audit")
    _require(
        audit,
        ("measurement_repair", "inverse_scaling_role"),
        "descriptive floating-point diagnostic only",
        "data audit",
    )
    _require(audit, ("measurement_repair", "inverse_scaling_absolute_tolerance_changed"), False, "data audit")
    _require(audit, ("conclusion", "common_pre_normalization_raw_targets_bitwise_identical"), True, "data audit")
    _require(audit, ("conclusion", "training_data_port_is_exact_for_this_scope"), False, "data audit")
    _require(audit, ("target_scaler", "current_center"), registered_center, "data audit")
    _require(audit, ("target_scaler", "current_scale"), registered_scale, "data audit")
    _require(audit, ("per_basin_target_standard_deviation", "basins_different"), 531, "data audit")


def _validate_data_receipt(
    receipt: dict[str, Any], paths: dict[str, Path], audit: dict[str, Any], center: float, scale: float
) -> None:
    _require(receipt, ("schema",), "nearing2022-author-v13-training-data-port-all531-receipt-v2", "data receipt")
    _require(receipt, ("slurm_job_id",), "202510", "data receipt")
    for key, path_key in (
        ("audit_sha256", "data_audit"),
        ("v1_script_sha256", "v1_audit"),
        ("v2_script_sha256", "v2_audit"),
        ("amendment_sha256", "deployed_amendment"),
        ("slurm_script_sha256", "data_slurm"),
        ("failed_audit_sha256", "failed_audit"),
        ("frozen_config_sha256", "frozen_config"),
        ("frozen_basin_list_sha256", "frozen_basins"),
        ("registered_source_config_sha256", "source_config"),
        ("registered_source_scaler_sha256", "source_scaler"),
    ):
        _require_hash(receipt, key, paths[path_key], "data receipt")
    for key in ("registered_target_center", "current_audit_target_center"):
        _require(receipt, (key,), center, "data receipt")
    for key in ("registered_target_scale", "current_audit_target_scale"):
        _require(receipt, (key,), scale, "data receipt")
    _require(receipt, ("registered_source_scaler_matches_current_audit",), True, "data receipt")
    _require(receipt, ("common_pre_normalization_raw_targets_bitwise_identical",), True, "data receipt")
    _require(receipt, ("inverse_scaling_is_descriptive_only",), True, "data receipt")
    _require(receipt, ("registered_matrix_modified",), False, "data receipt")
    _require(audit, ("scope", "registered_matrix_modified"), False, "data audit")


def _validate_mask_audit(audit: dict[str, Any], protocol: dict[str, Any], upstream_audit_path: Path) -> None:
    _require(audit, ("schema",), "nearing2022-warmup-target-isolation-audit-v1", "mask audit")
    _require(audit, ("scope", "basin_count"), 531, "mask audit")
    _require(audit, ("scope", "installed_package_modified"), False, "mask audit")
    _require(audit, ("scope", "registered_matrix_modified"), False, "mask audit")
    comparison = "author_vs_current_masked"
    for key in (
        "basins_compared",
        "bitwise_identical_normalized_dynamic_input_basins",
        "bitwise_identical_static_attribute_basins",
        "per_basin_target_standard_deviations_within_1e_6",
    ):
        _require(audit, (comparison, key), 531, "mask audit")
    for key in ("metadata_identical", "finite_target_mask_identical"):
        _require(audit, (comparison, key), True, "mask audit")
    for key in (
        "masked_minus_author_target_center",
        "masked_minus_author_target_scale",
        "maximum_absolute_common_raw_target_difference",
        "maximum_absolute_target_standard_deviation_difference",
    ):
        _require(audit, (comparison, key), 0.0, "mask audit")
    _require(audit, ("one_factor_contract", "statement_occurrences_before"), 0, "mask audit")
    _require(audit, ("one_factor_contract", "statement_occurrences_after"), 1, "mask audit")
    _require(audit, ("one_factor_contract", "other_installed_source_files_modified"), 0, "mask audit")
    _require(
        audit,
        ("source_binding", "unmasked_evidence_sha256"),
        sha256_file(upstream_audit_path),
        "mask audit",
    )
    _require(
        audit,
        ("source_binding", "current_basedataset_sha256"),
        _nested(protocol, ("frozen_inputs", "current_basedataset_sha256"), "protocol"),
        "mask audit",
    )
    _require(
        audit,
        ("one_factor_contract", "source_sha256_before"),
        _nested(protocol, ("frozen_inputs", "current_basedataset_sha256"), "protocol"),
        "mask audit",
    )
    _require(audit, ("conclusion", "single_mask_restores_released_training_data_for_scope"), True, "mask audit")


def _validate_mask_receipt(receipt: dict[str, Any], paths: dict[str, Path]) -> None:
    _require(receipt, ("schema",), "nearing2022-author-v13-warmup-isolation-all531-receipt-v2", "mask receipt")
    _require(receipt, ("slurm_job_id",), "202511", "mask receipt")
    for key, path_key in (
        ("audit_sha256", "mask_audit"),
        ("upstream_audit_sha256", "data_audit"),
        ("upstream_receipt_sha256", "data_receipt"),
        ("helper_script_sha256", "v1_audit"),
        ("isolation_script_sha256", "isolation"),
        ("paired_retraining_protocol_sha256", "deployed_protocol"),
        ("protocol_amendment_sha256", "deployed_amendment"),
        ("slurm_script_sha256", "mask_slurm"),
    ):
        _require_hash(receipt, key, paths[path_key], "mask receipt")
    _require(receipt, ("single_mask_restores_released_training_data_for_531_basins",), True, "mask receipt")
    _require(receipt, ("registered_matrix_modified",), False, "mask receipt")


def _artifact_rows(repo_root: Path, paths: dict[str, Path]) -> list[dict[str, Any]]:
    rows = []
    for label, path in sorted(paths.items()):
        if path.is_file():
            rows.append({
                "label": label,
                "path": path.relative_to(repo_root).as_posix(),
                "bytes": path.stat().st_size,
                "sha256": sha256_file(path),
            })
    return rows


def verify_replacement_chain(repo_root: Path) -> dict[str, Any]:
    repo_root = Path(repo_root).resolve()
    paths = {
        "protocol": _path(repo_root, PROTOCOL),
        "amendment": _path(repo_root, AMENDMENT),
        "deployed_protocol": _path(repo_root, DEPLOYED_PROTOCOL),
        "deployed_amendment": _path(repo_root, DEPLOYED_AMENDMENT),
        "submission_receipt": _path(repo_root, SUBMISSION_RECEIPT),
        "failed_audit": _path(repo_root, FAILED_AUDIT),
        "failed_stdout": _path(repo_root, FAILED_STDOUT),
        "source_config": _path(repo_root, SOURCE_CONFIG),
        "source_scaler": _path(repo_root, SOURCE_SCALER),
        "source_checkpoint": _path(repo_root, SOURCE_CHECKPOINT),
        "frozen_config": _path(repo_root, FROZEN_CONFIG),
        "frozen_basins": _path(repo_root, FROZEN_BASINS),
        "training_registry": _path(repo_root, TRAINING_REGISTRY),
        "evaluation_registry": _path(repo_root, EVALUATION_REGISTRY),
        "basedataset": _path(repo_root, BASEDATASET),
        "v1_audit": _path(repo_root, V1_AUDIT),
        "v2_audit": _path(repo_root, V2_AUDIT),
        "isolation": _path(repo_root, ISOLATION),
        "data_slurm": _path(repo_root, DATA_SLURM),
        "mask_slurm": _path(repo_root, MASK_SLURM),
        "original_verifier": _path(repo_root, ORIGINAL_VERIFIER),
        "verifier": _path(repo_root, VERIFIER),
    }
    for relative, expected in FROZEN_SHA256_BY_RELATIVE.items():
        actual = sha256_file(_path(repo_root, relative))
        if actual != expected:
            raise ValueError(f"Frozen source hash changed for {relative.as_posix()}: {actual}")
    if sha256_file(paths["deployed_protocol"]) != PROTOCOL_SHA256:
        raise ValueError("Deployed paired protocol differs from the immutable source")
    if sha256_file(paths["deployed_amendment"]) != AMENDMENT_SHA256:
        raise ValueError("Deployed amendment differs from the immutable source")
    if sha256_file(paths["submission_receipt"]) != SUBMISSION_RECEIPT_SHA256:
        raise ValueError("Replacement submission receipt SHA-256 changed")

    data_dir = _path(repo_root, DATA_OUTPUT, directory=True)
    mask_dir = _path(repo_root, MASK_OUTPUT, directory=True)
    _require_exact_members(data_dir, DATA_MEMBERS, "data output")
    _require_exact_members(mask_dir, MASK_MEMBERS, "mask output")
    paths.update({
        "data_audit": data_dir / "audit.json",
        "data_stdout": data_dir / "audit_stdout.json",
        "data_receipt": data_dir / "diagnostic_receipt.json",
        "data_copy_v1_audit": data_dir / V1_AUDIT.name,
        "data_copy_v2_audit": data_dir / V2_AUDIT.name,
        "data_copy_amendment": data_dir / AMENDMENT.name,
        "data_copy_slurm": data_dir / DATA_SLURM.name,
        "mask_audit": mask_dir / "audit.json",
        "mask_stdout": mask_dir / "audit_stdout.json",
        "mask_receipt": mask_dir / "diagnostic_receipt.json",
        "mask_copy_v1_audit": mask_dir / V1_AUDIT.name,
        "mask_copy_isolation": mask_dir / ISOLATION.name,
        "mask_copy_protocol": mask_dir / PROTOCOL.name,
        "mask_copy_amendment": mask_dir / AMENDMENT.name,
        "mask_copy_slurm": mask_dir / MASK_SLURM.name,
    })
    for copied_key, source_key in (
        ("data_copy_v1_audit", "v1_audit"),
        ("data_copy_v2_audit", "v2_audit"),
        ("data_copy_amendment", "deployed_amendment"),
        ("data_copy_slurm", "data_slurm"),
        ("mask_copy_v1_audit", "v1_audit"),
        ("mask_copy_isolation", "isolation"),
        ("mask_copy_protocol", "deployed_protocol"),
        ("mask_copy_amendment", "deployed_amendment"),
        ("mask_copy_slurm", "mask_slurm"),
    ):
        _require_same_bytes(paths[copied_key], paths[source_key], copied_key)

    protocol = _load_json(paths["protocol"])
    amendment = _load_json(paths["amendment"])
    submission = _load_json(paths["submission_receipt"])
    data_audit = _load_json(paths["data_audit"])
    data_stdout = _load_json(paths["data_stdout"])
    data_receipt = _load_json(paths["data_receipt"])
    mask_audit = _load_json(paths["mask_audit"])
    mask_stdout = _load_json(paths["mask_stdout"])
    mask_receipt = _load_json(paths["mask_receipt"])
    if data_stdout != data_audit:
        raise ValueError("Data audit stdout does not reproduce the published audit JSON")
    if mask_stdout != mask_audit.get("conclusion"):
        raise ValueError("Mask audit stdout does not reproduce the published audit conclusion")

    center, scale = _registered_scaler_values(paths["source_scaler"])
    _validate_protocol(protocol, paths)
    _validate_amendment(
        amendment,
        paths["protocol"],
        paths["failed_audit"],
        paths["failed_stdout"],
        paths["source_scaler"],
        center,
        scale,
    )
    _validate_submission_receipt(
        submission,
        paths["protocol"],
        paths["amendment"],
        paths["failed_audit"],
        paths["failed_stdout"],
        paths["data_slurm"],
        paths["mask_slurm"],
    )
    _validate_data_audit(data_audit, protocol, center, scale)
    _validate_data_receipt(data_receipt, paths, data_audit, center, scale)
    _validate_mask_audit(mask_audit, protocol, paths["data_audit"])
    _validate_mask_receipt(mask_receipt, paths)

    return {
        "schema": SCHEMA,
        "entry_artifact_gate_passed": True,
        "scheduler_gate_checked": False,
        "scheduler_gate_requirement": "jobs 202510 and 202511 must independently be COMPLETED with exit 0:0",
        "pair_runner_adaptation_permitted_by_this_file_alone": False,
        "registered_matrix_modified": False,
        "data_job_id": "202510",
        "mask_job_id": "202511",
        "basins": 531,
        "current_finite_author_missing_targets": 193284,
        "direct_common_raw_target_maximum_difference": 0.0,
        "single_mask_exact_restoration": True,
        "artifacts": _artifact_rows(repo_root, paths),
    }


def _write_json_atomic(path: Path, payload: dict[str, Any]) -> None:
    path = Path(path)
    if path.exists():
        raise FileExistsError(f"Refusing to overwrite independent verification: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.tmp-{os.getpid()}")
    if temporary.exists():
        raise FileExistsError(f"Refusing stale temporary verification path: {temporary}")
    temporary.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8", newline="\n")
    temporary.replace(path)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = verify_replacement_chain(args.repo_root)
    _write_json_atomic(args.output, result)
    print(json.dumps(result, sort_keys=True))


if __name__ == "__main__":
    main()

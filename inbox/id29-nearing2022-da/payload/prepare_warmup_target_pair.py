"""Validate the all-basin gates and prepare one immutable warmup-mask retraining arm."""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
from typing import Any, Iterable

import yaml


PROTOCOL_SHA256 = "16bdf57bcbf3afd335e91107bc908330e86ac7fa20db60cbf54ee30b1ab321c1"
MASK_STATEMENT = "df_sub.loc[df_sub.index < start_date, self.cfg.target_variables] = np.nan"
IGNORED_NAMES = {"__pycache__"}
IGNORED_SUFFIXES = {".pyc", ".pyo"}


def _sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _sha256_file(path: Path) -> str:
    return _sha256_bytes(Path(path).read_bytes())


def _load_json(path: Path) -> dict[str, Any]:
    payload = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise TypeError(f"Expected a JSON object in {path}")
    return payload


def _require_equal(mapping: dict[str, Any], key: str, expected: Any) -> None:
    actual = mapping.get(key)
    if actual != expected:
        raise ValueError(f"{key}: expected {expected!r}, got {actual!r}")


def _require_false(mapping: dict[str, Any], key: str) -> None:
    _require_equal(mapping, key, False)


def _require_file_hash(repo_root: Path, relative_path: str, expected: str) -> Path:
    path = Path(relative_path)
    path = path if path.is_absolute() else Path(repo_root) / path
    if not path.is_file():
        raise FileNotFoundError(f"Missing frozen input: {path}")
    actual = _sha256_file(path)
    if actual != expected:
        raise ValueError(f"Frozen input hash mismatch for {path}: expected {expected}, got {actual}")
    return path.resolve()


def _load_protocol(protocol_path: Path) -> dict[str, Any]:
    protocol_path = Path(protocol_path)
    actual = _sha256_file(protocol_path)
    if actual != PROTOCOL_SHA256:
        raise ValueError(f"Paired-retraining protocol hash mismatch: expected {PROTOCOL_SHA256}, got {actual}")
    protocol = _load_json(protocol_path)
    _require_equal(protocol, "schema", "nearing2022-warmup-target-paired-retraining-protocol-v1")
    _require_equal(protocol, "status", "preregistered_not_submitted")
    return protocol


def validate_entry_gates(
    repo_root: Path,
    protocol_path: Path,
    data_audit_dir: Path,
    mask_audit_dir: Path,
) -> dict[str, Any]:
    """Fail closed unless the two serial all-531 diagnostic jobs satisfy every frozen entry gate."""
    repo_root = Path(repo_root).resolve()
    protocol = _load_protocol(protocol_path)
    frozen = protocol["frozen_inputs"]
    data_audit_path = Path(data_audit_dir) / "audit.json"
    data_receipt_path = Path(data_audit_dir) / "diagnostic_receipt.json"
    mask_audit_path = Path(mask_audit_dir) / "audit.json"
    mask_receipt_path = Path(mask_audit_dir) / "diagnostic_receipt.json"
    for path in (data_audit_path, data_receipt_path, mask_audit_path, mask_receipt_path):
        if not path.is_file():
            raise FileNotFoundError(f"Missing paired-retraining entry evidence: {path}")

    data_audit = _load_json(data_audit_path)
    data_receipt = _load_json(data_receipt_path)
    mask_audit = _load_json(mask_audit_path)
    mask_receipt = _load_json(mask_receipt_path)
    data_sha = _sha256_file(data_audit_path)
    mask_sha = _sha256_file(mask_audit_path)

    _require_equal(data_receipt, "slurm_job_id", "202506")
    _require_equal(data_receipt, "audit_sha256", data_sha)
    _require_equal(data_receipt, "frozen_config_sha256", frozen["configuration_sha256"])
    _require_equal(data_receipt, "frozen_basin_list_sha256", frozen["basin_list_sha256"])
    _require_equal(data_receipt, "registered_source_scaler_matches_current_audit", True)
    _require_equal(data_audit["scope"], "basin_count", 531)
    _require_false(data_audit["scope"], "registered_matrix_modified")
    _require_equal(
        data_audit["inputs"],
        "basins_with_bitwise_identical_normalized_dynamic_inputs",
        531,
    )
    _require_equal(data_audit["inputs"], "basins_with_bitwise_identical_static_attributes", 531)
    _require_equal(data_audit["source"], "author_masks_warmup_targets", True)
    _require_equal(data_audit["source"], "current_masks_warmup_targets", False)
    current_only = data_audit["raw_targets_after_inverse_scaling"].get("current_finite_author_missing")
    if not isinstance(current_only, int) or current_only <= 0:
        raise ValueError(f"current_finite_author_missing must be a positive integer, got {current_only!r}")
    for audit_key, receipt_key in (
        ("current_center", "current_audit_target_center"),
        ("current_scale", "current_audit_target_scale"),
    ):
        _require_equal(data_receipt, receipt_key, data_audit["target_scaler"][audit_key])
    _require_equal(data_receipt, "registered_target_center", data_receipt["current_audit_target_center"])
    _require_equal(data_receipt, "registered_target_scale", data_receipt["current_audit_target_scale"])

    _require_equal(mask_receipt, "slurm_job_id", "202507")
    _require_equal(mask_receipt, "audit_sha256", mask_sha)
    _require_equal(mask_receipt, "upstream_audit_sha256", data_sha)
    _require_equal(mask_receipt, "paired_retraining_protocol_sha256", PROTOCOL_SHA256)
    _require_equal(mask_receipt, "single_mask_restores_released_training_data_for_531_basins", True)
    _require_false(mask_receipt, "registered_matrix_modified")
    _require_equal(mask_audit["scope"], "basin_count", 531)
    _require_false(mask_audit["scope"], "installed_package_modified")
    _require_false(mask_audit["scope"], "registered_matrix_modified")
    comparison = mask_audit["author_vs_current_masked"]
    for key in (
        "basins_compared",
        "bitwise_identical_normalized_dynamic_input_basins",
        "bitwise_identical_static_attribute_basins",
        "per_basin_target_standard_deviations_within_1e_6",
    ):
        _require_equal(comparison, key, 531)
    for key in ("metadata_identical", "finite_target_mask_identical"):
        _require_equal(comparison, key, True)
    for key in (
        "masked_minus_author_target_center",
        "masked_minus_author_target_scale",
        "maximum_absolute_common_raw_target_difference",
        "maximum_absolute_target_standard_deviation_difference",
    ):
        _require_equal(comparison, key, 0.0)
    _require_equal(mask_audit["one_factor_contract"], "source_sha256_before", frozen["current_basedataset_sha256"])
    _require_equal(mask_audit["one_factor_contract"], "statement_occurrences_before", 0)
    _require_equal(mask_audit["one_factor_contract"], "statement_occurrences_after", 1)
    _require_equal(mask_audit["one_factor_contract"], "other_installed_source_files_modified", 0)
    _require_equal(mask_audit["source_binding"], "unmasked_evidence_sha256", data_sha)
    _require_equal(mask_audit["conclusion"], "single_mask_restores_released_training_data_for_scope", True)

    return {
        "schema": "nearing2022-warmup-target-pair-entry-gates-v1",
        "protocol_sha256": PROTOCOL_SHA256,
        "data_audit_sha256": data_sha,
        "data_receipt_sha256": _sha256_file(data_receipt_path),
        "mask_audit_sha256": mask_sha,
        "mask_receipt_sha256": _sha256_file(mask_receipt_path),
        "basins": 531,
        "current_only_warmup_targets": current_only,
        "registered_source_scaler_matches_current_audit": True,
        "single_mask_restores_released_training_data_for_531_basins": True,
        "registered_matrix_modified": False,
        "repo_root": str(repo_root),
    }


def _tree_manifest(root: Path, prefix: str = "neuralhydrology") -> dict[str, dict[str, Any]]:
    root = Path(root)
    manifest: dict[str, dict[str, Any]] = {}
    for path in sorted(root.rglob("*"), key=lambda item: item.as_posix()):
        relative = path.relative_to(root)
        if any(part in IGNORED_NAMES for part in relative.parts):
            continue
        if not path.is_file() or path.suffix in IGNORED_SUFFIXES:
            continue
        key = (Path(prefix) / relative).as_posix()
        manifest[key] = {"bytes": path.stat().st_size, "sha256": _sha256_file(path)}
    return manifest


def _manifest_sha256(manifest: dict[str, dict[str, Any]]) -> str:
    encoded = json.dumps(manifest, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return _sha256_bytes(encoded)


def _load_isolation_module(repo_root: Path):
    path = Path(repo_root) / "src/29_nearing2022_da_ar/scripts/audit_warmup_target_isolation.py"
    spec = importlib.util.spec_from_file_location("nearing2022_warmup_isolation_for_pair", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load one-factor helper: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _derive_config(source_path: Path, destination: Path, experiment_id: str, run_dir: Path) -> list[str]:
    source_bytes = Path(source_path).read_bytes()
    text = source_bytes.decode("utf-8")
    lines = text.splitlines(keepends=True)
    replacements = {
        "experiment_name": experiment_id,
        "run_dir": run_dir.resolve().as_posix(),
    }
    counts = {key: 0 for key in replacements}
    derived_lines: list[str] = []
    for line in lines:
        content = line.rstrip("\r\n")
        ending = line[len(content):]
        key = content.split(":", 1)[0] if ":" in content and not content.startswith((" ", "\t")) else None
        if key in replacements:
            counts[key] += 1
            line = f"{key}: {replacements[key]}{ending}"
        derived_lines.append(line)
    if counts != {"experiment_name": 1, "run_dir": 1}:
        raise ValueError(f"Expected one top-level experiment_name and run_dir, got {counts}")
    derived_text = "".join(derived_lines)
    source_config = yaml.safe_load(text)
    derived_config = yaml.safe_load(derived_text)
    changed = sorted(
        key
        for key in set(source_config) | set(derived_config)
        if source_config.get(key) != derived_config.get(key)
    )
    if changed != ["experiment_name", "run_dir"]:
        raise ValueError(f"Derived configuration changed unexpected keys: {changed}")
    destination.write_text(derived_text, encoding="utf-8", newline="")
    return changed


def prepare_arm(repo_root: Path, protocol_path: Path, arm: str, work_root: Path) -> dict[str, Any]:
    """Copy the current runtime and derive one arm while preserving the registered source tree."""
    if arm not in {"control", "masked"}:
        raise ValueError(f"arm must be control or masked, got {arm!r}")
    repo_root = Path(repo_root).resolve()
    work_root = Path(work_root)
    if work_root.exists():
        raise FileExistsError(f"Refusing to replace paired-retraining work root: {work_root}")
    protocol = _load_protocol(protocol_path)
    frozen = protocol["frozen_inputs"]
    config_path = _require_file_hash(repo_root, frozen["configuration"], frozen["configuration_sha256"])
    _require_file_hash(repo_root, frozen["basin_list"], frozen["basin_list_sha256"])
    _require_file_hash(
        repo_root,
        "src/29_nearing2022_da_ar/registry/experiment_registry.csv",
        frozen["training_registry_sha256"],
    )
    _require_file_hash(
        repo_root,
        "src/29_nearing2022_da_ar/registry/evaluation_registry.csv",
        frozen["evaluation_registry_sha256"],
    )
    current_package = repo_root / "neuralhydrology"
    basedataset = current_package / "datasetzoo/basedataset.py"
    if _sha256_file(basedataset) != frozen["current_basedataset_sha256"]:
        raise ValueError("Current BaseDataset hash no longer matches the preregistered source")

    experiment = next(
        item for item in protocol["experiments"] if ("CONTROL" in item["experiment_id"]) == (arm == "control")
    )
    work_root.mkdir(parents=True)
    execution_root = work_root / "execution_root"
    runtime_package = execution_root / "neuralhydrology"
    shutil.copytree(
        current_package,
        runtime_package,
        ignore=shutil.ignore_patterns("__pycache__", "*.pyc", "*.pyo"),
    )
    source_manifest = _tree_manifest(current_package)
    before_manifest = _tree_manifest(runtime_package)
    if source_manifest != before_manifest:
        raise AssertionError("Copied runtime differs from the current package before treatment insertion")

    source_count_before = (runtime_package / "datasetzoo/basedataset.py").read_text(encoding="utf-8").count(
        MASK_STATEMENT
    )
    patch_contract: dict[str, Any] = {
        "statement_occurrences_before": source_count_before,
        "statement_occurrences_after": source_count_before,
    }
    if source_count_before != 0:
        raise ValueError("Current runtime already contains the preregistered warmup-target mask")
    if arm == "masked":
        isolation = _load_isolation_module(repo_root)
        patch_contract = isolation._patch_temporary_source(runtime_package / "datasetzoo/basedataset.py")

    runtime_manifest = _tree_manifest(runtime_package)
    changed_files = sorted(
        path
        for path in set(source_manifest) | set(runtime_manifest)
        if source_manifest.get(path) != runtime_manifest.get(path)
    )
    expected_changed = [] if arm == "control" else ["neuralhydrology/datasetzoo/basedataset.py"]
    if changed_files != expected_changed:
        raise ValueError(f"Prepared {arm} runtime changed unexpected files: {changed_files}")

    training_outputs = work_root / "training_outputs"
    derived_config_path = work_root / "training_config.yml"
    changed_keys = _derive_config(
        config_path,
        derived_config_path,
        experiment["experiment_id"],
        training_outputs,
    )
    manifest_payload = {
        "schema": "nearing2022-warmup-target-runtime-manifest-v1",
        "arm": arm,
        "source": source_manifest,
        "runtime": runtime_manifest,
        "changed_files": changed_files,
    }
    runtime_manifest_path = work_root / "runtime_manifest.json"
    runtime_manifest_path.write_text(
        json.dumps(manifest_payload, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
        newline="\n",
    )
    return {
        "schema": "nearing2022-warmup-target-prepared-arm-v1",
        "arm": arm,
        "experiment_id": experiment["experiment_id"],
        "protocol_sha256": PROTOCOL_SHA256,
        "frozen_config_sha256": _sha256_file(config_path),
        "derived_config": str(derived_config_path.resolve()),
        "derived_config_sha256": _sha256_file(derived_config_path),
        "derived_config_changed_keys": changed_keys,
        "execution_root": str(execution_root.resolve()),
        "runtime_package": str(runtime_package.resolve()),
        "runtime_manifest": str(runtime_manifest_path.resolve()),
        "runtime_manifest_sha256": _sha256_file(runtime_manifest_path),
        "source_tree_sha256": _manifest_sha256(source_manifest),
        "runtime_tree_sha256": _manifest_sha256(runtime_manifest),
        "runtime_files": len(runtime_manifest),
        "changed_files": changed_files,
        "mask_occurrences_before": patch_contract["statement_occurrences_before"],
        "mask_occurrences_after": patch_contract["statement_occurrences_after"],
        "training_output_parent": str(training_outputs.resolve()),
        "final_output_relative": experiment["output_root"],
        "registered_matrix_modified": False,
    }


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", type=Path, required=True)
    parser.add_argument("--protocol", type=Path, required=True)
    parser.add_argument("--data-audit-dir", type=Path, required=True)
    parser.add_argument("--mask-audit-dir", type=Path, required=True)
    parser.add_argument("--arm", choices=("control", "masked"), required=True)
    parser.add_argument("--work-root", type=Path, required=True)
    parser.add_argument("--receipt", type=Path, required=True)
    return parser


def main(argv: Iterable[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)
    if args.receipt.exists():
        raise FileExistsError(f"Refusing to overwrite preparation receipt: {args.receipt}")
    gates = validate_entry_gates(args.repo_root, args.protocol, args.data_audit_dir, args.mask_audit_dir)
    prepared = prepare_arm(args.repo_root, args.protocol, args.arm, args.work_root)
    prepared["entry_gates"] = gates
    args.receipt.parent.mkdir(parents=True, exist_ok=True)
    args.receipt.write_text(
        json.dumps(prepared, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
        newline="\n",
    )
    print(json.dumps(prepared, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

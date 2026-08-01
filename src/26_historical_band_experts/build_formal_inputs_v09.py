"""Authorized production entry for the formal version 09 complete input seal."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess
from typing import Mapping

from artifact_v09 import (
    assert_no_reparse_components,
    canonical_sha256,
    environment_fingerprint_v09,
    promote_directory,
    source_tree_manifest,
)
from audit_formal_inputs_v09 import audit_input_directory_v09, audit_input_source_boundary_v09
from formal_input_authorization_v09 import consume_input_authorization_v09
from formal_input_contract_v09 import (
    DEFAULT_PROTOCOL,
    DEFAULT_TARGET,
    FORMAL_BUILDING_RELATIVE,
    FORMAL_OUTPUT_RELATIVE,
    WORKTREE_ROOT,
    load_formal_input_contract_v09,
    primary_repository_root_v09,
)
from formal_input_resources_v09 import run_input_seal_runtime_v09
from formal_input_v09 import _build_input_directory_v09
from formal_v09_protocol import load_protocol_v09


AUTHORIZATION_RELATIVE = Path(
    "results/26_historical_band_experts/formal_v09/authorizations/formal_input_seal_authorization.json"
)
CONSUMPTION_RELATIVE = Path(
    "results/26_historical_band_experts/formal_v09/formal_input_seal_authorization_consumed.json"
)
SOURCE_TREE_FILES_V09 = (
    "src/26_historical_band_experts/configs/formal_v09_protocol.json",
    "src/26_historical_band_experts/artifact_v09.py",
    "src/26_historical_band_experts/audit_formal_inputs_v09.py",
    "src/26_historical_band_experts/build_formal_inputs_v09.py",
    "src/26_historical_band_experts/data.py",
    "src/26_historical_band_experts/formal_input_authorization_v09.py",
    "src/26_historical_band_experts/formal_input_contract_v09.py",
    "src/26_historical_band_experts/formal_input_resources_v09.py",
    "src/26_historical_band_experts/formal_input_sources_v09.py",
    "src/26_historical_band_experts/formal_input_v09.py",
    "src/26_historical_band_experts/formal_v09_protocol.py",
    "src/26_historical_band_experts/memory_safety_v09.py",
    "src/fair_benchmark/task_memory_v09.py",
)
BOUNDARY_SCANNED_FILES_V09 = (
    "src/26_historical_band_experts/artifact_v09.py",
    "src/26_historical_band_experts/audit_formal_inputs_v09.py",
    "src/26_historical_band_experts/build_formal_inputs_v09.py",
    "src/26_historical_band_experts/data.py",
    "src/26_historical_band_experts/formal_input_authorization_v09.py",
    "src/26_historical_band_experts/formal_input_contract_v09.py",
    "src/26_historical_band_experts/formal_input_resources_v09.py",
    "src/26_historical_band_experts/formal_input_sources_v09.py",
    "src/26_historical_band_experts/formal_input_v09.py",
)


def _require_clean_worktree() -> str:
    status = subprocess.run(
        ["git", "status", "--porcelain", "--untracked-files=all"],
        cwd=WORKTREE_ROOT,
        capture_output=True,
        text=True,
        check=True,
    )
    if status.stdout:
        raise ValueError("formal input sealing requires a clean reviewed Git worktree")
    return subprocess.run(
        ["git", "rev-parse", "HEAD"],
        cwd=WORKTREE_ROOT,
        capture_output=True,
        text=True,
        check=True,
    ).stdout.strip()


def _assert_formal_path_boundaries_v09(
    *,
    authorization_path: Path,
    consumption_path: Path,
    building_root: Path,
    final_root: Path,
    static_path: Path,
    target_path: Path,
    data_root: Path,
) -> None:
    for path in (
        authorization_path,
        consumption_path,
        building_root,
        final_root,
        static_path,
        target_path,
    ):
        assert_no_reparse_components(WORKTREE_ROOT, path)
    assert_no_reparse_components(primary_repository_root_v09(), data_root)


def reviewed_input_source_tree_v09() -> dict:
    """Return the exact clean source and environment object used by future authorization."""
    commit = _require_clean_worktree()
    source_tree = source_tree_manifest(WORKTREE_ROOT, SOURCE_TREE_FILES_V09)
    source_tree["git_commit"] = commit
    source_tree["git_worktree_clean"] = True
    source_tree["environment"] = environment_fingerprint_v09(WORKTREE_ROOT)
    if source_tree["environment"]["git_clean"] is not True:
        raise ValueError("formal input environment fingerprint requires a clean worktree")
    return source_tree


def build_formal_input_seal_v09() -> dict:
    """Consume one later authorization and publish only the fixed complete-input directory."""
    contract = load_formal_input_contract_v09()
    authorization_path = WORKTREE_ROOT / AUTHORIZATION_RELATIVE
    consumption_path = WORKTREE_ROOT / CONSUMPTION_RELATIVE
    building_root = WORKTREE_ROOT / FORMAL_BUILDING_RELATIVE
    final_root = WORKTREE_ROOT / FORMAL_OUTPUT_RELATIVE
    static_path = WORKTREE_ROOT / contract["static_file"]
    target_path = DEFAULT_TARGET
    data_root = primary_repository_root_v09() / "data/camels_us"
    boundary_paths = {
        "authorization_path": authorization_path,
        "consumption_path": consumption_path,
        "building_root": building_root,
        "final_root": final_root,
        "static_path": static_path,
        "target_path": target_path,
        "data_root": data_root,
    }
    _assert_formal_path_boundaries_v09(**boundary_paths)
    if not authorization_path.is_file():
        raise FileNotFoundError("formal complete-input production authorization does not exist")
    for path in (consumption_path, building_root, final_root):
        if path.exists():
            raise FileExistsError(f"formal complete-input precondition path already exists: {path}")
    source_tree = reviewed_input_source_tree_v09()
    protocol = load_protocol_v09(DEFAULT_PROTOCOL)
    audit_input_source_boundary_v09(
        WORKTREE_ROOT,
        relative_paths=BOUNDARY_SCANNED_FILES_V09,
        protocol=protocol,
    )

    def build(runtime):
        consumption = consume_input_authorization_v09(
            authorization_path,
            consumption_path,
            contract=contract,
            source_tree=source_tree,
            consumed_utc=__import__("datetime").datetime.now(
                __import__("datetime").timezone.utc
            ).isoformat().replace("+00:00", "Z"),
            trusted_root=WORKTREE_ROOT,
        )
        _assert_formal_path_boundaries_v09(**boundary_paths)
        resource_evidence = {
            "estimate": runtime.estimate,
            "start": runtime.start_report,
            "entry": runtime.entry_report,
            "entry_checkpoint": runtime.checkpoint(),
        }
        _build_input_directory_v09(
            contract=contract,
            data_root=data_root,
            static_path=static_path,
            target_path=target_path,
            building_root=building_root,
            source_tree=source_tree,
            resource_evidence=resource_evidence,
            authorization_consumption={
                **consumption,
                "consumption_canonical_sha256": canonical_sha256(consumption),
            },
            authorization_path=authorization_path,
            consumption_path=consumption_path,
            runtime=runtime,
        )
        runtime.checkpoint()
        _assert_formal_path_boundaries_v09(**boundary_paths)
        promote_directory(building_root, final_root, trusted_root=WORKTREE_ROOT)
        _assert_formal_path_boundaries_v09(**boundary_paths)
        return audit_input_directory_v09(
            final_root,
            contract=contract,
            require_seal=True,
            data_root=data_root,
            static_path=static_path,
            target_path=target_path,
            authorization_path=authorization_path,
            consumption_path=consumption_path,
        )

    run_report = run_input_seal_runtime_v09(contract, callback=build)
    return {
        "status": "formal_complete_input_sealed",
        "result": run_report["result"],
        "estimate": run_report["estimate"],
        "start": run_report["start"],
        "entry": run_report["entry"],
        "output": FORMAL_OUTPUT_RELATIVE.as_posix(),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.parse_args()
    print(json.dumps(build_formal_input_seal_v09(), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()

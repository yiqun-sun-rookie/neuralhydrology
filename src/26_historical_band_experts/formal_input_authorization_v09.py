"""One-time external authorization contract for formal version 09 input sealing."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
from typing import Mapping

from artifact_v09 import (
    assert_no_reparse_components,
    canonical_sha256,
    sha256_file,
    write_json_atomic,
)


PRODUCTION_APPROVAL_TEXT = "批准版本09正式完整输入封存生成；不批准训练、正式预测或评分。"
_ACTION = "formal_input_seal_generation"


def _approval_sha256(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def create_input_authorization_v09(
    *,
    approval_text: str,
    contract: Mapping,
    source_tree: Mapping,
    created_utc: str,
) -> dict:
    """Construct, but do not write, an authorization after the exact future approval."""
    if approval_text != PRODUCTION_APPROVAL_TEXT:
        raise ValueError("formal input generation requires the exact future production approval")
    return {
        "schema": "historical_multiscale_formal_v09_input_authorization_v1",
        "status": "authorized_once",
        "allowed_action": _ACTION,
        "maximum_attempts": 1,
        "created_utc": str(created_utc),
        "approval": {
            "text": approval_text,
            "sha256": _approval_sha256(approval_text),
        },
        "contract_sha256": contract["contract_sha256"],
        "protocol_raw_sha256": contract["protocol_raw_sha256"],
        "protocol_canonical_sha256": contract["protocol_canonical_sha256"],
        "target_bundle_sha256": contract["target_bundle_sha256"],
        "target_manifest_sha256": contract["target_manifest_sha256"],
        "allowed_output": contract["formal_output"],
        "source_tree": dict(source_tree),
    }


def validate_input_authorization_v09(
    receipt: Mapping,
    *,
    contract: Mapping,
    source_tree: Mapping,
) -> dict:
    expected = create_input_authorization_v09(
        approval_text=PRODUCTION_APPROVAL_TEXT,
        contract=contract,
        source_tree=source_tree,
        created_utc=str(receipt.get("created_utc", "")),
    )
    if dict(receipt) != expected:
        if receipt.get("source_tree") != source_tree:
            raise ValueError("authorization source tree binding drift")
        raise ValueError("authorization receipt differs from the exact one-attempt contract")
    return expected


def consume_input_authorization_v09(
    authorization_path: str | Path,
    consumption_path: str | Path,
    *,
    contract: Mapping,
    source_tree: Mapping,
    consumed_utc: str,
    trusted_root: str | Path | None = None,
) -> dict:
    """Atomically record the sole permitted attempt before any formal output is built."""
    authorization_path = Path(os.path.abspath(authorization_path))
    consumption_path = Path(os.path.abspath(consumption_path))
    boundary_root = (
        Path(os.path.abspath(trusted_root))
        if trusted_root is not None
        else Path(os.path.commonpath((authorization_path, consumption_path)))
    )
    assert_no_reparse_components(boundary_root, authorization_path)
    assert_no_reparse_components(boundary_root, consumption_path)
    if consumption_path.exists():
        raise FileExistsError("formal input authorization was already consumed")
    receipt = json.loads(authorization_path.read_text(encoding="utf-8"))
    validated = validate_input_authorization_v09(
        receipt,
        contract=contract,
        source_tree=source_tree,
    )
    consumption = {
        "schema": "historical_multiscale_formal_v09_input_authorization_consumption_v1",
        "status": "consumed_once",
        "allowed_action": _ACTION,
        "consumed_utc": str(consumed_utc),
        "authorization_file_sha256": sha256_file(authorization_path),
        "authorization_canonical_sha256": canonical_sha256(validated),
        "contract_sha256": contract["contract_sha256"],
        "source_tree_sha256": source_tree["tree_sha256"],
    }
    assert_no_reparse_components(boundary_root, authorization_path)
    assert_no_reparse_components(boundary_root, consumption_path)
    write_json_atomic(consumption_path, consumption)
    assert_no_reparse_components(boundary_root, authorization_path)
    assert_no_reparse_components(boundary_root, consumption_path)
    return consumption

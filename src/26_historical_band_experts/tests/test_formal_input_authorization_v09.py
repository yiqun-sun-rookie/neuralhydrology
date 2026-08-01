import json
from pathlib import Path
import sys

import pytest


IDEA_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(IDEA_ROOT))


def _contract():
    return {
        "contract_sha256": "1" * 64,
        "protocol_raw_sha256": "2" * 64,
        "protocol_canonical_sha256": "3" * 64,
        "target_bundle_sha256": "4" * 64,
        "target_manifest_sha256": "5" * 64,
        "formal_output": "results/26_historical_band_experts/formal_v09/input_attempt_01",
    }


def _tree():
    return {"schema": "exact_source_tree_v1", "files": [], "tree_sha256": "6" * 64}


def test_authorization_requires_future_generation_approval_not_current_code_approval():
    from formal_input_authorization_v09 import (
        PRODUCTION_APPROVAL_TEXT,
        create_input_authorization_v09,
    )

    with pytest.raises(ValueError, match="exact future production approval"):
        create_input_authorization_v09(
            approval_text="批准设计并实现代码；不批准生成正式输入。",
            contract=_contract(),
            source_tree=_tree(),
            created_utc="2026-08-01T00:00:00Z",
        )
    receipt = create_input_authorization_v09(
        approval_text=PRODUCTION_APPROVAL_TEXT,
        contract=_contract(),
        source_tree=_tree(),
        created_utc="2026-08-01T00:00:00Z",
    )
    assert receipt["maximum_attempts"] == 1
    assert receipt["allowed_action"] == "formal_input_seal_generation"


def test_validation_rejects_contract_source_tree_and_receipt_tampering():
    from formal_input_authorization_v09 import (
        PRODUCTION_APPROVAL_TEXT,
        create_input_authorization_v09,
        validate_input_authorization_v09,
    )

    receipt = create_input_authorization_v09(
        approval_text=PRODUCTION_APPROVAL_TEXT,
        contract=_contract(),
        source_tree=_tree(),
        created_utc="2026-08-01T00:00:00Z",
    )
    validate_input_authorization_v09(receipt, contract=_contract(), source_tree=_tree())
    drift = dict(receipt)
    drift["maximum_attempts"] = 2
    with pytest.raises(ValueError):
        validate_input_authorization_v09(drift, contract=_contract(), source_tree=_tree())
    changed_tree = dict(_tree())
    changed_tree["tree_sha256"] = "7" * 64
    with pytest.raises(ValueError, match="source tree"):
        validate_input_authorization_v09(receipt, contract=_contract(), source_tree=changed_tree)


def test_consumption_is_atomic_and_replay_is_rejected(tmp_path):
    from artifact_v09 import write_json_atomic
    from formal_input_authorization_v09 import (
        PRODUCTION_APPROVAL_TEXT,
        consume_input_authorization_v09,
        create_input_authorization_v09,
    )

    authorization = create_input_authorization_v09(
        approval_text=PRODUCTION_APPROVAL_TEXT,
        contract=_contract(),
        source_tree=_tree(),
        created_utc="2026-08-01T00:00:00Z",
    )
    authorization_path = tmp_path / "authorization.json"
    consumption_path = tmp_path / "consumed.json"
    write_json_atomic(authorization_path, authorization)
    report = consume_input_authorization_v09(
        authorization_path,
        consumption_path,
        contract=_contract(),
        source_tree=_tree(),
        consumed_utc="2026-08-01T01:00:00Z",
    )
    assert report["status"] == "consumed_once"
    assert json.loads(consumption_path.read_text(encoding="utf-8")) == report
    with pytest.raises(FileExistsError):
        consume_input_authorization_v09(
            authorization_path,
            consumption_path,
            contract=_contract(),
            source_tree=_tree(),
            consumed_utc="2026-08-01T02:00:00Z",
        )

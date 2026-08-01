from pathlib import Path
import sys

import numpy as np
import pytest


IDEA_ROOT = Path(__file__).resolve().parents[1]
TEST_ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(IDEA_ROOT))
sys.path.insert(0, str(TEST_ROOT))

from synthetic_input_case_v09 import build_synthetic_case


def test_post_seal_audit_is_read_only_and_idempotent(tmp_path):
    from audit_formal_inputs_v09 import audit_input_directory_v09

    case, root = build_synthetic_case(tmp_path)
    before = {path.name: path.read_bytes() for path in root.iterdir()}
    source_args = {
        "data_root": case["data_root"],
        "static_path": case["static_path"],
        "target_path": case["target_path"],
    }
    first = audit_input_directory_v09(
        root, contract=case["contract"], require_seal=True, **source_args
    )
    second = audit_input_directory_v09(
        root, contract=case["contract"], require_seal=True, **source_args
    )
    after = {path.name: path.read_bytes() for path in root.iterdir()}
    assert first == second
    assert before == after
    assert first["formal_evaluation_targets_present"] == 0


def test_audit_rejects_array_tampering(tmp_path):
    from audit_formal_inputs_v09 import audit_input_directory_v09

    case, root = build_synthetic_case(tmp_path)
    path = root / "forcing.npy"
    payload = bytearray(path.read_bytes())
    payload[-1] ^= 1
    path.write_bytes(payload)
    with pytest.raises(ValueError, match="differs from the frozen Maurer source"):
        audit_input_directory_v09(
            root,
            contract=case["contract"],
            require_seal=True,
            data_root=case["data_root"],
            static_path=case["static_path"],
            target_path=case["target_path"],
        )


def test_audit_rejects_target_value_even_before_manifest_hash_checks(tmp_path):
    from audit_formal_inputs_v09 import audit_input_directory_v09

    case, root = build_synthetic_case(tmp_path)
    targets = np.load(root / "targets.npy", mmap_mode="r+", allow_pickle=False)
    targets[0, 0] += np.float32(1.0)
    targets.flush()
    del targets
    with pytest.raises(ValueError, match="differs from the audited target CSV"):
        audit_input_directory_v09(
            root,
            contract=case["contract"],
            require_seal=True,
            data_root=case["data_root"],
            static_path=case["static_path"],
            target_path=case["target_path"],
        )


def test_audit_rejects_extra_file(tmp_path):
    from audit_formal_inputs_v09 import audit_input_directory_v09

    case, root = build_synthetic_case(tmp_path)
    (root / "unexpected.tmp").write_text("x", encoding="utf-8")
    with pytest.raises(ValueError, match="inventory"):
        audit_input_directory_v09(
            root,
            contract=case["contract"],
            require_seal=True,
            data_root=case["data_root"],
            static_path=case["static_path"],
            target_path=case["target_path"],
        )


def test_independent_resource_evidence_rejects_guard_or_lock_drift():
    from audit_formal_inputs_v09 import _audit_resource_evidence
    from formal_input_resources_v09 import (
        build_input_seal_peak_estimate_v09,
        formal_input_lock_path_v09,
    )

    contract = {
        "contract_sha256": "a" * 64,
        "basin_count": 3,
        "static_columns": [f"s{index}" for index in range(27)],
        "target_shape": [3, 4],
    }
    estimate = build_input_seal_peak_estimate_v09(contract)
    guarded = (estimate["estimated_peak_bytes"] * 5 + 3) // 4
    start = {
        "safe": True,
        "guarded_estimated_peak_bytes": guarded,
        "physical_reserve_bytes": 2 * 2**30,
        "commit_headroom_reserve_bytes": 2 * 2**30,
        "available_after_guarded_peak_bytes": 3 * 2**30,
        "commit_headroom_after_guarded_peak_bytes": 4 * 2**30,
        "serial_lease": {
            "held": True,
            "lock_path": str(formal_input_lock_path_v09()),
        },
    }
    resource = {
        "estimate": estimate,
        "start": start,
        "entry": dict(start),
        "entry_checkpoint": {
            "safe": True,
            "available_bytes": 3 * 2**30,
            "commit_headroom_bytes": 4 * 2**30,
        },
    }
    _audit_resource_evidence(resource, contract)
    resource["entry"]["serial_lease"] = {"held": False}
    with pytest.raises(ValueError, match="entry evidence"):
        _audit_resource_evidence(resource, contract)


def test_independent_authorization_evidence_rejects_manifest_drift(tmp_path):
    from artifact_v09 import canonical_sha256, write_json_atomic
    from audit_formal_inputs_v09 import _audit_authorization_evidence
    from formal_input_authorization_v09 import (
        PRODUCTION_APPROVAL_TEXT,
        consume_input_authorization_v09,
        create_input_authorization_v09,
    )

    contract = {
        "contract_sha256": "1" * 64,
        "protocol_raw_sha256": "2" * 64,
        "protocol_canonical_sha256": "3" * 64,
        "target_bundle_sha256": "4" * 64,
        "target_manifest_sha256": "5" * 64,
        "formal_output": "results/26_historical_band_experts/formal_v09/input_attempt_01",
    }
    source_tree = {
        "schema": "exact_source_tree_v1",
        "files": [{"relative_path": "x.py", "sha256": "6" * 64}],
        "tree_sha256": "7" * 64,
    }
    authorization = create_input_authorization_v09(
        approval_text=PRODUCTION_APPROVAL_TEXT,
        contract=contract,
        source_tree=source_tree,
        created_utc="2026-08-01T00:00:00Z",
    )
    authorization_path = tmp_path / "authorization.json"
    consumption_path = tmp_path / "consumption.json"
    write_json_atomic(authorization_path, authorization)
    consumption = consume_input_authorization_v09(
        authorization_path,
        consumption_path,
        contract=contract,
        source_tree=source_tree,
        consumed_utc="2026-08-01T01:00:00Z",
    )
    manifest = {
        "authorization_consumption": {
            **consumption,
            "consumption_canonical_sha256": canonical_sha256(consumption),
        }
    }
    _audit_authorization_evidence(
        manifest=manifest,
        contract=contract,
        source_tree=source_tree,
        authorization_path=authorization_path,
        consumption_path=consumption_path,
    )
    manifest["authorization_consumption"]["contract_sha256"] = "8" * 64
    with pytest.raises(ValueError, match="manifest authorization"):
        _audit_authorization_evidence(
            manifest=manifest,
            contract=contract,
            source_tree=source_tree,
            authorization_path=authorization_path,
            consumption_path=consumption_path,
        )


def test_formal_provenance_fails_before_any_array_load(tmp_path, monkeypatch):
    import json
    import audit_formal_inputs_v09 as module
    from formal_input_v09 import CORE_ARTIFACTS_V09

    for name in CORE_ARTIFACTS_V09:
        (tmp_path / name).write_bytes(b"placeholder")
    contract = {
        "schema": "historical_multiscale_formal_v09_complete_input_contract_v1",
        "contract_sha256": "a" * 64,
    }
    (tmp_path / "manifest.json").write_text(
        json.dumps({
            "status": "complete_before_audit",
            "contract_sha256": contract["contract_sha256"],
        }),
        encoding="utf-8",
    )
    monkeypatch.setattr(
        module,
        "_audit_formal_path_boundaries",
        lambda **kwargs: None,
    )
    monkeypatch.setattr(
        module,
        "_audit_formal_provenance",
        lambda **kwargs: (_ for _ in ()).throw(ValueError("provenance first")),
    )
    monkeypatch.setattr(
        module.np,
        "load",
        lambda *args, **kwargs: (_ for _ in ()).throw(AssertionError("array loaded too early")),
    )
    with pytest.raises(ValueError, match="provenance first"):
        module.audit_input_directory_v09(
            tmp_path,
            contract=contract,
            require_seal=False,
            data_root=tmp_path,
            static_path=tmp_path / "static.csv",
            target_path=tmp_path / "target.csv",
        )


def test_formal_path_boundaries_are_checked_before_inventory_walk(tmp_path, monkeypatch):
    import audit_formal_inputs_v09 as module

    contract = {
        "schema": "historical_multiscale_formal_v09_complete_input_contract_v1",
        "contract_sha256": "a" * 64,
    }
    monkeypatch.setattr(
        module,
        "_audit_formal_path_boundaries",
        lambda **kwargs: (_ for _ in ()).throw(ValueError("formal paths first")),
    )
    monkeypatch.setattr(
        Path,
        "rglob",
        lambda *args, **kwargs: (_ for _ in ()).throw(AssertionError("inventory walked too early")),
    )
    with pytest.raises(ValueError, match="formal paths first"):
        module.audit_input_directory_v09(
            tmp_path,
            contract=contract,
            require_seal=False,
            data_root=tmp_path,
            static_path=tmp_path / "static.csv",
            target_path=tmp_path / "target.csv",
            authorization_path=tmp_path / "authorization.json",
            consumption_path=tmp_path / "consumption.json",
        )

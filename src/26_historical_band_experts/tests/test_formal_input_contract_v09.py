import copy
import json
from pathlib import Path
import sys

import pytest


IDEA_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(IDEA_ROOT))


def test_live_contract_binds_all_allowed_inputs_and_keeps_actions_closed():
    from formal_input_contract_v09 import (
        DYNAMIC_COLUMNS_V09,
        FORMAL_V09_STATIC_COLUMNS,
        load_formal_input_contract_v09,
    )

    contract = load_formal_input_contract_v09()
    assert contract["basin_count"] == 531
    assert contract["forcing_shape"] == [531, 10501, 5]
    assert contract["target_shape"] == [531, 3288]
    assert contract["dynamic_columns"] == list(DYNAMIC_COLUMNS_V09)
    assert contract["static_columns"] == list(FORMAL_V09_STATIC_COLUMNS)
    assert FORMAL_V09_STATIC_COLUMNS == tuple(sorted(FORMAL_V09_STATIC_COLUMNS))
    assert len(contract["maurer_sources"]) == 531
    assert [item["basin"] for item in contract["maurer_sources"]] == contract["basins"]
    assert contract["target_bundle_sha256"] == (
        "6abadf7172f1c8ebd48122a8abf68985d7d4f94b8c894371270208eeb45f2ebb"
    )
    assert contract["target_manifest_sha256"] == (
        "3061d548fa0b9c81c8e3e25f0dbdd8cfbdb347aaea965ac6f6400c5f09da13e8"
    )
    assert all(value is False for key, value in contract["authorization"].items() if key != "protocol_implementation" and key != "synthetic_tests")
    assert contract["formal_evaluation_target_access"] is False


def test_contract_rejects_any_authorization_or_target_hash_drift(tmp_path):
    from formal_input_contract_v09 import load_formal_input_contract_v09

    protocol_path = IDEA_ROOT / "configs/formal_v09_protocol.json"
    protocol = json.loads(protocol_path.read_text(encoding="utf-8"))
    drift = copy.deepcopy(protocol)
    drift["authorization"]["training"] = True
    drift_path = tmp_path / "protocol.json"
    drift_path.write_text(json.dumps(drift), encoding="utf-8")
    with pytest.raises(ValueError):
        load_formal_input_contract_v09(protocol_path=drift_path)

    target = tmp_path / "targets.csv"
    target.write_text("basin,date,qobs\n", encoding="utf-8")
    with pytest.raises(ValueError, match="target bundle SHA-256"):
        load_formal_input_contract_v09(target_path=target)


def test_contract_rejects_incomplete_or_reordered_maurer_inventory(tmp_path):
    from formal_input_contract_v09 import load_formal_input_contract_v09

    live_manifest = json.loads(
        (IDEA_ROOT.parents[1] / "results/26_historical_band_experts/formal_v09/inputs/training_targets.manifest.json").read_text(encoding="utf-8")
    )
    live_manifest["source_files"] = [
        item for item in live_manifest["source_files"] if item.get("kind") != "maurer"
    ]
    path = tmp_path / "manifest.json"
    path.write_text(json.dumps(live_manifest), encoding="utf-8")
    with pytest.raises(ValueError, match="Maurer source inventory"):
        load_formal_input_contract_v09(target_manifest_path=path, expected_target_manifest_sha256=None)

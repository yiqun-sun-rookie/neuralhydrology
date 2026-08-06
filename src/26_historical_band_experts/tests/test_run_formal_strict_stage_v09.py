from pathlib import Path
import inspect
import json
import sys

import pytest

IDEA_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(IDEA_ROOT))

GIB = 2**30
MIB = 2**20


def _valid_legacy_report(protocol, input_bindings=None):
    from artifact_v09 import canonical_sha256
    from audit_legacy_checkpoint_bridge_v09 import _environment_binding_v09, _source_bindings_v09

    rows = protocol["basin_count"] * 12
    runs = protocol["legacy_reference"]["runs"]
    if input_bindings is None:
        input_bindings = {
            "input_seal_sha256": "1" * 64,
            "complete_input_external_audit_sha256": "2" * 64,
            "trusted_source_external_audit_sha256": "3" * 64,
        }
    return {
        "schema": "historical_multiscale_formal_v09_legacy_checkpoint_bridge_audit_v1",
        "status": "legacy_checkpoint_bridge_external_audit_passed",
        "protocol_canonical_sha256": canonical_sha256(protocol),
        "source_bindings": _source_bindings_v09(),
        "environment_binding": _environment_binding_v09("cuda:0"),
        "input_bindings": dict(input_bindings),
        "legacy_dynamic_input_names": ["PRCP(mm/day)", "Tmin(C)", "Tmax(C)", "SRAD(W/m2)", "Vp(Pa)"],
        "verified_identity": {
            "verified": True,
            "run_count": 8,
            "file_count": 16,
            "seeds": [run["seed"] for run in runs],
            "recorded_code_commit_prefix": protocol["legacy_reference"]["recorded_code_commit_prefix"],
        },
        "runs": [{
            "seed": run["seed"],
            "run_id": run["run_id"],
            "config_sha256": run["config_sha256"],
            "checkpoint_sha256": run["checkpoint_epoch030_sha256"],
            "real_panel_rows": rows,
        } for run in runs],
        "run_count": 8,
        "synthetic_panel_rows_per_run": 2,
        "real_panel_rows_per_run": rows,
        "real_panel_rows_total": rows * 8,
        "maximum_prediction_difference": 0.0,
        "training_target_value_reads": 0,
        "formal_evaluation_observation_reads": 0,
    }


def _valid_resource_report(protocol, tmp_path, *, lease=None):
    from formal_action_resources_v09 import AcceleratorMemorySnapshot
    from formal_action_runtime_v09 import (
        _audit_formal_action_resources_under_lease_v09,
        _audit_formal_action_resources_v09,
    )
    from memory_safety_v09 import HostMemorySnapshot

    kwargs = {
        "action": "training",
        "variant": "strict_nesting_pair",
        "host_snapshot": HostMemorySnapshot(32 * GIB, 16 * GIB, 256 * MIB, 30 * GIB),
        "accelerator_snapshot": AcceleratorMemorySnapshot(0, "synthetic-cuda", 16 * GIB, 12 * GIB),
    }
    if lease is not None:
        return _audit_formal_action_resources_under_lease_v09(protocol, lease=lease, **kwargs)
    return _audit_formal_action_resources_v09(protocol, lock_path=None, **kwargs)


def test_production_strict_entry_has_no_runtime_arguments_and_fixed_claim_paths():
    from run_formal_strict_stage_v09 import run_formal_strict_stage_v09, strict_stage_paths_v09

    assert not inspect.signature(run_formal_strict_stage_v09).parameters
    paths = strict_stage_paths_v09(IDEA_ROOT.parents[1])
    assert paths.output_root.name == "R09-NEST-S100"
    assert paths.authorization.name == "A09-NEST-01.authorization.json"
    assert paths.consumption.name == "A09-NEST-01.consumption.json"


def test_strict_prerequisite_hashes_reject_wrong_resource_variant(tmp_path):
    from formal_v09_protocol import load_protocol_v09
    from run_formal_strict_stage_v09 import StrictStagePathsV09, strict_prerequisite_hashes_v09

    input_root = tmp_path / "input"
    input_root.mkdir()
    protocol = load_protocol_v09(IDEA_ROOT / "configs/formal_v09_protocol.json")
    input_payloads = {
        input_root / "seal.json": {
            "status": "sealed"
        },
        tmp_path / "input.audit.json": {
            "status": "complete_input_audit_passed"
        },
        tmp_path / "trusted.audit.json": {
            "status": "complete_trusted_training_target_audit"
        },
    }
    for path, payload in input_payloads.items():
        path.write_text(json.dumps(payload), encoding="utf-8")
    from run_formal_strict_stage_v09 import strict_input_bindings_v09
    binding_paths = StrictStagePathsV09(
        worktree_root=tmp_path,
        protocol=tmp_path / "protocol.json",
        input_root=input_root,
        input_external_audit=tmp_path / "input.audit.json",
        trusted_source_audit=tmp_path / "trusted.audit.json",
        legacy_bridge_audit=tmp_path / "legacy.audit.json",
        resource_preflight_audit=tmp_path / "resource.audit.json",
        authorization=tmp_path / "authorization.json",
        consumption=tmp_path / "consumption.json",
        output_root=tmp_path / "output",
    )
    files = {
        tmp_path / "legacy.audit.json": _valid_legacy_report(protocol, strict_input_bindings_v09(binding_paths)),
        tmp_path / "resource.audit.json": _valid_resource_report(protocol, tmp_path),
    }
    files[tmp_path / "resource.audit.json"]["variant"] = "classic_lstm_256_clean"
    for path, payload in files.items():
        path.write_text(json.dumps(payload), encoding="utf-8")
    paths = binding_paths
    with pytest.raises(ValueError, match="resource preflight binding"):
        strict_prerequisite_hashes_v09(paths, protocol)


@pytest.mark.parametrize(
    ("mutation", "message"),
    [
        (lambda report: report.__setitem__("authorization_checked", True), "authorization"),
        (lambda report: report["estimate"].__setitem__("estimated_peak_bytes", 1), "estimate"),
        (lambda report: report["host"].__setitem__("safe", False), "host"),
        (lambda report: report["host"]["serial_lease"].__setitem__("held", False), "lease"),
        (lambda report: report["accelerator"].__setitem__("safe", False), "accelerator"),
        (lambda report: report["host_snapshot"].__setitem__("available_bytes", 0), "host arithmetic"),
        (lambda report: report["host_snapshot"].__setitem__("total_bytes", float(32 * GIB)), "type"),
        (lambda report: report["accelerator_snapshot"].__setitem__("device_index", 1), "device"),
        (lambda report: report["accelerator_snapshot"].__setitem__("device_index", False), "type"),
        (lambda report: report["accelerator_snapshot"].__setitem__("available_bytes", 0), "accelerator arithmetic"),
        (lambda report: report["host"].__setitem__("unexpected", True), "host"),
        (lambda report: report["accelerator"].__setitem__("unexpected", True), "accelerator"),
        (lambda report: report["host"]["serial_lease"].__setitem__("lock_path", "wrong"), "lease"),
        (lambda report: report.__setitem__("unexpected", True), "schema"),
    ],
)
def test_resource_preflight_report_is_recomputed_at_strict_launch(tmp_path, mutation, message):
    from formal_v09_protocol import load_protocol_v09
    from run_formal_strict_stage_v09 import _validate_resource_preflight_report_v09

    protocol = load_protocol_v09(IDEA_ROOT / "configs/formal_v09_protocol.json")
    report = _valid_resource_report(protocol, tmp_path)
    mutation(report)
    with pytest.raises(ValueError, match=message):
        _validate_resource_preflight_report_v09(report, protocol)


def test_resource_preflight_report_accepts_exact_current_protocol(tmp_path):
    from formal_v09_protocol import load_protocol_v09
    from run_formal_strict_stage_v09 import _validate_resource_preflight_report_v09

    protocol = load_protocol_v09(IDEA_ROOT / "configs/formal_v09_protocol.json")
    _validate_resource_preflight_report_v09(_valid_resource_report(protocol, tmp_path), protocol)


def test_status_and_hash_are_computed_from_the_same_file_bytes(tmp_path):
    import hashlib
    from run_formal_strict_stage_v09 import _load_json_status_and_sha256

    payload = b'{"status":"expected","value":1}\n'
    path = tmp_path / "report.json"
    path.write_bytes(payload)

    report, digest = _load_json_status_and_sha256(path, "expected")

    assert report == {"status": "expected", "value": 1}
    assert digest == hashlib.sha256(payload).hexdigest()


@pytest.mark.parametrize(
    ("field", "replacement", "message"),
    [
        ("protocol_canonical_sha256", "0" * 64, "protocol binding"),
        ("source_bindings", {}, "source binding"),
        ("environment_binding", {}, "environment binding"),
        ("input_bindings", {}, "input_bindings"),
        ("run_count", 7, "report geometry"),
        ("unexpected", True, "schema"),
    ],
)
def test_legacy_bridge_report_is_recomputed_at_strict_launch(field, replacement, message):
    from formal_v09_protocol import load_protocol_v09
    from run_formal_strict_stage_v09 import _validate_legacy_bridge_report_v09

    protocol = load_protocol_v09(IDEA_ROOT / "configs/formal_v09_protocol.json")
    expected_input_bindings = _valid_legacy_report(protocol)["input_bindings"]
    report = _valid_legacy_report(protocol)
    report[field] = replacement
    with pytest.raises(ValueError, match=message):
        _validate_legacy_bridge_report_v09(
            report,
            protocol,
            device="cuda:0",
            input_bindings=expected_input_bindings,
        )


def test_legacy_bridge_report_rejects_boolean_alias_for_zero_count():
    from formal_v09_protocol import load_protocol_v09
    from run_formal_strict_stage_v09 import _validate_legacy_bridge_report_v09

    protocol = load_protocol_v09(IDEA_ROOT / "configs/formal_v09_protocol.json")
    report = _valid_legacy_report(protocol)
    report["training_target_value_reads"] = False

    with pytest.raises(ValueError, match="type drift"):
        _validate_legacy_bridge_report_v09(
            report,
            protocol,
            device="cuda:0",
            input_bindings={
                "input_seal_sha256": "1" * 64,
                "complete_input_external_audit_sha256": "2" * 64,
                "trusted_source_external_audit_sha256": "3" * 64,
            },
        )


def test_strict_executable_tree_is_deterministic_and_binds_entry():
    from run_formal_strict_stage_v09 import strict_executable_tree_v09

    root = IDEA_ROOT.parents[1]
    first = strict_executable_tree_v09(root)
    second = strict_executable_tree_v09(root)
    assert first == second
    assert any(row["relative_path"].endswith("run_formal_strict_stage_v09.py") for row in first["files"])
    assert len(first["tree_sha256"]) == 64

"""Contract tests for the two closed strict-stage entries that had no production path.

`create_stage_authorization_v09` and `audit_strict_run_v09` existed only as library functions
called from tests, while `run_formal_strict_stage_v09` hard-fails without an authorization file.
These tests pin the closed contract of the two entries that connect them.
"""
from pathlib import Path
import inspect
import json
import sys

import pytest

IDEA_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(IDEA_ROOT))

from test_prepare_formal_strict_stage_v09 import _paths
from test_run_formal_strict_stage_v09 import _valid_legacy_report, _valid_resource_report

_HEAD = "a" * 40


def _protocol():
    from formal_v09_protocol import load_protocol_v09

    return load_protocol_v09(IDEA_ROOT / "configs/formal_v09_protocol.json")


def _write_valid_prerequisites(paths, protocol):
    from artifact_v09 import write_json_atomic
    from run_formal_strict_stage_v09 import strict_input_bindings_v09

    write_json_atomic(paths.resource_preflight_audit, _valid_resource_report(protocol, paths.worktree_root))
    write_json_atomic(
        paths.legacy_bridge_audit,
        _valid_legacy_report(protocol, strict_input_bindings_v09(paths)),
    )


def _wire_authorization_entry(module, monkeypatch, paths, protocol):
    monkeypatch.setattr(module, "_production_worktree_root_v09", lambda: paths.worktree_root)
    monkeypatch.setattr(module, "strict_stage_paths_v09", lambda root: paths)
    monkeypatch.setattr(module, "load_protocol_v09", lambda path: protocol)
    monkeypatch.setattr(module, "_require_clean_worktree_v09", lambda root: _HEAD)
    monkeypatch.setattr(
        module,
        "strict_executable_tree_v09",
        lambda root: {"tree_sha256": "e" * 64},
    )


def _wire_audit_entry(module, monkeypatch, paths, protocol):
    monkeypatch.setattr(module, "_production_worktree_root_v09", lambda: paths.worktree_root)
    monkeypatch.setattr(module, "strict_stage_paths_v09", lambda root: paths)
    monkeypatch.setattr(module, "load_protocol_v09", lambda path: protocol)


# --------------------------------------------------------------------------------------
# one-use authorization entry
# --------------------------------------------------------------------------------------


def test_authorization_entry_is_closed_and_cannot_train():
    import create_formal_strict_authorization_v09 as module

    assert not inspect.signature(module.create_formal_strict_authorization_v09).parameters
    source = inspect.getsource(module)
    assert "argparse" not in source
    assert "run_strict_training_v09" not in source
    assert "consume_stage_authorization_v09" not in source


@pytest.mark.parametrize("present", ["resource", "bridge", "none"])
def test_authorization_entry_refuses_a_missing_prerequisite_report(tmp_path, monkeypatch, present):
    import create_formal_strict_authorization_v09 as module
    from artifact_v09 import write_json_atomic
    from run_formal_strict_stage_v09 import strict_input_bindings_v09

    paths = _paths(tmp_path)
    protocol = _protocol()
    if present == "resource":
        write_json_atomic(paths.resource_preflight_audit, _valid_resource_report(protocol, tmp_path))
    elif present == "bridge":
        write_json_atomic(
            paths.legacy_bridge_audit,
            _valid_legacy_report(protocol, strict_input_bindings_v09(paths)),
        )
    _wire_authorization_entry(module, monkeypatch, paths, protocol)

    with pytest.raises(FileNotFoundError, match="prerequisite"):
        module.create_formal_strict_authorization_v09()
    assert not paths.authorization.exists()


def test_authorization_entry_creates_exactly_one_bound_receipt(tmp_path, monkeypatch):
    import create_formal_strict_authorization_v09 as module
    from artifact_v09 import canonical_sha256
    from stage_authorization_v09 import STRICT_NESTING_APPROVAL_TEXT

    paths = _paths(tmp_path)
    protocol = _protocol()
    _write_valid_prerequisites(paths, protocol)
    _wire_authorization_entry(module, monkeypatch, paths, protocol)

    result = module.create_formal_strict_authorization_v09()

    assert result["status"] == "strict_training_authorization_created"
    assert result["formal_training_started"] is False
    receipt = json.loads(paths.authorization.read_text(encoding="utf-8"))
    assert receipt["status"] == "authorized_once"
    assert receipt["receipt_id"] == "A09-NEST-01"
    assert receipt["scope"] == "R09-NEST-S100"
    assert receipt["maximum_attempts"] == 1
    assert receipt["allowed_runs"] == ["R09-NEST-S100"]
    assert receipt["approval"]["text"] == STRICT_NESTING_APPROVAL_TEXT
    assert receipt["git_commit"] == _HEAD
    assert receipt["protocol_sha256"] == canonical_sha256(protocol)
    assert receipt["executable_tree_sha256"] == "e" * 64
    assert receipt["formal_prediction_generation_authorized"] is False
    assert receipt["official_scoring_authorized"] is False
    assert not paths.consumption.exists()
    assert not paths.output_root.exists()


def test_authorization_entry_never_overwrites_an_existing_receipt(tmp_path, monkeypatch):
    import create_formal_strict_authorization_v09 as module

    paths = _paths(tmp_path)
    protocol = _protocol()
    _write_valid_prerequisites(paths, protocol)
    _wire_authorization_entry(module, monkeypatch, paths, protocol)

    module.create_formal_strict_authorization_v09()
    before = paths.authorization.read_bytes()

    with pytest.raises(FileExistsError, match="authorization"):
        module.create_formal_strict_authorization_v09()
    assert paths.authorization.read_bytes() == before


@pytest.mark.parametrize("blocked", ["consumption", "output"])
def test_authorization_entry_refuses_an_already_used_stage(tmp_path, monkeypatch, blocked):
    import create_formal_strict_authorization_v09 as module

    paths = _paths(tmp_path)
    protocol = _protocol()
    _write_valid_prerequisites(paths, protocol)
    if blocked == "output":
        paths.output_root.mkdir(parents=True)
    else:
        paths.consumption.parent.mkdir(parents=True, exist_ok=True)
        paths.consumption.write_text("{}", encoding="utf-8")
    _wire_authorization_entry(module, monkeypatch, paths, protocol)

    with pytest.raises(FileExistsError, match="consumption|output"):
        module.create_formal_strict_authorization_v09()
    assert not paths.authorization.exists()


def test_authorization_entry_refuses_a_dirty_worktree(tmp_path, monkeypatch):
    import create_formal_strict_authorization_v09 as module

    class Result:
        def __init__(self, stdout):
            self.stdout = stdout

    results = iter((Result(_HEAD + "\n"), Result("?? unexpected.file\n")))
    monkeypatch.setattr(module.subprocess, "run", lambda *args, **kwargs: next(results))

    with pytest.raises(ValueError, match="clean Git worktree"):
        module._require_clean_worktree_v09(tmp_path)


# --------------------------------------------------------------------------------------
# post-training external audit entry
# --------------------------------------------------------------------------------------


def test_audit_entry_is_closed_and_cannot_train_or_authorize():
    import audit_formal_strict_stage_v09 as module

    assert not inspect.signature(module.audit_formal_strict_stage_v09).parameters
    source = inspect.getsource(module)
    assert "argparse" not in source
    assert "run_strict_training_v09" not in source
    assert "create_stage_authorization_v09" not in source


@pytest.mark.parametrize("stage", ["no_consumption", "no_run_dir", "no_seal"])
def test_audit_entry_refuses_before_the_run_is_consumed_and_sealed(tmp_path, monkeypatch, stage):
    import audit_formal_strict_stage_v09 as module

    paths = _paths(tmp_path)
    protocol = _protocol()
    if stage != "no_consumption":
        paths.consumption.parent.mkdir(parents=True, exist_ok=True)
        paths.consumption.write_text(json.dumps({"status": "consumed_once"}), encoding="utf-8")
    if stage == "no_seal":
        paths.output_root.mkdir(parents=True)
    _wire_audit_entry(module, monkeypatch, paths, protocol)

    with pytest.raises(FileNotFoundError, match="consumption|run directory|seal"):
        module.audit_formal_strict_stage_v09()


def test_audit_report_path_is_outside_the_sealed_run(tmp_path):
    import audit_formal_strict_stage_v09 as module

    paths = _paths(tmp_path)
    report_path = module._strict_audit_report_path_v09(paths)

    assert report_path.name == "R09-NEST-S100.strict_nesting_external_audit.json"
    assert paths.output_root not in report_path.parents
    assert report_path.parent == paths.input_root.parent

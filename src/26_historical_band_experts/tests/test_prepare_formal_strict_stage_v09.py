from pathlib import Path
import inspect
import json
import sys

import pytest

IDEA_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(IDEA_ROOT))

from test_run_formal_strict_stage_v09 import _valid_legacy_report, _valid_resource_report


def _paths(tmp_path):
    from run_formal_strict_stage_v09 import StrictStagePathsV09

    formal = tmp_path / "results/26_historical_band_experts/formal_v09"
    input_root = formal / "input_attempt_01"
    input_root.mkdir(parents=True)
    fixed = {
        input_root / "seal.json": {"status": "sealed", "sealed_files": []},
        formal / "input_attempt_01.external_audit.json": {"status": "complete_input_audit_passed"},
        formal / "input_attempt_01.trusted_source_external_audit.json": {
            "status": "complete_trusted_training_target_audit"
        },
        formal / "formal_input_seal_authorization_consumed.json": {"status": "consumed_once"},
        formal / "authorizations/formal_input_seal_authorization.json": {"status": "authorized_once"},
        formal / "inputs/training_targets.csv": {"synthetic": True},
        formal / "inputs/training_targets.manifest.json": {"synthetic": True},
    }
    for path, value in fixed.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(value), encoding="utf-8")
    return StrictStagePathsV09(
        worktree_root=tmp_path,
        protocol=tmp_path / "protocol.json",
        input_root=input_root,
        input_external_audit=formal / "input_attempt_01.external_audit.json",
        trusted_source_audit=formal / "input_attempt_01.trusted_source_external_audit.json",
        legacy_bridge_audit=formal / "R09-NEST-S100.legacy_checkpoint_bridge_external_audit.json",
        resource_preflight_audit=formal / "R09-NEST-S100.training_resource_preflight_external_audit.json",
        authorization=formal / "authorizations/A09-NEST-01.authorization.json",
        consumption=formal / "authorizations/A09-NEST-01.consumption.json",
        output_root=formal / "strict_nesting/R09-NEST-S100",
    )


def _run(tmp_path, paths, monkeypatch):
    import prepare_formal_strict_stage_v09 as module
    from formal_v09_protocol import load_protocol_v09

    protocol = load_protocol_v09(IDEA_ROOT / "configs/formal_v09_protocol.json")
    calls = {"bridge": 0, "resource": 0}
    order = []

    def inputs_loader():
        order.append("inputs")
        return object()

    def bridge_auditor(*args, **kwargs):
        from artifact_v09 import write_json_atomic
        from memory_safety_v09 import TaskLeaseError, exclusive_high_load_lease_v09
        from run_formal_strict_stage_v09 import strict_input_bindings_v09

        calls["bridge"] += 1
        order.append("bridge")
        with pytest.raises(TaskLeaseError):
            with exclusive_high_load_lease_v09():
                pass
        report = _valid_legacy_report(protocol, strict_input_bindings_v09(paths))
        write_json_atomic(kwargs["report_path"], report)
        return report

    def resource_auditor(*args, **kwargs):
        calls["resource"] += 1
        order.append("resource")
        return _valid_resource_report(protocol, tmp_path, lease=kwargs["lease"])

    result = module._prepare_strict_prerequisites_v09(
        paths,
        protocol=protocol,
        inputs_loader=inputs_loader,
        legacy_results_root=tmp_path / "results/18_lstm_fair_531",
        bridge_auditor=bridge_auditor,
        resource_auditor=resource_auditor,
        preparation_lock_path=tmp_path / "preparation.lock",
    )
    return result, calls, protocol, order


def test_public_preparation_entry_has_no_arguments_and_fixed_legacy_root():
    import prepare_formal_strict_stage_v09 as module

    assert not inspect.signature(module.prepare_formal_strict_stage_v09).parameters
    assert module._LEGACY_RESULTS_ROOT.as_posix() == "results/18_lstm_fair_531"
    assert "create_stage_authorization_v09" not in inspect.getsource(module)
    assert "run_strict_training_v09" not in inspect.getsource(module)


def test_public_preparation_entry_wires_only_fixed_dependencies(tmp_path, monkeypatch):
    import prepare_formal_strict_stage_v09 as module
    from artifact_v09 import write_json_atomic
    from formal_v09_protocol import load_protocol_v09

    paths = _paths(tmp_path)
    protocol = load_protocol_v09(IDEA_ROOT / "configs/formal_v09_protocol.json")
    sentinel_inputs = object()
    seen = []
    monkeypatch.setattr(module, "_production_worktree_root_v09", lambda: tmp_path)
    monkeypatch.setattr(module, "_primary_repository_root_v09", lambda root: tmp_path)
    monkeypatch.setattr(module, "strict_stage_paths_v09", lambda root: paths)
    monkeypatch.setattr(module, "_require_clean_worktree_v09", lambda root: "c" * 40)
    monkeypatch.setattr(module, "load_protocol_v09", lambda path: protocol)
    monkeypatch.setattr(
        module,
        "load_sealed_bridge_inputs_v09",
        lambda *args, **kwargs: sentinel_inputs,
    )
    monkeypatch.setattr(module, "_preparation_lock_path_v09", lambda: tmp_path / "preparation.lock")

    def resource_auditor(captured_protocol, **kwargs):
        seen.append(("resource", captured_protocol, kwargs["action"], kwargs["variant"]))
        return _valid_resource_report(protocol, tmp_path, lease=kwargs["lease"])

    def bridge_auditor(captured_protocol, **kwargs):
        from run_formal_strict_stage_v09 import strict_input_bindings_v09

        seen.append(("bridge", captured_protocol, kwargs["inputs"], kwargs["legacy_results_root"]))
        write_json_atomic(
            kwargs["report_path"],
            _valid_legacy_report(protocol, strict_input_bindings_v09(paths)),
        )

    monkeypatch.setattr(module, "_audit_formal_action_resources_under_lease_v09", resource_auditor)
    monkeypatch.setattr(module, "audit_legacy_checkpoint_bridge_v09", bridge_auditor)

    result = module.prepare_formal_strict_stage_v09()

    assert result["status"] == "strict_prerequisites_prepared"
    assert seen == [
        ("resource", protocol, "training", "strict_nesting_pair"),
        ("bridge", protocol, sentinel_inputs, tmp_path / "results/18_lstm_fair_531"),
    ]
    assert result["training_authorization_created"] is False
    assert not paths.authorization.exists() and not paths.output_root.exists()


def test_primary_repository_root_comes_from_git_common_directory(tmp_path, monkeypatch):
    import prepare_formal_strict_stage_v09 as module

    repository_root = tmp_path / "primary"
    common_dir = repository_root / ".git"
    common_dir.mkdir(parents=True)

    class Result:
        stdout = str(common_dir) + "\n"

    seen = {}

    def run(command, **kwargs):
        seen["command"] = command
        seen["cwd"] = kwargs["cwd"]
        return Result()

    monkeypatch.setattr(module.subprocess, "run", run)

    assert module._primary_repository_root_v09(tmp_path / "worktree") == repository_root
    assert seen == {
        "command": ["git", "rev-parse", "--path-format=absolute", "--git-common-dir"],
        "cwd": tmp_path / "worktree",
    }


def test_clean_worktree_gate_rejects_untracked_or_modified_files(tmp_path, monkeypatch):
    import prepare_formal_strict_stage_v09 as module

    class Result:
        def __init__(self, stdout):
            self.stdout = stdout

    results = iter((Result("c" * 40 + "\n"), Result("?? unexpected.file\n")))
    monkeypatch.setattr(module.subprocess, "run", lambda *args, **kwargs: next(results))

    with pytest.raises(ValueError, match="clean Git worktree"):
        module._require_clean_worktree_v09(tmp_path)


@pytest.mark.parametrize("blocked", ["authorization", "consumption", "output"])
def test_preparation_rejects_any_formal_stage_state_before_auditors(tmp_path, monkeypatch, blocked):
    import prepare_formal_strict_stage_v09 as module
    from formal_v09_protocol import load_protocol_v09

    paths = _paths(tmp_path)
    path = getattr(paths, "output_root" if blocked == "output" else blocked)
    if blocked == "output":
        path.mkdir(parents=True)
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("{}", encoding="utf-8")
    protocol = load_protocol_v09(IDEA_ROOT / "configs/formal_v09_protocol.json")
    called = []
    with pytest.raises((FileExistsError, ValueError), match="authorization|consumption|output"):
        module._prepare_strict_prerequisites_v09(
            paths,
            protocol=protocol,
            inputs_loader=lambda: called.append("inputs"),
            legacy_results_root=tmp_path / "results/18_lstm_fair_531",
            bridge_auditor=lambda *args, **kwargs: called.append("bridge"),
            resource_auditor=lambda *args, **kwargs: called.append("resource"),
            preparation_lock_path=tmp_path / "preparation.lock",
        )
    assert called == []


def test_preparation_creates_both_reports_once_and_is_resumable(tmp_path, monkeypatch):
    paths = _paths(tmp_path)

    first, first_calls, _, first_order = _run(tmp_path, paths, monkeypatch)
    second, second_calls, _, second_order = _run(tmp_path, paths, monkeypatch)

    assert first["status"] == "strict_prerequisites_prepared"
    assert first["training_authorization_created"] is False
    assert first["formal_training_started"] is False
    assert first["prerequisite_sha256"] == second["prerequisite_sha256"]
    assert first_calls == {"bridge": 1, "resource": 1}
    assert second_calls == {"bridge": 0, "resource": 0}
    assert first_order == ["resource", "inputs", "bridge"]
    assert second_order == []
    assert paths.legacy_bridge_audit.is_file()
    assert paths.resource_preflight_audit.is_file()
    assert not paths.authorization.exists()
    assert not paths.consumption.exists()
    assert not paths.output_root.exists()


def test_preparation_resumes_from_resource_only_after_live_resource_recheck(tmp_path, monkeypatch):
    from artifact_v09 import write_json_atomic
    from formal_v09_protocol import load_protocol_v09

    paths = _paths(tmp_path)
    protocol = load_protocol_v09(IDEA_ROOT / "configs/formal_v09_protocol.json")
    write_json_atomic(paths.resource_preflight_audit, _valid_resource_report(protocol, tmp_path))

    result, calls, _, order = _run(tmp_path, paths, monkeypatch)

    assert result["status"] == "strict_prerequisites_prepared"
    assert calls == {"bridge": 1, "resource": 1}
    assert order == ["resource", "inputs", "bridge"]


def test_preparation_resumes_from_bridge_only_without_loading_inputs(tmp_path, monkeypatch):
    from artifact_v09 import write_json_atomic
    from formal_v09_protocol import load_protocol_v09

    paths = _paths(tmp_path)
    protocol = load_protocol_v09(IDEA_ROOT / "configs/formal_v09_protocol.json")
    from run_formal_strict_stage_v09 import strict_input_bindings_v09
    write_json_atomic(
        paths.legacy_bridge_audit,
        _valid_legacy_report(protocol, strict_input_bindings_v09(paths)),
    )

    result, calls, _, order = _run(tmp_path, paths, monkeypatch)

    assert result["status"] == "strict_prerequisites_prepared"
    assert calls == {"bridge": 0, "resource": 1}
    assert order == ["resource"]


def test_preparation_preserves_resource_report_when_bridge_fails_and_resumes(tmp_path, monkeypatch):
    import prepare_formal_strict_stage_v09 as module
    from formal_v09_protocol import load_protocol_v09

    paths = _paths(tmp_path)
    protocol = load_protocol_v09(IDEA_ROOT / "configs/formal_v09_protocol.json")
    with pytest.raises(RuntimeError, match="synthetic bridge failure"):
        module._prepare_strict_prerequisites_v09(
            paths,
            protocol=protocol,
            inputs_loader=object,
            legacy_results_root=tmp_path / "results/18_lstm_fair_531",
            bridge_auditor=lambda *args, **kwargs: (_ for _ in ()).throw(
                RuntimeError("synthetic bridge failure")
            ),
            resource_auditor=lambda *args, **kwargs: _valid_resource_report(
                protocol,
                tmp_path,
                lease=kwargs["lease"],
            ),
            preparation_lock_path=tmp_path / "preparation.lock",
        )
    resource_bytes = paths.resource_preflight_audit.read_bytes()
    assert not paths.legacy_bridge_audit.exists()

    result, calls, _, order = _run(tmp_path, paths, monkeypatch)

    assert result["status"] == "strict_prerequisites_prepared"
    assert calls == {"bridge": 1, "resource": 1}
    assert order == ["resource", "inputs", "bridge"]
    assert paths.resource_preflight_audit.read_bytes() == resource_bytes


def test_existing_resource_report_cannot_replace_live_gate_before_bridge(tmp_path):
    import prepare_formal_strict_stage_v09 as module
    from artifact_v09 import write_json_atomic
    from formal_v09_protocol import load_protocol_v09
    from memory_safety_v09 import MemorySafetyError

    paths = _paths(tmp_path)
    protocol = load_protocol_v09(IDEA_ROOT / "configs/formal_v09_protocol.json")
    write_json_atomic(paths.resource_preflight_audit, _valid_resource_report(protocol, tmp_path))
    called = []

    with pytest.raises(MemorySafetyError, match="current live resource gate failed"):
        module._prepare_strict_prerequisites_v09(
            paths,
            protocol=protocol,
            inputs_loader=lambda: called.append("inputs"),
            legacy_results_root=tmp_path / "results/18_lstm_fair_531",
            bridge_auditor=lambda *args, **kwargs: called.append("bridge"),
            resource_auditor=lambda *args, **kwargs: (_ for _ in ()).throw(
                MemorySafetyError("current live resource gate failed")
            ),
            preparation_lock_path=tmp_path / "preparation.lock",
        )

    assert called == []


def test_preparation_rejects_invalid_existing_report_without_overwrite(tmp_path, monkeypatch):
    import prepare_formal_strict_stage_v09 as module
    from formal_v09_protocol import load_protocol_v09

    paths = _paths(tmp_path)
    paths.legacy_bridge_audit.write_text(json.dumps({"status": "wrong"}), encoding="utf-8")
    before = paths.legacy_bridge_audit.read_bytes()
    protocol = load_protocol_v09(IDEA_ROOT / "configs/formal_v09_protocol.json")
    with pytest.raises(ValueError, match="status"):
        module._prepare_strict_prerequisites_v09(
            paths,
            protocol=protocol,
            inputs_loader=lambda: pytest.fail("must stop before loading inputs"),
            legacy_results_root=tmp_path / "results/18_lstm_fair_531",
            bridge_auditor=lambda *args, **kwargs: pytest.fail("must not overwrite existing bridge report"),
            resource_auditor=lambda *args, **kwargs: pytest.fail("must stop before resource audit"),
            preparation_lock_path=tmp_path / "preparation.lock",
        )
    assert paths.legacy_bridge_audit.read_bytes() == before


def test_preparation_rejects_temporary_formal_artifact_before_auditors(tmp_path):
    import prepare_formal_strict_stage_v09 as module
    from formal_v09_protocol import load_protocol_v09

    paths = _paths(tmp_path)
    temporary = paths.input_root.parent / ".unexpected.tmp"
    temporary.write_text("partial", encoding="utf-8")
    protocol = load_protocol_v09(IDEA_ROOT / "configs/formal_v09_protocol.json")
    with pytest.raises(ValueError, match="inventory"):
        module._prepare_strict_prerequisites_v09(
            paths,
            protocol=protocol,
            inputs_loader=lambda: pytest.fail("must not load inputs"),
            legacy_results_root=tmp_path / "results/18_lstm_fair_531",
            bridge_auditor=lambda *args, **kwargs: pytest.fail("must not run"),
            resource_auditor=lambda *args, **kwargs: pytest.fail("must not run"),
            preparation_lock_path=tmp_path / "preparation.lock",
        )


def test_preparation_rejects_concurrent_preparation_lock(tmp_path):
    import prepare_formal_strict_stage_v09 as module
    from formal_v09_protocol import load_protocol_v09
    from memory_safety_v09 import TaskLeaseError, exclusive_high_load_lease_v09

    paths = _paths(tmp_path)
    protocol = load_protocol_v09(IDEA_ROOT / "configs/formal_v09_protocol.json")
    lock_path = tmp_path / "preparation.lock"
    with exclusive_high_load_lease_v09(lock_path=lock_path):
        with pytest.raises(TaskLeaseError):
            module._prepare_strict_prerequisites_v09(
                paths,
                protocol=protocol,
                inputs_loader=lambda: pytest.fail("must not load inputs"),
                legacy_results_root=tmp_path / "results/18_lstm_fair_531",
                bridge_auditor=lambda *args, **kwargs: pytest.fail("must not run"),
                resource_auditor=lambda *args, **kwargs: pytest.fail("must not run"),
                preparation_lock_path=lock_path,
            )

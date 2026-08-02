import inspect
import json
from dataclasses import replace
from pathlib import Path
import sys

import pytest

IDEA_ROOT = Path(__file__).resolve().parents[1]
CONFIG = IDEA_ROOT / "configs/formal_v09_protocol.json"
sys.path.insert(0, str(IDEA_ROOT))

GIB = 2**30
MIB = 2**20


def _config() -> dict:
    return json.loads(CONFIG.read_text(encoding="utf-8"))


def _host_snapshot():
    from memory_safety_v09 import HostMemorySnapshot

    return HostMemorySnapshot(32 * GIB, 16 * GIB, 256 * MIB, 30 * GIB)


def _accelerator_snapshot():
    from formal_action_resources_v09 import AcceleratorMemorySnapshot

    return AcceleratorMemorySnapshot(0, "synthetic-cuda", 16 * GIB, 12 * GIB)


@pytest.mark.parametrize(
    ("action", "variant", "accelerator_required"),
    [
        ("formal_target_bundle_generation", None, False),
        ("training", "classic_lstm_256_clean", True),
        ("formal_prediction_generation", "continuous_multiscale_history", True),
    ],
)
def test_resource_preflight_is_read_only_and_covers_host_accelerator_and_lock(
    tmp_path,
    action,
    variant,
    accelerator_required,
):
    from formal_action_runtime_v09 import _audit_formal_action_resources_v09

    report = _audit_formal_action_resources_v09(
        _config(),
        action=action,
        variant=variant,
        host_snapshot=_host_snapshot(),
        accelerator_snapshot=(_accelerator_snapshot() if accelerator_required else None),
        lock_path=tmp_path / "formal-v09.lock",
    )

    assert report["status"] == "resource_preflight_passed"
    assert report["authorization_checked"] is False
    assert report["host"]["safe"] is True
    assert report["host"]["serial_lease"]["held"] is True
    assert report["accelerator"]["required"] is accelerator_required


def test_authorized_runner_refuses_before_callback_while_authorization_is_closed(tmp_path):
    from formal_action_runtime_v09 import run_authorized_formal_action_v09
    from launch_gate_v09 import LaunchAuthorizationError

    called = []
    with pytest.raises(LaunchAuthorizationError, match="not authorized"):
        run_authorized_formal_action_v09(
            _config(),
            action="formal_target_bundle_generation",
            callback=lambda runtime: called.append(runtime),
        )

    assert called == []


def test_runner_holds_one_lock_and_checks_live_resources_during_callback(
    tmp_path,
    monkeypatch,
):
    import formal_action_runtime_v09 as runtime_module

    seen = []
    runtime_handles = []

    def synthetic_authorization_gate(config, **kwargs):
        assert kwargs["lease"].is_valid()
        return {"status": "launch_allowed", "memory": {"safe": True}}

    monkeypatch.setattr(
        runtime_module,
        "assert_launch_allowed_v09",
        synthetic_authorization_gate,
    )

    def callback(runtime):
        assert runtime.lease.is_valid()
        runtime_handles.append(runtime)
        seen.append(runtime.checkpoint())
        return "complete"

    result = runtime_module._run_authorized_formal_action_v09(
        _config(),
        action="formal_target_bundle_generation",
        callback=callback,
        host_sampler=_host_snapshot,
        lock_path=tmp_path / "formal-v09.lock",
    )

    assert result["result"] == "complete"
    assert seen[0]["host"]["safe"] is True
    assert seen[0]["accelerator"]["required"] is False
    assert runtime_handles[0].lease.is_valid() is False


def test_training_runtime_checkpoint_fails_closed_on_accelerator_pressure(
    tmp_path,
    monkeypatch,
):
    import formal_action_runtime_v09 as runtime_module
    from formal_action_resources_v09 import AcceleratorMemorySnapshot
    from memory_safety_v09 import MemorySafetyError

    monkeypatch.setattr(
        runtime_module,
        "assert_launch_allowed_v09",
        lambda config, **kwargs: {
            "status": "launch_allowed",
            "memory": {
                "safe": True
            }
        },
    )
    snapshots = iter([
        _accelerator_snapshot(),
        _accelerator_snapshot(),
        AcceleratorMemorySnapshot(0, "synthetic-cuda", 16 * GIB, 1 * GIB - 1),
    ])

    with pytest.raises(MemorySafetyError, match="runtime reserve"):
        runtime_module._run_authorized_formal_action_v09(
            _config(),
            action="training",
            variant="classic_lstm_256_clean",
            callback=lambda runtime: runtime.checkpoint(),
            host_sampler=_host_snapshot,
            accelerator_sampler=lambda: next(snapshots),
            lock_path=tmp_path / "formal-v09.lock",
        )


def test_public_production_entry_points_do_not_accept_snapshot_or_lock_injection():
    from formal_action_runtime_v09 import (
        FormalActionRuntimeV09,
        audit_formal_action_resources_v09,
        run_authorized_formal_action_v09,
    )

    forbidden = {
        "host_snapshot",
        "accelerator_snapshot",
        "host_sampler",
        "accelerator_sampler",
        "lock_path",
    }
    assert forbidden.isdisjoint(inspect.signature(audit_formal_action_resources_v09).parameters)
    assert forbidden.isdisjoint(inspect.signature(run_authorized_formal_action_v09).parameters)
    with pytest.raises(TypeError, match="authorized runner"):
        FormalActionRuntimeV09()


def test_runtime_rejects_accelerator_device_switch_before_callback(tmp_path, monkeypatch):
    import formal_action_runtime_v09 as runtime_module
    from formal_action_resources_v09 import AcceleratorMemorySnapshot
    from memory_safety_v09 import MemorySafetyError

    monkeypatch.setattr(
        runtime_module,
        "assert_launch_allowed_v09",
        lambda config, **kwargs: {
            "status": "launch_allowed",
            "memory": {
                "safe": True
            }
        },
    )
    snapshots = iter([
        _accelerator_snapshot(),
        AcceleratorMemorySnapshot(1, "other-cuda", 16 * GIB, 12 * GIB),
    ])
    called = []

    with pytest.raises(MemorySafetyError, match="device identity"):
        runtime_module._run_authorized_formal_action_v09(
            _config(),
            action="training",
            variant="classic_lstm_256_clean",
            callback=lambda runtime: called.append(runtime),
            host_sampler=_host_snapshot,
            accelerator_sampler=lambda: next(snapshots),
            lock_path=tmp_path / "formal-v09.lock",
        )

    assert called == []


def test_entry_rechecks_full_host_peak_before_callback(tmp_path, monkeypatch):
    import formal_action_runtime_v09 as runtime_module
    from memory_safety_v09 import HostMemorySnapshot, MemorySafetyError

    monkeypatch.setattr(
        runtime_module,
        "assert_launch_allowed_v09",
        lambda config, **kwargs: {
            "status": "launch_allowed",
            "memory": {
                "safe": True
            }
        },
    )
    host_snapshots = iter([
        _host_snapshot(),
        HostMemorySnapshot(32 * GIB, 2 * GIB + 1, 256 * MIB, 30 * GIB),
    ])
    called = []

    with pytest.raises(MemorySafetyError, match="guarded task estimate"):
        runtime_module._run_authorized_formal_action_v09(
            _config(),
            action="formal_target_bundle_generation",
            callback=lambda runtime: called.append(runtime),
            host_sampler=lambda: next(host_snapshots),
            lock_path=tmp_path / "formal-v09.lock",
        )

    assert called == []


def test_entry_rechecks_full_accelerator_peak_before_callback(tmp_path, monkeypatch):
    import formal_action_runtime_v09 as runtime_module
    from formal_action_resources_v09 import AcceleratorMemorySnapshot
    from memory_safety_v09 import MemorySafetyError

    monkeypatch.setattr(
        runtime_module,
        "assert_launch_allowed_v09",
        lambda config, **kwargs: {
            "status": "launch_allowed",
            "memory": {
                "safe": True
            }
        },
    )
    accelerator_snapshots = iter([
        _accelerator_snapshot(),
        AcceleratorMemorySnapshot(0, "synthetic-cuda", 16 * GIB, 2 * GIB),
    ])
    called = []

    with pytest.raises(MemorySafetyError, match="accelerator reserve"):
        runtime_module._run_authorized_formal_action_v09(
            _config(),
            action="training",
            variant="classic_lstm_256_clean",
            callback=lambda runtime: called.append(runtime),
            host_sampler=_host_snapshot,
            accelerator_sampler=lambda: next(accelerator_snapshots),
            lock_path=tmp_path / "formal-v09.lock",
        )

    assert called == []


def test_training_stage_receipt_is_consumed_after_resource_checks_and_before_callback(tmp_path, monkeypatch):
    from artifact_v09 import canonical_sha256
    from formal_action_runtime_v09 import _run_authorized_formal_action_v09
    from stage_authorization_v09 import (
        STRICT_NESTING_APPROVAL_TEXT,
        create_stage_authorization_v09,
        stage_authorization_paths_v09,
    )

    prerequisites = {
        "input_seal": "1" * 64,
        "input_artifact_external_audit": "2" * 64,
        "trusted_target_external_audit": "3" * 64,
        "legacy_checkpoint_bridge_external_audit": "4" * 64,
        "training_resource_preflight_external_audit": "5" * 64,
    }
    output_root = "results/26_historical_band_experts/formal_v09/strict_nesting/seed_100"
    config = _config()
    protocol_sha256 = canonical_sha256(config)
    receipt = create_stage_authorization_v09(
        approval_text=STRICT_NESTING_APPROVAL_TEXT,
        scope="R09-NEST-S100",
        protocol_sha256=protocol_sha256,
        prerequisite_sha256=prerequisites,
        executable_tree_sha256="b" * 64,
        git_commit="c" * 40,
        worktree_root=tmp_path,
        output_root=output_root,
        created_utc="2026-08-02T00:00:00Z",
    )
    authorization_path, consumption_path = stage_authorization_paths_v09("R09-NEST-S100", worktree_root=tmp_path)
    authorization_path.parent.mkdir(parents=True)
    authorization_path.write_text(json.dumps(receipt), encoding="utf-8")
    callback_observations = []

    def callback(*, runtime, inputs, protocol, output_dir, device):
        assert inputs.root == tmp_path / "results/26_historical_band_experts/formal_v09/input_attempt_01"
        assert protocol is config
        assert Path(output_dir).resolve() == Path(receipt["output_root"])
        assert device == "cuda:0"
        callback_observations.append(consumption_path.is_file())
        return runtime.checkpoint()

    import train_strict_formal_v09
    monkeypatch.setattr(train_strict_formal_v09, "run_strict_training_v09", callback)

    from test_train_strict_formal_v09 import _inputs
    inputs = replace(
        _inputs(),
        root=tmp_path / "results/26_historical_band_experts/formal_v09/input_attempt_01",
        input_seal_sha256="1" * 64,
    )
    result = _run_authorized_formal_action_v09(
        config,
        action="training",
        variant="strict_nesting_pair",
        callback=callback,
        host_sampler=_host_snapshot,
        accelerator_sampler=_accelerator_snapshot,
        lock_path=tmp_path / "formal-v09.lock",
        authorization_scope="R09-NEST-S100",
        stage_worktree_root=tmp_path,
        stage_bindings={
            "protocol_sha256": protocol_sha256,
            "prerequisite_sha256": prerequisites,
            "executable_tree_sha256": "b" * 64,
            "worktree_root": str(tmp_path.resolve()),
            "output_root": receipt["output_root"],
        },
        run_claim={
            "run_id": "R09-NEST-S100",
            "seed": 100,
            "variant": "strict_nesting_pair",
            "output_root": receipt["output_root"],
        },
        callback_kwargs={
            "inputs": inputs,
            "protocol": config,
            "output_dir": receipt["output_root"],
            "device": "cuda:0",
        },
    )

    assert callback_observations == [True]
    assert result["stage_consumption"]["status"] == "consumed_once"
    assert json.loads(consumption_path.read_text(encoding="utf-8"))["scope"] == "R09-NEST-S100"


def test_strict_stage_rejects_wrong_workload_before_consuming_receipt(tmp_path, monkeypatch):
    from formal_action_runtime_v09 import _run_authorized_formal_action_v09
    from stage_authorization_v09 import (
        STRICT_NESTING_APPROVAL_TEXT,
        create_stage_authorization_v09,
        stage_authorization_paths_v09,
    )
    import train_strict_formal_v09

    prerequisites = {
        "input_seal": "1" * 64,
        "input_artifact_external_audit": "2" * 64,
        "trusted_target_external_audit": "3" * 64,
        "legacy_checkpoint_bridge_external_audit": "4" * 64,
        "training_resource_preflight_external_audit": "5" * 64,
    }
    receipt = create_stage_authorization_v09(
        approval_text=STRICT_NESTING_APPROVAL_TEXT,
        scope="R09-NEST-S100",
        protocol_sha256="a" * 64,
        prerequisite_sha256=prerequisites,
        executable_tree_sha256="b" * 64,
        git_commit="c" * 40,
        worktree_root=tmp_path,
        output_root="results/strict",
        created_utc="2026-08-02T00:00:00Z",
    )
    authorization_path, consumption_path = stage_authorization_paths_v09("R09-NEST-S100", worktree_root=tmp_path)
    authorization_path.parent.mkdir(parents=True)
    authorization_path.write_text(json.dumps(receipt), encoding="utf-8")

    def callback(*, runtime):
        return runtime.checkpoint()

    monkeypatch.setattr(train_strict_formal_v09, "run_strict_training_v09", callback)
    bindings = {
        "protocol_sha256": "a" * 64,
        "prerequisite_sha256": prerequisites,
        "executable_tree_sha256": "b" * 64,
        "worktree_root": str(tmp_path.resolve()),
        "output_root": receipt["output_root"],
    }
    with pytest.raises(ValueError, match="strict nesting workload"):
        _run_authorized_formal_action_v09(
            _config(),
            action="training",
            variant="strict_nesting_pair",
            callback=callback,
            host_sampler=_host_snapshot,
            accelerator_sampler=_accelerator_snapshot,
            lock_path=tmp_path / "formal-v09.lock",
            authorization_scope="R09-NEST-S100",
            stage_worktree_root=tmp_path,
            stage_bindings=bindings,
            run_claim={
                "run_id": "R09-NEST-S100",
                "seed": 101,
                "variant": "strict_nesting_pair",
                "output_root": receipt["output_root"],
            },
        )
    assert not consumption_path.exists()


def test_strict_stage_callback_arguments_fail_before_consumption(tmp_path):
    from artifact_v09 import canonical_sha256
    from formal_action_runtime_v09 import _validate_stage_callback_kwargs_v09
    from test_train_strict_formal_v09 import _inputs

    config = _config()
    input_root = tmp_path / "results/26_historical_band_experts/formal_v09/input_attempt_01"
    inputs = replace(_inputs(), root=input_root, input_seal_sha256="1" * 64)
    output_root = str((tmp_path / "results/strict").resolve())
    receipt = {
        "protocol_sha256": canonical_sha256(config),
        "prerequisite_sha256": {
            "input_seal": "1" * 64
        },
    }
    claim = {
        "run_id": "R09-NEST-S100",
        "seed": 100,
        "variant": "strict_nesting_pair",
        "output_root": output_root,
    }
    arguments = {
        "inputs": inputs,
        "protocol": config,
        "output_dir": tmp_path / "wrong-output",
        "device": "cuda:0",
    }
    with pytest.raises(ValueError, match="output directory drift"):
        _validate_stage_callback_kwargs_v09(
            config,
            receipt,
            scope="R09-NEST-S100",
            worktree_root=tmp_path,
            run_claim=claim,
            callback_kwargs=arguments,
        )

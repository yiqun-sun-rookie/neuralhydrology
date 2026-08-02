"""Resource preflight and lock-scoped execution for formal version-09 actions."""
from __future__ import annotations

from collections.abc import Callable, Mapping
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import socket
from typing import Any
from types import MappingProxyType

from artifact_v09 import assert_no_reparse_components, canonical_sha256
from formal_action_resources_v09 import (
    AcceleratorMemorySnapshot,
    assert_accelerator_runtime_safe_v09,
    assert_accelerator_safe_v09,
    build_formal_action_peak_estimate_v09,
    sample_cuda_memory_v09,
    validate_formal_action_peak_estimate_v09,
)
from launch_gate_v09 import assert_launch_allowed_v09
from memory_safety_v09 import (
    HostMemorySnapshot,
    MemorySafetyError,
    MemorySafetyGate,
    TaskMemoryLease,
    exclusive_high_load_lease_v09,
    sample_host_memory,
)
from stage_authorization_v09 import (
    consume_stage_authorization_v09,
    stage_authorization_paths_v09,
)

_FORMAL_ACTIONS = {
    "formal_target_bundle_generation",
    "training",
    "formal_prediction_generation",
}
_FORMAL_ACCELERATOR_DEVICE_INDEX = 0


def _require_action(action: str) -> None:
    if action not in _FORMAL_ACTIONS:
        raise ValueError(f"unsupported formal action: {action}")


def _initial_accelerator_snapshot(
    action: str,
    supplied: AcceleratorMemorySnapshot | None,
    sampler: Callable[[], AcceleratorMemorySnapshot],
) -> AcceleratorMemorySnapshot | None:
    if action == "formal_target_bundle_generation":
        if supplied is not None:
            raise ValueError("target-bundle generation does not accept an accelerator snapshot")
        return None
    snapshot = supplied if supplied is not None else sampler()
    if type(snapshot.device_index) is not int or snapshot.device_index != _FORMAL_ACCELERATOR_DEVICE_INDEX:
        raise MemorySafetyError("formal model actions require a CUDA device-0 resource snapshot")
    return snapshot


def _assert_same_accelerator_v09(
    initial: AcceleratorMemorySnapshot | None,
    current: AcceleratorMemorySnapshot | None,
) -> None:
    if initial is None and current is None:
        return
    if initial is None or current is None:
        raise MemorySafetyError("accelerator device identity changed during the formal action")
    initial_identity = (initial.device_index, initial.device_name, initial.total_bytes)
    current_identity = (current.device_index, current.device_name, current.total_bytes)
    if current_identity != initial_identity:
        raise MemorySafetyError("accelerator device identity changed during the formal action")


class FormalActionRuntimeV09:
    """Non-constructible capability valid only while the global formal lock is held."""

    __slots__ = (
        "config",
        "action",
        "variant",
        "estimate",
        "lease",
        "host_gate",
        "host_sampler",
        "accelerator_sampler",
        "initial_accelerator",
        "run_claim",
    )

    def __init__(self, *args, **kwargs) -> None:
        raise TypeError("FormalActionRuntimeV09 is created only by the authorized runner")

    def is_valid_for(
        self,
        action: str,
        *,
        run_id: str | None = None,
        seed: int | None = None,
        variant: str | None = None,
        output_root: str | Path | None = None,
    ) -> bool:
        if self.action != action or not self.lease.is_valid():
            return False
        expected = {
            "run_id": run_id,
            "seed": seed,
            "variant": variant,
            "output_root": None if output_root is None else str(Path(output_root).resolve()),
        }
        return all(value is None or self.run_claim.get(key) == value for key, value in expected.items())

    def checkpoint(self) -> dict:
        """Fail closed between chunks if the lock, device, or either reserve is lost."""
        if not self.lease.is_valid():
            raise MemorySafetyError("formal action runtime no longer owns the serial lease")
        host_report = self.host_gate.assert_runtime_safe(self.host_sampler())
        current_accelerator = (None if self.action == "formal_target_bundle_generation" else self.accelerator_sampler())
        _assert_same_accelerator_v09(self.initial_accelerator, current_accelerator)
        accelerator_report = assert_accelerator_runtime_safe_v09(
            self.config,
            self.action,
            self.estimate,
            current_accelerator,
            variant=self.variant,
        )
        return {"host": host_report, "accelerator": accelerator_report}

    def assert_entry_safe(self) -> dict:
        """Repeat the complete guarded peak check immediately before the callback."""
        if not self.lease.is_valid():
            raise MemorySafetyError("formal action runtime no longer owns the serial lease")
        current_host = self.host_sampler()
        host_report = self.host_gate.assert_start_safe(
            current_host,
            self.estimate,
            long_running=True,
            lease=self.lease,
        )
        current_accelerator = (None if self.action == "formal_target_bundle_generation" else self.accelerator_sampler())
        _assert_same_accelerator_v09(self.initial_accelerator, current_accelerator)
        accelerator_report = assert_accelerator_safe_v09(
            self.config,
            self.action,
            self.estimate,
            current_accelerator,
            variant=self.variant,
        )
        return {"host": host_report, "accelerator": accelerator_report}


def _create_runtime_v09(
    *,
    config: Mapping,
    action: str,
    variant: str | None,
    estimate: Mapping,
    lease: TaskMemoryLease,
    host_gate: MemorySafetyGate,
    host_sampler: Callable[[], HostMemorySnapshot],
    accelerator_sampler: Callable[[], AcceleratorMemorySnapshot],
    initial_accelerator: AcceleratorMemorySnapshot | None,
    run_claim: Mapping | None = None,
) -> FormalActionRuntimeV09:
    runtime = object.__new__(FormalActionRuntimeV09)
    runtime.config = config
    runtime.action = action
    runtime.variant = variant
    runtime.estimate = estimate
    runtime.lease = lease
    runtime.host_gate = host_gate
    runtime.host_sampler = host_sampler
    runtime.accelerator_sampler = accelerator_sampler
    runtime.initial_accelerator = initial_accelerator
    runtime.run_claim = MappingProxyType(dict(run_claim or {}))
    return runtime


def _validate_stage_run_claim_v09(
    receipt: Mapping,
    *,
    scope: str,
    action: str,
    variant: str | None,
    run_claim: Mapping,
) -> dict:
    expected_keys = {"run_id", "seed", "variant", "output_root"}
    if not isinstance(run_claim, Mapping) or set(run_claim) != expected_keys:
        raise ValueError("formal stage run claim schema drift")
    claim = dict(run_claim)
    if action != "training" or claim["run_id"] not in receipt.get("allowed_runs", ()):
        raise ValueError("formal stage run is outside the authorized workload")
    if claim["variant"] != variant or claim["output_root"] != receipt.get("output_root"):
        raise ValueError("formal stage variant or output root claim drift")
    if scope == "R09-NEST-S100":
        expected = {
            "run_id": "R09-NEST-S100",
            "seed": 100,
            "variant": "strict_nesting_pair",
            "output_root": receipt["output_root"],
        }
        if claim != expected:
            raise ValueError("strict nesting workload claim drift")
    return claim


def _assert_stage_callback_v09(scope: str, callback: Callable) -> None:
    if scope != "R09-NEST-S100":
        raise ValueError(f"no closed formal executor is registered for stage scope {scope}")
    from train_strict_formal_v09 import run_strict_training_v09
    if callback is not run_strict_training_v09:
        raise ValueError("strict nesting receipt requires the fixed formal training executor")


def _validate_stage_callback_kwargs_v09(
    config: Mapping,
    receipt: Mapping,
    *,
    scope: str,
    worktree_root: str | Path,
    run_claim: Mapping,
    callback_kwargs: Mapping | None,
) -> dict:
    if scope != "R09-NEST-S100":
        raise ValueError(f"no callback contract is registered for stage scope {scope}")
    expected_keys = {"inputs", "protocol", "output_dir", "device"}
    if not isinstance(callback_kwargs, Mapping) or set(callback_kwargs) != expected_keys:
        raise ValueError("strict nesting callback argument schema drift")
    from formal_training_data_v09 import FormalTrainingInputsV09
    values = dict(callback_kwargs)
    if values["protocol"] is not config or canonical_sha256(config) != receipt.get("protocol_sha256"):
        raise ValueError("strict nesting callback protocol binding drift")
    inputs = values["inputs"]
    root = Path(os.path.abspath(worktree_root))
    expected_input_root = root / "results/26_historical_band_experts/formal_v09/input_attempt_01"
    if not isinstance(inputs, FormalTrainingInputsV09) or inputs.root is None:
        raise ValueError("strict nesting callback requires sealed formal inputs")
    assert_no_reparse_components(root, expected_input_root)
    if Path(os.path.abspath(inputs.root)) != expected_input_root:
        raise ValueError("strict nesting callback input root drift")
    if inputs.input_seal_sha256 != receipt["prerequisite_sha256"]["input_seal"]:
        raise ValueError("strict nesting callback input seal drift")
    output_dir = Path(os.path.abspath(values["output_dir"]))
    assert_no_reparse_components(root, output_dir)
    if str(output_dir.resolve()) != run_claim["output_root"]:
        raise ValueError("strict nesting callback output directory drift")
    if values["device"] != "cuda:0":
        raise ValueError("strict nesting callback device drift")
    return values


def _audit_formal_action_resources_v09(
    config: Mapping,
    *,
    action: str,
    variant: str | None = None,
    host_snapshot: HostMemorySnapshot | None = None,
    accelerator_snapshot: AcceleratorMemorySnapshot | None = None,
    host_sampler: Callable[[], HostMemorySnapshot] = sample_host_memory,
    accelerator_sampler: Callable[[], AcceleratorMemorySnapshot] = sample_cuda_memory_v09,
    lock_path: str | Path | None = None,
) -> dict:
    """Injectable implementation used only by isolated synthetic tests."""
    with exclusive_high_load_lease_v09(lock_path=lock_path) as lease:
        return _audit_formal_action_resources_under_lease_v09(
            config,
            action=action,
            variant=variant,
            lease=lease,
            host_snapshot=host_snapshot,
            accelerator_snapshot=accelerator_snapshot,
            host_sampler=host_sampler,
            accelerator_sampler=accelerator_sampler,
        )


def _audit_formal_action_resources_under_lease_v09(
    config: Mapping,
    *,
    action: str,
    lease: TaskMemoryLease,
    variant: str | None = None,
    host_snapshot: HostMemorySnapshot | None = None,
    accelerator_snapshot: AcceleratorMemorySnapshot | None = None,
    host_sampler: Callable[[], HostMemorySnapshot] = sample_host_memory,
    accelerator_sampler: Callable[[], AcceleratorMemorySnapshot] = sample_cuda_memory_v09,
) -> dict:
    """Audit resources while the caller keeps the one global high-load lease."""
    _require_action(action)
    if not isinstance(lease, TaskMemoryLease) or not lease.is_valid():
        raise MemorySafetyError("resource preflight requires the live serial lease")
    estimate = build_formal_action_peak_estimate_v09(config, action, variant=variant)
    validate_formal_action_peak_estimate_v09(
        config,
        action,
        estimate,
        variant=variant,
    )
    initial_host = host_snapshot if host_snapshot is not None else host_sampler()
    initial_accelerator = _initial_accelerator_snapshot(
        action,
        accelerator_snapshot,
        accelerator_sampler,
    )
    host_gate = MemorySafetyGate.from_snapshot(initial_host, config["memory_safety"])
    host_report = host_gate.assert_start_safe(
        initial_host,
        estimate,
        long_running=True,
        lease=lease,
    )
    accelerator_report = assert_accelerator_safe_v09(
        config,
        action,
        estimate,
        initial_accelerator,
        variant=variant,
    )
    return {
        "status": "resource_preflight_passed",
        "action": action,
        "variant": variant,
        "authorization_checked": False,
        "estimate": estimate,
        "host_snapshot": {
            "total_bytes": initial_host.total_bytes,
            "available_bytes": initial_host.available_bytes,
            "process_rss_bytes": initial_host.process_rss_bytes,
            "commit_headroom_bytes": initial_host.commit_headroom_bytes,
        },
        "accelerator_snapshot": (
            {
                "device_index": initial_accelerator.device_index,
                "device_name": initial_accelerator.device_name,
                "total_bytes": initial_accelerator.total_bytes,
                "available_bytes": initial_accelerator.available_bytes,
            }
            if initial_accelerator is not None
            else None
        ),
        "host": host_report,
        "accelerator": accelerator_report,
    }


def audit_formal_action_resources_v09(
    config: Mapping,
    *,
    action: str,
    variant: str | None = None,
) -> dict:
    """Audit live resources under the one global lock without granting authorization."""
    return _audit_formal_action_resources_v09(
        config,
        action=action,
        variant=variant,
        host_sampler=sample_host_memory,
        accelerator_sampler=sample_cuda_memory_v09,
        lock_path=None,
    )


def _run_authorized_formal_action_v09(
    config: Mapping,
    *,
    action: str,
    callback: Callable[[FormalActionRuntimeV09], Any],
    variant: str | None = None,
    host_sampler: Callable[[], HostMemorySnapshot] = sample_host_memory,
    accelerator_sampler: Callable[[], AcceleratorMemorySnapshot] = sample_cuda_memory_v09,
    lock_path: str | Path | None = None,
    authorization_scope: str | None = None,
    stage_bindings: Mapping | None = None,
    stage_worktree_root: str | Path | None = None,
    run_claim: Mapping | None = None,
    callback_kwargs: Mapping | None = None,
) -> dict:
    """Injectable implementation used only by isolated lifecycle tests."""
    _require_action(action)
    stage_arguments = (
        authorization_scope,
        stage_bindings,
        stage_worktree_root,
        run_claim,
    )
    if any(value is not None for value in stage_arguments) and any(value is None for value in stage_arguments):
        raise ValueError("formal stage authorization arguments must be supplied together")
    stage_authorization = None
    stage_authorization_path = None
    if authorization_scope is not None:
        stage_authorization_path, _ = stage_authorization_paths_v09(
            authorization_scope,
            worktree_root=stage_worktree_root,
        )
        stage_authorization = json.loads(stage_authorization_path.read_text(encoding="utf-8"))
        run_claim = _validate_stage_run_claim_v09(
            stage_authorization,
            scope=authorization_scope,
            action=action,
            variant=variant,
            run_claim=run_claim,
        )
        _assert_stage_callback_v09(authorization_scope, callback)
        callback_kwargs = _validate_stage_callback_kwargs_v09(
            config,
            stage_authorization,
            scope=authorization_scope,
            worktree_root=stage_worktree_root,
            run_claim=run_claim,
            callback_kwargs=callback_kwargs,
        )
    elif callback_kwargs is not None:
        raise ValueError("generic formal callback does not accept stage callback arguments")
    estimate = build_formal_action_peak_estimate_v09(config, action, variant=variant)
    with exclusive_high_load_lease_v09(lock_path=lock_path) as lease:
        initial_host = host_sampler()
        launch_report = assert_launch_allowed_v09(
            config,
            action=action,
            peak_estimate=estimate,
            variant=variant,
            snapshot=initial_host,
            lease=lease,
            stage_authorization=stage_authorization,
            authorization_scope=authorization_scope,
            stage_bindings=stage_bindings,
        )
        initial_accelerator = _initial_accelerator_snapshot(
            action,
            None,
            accelerator_sampler,
        )
        accelerator_report = assert_accelerator_safe_v09(
            config,
            action,
            estimate,
            initial_accelerator,
            variant=variant,
        )
        runtime = _create_runtime_v09(
            config=config,
            action=action,
            variant=variant,
            estimate=estimate,
            lease=lease,
            host_gate=MemorySafetyGate.from_snapshot(initial_host, config["memory_safety"]),
            host_sampler=host_sampler,
            accelerator_sampler=accelerator_sampler,
            initial_accelerator=initial_accelerator,
            run_claim=run_claim,
        )
        entry_checkpoint = runtime.assert_entry_safe()
        stage_consumption = None
        if stage_authorization is not None:
            stage_consumption = consume_stage_authorization_v09(
                stage_authorization_path,
                receipt=stage_authorization,
                worktree_root=stage_worktree_root,
                process_id=os.getpid(),
                hostname=socket.gethostname(),
                consumed_utc=datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
                memory_snapshot=launch_report["host"],
            )
        if stage_authorization is None:
            result = callback(runtime)
        else:
            result = callback(runtime=runtime, **callback_kwargs)
    return {
        "status": "formal_action_completed",
        "action": action,
        "variant": variant,
        "launch": launch_report,
        "accelerator": accelerator_report,
        "entry_checkpoint": entry_checkpoint,
        "stage_consumption": stage_consumption,
        "result": result,
    }


def run_authorized_formal_action_v09(
    config: Mapping,
    *,
    action: str,
    callback: Callable[[FormalActionRuntimeV09], Any],
    variant: str | None = None,
) -> dict:
    """Run only with live samplers and the one fixed global serial lock."""
    return _run_authorized_formal_action_v09(
        config,
        action=action,
        callback=callback,
        variant=variant,
        host_sampler=sample_host_memory,
        accelerator_sampler=sample_cuda_memory_v09,
        lock_path=None,
    )

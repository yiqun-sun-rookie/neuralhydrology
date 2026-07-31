"""Resource preflight and lock-scoped execution for formal version-09 actions."""
from __future__ import annotations

from collections.abc import Callable, Mapping
from pathlib import Path
from typing import Any

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


_FORMAL_ACTIONS = {
    "formal_target_bundle_generation",
    "training",
    "formal_prediction_generation",
}


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
    return supplied if supplied is not None else sampler()


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
    )

    def __init__(self, *args, **kwargs) -> None:
        raise TypeError("FormalActionRuntimeV09 is created only by the authorized runner")

    def is_valid_for(self, action: str) -> bool:
        return self.action == action and self.lease.is_valid()

    def checkpoint(self) -> dict:
        """Fail closed between chunks if the lock, device, or either reserve is lost."""
        if not self.lease.is_valid():
            raise MemorySafetyError("formal action runtime no longer owns the serial lease")
        host_report = self.host_gate.assert_runtime_safe(self.host_sampler())
        current_accelerator = (
            None
            if self.action == "formal_target_bundle_generation"
            else self.accelerator_sampler()
        )
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
        current_accelerator = (
            None
            if self.action == "formal_target_bundle_generation"
            else self.accelerator_sampler()
        )
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
    return runtime


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
    _require_action(action)
    estimate = build_formal_action_peak_estimate_v09(config, action, variant=variant)
    validate_formal_action_peak_estimate_v09(
        config,
        action,
        estimate,
        variant=variant,
    )
    with exclusive_high_load_lease_v09(lock_path=lock_path) as lease:
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
) -> dict:
    """Injectable implementation used only by isolated lifecycle tests."""
    _require_action(action)
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
        )
        entry_checkpoint = runtime.assert_entry_safe()
        result = callback(runtime)
    return {
        "status": "formal_action_completed",
        "action": action,
        "variant": variant,
        "launch": launch_report,
        "accelerator": accelerator_report,
        "entry_checkpoint": entry_checkpoint,
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

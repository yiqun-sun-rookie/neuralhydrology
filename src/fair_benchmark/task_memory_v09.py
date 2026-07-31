"""Task-specific memory evidence and cross-process serialization for version 09."""
from __future__ import annotations

from collections.abc import Iterator, Mapping
from contextlib import contextmanager
import ctypes
from dataclasses import dataclass
import hashlib
import json
import math
import os
from pathlib import Path
import re
import tempfile
from typing import BinaryIO, Sequence

import numpy as np
import psutil


GIB = 2**30
MIB = 2**20
_HEX64 = re.compile(r"^[0-9a-f]{64}$")
_ESTIMATE_METHODS = {
    "analytical_file_working_set_v1",
    "analytical_chunk_working_set_v1",
    "analytical_target_bundle_working_set_v1",
    "analytical_training_working_set_v1",
    "analytical_prediction_working_set_v1",
    "synthetic_bound_v1",
}
_GLOBAL_LOCK_PATH = (
    Path(tempfile.gettempdir()) / "neuralhydrology_historical_multiscale_v09_high_load.lock"
)
_ACTIVE_LEASE_REGISTRATIONS: set[object] = set()


class MemorySafetyError(RuntimeError):
    """Raised before this task can put the host near memory exhaustion."""


class TaskLeaseError(RuntimeError):
    """Raised when another version-09 high-load process owns the serial lease."""


@dataclass(frozen=True)
class HostMemorySnapshot:
    """Physical, committed-memory, and current-process usage at one decision point."""

    total_bytes: int
    available_bytes: int
    process_rss_bytes: int
    commit_headroom_bytes: int

    def __post_init__(self) -> None:
        if self.total_bytes <= 0:
            raise ValueError("total_bytes must be positive")
        if not 0 <= self.available_bytes <= self.total_bytes:
            raise ValueError("available_bytes must be within physical memory")
        if self.process_rss_bytes < 0:
            raise ValueError("process_rss_bytes must be nonnegative")
        if self.commit_headroom_bytes < 0:
            raise ValueError("commit_headroom_bytes must be nonnegative")


class TaskMemoryLease:
    """Non-constructible proof that this process currently owns the high-load mutex."""

    __slots__ = ("lock_path", "held", "_registration")

    def __init__(self, *args, **kwargs) -> None:
        raise TypeError("TaskMemoryLease instances are created only by the lease context")

    def is_valid(self) -> bool:
        return (
            getattr(self, "held", False) is True
            and getattr(self, "_registration", None) in _ACTIVE_LEASE_REGISTRATIONS
        )


@dataclass(frozen=True)
class MemorySafetyPolicy:
    """Task-specific peak margin and host reserves for version 09."""

    total_bytes: int
    estimated_peak_safety_factor: float
    physical_reserve_bytes: int
    commit_headroom_reserve_bytes: int
    allowed_long_task_estimate_methods: tuple[str, ...]
    maximum_batch_size: int
    full_window_materialization_forbidden: bool

    @classmethod
    def from_total(
        cls,
        total_bytes: int,
        policy_config: Mapping | None = None,
    ) -> "MemorySafetyPolicy":
        total_bytes = int(total_bytes)
        if total_bytes <= 0:
            raise ValueError("total_bytes must be positive")
        if policy_config is None:
            policy_config = {
                "policy": "task_specific_evidence_bound_v1",
                "serial_execution_only": True,
                "estimated_peak_safety_factor": 1.25,
                "physical_reserve_gib": 2.0,
                "commit_headroom_reserve_gib": 2.0,
                "peak_estimate_evidence_required": True,
                "allowed_long_task_estimate_methods": [
                    "analytical_file_working_set_v1",
                    "analytical_chunk_working_set_v1",
                    "analytical_target_bundle_working_set_v1",
                    "analytical_training_working_set_v1",
                    "analytical_prediction_working_set_v1",
                ],
                "maximum_batch_size": 256,
                "full_window_materialization_forbidden": True,
            }
        if policy_config.get("policy") != "task_specific_evidence_bound_v1":
            raise ValueError("unsupported memory-safety policy")
        if policy_config.get("serial_execution_only") is not True:
            raise ValueError("version 09 memory safety requires serial execution")
        if policy_config.get("peak_estimate_evidence_required") is not True:
            raise ValueError("version 09 memory safety requires peak-estimate evidence")
        allowed_methods = tuple(policy_config.get("allowed_long_task_estimate_methods", ()))
        expected_methods = (
            "analytical_file_working_set_v1",
            "analytical_chunk_working_set_v1",
            "analytical_target_bundle_working_set_v1",
            "analytical_training_working_set_v1",
            "analytical_prediction_working_set_v1",
        )
        if allowed_methods != expected_methods:
            raise ValueError("allowed long-task peak-estimate methods drift")
        factor = float(policy_config.get("estimated_peak_safety_factor", 0.0))
        physical_reserve_gib = float(policy_config.get("physical_reserve_gib", -1.0))
        commit_reserve_gib = float(policy_config.get("commit_headroom_reserve_gib", -1.0))
        maximum_batch_size = int(policy_config.get("maximum_batch_size", 0))
        full_window_forbidden = policy_config.get("full_window_materialization_forbidden")
        if not math.isfinite(factor) or factor < 1.0:
            raise ValueError("estimated_peak_safety_factor must be finite and at least 1")
        if not math.isfinite(physical_reserve_gib) or physical_reserve_gib < 0:
            raise ValueError("physical_reserve_gib must be finite and nonnegative")
        if not math.isfinite(commit_reserve_gib) or commit_reserve_gib < 0:
            raise ValueError("commit_headroom_reserve_gib must be finite and nonnegative")
        if maximum_batch_size <= 0:
            raise ValueError("maximum_batch_size must be positive")
        if full_window_forbidden is not True:
            raise ValueError("full training-window materialization must remain forbidden")
        return cls(
            total_bytes=total_bytes,
            estimated_peak_safety_factor=factor,
            physical_reserve_bytes=math.ceil(physical_reserve_gib * GIB),
            commit_headroom_reserve_bytes=math.ceil(commit_reserve_gib * GIB),
            allowed_long_task_estimate_methods=allowed_methods,
            maximum_batch_size=maximum_batch_size,
            full_window_materialization_forbidden=True,
        )


def _canonical_sha256(value: Mapping) -> str:
    payload = json.dumps(
        value,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
        allow_nan=False,
    ).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def build_file_peak_estimate_v09(
    *,
    prediction_paths: Mapping[str, str | Path],
    answer_path: str | Path,
) -> dict:
    """Build a reproducible conservative peak estimate from the exact scoring files."""
    if set(prediction_paths) != {"baseline", "capacity_control", "challenger"}:
        raise ValueError("prediction_paths must contain the three clean-pair roles")
    resolved_predictions = {
        role: Path(path).resolve() for role, path in prediction_paths.items()
    }
    resolved_answer = Path(answer_path).resolve()
    for name, path in {**resolved_predictions, "answer": resolved_answer}.items():
        if not path.is_file():
            raise ValueError(f"peak-estimate input is missing: {name}")
    prediction_sizes = {
        role: path.stat().st_size for role, path in resolved_predictions.items()
    }
    answer_size = resolved_answer.stat().st_size
    evidence_fields = {
        "formula": "512MiB + 8*answer_bytes + 10*max_prediction_bytes",
        "fixed_overhead_bytes": 512 * MIB,
        "answer_multiplier": 8,
        "prediction_multiplier": 10,
        "answer": {
            "path": str(resolved_answer),
            "size_bytes": answer_size,
        },
        "predictions": {
            role: {
                "path": str(resolved_predictions[role]),
                "size_bytes": prediction_sizes[role],
            }
            for role in ("baseline", "capacity_control", "challenger")
        },
    }
    estimated_peak = (
        evidence_fields["fixed_overhead_bytes"]
        + evidence_fields["answer_multiplier"] * answer_size
        + evidence_fields["prediction_multiplier"] * max(prediction_sizes.values())
    )
    return build_peak_estimate_v09(
        method="analytical_file_working_set_v1",
        estimated_peak_bytes=estimated_peak,
        evidence_fields=evidence_fields,
    )


def build_peak_estimate_v09(
    *,
    method: str,
    estimated_peak_bytes: int,
    evidence_fields: Mapping,
) -> dict:
    """Build a hash-bound peak estimate from deterministic evidence fields."""
    if method not in _ESTIMATE_METHODS:
        raise ValueError("peak estimate method is not permitted")
    estimated_peak_bytes = int(estimated_peak_bytes)
    if estimated_peak_bytes < 0:
        raise ValueError("estimated_peak_bytes must be nonnegative")
    if not isinstance(evidence_fields, Mapping):
        raise ValueError("evidence_fields must be an object")
    if set(evidence_fields) & {"method", "estimated_peak_bytes"}:
        raise ValueError("evidence_fields cannot override bound estimate fields")
    evidence = {
        "method": method,
        "estimated_peak_bytes": estimated_peak_bytes,
        **dict(evidence_fields),
    }
    return {
        "method": method,
        "estimated_peak_bytes": estimated_peak_bytes,
        "evidence_sha256": _canonical_sha256(evidence),
        "evidence": evidence,
    }


def validate_peak_estimate_v09(
    estimate: Mapping,
    *,
    long_running: bool,
) -> dict:
    """Require a positive, hash-bound estimate before any long-running action."""
    if not isinstance(estimate, Mapping) or set(estimate) != {
        "method",
        "estimated_peak_bytes",
        "evidence_sha256",
        "evidence",
    }:
        raise MemorySafetyError("peak estimate schema is invalid")
    method = estimate.get("method")
    if method not in _ESTIMATE_METHODS:
        raise MemorySafetyError("peak estimate method is not permitted")
    estimated_peak_bytes = int(estimate.get("estimated_peak_bytes", -1))
    if estimated_peak_bytes < 0 or (long_running and estimated_peak_bytes == 0):
        raise MemorySafetyError("long-running tasks require a positive peak estimate")
    evidence = estimate.get("evidence")
    if not isinstance(evidence, Mapping):
        raise MemorySafetyError("peak estimate evidence must be an object")
    evidence_sha256 = estimate.get("evidence_sha256")
    if not isinstance(evidence_sha256, str) or _HEX64.fullmatch(evidence_sha256) is None:
        raise MemorySafetyError("peak estimate evidence SHA-256 is invalid")
    if _canonical_sha256(evidence) != evidence_sha256:
        raise MemorySafetyError("peak estimate evidence SHA-256 drift")
    if evidence.get("method") != method:
        raise MemorySafetyError("peak estimate method differs from its evidence")
    if evidence.get("estimated_peak_bytes") != estimated_peak_bytes:
        raise MemorySafetyError("peak estimate bytes differ from its evidence")
    if method == "analytical_file_working_set_v1":
        _validate_file_peak_evidence_v09(evidence, estimated_peak_bytes)
    elif method == "analytical_chunk_working_set_v1":
        _validate_chunk_peak_evidence_v09(evidence, estimated_peak_bytes)
    elif method == "analytical_target_bundle_working_set_v1":
        _validate_target_bundle_peak_evidence_v09(evidence, estimated_peak_bytes)
    elif method == "analytical_training_working_set_v1":
        _validate_model_action_peak_evidence_v09(
            evidence,
            estimated_peak_bytes,
            action="training",
        )
    elif method == "analytical_prediction_working_set_v1":
        _validate_model_action_peak_evidence_v09(
            evidence,
            estimated_peak_bytes,
            action="formal_prediction_generation",
        )
    if long_running and method == "synthetic_bound_v1":
        raise MemorySafetyError("synthetic bounds cannot authorize a long-running task")
    return {
        "method": method,
        "estimated_peak_bytes": estimated_peak_bytes,
        "evidence_sha256": evidence_sha256,
    }


def _require_plain_nonnegative_int(value: object, *, field_name: str) -> int:
    if type(value) is not int or value < 0:
        raise MemorySafetyError(f"{field_name} must be a nonnegative integer")
    return value


def _validate_file_peak_evidence_v09(
    evidence: Mapping,
    estimated_peak_bytes: int,
) -> None:
    expected_keys = {
        "method",
        "estimated_peak_bytes",
        "formula",
        "fixed_overhead_bytes",
        "answer_multiplier",
        "prediction_multiplier",
        "answer",
        "predictions",
    }
    if set(evidence) != expected_keys:
        raise MemorySafetyError("analytical file peak evidence schema is invalid")
    if evidence.get("formula") != "512MiB + 8*answer_bytes + 10*max_prediction_bytes":
        raise MemorySafetyError("analytical file peak formula drift")
    if evidence.get("fixed_overhead_bytes") != 512 * MIB:
        raise MemorySafetyError("analytical file fixed overhead drift")
    if evidence.get("answer_multiplier") != 8:
        raise MemorySafetyError("analytical file answer multiplier drift")
    if evidence.get("prediction_multiplier") != 10:
        raise MemorySafetyError("analytical file prediction multiplier drift")

    answer = evidence.get("answer")
    if not isinstance(answer, Mapping) or set(answer) != {"path", "size_bytes"}:
        raise MemorySafetyError("analytical file answer evidence schema is invalid")
    answer_size = _validate_file_size_evidence_v09(answer, label="answer")

    predictions = evidence.get("predictions")
    roles = {"baseline", "capacity_control", "challenger"}
    if not isinstance(predictions, Mapping) or set(predictions) != roles:
        raise MemorySafetyError("analytical file prediction evidence schema is invalid")
    prediction_sizes = [
        _validate_file_size_evidence_v09(predictions[role], label=role)
        for role in sorted(roles)
    ]
    recomputed_peak = 512 * MIB + 8 * answer_size + 10 * max(prediction_sizes)
    if recomputed_peak != estimated_peak_bytes:
        raise MemorySafetyError("analytical file peak estimate does not match exact files")


def _validate_file_size_evidence_v09(value: object, *, label: str) -> int:
    if not isinstance(value, Mapping) or set(value) != {"path", "size_bytes"}:
        raise MemorySafetyError(f"analytical file evidence is invalid for {label}")
    path_text = value.get("path")
    if not isinstance(path_text, str) or not path_text:
        raise MemorySafetyError(f"analytical file path is invalid for {label}")
    path = Path(path_text)
    if not path.is_absolute() or str(path.resolve()) != path_text:
        raise MemorySafetyError(f"analytical file path is not resolved for {label}")
    recorded_size = _require_plain_nonnegative_int(
        value.get("size_bytes"),
        field_name=f"{label} size_bytes",
    )
    if not path.is_file() or path.stat().st_size != recorded_size:
        raise MemorySafetyError(f"analytical file size evidence drift for {label}")
    return recorded_size


def _validate_chunk_peak_evidence_v09(
    evidence: Mapping,
    estimated_peak_bytes: int,
) -> None:
    expected_keys = {
        "method",
        "estimated_peak_bytes",
        "formula",
        "chunk_rows",
        "seed_count",
        "bytes_per_seed_row_upper_bound",
    }
    if set(evidence) != expected_keys:
        raise MemorySafetyError("analytical chunk peak evidence schema is invalid")
    if evidence.get("formula") != "chunk_rows * seed_count * 256":
        raise MemorySafetyError("analytical chunk peak formula drift")
    chunk_rows = _require_plain_nonnegative_int(
        evidence.get("chunk_rows"),
        field_name="chunk_rows",
    )
    seed_count = _require_plain_nonnegative_int(
        evidence.get("seed_count"),
        field_name="seed_count",
    )
    if chunk_rows == 0 or seed_count == 0:
        raise MemorySafetyError("analytical chunk dimensions must be positive")
    if evidence.get("bytes_per_seed_row_upper_bound") != 256:
        raise MemorySafetyError("analytical chunk byte bound drift")
    if chunk_rows * seed_count * 256 != estimated_peak_bytes:
        raise MemorySafetyError("analytical chunk peak estimate does not match its dimensions")


def _validate_target_bundle_peak_evidence_v09(
    evidence: Mapping,
    estimated_peak_bytes: int,
) -> None:
    expected_keys = {
        "method",
        "estimated_peak_bytes",
        "protocol_canonical_sha256",
        "action",
        "formula",
        "writer",
        "fixed_overhead_bytes",
        "source_rows_per_basin",
        "source_row_bytes_upper_bound",
        "target_rows_per_basin",
        "target_row_bytes_upper_bound",
        "serialization_buffer_bytes",
    }
    if set(evidence) != expected_keys:
        raise MemorySafetyError("analytical target-bundle evidence schema is invalid")
    if evidence.get("action") != "formal_target_bundle_generation":
        raise MemorySafetyError("analytical target-bundle action drift")
    if evidence.get("writer") != "stream_one_basin_v1":
        raise MemorySafetyError("analytical target-bundle writer drift")
    if evidence.get("formula") != (
        "fixed_overhead_bytes + source_rows_per_basin*source_row_bytes_upper_bound "
        "+ target_rows_per_basin*target_row_bytes_upper_bound + serialization_buffer_bytes"
    ):
        raise MemorySafetyError("analytical target-bundle formula drift")
    _require_hex64_evidence(evidence.get("protocol_canonical_sha256"), "protocol content")
    values = {
        key: _require_plain_nonnegative_int(evidence.get(key), field_name=key)
        for key in (
            "fixed_overhead_bytes",
            "source_rows_per_basin",
            "source_row_bytes_upper_bound",
            "target_rows_per_basin",
            "target_row_bytes_upper_bound",
            "serialization_buffer_bytes",
        )
    }
    if any(values[key] == 0 for key in values):
        raise MemorySafetyError("analytical target-bundle dimensions must be positive")
    recomputed = (
        values["fixed_overhead_bytes"]
        + values["source_rows_per_basin"] * values["source_row_bytes_upper_bound"]
        + values["target_rows_per_basin"] * values["target_row_bytes_upper_bound"]
        + values["serialization_buffer_bytes"]
    )
    if recomputed != estimated_peak_bytes:
        raise MemorySafetyError("analytical target-bundle peak does not match its dimensions")


def _require_hex64_evidence(value: object, label: str) -> str:
    if not isinstance(value, str) or _HEX64.fullmatch(value) is None:
        raise MemorySafetyError(f"{label} SHA-256 is invalid")
    return value


def _validate_model_action_peak_evidence_v09(
    evidence: Mapping,
    estimated_peak_bytes: int,
    *,
    action: str,
) -> None:
    common_keys = {
        "method",
        "estimated_peak_bytes",
        "protocol_canonical_sha256",
        "action",
        "variant",
        "formula",
        "accelerator_formula",
        "host_fixed_overhead_bytes",
        "forcing_rows",
        "dynamic_input_count",
        "float_bytes",
        "forcing_copy_count",
        "basin_count",
        "static_attribute_count",
        "static_copy_count",
        "batch_size",
        "causal_window_days",
        "window_copy_count",
        "parameter_count",
        "parameter_bytes_upper_bound",
        "recent_steps",
        "recent_hidden_size",
        "history_steps",
        "history_hidden_size",
        "accelerator_fixed_overhead_bytes",
        "accelerator_input_copy_count",
        "accelerator_activation_multiplier",
        "accelerator_parameter_bytes_upper_bound",
        "accelerator_estimated_peak_bytes",
    }
    training_only = {"target_copy_count"}
    prediction_only = {
        "prediction_rows",
        "prediction_chunk_rows",
        "prediction_row_bytes_upper_bound",
    }
    expected_keys = common_keys | (training_only if action == "training" else prediction_only)
    if set(evidence) != expected_keys:
        raise MemorySafetyError(f"analytical {action} evidence schema is invalid")
    if evidence.get("action") != action:
        raise MemorySafetyError(f"analytical {action} action drift")
    _require_hex64_evidence(evidence.get("protocol_canonical_sha256"), "protocol content")
    variant = evidence.get("variant")
    if variant not in {
        "classic_lstm_256_clean",
        "classic_lstm_369_capacity",
        "continuous_multiscale_history",
    }:
        raise MemorySafetyError(f"analytical {action} variant is invalid")
    integer_keys = expected_keys - {
        "method",
        "protocol_canonical_sha256",
        "action",
        "variant",
        "formula",
        "accelerator_formula",
    }
    values = {
        key: _require_plain_nonnegative_int(evidence.get(key), field_name=key)
        for key in integer_keys
    }
    if any(values[key] == 0 for key in integer_keys - {"history_steps", "history_hidden_size"}):
        raise MemorySafetyError(f"analytical {action} dimensions must be positive")
    if (values["history_steps"] == 0) != (values["history_hidden_size"] == 0):
        raise MemorySafetyError(f"analytical {action} history geometry is inconsistent")

    if action == "training":
        expected_formula = (
            "host_fixed_overhead_bytes + forcing_bytes*forcing_copy_count + "
            "target_bytes*target_copy_count + static_bytes*static_copy_count + "
            "window_bytes*window_copy_count + parameter_count*parameter_bytes_upper_bound"
        )
    else:
        expected_formula = (
            "host_fixed_overhead_bytes + forcing_bytes*forcing_copy_count + "
            "static_bytes*static_copy_count + window_bytes*window_copy_count + "
            "prediction_chunk_rows*prediction_row_bytes_upper_bound + "
            "parameter_count*parameter_bytes_upper_bound"
        )
    if evidence.get("formula") != expected_formula:
        raise MemorySafetyError(f"analytical {action} formula drift")
    expected_accelerator_formula = (
        "accelerator_fixed_overhead_bytes + window_bytes*accelerator_input_copy_count + "
        "state_elements*float_bytes*accelerator_activation_multiplier + "
        "parameter_count*accelerator_parameter_bytes_upper_bound"
    )
    if evidence.get("accelerator_formula") != expected_accelerator_formula:
        raise MemorySafetyError(f"analytical {action} accelerator formula drift")

    forcing_bytes = (
        values["forcing_rows"] * values["dynamic_input_count"] * values["float_bytes"]
    )
    static_bytes = (
        values["basin_count"]
        * values["static_attribute_count"]
        * values["float_bytes"]
    )
    window_bytes = (
        values["batch_size"]
        * values["causal_window_days"]
        * values["dynamic_input_count"]
        * values["float_bytes"]
    )
    recomputed = (
        values["host_fixed_overhead_bytes"]
        + forcing_bytes * values["forcing_copy_count"]
        + static_bytes * values["static_copy_count"]
        + window_bytes * values["window_copy_count"]
        + values["parameter_count"] * values["parameter_bytes_upper_bound"]
    )
    if action == "training":
        target_bytes = values["forcing_rows"] * values["float_bytes"]
        recomputed += target_bytes * values["target_copy_count"]
    else:
        recomputed += (
            values["prediction_chunk_rows"]
            * values["prediction_row_bytes_upper_bound"]
        )
    if recomputed != estimated_peak_bytes:
        raise MemorySafetyError(f"analytical {action} host peak does not match its dimensions")

    state_elements = values["batch_size"] * (
        values["recent_steps"] * values["recent_hidden_size"]
        + values["history_steps"] * values["history_hidden_size"]
    )
    accelerator_peak = (
        values["accelerator_fixed_overhead_bytes"]
        + window_bytes * values["accelerator_input_copy_count"]
        + state_elements
        * values["float_bytes"]
        * values["accelerator_activation_multiplier"]
        + values["parameter_count"]
        * values["accelerator_parameter_bytes_upper_bound"]
    )
    if accelerator_peak != values["accelerator_estimated_peak_bytes"]:
        raise MemorySafetyError(
            f"analytical {action} accelerator peak does not match its dimensions"
        )


def _sample_commit_headroom_bytes() -> int:
    if os.name != "nt":
        virtual_memory = psutil.virtual_memory()
        swap_memory = psutil.swap_memory()
        return int(virtual_memory.available + swap_memory.free)

    class MEMORYSTATUSEX(ctypes.Structure):
        _fields_ = [
            ("dwLength", ctypes.c_ulong),
            ("dwMemoryLoad", ctypes.c_ulong),
            ("ullTotalPhys", ctypes.c_ulonglong),
            ("ullAvailPhys", ctypes.c_ulonglong),
            ("ullTotalPageFile", ctypes.c_ulonglong),
            ("ullAvailPageFile", ctypes.c_ulonglong),
            ("ullTotalVirtual", ctypes.c_ulonglong),
            ("ullAvailVirtual", ctypes.c_ulonglong),
            ("sullAvailExtendedVirtual", ctypes.c_ulonglong),
        ]

    status = MEMORYSTATUSEX()
    status.dwLength = ctypes.sizeof(MEMORYSTATUSEX)
    if not ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(status)):
        raise OSError("GlobalMemoryStatusEx failed")
    return int(status.ullAvailPageFile)


def sample_host_memory() -> HostMemorySnapshot:
    """Measure physical availability, commit headroom, and process resident memory."""
    virtual_memory = psutil.virtual_memory()
    resident = psutil.Process(os.getpid()).memory_info().rss
    return HostMemorySnapshot(
        total_bytes=int(virtual_memory.total),
        available_bytes=int(virtual_memory.available),
        process_rss_bytes=int(resident),
        commit_headroom_bytes=_sample_commit_headroom_bytes(),
    )


def _lock_handle_nonblocking(handle: BinaryIO) -> None:
    handle.seek(0)
    if os.name == "nt":
        import msvcrt

        try:
            msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
        except OSError as exc:
            raise TaskLeaseError("another version-09 high-load process owns the serial lease") from exc
        return
    import fcntl

    try:
        fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError as exc:
        raise TaskLeaseError("another version-09 high-load process owns the serial lease") from exc


def _unlock_handle(handle: BinaryIO) -> None:
    handle.seek(0)
    if os.name == "nt":
        import msvcrt

        msvcrt.locking(handle.fileno(), msvcrt.LK_UNLCK, 1)
        return
    import fcntl

    fcntl.flock(handle.fileno(), fcntl.LOCK_UN)


@contextmanager
def exclusive_high_load_lease_v09(
    *,
    lock_path: str | Path | None = None,
) -> Iterator[TaskMemoryLease]:
    """Hold one current-user cross-process lease for the full high-load action."""
    path = Path(lock_path).resolve() if lock_path is not None else _GLOBAL_LOCK_PATH
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a+b") as handle:
        if path.stat().st_size == 0:
            handle.write(b"\0")
            handle.flush()
        _lock_handle_nonblocking(handle)
        registration = object()
        lease = object.__new__(TaskMemoryLease)
        object.__setattr__(lease, "lock_path", str(path))
        object.__setattr__(lease, "held", True)
        object.__setattr__(lease, "_registration", registration)
        _ACTIVE_LEASE_REGISTRATIONS.add(registration)
        try:
            yield lease
        finally:
            _ACTIVE_LEASE_REGISTRATIONS.discard(registration)
            object.__setattr__(lease, "held", False)
            _unlock_handle(handle)


class MemorySafetyGate:
    """Apply evidence-bound start, runtime, and planned-allocation checks."""

    def __init__(self, policy: MemorySafetyPolicy) -> None:
        self.policy = policy

    @classmethod
    def from_snapshot(
        cls,
        snapshot: HostMemorySnapshot,
        policy_config: Mapping | None = None,
    ) -> "MemorySafetyGate":
        return cls(MemorySafetyPolicy.from_total(snapshot.total_bytes, policy_config))

    def _validate_snapshot(self, snapshot: HostMemorySnapshot) -> None:
        if snapshot.total_bytes != self.policy.total_bytes:
            raise MemorySafetyError("host physical-memory total changed after policy creation")

    def assert_start_safe(
        self,
        snapshot: HostMemorySnapshot,
        estimate: Mapping,
        *,
        long_running: bool,
        lease: TaskMemoryLease | None = None,
    ) -> dict:
        """Require peak evidence, a serial lease, and both memory reserves."""
        self._validate_snapshot(snapshot)
        validated_estimate = validate_peak_estimate_v09(
            estimate,
            long_running=long_running,
        )
        if (
            long_running
            and validated_estimate["method"]
            not in self.policy.allowed_long_task_estimate_methods
        ):
            raise MemorySafetyError("peak estimate method is not authorized for long tasks")
        if long_running and (lease is None or not lease.is_valid()):
            raise MemorySafetyError("long-running tasks require the exclusive serial lease")
        estimated_peak_bytes = validated_estimate["estimated_peak_bytes"]
        guarded_estimate = math.ceil(
            estimated_peak_bytes * self.policy.estimated_peak_safety_factor
        )
        physical_remaining = snapshot.available_bytes - guarded_estimate
        if physical_remaining < self.policy.physical_reserve_bytes:
            raise MemorySafetyError(
                "guarded task estimate would cross the physical-memory reserve: "
                f"{physical_remaining} < {self.policy.physical_reserve_bytes}"
            )
        commit_remaining = snapshot.commit_headroom_bytes - guarded_estimate
        if commit_remaining < self.policy.commit_headroom_reserve_bytes:
            raise MemorySafetyError(
                "guarded task estimate would cross the committed-memory reserve: "
                f"{commit_remaining} < {self.policy.commit_headroom_reserve_bytes}"
            )
        return {
            "safe": True,
            "long_running": bool(long_running),
            **validated_estimate,
            "guarded_estimated_peak_bytes": guarded_estimate,
            "available_after_guarded_peak_bytes": physical_remaining,
            "commit_headroom_after_guarded_peak_bytes": commit_remaining,
            "physical_reserve_bytes": self.policy.physical_reserve_bytes,
            "commit_headroom_reserve_bytes": self.policy.commit_headroom_reserve_bytes,
            "serial_lease": (
                {"held": True, "lock_path": lease.lock_path}
                if lease is not None
                else {"held": False}
            ),
        }

    def assert_runtime_safe(self, snapshot: HostMemorySnapshot) -> dict:
        """Stop between chunks before physical or committed-memory reserves are crossed."""
        self._validate_snapshot(snapshot)
        if snapshot.available_bytes < self.policy.physical_reserve_bytes:
            raise MemorySafetyError(
                "available physical memory is below the task reserve: "
                f"{snapshot.available_bytes} < {self.policy.physical_reserve_bytes}"
            )
        if snapshot.commit_headroom_bytes < self.policy.commit_headroom_reserve_bytes:
            raise MemorySafetyError(
                "committed-memory headroom is below the task reserve: "
                f"{snapshot.commit_headroom_bytes} < "
                f"{self.policy.commit_headroom_reserve_bytes}"
            )
        return {
            "safe": True,
            "available_bytes": snapshot.available_bytes,
            "commit_headroom_bytes": snapshot.commit_headroom_bytes,
            "process_rss_bytes": snapshot.process_rss_bytes,
        }

    def assert_allocation_safe(
        self,
        snapshot: HostMemorySnapshot,
        shape: Sequence[int],
        dtype,
        *,
        copies: int = 1,
    ) -> dict:
        """Reject structurally forbidden or memory-unsafe dense allocations."""
        self.assert_runtime_safe(snapshot)
        dimensions = tuple(int(value) for value in shape)
        if not dimensions or any(value < 0 for value in dimensions):
            raise ValueError("shape must contain nonnegative dimensions")
        copies = int(copies)
        if copies <= 0:
            raise ValueError("copies must be positive")
        if (
            self.policy.full_window_materialization_forbidden
            and len(dimensions) == 3
            and dimensions[1:] == (3_562, 5)
            and dimensions[0] > self.policy.maximum_batch_size
        ):
            raise MemorySafetyError(
                "full training-window materialization is forbidden independently of host capacity"
            )
        allocation_bytes = math.prod(dimensions) * np.dtype(dtype).itemsize * copies
        guarded_allocation = math.ceil(
            allocation_bytes * self.policy.estimated_peak_safety_factor
        )
        if snapshot.available_bytes - guarded_allocation < self.policy.physical_reserve_bytes:
            raise MemorySafetyError("planned allocation would cross the physical-memory reserve")
        if (
            snapshot.commit_headroom_bytes - guarded_allocation
            < self.policy.commit_headroom_reserve_bytes
        ):
            raise MemorySafetyError("planned allocation would cross the committed-memory reserve")
        return {
            "safe": True,
            "shape": dimensions,
            "dtype": np.dtype(dtype).name,
            "copies": copies,
            "allocation_bytes": allocation_bytes,
            "guarded_allocation_bytes": guarded_allocation,
        }

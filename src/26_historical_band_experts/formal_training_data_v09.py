"""Read-only, memory-bounded formal version-09 training inputs and batches."""
from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
from typing import Mapping

import numpy as np
import torch

from artifact_v09 import (
    array_payload_sha256,
    assert_no_embedded_seal_entries,
    assert_no_reparse_components,
    assert_no_reparse_tree,
    canonical_sha256,
    sha256_file,
)
from bands_formal_v09 import gather_causal_windows_v09, split_windows_v09
from formal_input_contract_v09 import STATIC_NORMALIZED_FLOAT32_SHA256
from memory_safety_v09 import HostMemorySnapshot, MemorySafetyGate, sample_host_memory

_RECENT_DAYS = 270
_FULL_DAYS = 3_562
_DYNAMIC_SIZE = 5
_STATIC_SIZE = 27
_RECENT_VARIANTS = {
    "classic_lstm_256_clean",
    "classic_lstm_369_capacity",
    "nested_history_disabled",
}
_HISTORY_VARIANT = "continuous_multiscale_history"


class FormalTrainingDataError(RuntimeError):
    """Raised when sealed training inputs or numeric layout drift."""


@dataclass(frozen=True)
class FormalTrainingInputsV09:
    root: Path | None
    basins: tuple[str, ...]
    dates: np.ndarray
    target_dates: np.ndarray
    forcing: np.ndarray
    statics: np.ndarray
    targets: np.ndarray
    scaler: Mapping
    input_seal_sha256: str | None = None
    external_audit_sha256: str | None = None
    trusted_source_audit_sha256: str | None = None

    @classmethod
    def synthetic(
        cls,
        *,
        forcing: np.ndarray,
        statics: np.ndarray,
        targets: np.ndarray,
        dates: np.ndarray,
        target_dates: np.ndarray,
        scaler: Mapping | None = None,
    ) -> "FormalTrainingInputsV09":
        if scaler is None:
            scaler = {
                "dynamic_center_float64": [0.0] * forcing.shape[-1],
                "dynamic_scale_float64": [1.0] * forcing.shape[-1],
                "target_center_float64": 0.0,
                "target_scale_float64": 1.0,
                "per_basin_target_scale_float64": [1.0] * forcing.shape[0],
            }
        basins = tuple(f"{index + 1:08d}" for index in range(forcing.shape[0]))
        result = cls(
            root=None,
            basins=basins,
            dates=np.asarray(dates),
            target_dates=np.asarray(target_dates),
            forcing=np.asarray(forcing),
            statics=np.asarray(statics),
            targets=np.asarray(targets),
            scaler=dict(scaler),
        )
        _validate_training_arrays_v09(result, require_formal_geometry=False)
        return result


@dataclass(frozen=True)
class TrainingBatchV09:
    dynamic: dict[str, torch.Tensor]
    statics: torch.Tensor
    target: torch.Tensor
    raw_per_basin_std: torch.Tensor
    basin_indices: np.ndarray
    target_indices: np.ndarray


def _validate_training_arrays_v09(
    inputs: FormalTrainingInputsV09,
    *,
    require_formal_geometry: bool,
) -> None:
    basin_count = len(inputs.basins)
    if inputs.forcing.dtype != np.float32 or inputs.forcing.shape[-1] != _DYNAMIC_SIZE:
        raise FormalTrainingDataError("forcing geometry or dtype drift")
    if inputs.statics.dtype != np.float32 or inputs.statics.shape != (basin_count, _STATIC_SIZE):
        raise FormalTrainingDataError("static geometry or dtype drift")
    if inputs.targets.dtype != np.float32 or inputs.targets.shape != (
            basin_count,
            len(inputs.target_dates),
    ):
        raise FormalTrainingDataError("target geometry or dtype drift")
    if inputs.forcing.shape[:2] != (basin_count, len(inputs.dates)):
        raise FormalTrainingDataError("forcing date coverage drift")
    if inputs.dates.dtype != np.dtype("datetime64[D]") or inputs.target_dates.dtype != np.dtype("datetime64[D]"):
        raise FormalTrainingDataError("date dtype drift")
    if len(np.unique(inputs.dates)) != len(inputs.dates) or len(np.unique(inputs.target_dates)) != len(
            inputs.target_dates):
        raise FormalTrainingDataError("duplicate training date")
    if not np.all(np.diff(inputs.dates).astype("timedelta64[D]") == np.timedelta64(1, "D")):
        raise FormalTrainingDataError("forcing dates are not contiguous")
    if not np.all(np.diff(inputs.target_dates).astype("timedelta64[D]") == np.timedelta64(1, "D")):
        raise FormalTrainingDataError("target dates are not contiguous")
    if not np.isfinite(inputs.statics).all() or not np.isfinite(inputs.targets).all():
        raise FormalTrainingDataError("nonfinite sealed training values")
    if require_formal_geometry and (basin_count != 531 or inputs.forcing.shape != (531, 10_501, 5) or
                                    inputs.statics.shape != (531, 27) or inputs.targets.shape != (531, 3_288)):
        raise FormalTrainingDataError("formal training geometry drift")


def _load_passed_report(path: Path, expected_status: str) -> dict:
    if not path.is_file():
        raise FormalTrainingDataError(f"required external audit is missing: {path.name}")
    report = json.loads(path.read_text(encoding="utf-8"))
    if report.get("status") != expected_status:
        raise FormalTrainingDataError(f"external audit status failed: {path.name}")
    return report


def _verify_consumed_input_files_v09(input_root: Path, seal: Mapping) -> None:
    """Rehash every file that can affect training before opening any array."""
    sealed_files = seal.get("sealed_files")
    if not isinstance(sealed_files, list):
        raise FormalTrainingDataError("complete input sealed-file inventory drift")
    assert_no_embedded_seal_entries(sealed_files)
    if seal.get("sealed_files_sha256") != canonical_sha256(sealed_files):
        raise FormalTrainingDataError("complete input sealed-file inventory drift")
    assert_no_reparse_tree(input_root)
    descriptor_by_name = {item.get("relative_path"): item for item in sealed_files if isinstance(item, Mapping)}
    consumed_names = (
        "basins.txt",
        "dates.npy",
        "target_dates.npy",
        "forcing.npy",
        "statics.npy",
        "targets.npy",
        "scaler.json",
    )
    if any(name not in descriptor_by_name for name in consumed_names):
        raise FormalTrainingDataError("complete input consumed-file inventory is incomplete")
    actual_names = sorted(path.relative_to(input_root).as_posix() for path in input_root.rglob("*") if path.is_file())
    expected_names = sorted((*descriptor_by_name, "seal.json"))
    if actual_names != expected_names:
        raise FormalTrainingDataError("complete input directory file inventory drift")
    for name in consumed_names:
        descriptor = descriptor_by_name[name]
        path = input_root / name
        if (path.stat().st_size != descriptor.get("size_bytes") or sha256_file(path) != descriptor.get("sha256")):
            raise FormalTrainingDataError(f"sealed training input file drift: {name}")


def load_sealed_training_inputs_v09(
    input_root: str | Path,
    protocol_path: str | Path,
    *,
    worktree_root: str | Path,
    external_audit_path: str | Path | None = None,
    trusted_source_audit_path: str | Path | None = None,
) -> FormalTrainingInputsV09:
    """Open only the sealed normalized arrays needed by formal training."""
    trusted_root = Path(os.path.abspath(worktree_root))
    raw_input_root = Path(os.path.abspath(input_root))
    raw_protocol_path = Path(os.path.abspath(protocol_path))
    assert_no_reparse_components(trusted_root, trusted_root)
    assert_no_reparse_components(trusted_root, raw_input_root)
    assert_no_reparse_components(trusted_root, raw_protocol_path)
    input_root = raw_input_root.resolve()
    protocol_path = raw_protocol_path.resolve()
    formal_root = input_root.parent
    if external_audit_path is None:
        external_audit_path = formal_root / f"{input_root.name}.external_audit.json"
    if trusted_source_audit_path is None:
        trusted_source_audit_path = formal_root / f"{input_root.name}.trusted_source_external_audit.json"
    external_audit_path = Path(external_audit_path)
    trusted_source_audit_path = Path(trusted_source_audit_path)
    assert_no_reparse_components(trusted_root, external_audit_path)
    assert_no_reparse_components(trusted_root, trusted_source_audit_path)
    external = _load_passed_report(external_audit_path, "complete_input_audit_passed")
    trusted = _load_passed_report(trusted_source_audit_path, "complete_trusted_training_target_audit")
    protocol = json.loads(protocol_path.read_text(encoding="utf-8"))
    if protocol.get("formal_evaluation_target_access") is not False:
        raise FormalTrainingDataError("formal evaluation target access must remain closed")
    seal_path = input_root / "seal.json"
    seal = json.loads(seal_path.read_text(encoding="utf-8"))
    if seal.get("status") != "sealed":
        raise FormalTrainingDataError("complete input seal status drift")
    if external.get("audit_context", {}).get("input_seal_sha256") != sha256_file(seal_path):
        raise FormalTrainingDataError("external input audit seal binding drift")
    if trusted.get("complete_input_external_audit_sha256") != sha256_file(external_audit_path):
        raise FormalTrainingDataError("trusted target audit binding drift")
    _verify_consumed_input_files_v09(input_root, seal)
    basins = tuple(
        line.strip() for line in (input_root / "basins.txt").read_text(encoding="utf-8").splitlines() if line.strip())
    scaler = json.loads((input_root / "scaler.json").read_text(encoding="utf-8"))
    dates = np.load(input_root / "dates.npy", mmap_mode="r", allow_pickle=False)
    target_dates = np.load(input_root / "target_dates.npy", mmap_mode="r", allow_pickle=False)
    forcing = np.load(input_root / "forcing.npy", mmap_mode="r", allow_pickle=False)
    statics = np.load(input_root / "statics.npy", mmap_mode="r", allow_pickle=False)
    targets = np.load(input_root / "targets.npy", mmap_mode="r", allow_pickle=False)
    for label, values in (
        ("dates", dates),
        ("target dates", target_dates),
        ("forcing", forcing),
        ("statics", statics),
        ("targets", targets),
    ):
        if values.flags.writeable:
            raise FormalTrainingDataError(f"sealed {label} array is not read-only")
    if array_payload_sha256(statics) != STATIC_NORMALIZED_FLOAT32_SHA256:
        raise FormalTrainingDataError("normalized static payload SHA-256 drift")
    result = FormalTrainingInputsV09(
        root=input_root,
        basins=basins,
        dates=dates,
        target_dates=target_dates,
        forcing=forcing,
        statics=statics,
        targets=targets,
        scaler=scaler,
        input_seal_sha256=sha256_file(seal_path),
        external_audit_sha256=sha256_file(external_audit_path),
        trusted_source_audit_sha256=sha256_file(trusted_source_audit_path),
    )
    _validate_training_arrays_v09(result, require_formal_geometry=True)
    return result


def ordered_training_keys_v09(inputs: FormalTrainingInputsV09,) -> tuple[np.ndarray, np.ndarray]:
    """Return basin-major, date-minor indices into the forcing cube."""
    locations = np.searchsorted(inputs.dates, inputs.target_dates)
    if np.any(locations >= len(inputs.dates)) or not np.array_equal(inputs.dates[locations], inputs.target_dates):
        raise FormalTrainingDataError("target dates are not an exact subset of forcing dates")
    basin_indices = np.repeat(np.arange(len(inputs.basins), dtype=np.int64), len(inputs.target_dates))
    target_indices = np.tile(locations.astype(np.int64, copy=False), len(inputs.basins))
    return basin_indices, target_indices


def epoch_order_v09(sample_count: int, *, seed: int, epoch: int) -> np.ndarray:
    """Create one complete model-independent CPU permutation."""
    sample_count = int(sample_count)
    if sample_count <= 0:
        raise ValueError("sample_count must be positive")
    if int(epoch) <= 0:
        raise ValueError("epoch must be positive")
    generator = torch.Generator(device="cpu")
    generator.manual_seed(int(seed) * 1_000_003 + int(epoch))
    return torch.randperm(sample_count, generator=generator, dtype=torch.int64).numpy()


def permutation_sha256_v09(order: np.ndarray) -> str:
    if order.dtype != np.int64 or order.ndim != 1 or not order.flags.c_contiguous:
        raise FormalTrainingDataError("permutation layout drift")
    return hashlib.sha256(order.tobytes(order="C")).hexdigest()


def normalize_forcing_batch_v09(values: np.ndarray, scaler: Mapping) -> np.ndarray:
    """Apply the frozen float32 subtract-then-divide sequence."""
    if values.dtype != np.float32 or not values.flags.c_contiguous:
        raise FormalTrainingDataError("forcing batch layout drift")
    center = np.ascontiguousarray(np.asarray(scaler["dynamic_center_float64"], dtype=np.float32))
    scale = np.ascontiguousarray(np.asarray(scaler["dynamic_scale_float64"], dtype=np.float32))
    if center.shape != (values.shape[-1],) or scale.shape != center.shape:
        raise FormalTrainingDataError("dynamic scaler geometry drift")
    if not np.isfinite(scale).all() or np.any(scale <= 0):
        raise FormalTrainingDataError("invalid dynamic scale")
    normalized = np.empty_like(values)
    np.subtract(values, center, out=normalized, casting="no")
    np.divide(normalized, scale, out=normalized, casting="no")
    if not np.isfinite(normalized).all():
        raise FormalTrainingDataError("nonfinite normalized forcing")
    return normalized


def normalize_target_batch_v09(values: np.ndarray, scaler: Mapping) -> np.ndarray:
    if values.dtype != np.float32 or values.ndim != 1 or not values.flags.c_contiguous:
        raise FormalTrainingDataError("target batch layout drift")
    center = np.float32(scaler["target_center_float64"])
    scale = np.float32(scaler["target_scale_float64"])
    if not np.isfinite(scale) or scale <= 0:
        raise FormalTrainingDataError("invalid target scale")
    normalized = np.empty_like(values)
    np.subtract(values, center, out=normalized, casting="no")
    np.divide(normalized, scale, out=normalized, casting="no")
    if not np.isfinite(normalized).all():
        raise FormalTrainingDataError("nonfinite normalized target")
    return normalized


def masked_nse_training_loss_v09(
    prediction: torch.Tensor,
    target: torch.Tensor,
    raw_per_basin_std: torch.Tensor,
) -> torch.Tensor:
    if prediction.shape != target.shape or prediction.shape != raw_per_basin_std.shape:
        raise FormalTrainingDataError("loss tensor shape drift")
    if prediction.ndim != 1:
        raise FormalTrainingDataError("loss tensors must be one-dimensional")
    if not torch.isfinite(prediction).all() or not torch.isfinite(target).all():
        raise FormalTrainingDataError("loss input contains nonfinite values")
    if not torch.isfinite(raw_per_basin_std).all() or torch.any(raw_per_basin_std <= 0):
        raise FormalTrainingDataError("invalid per-basin target scale")
    eps = torch.tensor(0.1, dtype=prediction.dtype, device=prediction.device)
    return torch.mean(torch.square(prediction - target) / torch.square(raw_per_basin_std + eps))


def _as_batch_indices(values, upper: int, label: str) -> np.ndarray:
    result = np.ascontiguousarray(np.asarray(values, dtype=np.int64))
    if result.ndim != 1 or result.size == 0 or result.size > 256:
        raise FormalTrainingDataError(f"{label} must contain 1 through 256 indices")
    if int(result.min()) < 0 or int(result.max()) >= upper:
        raise FormalTrainingDataError(f"{label} is outside the sealed array")
    return result


def _allocation_check(
    gate: MemorySafetyGate | None,
    snapshot: HostMemorySnapshot | None,
    shape,
    *,
    copies: int,
) -> HostMemorySnapshot | None:
    if gate is None:
        return snapshot
    if snapshot is None:
        snapshot = sample_host_memory()
    gate.assert_allocation_safe(snapshot, shape, np.float32, copies=copies)
    return snapshot


def load_training_batch_v09(
    inputs: FormalTrainingInputsV09,
    basin_indices,
    target_indices,
    *,
    variant: str,
    device: str | torch.device,
    gate: MemorySafetyGate | None = None,
    snapshot: HostMemorySnapshot | None = None,
) -> TrainingBatchV09:
    """Copy, normalize, and transfer exactly one formal training batch."""
    if variant not in (*_RECENT_VARIANTS, _HISTORY_VARIANT):
        raise ValueError(f"unsupported formal training variant: {variant}")
    basins = _as_batch_indices(basin_indices, len(inputs.basins), "basin_indices")
    targets = _as_batch_indices(target_indices, len(inputs.dates), "target_indices")
    if basins.shape != targets.shape:
        raise FormalTrainingDataError("batch basin and target index shape drift")
    positions = np.searchsorted(inputs.target_dates, inputs.dates[targets])
    if np.any(positions >= len(inputs.target_dates)) or not np.array_equal(inputs.target_dates[positions],
                                                                           inputs.dates[targets]):
        raise FormalTrainingDataError("training target date is outside the sealed target period")

    if variant == _HISTORY_VARIANT:
        snapshot = _allocation_check(gate, snapshot, (len(basins), _FULL_DAYS, _DYNAMIC_SIZE), copies=4)
        windows = gather_causal_windows_v09(
            inputs.forcing,
            basins,
            targets,
            gate=gate,
            snapshot=snapshot,
        )
        normalized = normalize_forcing_batch_v09(windows, inputs.scaler)
        dynamic = split_windows_v09(torch.from_numpy(normalized).to(device))
    else:
        snapshot = _allocation_check(gate, snapshot, (len(basins), _RECENT_DAYS, _DYNAMIC_SIZE), copies=4)
        recent = np.empty((len(basins), _RECENT_DAYS, _DYNAMIC_SIZE), dtype=np.float32)
        for row, (basin_index, target_index) in enumerate(zip(basins, targets)):
            source = inputs.forcing[int(basin_index), int(target_index) - _RECENT_DAYS + 1:int(target_index) + 1]
            if source.shape != (_RECENT_DAYS, _DYNAMIC_SIZE):
                raise FormalTrainingDataError("recent forcing window coverage drift")
            np.copyto(recent[row], source, casting="no")
        normalized = normalize_forcing_batch_v09(recent, inputs.scaler)
        dynamic = {"recent": torch.from_numpy(normalized).to(device)}

    static_values = np.ascontiguousarray(inputs.statics[basins], dtype=np.float32)
    raw_targets = np.ascontiguousarray(inputs.targets[basins, positions], dtype=np.float32)
    target_values = normalize_target_batch_v09(raw_targets, inputs.scaler)
    per_basin = np.ascontiguousarray(
        np.asarray(inputs.scaler["per_basin_target_scale_float64"], dtype=np.float32)[basins])
    if not np.isfinite(per_basin).all() or np.any(per_basin <= 0):
        raise FormalTrainingDataError("invalid per-basin target scale")
    return TrainingBatchV09(
        dynamic=dynamic,
        statics=torch.from_numpy(static_values).to(device),
        target=torch.from_numpy(target_values).to(device),
        raw_per_basin_std=torch.from_numpy(per_basin).to(device),
        basin_indices=basins,
        target_indices=targets,
    )

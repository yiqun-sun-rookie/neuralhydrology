"""Pre-registered history-state diagnostics for the eight continuous runs (S5).

Everything here is fixed by
`docs/technical/historical_multiscale_formal_v09_state_diagnostics_preregistration.md`
and nothing may be chosen after seeing results: the panel, the sample order, the five
columns, the dtypes and the summary statistics were all written down first.

This process runs *after* all training is finished and only ever touches the history
encoder. It never opens the training targets, never runs the recent path or the flow head,
and never writes into a sealed run directory.
"""
from __future__ import annotations

from collections.abc import Mapping, Sequence
import argparse
import hashlib
import json
import os
import platform
from pathlib import Path
import subprocess

import numpy as np
import torch

IDEA_ROOT = Path(__file__).resolve().parent
import sys

if str(IDEA_ROOT) not in sys.path:
    sys.path.insert(0, str(IDEA_ROOT))

from artifact_v09 import canonical_sha256, promote_directory, sha256_file, write_json_atomic
from bands_formal_v09 import gather_causal_windows_v09, split_windows_v09
from formal_training_data_v09 import (
    load_sealed_bridge_inputs_v09,
    normalize_forcing_batch_v09,
    verify_sealed_bridge_inputs_unchanged_v09,
)
from models_formal_v09 import build_model_v09
from train_formal_v09 import load_run_order_v09

_CHECKPOINT_EPOCHS = (10, 20, 30)
_PANEL_DATES = 12
_TRAINING_DATE_COUNT = 3288
_STATE_COLUMNS = (
    "raw_hidden_norm",
    "raw_cell_norm",
    "gated_hidden_norm",
    "gated_cell_norm",
    "raw_cell_max_abs",
)
_SATURATION_THRESHOLD = 0.95
_DIAGNOSTIC_SOURCE_FILES = (
    "src/26_historical_band_experts/artifact_v09.py",
    "src/26_historical_band_experts/audit_state_diagnostics_formal_v09.py",
    "src/26_historical_band_experts/bands_formal_v09.py",
    "src/26_historical_band_experts/formal_training_data_v09.py",
    "src/26_historical_band_experts/models_formal_v09.py",
    "src/26_historical_band_experts/models_v03.py",
    "src/26_historical_band_experts/state_diagnostics_formal_v09.py",
    "src/26_historical_band_experts/train_formal_v09.py",
    "src/26_historical_band_experts/configs/formal_v09_protocol.json",
    "src/26_historical_band_experts/configs/formal_v09_run_order.json",
    "docs/technical/historical_multiscale_formal_v09_state_diagnostics_preregistration.md",
)


class StateDiagnosticsError(RuntimeError):
    """Raised when the diagnostics cannot be produced exactly as pre-registered."""


def panel_date_indices_v09(training_date_count: int = _TRAINING_DATE_COUNT) -> np.ndarray:
    """The twelve frozen date indices: floor(linspace(0, last, 12))."""
    last = int(training_date_count) - 1
    return np.floor(np.linspace(0, last, _PANEL_DATES)).astype(np.int64)


def panel_keys_v09(basin_count: int, training_date_count: int = _TRAINING_DATE_COUNT) -> np.ndarray:
    """Basin-major order: frozen basin order first, then the twelve date indices ascending."""
    dates = panel_date_indices_v09(training_date_count)
    basins = np.repeat(np.arange(int(basin_count), dtype=np.int64), len(dates))
    tiled = np.tile(dates, int(basin_count))
    return np.ascontiguousarray(np.stack((basins, tiled), axis=1).astype(np.int32))


def all_training_keys_v09(basin_count: int, training_date_count: int = _TRAINING_DATE_COUNT) -> np.ndarray:
    """Every training key, frozen basin order first, then date index 0..last."""
    dates = np.arange(int(training_date_count), dtype=np.int64)
    basins = np.repeat(np.arange(int(basin_count), dtype=np.int64), len(dates))
    tiled = np.tile(dates, int(basin_count))
    return np.ascontiguousarray(np.stack((basins, tiled), axis=1).astype(np.int32))


def state_norms_from_states_v09(
    raw_hidden: torch.Tensor,
    raw_cell: torch.Tensor,
    gated_hidden: torch.Tensor,
    gated_cell: torch.Tensor,
) -> np.ndarray:
    """The five pre-registered float32 columns, in the pre-registered order."""
    for name, tensor in (("raw_hidden", raw_hidden), ("raw_cell", raw_cell),
                         ("gated_hidden", gated_hidden), ("gated_cell", gated_cell)):
        if tensor.ndim != 2:
            raise StateDiagnosticsError(f"{name} state must be [batch, hidden]")
    columns = torch.stack(
        (
            torch.linalg.vector_norm(raw_hidden, dim=1),
            torch.linalg.vector_norm(raw_cell, dim=1),
            torch.linalg.vector_norm(gated_hidden, dim=1),
            torch.linalg.vector_norm(gated_cell, dim=1),
            raw_cell.abs().amax(dim=1),
        ),
        dim=1,
    )
    return np.ascontiguousarray(columns.detach().cpu().numpy().astype("<f4"))


def history_states_v09(model: torch.nn.Module, history: torch.Tensor, statics: torch.Tensor) -> dict:
    """Run only the history encoder and its two gates; never the recent path or the head."""
    from models_v03 import _append_statics

    with torch.no_grad():
        _, (hidden, cell) = model.history_encoder(_append_statics(history, statics))
        raw_hidden = hidden.squeeze(0)
        raw_cell = cell.squeeze(0)
        gated_hidden = torch.tanh(model.hidden_gate).reshape(1, -1) * raw_hidden
        gated_cell = torch.tanh(model.cell_gate).reshape(1, -1) * raw_cell
    return {
        "raw_hidden": raw_hidden,
        "raw_cell": raw_cell,
        "gated_hidden": gated_hidden,
        "gated_cell": gated_cell,
    }


def gate_summary_v09(model: torch.nn.Module) -> dict:
    """Gate norms, extremes and the pre-registered saturation fraction."""
    summary = {}
    with torch.no_grad():
        for name in ("hidden_gate", "cell_gate"):
            gate = getattr(model, name).detach()
            saturated = (torch.tanh(gate).abs() >= _SATURATION_THRESHOLD).double().mean()
            summary[name] = {
                "euclidean_norm": float(torch.linalg.vector_norm(gate.reshape(-1)).cpu()),
                "maximum_absolute": float(gate.abs().max().cpu()),
                "saturated_fraction": float(saturated.cpu()),
            }
    return summary


def column_summary_v09(states: np.ndarray) -> dict:
    """Summaries are recomputed in float64 from the reloaded array, linear interpolation."""
    if states.ndim != 2 or states.shape[1] != len(_STATE_COLUMNS):
        raise StateDiagnosticsError("state array must be [samples, 5]")
    values = states.astype(np.float64)
    finite = np.isfinite(values)
    summary = {
        "sample_count": int(states.shape[0]),
        "finite_values": int(finite.sum()),
        "nonfinite_positions": [[int(r), int(c)] for r, c in zip(*np.nonzero(~finite))][:64],
        "columns": {},
    }
    for index, name in enumerate(_STATE_COLUMNS):
        column = values[:, index]
        summary["columns"][name] = {
            "minimum": float(np.min(column)),
            "median": float(np.percentile(column, 50, method="linear")),
            "percentile_95": float(np.percentile(column, 95, method="linear")),
            "percentile_99": float(np.percentile(column, 99, method="linear")),
            "maximum": float(np.max(column)),
        }
    return summary


def _sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def _save_array_v09(path: Path, array: np.ndarray, dtype: str) -> dict:
    if array.dtype.str != dtype or not array.flags.c_contiguous:
        raise StateDiagnosticsError(f"array layout drift for {path.name}")
    if path.exists():
        raise FileExistsError(f"diagnostic array already exists: {path}")
    np.save(path, array, allow_pickle=False)
    return {
        "relative_path": path.name,
        "shape": list(array.shape),
        "dtype": array.dtype.str,
        "c_contiguous": True,
        "raw_bytes_sha256": _sha256_bytes(array.tobytes(order="C")),
        "file_sha256": _sha256_bytes(path.read_bytes()),
    }


def write_seed_diagnostics_v09(
    output_dir: str | Path,
    *,
    seed: int,
    checkpoints: Mapping[int, Mapping],
    provenance: Mapping | None = None,
) -> dict:
    """Persist one continuous run's diagnostics; `checkpoints` maps epoch -> arrays."""
    output_dir = Path(os.path.abspath(output_dir))
    if output_dir.exists() and any(output_dir.iterdir()):
        raise FileExistsError(f"diagnostic directory is not empty: {output_dir}")
    output_dir.mkdir(parents=True, exist_ok=True)
    entries = {}
    summary = {"seed": int(seed), "checkpoints": {}}
    for epoch in _CHECKPOINT_EPOCHS:
        if epoch not in checkpoints:
            raise StateDiagnosticsError(f"missing checkpoint {epoch} diagnostics for seed {seed}")
        payload = checkpoints[epoch]
        prefix = f"epoch{epoch:03d}_panel"
        entries[f"{prefix}_keys"] = _save_array_v09(
            output_dir / f"{prefix}_keys.int32.npy", payload["panel_keys"], "<i4")
        entries[f"{prefix}_state_norms"] = _save_array_v09(
            output_dir / f"{prefix}_state_norms.float32.npy", payload["panel_states"], "<f4")
        summary["checkpoints"][str(epoch)] = {
            "gates": payload["gates"],
            "panel": column_summary_v09(np.load(output_dir / f"{prefix}_state_norms.float32.npy")),
        }
        if epoch == 30:
            entries["epoch030_all_training_keys"] = _save_array_v09(
                output_dir / "epoch030_all_training_keys.int32.npy", payload["all_keys"], "<i4")
            entries["epoch030_all_training_state_norms"] = _save_array_v09(
                output_dir / "epoch030_all_training_state_norms.float32.npy", payload["all_states"], "<f4")
            summary["checkpoints"]["30"]["all_training_keys"] = column_summary_v09(
                np.load(output_dir / "epoch030_all_training_state_norms.float32.npy"))
    manifest = {
        "schema": "historical_multiscale_formal_v09_state_diagnostics_manifest_v1",
        "status": "state_diagnostics_complete",
        "seed": int(seed),
        "state_columns": list(_STATE_COLUMNS),
        "checkpoint_epochs": list(_CHECKPOINT_EPOCHS),
        "arrays": entries,
        "training_target_reads": 0,
        "formal_evaluation_observation_reads": 0,
        "recent_path_executed": False,
        "flow_head_executed": False,
    }
    if provenance is not None:
        manifest["provenance"] = dict(provenance)

    write_json_atomic(output_dir / "summary.json", summary)
    write_json_atomic(output_dir / "manifest.json", manifest)
    return manifest


def compare_diagnostic_manifests_v09(first: Mapping, second: Mapping) -> dict:
    """Independent replay must reproduce every key and state array byte for byte."""
    mismatched = []
    for name, entry in first["arrays"].items():
        other = second["arrays"].get(name)
        if other is None:
            mismatched.append(name)
            continue
        if entry["raw_bytes_sha256"] != other["raw_bytes_sha256"] or entry["shape"] != other["shape"]:
            mismatched.append(name)
    if set(second["arrays"]) - set(first["arrays"]):
        mismatched.extend(sorted(set(second["arrays"]) - set(first["arrays"])))
    if mismatched:
        raise StateDiagnosticsError(f"state diagnostic replay differs for: {sorted(set(mismatched))}")
    return {"arrays_identical": True, "array_count": len(first["arrays"])}


def _load_json_v09(path: Path) -> dict:
    def reject_constant(value: str):
        raise StateDiagnosticsError(f"non-finite JSON constant is forbidden: {value}")

    try:
        value = json.loads(path.read_text(encoding="utf-8"), parse_constant=reject_constant)
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise StateDiagnosticsError(f"invalid state-diagnostic dependency: {path}") from exc
    if not isinstance(value, dict):
        raise StateDiagnosticsError(f"state-diagnostic dependency must be a JSON object: {path}")
    return value


def _require_sha256_v09(value: object, label: str) -> str:
    if (not isinstance(value, str) or len(value) != 64 or
            any(character not in "0123456789abcdef" for character in value)):
        raise StateDiagnosticsError(f"{label} is not a lowercase SHA-256 digest")
    return value


def _resolve_run_order_v09(run_order) -> tuple:
    if isinstance(run_order, (str, Path)):
        return load_run_order_v09(run_order)
    if not isinstance(run_order, Sequence) or isinstance(run_order, (str, bytes)):
        raise StateDiagnosticsError("state diagnostics require the frozen run order")
    specs = tuple(run_order)
    if len(specs) != 24 or [getattr(spec, "position", None) for spec in specs] != list(range(1, 25)):
        raise StateDiagnosticsError("state diagnostics require exactly 24 ordered run specifications")
    if len({getattr(spec, "run_id", None) for spec in specs}) != 24:
        raise StateDiagnosticsError("state diagnostic run identifiers are duplicated")
    return specs


def _deterministic_environment_v09(device: str | torch.device) -> dict:
    torch_device = torch.device(device)
    device_name = None
    device_capability = None
    device_total_memory_bytes = None
    driver_version = None
    if torch_device.type == "cuda":
        if os.environ.get("CUBLAS_WORKSPACE_CONFIG") != ":4096:8":
            raise StateDiagnosticsError("CUBLAS_WORKSPACE_CONFIG must be set before the CUDA process starts")
        if not torch.cuda.is_available():
            raise StateDiagnosticsError("the registered CUDA device is unavailable")
        torch.use_deterministic_algorithms(True)
        torch.backends.cudnn.benchmark = False
        torch.backends.cudnn.deterministic = True
        torch.backends.cuda.matmul.allow_tf32 = False
        torch.backends.cudnn.allow_tf32 = False
        device_name = torch.cuda.get_device_name(torch_device)
        device_capability = list(torch.cuda.get_device_capability(torch_device))
        device_total_memory_bytes = int(torch.cuda.get_device_properties(torch_device).total_memory)
        completed = subprocess.run(
            ["nvidia-smi", "--query-gpu=driver_version", "--format=csv,noheader,nounits"],
            capture_output=True,
            text=True,
            check=False,
            timeout=15,
        )
        versions = {line.strip() for line in completed.stdout.splitlines() if line.strip()}
        if completed.returncode != 0 or len(versions) != 1:
            raise StateDiagnosticsError("NVIDIA driver version cannot be recorded unambiguously")
        driver_version = versions.pop()
    return {
        "device": str(torch_device),
        "device_name": device_name,
        "device_capability": device_capability,
        "device_total_memory_bytes": device_total_memory_bytes,
        "driver_version": driver_version,
        "python": platform.python_version(),
        "python_executable": str(Path(sys.executable).resolve()),
        "numpy": np.__version__,
        "torch": torch.__version__,
        "cuda": torch.version.cuda,
        "cudnn": torch.backends.cudnn.version(),
        "deterministic_algorithms": torch.are_deterministic_algorithms_enabled(),
        "cudnn_benchmark": torch.backends.cudnn.benchmark,
        "cudnn_deterministic": torch.backends.cudnn.deterministic,
        "cuda_matmul_allow_tf32": torch.backends.cuda.matmul.allow_tf32,
        "cudnn_allow_tf32": torch.backends.cudnn.allow_tf32,
        "cublas_workspace_config": os.environ.get("CUBLAS_WORKSPACE_CONFIG"),
    }


def _load_diagnostic_inputs_v09(input_root: Path, formal_root: Path):
    repo_root = formal_root.parents[2]
    protocol_path = repo_root / "src/26_historical_band_experts/configs/formal_v09_protocol.json"
    return load_sealed_bridge_inputs_v09(
        input_root,
        protocol_path,
        worktree_root=repo_root,
        external_audit_path=formal_root / "input_attempt_01.external_audit.json",
        trusted_source_audit_path=formal_root / "input_attempt_01.trusted_source_external_audit.json",
    )


def _load_training_audit_v09(formal_root: Path) -> tuple[dict, dict[str, dict]]:
    path = formal_root / "training_external_audit.json"
    report = _load_json_v09(path)
    if (report.get("schema") != "historical_multiscale_formal_v09_training_external_audit_v1" or
            report.get("status") != "complete_training_audit"):
        raise StateDiagnosticsError("training external audit schema or status drift")
    if report.get("coverage") != {"expected_runs": 24, "audited_runs": 24, "passed_runs": 24}:
        raise StateDiagnosticsError("training external audit run coverage drift")
    if (report.get("formal_evaluation_observation_reads") != 0 or
            report.get("formal_period_predictions_generated") is not False or
            report.get("official_score_called") is not False):
        raise StateDiagnosticsError("training external audit contains premature evaluation activity")
    runs = report.get("runs")
    if not isinstance(runs, list) or len(runs) != 24:
        raise StateDiagnosticsError("training external audit run records are incomplete")
    by_id = {row.get("run_id"): row for row in runs if isinstance(row, Mapping)}
    if len(by_id) != 24 or None in by_id:
        raise StateDiagnosticsError("training external audit run identifiers are duplicated")
    return report, by_id


def _validate_diagnostic_checkpoint_record_v09(record: Mapping, spec, epoch: int) -> dict:
    if (record.get("family") != spec.family or record.get("variant") != spec.variant or
            record.get("seed") != spec.seed):
        raise StateDiagnosticsError(f"training audit identity drift for {spec.run_id}")
    checkpoints = record.get("checkpoints")
    if not isinstance(checkpoints, list) or len(checkpoints) != 3:
        raise StateDiagnosticsError(f"training audit checkpoint coverage drift for {spec.run_id}")
    matches = [entry for entry in checkpoints if isinstance(entry, Mapping) and entry.get("epoch") == epoch]
    if len(matches) != 1:
        raise StateDiagnosticsError(f"training audit checkpoint epoch {epoch} drift for {spec.run_id}")
    entry = dict(matches[0])
    expected_name = f"checkpoint_epoch{epoch:03d}.pt"
    if entry.get("relative_path") != expected_name:
        raise StateDiagnosticsError(f"training audit checkpoint filename drift for {spec.run_id}")
    _require_sha256_v09(entry.get("sha256"), f"checkpoint hash for {spec.run_id} epoch {epoch}")
    if entry.get("eligible_for_formal_prediction") is not (epoch == 30):
        raise StateDiagnosticsError(f"training audit checkpoint eligibility drift for {spec.run_id}")
    if entry.get("not_eligible_for_formal_prediction") is not (epoch != 30):
        raise StateDiagnosticsError(f"training audit intermediate checkpoint eligibility drift for {spec.run_id}")
    return entry


def _finite_checkpoint_tree_v09(value: object, label: str) -> None:
    if isinstance(value, torch.Tensor):
        if not bool(torch.isfinite(value).all()):
            raise StateDiagnosticsError(f"non-finite diagnostic checkpoint tensor: {label}")
        return
    if isinstance(value, Mapping):
        for key, item in value.items():
            _finite_checkpoint_tree_v09(item, f"{label}.{key}")
        return
    if isinstance(value, (list, tuple)):
        for index, item in enumerate(value):
            _finite_checkpoint_tree_v09(item, f"{label}[{index}]")
        return
    if isinstance(value, float) and not np.isfinite(value):
        raise StateDiagnosticsError(f"non-finite diagnostic checkpoint scalar: {label}")


def _load_diagnostic_model_v09(
    checkpoint_path: Path,
    spec,
    epoch: int,
    expected_sha256: str,
    device: str | torch.device,
):
    if sha256_file(checkpoint_path) != expected_sha256:
        raise StateDiagnosticsError(f"diagnostic checkpoint hash drift for {spec.run_id} epoch {epoch}")
    checkpoint = torch.load(checkpoint_path, map_location=device, weights_only=False)
    if (not isinstance(checkpoint, Mapping) or
            checkpoint.get("schema") != "historical_multiscale_formal_v09_run_checkpoint_v1" or
            checkpoint.get("epoch") != epoch):
        raise StateDiagnosticsError(f"diagnostic checkpoint identity drift for {spec.run_id} epoch {epoch}")
    _finite_checkpoint_tree_v09(checkpoint, f"{spec.run_id}.epoch{epoch}")
    model = build_model_v09(spec.variant, spec.seed).to(device)
    trainable_parameters = sum(
        parameter.numel() for parameter in model.parameters() if parameter.requires_grad)
    if trainable_parameters != spec.trainable_parameters:
        raise StateDiagnosticsError(f"diagnostic model parameter count drift for {spec.run_id}")
    try:
        model.load_state_dict(checkpoint["model_state_dict"], strict=True)
    except (KeyError, RuntimeError) as exc:
        raise StateDiagnosticsError(f"diagnostic model state drift for {spec.run_id} epoch {epoch}") from exc
    return model.eval()


def state_norms_for_keys_v09(
    inputs,
    model,
    keys: np.ndarray,
    *,
    device: str | torch.device,
) -> np.ndarray:
    """Compute pre-registered history-state columns for target-free basin/date keys."""
    if hasattr(inputs, "targets"):
        raise StateDiagnosticsError("state diagnostics refuse any input object that exposes training targets")
    if keys.dtype.str != "<i4" or not keys.flags.c_contiguous or keys.ndim != 2 or keys.shape[1] != 2:
        raise StateDiagnosticsError("diagnostic keys must be C-contiguous little-endian int32[samples,2]")
    target_positions = np.searchsorted(inputs.dates, inputs.target_dates)
    if (np.any(target_positions >= len(inputs.dates)) or
            not np.array_equal(inputs.dates[target_positions], inputs.target_dates)):
        raise StateDiagnosticsError("diagnostic target dates are not an exact subset of predictor dates")
    if len(keys) == 0 or int(keys[:, 0].min()) < 0 or int(keys[:, 0].max()) >= len(inputs.basins):
        raise StateDiagnosticsError("diagnostic basin key is outside the frozen input")
    if int(keys[:, 1].min()) < 0 or int(keys[:, 1].max()) >= len(inputs.target_dates):
        raise StateDiagnosticsError("diagnostic date key is outside the frozen training period")
    output = np.empty((len(keys), len(_STATE_COLUMNS)), dtype="<f4")
    for start in range(0, len(keys), 256):
        batch_keys = keys[start:start + 256]
        basin_indices = batch_keys[:, 0].astype(np.int64, copy=False)
        positions = target_positions[batch_keys[:, 1]].astype(np.int64, copy=False)
        windows = gather_causal_windows_v09(inputs.forcing, basin_indices, positions)
        normalized = normalize_forcing_batch_v09(windows, inputs.scaler)
        dynamic = split_windows_v09(torch.from_numpy(normalized).to(device))
        statics = np.ascontiguousarray(inputs.statics[basin_indices], dtype=np.float32)
        states = history_states_v09(model, dynamic["history"], torch.from_numpy(statics).to(device))
        output[start:start + len(batch_keys)] = state_norms_from_states_v09(
            states["raw_hidden"],
            states["raw_cell"],
            states["gated_hidden"],
            states["gated_cell"],
        )
    if not np.isfinite(output).all():
        raise StateDiagnosticsError("state diagnostics produced a non-finite state value")
    return np.ascontiguousarray(output, dtype="<f4")


def _directory_binding_v09(root: Path) -> dict:
    files = []
    for path in sorted(root.rglob("*"), key=lambda value: value.as_posix()):
        if path.is_file():
            files.append({
                "relative_path": path.relative_to(root).as_posix(),
                "size_bytes": path.stat().st_size,
                "sha256": sha256_file(path),
            })
    if not files:
        raise StateDiagnosticsError(f"state diagnostic directory is empty: {root}")
    return {"file_count": len(files), "files_sha256": canonical_sha256(files), "files": files}


def _diagnostic_source_context_v09() -> dict:
    repo_root = IDEA_ROOT.parents[1]
    files = []
    for relative in _DIAGNOSTIC_SOURCE_FILES:
        path = repo_root / relative
        if not path.is_file():
            raise StateDiagnosticsError(f"diagnostic source file is missing: {relative}")
        files.append({
            "relative_path": relative,
            "size_bytes": path.stat().st_size,
            "sha256": sha256_file(path),
        })
    return {
        "schema": "historical_multiscale_formal_v09_state_diagnostic_source_v1",
        "file_count": len(files),
        "files": files,
        "tree_sha256": canonical_sha256(files),
    }


def _run_order_binding_v09(specs: Sequence) -> str:
    values = [
        {
            "position": spec.position,
            "seed": spec.seed,
            "family": spec.family,
            "run_id": spec.run_id,
            "variant": spec.variant,
            "trainable_parameters": spec.trainable_parameters,
            "results_root": spec.results_root,
        }
        for spec in specs
    ]
    return canonical_sha256(values)


def _preregistration_path_v09() -> Path:
    return IDEA_ROOT.parents[1] / "docs/technical/historical_multiscale_formal_v09_state_diagnostics_preregistration.md"


def write_history_state_diagnostics_v09(
    input_root: str | Path,
    formal_root: str | Path,
    run_order,
    output_root: str | Path,
    device: str | torch.device,
    *,
    require_formal_geometry: bool = True,
) -> dict:
    """Write the frozen diagnostics for all eight continuous-history training runs."""
    output_root = Path(os.path.abspath(output_root)).resolve()
    building_root = output_root.with_name(f"{output_root.name}.building")
    if output_root.exists() or building_root.exists():
        raise FileExistsError(f"state diagnostic output already exists: {output_root}")
    formal_root = Path(os.path.abspath(formal_root)).resolve()
    input_root = Path(os.path.abspath(input_root)).resolve()
    if not formal_root.is_dir():
        raise FileNotFoundError(f"formal training root is missing: {formal_root}")
    if output_root != formal_root / "state_diagnostics":
        raise StateDiagnosticsError("state diagnostic output path must be the fixed directory outside all runs")
    specs = _resolve_run_order_v09(run_order)
    continuous = [spec for spec in specs if spec.variant == "continuous_multiscale_history"]
    expected_seeds = list(range(100, 801, 100))
    if len(continuous) != 8 or [spec.seed for spec in continuous] != expected_seeds:
        raise StateDiagnosticsError("state diagnostics require the eight frozen continuous-history runs")
    environment = _deterministic_environment_v09(device)
    environment_sha256 = canonical_sha256(environment)
    diagnostic_source = _diagnostic_source_context_v09()
    diagnostic_source_sha256 = canonical_sha256(diagnostic_source)
    training_audit, audited_runs = _load_training_audit_v09(formal_root)
    input_bindings = training_audit.get("input_bindings")
    if not isinstance(input_bindings, Mapping):
        raise StateDiagnosticsError("training external audit input bindings are missing")
    inputs = _load_diagnostic_inputs_v09(input_root, formal_root)
    actual_input_bindings = {
        "input_seal_sha256": inputs.input_seal_sha256,
        "input_external_audit_sha256": inputs.external_audit_sha256,
        "trusted_source_audit_sha256": inputs.trusted_source_audit_sha256,
    }
    if dict(input_bindings) != actual_input_bindings:
        raise StateDiagnosticsError("state diagnostic input binding differs from the training audit")
    if hasattr(inputs, "targets"):
        raise StateDiagnosticsError("state diagnostic loader exposed the training target array")
    basin_count = len(inputs.basins)
    if require_formal_geometry and basin_count != 531:
        raise StateDiagnosticsError("state diagnostic basin count drift")
    panel_keys = panel_keys_v09(basin_count)
    all_keys = all_training_keys_v09(basin_count)
    if require_formal_geometry and (panel_keys.shape != (6_372, 2) or all_keys.shape != (1_745_928, 2)):
        raise StateDiagnosticsError("state diagnostic key coverage drift")
    verify_sealed_bridge_inputs_unchanged_v09(inputs)
    building_root.mkdir(parents=True, exist_ok=False)
    training_audit_path = formal_root / "training_external_audit.json"
    preregistration = _preregistration_path_v09()
    preregistration_sha256 = sha256_file(preregistration)
    run_order_sha256 = _run_order_binding_v09(specs)
    children = []
    for spec in continuous:
        record = audited_runs.get(spec.run_id)
        if not isinstance(record, Mapping):
            raise StateDiagnosticsError(f"training audit is missing {spec.run_id}")
        checkpoints = {}
        checkpoint_hashes = {}
        run_dir = formal_root / Path(spec.results_root).name / f"seed_{spec.seed}"
        for epoch in _CHECKPOINT_EPOCHS:
            entry = _validate_diagnostic_checkpoint_record_v09(record, spec, epoch)
            checkpoint_path = run_dir / entry["relative_path"]
            model = _load_diagnostic_model_v09(
                checkpoint_path,
                spec,
                epoch,
                entry["sha256"],
                device,
            )
            payload = {
                "panel_keys": panel_keys,
                "panel_states": state_norms_for_keys_v09(inputs, model, panel_keys, device=device),
                "gates": gate_summary_v09(model),
            }
            if epoch == 30:
                payload["all_keys"] = all_keys
                payload["all_states"] = state_norms_for_keys_v09(inputs, model, all_keys, device=device)
            checkpoints[epoch] = payload
            checkpoint_hashes[str(epoch)] = entry["sha256"]
            del model
        provenance = {
            **actual_input_bindings,
            "training_external_audit_sha256": sha256_file(training_audit_path),
            "training_source_context_sha256": _require_sha256_v09(
                training_audit.get("source_context_sha256"), "training source context"),
            "run_order_canonical_sha256": run_order_sha256,
            "state_diagnostics_preregistration_sha256": preregistration_sha256,
            "diagnostic_environment_sha256": environment_sha256,
            "diagnostic_source_tree_sha256": diagnostic_source["tree_sha256"],
            "run_id": spec.run_id,
            "run_seal_sha256": _require_sha256_v09(record.get("run_seal_sha256"), "run seal"),
            "checkpoint_sha256": checkpoint_hashes,
        }
        child_name = f"E09-CONTINUOUS_s{spec.seed}"
        child_root = building_root / child_name
        manifest = write_seed_diagnostics_v09(
            child_root,
            seed=spec.seed,
            checkpoints=checkpoints,
            provenance=provenance,
        )
        binding = _directory_binding_v09(child_root)
        children.append({
            "seed": spec.seed,
            "run_id": spec.run_id,
            "relative_path": child_name,
            "manifest_sha256": sha256_file(child_root / "manifest.json"),
            "directory_file_count": binding["file_count"],
            "directory_files_sha256": binding["files_sha256"],
            "array_count": len(manifest["arrays"]),
            "checkpoint_sha256": checkpoint_hashes,
        })
    verify_sealed_bridge_inputs_unchanged_v09(inputs)
    root_manifest = {
        "schema": "historical_multiscale_formal_v09_state_diagnostics_root_v1",
        "status": "state_diagnostics_complete",
        "seed_count": len(children),
        "seeds": expected_seeds,
        "children": children,
        "input_bindings": actual_input_bindings,
        "training_external_audit_sha256": sha256_file(training_audit_path),
        "training_source_context_sha256": training_audit["source_context_sha256"],
        "run_order_canonical_sha256": run_order_sha256,
        "state_diagnostics_preregistration_sha256": preregistration_sha256,
        "environment": environment,
        "environment_sha256": environment_sha256,
        "diagnostic_source": diagnostic_source,
        "diagnostic_source_sha256": diagnostic_source_sha256,
        "training_target_reads": 0,
        "formal_evaluation_observation_reads": 0,
        "recent_path_executed": False,
        "flow_head_executed": False,
        "formal_period_predictions_generated": False,
        "official_score_called": False,
    }
    write_json_atomic(building_root / "manifest.json", root_manifest)
    promote_directory(building_root, output_root, trusted_root=formal_root)
    return root_manifest


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="write formal version-09 history-state diagnostics")
    parser.add_argument("--input-root", required=True)
    parser.add_argument("--formal-root", required=True)
    parser.add_argument("--run-order", required=True)
    parser.add_argument("--output-root", required=True)
    parser.add_argument("--device", default="cuda:0")
    args = parser.parse_args(argv)
    report = write_history_state_diagnostics_v09(
        args.input_root,
        args.formal_root,
        args.run_order,
        args.output_root,
        args.device,
    )
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

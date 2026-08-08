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
import hashlib
import json
import os
from pathlib import Path

import numpy as np
import torch

IDEA_ROOT = Path(__file__).resolve().parent
import sys

if str(IDEA_ROOT) not in sys.path:
    sys.path.insert(0, str(IDEA_ROOT))

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
    from artifact_v09 import write_json_atomic

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

"""Formal version-09 evaluation-period predictions from the 24 sealed final checkpoints.

This process runs *after* the 24-run training audit and both state-diagnostic processes.
It loads only sealed predictors through the bridge loader, which cannot expose training
targets by construction, and it never opens formal evaluation observations, never calls a
scoring service, and never writes into a sealed run directory.

Scope note. This module produces predictions only. Whether those predictions are then
scored diagnostically or submitted through the one-call clean-pair route is a separate,
separately authorized decision; nothing here consumes a one-time authorization, draws the
post-seal holdout nonce, or appends to the score ledger.
"""
from __future__ import annotations

from collections.abc import Mapping, Sequence
import argparse
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

_FINAL_EPOCH = 30
_BATCH_ROWS = 256
_WINDOW_DAYS = 3_562
_RECENT_DAYS = 270
_EVALUATION_START = np.datetime64("1989-10-01", "D")
_EVALUATION_END = np.datetime64("1999-09-30", "D")
_EVALUATION_DAYS = 3_652
_EVALUATION_START_INDEX = 3_561
_BASIN_COUNT = 531
_FAMILIES = ("B09-CLASSIC", "B09-CAPACITY", "E09-CONTINUOUS")
_RECENT_ONLY_VARIANTS = ("classic_lstm_256_clean", "classic_lstm_369_capacity")
_HISTORY_VARIANT = "continuous_multiscale_history"
_CSV_HEADER = "basin,date,qsim\n"
_QSIM_FORMAT = "%.17g"
_PREDICTION_SOURCE_FILES = (
    "src/26_historical_band_experts/artifact_v09.py",
    "src/26_historical_band_experts/bands_formal_v09.py",
    "src/26_historical_band_experts/formal_training_data_v09.py",
    "src/26_historical_band_experts/models_formal_v09.py",
    "src/26_historical_band_experts/models_v03.py",
    "src/26_historical_band_experts/predict_formal_v09.py",
    "src/26_historical_band_experts/train_formal_v09.py",
    "src/26_historical_band_experts/configs/formal_v09_protocol.json",
    "src/26_historical_band_experts/configs/formal_v09_run_order.json",
)


class FormalPredictionError(RuntimeError):
    """Raised when formal predictions cannot be produced exactly as specified."""


def evaluation_start_index_v09(dates: np.ndarray, *, require_formal_geometry: bool = True) -> int:
    """Locate 1989-10-01 in the sealed predictor dates and check the causal window fits."""
    position = int(np.searchsorted(dates, _EVALUATION_START))
    if position >= len(dates) or dates[position] != _EVALUATION_START:
        raise FormalPredictionError("the evaluation start date is absent from the sealed predictor dates")
    if position < _WINDOW_DAYS - 1:
        raise FormalPredictionError(
            f"the causal window needs {_WINDOW_DAYS - 1} prior days but only {position} exist")
    last = position + _EVALUATION_DAYS - 1
    if last >= len(dates) or dates[last] != _EVALUATION_END:
        raise FormalPredictionError("the evaluation period is not a contiguous 3,652-day span of predictor dates")
    if require_formal_geometry and position != _EVALUATION_START_INDEX:
        raise FormalPredictionError(
            f"evaluation start index drift: {position} != {_EVALUATION_START_INDEX}")
    return position


def evaluation_keys_v09(basin_count: int, evaluation_days: int = _EVALUATION_DAYS) -> np.ndarray:
    """Basin-major keys: frozen basin order first, then evaluation day offset ascending."""
    offsets = np.arange(int(evaluation_days), dtype=np.int64)
    basins = np.repeat(np.arange(int(basin_count), dtype=np.int64), len(offsets))
    tiled = np.tile(offsets, int(basin_count))
    return np.ascontiguousarray(np.stack((basins, tiled), axis=1).astype(np.int32))


def _recent_from_windows_v09(windows: torch.Tensor) -> torch.Tensor:
    """Slice the recent path exactly as ``split_windows_v09`` does, without history pooling.

    The recent tensor is a pure trailing slice and does not depend on the history prefix
    sums, so skipping the 120-bin pooling for recent-only variants is numerically identical
    while avoiding 3,562 sequential CUDA reductions per batch.
    """
    if windows.ndim != 3 or tuple(windows.shape[1:]) != (_WINDOW_DAYS, 5):
        raise FormalPredictionError("windows must have shape [batch,3562,5]")
    if windows.shape[0] == 0 or windows.shape[0] > _BATCH_ROWS:
        raise FormalPredictionError("one version 09 window batch must contain from 1 through 256 samples")
    return windows[:, -_RECENT_DAYS:]


def denormalize_prediction_v09(prediction: torch.Tensor, scaler: Mapping) -> np.ndarray:
    """Invert the frozen global target normalization in float64."""
    center = float(scaler["target_center_float64"])
    scale = float(scaler["target_scale_float64"])
    if not np.isfinite(scale) or scale <= 0:
        raise FormalPredictionError("invalid target scale")
    values = prediction.detach().to(torch.float64).cpu().numpy()
    if values.ndim != 1:
        raise FormalPredictionError("model prediction must be one-dimensional")
    return np.ascontiguousarray(values * scale + center, dtype=np.float64)


def predict_evaluation_period_v09(
    inputs,
    model: torch.nn.Module,
    variant: str,
    keys: np.ndarray,
    start_index: int,
    *,
    device: str | torch.device,
) -> np.ndarray:
    """Run one final checkpoint over every evaluation key; observations are never opened."""
    if hasattr(inputs, "targets"):
        raise FormalPredictionError("formal prediction refuses any input object that exposes training targets")
    if keys.dtype.str != "<i4" or not keys.flags.c_contiguous or keys.ndim != 2 or keys.shape[1] != 2:
        raise FormalPredictionError("prediction keys must be C-contiguous little-endian int32[samples,2]")
    if len(keys) == 0 or int(keys[:, 0].min()) < 0 or int(keys[:, 0].max()) >= len(inputs.basins):
        raise FormalPredictionError("prediction basin key is outside the frozen input")
    if int(keys[:, 1].min()) < 0 or int(keys[:, 1].max()) >= _EVALUATION_DAYS:
        raise FormalPredictionError("prediction date key is outside the frozen evaluation period")
    needs_history = variant == _HISTORY_VARIANT
    if not needs_history and variant not in _RECENT_ONLY_VARIANTS:
        raise FormalPredictionError(f"unknown formal version 09 variant: {variant}")
    output = np.empty(len(keys), dtype=np.float64)
    with torch.no_grad():
        for start in range(0, len(keys), _BATCH_ROWS):
            batch_keys = keys[start:start + _BATCH_ROWS]
            basin_indices = batch_keys[:, 0].astype(np.int64, copy=False)
            positions = batch_keys[:, 1].astype(np.int64, copy=False) + int(start_index)
            windows = gather_causal_windows_v09(inputs.forcing, basin_indices, positions)
            normalized = normalize_forcing_batch_v09(windows, inputs.scaler)
            tensor = torch.from_numpy(normalized).to(device)
            statics = np.ascontiguousarray(inputs.statics[basin_indices], dtype=np.float32)
            static_tensor = torch.from_numpy(statics).to(device)
            if needs_history:
                dynamic = split_windows_v09(tensor)
                result = model(dynamic, static_tensor, history_mode="normal")
            else:
                dynamic = {"recent": _recent_from_windows_v09(tensor)}
                result = model(dynamic, static_tensor)
            output[start:start + len(batch_keys)] = denormalize_prediction_v09(result.prediction, inputs.scaler)
    if not np.isfinite(output).all():
        raise FormalPredictionError("formal prediction produced a non-finite streamflow value")
    return output


def _load_json_v09(path: Path) -> dict:
    def reject_constant(value: str):
        raise FormalPredictionError(f"non-finite JSON constant is forbidden: {value}")

    try:
        value = json.loads(path.read_text(encoding="utf-8"), parse_constant=reject_constant)
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise FormalPredictionError(f"invalid formal prediction dependency: {path}") from exc
    if not isinstance(value, dict):
        raise FormalPredictionError(f"formal prediction dependency must be a JSON object: {path}")
    return value


def _require_sha256_v09(value: object, label: str) -> str:
    if (not isinstance(value, str) or len(value) != 64 or
            any(character not in "0123456789abcdef" for character in value)):
        raise FormalPredictionError(f"{label} is not a lowercase SHA-256 digest")
    return value


def _load_training_audit_v09(formal_root: Path) -> tuple[dict, dict[str, dict]]:
    path = formal_root / "training_external_audit.json"
    report = _load_json_v09(path)
    if (report.get("schema") != "historical_multiscale_formal_v09_training_external_audit_v1" or
            report.get("status") != "complete_training_audit"):
        raise FormalPredictionError("training external audit schema or status drift")
    if report.get("coverage") != {"expected_runs": 24, "audited_runs": 24, "passed_runs": 24}:
        raise FormalPredictionError("training external audit run coverage drift")
    if report.get("formal_evaluation_observation_reads") != 0 or report.get("official_score_called") is not False:
        raise FormalPredictionError("training external audit contains premature scoring activity")
    runs = report.get("runs")
    if not isinstance(runs, list) or len(runs) != 24:
        raise FormalPredictionError("training external audit run records are incomplete")
    by_id = {row.get("run_id"): row for row in runs if isinstance(row, Mapping)}
    if len(by_id) != 24 or None in by_id:
        raise FormalPredictionError("training external audit run identifiers are duplicated")
    return report, by_id


def _final_checkpoint_record_v09(record: Mapping, spec) -> dict:
    if (record.get("family") != spec.family or record.get("variant") != spec.variant or
            record.get("seed") != spec.seed):
        raise FormalPredictionError(f"training audit identity drift for {spec.run_id}")
    checkpoints = record.get("checkpoints")
    if not isinstance(checkpoints, list) or len(checkpoints) != 3:
        raise FormalPredictionError(f"training audit checkpoint coverage drift for {spec.run_id}")
    matches = [entry for entry in checkpoints if isinstance(entry, Mapping) and entry.get("epoch") == _FINAL_EPOCH]
    if len(matches) != 1:
        raise FormalPredictionError(f"training audit final checkpoint drift for {spec.run_id}")
    entry = dict(matches[0])
    if entry.get("relative_path") != f"checkpoint_epoch{_FINAL_EPOCH:03d}.pt":
        raise FormalPredictionError(f"training audit checkpoint filename drift for {spec.run_id}")
    if entry.get("eligible_for_formal_prediction") is not True:
        raise FormalPredictionError(f"final checkpoint is not eligible for formal prediction: {spec.run_id}")
    _require_sha256_v09(entry.get("sha256"), f"final checkpoint hash for {spec.run_id}")
    return entry


def _finite_checkpoint_tree_v09(value: object, label: str) -> None:
    if isinstance(value, torch.Tensor):
        if not bool(torch.isfinite(value).all()):
            raise FormalPredictionError(f"non-finite prediction checkpoint tensor: {label}")
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
        raise FormalPredictionError(f"non-finite prediction checkpoint scalar: {label}")


def _load_final_model_v09(checkpoint_path: Path, spec, expected_sha256: str, device: str | torch.device):
    if sha256_file(checkpoint_path) != expected_sha256:
        raise FormalPredictionError(f"final checkpoint hash drift for {spec.run_id}")
    checkpoint = torch.load(checkpoint_path, map_location=device, weights_only=False)
    if (not isinstance(checkpoint, Mapping) or
            checkpoint.get("schema") != "historical_multiscale_formal_v09_run_checkpoint_v1" or
            checkpoint.get("epoch") != _FINAL_EPOCH):
        raise FormalPredictionError(f"final checkpoint identity drift for {spec.run_id}")
    _finite_checkpoint_tree_v09(checkpoint, f"{spec.run_id}.epoch{_FINAL_EPOCH}")
    model = build_model_v09(spec.variant, spec.seed).to(device)
    trainable = sum(parameter.numel() for parameter in model.parameters() if parameter.requires_grad)
    if trainable != spec.trainable_parameters:
        raise FormalPredictionError(f"prediction model parameter count drift for {spec.run_id}")
    try:
        model.load_state_dict(checkpoint["model_state_dict"], strict=True)
    except (KeyError, RuntimeError) as exc:
        raise FormalPredictionError(f"prediction model state drift for {spec.run_id}") from exc
    return model.eval()


def _deterministic_environment_v09(device: str | torch.device) -> dict:
    torch_device = torch.device(device)
    device_name = None
    device_capability = None
    device_total_memory_bytes = None
    driver_version = None
    if torch_device.type == "cuda":
        if os.environ.get("CUBLAS_WORKSPACE_CONFIG") != ":4096:8":
            raise FormalPredictionError("CUBLAS_WORKSPACE_CONFIG must be set before the CUDA process starts")
        if not torch.cuda.is_available():
            raise FormalPredictionError("the registered CUDA device is unavailable")
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
            raise FormalPredictionError("NVIDIA driver version cannot be recorded unambiguously")
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


def _prediction_source_context_v09() -> dict:
    repo_root = IDEA_ROOT.parents[1]
    files = []
    for relative in _PREDICTION_SOURCE_FILES:
        path = repo_root / relative
        if not path.is_file():
            raise FormalPredictionError(f"prediction source file is missing: {relative}")
        files.append({
            "relative_path": relative,
            "size_bytes": path.stat().st_size,
            "sha256": sha256_file(path),
        })
    return {
        "schema": "historical_multiscale_formal_v09_prediction_source_v1",
        "file_count": len(files),
        "files": files,
        "tree_sha256": canonical_sha256(files),
    }


def _run_order_binding_v09(specs: Sequence) -> str:
    values = [{
        "position": spec.position,
        "seed": spec.seed,
        "family": spec.family,
        "run_id": spec.run_id,
        "variant": spec.variant,
        "trainable_parameters": spec.trainable_parameters,
        "results_root": spec.results_root,
    } for spec in specs]
    return canonical_sha256(values)


def write_prediction_csv_v09(path: Path, basins: Sequence[str], dates: np.ndarray, values: np.ndarray) -> dict:
    """Write one basin-major ``basin,date,qsim`` file and return its binding record."""
    if path.exists():
        raise FileExistsError(f"prediction file already exists: {path}")
    if values.ndim != 1 or values.dtype != np.float64:
        raise FormalPredictionError("prediction values must be a one-dimensional float64 array")
    if len(values) != len(basins) * len(dates):
        raise FormalPredictionError("prediction row count drift")
    date_text = np.datetime_as_string(dates, unit="D")
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="\n") as handle:
        handle.write(_CSV_HEADER)
        for basin_index, basin in enumerate(basins):
            offset = basin_index * len(dates)
            block = values[offset:offset + len(dates)]
            handle.writelines(
                f"{basin},{date_text[day]},{_QSIM_FORMAT % block[day]}\n" for day in range(len(dates)))
    return {
        "relative_path": path.name,
        "rows": int(len(values)),
        "sha256": sha256_file(path),
        "size_bytes": path.stat().st_size,
    }


def compose_family_ensemble_v09(members: Mapping[int, np.ndarray]) -> np.ndarray:
    """Average the eight seeds of one family in float64, in ascending seed order."""
    seeds = sorted(int(seed) for seed in members)
    if seeds != list(range(100, 801, 100)):
        raise FormalPredictionError("an ensemble needs exactly the eight frozen seeds")
    accumulator = np.zeros_like(members[seeds[0]], dtype=np.float64)
    for seed in seeds:
        member = members[seed]
        if member.shape != accumulator.shape or member.dtype != np.float64:
            raise FormalPredictionError("ensemble member geometry or dtype drift")
        accumulator += member
    accumulator /= float(len(seeds))
    if not np.isfinite(accumulator).all():
        raise FormalPredictionError("ensemble composition produced a non-finite value")
    return np.ascontiguousarray(accumulator, dtype=np.float64)


def write_formal_predictions_v09(
    input_root: str | Path,
    formal_root: str | Path,
    run_order,
    output_root: str | Path,
    device: str | torch.device,
    *,
    require_formal_geometry: bool = True,
) -> dict:
    """Produce all 24 seed predictions and the three family ensembles for the evaluation period."""
    output_root = Path(os.path.abspath(output_root)).resolve()
    building_root = output_root.with_name(f"{output_root.name}.building")
    if output_root.exists() or building_root.exists():
        raise FileExistsError(f"formal prediction output already exists: {output_root}")
    formal_root = Path(os.path.abspath(formal_root)).resolve()
    input_root = Path(os.path.abspath(input_root)).resolve()
    if not formal_root.is_dir():
        raise FileNotFoundError(f"formal training root is missing: {formal_root}")
    if output_root != formal_root / "predictions":
        raise FormalPredictionError("prediction output path must be the fixed directory outside all runs")
    specs = load_run_order_v09(run_order) if isinstance(run_order, (str, Path)) else tuple(run_order)
    if len(specs) != 24:
        raise FormalPredictionError("formal prediction requires exactly the 24 frozen runs")
    environment = _deterministic_environment_v09(device)
    environment_sha256 = canonical_sha256(environment)
    prediction_source = _prediction_source_context_v09()
    training_audit, audited_runs = _load_training_audit_v09(formal_root)
    input_bindings = training_audit.get("input_bindings")
    if not isinstance(input_bindings, Mapping):
        raise FormalPredictionError("training external audit input bindings are missing")

    repo_root = formal_root.parents[2]
    inputs = load_sealed_bridge_inputs_v09(
        input_root,
        repo_root / "src/26_historical_band_experts/configs/formal_v09_protocol.json",
        worktree_root=repo_root,
        external_audit_path=formal_root / "input_attempt_01.external_audit.json",
        trusted_source_audit_path=formal_root / "input_attempt_01.trusted_source_external_audit.json",
    )
    actual_input_bindings = {
        "input_seal_sha256": inputs.input_seal_sha256,
        "input_external_audit_sha256": inputs.external_audit_sha256,
        "trusted_source_audit_sha256": inputs.trusted_source_audit_sha256,
    }
    if dict(input_bindings) != actual_input_bindings:
        raise FormalPredictionError("prediction input binding differs from the training audit")
    if hasattr(inputs, "targets"):
        raise FormalPredictionError("prediction loader exposed the training target array")

    basin_count = len(inputs.basins)
    if require_formal_geometry and basin_count != _BASIN_COUNT:
        raise FormalPredictionError("prediction basin count drift")
    start_index = evaluation_start_index_v09(inputs.dates, require_formal_geometry=require_formal_geometry)
    evaluation_dates = np.asarray(inputs.dates[start_index:start_index + _EVALUATION_DAYS])
    keys = evaluation_keys_v09(basin_count)
    expected_rows = basin_count * _EVALUATION_DAYS
    if len(keys) != expected_rows:
        raise FormalPredictionError("prediction key coverage drift")
    verify_sealed_bridge_inputs_unchanged_v09(inputs)

    building_root.mkdir(parents=True, exist_ok=False)
    seed_dir = building_root / "seeds"
    ensemble_dir = building_root / "ensembles"
    seed_dir.mkdir(parents=True, exist_ok=False)
    ensemble_dir.mkdir(parents=True, exist_ok=False)

    by_family: dict[str, dict[int, np.ndarray]] = {family: {} for family in _FAMILIES}
    seed_records = []
    for spec in specs:
        record = audited_runs.get(spec.run_id)
        if not isinstance(record, Mapping):
            raise FormalPredictionError(f"training audit is missing {spec.run_id}")
        entry = _final_checkpoint_record_v09(record, spec)
        run_dir = formal_root / Path(spec.results_root).name / f"seed_{spec.seed}"
        model = _load_final_model_v09(run_dir / entry["relative_path"], spec, entry["sha256"], device)
        values = predict_evaluation_period_v09(
            inputs, model, spec.variant, keys, start_index, device=device)
        del model
        if spec.family not in by_family:
            raise FormalPredictionError(f"unknown family in the frozen run order: {spec.family}")
        by_family[spec.family][int(spec.seed)] = values
        binding = write_prediction_csv_v09(
            seed_dir / f"{spec.run_id}.csv", inputs.basins, evaluation_dates, values)
        seed_records.append({
            "position": spec.position,
            "run_id": spec.run_id,
            "family": spec.family,
            "variant": spec.variant,
            "seed": spec.seed,
            "checkpoint_sha256": entry["sha256"],
            "run_seal_sha256": _require_sha256_v09(record.get("run_seal_sha256"), "run seal"),
            **binding,
        })

    ensemble_records = []
    for family in _FAMILIES:
        members = by_family[family]
        if require_formal_geometry and len(members) != 8:
            raise FormalPredictionError(f"family {family} does not have the eight frozen seeds")
        ensemble = compose_family_ensemble_v09(members)
        binding = write_prediction_csv_v09(
            ensemble_dir / f"{family}_ensemble.csv", inputs.basins, evaluation_dates, ensemble)
        ensemble_records.append({
            "family": family,
            "seed_count": len(members),
            "operation": "float64_arithmetic_mean",
            "seed_order": sorted(int(seed) for seed in members),
            **binding,
        })

    verify_sealed_bridge_inputs_unchanged_v09(inputs)
    manifest = {
        "schema": "historical_multiscale_formal_v09_predictions_root_v1",
        "status": "formal_predictions_complete",
        "evaluation_period": {
            "start_date": str(_EVALUATION_START),
            "end_date": str(_EVALUATION_END),
            "dates_per_basin": _EVALUATION_DAYS,
            "start_index_in_sealed_dates": int(start_index),
            "basin_count": basin_count,
            "rows_per_file": expected_rows,
        },
        "seed_predictions": seed_records,
        "ensembles": ensemble_records,
        "input_bindings": actual_input_bindings,
        "training_external_audit_sha256": sha256_file(formal_root / "training_external_audit.json"),
        "training_source_context_sha256": training_audit["source_context_sha256"],
        "run_order_canonical_sha256": _run_order_binding_v09(specs),
        "environment": environment,
        "environment_sha256": environment_sha256,
        "prediction_source": prediction_source,
        "prediction_source_sha256": canonical_sha256(prediction_source),
        "target_denormalization": {
            "center": float(inputs.scaler["target_center_float64"]),
            "scale": float(inputs.scaler["target_scale_float64"]),
            "applied_in": "float64",
        },
        "training_target_reads": 0,
        "formal_evaluation_observation_reads": 0,
        "official_score_called": False,
        "holdout_nonce_drawn": False,
        "score_ledger_appended": False,
    }
    write_json_atomic(building_root / "manifest.json", manifest)
    promote_directory(building_root, output_root, trusted_root=formal_root)
    return manifest


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="write formal version-09 evaluation-period predictions")
    parser.add_argument("--input-root", required=True)
    parser.add_argument("--formal-root", required=True)
    parser.add_argument("--run-order", required=True)
    parser.add_argument("--output-root", required=True)
    parser.add_argument("--device", default="cuda:0")
    args = parser.parse_args(argv)
    report = write_formal_predictions_v09(
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

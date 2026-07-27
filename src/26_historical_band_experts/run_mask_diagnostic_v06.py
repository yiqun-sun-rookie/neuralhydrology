"""Read-only evaluation of all seven nonempty masks for the frozen version 05 checkpoint."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
from typing import Mapping

import numpy as np
import pandas as pd
import torch

from data import (
    DataPack,
    load_basin_ids,
    load_data_pack,
    normalize_pack,
    split_target_indices,
)
from diagnostics_v06 import (
    BRANCH_COMBINATIONS,
    capture_fused_features,
    masked_predictions_from_fused,
)
from metrics import per_basin_nse
from models_v05 import build_model_v05
from train_v05 import _limited_balanced_indices, dynamic_batch_v05, validate_frozen_file_hash


_REPO = Path(__file__).resolve().parents[2]
_BASIN_SHA256 = "3160dad3b22200fdb596164c9f69e4fbe19cc156cfad768beb193efea7b26b65"
_TARGET_SHA256 = "d4c93675eefd433515d6f7e10943caea31c6eb7e30533d4c387cf9325886e05c"
_FORBIDDEN_TOKENS = ("usgs_streamflow", "camels_hydro", "_obs_eval.parquet")
_EXPECTED_PARAMETER_COUNT = 455_105


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _atomic_text(path: Path, content: str) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(content, encoding="utf-8")
    os.replace(temporary, path)


def _atomic_frame(path: Path, frame: pd.DataFrame) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    frame.to_csv(temporary, index=False)
    os.replace(temporary, path)


def _validate_hex(config: Mapping, key: str) -> None:
    value = config.get(key)
    if not isinstance(value, str) or len(value) != 64:
        raise ValueError(f"{key} must be a 64-character hexadecimal binding")
    try:
        int(value, 16)
    except ValueError as error:
        raise ValueError(f"{key} must be a 64-character hexadecimal binding") from error


def validate_mask_config_v06(config: Mapping) -> None:
    """Reject input, date, identity, or output drift for the version 06 diagnostic."""
    expected = {
        "experiment_id": "D06-MASK",
        "experiment_family": "strict_branch_masking_v06",
        "basin_file_sha256": _BASIN_SHA256,
        "target_bundle_sha256": _TARGET_SHA256,
        "validation_start": "2006-10-01",
        "validation_end": "2008-09-30",
        "source_variant": "hierarchical_rich_history",
        "source_seed": 100,
        "formal_evaluation_access": False,
    }
    for key, value in expected.items():
        if config.get(key) != value:
            raise ValueError(f"{key} must be frozen at {value!r}, got {config.get(key)!r}")
    for key in ("source_checkpoint_sha256", "source_predictions_sha256"):
        _validate_hex(config, key)
    if int(config.get("validation_batch_size", 0)) <= 0:
        raise ValueError("validation_batch_size must be positive")
    mode = config.get("mode")
    limit = int(config.get("limit_validation_samples", 0))
    if mode == "pilot":
        if limit != 0:
            raise ValueError("limit_validation_samples must be zero in pilot mode")
    elif mode == "smoke":
        if limit <= 0:
            raise ValueError("limit_validation_samples must be positive in smoke mode")
    else:
        raise ValueError("mode must be 'pilot' or 'smoke'")
    serialized = json.dumps(config, sort_keys=True).lower()
    if any(token in serialized for token in _FORBIDDEN_TOKENS):
        raise ValueError("forbidden input path or filename in diagnostic configuration")
    results_root = str(config.get("results_root", ""))
    if not results_root:
        raise ValueError("results_root must be nonempty")
    if any(f"_v0{version}" in results_root for version in (3, 4, 5)):
        raise ValueError("results_root must not reuse a version 03, 04, or 05 output root")


def _validate_source_run(config: Mapping, source_run: Path) -> tuple[dict, pd.DataFrame]:
    manifest_path = source_run / "manifest.json"
    checkpoint_path = source_run / "checkpoint.pt"
    predictions_path = source_run / "predictions.csv"
    if not manifest_path.exists() or not checkpoint_path.exists() or not predictions_path.exists():
        raise FileNotFoundError("source run is missing its manifest, checkpoint, or predictions")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("status") != "complete":
        raise ValueError("source run is not complete")
    if manifest.get("variant") != config["source_variant"]:
        raise ValueError("source variant does not match the frozen configuration")
    if int(manifest.get("seed", -1)) != int(config["source_seed"]):
        raise ValueError("source seed does not match the frozen configuration")
    if int(manifest.get("parameter_count", -1)) != _EXPECTED_PARAMETER_COUNT:
        raise ValueError("source parameter count is not 455105")
    if manifest.get("data_access", {}).get("raw_observed_discharge_reads") != 0:
        raise ValueError("source manifest records a raw observed-discharge read")
    actual_checkpoint = _sha256(checkpoint_path)
    if actual_checkpoint != config["source_checkpoint_sha256"]:
        raise ValueError(
            "checkpoint SHA-256 mismatch: "
            f"expected {config['source_checkpoint_sha256']}, got {actual_checkpoint}"
        )
    actual_predictions = _sha256(predictions_path)
    if actual_predictions != config["source_predictions_sha256"]:
        raise ValueError(
            "predictions SHA-256 mismatch: "
            f"expected {config['source_predictions_sha256']}, got {actual_predictions}"
        )
    for name, actual in (
        ("checkpoint.pt", actual_checkpoint),
        ("predictions.csv", actual_predictions),
    ):
        recorded = manifest.get("artifacts", {}).get(name)
        if recorded != actual:
            raise ValueError(f"source manifest artifact hash mismatch for {name}")
    predictions = pd.read_csv(predictions_path, dtype={"basin": str})
    return manifest, predictions


def _combination_label(combination: tuple[str, ...]) -> str:
    return "_".join(combination)


def _metrics_from_wide(predictions: pd.DataFrame) -> pd.DataFrame:
    rows = []
    key_columns = ["basin", "date", "qobs"]
    for combination in BRANCH_COMBINATIONS:
        label = _combination_label(combination)
        narrow = predictions[key_columns + [f"qsim_{label}"]].rename(
            columns={f"qsim_{label}": "qsim"}
        )
        metrics = per_basin_nse(narrow)
        metrics.insert(0, "combination", label)
        rows.append(metrics)
    return pd.concat(rows, ignore_index=True)


def run_mask_diagnostic_v06(
    pack: DataPack,
    config: Mapping,
    source_run: str | Path,
    output_dir: str | Path,
    device: str,
) -> dict:
    """Evaluate all masks without updating the frozen model."""
    validate_mask_config_v06(config)
    source_run = Path(source_run)
    output_dir = Path(output_dir)
    _source_manifest, source_predictions = _validate_source_run(config, source_run)
    if output_dir.exists() and any(output_dir.iterdir()):
        raise FileExistsError(f"output directory is not empty: {output_dir}")

    checkpoint = torch.load(
        source_run / "checkpoint.pt",
        map_location=torch.device(device),
        weights_only=False,
    )
    if checkpoint.get("variant") != config["source_variant"]:
        raise ValueError("checkpoint variant does not match the frozen configuration")
    if int(checkpoint.get("seed", -1)) != int(config["source_seed"]):
        raise ValueError("checkpoint seed does not match the frozen configuration")
    if int(checkpoint.get("parameter_count", -1)) != _EXPECTED_PARAMETER_COUNT:
        raise ValueError("checkpoint parameter count is not 455105")
    scaler = checkpoint.get("scaler")
    if not isinstance(scaler, Mapping):
        raise ValueError("checkpoint does not contain its saved scaler")

    torch_device = torch.device(device)
    model = build_model_v05(config["source_variant"], seed=int(config["source_seed"]))
    model.load_state_dict(checkpoint["model_state_dict"], strict=True)
    model = model.to(torch_device).eval()
    normalized = normalize_pack(pack, scaler)
    forcing = torch.tensor(normalized.forcing, device=torch_device)
    statics = torch.tensor(normalized.statics, device=torch_device)
    validation_basins, validation_times = split_target_indices(
        pack.dates,
        pack.discharge,
        split="validation",
    )
    validation_basins, validation_times = _limited_balanced_indices(
        validation_basins,
        validation_times,
        int(config.get("limit_validation_samples", 0)),
    )

    parts = []
    batch_size = int(config["validation_batch_size"])
    with torch.no_grad():
        for start in range(0, len(validation_basins), batch_size):
            basin_numpy = validation_basins[start:start + batch_size]
            target_numpy = validation_times[start:start + batch_size]
            basin_index = torch.tensor(basin_numpy, device=torch_device)
            target_index = torch.tensor(target_numpy, device=torch_device)
            dynamic = dynamic_batch_v05(
                config["source_variant"],
                forcing,
                basin_index,
                target_index,
            )
            original, fused = capture_fused_features(model, dynamic, statics[basin_index])
            masked = masked_predictions_from_fused(model, fused)
            if not torch.equal(masked[("recent", "medium", "old")], original):
                raise RuntimeError("all-branch mask does not exactly reproduce the model forward")
            frame = pd.DataFrame({
                "basin": [pack.basins[index] for index in basin_numpy],
                "date": pack.dates[target_numpy].strftime("%Y-%m-%d"),
                "qobs": pack.discharge[basin_numpy, target_numpy],
            })
            for combination, prediction in masked.items():
                label = _combination_label(combination)
                frame[f"qsim_{label}"] = (
                    prediction.detach().cpu().numpy() * float(scaler["q_scale"])
                    + float(scaler["q_center"])
                )
            parts.append(frame)

    predictions = pd.concat(parts, ignore_index=True)
    predictions["basin"] = predictions["basin"].astype(str).str.zfill(8)
    predictions = predictions.sort_values(["basin", "date"]).reset_index(drop=True)
    expected_rows = 43_860 if config["mode"] == "pilot" else int(config["limit_validation_samples"])
    if len(predictions) != expected_rows:
        raise ValueError(f"validation prediction count must be {expected_rows}, got {len(predictions)}")
    if not np.isfinite(predictions.select_dtypes(include=[np.number]).to_numpy()).all():
        raise ValueError("mask predictions contain non-finite values")

    source_predictions["basin"] = source_predictions["basin"].astype(str).str.zfill(8)
    source_predictions = source_predictions.sort_values(["basin", "date"]).reset_index(drop=True)
    if not predictions[["basin", "date"]].equals(source_predictions[["basin", "date"]]):
        raise ValueError("source and reconstructed prediction keys differ")
    if not np.array_equal(
        predictions["qobs"].to_numpy(dtype=np.float32),
        source_predictions["qobs"].to_numpy(dtype=np.float32),
    ):
        raise ValueError("source and reconstructed observed targets differ")
    full_column = "qsim_recent_medium_old"
    if not np.array_equal(
        predictions[full_column].to_numpy(dtype=np.float32),
        source_predictions["qsim"].to_numpy(dtype=np.float32),
    ):
        difference = np.max(np.abs(
            predictions[full_column].to_numpy(dtype=np.float64)
            - source_predictions["qsim"].to_numpy(dtype=np.float64)
        ))
        raise ValueError(f"all-branch predictions do not exactly match source; max abs {difference}")

    output_dir.mkdir(parents=True, exist_ok=True)
    _atomic_text(output_dir / "config.json", json.dumps(dict(config), indent=2, sort_keys=True))
    _atomic_frame(output_dir / "predictions.csv", predictions)
    reloaded_predictions = pd.read_csv(output_dir / "predictions.csv", dtype={"basin": str})
    metrics = _metrics_from_wide(reloaded_predictions)
    if not np.isfinite(metrics["nse"].to_numpy(dtype=np.float64)).all():
        raise ValueError("mask metrics contain non-finite values")
    summary = {
        "status": "complete",
        "n_validation_predictions": int(len(predictions)),
        "all_branch_exact_match": True,
        "median_nse": {
            label: float(np.median(group["nse"].to_numpy(dtype=np.float64)))
            for label, group in metrics.groupby("combination", sort=True)
        },
    }

    _atomic_frame(output_dir / "per_basin_metrics.csv", metrics)
    _atomic_text(output_dir / "summary.json", json.dumps(summary, indent=2, sort_keys=True))
    artifact_names = ("config.json", "predictions.csv", "per_basin_metrics.csv", "summary.json")
    manifest = {
        **summary,
        "experiment_id": config["experiment_id"],
        "experiment_family": config["experiment_family"],
        "source_checkpoint_sha256": config["source_checkpoint_sha256"],
        "source_predictions_sha256": config["source_predictions_sha256"],
        "scaler_source": "checkpoint.pt",
        "device": str(torch_device),
        "environment": {
            "torch": torch.__version__,
            "cuda_runtime": torch.version.cuda,
            "cudnn": torch.backends.cudnn.version(),
            "gpu": torch.cuda.get_device_name(torch_device) if torch_device.type == "cuda" else None,
            "deterministic_algorithms": torch.are_deterministic_algorithms_enabled(),
            "cudnn_deterministic": torch.backends.cudnn.deterministic,
            "cudnn_benchmark": torch.backends.cudnn.benchmark,
        },
        "data_access": {
            "raw_observed_discharge_reads": 0,
            "target_bundle_interface": True,
            "formal_evaluation_access": False,
        },
        "artifacts": {
            name: _sha256(output_dir / name)
            for name in artifact_names
        },
    }
    _atomic_text(output_dir / "manifest.json", json.dumps(manifest, indent=2, sort_keys=True))
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--data-dir", type=Path, required=True)
    parser.add_argument("--targets-file", type=Path, required=True)
    parser.add_argument("--targets-sha256", required=True)
    parser.add_argument("--device", default="cpu")
    args = parser.parse_args()

    config = json.loads(args.config.read_text(encoding="utf-8"))
    validate_mask_config_v06(config)
    if args.targets_sha256.lower() != config["target_bundle_sha256"].lower():
        raise ValueError("command target SHA-256 does not match the frozen configuration")
    basin_file = _REPO / config["basin_file"]
    validate_frozen_file_hash(basin_file, config["basin_file_sha256"], "basin list")
    basins = load_basin_ids(basin_file)
    pack = load_data_pack(
        args.data_dir,
        basins,
        targets_file=args.targets_file,
        expected_targets_sha256=args.targets_sha256,
    )
    manifest = run_mask_diagnostic_v06(
        pack=pack,
        config=config,
        source_run=_REPO / config["source_run_dir"],
        output_dir=_REPO / config["results_root"],
        device=args.device,
    )
    print(json.dumps(manifest, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()

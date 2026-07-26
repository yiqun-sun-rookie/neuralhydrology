"""Atomic runner for hierarchical rich historical context."""
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

from bands_v05 import gather_rich_bands_v05
from data import (
    DataPack,
    compute_scaler,
    load_basin_ids,
    load_data_pack,
    normalize_pack,
    split_target_indices,
)
from metrics import per_basin_nse
from models_v05 import VARIANTS_V05, build_model_v05, count_trainable_parameters


_REPO = Path(__file__).resolve().parents[2]
_CLASSIC_VARIANTS = (
    "classic_lstm_256",
    "classic_lstm_320",
)
_FROZEN_CONFIG = {
    "experiment_family": "hierarchical_rich_historical_context_v05",
    "batch_size": 256,
    "learning_rate_schedule": {"1": 0.001, "12": 0.0005, "22": 0.0001},
    "gradient_clip": 1.0,
    "recent_hidden_size": 256,
    "medium_hidden_size": 64,
    "old_within_hidden_size": 64,
    "old_across_hidden_size": 128,
    "history_statistics": ["mean", "population_std", "minimum", "maximum"],
    "initial_forget_bias": 5.0,
    "output_dropout": 0.4,
}
_EVIDENCE_LENGTHS = {
    "design_commit": 40,
    "basin_file_sha256": 64,
    "target_bundle_sha256": 64,
    "reference_v03_summary_sha256": 64,
    "reference_v04_summary_sha256": 64,
}


def _atomic_text(path: Path, content: str) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(content, encoding="utf-8")
    os.replace(temporary, path)


def _atomic_frame(path: Path, frame: pd.DataFrame) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    frame.to_csv(temporary, index=False)
    os.replace(temporary, path)


def _atomic_checkpoint(path: Path, payload: dict) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    torch.save(payload, temporary)
    os.replace(temporary, path)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def validate_frozen_file_hash(path: str | Path, expected_sha256: str, label: str) -> str:
    """Reject a frozen input file whose bytes do not match the configuration."""
    actual_sha256 = _sha256(Path(path))
    if actual_sha256.lower() != str(expected_sha256).lower():
        raise ValueError(f"{label} SHA-256 mismatch: expected {expected_sha256}, got {actual_sha256}")
    return actual_sha256


def _validate_hex_binding(config: Mapping, key: str, length: int) -> None:
    value = config.get(key)
    if not isinstance(value, str) or len(value) != length:
        raise ValueError(f"{key} must be a {length}-character hexadecimal binding")
    try:
        int(value, 16)
    except ValueError as error:
        raise ValueError(f"{key} must be a {length}-character hexadecimal binding") from error


def validate_frozen_config_v05(config: Mapping) -> None:
    """Reject any version 05 architecture, training, or evidence-binding drift."""
    for key, expected in _FROZEN_CONFIG.items():
        if config.get(key) != expected:
            raise ValueError(f"{key} must be frozen at {expected!r}, got {config.get(key)!r}")
    for key, length in _EVIDENCE_LENGTHS.items():
        _validate_hex_binding(config, key, length)

    mode = config.get("mode")
    if mode == "pilot":
        if config.get("epochs") != 30:
            raise ValueError("epochs must be 30 in pilot mode")
        if int(config.get("limit_batches", 0)) != 0:
            raise ValueError("limit_batches must be 0 in pilot mode")
        if int(config.get("limit_validation_samples", 0)) != 0:
            raise ValueError("limit_validation_samples must be 0 in pilot mode")
    elif mode == "smoke":
        if config.get("epochs") != 2:
            raise ValueError("epochs must be 2 in smoke mode")
        if int(config.get("limit_batches", 0)) <= 0:
            raise ValueError("limit_batches must be positive in smoke mode")
        if int(config.get("limit_validation_samples", 0)) <= 0:
            raise ValueError("limit_validation_samples must be positive in smoke mode")
    else:
        raise ValueError("mode must be 'smoke' or 'pilot'")


def learning_rate_for_epoch(config: Mapping, epoch: int) -> float:
    """Return the classic piecewise-constant rate for a one-indexed epoch."""
    if epoch < 1:
        raise ValueError("epoch must be one-indexed")
    schedule = sorted(
        (int(start), float(rate))
        for start, rate in config["learning_rate_schedule"].items()
    )
    eligible = [rate for start, rate in schedule if start <= epoch]
    if not eligible:
        raise ValueError(f"learning-rate schedule has no value for epoch {epoch}")
    return eligible[-1]


def _gather_recent(
    forcing: torch.Tensor,
    basin_indices: torch.Tensor,
    target_indices: torch.Tensor,
) -> torch.Tensor:
    lags = torch.arange(269, -1, -1, device=forcing.device)
    times = target_indices[:, None] - lags[None, :]
    return forcing[basin_indices[:, None], times]


def dynamic_batch_v05(
    variant: str,
    forcing: torch.Tensor,
    basin_indices: torch.Tensor,
    target_indices: torch.Tensor,
) -> dict[str, torch.Tensor]:
    """Gather exactly the dynamic information consumed by one model arm."""
    if variant not in VARIANTS_V05:
        raise ValueError(f"unknown variant: {variant}")
    if variant in _CLASSIC_VARIANTS:
        return {"recent": _gather_recent(forcing, basin_indices, target_indices)}
    return gather_rich_bands_v05(
        forcing,
        basin_indices,
        target_indices,
    )


def _limited_balanced_indices(
    basin_indices: np.ndarray,
    target_indices: np.ndarray,
    limit: int,
) -> tuple[np.ndarray, np.ndarray]:
    if limit <= 0 or len(basin_indices) <= limit:
        return basin_indices, target_indices
    unique = np.unique(basin_indices)
    per_basin = max(1, int(np.ceil(limit / len(unique))))
    selected = []
    for basin in unique:
        positions = np.flatnonzero(basin_indices == basin)
        selected.extend(positions[:per_basin].tolist())
    selected = np.asarray(selected[:limit], dtype=np.int64)
    return basin_indices[selected], target_indices[selected]


def _snapshot(config: Mapping, variant: str, seed: int) -> dict:
    snapshot = dict(config)
    snapshot["variant"] = variant
    snapshot["seed"] = int(seed)
    return snapshot


def run_experiment_v05(
    pack: DataPack,
    config: Mapping,
    variant: str,
    seed: int,
    output_dir: str | Path,
    device: str,
) -> dict:
    """Train one version 05 arm and write independently recomputable evidence."""
    if variant not in VARIANTS_V05:
        raise ValueError(f"variant must be one of {VARIANTS_V05}")
    validate_frozen_config_v05(config)
    output_dir = Path(output_dir)
    if output_dir.exists() and any(output_dir.iterdir()):
        raise FileExistsError(f"output directory is not empty: {output_dir}")
    output_dir.mkdir(parents=True, exist_ok=True)

    _atomic_text(
        output_dir / "config.json",
        json.dumps(_snapshot(config, variant, seed), indent=2, sort_keys=True),
    )
    torch.manual_seed(seed)
    np.random.seed(seed)
    generator = np.random.default_rng(seed)
    torch_device = torch.device(device)

    scaler = compute_scaler(pack.forcing, pack.discharge, pack.statics, pack.dates)
    normalized = normalize_pack(pack, scaler)
    forcing = torch.tensor(normalized.forcing, device=torch_device)
    statics = torch.tensor(normalized.statics, device=torch_device)
    discharge = torch.tensor(normalized.discharge, device=torch_device)
    raw_q_std = torch.tensor(
        np.asarray(scaler["per_basin_q_std"], dtype=np.float32),
        device=torch_device,
    )

    model = build_model_v05(variant, seed=seed).to(torch_device)
    parameter_count = count_trainable_parameters(model)
    optimizer = torch.optim.Adam(
        model.parameters(),
        lr=learning_rate_for_epoch(config, 1),
    )
    train_basins, train_times = split_target_indices(pack.dates, pack.discharge, split="train")
    batch_size = int(config["batch_size"])
    limit_batches = int(config.get("limit_batches", 0))
    final_losses: list[float] = []
    optimizer_steps_total = 0
    epoch_learning_rates = []

    for epoch in range(1, int(config["epochs"]) + 1):
        learning_rate = learning_rate_for_epoch(config, epoch)
        epoch_learning_rates.append(learning_rate)
        for group in optimizer.param_groups:
            group["lr"] = learning_rate
        order = generator.permutation(len(train_basins))
        batch_count = int(np.ceil(len(order) / batch_size))
        if limit_batches > 0:
            batch_count = min(batch_count, limit_batches)
        model.train()
        epoch_losses = []
        for batch_index in range(batch_count):
            selected = order[batch_index * batch_size:(batch_index + 1) * batch_size]
            basin_index = torch.tensor(train_basins[selected], device=torch_device)
            target_index = torch.tensor(train_times[selected], device=torch_device)
            dynamic = dynamic_batch_v05(
                variant,
                forcing,
                basin_index,
                target_index,
            )
            output = model(dynamic, statics[basin_index])
            target = discharge[basin_index, target_index]
            loss_weights = 1.0 / torch.square(raw_q_std[basin_index] + 0.1)
            loss = (loss_weights * torch.square(output.prediction - target)).mean()
            optimizer.zero_grad()
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), float(config["gradient_clip"]))
            optimizer.step()
            epoch_losses.append(float(loss.detach().cpu()))
            optimizer_steps_total += 1
        if not epoch_losses:
            raise RuntimeError("training produced no optimizer steps")
        final_losses = epoch_losses

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
    validation_batch_size = int(config["validation_batch_size"])
    prediction_parts = []
    model.eval()
    with torch.no_grad():
        for start in range(0, len(validation_basins), validation_batch_size):
            basin_numpy = validation_basins[start:start + validation_batch_size]
            target_numpy = validation_times[start:start + validation_batch_size]
            basin_index = torch.tensor(basin_numpy, device=torch_device)
            target_index = torch.tensor(target_numpy, device=torch_device)
            dynamic = dynamic_batch_v05(
                variant,
                forcing,
                basin_index,
                target_index,
            )
            output = model(dynamic, statics[basin_index])
            qsim = (
                output.prediction.detach().cpu().numpy() * float(scaler["q_scale"])
                + float(scaler["q_center"])
            )
            prediction_parts.append(pd.DataFrame({
                "basin": [pack.basins[index] for index in basin_numpy],
                "date": pack.dates[target_numpy].strftime("%Y-%m-%d"),
                "qobs": pack.discharge[basin_numpy, target_numpy],
                "qsim": qsim,
            }))

    predictions = pd.concat(prediction_parts, ignore_index=True)
    predictions = predictions.sort_values(["basin", "date"]).reset_index(drop=True)
    predictions_path = output_dir / "predictions.csv"
    _atomic_frame(predictions_path, predictions)
    reloaded = pd.read_csv(predictions_path, dtype={"basin": str})
    metrics_path = output_dir / "per_basin_metrics.csv"
    _atomic_frame(metrics_path, per_basin_nse(reloaded))
    _atomic_checkpoint(
        output_dir / "checkpoint.pt",
        {
            "model_state_dict": model.state_dict(),
            "variant": variant,
            "seed": int(seed),
            "parameter_count": parameter_count,
            "scaler": scaler,
        },
    )

    manifest = {
        "status": "complete",
        "experiment_family": config["experiment_family"],
        "design_commit": config["design_commit"],
        "target_bundle_sha256": config["target_bundle_sha256"],
        "reference_v03_summary_sha256": config["reference_v03_summary_sha256"],
        "reference_v04_summary_sha256": config["reference_v04_summary_sha256"],
        "variant": variant,
        "seed": int(seed),
        "parameter_count": parameter_count,
        "epochs": int(config["epochs"]),
        "epoch_learning_rates": epoch_learning_rates,
        "optimizer_steps_total": optimizer_steps_total,
        "optimizer_steps_last_epoch": len(final_losses),
        "final_training_loss": float(np.mean(final_losses)),
        "n_training_samples": int(len(train_basins)),
        "n_validation_predictions": int(len(predictions)),
        "data_access": {
            "raw_observed_discharge_reads": 0,
            "target_bundle_interface": True,
        },
        "artifacts": {
            name: _sha256(output_dir / name)
            for name in (
                "config.json",
                "checkpoint.pt",
                "predictions.csv",
                "per_basin_metrics.csv",
            )
        },
    }
    _atomic_text(output_dir / "manifest.json", json.dumps(manifest, indent=2, sort_keys=True))
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--variant", choices=VARIANTS_V05, required=True)
    parser.add_argument("--seed", type=int, required=True)
    parser.add_argument("--data-dir", type=Path, required=True)
    parser.add_argument("--targets-file", type=Path, required=True)
    parser.add_argument("--targets-sha256", required=True)
    parser.add_argument("--device", default="cpu")
    args = parser.parse_args()

    config = json.loads(args.config.read_text(encoding="utf-8"))
    validate_frozen_config_v05(config)
    expected_targets_sha256 = config["target_bundle_sha256"]
    if str(expected_targets_sha256).lower() != args.targets_sha256.lower():
        raise ValueError("command target SHA-256 does not match the frozen configuration")
    basin_file = _REPO / config["basin_file"]
    validate_frozen_file_hash(basin_file, config["basin_file_sha256"], "basin list")
    reference_summary = _REPO / config["reference_v03_results_root"] / "summary.json"
    validate_frozen_file_hash(
        reference_summary,
        config["reference_v03_summary_sha256"],
        "version 03 summary",
    )
    version_04_summary = _REPO / config["reference_v04_results_root"] / "summary.json"
    validate_frozen_file_hash(
        version_04_summary,
        config["reference_v04_summary_sha256"],
        "version 04 summary",
    )
    basins = load_basin_ids(basin_file)
    pack = load_data_pack(
        args.data_dir,
        basins,
        targets_file=args.targets_file,
        expected_targets_sha256=args.targets_sha256,
    )
    output_dir = _REPO / config["results_root"] / f"{args.variant}_s{args.seed}"
    manifest = run_experiment_v05(
        pack=pack,
        config=config,
        variant=args.variant,
        seed=args.seed,
        output_dir=output_dir,
        device=args.device,
    )
    print(json.dumps(manifest, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()

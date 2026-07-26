"""Atomic trainer for one fixed historical-band comparison arm and seed."""
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

from bands import forcing_prefix, gather_fixed_bands
from data import (
    DataPack,
    compute_scaler,
    load_basin_ids,
    load_data_pack,
    normalize_pack,
    split_target_indices,
)
from metrics import per_basin_nse
from models import HistoricalBandExperts, MainstreamLSTM, MultiscaleFusion


_REPO = Path(__file__).resolve().parents[2]
VARIANTS = ("mainstream_lstm", "multiscale_fusion", "historical_band_experts")


def _atomic_text(path: Path, text: str) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(text, encoding="utf-8")
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


def _build_model(variant: str) -> torch.nn.Module:
    if variant == "mainstream_lstm":
        return MainstreamLSTM(5, 27)
    if variant == "multiscale_fusion":
        return MultiscaleFusion(5, 27)
    if variant == "historical_band_experts":
        return HistoricalBandExperts(5, 27)
    raise ValueError(f"unknown variant: {variant}")


def _gather_mainstream(
    forcing: torch.Tensor,
    basin_indices: torch.Tensor,
    target_indices: torch.Tensor,
) -> torch.Tensor:
    lags = torch.arange(269, -1, -1, device=forcing.device)
    times = target_indices[:, None] - lags[None, :]
    return forcing[basin_indices[:, None], times]


def _dynamic_batch(
    variant: str,
    forcing: torch.Tensor,
    prefix: torch.Tensor,
    basin_indices: torch.Tensor,
    target_indices: torch.Tensor,
) -> dict[str, torch.Tensor]:
    if variant == "mainstream_lstm":
        return {
            "mainstream": _gather_mainstream(forcing, basin_indices, target_indices),
        }
    return gather_fixed_bands(
        forcing,
        basin_indices,
        target_indices,
        prefix=prefix,
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


def _jsonable_config(config: Mapping, variant: str, seed: int) -> dict:
    snapshot = dict(config)
    snapshot["variant"] = variant
    snapshot["seed"] = int(seed)
    return snapshot


def run_experiment(
    pack: DataPack,
    config: Mapping,
    variant: str,
    seed: int,
    output_dir: str | Path,
    device: str,
) -> dict:
    """Train one atomic arm and write predictions plus independently recomputable metrics."""
    if variant not in VARIANTS:
        raise ValueError(f"variant must be one of {VARIANTS}")
    output_dir = Path(output_dir)
    if output_dir.exists() and any(output_dir.iterdir()):
        raise FileExistsError(f"output directory is not empty: {output_dir}")
    output_dir.mkdir(parents=True, exist_ok=True)

    snapshot = _jsonable_config(config, variant, seed)
    _atomic_text(output_dir / "config.json", json.dumps(snapshot, indent=2, sort_keys=True))

    torch.manual_seed(seed)
    np.random.seed(seed)
    generator = np.random.default_rng(seed)
    torch_device = torch.device(device)

    scaler = compute_scaler(pack.forcing, pack.discharge, pack.statics, pack.dates)
    normalized = normalize_pack(pack, scaler)
    forcing = torch.tensor(normalized.forcing, device=torch_device)
    statics = torch.tensor(normalized.statics, device=torch_device)
    discharge = torch.tensor(normalized.discharge, device=torch_device)
    prefix = forcing_prefix(forcing)
    raw_q_std = torch.tensor(
        np.asarray(scaler["per_basin_q_std"], dtype=np.float32),
        device=torch_device,
    )

    model = _build_model(variant).to(torch_device)
    optimizer = torch.optim.Adam(model.parameters(), lr=float(config["learning_rate"]))
    train_basins, train_times = split_target_indices(pack.dates, pack.discharge, split="train")
    batch_size = int(config["batch_size"])
    limit_batches = int(config.get("limit_batches", 0))
    final_losses = []

    for _epoch in range(int(config["epochs"])):
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
            dynamic = _dynamic_batch(
                variant,
                forcing,
                prefix,
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
            dynamic = _dynamic_batch(
                variant,
                forcing,
                prefix,
                basin_index,
                target_index,
            )
            output = model(dynamic, statics[basin_index])
            qsim = (
                output.prediction.detach().cpu().numpy() * float(scaler["q_scale"])
                + float(scaler["q_center"])
            )
            frame = pd.DataFrame({
                "basin": [pack.basins[index] for index in basin_numpy],
                "date": pack.dates[target_numpy].strftime("%Y-%m-%d"),
                "qobs": pack.discharge[basin_numpy, target_numpy],
                "qsim": qsim,
            })
            if output.weights is not None:
                weights = output.weights.detach().cpu().numpy()
                frame["weight_recent"] = weights[:, 0]
                frame["weight_medium"] = weights[:, 1]
                frame["weight_old"] = weights[:, 2]
            prediction_parts.append(frame)

    predictions = pd.concat(prediction_parts, ignore_index=True)
    predictions = predictions.sort_values(["basin", "date"]).reset_index(drop=True)
    predictions_path = output_dir / "predictions.csv"
    _atomic_frame(predictions_path, predictions)
    reloaded = pd.read_csv(predictions_path, dtype={"basin": str})
    metrics = per_basin_nse(reloaded)
    metrics_path = output_dir / "per_basin_metrics.csv"
    _atomic_frame(metrics_path, metrics)
    _atomic_checkpoint(
        output_dir / "checkpoint.pt",
        {
            "model_state_dict": model.state_dict(),
            "variant": variant,
            "seed": seed,
            "scaler": scaler,
        },
    )

    manifest = {
        "status": "complete",
        "variant": variant,
        "seed": int(seed),
        "epochs": int(config["epochs"]),
        "optimizer_steps_last_epoch": len(final_losses),
        "final_training_loss": float(np.mean(final_losses)),
        "n_training_samples": int(len(train_basins)),
        "n_validation_predictions": int(len(predictions)),
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
    parser.add_argument("--variant", choices=VARIANTS, required=True)
    parser.add_argument("--seed", type=int, required=True)
    parser.add_argument("--data-dir", type=Path, required=True)
    parser.add_argument("--device", default="cpu")
    args = parser.parse_args()

    config = json.loads(args.config.read_text(encoding="utf-8"))
    basin_file = _REPO / config["basin_file"]
    basins = load_basin_ids(basin_file)
    pack = load_data_pack(args.data_dir, basins)
    output_dir = _REPO / config["results_root"] / f"{args.variant}_s{args.seed}"
    manifest = run_experiment(
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

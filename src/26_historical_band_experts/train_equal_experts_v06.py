"""Atomic runner for equal historical experts iteration 1."""
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

from bands_v03 import forcing_prefix, gather_fixed_bands_v03
from data import (
    DataPack,
    compute_scaler,
    load_basin_ids,
    load_data_pack,
    normalize_pack,
    split_target_indices,
)
from metrics import per_basin_nse
from models_equal_experts_v06 import (
    VARIANTS_EQUAL_EXPERTS_V06,
    build_equal_experts_model_v06,
)
from models_v03 import count_trainable_parameters
from train_v05 import (
    _gather_recent,
    _limited_balanced_indices,
    learning_rate_for_epoch,
    validate_frozen_file_hash,
)


_REPO = Path(__file__).resolve().parents[2]
_CLASSIC_VARIANTS = ("classic_lstm_256_keyed", "classic_lstm_455_keyed")
_EXPECTED_COUNTS = {
    "classic_lstm_256_keyed": 297_217,
    "classic_lstm_455_keyed": 890_436,
    "late_concat_keyed": 308_401,
    "equal_experts": 891_649,
}
_EXPECTED = {
    "experiment_id": "E06-I01",
    "experiment_family": "equal_historical_experts_i01_v06",
    "candidate_iteration": 1,
    "candidate_iteration_budget": 5,
    "basin_file_sha256": "3160dad3b22200fdb596164c9f69e4fbe19cc156cfad768beb193efea7b26b65",
    "target_bundle_sha256": "d4c93675eefd433515d6f7e10943caea31c6eb7e30533d4c387cf9325886e05c",
    "strict_nesting_summary_sha256": "38cb81e24d575e8291fa04f0a530de2baf45ad9e32fcb8bdf524f9f61b780f2d",
    "learning_rate_schedule": {"1": 0.001, "12": 0.0005, "22": 0.0001},
    "gradient_clip": 1.0,
    "initial_forget_bias": 5.0,
    "output_dropout": 0.4,
    "dropout_stream": "seed_epoch_batch_branch_sha256",
    "recent_hidden_size": 256,
    "medium_hidden_size": 256,
    "old_hidden_size": 256,
    "capacity_control_hidden_size": 455,
    "recent_lags": [0, 269],
    "medium_lags": [270, 1824],
    "old_lags": [1825, 3649],
    "medium_bins": 60,
    "old_bins": 60,
    "history_statistics": ["mean"],
    "candidate_parameter_count": 891_649,
    "capacity_control_parameter_count": 890_436,
    "seeds": [100, 200, 300],
    "stage1_seed": 100,
    "stage1_gates": {
        "median_delta_classic_at_least": 0.01,
        "median_delta_capacity_above": 0.0,
        "median_delta_late_concat_above": 0.0,
        "win_fraction_classic_at_least": 0.55,
    },
    "formal_evaluation_access": False,
}


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


def _atomic_checkpoint(path: Path, payload: dict) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    torch.save(payload, temporary)
    os.replace(temporary, path)


def validate_equal_config_v06(config: Mapping) -> None:
    for key, expected in _EXPECTED.items():
        if config.get(key) != expected:
            raise ValueError(f"{key} must be frozen at {expected!r}, got {config.get(key)!r}")
    if int(config.get("batch_size", 0)) <= 0:
        raise ValueError("batch_size must be positive")
    if int(config.get("validation_batch_size", 0)) <= 0:
        raise ValueError("validation_batch_size must be positive")
    results_root = str(config.get("results_root", ""))
    mode = config.get("mode")
    expected_suffix = (
        "equal_experts_i01_v06_smoke"
        if mode == "smoke"
        else "equal_experts_i01_v06"
    )
    if not results_root.endswith(expected_suffix):
        raise ValueError("results_root must be isolated for equal-experts iteration 1")
    limit_batches = int(config.get("limit_batches", 0))
    limit_validation = int(config.get("limit_validation_samples", 0))
    if mode == "pilot":
        if int(config.get("epochs", 0)) != 30:
            raise ValueError("epochs must be 30 in pilot mode")
        if int(config["batch_size"]) != 256 or int(config["validation_batch_size"]) != 512:
            raise ValueError("pilot batch sizes must be 256 and 512")
        if limit_batches != 0 or limit_validation != 0:
            raise ValueError("pilot mode must not limit batches or validation samples")
    elif mode == "smoke":
        if int(config.get("epochs", 0)) != 2:
            raise ValueError("epochs must be 2 in smoke mode")
        if limit_batches <= 0 or limit_validation <= 0:
            raise ValueError("smoke mode requires positive limits")
    else:
        raise ValueError("mode must be 'pilot' or 'smoke'")


def dynamic_batch_equal_v06(
    variant: str,
    forcing: torch.Tensor,
    prefix: torch.Tensor,
    basin_indices: torch.Tensor,
    target_indices: torch.Tensor,
) -> dict[str, torch.Tensor]:
    if variant not in VARIANTS_EQUAL_EXPERTS_V06:
        raise ValueError(f"unknown equal-expert variant: {variant}")
    if variant in _CLASSIC_VARIANTS:
        return {"recent": _gather_recent(forcing, basin_indices, target_indices)}
    return gather_fixed_bands_v03(
        forcing,
        basin_indices,
        target_indices,
        prefix=prefix,
    )


def run_equal_experiment_v06(
    pack: DataPack,
    config: Mapping,
    variant: str,
    seed: int,
    output_dir: str | Path,
    device: str,
) -> dict:
    validate_equal_config_v06(config)
    if variant not in VARIANTS_EQUAL_EXPERTS_V06:
        raise ValueError(f"unknown equal-expert variant: {variant}")
    if int(seed) not in config["seeds"]:
        raise ValueError("seed is not in the frozen seed policy")
    output_dir = Path(output_dir)
    if output_dir.exists() and any(output_dir.iterdir()):
        raise FileExistsError(f"output directory is not empty: {output_dir}")
    output_dir.mkdir(parents=True, exist_ok=True)
    snapshot = dict(config)
    snapshot.update({"variant": variant, "seed": int(seed)})
    _atomic_text(output_dir / "config.json", json.dumps(snapshot, indent=2, sort_keys=True))

    torch.manual_seed(int(seed))
    np.random.seed(int(seed))
    generator = np.random.default_rng(int(seed))
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
    model = build_equal_experts_model_v06(variant, seed=int(seed)).to(torch_device)
    parameter_count = count_trainable_parameters(model)
    if parameter_count != _EXPECTED_COUNTS[variant]:
        raise ValueError(f"parameter count mismatch for {variant}")
    optimizer = torch.optim.Adam(model.parameters(), lr=learning_rate_for_epoch(config, 1))
    train_basins, train_times = split_target_indices(
        pack.dates,
        pack.discharge,
        split="train",
    )
    optimizer_steps_total = 0
    final_losses = []
    epoch_rows = []
    for epoch in range(1, int(config["epochs"]) + 1):
        learning_rate = learning_rate_for_epoch(config, epoch)
        for group in optimizer.param_groups:
            group["lr"] = learning_rate
        order = generator.permutation(len(train_basins))
        batch_count = int(np.ceil(len(order) / int(config["batch_size"])))
        limit_batches = int(config.get("limit_batches", 0))
        if limit_batches > 0:
            batch_count = min(batch_count, limit_batches)
        model.train()
        losses = []
        for batch_index in range(batch_count):
            selected = order[
                batch_index * int(config["batch_size"]):
                (batch_index + 1) * int(config["batch_size"])
            ]
            basin_index = torch.tensor(train_basins[selected], device=torch_device)
            target_index = torch.tensor(train_times[selected], device=torch_device)
            dynamic = dynamic_batch_equal_v06(
                variant,
                forcing,
                prefix,
                basin_index,
                target_index,
            )
            output = model(
                dynamic,
                statics[basin_index],
                dropout_context=(int(seed), epoch, batch_index),
            )
            target = discharge[basin_index, target_index]
            loss_weights = 1.0 / torch.square(raw_q_std[basin_index] + 0.1)
            loss = (loss_weights * torch.square(output.prediction - target)).mean()
            optimizer.zero_grad()
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), float(config["gradient_clip"]))
            optimizer.step()
            losses.append(float(loss.detach().cpu()))
            optimizer_steps_total += 1
        if not losses:
            raise RuntimeError("training produced no optimizer steps")
        final_losses = losses
        epoch_row = {
            "epoch": epoch,
            "learning_rate": learning_rate,
            "mean_loss": float(np.mean(losses)),
            "optimizer_steps_total": optimizer_steps_total,
        }
        epoch_rows.append(epoch_row)
        print(json.dumps({"variant": variant, **epoch_row}, sort_keys=True), flush=True)

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
    model.eval()
    parts = []
    with torch.no_grad():
        for start in range(0, len(validation_basins), int(config["validation_batch_size"])):
            basin_numpy = validation_basins[start:start + int(config["validation_batch_size"])]
            target_numpy = validation_times[start:start + int(config["validation_batch_size"])]
            basin_index = torch.tensor(basin_numpy, device=torch_device)
            target_index = torch.tensor(target_numpy, device=torch_device)
            dynamic = dynamic_batch_equal_v06(
                variant,
                forcing,
                prefix,
                basin_index,
                target_index,
            )
            prediction = model(dynamic, statics[basin_index], dropout_context=None).prediction
            qsim = (
                prediction.detach().cpu().numpy() * float(scaler["q_scale"])
                + float(scaler["q_center"])
            )
            parts.append(pd.DataFrame({
                "basin": [pack.basins[index] for index in basin_numpy],
                "date": pack.dates[target_numpy].strftime("%Y-%m-%d"),
                "qobs": pack.discharge[basin_numpy, target_numpy],
                "qsim": qsim,
            }))
    predictions = pd.concat(parts, ignore_index=True).sort_values(
        ["basin", "date"]
    ).reset_index(drop=True)
    expected_rows = 43_860 if config["mode"] == "pilot" else int(config["limit_validation_samples"])
    if len(predictions) != expected_rows:
        raise ValueError(f"validation prediction count must be {expected_rows}, got {len(predictions)}")
    _atomic_frame(output_dir / "predictions.csv", predictions)
    reloaded = pd.read_csv(output_dir / "predictions.csv", dtype={"basin": str})
    _atomic_frame(output_dir / "per_basin_metrics.csv", per_basin_nse(reloaded))
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
    artifact_names = ("config.json", "checkpoint.pt", "predictions.csv", "per_basin_metrics.csv")
    manifest = {
        "status": "complete",
        "experiment_id": config["experiment_id"],
        "experiment_family": config["experiment_family"],
        "candidate_iteration": int(config["candidate_iteration"]),
        "variant": variant,
        "seed": int(seed),
        "parameter_count": parameter_count,
        "dropout_stream": config["dropout_stream"],
        "epochs": int(config["epochs"]),
        "optimizer_steps_total": optimizer_steps_total,
        "final_training_loss": float(np.mean(final_losses)),
        "n_training_samples": int(len(train_basins)),
        "n_validation_predictions": int(len(predictions)),
        "epoch_trace": epoch_rows,
        "device": str(torch_device),
        "data_access": {
            "raw_observed_discharge_reads": 0,
            "target_bundle_interface": True,
            "formal_evaluation_access": False,
        },
        "artifacts": {name: _sha256(output_dir / name) for name in artifact_names},
    }
    _atomic_text(output_dir / "manifest.json", json.dumps(manifest, indent=2, sort_keys=True))
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--variant", choices=VARIANTS_EQUAL_EXPERTS_V06, required=True)
    parser.add_argument("--seed", type=int, required=True)
    parser.add_argument("--data-dir", type=Path, required=True)
    parser.add_argument("--targets-file", type=Path, required=True)
    parser.add_argument("--targets-sha256", required=True)
    parser.add_argument("--device", default="cpu")
    args = parser.parse_args()
    config = json.loads(args.config.read_text(encoding="utf-8"))
    validate_equal_config_v06(config)
    if args.targets_sha256.lower() != config["target_bundle_sha256"].lower():
        raise ValueError("command target SHA-256 does not match the frozen configuration")
    validate_frozen_file_hash(
        _REPO / "results/26_historical_band_experts/strict_nesting_v06/summary.json",
        config["strict_nesting_summary_sha256"],
        "strict nesting summary",
    )
    basin_file = _REPO / config["basin_file"]
    validate_frozen_file_hash(basin_file, config["basin_file_sha256"], "basin list")
    basins = load_basin_ids(basin_file)
    pack = load_data_pack(
        args.data_dir,
        basins,
        targets_file=args.targets_file,
        expected_targets_sha256=args.targets_sha256,
    )
    manifest = run_equal_experiment_v06(
        pack=pack,
        config=config,
        variant=args.variant,
        seed=args.seed,
        output_dir=_REPO / config["results_root"] / f"{args.variant}_s{args.seed}",
        device=args.device,
    )
    print(json.dumps(manifest, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()

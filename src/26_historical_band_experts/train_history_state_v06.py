"""Train historical experts to initialize a frozen recent LSTM state."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Mapping

import numpy as np
import pandas as pd
import torch

from bands_v03 import forcing_prefix
from data import (
    DataPack,
    load_basin_ids,
    load_data_pack,
    normalize_pack,
    split_target_indices,
)
from metrics import per_basin_nse
from models_equal_experts_v06 import build_equal_experts_model_v06
from models_history_state_v06 import (
    FrozenRecentHistoryState,
    build_history_state_candidate_v06,
)
from train_equal_experts_v06 import (
    _atomic_checkpoint,
    _atomic_frame,
    _atomic_text,
    _sha256,
    dynamic_batch_equal_v06,
)
from train_frozen_residual_v06 import (
    _recent_state_sha256,
    _validate_base_checkpoint,
)
from train_v05 import (
    _limited_balanced_indices,
    learning_rate_for_epoch,
    validate_frozen_file_hash,
)


_REPO = Path(__file__).resolve().parents[2]
_EXPECTED = {
    "experiment_id": "E06-I03",
    "experiment_family": "frozen_recent_history_state_i03_v06",
    "candidate_iteration": 3,
    "candidate_iteration_budget": 5,
    "basin_file_sha256": "3160dad3b22200fdb596164c9f69e4fbe19cc156cfad768beb193efea7b26b65",
    "target_bundle_sha256": "d4c93675eefd433515d6f7e10943caea31c6eb7e30533d4c387cf9325886e05c",
    "iteration_two_summary_sha256": "963a945ff555eed629408f7d7857fd893ac509ebe1b47a64cfab0b169d407b54",
    "base_checkpoint_sha256": "6dc004ed0580ddf3f6b81a1ce90c706c0e102713795a7a913ff9798d9f85190b",
    "classic_predictions_sha256": "3ec0c449da8dc1e5165e7082da978676f3369ac39b7c3d1c093572def7ed1b4f",
    "capacity_predictions_sha256": "14c1023e23243ba37db488b7d9f5027081b46de4f1008d1525d1f456e720e5b4",
    "late_concat_predictions_sha256": "dc67277dd9302e7fe5985728a87d82178de1029a9f2bab123a3cbe72d5807941",
    "learning_rate_schedule": {"1": 0.001, "12": 0.0005, "22": 0.0001},
    "gradient_clip": 1.0,
    "initial_forget_bias": 5.0,
    "history_state_dropout": 0.4,
    "dropout_stream": "seed_epoch_batch_branch_sha256",
    "recent_training": "frozen",
    "recent_output_dropout": False,
    "history_injection": "initial_hidden_and_cell_diagonal_gates",
    "state_gate_activation": "tanh",
    "state_gate_initialization": "zero",
    "recent_hidden_size": 256,
    "medium_hidden_size": 256,
    "old_hidden_size": 256,
    "recent_lags": [0, 269],
    "medium_lags": [270, 1824],
    "old_lags": [1825, 3649],
    "medium_bins": 60,
    "old_bins": 60,
    "history_statistics": ["mean"],
    "candidate_parameter_count": 892_161,
    "trainable_history_parameter_count": 594_944,
    "stage1_seed": 100,
    "conditional_seeds": [200, 300],
    "stage1_gates": {
        "median_delta_classic_at_least": 0.01,
        "median_delta_capacity_above": 0.0,
        "median_delta_late_concat_above": 0.0,
        "win_fraction_classic_at_least": 0.55,
    },
    "formal_evaluation_access": False,
}


def validate_history_state_config_v06(config: Mapping) -> None:
    for key, expected in _EXPECTED.items():
        if config.get(key) != expected:
            raise ValueError(f"{key} must be frozen at {expected!r}, got {config.get(key)!r}")
    if int(config.get("batch_size", 0)) <= 0:
        raise ValueError("batch_size must be positive")
    if int(config.get("validation_batch_size", 0)) <= 0:
        raise ValueError("validation_batch_size must be positive")
    mode = config.get("mode")
    expected_suffix = (
        "history_state_i03_v06_smoke"
        if mode == "smoke"
        else "history_state_i03_v06"
    )
    if not str(config.get("results_root", "")).endswith(expected_suffix):
        raise ValueError("results_root must be isolated for history-state iteration 3")
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


def train_history_state_step_v06(
    model: FrozenRecentHistoryState,
    optimizer: torch.optim.Optimizer,
    dynamic: Mapping[str, torch.Tensor],
    statics: torch.Tensor,
    target: torch.Tensor,
    loss_weights: torch.Tensor,
    dropout_context: tuple[int, int, int],
    gradient_clip: float,
) -> float:
    model.train()
    prediction = model(
        dynamic,
        statics,
        dropout_context=dropout_context,
    ).prediction
    loss = (loss_weights * torch.square(prediction - target)).mean()
    optimizer.zero_grad()
    loss.backward()
    torch.nn.utils.clip_grad_norm_(
        (parameter for parameter in model.parameters() if parameter.requires_grad),
        float(gradient_clip),
    )
    optimizer.step()
    return float(loss.detach().cpu())


def _initial_prediction_is_exact(
    model: FrozenRecentHistoryState,
    base_state_dict: Mapping[str, torch.Tensor],
    dynamic: Mapping[str, torch.Tensor],
    statics: torch.Tensor,
    device: torch.device,
) -> bool:
    base = build_equal_experts_model_v06("classic_lstm_256_keyed", seed=100)
    base.load_state_dict(base_state_dict)
    base.to(device).eval()
    model.eval()
    with torch.no_grad():
        expected = base({"recent": dynamic["recent"]}, statics).prediction
        actual = model(dynamic, statics, dropout_context=None).prediction
    return bool(torch.equal(actual, expected))


def run_history_state_experiment_v06(
    pack: DataPack,
    config: Mapping,
    seed: int,
    base_checkpoint: Mapping,
    output_dir: str | Path,
    device: str,
) -> dict:
    validate_history_state_config_v06(config)
    if int(seed) != int(config["stage1_seed"]):
        raise ValueError("stage-one runner only permits the frozen seed 100")
    _validate_base_checkpoint(base_checkpoint, seed)
    output_dir = Path(output_dir)
    if output_dir.exists() and any(output_dir.iterdir()):
        raise FileExistsError(f"output directory is not empty: {output_dir}")
    output_dir.mkdir(parents=True, exist_ok=True)
    snapshot = dict(config)
    snapshot.update({"variant": "frozen_recent_history_state", "seed": int(seed)})
    _atomic_text(output_dir / "config.json", json.dumps(snapshot, indent=2, sort_keys=True))

    torch.manual_seed(int(seed))
    np.random.seed(int(seed))
    generator = np.random.default_rng(int(seed))
    torch_device = torch.device(device)
    scaler = base_checkpoint["scaler"]
    normalized = normalize_pack(pack, scaler)
    forcing = torch.tensor(normalized.forcing, device=torch_device)
    statics = torch.tensor(normalized.statics, device=torch_device)
    discharge = torch.tensor(normalized.discharge, device=torch_device)
    prefix = forcing_prefix(forcing)
    raw_q_std = torch.tensor(
        np.asarray(scaler["per_basin_q_std"], dtype=np.float32),
        device=torch_device,
    )
    model = build_history_state_candidate_v06(
        base_checkpoint["model_state_dict"],
        seed=int(seed),
    ).to(torch_device)
    frozen_before = _recent_state_sha256(model)
    optimizer = torch.optim.Adam(
        (parameter for parameter in model.parameters() if parameter.requires_grad),
        lr=learning_rate_for_epoch(config, 1),
    )
    train_basins, train_times = split_target_indices(
        pack.dates,
        pack.discharge,
        split="train",
    )
    probe_basins = torch.tensor(train_basins[:8], device=torch_device)
    probe_times = torch.tensor(train_times[:8], device=torch_device)
    probe_dynamic = dynamic_batch_equal_v06(
        "equal_experts",
        forcing,
        prefix,
        probe_basins,
        probe_times,
    )
    initial_prediction_exact = _initial_prediction_is_exact(
        model,
        base_checkpoint["model_state_dict"],
        probe_dynamic,
        statics[probe_basins],
        torch_device,
    )
    if not initial_prediction_exact:
        raise RuntimeError("zero-gate candidate does not exactly reproduce the base prediction")

    optimizer_steps_total = 0
    final_losses: list[float] = []
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
        losses = []
        for batch_index in range(batch_count):
            selected = order[
                batch_index * int(config["batch_size"]):
                (batch_index + 1) * int(config["batch_size"])
            ]
            basin_index = torch.tensor(train_basins[selected], device=torch_device)
            target_index = torch.tensor(train_times[selected], device=torch_device)
            dynamic = dynamic_batch_equal_v06(
                "equal_experts",
                forcing,
                prefix,
                basin_index,
                target_index,
            )
            target = discharge[basin_index, target_index]
            loss_weights = 1.0 / torch.square(raw_q_std[basin_index] + 0.1)
            loss = train_history_state_step_v06(
                model=model,
                optimizer=optimizer,
                dynamic=dynamic,
                statics=statics[basin_index],
                target=target,
                loss_weights=loss_weights,
                dropout_context=(int(seed), epoch, batch_index),
                gradient_clip=float(config["gradient_clip"]),
            )
            losses.append(loss)
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
        print(json.dumps({"variant": "frozen_recent_history_state", **epoch_row}, sort_keys=True), flush=True)

    frozen_after = _recent_state_sha256(model)
    if frozen_after != frozen_before:
        raise RuntimeError("frozen recent state changed during history-state training")
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
                "equal_experts",
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
            "variant": "frozen_recent_history_state",
            "seed": int(seed),
            "parameter_count": 892_161,
            "trainable_parameter_count": 594_944,
            "scaler": scaler,
            "base_checkpoint_sha256": config["base_checkpoint_sha256"],
        },
    )
    artifact_names = ("config.json", "checkpoint.pt", "predictions.csv", "per_basin_metrics.csv")
    manifest = {
        "status": "complete",
        "experiment_id": config["experiment_id"],
        "experiment_family": config["experiment_family"],
        "candidate_iteration": int(config["candidate_iteration"]),
        "variant": "frozen_recent_history_state",
        "seed": int(seed),
        "parameter_count": 892_161,
        "trainable_history_parameter_count": 594_944,
        "base_checkpoint_sha256": config["base_checkpoint_sha256"],
        "dropout_stream": config["dropout_stream"],
        "epochs": int(config["epochs"]),
        "optimizer_steps_total": optimizer_steps_total,
        "final_training_loss": float(np.mean(final_losses)),
        "n_training_samples": int(len(train_basins)),
        "n_validation_predictions": int(len(predictions)),
        "epoch_trace": epoch_rows,
        "initial_prediction_exact": initial_prediction_exact,
        "frozen_recent_state_sha256_before": frozen_before,
        "frozen_recent_state_sha256_after": frozen_after,
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
    parser.add_argument("--seed", type=int, required=True)
    parser.add_argument("--data-dir", type=Path, required=True)
    parser.add_argument("--targets-file", type=Path, required=True)
    parser.add_argument("--targets-sha256", required=True)
    parser.add_argument("--device", default="cpu")
    args = parser.parse_args()
    config = json.loads(args.config.read_text(encoding="utf-8"))
    validate_history_state_config_v06(config)
    if args.targets_sha256.lower() != config["target_bundle_sha256"].lower():
        raise ValueError("command target SHA-256 does not match the frozen configuration")
    for path_key, hash_key, label in (
        ("iteration_two_summary", "iteration_two_summary_sha256", "iteration-two summary"),
        ("base_checkpoint", "base_checkpoint_sha256", "base checkpoint"),
        ("classic_predictions", "classic_predictions_sha256", "classic predictions"),
        ("capacity_predictions", "capacity_predictions_sha256", "capacity predictions"),
        ("late_concat_predictions", "late_concat_predictions_sha256", "late-concat predictions"),
    ):
        validate_frozen_file_hash(_REPO / config[path_key], config[hash_key], label)
    basin_file = _REPO / config["basin_file"]
    validate_frozen_file_hash(basin_file, config["basin_file_sha256"], "basin list")
    basins = load_basin_ids(basin_file)
    pack = load_data_pack(
        args.data_dir,
        basins,
        targets_file=args.targets_file,
        expected_targets_sha256=args.targets_sha256,
    )
    base_checkpoint = torch.load(
        _REPO / config["base_checkpoint"],
        map_location="cpu",
        weights_only=False,
    )
    manifest = run_history_state_experiment_v06(
        pack=pack,
        config=config,
        seed=args.seed,
        base_checkpoint=base_checkpoint,
        output_dir=_REPO / config["results_root"] / f"frozen_recent_history_state_s{args.seed}",
        device=args.device,
    )
    print(json.dumps(manifest, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()

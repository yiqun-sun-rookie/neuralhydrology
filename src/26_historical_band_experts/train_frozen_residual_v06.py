"""Train equal-width historical experts while preserving a frozen recent expert."""
from __future__ import annotations

import argparse
import hashlib
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
from models_equal_experts_v06 import (
    EqualHistoricalExperts,
    build_equal_experts_model_v06,
    keyed_dropout,
)
from models_v03 import _append_statics, count_trainable_parameters
from train_equal_experts_v06 import (
    _atomic_checkpoint,
    _atomic_frame,
    _atomic_text,
    _sha256,
    dynamic_batch_equal_v06,
)
from train_v05 import (
    _limited_balanced_indices,
    learning_rate_for_epoch,
    validate_frozen_file_hash,
)


_REPO = Path(__file__).resolve().parents[2]
_EXPECTED = {
    "experiment_id": "E06-I02",
    "experiment_family": "frozen_recent_residual_i02_v06",
    "candidate_iteration": 2,
    "candidate_iteration_budget": 5,
    "basin_file_sha256": "3160dad3b22200fdb596164c9f69e4fbe19cc156cfad768beb193efea7b26b65",
    "target_bundle_sha256": "d4c93675eefd433515d6f7e10943caea31c6eb7e30533d4c387cf9325886e05c",
    "iteration_one_summary_sha256": "4f1e0b20de3e53bf70b2e24939edd71874856267e9b69c535bdbd1005b0470eb",
    "base_checkpoint_sha256": "6dc004ed0580ddf3f6b81a1ce90c706c0e102713795a7a913ff9798d9f85190b",
    "classic_predictions_sha256": "3ec0c449da8dc1e5165e7082da978676f3369ac39b7c3d1c093572def7ed1b4f",
    "capacity_predictions_sha256": "14c1023e23243ba37db488b7d9f5027081b46de4f1008d1525d1f456e720e5b4",
    "late_concat_predictions_sha256": "dc67277dd9302e7fe5985728a87d82178de1029a9f2bab123a3cbe72d5807941",
    "learning_rate_schedule": {"1": 0.001, "12": 0.0005, "22": 0.0001},
    "gradient_clip": 1.0,
    "initial_forget_bias": 5.0,
    "output_dropout": 0.4,
    "dropout_stream": "seed_epoch_batch_branch_sha256",
    "recent_training": "frozen",
    "recent_training_dropout": False,
    "recent_prediction_csv_max_abs_tolerance": 2e-6,
    "history_training": "residual",
    "history_head_initialization": "zero",
    "recent_hidden_size": 256,
    "medium_hidden_size": 256,
    "old_hidden_size": 256,
    "recent_lags": [0, 269],
    "medium_lags": [270, 1824],
    "old_lags": [1825, 3649],
    "medium_bins": 60,
    "old_bins": 60,
    "history_statistics": ["mean"],
    "candidate_parameter_count": 891_649,
    "trainable_history_parameter_count": 594_432,
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
_CLASSIC_TO_RECENT = {
    "lstm.weight_ih_l0": "weight_ih_l0",
    "lstm.weight_hh_l0": "weight_hh_l0",
    "lstm.bias_ih_l0": "bias_ih_l0",
    "lstm.bias_hh_l0": "bias_hh_l0",
}


def validate_frozen_residual_config_v06(config: Mapping) -> None:
    for key, expected in _EXPECTED.items():
        if config.get(key) != expected:
            raise ValueError(f"{key} must be frozen at {expected!r}, got {config.get(key)!r}")
    if int(config.get("batch_size", 0)) <= 0:
        raise ValueError("batch_size must be positive")
    if int(config.get("validation_batch_size", 0)) <= 0:
        raise ValueError("validation_batch_size must be positive")
    mode = config.get("mode")
    expected_suffix = (
        "frozen_recent_residual_i02_v06_smoke"
        if mode == "smoke"
        else "frozen_recent_residual_i02_v06"
    )
    if not str(config.get("results_root", "")).endswith(expected_suffix):
        raise ValueError("results_root must be isolated for frozen-residual iteration 2")
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


def build_frozen_recent_candidate_v06(
    base_state_dict: Mapping[str, torch.Tensor],
    seed: int,
) -> EqualHistoricalExperts:
    model = build_equal_experts_model_v06("equal_experts", seed=int(seed))
    if not isinstance(model, EqualHistoricalExperts):
        raise TypeError("equal-expert builder returned an unexpected model")
    recurrent_state = {
        target: base_state_dict[source]
        for source, target in _CLASSIC_TO_RECENT.items()
    }
    model.recent_encoder.load_state_dict(recurrent_state)
    model.recent_head.load_state_dict({
        "weight": base_state_dict["head.weight"],
        "bias": base_state_dict["head.bias"],
    })
    for parameter in model.recent_encoder.parameters():
        parameter.requires_grad_(False)
    for parameter in model.recent_head.parameters():
        parameter.requires_grad_(False)
    if count_trainable_parameters(model) != 594_432:
        raise ValueError("trainable history parameter count is not 594432")
    return model


def frozen_recent_prediction_v06(
    model: EqualHistoricalExperts,
    dynamic: Mapping[str, torch.Tensor],
    statics: torch.Tensor,
) -> torch.Tensor:
    recent, _ = model.recent_encoder(_append_statics(dynamic["recent"], statics))
    return model.recent_head(recent[:, -1])[:, 0]


def history_residual_prediction_v06(
    model: EqualHistoricalExperts,
    dynamic: Mapping[str, torch.Tensor],
    statics: torch.Tensor,
    dropout_context: tuple[int, int, int] | None,
) -> torch.Tensor:
    medium, _ = model.medium_encoder(_append_statics(dynamic["medium"], statics))
    old, _ = model.old_encoder(_append_statics(dynamic["old"], statics))
    medium_state = keyed_dropout(
        medium[:, -1],
        model.dropout_probability,
        dropout_context,
        branch="medium",
        training=model.training,
    )
    old_state = keyed_dropout(
        old[:, -1],
        model.dropout_probability,
        dropout_context,
        branch="old",
        training=model.training,
    )
    return (
        model.medium_head(medium_state)
        + model.old_head(old_state)
    )[:, 0]


def train_frozen_residual_step_v06(
    model: EqualHistoricalExperts,
    optimizer: torch.optim.Optimizer,
    dynamic: Mapping[str, torch.Tensor],
    statics: torch.Tensor,
    target: torch.Tensor,
    loss_weights: torch.Tensor,
    dropout_context: tuple[int, int, int],
    gradient_clip: float,
) -> float:
    model.train()
    with torch.no_grad():
        recent = frozen_recent_prediction_v06(model, dynamic, statics)
    residual = history_residual_prediction_v06(
        model,
        dynamic,
        statics,
        dropout_context=dropout_context,
    )
    loss = (loss_weights * torch.square(recent + residual - target)).mean()
    optimizer.zero_grad()
    loss.backward()
    torch.nn.utils.clip_grad_norm_(
        (parameter for parameter in model.parameters() if parameter.requires_grad),
        float(gradient_clip),
    )
    optimizer.step()
    return float(loss.detach().cpu())


def _recent_state_sha256(model: EqualHistoricalExperts) -> str:
    digest = hashlib.sha256()
    for name, value in model.state_dict().items():
        if not name.startswith(("recent_encoder.", "recent_head.")):
            continue
        array = value.detach().cpu().contiguous().numpy()
        digest.update(name.encode("utf-8"))
        digest.update(str(array.dtype).encode("ascii"))
        digest.update(str(array.shape).encode("ascii"))
        digest.update(array.tobytes())
    return digest.hexdigest()


def _validate_base_checkpoint(base_checkpoint: Mapping, seed: int) -> None:
    if base_checkpoint.get("variant") != "classic_lstm_256_keyed":
        raise ValueError("base checkpoint must be classic_lstm_256_keyed")
    if int(base_checkpoint.get("seed", -1)) != int(seed):
        raise ValueError("base checkpoint seed does not match the candidate seed")
    if int(base_checkpoint.get("parameter_count", -1)) != 297_217:
        raise ValueError("base checkpoint parameter count must be 297217")
    if "model_state_dict" not in base_checkpoint or "scaler" not in base_checkpoint:
        raise ValueError("base checkpoint must contain model state and scaler")


def _align_recent_reference_v06(
    actual: pd.DataFrame,
    full_reference: pd.DataFrame,
) -> pd.DataFrame:
    keys = ["basin", "date"]
    if actual.duplicated(keys).any():
        raise ValueError("actual recent predictions contain duplicate keys")
    if full_reference.duplicated(keys).any():
        raise ValueError("reference recent predictions contain duplicate keys")
    aligned = actual[keys].merge(
        full_reference,
        on=keys,
        how="left",
        sort=False,
        validate="one_to_one",
        indicator=True,
    )
    if not bool((aligned["_merge"] == "both").all()):
        raise ValueError("frozen recent prediction keys do not match the reference")
    return aligned.drop(columns="_merge")[["basin", "date", "qobs", "qsim"]]


def run_frozen_residual_experiment_v06(
    pack: DataPack,
    config: Mapping,
    seed: int,
    base_checkpoint: Mapping,
    output_dir: str | Path,
    device: str,
    expected_recent_predictions: pd.DataFrame | None = None,
) -> dict:
    validate_frozen_residual_config_v06(config)
    if int(seed) != int(config["stage1_seed"]):
        raise ValueError("stage-one runner only permits the frozen seed 100")
    _validate_base_checkpoint(base_checkpoint, seed)
    output_dir = Path(output_dir)
    if output_dir.exists() and any(output_dir.iterdir()):
        raise FileExistsError(f"output directory is not empty: {output_dir}")
    output_dir.mkdir(parents=True, exist_ok=True)
    snapshot = dict(config)
    snapshot.update({"variant": "frozen_recent_equal_experts", "seed": int(seed)})
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
    model = build_frozen_recent_candidate_v06(
        base_checkpoint["model_state_dict"],
        seed=int(seed),
    ).to(torch_device)
    if sum(parameter.numel() for parameter in model.parameters()) != 891_649:
        raise ValueError("candidate total parameter count must be 891649")
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
            loss = train_frozen_residual_step_v06(
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
        print(json.dumps({"variant": "frozen_recent_equal_experts", **epoch_row}, sort_keys=True), flush=True)

    frozen_after = _recent_state_sha256(model)
    if frozen_after != frozen_before:
        raise RuntimeError("frozen recent state changed during residual training")
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
    recent_parts = []
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
            recent = frozen_recent_prediction_v06(model, dynamic, statics[basin_index])
            residual = history_residual_prediction_v06(
                model,
                dynamic,
                statics[basin_index],
                dropout_context=None,
            )
            qsim = (
                (recent + residual).detach().cpu().numpy() * float(scaler["q_scale"])
                + float(scaler["q_center"])
            )
            recent_qsim = (
                recent.detach().cpu().numpy() * float(scaler["q_scale"])
                + float(scaler["q_center"])
            )
            common = {
                "basin": [pack.basins[index] for index in basin_numpy],
                "date": pack.dates[target_numpy].strftime("%Y-%m-%d"),
                "qobs": pack.discharge[basin_numpy, target_numpy],
            }
            parts.append(pd.DataFrame({**common, "qsim": qsim}))
            recent_parts.append(pd.DataFrame({**common, "qsim": recent_qsim}))
    predictions = pd.concat(parts, ignore_index=True).sort_values(
        ["basin", "date"]
    ).reset_index(drop=True)
    recent_predictions = pd.concat(recent_parts, ignore_index=True).sort_values(
        ["basin", "date"]
    ).reset_index(drop=True)
    expected_rows = 43_860 if config["mode"] == "pilot" else int(config["limit_validation_samples"])
    if len(predictions) != expected_rows:
        raise ValueError(f"validation prediction count must be {expected_rows}, got {len(predictions)}")
    recent_max_abs = None
    if expected_recent_predictions is not None:
        reference = _align_recent_reference_v06(
            recent_predictions,
            expected_recent_predictions,
        )
        if not np.array_equal(
            recent_predictions["qobs"].to_numpy(),
            reference["qobs"].to_numpy(),
        ):
            raise ValueError("frozen recent observations do not match the reference")
        recent_max_abs = float(np.max(np.abs(
            recent_predictions["qsim"].to_numpy(dtype=np.float64)
            - reference["qsim"].to_numpy(dtype=np.float64)
        )))
        tolerance = float(config["recent_prediction_csv_max_abs_tolerance"])
        if recent_max_abs > tolerance:
            raise ValueError(
                f"frozen recent prediction drift exceeds {tolerance}: {recent_max_abs}"
            )
    _atomic_frame(output_dir / "predictions.csv", predictions)
    reloaded = pd.read_csv(output_dir / "predictions.csv", dtype={"basin": str})
    _atomic_frame(output_dir / "per_basin_metrics.csv", per_basin_nse(reloaded))
    _atomic_checkpoint(
        output_dir / "checkpoint.pt",
        {
            "model_state_dict": model.state_dict(),
            "variant": "frozen_recent_equal_experts",
            "seed": int(seed),
            "parameter_count": 891_649,
            "trainable_parameter_count": 594_432,
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
        "variant": "frozen_recent_equal_experts",
        "seed": int(seed),
        "parameter_count": 891_649,
        "trainable_history_parameter_count": 594_432,
        "base_checkpoint_sha256": config["base_checkpoint_sha256"],
        "dropout_stream": config["dropout_stream"],
        "epochs": int(config["epochs"]),
        "optimizer_steps_total": optimizer_steps_total,
        "final_training_loss": float(np.mean(final_losses)),
        "n_training_samples": int(len(train_basins)),
        "n_validation_predictions": int(len(predictions)),
        "epoch_trace": epoch_rows,
        "frozen_recent_state_sha256_before": frozen_before,
        "frozen_recent_state_sha256_after": frozen_after,
        "frozen_recent_prediction_max_abs_vs_reference": recent_max_abs,
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
    validate_frozen_residual_config_v06(config)
    if args.targets_sha256.lower() != config["target_bundle_sha256"].lower():
        raise ValueError("command target SHA-256 does not match the frozen configuration")
    for path_key, hash_key, label in (
        ("iteration_one_summary", "iteration_one_summary_sha256", "iteration-one summary"),
        ("base_checkpoint", "base_checkpoint_sha256", "base checkpoint"),
        ("classic_predictions", "classic_predictions_sha256", "classic predictions"),
        ("capacity_predictions", "capacity_predictions_sha256", "capacity predictions"),
        ("late_concat_predictions", "late_concat_predictions_sha256", "late-concat predictions"),
    ):
        validate_frozen_file_hash(
            _REPO / config[path_key],
            config[hash_key],
            label,
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
    base_checkpoint = torch.load(
        _REPO / config["base_checkpoint"],
        map_location="cpu",
        weights_only=False,
    )
    expected_recent = pd.read_csv(
        _REPO / config["classic_predictions"],
        dtype={"basin": str},
    )
    manifest = run_frozen_residual_experiment_v06(
        pack=pack,
        config=config,
        seed=args.seed,
        base_checkpoint=base_checkpoint,
        output_dir=_REPO / config["results_root"] / f"frozen_recent_equal_experts_s{args.seed}",
        device=args.device,
        expected_recent_predictions=expected_recent,
    )
    print(json.dumps(manifest, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()

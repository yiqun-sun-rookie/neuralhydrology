"""Atomic fresh-split training and exact nesting for continuous history version 08."""
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

from bands_continuous_v08 import forcing_prefix, gather_continuous_history_v08
from data import (
    DataPack,
    load_basin_ids,
    load_data_pack,
    normalize_pack,
)
from metrics import per_basin_nse
from models_continuous_v08 import (
    ContinuousMultiscaleHistoryLSTM,
    VARIANTS_CONTINUOUS_V08,
    build_model_v08,
)
from models_v03 import count_trainable_parameters
from train_strict_v06 import (
    _assert_gradients_equal,
    _assert_optimizer_states_equal,
    _assert_rng_state_equal,
    _rng_state,
    _set_rng_state,
    active_named_parameters,
    assert_exact_tensor,
    assert_parameter_sequence_equal,
)
from train_v05 import (
    _gather_recent,
    _limited_balanced_indices,
    learning_rate_for_epoch,
    validate_frozen_file_hash,
)


_REPO = Path(__file__).resolve().parents[2]
_RUN_VARIANTS = (
    "classic_lstm_256_keyed",
    "classic_lstm_369_keyed",
    "continuous_multiscale_history",
)
_EXPECTED_COUNTS = {
    "classic_lstm_256_keyed": 297_217,
    "classic_lstm_369_keyed": 595_198,
    "continuous_multiscale_history": 596_737,
}
_EXPECTED_COMMON = {
    "experiment_id": "E08-C01",
    "strict_reproduction_id": "R08-NEST",
    "experiment_family": "continuous_multiscale_history_v08",
    "basin_file_sha256": "3160dad3b22200fdb596164c9f69e4fbe19cc156cfad768beb193efea7b26b65",
    "target_bundle_sha256": "d4c93675eefd433515d6f7e10943caea31c6eb7e30533d4c387cf9325886e05c",
    "design_file_sha256": "2ec149b51a2cefad68ef1e3936b64774755d9fa0024ee800ffa411254127f78f",
    "prior_mask_summary_sha256": "e324538713b6fd1419f141621184be3081b8728fcc562c56a0d59e9433c3ca62",
    "prior_strict_nesting_summary_sha256": (
        "38cb81e24d575e8291fa04f0a530de2baf45ad9e32fcb8bdf524f9f61b780f2d"
    ),
    "train_period": ["1999-10-01", "2004-09-30"],
    "confirmation_period": ["2004-10-01", "2006-09-30"],
    "unused_previous_validation_period": ["2006-10-01", "2008-09-30"],
    "expected_training_samples": 109_620,
    "expected_confirmation_predictions": 43_800,
    "earliest_forcing_date": "1989-10-04",
    "gradient_clip": 1.0,
    "initial_forget_bias": 5.0,
    "output_dropout": 0.4,
    "dropout_stream": "seed_epoch_batch_branch_sha256",
    "state_transfer": "zero_gated_history_to_recent_hidden_and_cell",
    "gate_initialization": "exact_zero",
    "recent_hidden_size": 256,
    "history_hidden_size": 256,
    "capacity_control_hidden_size": 369,
    "recent_lags": [0, 269],
    "history_lags": [270, 3649],
    "history_bins": 120,
    "history_edge_formula": "round(exp(linspace(log(270),log(3650),121)))",
    "history_edges_sha256": (
        "bae1f744feca9160181365545a07b445eab269d6afa8817a2e7c99e19f200d73"
    ),
    "history_width_range_days": [6, 78],
    "history_features": [
        "maurer_mean_5",
        "log_duration_coordinate",
        "log_midpoint_lag_coordinate",
    ],
    "candidate_parameter_count": 596_737,
    "capacity_control_parameter_count": 595_198,
    "variants": list(_RUN_VARIANTS),
    "stage1_seed": 100,
    "conditional_seeds": [200, 300],
    "bootstrap_resamples": 100_000,
    "bootstrap_seed": 20_260_728,
    "stage1_gates": {
        "median_delta_classic_at_least": 0.01,
        "median_delta_capacity_above": 0.0,
        "win_fraction_classic_at_least": 0.55,
        "bootstrap_ci_lower_above": 0.0,
    },
    "diagnostic_modes": ["normal", "history_gates_zero"],
    "formal_evaluation_target_access": False,
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


def validate_config_v08(config: Mapping) -> None:
    """Reject any drift from the frozen scientific and access protocol."""
    for key, expected in _EXPECTED_COMMON.items():
        if config.get(key) != expected:
            raise ValueError(f"{key} must be frozen at {expected!r}, got {config.get(key)!r}")
    if int(config.get("batch_size", 0)) <= 0:
        raise ValueError("batch_size must be positive")
    if int(config.get("confirmation_batch_size", 0)) <= 0:
        raise ValueError("confirmation_batch_size must be positive")
    mode = config.get("mode")
    results_root = str(config.get("results_root", ""))
    limit_batches = int(config.get("limit_batches", 0))
    limit_confirmation = int(config.get("limit_confirmation_samples", 0))
    if mode == "pilot":
        if not results_root.endswith("continuous_multiscale_history_v08"):
            raise ValueError("results_root must be isolated for version 08")
        if int(config.get("epochs", 0)) != 30:
            raise ValueError("epochs must be 30 in pilot mode")
        if int(config["batch_size"]) != 256 or int(config["confirmation_batch_size"]) != 512:
            raise ValueError("pilot batch sizes must be 256 and 512")
        if config.get("learning_rate_schedule") != {
            "1": 0.001,
            "12": 0.0005,
            "22": 0.0001,
        }:
            raise ValueError("learning_rate_schedule must match the pilot schedule")
        if limit_batches != 0 or limit_confirmation != 0:
            raise ValueError("pilot mode must not limit training or confirmation")
    elif mode == "smoke":
        if not results_root.endswith("continuous_multiscale_history_v08_smoke"):
            raise ValueError("results_root must be isolated for version 08 smoke")
        if int(config.get("epochs", 0)) != 2:
            raise ValueError("epochs must be 2 in smoke mode")
        if config.get("learning_rate_schedule") != {"1": 0.001, "2": 0.0005}:
            raise ValueError("learning_rate_schedule must match the smoke schedule")
        if limit_batches <= 0 or limit_confirmation <= 0:
            raise ValueError("smoke mode requires positive limits")
    else:
        raise ValueError("mode must be 'pilot' or 'smoke'")


def _period_bounds(config: Mapping, split: str) -> tuple[pd.Timestamp, pd.Timestamp]:
    if split == "train":
        values = config["train_period"]
    elif split == "confirmation":
        values = config["confirmation_period"]
    else:
        raise ValueError("split must be 'train' or 'confirmation'")
    return pd.Timestamp(values[0]), pd.Timestamp(values[1])


def split_target_indices_v08(
    dates: pd.DatetimeIndex,
    discharge: np.ndarray,
    split: str,
    config: Mapping,
    require_history: bool = True,
) -> tuple[np.ndarray, np.ndarray]:
    """Return finite target coordinates for the frozen fresh split."""
    start, end = _period_bounds(config, split)
    if discharge.ndim != 2 or discharge.shape[1] != len(dates):
        raise ValueError("discharge must have shape [basin,time] aligned with dates")
    date_mask = np.asarray((dates >= start) & (dates <= end))
    valid = np.isfinite(discharge) & date_mask[None, :]
    basin_indices, target_indices = np.nonzero(valid)
    if require_history and len(target_indices) and int(target_indices.min()) < 3649:
        raise ValueError("a selected target lacks the required 3649 lag days")
    return basin_indices.astype(np.int64), target_indices.astype(np.int64)


def compute_scaler_v08(
    forcing: np.ndarray,
    discharge: np.ndarray,
    statics: np.ndarray,
    dates: pd.DatetimeIndex,
    config: Mapping,
) -> dict[str, np.ndarray | float]:
    """Compute every normalization and loss statistic from new training dates only."""
    start, end = _period_bounds(config, "train")
    train_mask = np.asarray((dates >= start) & (dates <= end))
    dynamic_values = forcing[:, train_mask, :].reshape(-1, forcing.shape[-1])
    target_values = discharge[:, train_mask]
    dynamic_center = np.nanmean(dynamic_values, axis=0)
    dynamic_scale = np.nanstd(dynamic_values, axis=0)
    dynamic_scale[dynamic_scale < 1e-8] = 1.0
    q_center = float(np.nanmean(target_values))
    q_scale = float(np.nanstd(target_values))
    if q_scale < 1e-8:
        q_scale = 1.0
    static_center = np.nanmean(statics, axis=0)
    static_scale = np.nanstd(statics, axis=0)
    static_scale[static_scale < 1e-8] = 1.0
    per_basin_q_std = np.nanstd(target_values, axis=1)
    return {
        "dynamic_center": dynamic_center.astype(np.float32),
        "dynamic_scale": dynamic_scale.astype(np.float32),
        "q_center": q_center,
        "q_scale": q_scale,
        "static_center": static_center.astype(np.float32),
        "static_scale": static_scale.astype(np.float32),
        "per_basin_q_std": per_basin_q_std.astype(np.float32),
    }


def dynamic_batch_v08(
    variant: str,
    forcing: torch.Tensor,
    prefix: torch.Tensor,
    basin_indices: torch.Tensor,
    target_indices: torch.Tensor,
) -> dict[str, torch.Tensor]:
    if variant not in VARIANTS_CONTINUOUS_V08:
        raise ValueError(f"unknown version 08 variant: {variant}")
    if variant == "continuous_multiscale_history":
        return gather_continuous_history_v08(
            forcing,
            prefix,
            basin_indices,
            target_indices,
        )
    return {"recent": _gather_recent(forcing, basin_indices, target_indices)}


def _prepare_tensors(
    pack: DataPack,
    config: Mapping,
    device: torch.device,
) -> tuple[dict, DataPack, torch.Tensor, torch.Tensor, torch.Tensor, torch.Tensor, torch.Tensor]:
    scaler = compute_scaler_v08(
        pack.forcing,
        pack.discharge,
        pack.statics,
        pack.dates,
        config,
    )
    normalized = normalize_pack(pack, scaler)
    forcing = torch.tensor(normalized.forcing, device=device)
    statics = torch.tensor(normalized.statics, device=device)
    discharge = torch.tensor(normalized.discharge, device=device)
    prefix = forcing_prefix(forcing)
    raw_q_std = torch.tensor(
        np.asarray(scaler["per_basin_q_std"], dtype=np.float32),
        device=device,
    )
    return scaler, normalized, forcing, statics, discharge, prefix, raw_q_std


def _expected_confirmation_rows(config: Mapping) -> int:
    if config["mode"] == "pilot":
        return int(config["expected_confirmation_predictions"])
    return int(config["limit_confirmation_samples"])


def _parameter_drift(
    model: torch.nn.Module,
    initial: Mapping[str, torch.Tensor],
) -> float:
    squared = 0.0
    for name, parameter in model.named_parameters():
        if name in initial:
            difference = parameter.detach().cpu() - initial[name]
            squared += float(torch.sum(torch.square(difference)))
    return float(np.sqrt(squared))


def _data_access(pack: DataPack) -> dict:
    return {
        "raw_observed_discharge_reads": 0,
        "target_bundle_interface": True,
        "formal_evaluation_target_access": False,
        "unused_previous_validation_target_uses": 0,
        "earliest_forcing_date": str(pack.dates.min().date()),
    }


def run_experiment_v08(
    pack: DataPack,
    config: Mapping,
    variant: str,
    seed: int,
    output_dir: str | Path,
    device: str,
) -> dict:
    """Train one frozen version 08 comparison arm and persist auditable artifacts."""
    validate_config_v08(config)
    if variant not in _RUN_VARIANTS:
        raise ValueError(f"variant must be one of {_RUN_VARIANTS}")
    allowed_seeds = [int(config["stage1_seed"])] + [
        int(value) for value in config["conditional_seeds"]
    ]
    if int(seed) not in allowed_seeds:
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
    scaler, _normalized, forcing, statics, discharge, prefix, raw_q_std = _prepare_tensors(
        pack,
        config,
        torch_device,
    )
    model = build_model_v08(variant, int(seed)).to(torch_device)
    parameter_count = count_trainable_parameters(model)
    if parameter_count != _EXPECTED_COUNTS[variant]:
        raise ValueError(f"parameter count mismatch for {variant}")
    active_parameters = [parameter for parameter in model.parameters() if parameter.requires_grad]
    optimizer = torch.optim.Adam(active_parameters, lr=learning_rate_for_epoch(config, 1))
    initial_recent = {
        name: parameter.detach().cpu().clone()
        for name, parameter in model.named_parameters()
        if name.startswith("lstm.") or name.startswith("head.")
    }
    train_basins, train_times = split_target_indices_v08(
        pack.dates,
        pack.discharge,
        "train",
        config,
    )
    if config["mode"] == "pilot" and len(train_basins) != int(
        config["expected_training_samples"]
    ):
        raise ValueError("pilot training sample count does not match the frozen configuration")

    optimizer_steps_total = 0
    history_first_nonzero_gradient_step = None
    history_gradient_norm = 0.0
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
        model.train()
        losses = []
        for batch_index in range(batch_count):
            selected = order[
                batch_index * int(config["batch_size"]):
                (batch_index + 1) * int(config["batch_size"])
            ]
            basin_index = torch.tensor(train_basins[selected], device=torch_device)
            target_index = torch.tensor(train_times[selected], device=torch_device)
            dynamic = dynamic_batch_v08(
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
            optimizer.zero_grad(set_to_none=True)
            loss.backward()
            if isinstance(model, ContinuousMultiscaleHistoryLSTM):
                gradient = model.history_encoder.weight_ih_l0.grad
                history_gradient_norm = (
                    0.0
                    if gradient is None
                    else float(gradient.detach().norm().cpu())
                )
                if history_gradient_norm > 0 and history_first_nonzero_gradient_step is None:
                    history_first_nonzero_gradient_step = optimizer_steps_total + 1
            torch.nn.utils.clip_grad_norm_(active_parameters, float(config["gradient_clip"]))
            optimizer.step()
            optimizer_steps_total += 1
            losses.append(float(loss.detach().cpu()))
        if not losses or not np.isfinite(losses).all():
            raise RuntimeError("training produced no finite optimizer steps")
        final_losses = losses
        epoch_row = {
            "epoch": epoch,
            "learning_rate": learning_rate,
            "mean_loss": float(np.mean(losses)),
            "optimizer_steps_total": optimizer_steps_total,
        }
        epoch_rows.append(epoch_row)
        print(json.dumps({"variant": variant, **epoch_row}, sort_keys=True), flush=True)
    if (
        isinstance(model, ContinuousMultiscaleHistoryLSTM)
        and optimizer_steps_total >= 3
        and history_first_nonzero_gradient_step is None
    ):
        raise RuntimeError("history encoder has no nonzero gradient by optimizer step three")

    confirmation_basins, confirmation_times = split_target_indices_v08(
        pack.dates,
        pack.discharge,
        "confirmation",
        config,
    )
    confirmation_basins, confirmation_times = _limited_balanced_indices(
        confirmation_basins,
        confirmation_times,
        int(config.get("limit_confirmation_samples", 0)),
    )
    model.eval()
    parts = []
    with torch.no_grad():
        for start in range(
            0,
            len(confirmation_basins),
            int(config["confirmation_batch_size"]),
        ):
            basin_numpy = confirmation_basins[
                start:start + int(config["confirmation_batch_size"])
            ]
            target_numpy = confirmation_times[
                start:start + int(config["confirmation_batch_size"])
            ]
            basin_index = torch.tensor(basin_numpy, device=torch_device)
            target_index = torch.tensor(target_numpy, device=torch_device)
            dynamic = dynamic_batch_v08(
                variant,
                forcing,
                prefix,
                basin_index,
                target_index,
            )
            prediction = model(
                dynamic,
                statics[basin_index],
                dropout_context=None,
            ).prediction
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
    expected_rows = _expected_confirmation_rows(config)
    if len(predictions) != expected_rows:
        raise ValueError(
            f"confirmation prediction count must be {expected_rows}, got {len(predictions)}"
        )
    if not np.isfinite(predictions["qsim"]).all():
        raise RuntimeError("confirmation predictions are not finite")
    _atomic_frame(output_dir / "predictions.csv", predictions)
    reloaded = pd.read_csv(output_dir / "predictions.csv", dtype={"basin": str})
    _atomic_frame(output_dir / "per_basin_metrics.csv", per_basin_nse(reloaded))

    if isinstance(model, ContinuousMultiscaleHistoryLSTM):
        hidden_gate_norm = float(model.hidden_gate.detach().norm().cpu())
        cell_gate_norm = float(model.cell_gate.detach().norm().cpu())
    else:
        hidden_gate_norm = None
        cell_gate_norm = None
    diagnostics = {
        "history_first_nonzero_gradient_step": history_first_nonzero_gradient_step,
        "history_gradient_norm": history_gradient_norm,
        "hidden_gate_norm": hidden_gate_norm,
        "cell_gate_norm": cell_gate_norm,
        "recent_parameter_l2_drift": _parameter_drift(model, initial_recent),
        "state_transfer": (
            config["state_transfer"]
            if variant == "continuous_multiscale_history"
            else "not_applicable_recent_only"
        ),
    }
    _atomic_text(
        output_dir / "training_diagnostics.json",
        json.dumps(diagnostics, indent=2, sort_keys=True),
    )
    _atomic_checkpoint(
        output_dir / "checkpoint.pt",
        {
            "model_state_dict": model.state_dict(),
            "variant": variant,
            "seed": int(seed),
            "parameter_count": parameter_count,
            "scaler": scaler,
            "train_period": list(config["train_period"]),
            "confirmation_period": list(config["confirmation_period"]),
        },
    )
    artifact_names = (
        "config.json",
        "checkpoint.pt",
        "predictions.csv",
        "per_basin_metrics.csv",
        "training_diagnostics.json",
    )
    manifest = {
        "status": "complete",
        "experiment_id": config["experiment_id"],
        "experiment_family": config["experiment_family"],
        "variant": variant,
        "seed": int(seed),
        "parameter_count": parameter_count,
        "epochs": int(config["epochs"]),
        "optimizer_steps_total": optimizer_steps_total,
        "final_training_loss": float(np.mean(final_losses)),
        "n_training_samples": int(len(train_basins)),
        "n_confirmation_predictions": int(len(predictions)),
        "train_period": list(config["train_period"]),
        "confirmation_period": list(config["confirmation_period"]),
        "epoch_trace": epoch_rows,
        "device": str(torch_device),
        "data_access": _data_access(pack),
        "artifacts": {name: _sha256(output_dir / name) for name in artifact_names},
    }
    _atomic_text(output_dir / "manifest.json", json.dumps(manifest, indent=2, sort_keys=True))
    return manifest


def _lockstep_train_step_v08(
    classic: torch.nn.Module,
    nested: torch.nn.Module,
    classic_optimizer: torch.optim.Optimizer,
    nested_optimizer: torch.optim.Optimizer,
    dynamic: dict[str, torch.Tensor],
    statics: torch.Tensor,
    target: torch.Tensor,
    loss_weights: torch.Tensor,
    dropout_context: tuple[int, int, int],
    gradient_clip: float,
) -> dict:
    classic_parameters = active_named_parameters(classic)
    nested_parameters = active_named_parameters(nested)
    assert_parameter_sequence_equal(classic_parameters, nested_parameters)
    device = classic_parameters[0][1].device
    classic.train()
    nested.train()
    classic_optimizer.zero_grad(set_to_none=True)
    nested_optimizer.zero_grad(set_to_none=True)
    before = _rng_state(device)
    classic_prediction = classic(
        dynamic,
        statics,
        dropout_context=dropout_context,
    ).prediction
    classic_after = _rng_state(device)
    _set_rng_state(before, device)
    nested_prediction = nested(
        dynamic,
        statics,
        dropout_context=dropout_context,
    ).prediction
    nested_after = _rng_state(device)
    _assert_rng_state_equal(classic_after, nested_after)
    assert_exact_tensor("prediction", classic_prediction, nested_prediction)
    classic_loss = (loss_weights * torch.square(classic_prediction - target)).mean()
    nested_loss = (loss_weights * torch.square(nested_prediction - target)).mean()
    assert_exact_tensor("loss", classic_loss, nested_loss)
    classic_loss.backward()
    nested_loss.backward()
    _assert_gradients_equal(classic_parameters, nested_parameters, "unclipped")
    classic_norm = torch.nn.utils.clip_grad_norm_(
        [parameter for _, parameter in classic_parameters],
        float(gradient_clip),
    )
    nested_norm = torch.nn.utils.clip_grad_norm_(
        [parameter for _, parameter in nested_parameters],
        float(gradient_clip),
    )
    assert_exact_tensor("gradient norm", classic_norm, nested_norm)
    _assert_gradients_equal(classic_parameters, nested_parameters, "clipped")
    classic_optimizer.step()
    nested_optimizer.step()
    assert_parameter_sequence_equal(classic_parameters, nested_parameters)
    _assert_optimizer_states_equal(
        classic_optimizer,
        nested_optimizer,
        classic_parameters,
        nested_parameters,
    )
    return {
        "loss": float(classic_loss.detach().cpu()),
        "gradient_norm": float(classic_norm.detach().cpu()),
    }


def _strict_metrics(predictions: pd.DataFrame) -> pd.DataFrame:
    classic = predictions[["basin", "date", "qobs", "qsim_classic"]].rename(
        columns={"qsim_classic": "qsim"}
    )
    nested = predictions[["basin", "date", "qobs", "qsim_nested"]].rename(
        columns={"qsim_nested": "qsim"}
    )
    classic_metrics = per_basin_nse(classic).rename(columns={"nse": "nse_classic"})
    nested_metrics = per_basin_nse(nested).rename(columns={"nse": "nse_nested"})
    return classic_metrics.merge(nested_metrics, on="basin", validate="one_to_one")


def run_strict_reproduction_v08(
    pack: DataPack,
    config: Mapping,
    seed: int,
    output_dir: str | Path,
    device: str,
) -> dict:
    """Train classic and disabled-history models in zero-tolerance lockstep."""
    validate_config_v08(config)
    if int(seed) != int(config["stage1_seed"]):
        raise ValueError("strict reproduction uses only the frozen stage-one seed")
    output_dir = Path(output_dir)
    if output_dir.exists() and any(output_dir.iterdir()):
        raise FileExistsError(f"output directory is not empty: {output_dir}")
    output_dir.mkdir(parents=True, exist_ok=True)
    snapshot = dict(config)
    snapshot.update({"variant": "strict_nesting", "seed": int(seed)})
    _atomic_text(output_dir / "config.json", json.dumps(snapshot, indent=2, sort_keys=True))

    torch.manual_seed(int(seed))
    np.random.seed(int(seed))
    generator = np.random.default_rng(int(seed))
    torch_device = torch.device(device)
    scaler, _normalized, forcing, statics, discharge, _prefix, raw_q_std = _prepare_tensors(
        pack,
        config,
        torch_device,
    )
    classic = build_model_v08("classic_lstm_256_keyed", int(seed)).to(torch_device)
    nested = build_model_v08("nested_history_disabled", int(seed)).to(torch_device)
    classic_parameters = active_named_parameters(classic)
    nested_parameters = active_named_parameters(nested)
    assert_parameter_sequence_equal(classic_parameters, nested_parameters)
    if count_trainable_parameters(classic) != 297_217:
        raise ValueError("classic active parameter count mismatch")
    if count_trainable_parameters(nested) != 297_217:
        raise ValueError("nested active parameter count mismatch")
    classic_optimizer = torch.optim.Adam(
        [parameter for _, parameter in classic_parameters],
        lr=learning_rate_for_epoch(config, 1),
    )
    nested_optimizer = torch.optim.Adam(
        [parameter for _, parameter in nested_parameters],
        lr=learning_rate_for_epoch(config, 1),
    )
    train_basins, train_times = split_target_indices_v08(
        pack.dates,
        pack.discharge,
        "train",
        config,
    )
    if config["mode"] == "pilot" and len(train_basins) != int(
        config["expected_training_samples"]
    ):
        raise ValueError("pilot training sample count does not match the frozen configuration")
    optimizer_steps_total = 0
    epoch_rows = []
    final_losses: list[float] = []
    first_ten_reports = []
    for epoch in range(1, int(config["epochs"]) + 1):
        learning_rate = learning_rate_for_epoch(config, epoch)
        for optimizer in (classic_optimizer, nested_optimizer):
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
            dynamic = {"recent": _gather_recent(forcing, basin_index, target_index)}
            target = discharge[basin_index, target_index]
            loss_weights = 1.0 / torch.square(raw_q_std[basin_index] + 0.1)
            report = _lockstep_train_step_v08(
                classic,
                nested,
                classic_optimizer,
                nested_optimizer,
                dynamic,
                statics[basin_index],
                target,
                loss_weights,
                dropout_context=(int(seed), epoch, batch_index),
                gradient_clip=float(config["gradient_clip"]),
            )
            optimizer_steps_total += 1
            losses.append(report["loss"])
            if len(first_ten_reports) < 10:
                first_ten_reports.append({
                    "step": optimizer_steps_total,
                    **report,
                })
        if not losses or not np.isfinite(losses).all():
            raise RuntimeError("strict reproduction produced no finite optimizer steps")
        final_losses = losses
        epoch_row = {
            "epoch": epoch,
            "learning_rate": learning_rate,
            "mean_loss": float(np.mean(losses)),
            "optimizer_steps_total": optimizer_steps_total,
        }
        epoch_rows.append(epoch_row)
        print(json.dumps({"variant": "strict_nesting", **epoch_row}, sort_keys=True), flush=True)

    confirmation_basins, confirmation_times = split_target_indices_v08(
        pack.dates,
        pack.discharge,
        "confirmation",
        config,
    )
    confirmation_basins, confirmation_times = _limited_balanced_indices(
        confirmation_basins,
        confirmation_times,
        int(config.get("limit_confirmation_samples", 0)),
    )
    classic.eval()
    nested.eval()
    parts = []
    with torch.no_grad():
        for start in range(
            0,
            len(confirmation_basins),
            int(config["confirmation_batch_size"]),
        ):
            basin_numpy = confirmation_basins[
                start:start + int(config["confirmation_batch_size"])
            ]
            target_numpy = confirmation_times[
                start:start + int(config["confirmation_batch_size"])
            ]
            basin_index = torch.tensor(basin_numpy, device=torch_device)
            target_index = torch.tensor(target_numpy, device=torch_device)
            dynamic = {"recent": _gather_recent(forcing, basin_index, target_index)}
            classic_prediction = classic(
                dynamic,
                statics[basin_index],
                dropout_context=None,
            ).prediction
            nested_prediction = nested(
                dynamic,
                statics[basin_index],
                dropout_context=None,
            ).prediction
            assert_exact_tensor(
                "confirmation prediction",
                classic_prediction,
                nested_prediction,
            )
            qsim_classic = (
                classic_prediction.detach().cpu().numpy() * float(scaler["q_scale"])
                + float(scaler["q_center"])
            )
            qsim_nested = (
                nested_prediction.detach().cpu().numpy() * float(scaler["q_scale"])
                + float(scaler["q_center"])
            )
            parts.append(pd.DataFrame({
                "basin": [pack.basins[index] for index in basin_numpy],
                "date": pack.dates[target_numpy].strftime("%Y-%m-%d"),
                "qobs": pack.discharge[basin_numpy, target_numpy],
                "qsim_classic": qsim_classic,
                "qsim_nested": qsim_nested,
            }))
    predictions = pd.concat(parts, ignore_index=True).sort_values(
        ["basin", "date"]
    ).reset_index(drop=True)
    expected_rows = _expected_confirmation_rows(config)
    if len(predictions) != expected_rows:
        raise ValueError(
            f"confirmation prediction count must be {expected_rows}, got {len(predictions)}"
        )
    difference = np.abs(
        predictions["qsim_classic"].to_numpy()
        - predictions["qsim_nested"].to_numpy()
    )
    maximum_difference = float(difference.max(initial=0.0))
    if maximum_difference != 0.0:
        raise RuntimeError("strict confirmation predictions are not exactly equal")
    _atomic_frame(output_dir / "predictions.csv", predictions)
    reloaded = pd.read_csv(output_dir / "predictions.csv", dtype={"basin": str})
    metrics = _strict_metrics(reloaded)
    _atomic_frame(output_dir / "per_basin_metrics.csv", metrics)
    _atomic_checkpoint(
        output_dir / "checkpoint.pt",
        {
            "classic_state_dict": classic.state_dict(),
            "nested_state_dict": nested.state_dict(),
            "classic_optimizer_state_dict": classic_optimizer.state_dict(),
            "nested_optimizer_state_dict": nested_optimizer.state_dict(),
            "seed": int(seed),
            "scaler": scaler,
        },
    )
    summary = {
        "status": "complete_exact",
        "lockstep_exact": True,
        "seed": int(seed),
        "optimizer_steps_total": optimizer_steps_total,
        "n_confirmation_predictions": int(len(predictions)),
        "max_prediction_abs_difference": maximum_difference,
        "median_nse_classic": float(np.nanmedian(metrics["nse_classic"])),
        "median_nse_nested": float(np.nanmedian(metrics["nse_nested"])),
        "first_ten_step_reports": first_ten_reports,
    }
    _atomic_text(output_dir / "summary.json", json.dumps(summary, indent=2, sort_keys=True))
    artifact_names = (
        "config.json",
        "checkpoint.pt",
        "predictions.csv",
        "per_basin_metrics.csv",
        "summary.json",
    )
    manifest = {
        "status": "complete_exact",
        "experiment_id": config["strict_reproduction_id"],
        "experiment_family": config["experiment_family"],
        "seed": int(seed),
        "lockstep_exact": True,
        "active_parameter_count": 297_217,
        "epochs": int(config["epochs"]),
        "optimizer_steps_total": optimizer_steps_total,
        "final_training_loss": float(np.mean(final_losses)),
        "n_training_samples": int(len(train_basins)),
        "n_confirmation_predictions": int(len(predictions)),
        "max_prediction_abs_difference": maximum_difference,
        "train_period": list(config["train_period"]),
        "confirmation_period": list(config["confirmation_period"]),
        "epoch_trace": epoch_rows,
        "device": str(torch_device),
        "data_access": _data_access(pack),
        "artifacts": {name: _sha256(output_dir / name) for name in artifact_names},
    }
    _atomic_text(output_dir / "manifest.json", json.dumps(manifest, indent=2, sort_keys=True))
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--variant", choices=_RUN_VARIANTS)
    parser.add_argument("--strict-nesting", action="store_true")
    parser.add_argument("--seed", type=int, required=True)
    parser.add_argument("--data-dir", type=Path, required=True)
    parser.add_argument("--targets-file", type=Path, required=True)
    parser.add_argument("--targets-sha256", required=True)
    parser.add_argument("--device", default="cpu")
    args = parser.parse_args()
    if args.strict_nesting == (args.variant is not None):
        raise ValueError("choose exactly one of --strict-nesting or --variant")
    config = json.loads(args.config.read_text(encoding="utf-8"))
    validate_config_v08(config)
    if args.targets_sha256.lower() != config["target_bundle_sha256"].lower():
        raise ValueError("command target SHA-256 does not match the frozen configuration")
    for path_key, hash_key, label in (
        ("design_file", "design_file_sha256", "version 08 design"),
        ("prior_mask_summary", "prior_mask_summary_sha256", "prior mask summary"),
        (
            "prior_strict_nesting_summary",
            "prior_strict_nesting_summary_sha256",
            "prior strict nesting summary",
        ),
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
    results_root = _REPO / config["results_root"]
    if args.strict_nesting:
        output_dir = results_root / f"strict_nesting_s{args.seed}"
        manifest = run_strict_reproduction_v08(
            pack,
            config,
            args.seed,
            output_dir,
            args.device,
        )
    else:
        output_dir = results_root / f"{args.variant}_s{args.seed}"
        manifest = run_experiment_v08(
            pack,
            config,
            args.variant,
            args.seed,
            output_dir,
            args.device,
        )
    print(json.dumps(manifest, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()

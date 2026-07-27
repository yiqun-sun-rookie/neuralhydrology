"""Zero-tolerance lockstep training primitives for the strict nested control."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
from typing import Iterable

import numpy as np
import pandas as pd
import torch
from torch import nn

from bands_v03 import forcing_prefix
from data import (
    DataPack,
    compute_scaler,
    load_basin_ids,
    load_data_pack,
    normalize_pack,
    split_target_indices,
)
from metrics import per_basin_nse
from models_v03 import count_trainable_parameters
from models_v06 import build_strict_pair_v06
from train_v05 import (
    _limited_balanced_indices,
    dynamic_batch_v05,
    learning_rate_for_epoch,
    validate_frozen_file_hash,
)


_REPO = Path(__file__).resolve().parents[2]
_BASIN_SHA256 = "3160dad3b22200fdb596164c9f69e4fbe19cc156cfad768beb193efea7b26b65"
_TARGET_SHA256 = "d4c93675eefd433515d6f7e10943caea31c6eb7e30533d4c387cf9325886e05c"
_LEARNING_RATE_SCHEDULE = {"1": 0.001, "12": 0.0005, "22": 0.0001}


class StrictNestingMismatch(RuntimeError):
    """Raised at the first component that differs between the paired runs."""


def active_named_parameters(model: nn.Module) -> list[tuple[str, nn.Parameter]]:
    return [(name, parameter) for name, parameter in model.named_parameters() if parameter.requires_grad]


def assert_exact_tensor(label: str, reference: torch.Tensor, candidate: torch.Tensor) -> None:
    if reference.shape != candidate.shape:
        raise StrictNestingMismatch(
            f"{label} shape mismatch: {tuple(reference.shape)} != {tuple(candidate.shape)}"
        )
    if reference.dtype != candidate.dtype:
        raise StrictNestingMismatch(f"{label} dtype mismatch: {reference.dtype} != {candidate.dtype}")
    if not torch.equal(reference, candidate):
        if reference.numel() and reference.is_floating_point():
            maximum = float((reference - candidate).abs().max().detach().cpu())
            detail = f"; max abs {maximum}"
        else:
            detail = ""
        raise StrictNestingMismatch(f"{label} mismatch{detail}")


def assert_batch_indices_equal(
    basin_indices: tuple[torch.Tensor, torch.Tensor],
    target_indices: tuple[torch.Tensor, torch.Tensor],
) -> None:
    assert_exact_tensor("basin batch indices", basin_indices[0], basin_indices[1])
    assert_exact_tensor("target batch indices", target_indices[0], target_indices[1])


def assert_parameter_sequence_equal(
    reference: Iterable[tuple[str, nn.Parameter]],
    candidate: Iterable[tuple[str, nn.Parameter]],
    compare_values: bool = True,
) -> None:
    reference = list(reference)
    candidate = list(candidate)
    reference_names = [name for name, _ in reference]
    candidate_names = [name for name, _ in candidate]
    if reference_names != candidate_names:
        raise StrictNestingMismatch(
            f"parameter order mismatch: {reference_names} != {candidate_names}"
        )
    for (name, reference_parameter), (_, candidate_parameter) in zip(reference, candidate):
        if reference_parameter.shape != candidate_parameter.shape:
            raise StrictNestingMismatch(f"parameter shape mismatch for {name}")
        if compare_values:
            assert_exact_tensor(f"parameter {name}", reference_parameter, candidate_parameter)


def _rng_state(device: torch.device) -> dict[str, torch.Tensor]:
    state = {"cpu": torch.get_rng_state().clone()}
    if device.type == "cuda":
        state["cuda"] = torch.cuda.get_rng_state(device).clone()
    return state


def _set_rng_state(state: dict[str, torch.Tensor], device: torch.device) -> None:
    torch.set_rng_state(state["cpu"])
    if device.type == "cuda":
        torch.cuda.set_rng_state(state["cuda"], device)


def _assert_rng_state_equal(
    reference: dict[str, torch.Tensor],
    candidate: dict[str, torch.Tensor],
) -> None:
    if tuple(reference) != tuple(candidate):
        raise StrictNestingMismatch("random-number state device set mismatch")
    for name in reference:
        assert_exact_tensor(f"{name} random-number state", reference[name], candidate[name])


def _assert_gradients_equal(
    reference: list[tuple[str, nn.Parameter]],
    candidate: list[tuple[str, nn.Parameter]],
    label: str,
) -> None:
    for (name, reference_parameter), (_, candidate_parameter) in zip(reference, candidate):
        if reference_parameter.grad is None or candidate_parameter.grad is None:
            if reference_parameter.grad is not candidate_parameter.grad:
                raise StrictNestingMismatch(f"{label} gradient presence mismatch for {name}")
            continue
        assert_exact_tensor(
            f"{label} gradient {name}",
            reference_parameter.grad,
            candidate_parameter.grad,
        )


def _assert_optimizer_states_equal(
    reference_optimizer: torch.optim.Optimizer,
    candidate_optimizer: torch.optim.Optimizer,
    reference_parameters: list[tuple[str, nn.Parameter]],
    candidate_parameters: list[tuple[str, nn.Parameter]],
) -> None:
    if len(reference_optimizer.param_groups) != len(candidate_optimizer.param_groups):
        raise StrictNestingMismatch("optimizer parameter-group count mismatch")
    for reference_group, candidate_group in zip(
        reference_optimizer.param_groups,
        candidate_optimizer.param_groups,
    ):
        reference_settings = {key: value for key, value in reference_group.items() if key != "params"}
        candidate_settings = {key: value for key, value in candidate_group.items() if key != "params"}
        if reference_settings != candidate_settings:
            raise StrictNestingMismatch("optimizer hyperparameter mismatch")
    for (name, reference_parameter), (_, candidate_parameter) in zip(
        reference_parameters,
        candidate_parameters,
    ):
        reference_state = reference_optimizer.state.get(reference_parameter, {})
        candidate_state = candidate_optimizer.state.get(candidate_parameter, {})
        if tuple(reference_state) != tuple(candidate_state):
            raise StrictNestingMismatch(f"optimizer state keys mismatch for {name}")
        for key in reference_state:
            reference_value = reference_state[key]
            candidate_value = candidate_state[key]
            if isinstance(reference_value, torch.Tensor):
                assert_exact_tensor(
                    f"optimizer state {name}.{key}",
                    reference_value,
                    candidate_value,
                )
            elif reference_value != candidate_value:
                raise StrictNestingMismatch(f"optimizer state mismatch for {name}.{key}")


def lockstep_train_step(
    classic: nn.Module,
    nested: nn.Module,
    classic_optimizer: torch.optim.Optimizer,
    nested_optimizer: torch.optim.Optimizer,
    dynamic: dict[str, torch.Tensor],
    statics: torch.Tensor,
    target: torch.Tensor,
    loss_weights: torch.Tensor,
    basin_indices: tuple[torch.Tensor, torch.Tensor],
    target_indices: tuple[torch.Tensor, torch.Tensor],
    gradient_clip: float,
) -> dict:
    """Apply one paired optimizer step and fail at the first non-exact component."""
    assert_batch_indices_equal(basin_indices, target_indices)
    classic_parameters = active_named_parameters(classic)
    nested_parameters = active_named_parameters(nested)
    assert_parameter_sequence_equal(classic_parameters, nested_parameters)
    device = classic_parameters[0][1].device
    if nested_parameters[0][1].device != device:
        raise StrictNestingMismatch("model device mismatch")

    classic.train()
    nested.train()
    classic_optimizer.zero_grad(set_to_none=True)
    nested_optimizer.zero_grad(set_to_none=True)
    before = _rng_state(device)
    classic_prediction = classic(dynamic, statics).prediction
    classic_after = _rng_state(device)
    _set_rng_state(before, device)
    nested_prediction = nested(dynamic, statics).prediction
    nested_after = _rng_state(device)
    _assert_rng_state_equal(classic_after, nested_after)
    assert_exact_tensor("prediction", classic_prediction, nested_prediction)

    classic_loss = (
        loss_weights * torch.square(classic_prediction - target)
    ).mean()
    nested_loss = (
        loss_weights * torch.square(nested_prediction - target)
    ).mean()
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
        "status": "exact",
        "prediction_equal": True,
        "loss_equal": True,
        "gradients_equal": True,
        "optimizer_state_equal": True,
        "parameters_equal": True,
        "loss": float(classic_loss.detach().cpu()),
        "gradient_norm": float(classic_norm.detach().cpu()),
    }


def exact_evaluation_predictions(
    classic: nn.Module,
    nested: nn.Module,
    batches: Iterable[tuple[dict[str, torch.Tensor], torch.Tensor]],
) -> tuple[torch.Tensor, torch.Tensor]:
    """Evaluate paired batches and require every prediction to be bitwise equal."""
    assert_parameter_sequence_equal(
        active_named_parameters(classic),
        active_named_parameters(nested),
    )
    classic.eval()
    nested.eval()
    classic_parts = []
    nested_parts = []
    with torch.no_grad():
        for batch_index, (dynamic, statics) in enumerate(batches):
            classic_prediction = classic(dynamic, statics).prediction
            nested_prediction = nested(dynamic, statics).prediction
            assert_exact_tensor(
                f"evaluation prediction batch {batch_index}",
                classic_prediction,
                nested_prediction,
            )
            classic_parts.append(classic_prediction)
            nested_parts.append(nested_prediction)
    if not classic_parts:
        raise ValueError("at least one evaluation batch is required")
    return torch.cat(classic_parts), torch.cat(nested_parts)


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


def _state_sha256(state: torch.Tensor) -> str:
    return hashlib.sha256(state.detach().cpu().numpy().tobytes()).hexdigest()


def _validate_hex(config: dict, key: str) -> None:
    value = config.get(key)
    if not isinstance(value, str) or len(value) != 64:
        raise ValueError(f"{key} must be a 64-character hexadecimal binding")
    try:
        int(value, 16)
    except ValueError as error:
        raise ValueError(f"{key} must be a 64-character hexadecimal binding") from error


def validate_strict_config_v06(config: dict) -> None:
    """Reject any identity, data, training, tolerance, or budget drift."""
    expected = {
        "experiment_id": "R06-NEST",
        "experiment_family": "strict_nesting_v06",
        "basin_file_sha256": _BASIN_SHA256,
        "target_bundle_sha256": _TARGET_SHA256,
        "validation_start": "2006-10-01",
        "validation_end": "2008-09-30",
        "learning_rate_schedule": _LEARNING_RATE_SCHEDULE,
        "gradient_clip": 1.0,
        "recent_hidden_size": 256,
        "initial_forget_bias": 5.0,
        "output_dropout": 0.4,
        "reproduction_tolerance": {"absolute": 0.0, "relative": 0.0},
        "candidate_iteration_budget": 5,
        "formal_evaluation_access": False,
    }
    for key, value in expected.items():
        if config.get(key) != value:
            raise ValueError(f"{key} must be frozen at {value!r}, got {config.get(key)!r}")
    if int(config.get("batch_size", 0)) <= 0:
        raise ValueError("batch_size must be positive")
    if int(config.get("validation_batch_size", 0)) <= 0:
        raise ValueError("validation_batch_size must be positive")
    results_root = str(config.get("results_root", ""))
    if not results_root or any(f"_v0{version}" in results_root for version in (3, 4, 5)):
        raise ValueError("results_root must be a new version 06 output root")
    mode = config.get("mode")
    limit_batches = int(config.get("limit_batches", 0))
    limit_validation = int(config.get("limit_validation_samples", 0))
    if mode == "pilot":
        if int(config.get("epochs", 0)) != 30:
            raise ValueError("epochs must be 30 in pilot mode")
        if int(config["batch_size"]) != 256:
            raise ValueError("batch_size must be 256 in pilot mode")
        if int(config["validation_batch_size"]) != 512:
            raise ValueError("validation_batch_size must be 512 in pilot mode")
        if limit_batches != 0 or limit_validation != 0:
            raise ValueError("pilot mode must not limit batches or validation samples")
        for key in ("reference_checkpoint_sha256", "reference_predictions_sha256"):
            _validate_hex(config, key)
        if not config.get("reference_run_dir"):
            raise ValueError("reference_run_dir is required in pilot mode")
    elif mode == "smoke":
        if int(config.get("epochs", 0)) != 2:
            raise ValueError("epochs must be 2 in smoke mode")
        if limit_batches <= 0 or limit_validation <= 0:
            raise ValueError("smoke mode requires positive batch and validation limits")
    else:
        raise ValueError("mode must be 'pilot' or 'smoke'")


def _paired_metrics(predictions: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for variant in ("classic", "nested"):
        narrow = predictions[["basin", "date", "qobs", f"qsim_{variant}"]].rename(
            columns={f"qsim_{variant}": "qsim"}
        )
        metrics = per_basin_nse(narrow)
        metrics.insert(0, "variant", variant)
        rows.append(metrics)
    return pd.concat(rows, ignore_index=True)


def median_nse_by_variant(metrics: pd.DataFrame) -> dict[str, float]:
    """Return per-variant medians while ignoring undefined basin metrics."""
    return {
        variant: float(np.nanmedian(frame["nse"].to_numpy(dtype=np.float64)))
        for variant, frame in metrics.groupby("variant", sort=True)
    }


def run_strict_reproduction_v06(
    pack: DataPack,
    config: dict,
    output_dir: str | Path,
    device: str,
) -> dict:
    """Train the classic and inert-history control in exact lockstep."""
    validate_strict_config_v06(config)
    output_dir = Path(output_dir)
    if output_dir.exists() and any(output_dir.iterdir()):
        raise FileExistsError(f"output directory is not empty: {output_dir}")
    output_dir.mkdir(parents=True, exist_ok=True)
    _atomic_text(output_dir / "config.json", json.dumps(dict(config), indent=2, sort_keys=True))

    seed = int(config["seed"])
    torch.manual_seed(seed)
    np.random.seed(seed)
    generator = np.random.default_rng(seed)
    torch_device = torch.device(device)
    scaler = compute_scaler(pack.forcing, pack.discharge, pack.statics, pack.dates)
    normalized = normalize_pack(pack, scaler)
    forcing = torch.tensor(normalized.forcing, device=torch_device)
    statics = torch.tensor(normalized.statics, device=torch_device)
    discharge = torch.tensor(normalized.discharge, device=torch_device)
    _historical_prefix_allocation = forcing_prefix(forcing)
    raw_q_std = torch.tensor(
        np.asarray(scaler["per_basin_q_std"], dtype=np.float32),
        device=torch_device,
    )

    classic, nested = build_strict_pair_v06(seed=seed)
    classic = classic.to(torch_device)
    nested = nested.to(torch_device)
    if count_trainable_parameters(classic) != 297_217:
        raise StrictNestingMismatch("classic active parameter count is not 297217")
    if count_trainable_parameters(nested) != 297_217:
        raise StrictNestingMismatch("nested active parameter count is not 297217")
    assert_parameter_sequence_equal(
        active_named_parameters(classic),
        active_named_parameters(nested),
    )
    post_build_rng = {
        "cpu": _state_sha256(torch.get_rng_state()),
        "cuda": (
            _state_sha256(torch.cuda.get_rng_state(torch_device))
            if torch_device.type == "cuda"
            else None
        ),
    }
    classic_optimizer = torch.optim.Adam(
        [parameter for _, parameter in active_named_parameters(classic)],
        lr=learning_rate_for_epoch(config, 1),
    )
    nested_optimizer = torch.optim.Adam(
        [parameter for _, parameter in active_named_parameters(nested)],
        lr=learning_rate_for_epoch(config, 1),
    )
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
            dynamic = dynamic_batch_v05(
                "classic_lstm_256",
                forcing,
                basin_index,
                target_index,
            )
            target = discharge[basin_index, target_index]
            loss_weights = 1.0 / torch.square(raw_q_std[basin_index] + 0.1)
            report = lockstep_train_step(
                classic=classic,
                nested=nested,
                classic_optimizer=classic_optimizer,
                nested_optimizer=nested_optimizer,
                dynamic=dynamic,
                statics=statics[basin_index],
                target=target,
                loss_weights=loss_weights,
                basin_indices=(basin_index, basin_index.clone()),
                target_indices=(target_index, target_index.clone()),
                gradient_clip=float(config["gradient_clip"]),
            )
            losses.append(report["loss"])
            optimizer_steps_total += 1
        if not losses:
            raise RuntimeError("strict reproduction produced no optimizer steps")
        final_losses = losses
        epoch_row = {
            "epoch": epoch,
            "learning_rate": learning_rate,
            "mean_loss": float(np.mean(losses)),
            "optimizer_steps_total": optimizer_steps_total,
            "status": "exact",
        }
        epoch_rows.append(epoch_row)
        print(json.dumps(epoch_row, sort_keys=True), flush=True)

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
    prediction_parts = []
    validation_batch_size = int(config["validation_batch_size"])
    for start in range(0, len(validation_basins), validation_batch_size):
        basin_numpy = validation_basins[start:start + validation_batch_size]
        target_numpy = validation_times[start:start + validation_batch_size]
        basin_index = torch.tensor(basin_numpy, device=torch_device)
        target_index = torch.tensor(target_numpy, device=torch_device)
        dynamic = dynamic_batch_v05(
            "classic_lstm_256",
            forcing,
            basin_index,
            target_index,
        )
        classic_prediction, nested_prediction = exact_evaluation_predictions(
            classic,
            nested,
            [(dynamic, statics[basin_index])],
        )
        classic_qsim = (
            classic_prediction.detach().cpu().numpy() * float(scaler["q_scale"])
            + float(scaler["q_center"])
        )
        nested_qsim = (
            nested_prediction.detach().cpu().numpy() * float(scaler["q_scale"])
            + float(scaler["q_center"])
        )
        prediction_parts.append(pd.DataFrame({
            "basin": [pack.basins[index] for index in basin_numpy],
            "date": pack.dates[target_numpy].strftime("%Y-%m-%d"),
            "qobs": pack.discharge[basin_numpy, target_numpy],
            "qsim_classic": classic_qsim,
            "qsim_nested": nested_qsim,
        }))
    predictions = pd.concat(prediction_parts, ignore_index=True)
    predictions = predictions.sort_values(["basin", "date"]).reset_index(drop=True)
    expected_rows = 43_860 if config["mode"] == "pilot" else int(config["limit_validation_samples"])
    if len(predictions) != expected_rows:
        raise ValueError(f"validation prediction count must be {expected_rows}, got {len(predictions)}")
    classic_values = predictions["qsim_classic"].to_numpy(dtype=np.float32)
    nested_values = predictions["qsim_nested"].to_numpy(dtype=np.float32)
    if not np.array_equal(classic_values, nested_values):
        raise StrictNestingMismatch("final validation predictions mismatch")

    historical_reference_checked = config["mode"] == "pilot"
    historical_reference_exact = None
    historical_reference_maximum_difference = None
    if historical_reference_checked:
        reference_run = _REPO / config["reference_run_dir"]
        reference_checkpoint = reference_run / "checkpoint.pt"
        reference_predictions_path = reference_run / "predictions.csv"
        if _sha256(reference_checkpoint) != config["reference_checkpoint_sha256"]:
            raise ValueError("historical reference checkpoint SHA-256 mismatch")
        if _sha256(reference_predictions_path) != config["reference_predictions_sha256"]:
            raise ValueError("historical reference predictions SHA-256 mismatch")
        reference_predictions = pd.read_csv(reference_predictions_path, dtype={"basin": str})
        reference_predictions = reference_predictions.sort_values(["basin", "date"]).reset_index(drop=True)
        if not predictions[["basin", "date"]].equals(reference_predictions[["basin", "date"]]):
            raise ValueError("fresh and historical classic prediction keys differ")
        reference_values = reference_predictions["qsim"].to_numpy(dtype=np.float32)
        historical_reference_exact = bool(np.array_equal(classic_values, reference_values))
        historical_reference_maximum_difference = float(np.max(np.abs(
            classic_values.astype(np.float64) - reference_values.astype(np.float64)
        )))

    _atomic_frame(output_dir / "predictions.csv", predictions)
    reloaded_predictions = pd.read_csv(output_dir / "predictions.csv", dtype={"basin": str})
    metrics = _paired_metrics(reloaded_predictions)
    _atomic_frame(output_dir / "per_basin_metrics.csv", metrics)
    active_names = [name for name, _ in active_named_parameters(classic)]
    _atomic_checkpoint(
        output_dir / "checkpoint.pt",
        {
            "classic_state_dict": classic.state_dict(),
            "nested_state_dict": nested.state_dict(),
            "classic_optimizer_state_dict": classic_optimizer.state_dict(),
            "nested_optimizer_state_dict": nested_optimizer.state_dict(),
            "active_parameter_names": active_names,
            "scaler": scaler,
            "seed": seed,
        },
    )
    status = (
        "complete_exact"
        if historical_reference_exact is not False
        else "historical_reference_mismatch"
    )
    summary = {
        "status": status,
        "lockstep_exact": True,
        "historical_reference_checked": historical_reference_checked,
        "historical_reference_exact": historical_reference_exact,
        "historical_reference_maximum_prediction_absolute_difference": (
            historical_reference_maximum_difference
        ),
        "maximum_prediction_absolute_difference": float(np.max(np.abs(
            classic_values.astype(np.float64) - nested_values.astype(np.float64)
        ))),
        "n_validation_predictions": int(len(predictions)),
        "median_nse": median_nse_by_variant(metrics),
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
        **summary,
        "experiment_id": config["experiment_id"],
        "experiment_family": config["experiment_family"],
        "seed": seed,
        "epochs": int(config["epochs"]),
        "active_parameter_count": 297_217,
        "optimizer_steps_total": optimizer_steps_total,
        "final_training_loss": float(np.mean(final_losses)),
        "n_training_samples": int(len(train_basins)),
        "epoch_trace": epoch_rows,
        "post_build_rng_sha256": post_build_rng,
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
    validate_strict_config_v06(config)
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
    manifest = run_strict_reproduction_v06(
        pack=pack,
        config=config,
        output_dir=_REPO / config["results_root"],
        device=args.device,
    )
    print(json.dumps(manifest, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()

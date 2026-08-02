"""Full zero-tolerance strict-nesting training for formal version 09."""
from __future__ import annotations

from dataclasses import dataclass
import math
from pathlib import Path
from typing import Callable, Mapping

import numpy as np
import torch
from torch import nn

from artifact_v09 import (
    array_payload_sha256,
    canonical_sha256,
    exact_file_inventory,
    sha256_file,
    write_json_atomic,
)
from formal_training_data_v09 import (
    FormalTrainingInputsV09,
    epoch_order_v09,
    load_training_batch_v09,
    ordered_training_keys_v09,
    permutation_sha256_v09,
)
from formal_v09_protocol import learning_rate_for_epoch_v09, validate_protocol_v09
from models_formal_v09 import build_model_v09
from strict_nesting_formal_v09 import lockstep_train_step_v09
from train_strict_v06 import active_named_parameters, assert_parameter_sequence_equal


@dataclass(frozen=True)
class StrictExecutionSpecV09:
    epochs: int
    batch_size: int
    checkpoint_epochs: tuple[int, ...]
    expected_samples: int
    expected_steps_per_epoch: int
    formal: bool = False


def _validate_spec(spec: StrictExecutionSpecV09) -> None:
    if spec.epochs <= 0 or not 1 <= spec.batch_size <= 256:
        raise ValueError("strict execution epochs or batch size is invalid")
    if tuple(sorted(set(spec.checkpoint_epochs))) != spec.checkpoint_epochs:
        raise ValueError("strict checkpoint epochs must be unique and ordered")
    if not spec.checkpoint_epochs or spec.checkpoint_epochs[-1] != spec.epochs:
        raise ValueError("strict checkpoints must include the final epoch")
    if any(epoch < 1 or epoch > spec.epochs for epoch in spec.checkpoint_epochs):
        raise ValueError("strict checkpoint epoch is outside execution")
    expected_steps = math.ceil(spec.expected_samples / spec.batch_size)
    if spec.expected_samples <= 0 or spec.expected_steps_per_epoch != expected_steps:
        raise ValueError("strict expected sample or step count is inconsistent")


def _formal_spec(protocol: Mapping) -> StrictExecutionSpecV09:
    validate_protocol_v09(protocol)
    spec = StrictExecutionSpecV09(
        epochs=int(protocol["epochs"]),
        batch_size=int(protocol["batch_size"]),
        checkpoint_epochs=(10, 20, 30),
        expected_samples=int(protocol["expected_training_samples"]),
        expected_steps_per_epoch=int(protocol["optimizer_steps_per_epoch"]),
        formal=True,
    )
    _validate_spec(spec)
    return spec


def _save_checkpoint(
    path: Path,
    *,
    epoch: int,
    classic: nn.Module,
    nested: nn.Module,
    classic_optimizer: torch.optim.Optimizer,
    nested_optimizer: torch.optim.Optimizer,
    permutation_sha256: str,
) -> None:
    if path.exists():
        raise FileExistsError(f"strict checkpoint already exists: {path}")
    torch.save(
        {
            "schema": "historical_multiscale_formal_v09_strict_checkpoint_v1",
            "epoch": int(epoch),
            "classic_state_dict": classic.state_dict(),
            "nested_state_dict": nested.state_dict(),
            "classic_optimizer_state_dict": classic_optimizer.state_dict(),
            "nested_optimizer_state_dict": nested_optimizer.state_dict(),
            "permutation_sha256": permutation_sha256,
        },
        path,
    )


def predict_strict_pair_v09(
    classic: nn.Module,
    nested: nn.Module,
    inputs: FormalTrainingInputsV09,
    *,
    batch_size: int,
    device: str | torch.device,
    runtime=None,
) -> tuple[np.ndarray, np.ndarray]:
    """Stream every training key in frozen basin-major order."""
    basin_keys, target_keys = ordered_training_keys_v09(inputs)
    classic_predictions = np.empty(len(basin_keys), dtype=np.float32)
    nested_predictions = np.empty(len(basin_keys), dtype=np.float32)
    classic.eval()
    nested.eval()
    with torch.no_grad():
        for start in range(0, len(basin_keys), batch_size):
            stop = min(start + batch_size, len(basin_keys))
            batch = load_training_batch_v09(
                inputs,
                basin_keys[start:stop],
                target_keys[start:stop],
                variant="classic_lstm_256_clean",
                device=device,
            )
            reference = classic(batch.dynamic, batch.statics).prediction
            candidate = nested(batch.dynamic, batch.statics).prediction
            if not torch.equal(reference, candidate):
                maximum = float((reference - candidate).abs().max().cpu())
                raise RuntimeError(f"strict final prediction mismatch; max abs {maximum}")
            classic_predictions[start:stop] = reference.detach().cpu().numpy()
            nested_predictions[start:stop] = candidate.detach().cpu().numpy()
            if runtime is not None and (start // batch_size) % 64 == 0:
                runtime.checkpoint()
    return classic_predictions, nested_predictions


def _run_strict_training_v09(
    inputs: FormalTrainingInputsV09,
    *,
    protocol: Mapping,
    output_dir: str | Path,
    device: str | torch.device,
    execution_spec: StrictExecutionSpecV09,
    model_builder: Callable[[str, int], nn.Module] = build_model_v09,
    runtime=None,
) -> dict:
    """Injectable strict runner used by synthetic tests and the formal wrapper."""
    _validate_spec(execution_spec)
    output_dir = Path(output_dir)
    if output_dir.exists():
        raise FileExistsError(f"strict output already exists: {output_dir}")
    output_dir.mkdir(parents=True, exist_ok=False)
    basin_keys, target_keys = ordered_training_keys_v09(inputs)
    if len(basin_keys) != execution_spec.expected_samples:
        raise ValueError("strict training sample count drift")

    seed = 100
    torch_device = torch.device(device)
    classic = model_builder("classic_lstm_256_clean", seed).to(torch_device)
    nested = model_builder("nested_history_disabled", seed).to(torch_device)
    classic_parameters = active_named_parameters(classic)
    nested_parameters = active_named_parameters(nested)
    assert_parameter_sequence_equal(classic_parameters, nested_parameters)
    classic_optimizer = torch.optim.Adam([parameter for _, parameter in classic_parameters], lr=0.001)
    nested_optimizer = torch.optim.Adam([parameter for _, parameter in nested_parameters], lr=0.001)
    torch.manual_seed(seed * 1_000_003 + 900_001)
    if torch_device.type == "cuda":
        torch.cuda.manual_seed(seed * 1_000_003 + 900_001)

    epoch_trace = []
    optimizer_steps_total = 0
    checkpoint_names = []
    for epoch in range(1, execution_spec.epochs + 1):
        learning_rate = learning_rate_for_epoch_v09(epoch)
        for optimizer in (classic_optimizer, nested_optimizer):
            for group in optimizer.param_groups:
                group["lr"] = learning_rate
        order = epoch_order_v09(len(basin_keys), seed=seed, epoch=epoch)
        order_sha256 = permutation_sha256_v09(order)
        losses = []
        steps = 0
        for start in range(0, len(order), execution_spec.batch_size):
            selection = order[start:start + execution_spec.batch_size]
            batch = load_training_batch_v09(
                inputs,
                basin_keys[selection],
                target_keys[selection],
                variant="classic_lstm_256_clean",
                device=torch_device,
            )
            weights = torch.reciprocal(torch.square(batch.raw_per_basin_std + 0.1))
            report = lockstep_train_step_v09(
                classic,
                nested,
                classic_optimizer,
                nested_optimizer,
                batch.dynamic,
                batch.statics,
                batch.target,
                weights,
                basin_indices=(
                    torch.from_numpy(batch.basin_indices.copy()),
                    torch.from_numpy(batch.basin_indices.copy()),
                ),
                target_indices=(
                    torch.from_numpy(batch.target_indices.copy()),
                    torch.from_numpy(batch.target_indices.copy()),
                ),
                dropout_context=(seed, epoch, steps),
                gradient_clip=1.0,
            )
            losses.append(report["loss"])
            steps += 1
            optimizer_steps_total += 1
            if runtime is not None and steps % 64 == 0:
                runtime.checkpoint()
        if steps != execution_spec.expected_steps_per_epoch:
            raise RuntimeError("strict optimizer step count drift")
        epoch_trace.append({
            "epoch": epoch,
            "learning_rate": learning_rate,
            "permutation_sha256": order_sha256,
            "optimizer_steps": steps,
            "mean_training_loss": float(np.mean(np.asarray(losses, dtype=np.float64))),
        })
        if epoch in execution_spec.checkpoint_epochs:
            checkpoint_name = f"checkpoint_epoch{epoch:03d}.pt"
            _save_checkpoint(
                output_dir / checkpoint_name,
                epoch=epoch,
                classic=classic,
                nested=nested,
                classic_optimizer=classic_optimizer,
                nested_optimizer=nested_optimizer,
                permutation_sha256=order_sha256,
            )
            checkpoint_names.append(checkpoint_name)
        if runtime is not None:
            runtime.checkpoint()

    classic_predictions, nested_predictions = predict_strict_pair_v09(
        classic,
        nested,
        inputs,
        batch_size=execution_spec.batch_size,
        device=torch_device,
        runtime=runtime,
    )
    classic_name = "classic_training_predictions.float32.npy"
    nested_name = "nested_training_predictions.float32.npy"
    np.save(output_dir / classic_name, classic_predictions, allow_pickle=False)
    np.save(output_dir / nested_name, nested_predictions, allow_pickle=False)
    maximum_difference = float(
        np.max(np.abs(classic_predictions.astype(np.float64) - nested_predictions.astype(np.float64))))
    if maximum_difference != 0.0:
        raise RuntimeError("strict final prediction maximum difference is nonzero")

    manifest = {
        "schema": "historical_multiscale_formal_v09_strict_run_v1",
        "status": "strict_nesting_complete",
        "protocol_canonical_sha256": canonical_sha256(protocol),
        "formal_execution": execution_spec.formal,
        "seed": seed,
        "epochs": execution_spec.epochs,
        "batch_size": execution_spec.batch_size,
        "training_samples": len(basin_keys),
        "optimizer_steps_per_epoch": execution_spec.expected_steps_per_epoch,
        "optimizer_steps_total": optimizer_steps_total,
        "checkpoint_epochs": list(execution_spec.checkpoint_epochs),
        "checkpoint_files": checkpoint_names,
        "epoch_trace": epoch_trace,
        "maximum_prediction_difference": maximum_difference,
        "classic_prediction_payload_sha256": array_payload_sha256(classic_predictions),
        "nested_prediction_payload_sha256": array_payload_sha256(nested_predictions),
        "input_bindings": {
            "input_seal_sha256": inputs.input_seal_sha256,
            "input_external_audit_sha256": inputs.external_audit_sha256,
            "trusted_source_audit_sha256": inputs.trusted_source_audit_sha256,
        },
        "formal_evaluation_observation_reads": 0,
    }
    manifest_name = "manifest.json"
    write_json_atomic(output_dir / manifest_name, manifest)
    sealed_names = (*checkpoint_names, classic_name, nested_name, manifest_name)
    sealed_files = exact_file_inventory(output_dir, sealed_names)
    seal = {
        "schema": "historical_multiscale_formal_v09_strict_seal_v1",
        "status": "sealed",
        "sealed_files": sealed_files,
        "sealed_files_sha256": canonical_sha256(sealed_files),
        "manifest_sha256": sha256_file(output_dir / manifest_name),
    }
    write_json_atomic(output_dir / "seal.json", seal)
    return manifest


def run_strict_training_v09(
    inputs: FormalTrainingInputsV09,
    *,
    protocol: Mapping,
    output_dir: str | Path,
    device: str | torch.device,
    runtime,
) -> dict:
    """Run the only formal seed-100 strict stage under a live guarded runtime."""
    spec = _formal_spec(protocol)
    if runtime is None or not runtime.is_valid_for(
            "training",
            run_id="R09-NEST-S100",
            seed=100,
            variant="strict_nesting_pair",
            output_root=output_dir,
    ):
        raise ValueError("formal strict training requires a live training runtime")
    return _run_strict_training_v09(
        inputs,
        protocol=protocol,
        output_dir=output_dir,
        device=device,
        execution_spec=spec,
        model_builder=build_model_v09,
        runtime=runtime,
    )

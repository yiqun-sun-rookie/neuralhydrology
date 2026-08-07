"""Formal version-09 main-training primitives.

Stage S1 of `docs/plans/2026-08-07-id26-v09-main-training-implementation.md`: the frozen
24-run order and the dropout RNG streams. The single-run trainer itself lands in S2.

The run order is frozen twice on purpose -- here as data, and in
``stage_authorization_v09.MAIN_ALLOWED_RUNS`` as code. `validate_run_order_v09` refuses to
accept one without the other, so an edit to either side fails before any training starts.
"""
from __future__ import annotations

from collections.abc import Mapping, Sequence
from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path

import torch

import numpy as np

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
from formal_v09_protocol import learning_rate_for_epoch_v09
from models_formal_v09 import VARIANTS_FORMAL_V09, _EXPECTED_TRAINABLE_COUNTS, build_model_v09
from train_strict_formal_v09 import StrictExecutionSpecV09, _formal_spec as _frozen_execution_spec_v09
from train_strict_v06 import active_named_parameters

_SCHEMA = "historical_multiscale_formal_v09_run_order_v1"
_SCOPE = "FORMAL-MAIN-24"
_EXPECTED_RUNS = 24
_RUNS_PER_FAMILY = 8
_RUNS_PER_SEED = 3
# The strict-nesting stage already burned this stream in (train_strict_formal_v09 line 163).
# The main runs must use the identical formula or the two stages diverge silently.
_DROPOUT_MULTIPLIER = 1_000_003
_DROPOUT_OFFSET = 900_001


@dataclass(frozen=True)
class FormalRunSpecV09:
    """One of the 24 frozen main-training runs."""

    position: int
    seed: int
    family: str
    run_id: str
    variant: str
    trainable_parameters: int
    results_root: str


def _require_mapping(value, label: str) -> Mapping:
    if not isinstance(value, Mapping):
        raise ValueError(f"run order {label} must be an object")
    return value


def _validate_families_v09(order: Mapping) -> dict[str, dict]:
    families = _require_mapping(order.get("families"), "families")
    if len(families) != 3:
        raise ValueError("run order must register exactly three model families")
    resolved: dict[str, dict] = {}
    roots: set[str] = set()
    for name, entry in families.items():
        entry = _require_mapping(entry, f"family {name}")
        variant = entry.get("variant")
        if variant not in VARIANTS_FORMAL_V09:
            raise ValueError(f"run order family {name} names an unregistered variant")
        expected = _EXPECTED_TRAINABLE_COUNTS[variant]
        if entry.get("trainable_parameters") != expected:
            raise ValueError(
                f"run order family {name} trainable parameter count disagrees with the model registry")
        root = entry.get("results_root")
        if not isinstance(root, str) or not root:
            raise ValueError(f"run order family {name} results root is invalid")
        if root in roots:
            raise ValueError("run order families must not share a results root")
        roots.add(root)
        resolved[name] = {
            "variant": variant,
            "trainable_parameters": expected,
            "results_root": root,
        }
    return resolved


def validate_run_order_v09(order: Mapping) -> tuple[FormalRunSpecV09, ...]:
    """Accept only the exact frozen 24-run order; never mutate the input."""
    order = _require_mapping(order, "document")
    if order.get("schema") != _SCHEMA:
        raise ValueError("run order schema drift")
    if order.get("scope") != _SCOPE:
        raise ValueError("run order scope drift")

    families = _validate_families_v09(order)

    seeds = order.get("seeds")
    if not isinstance(seeds, Sequence) or isinstance(seeds, (str, bytes)):
        raise ValueError("run order seed list is invalid")
    seeds = tuple(seeds)
    if len(seeds) != 8 or len(set(seeds)) != 8 or any(not isinstance(s, int) for s in seeds):
        raise ValueError("run order must register exactly eight unique integer seeds")

    runs = order.get("runs")
    if not isinstance(runs, Sequence) or isinstance(runs, (str, bytes)):
        raise ValueError("run order runs must be a list")
    if len(runs) != _EXPECTED_RUNS:
        raise ValueError(f"run order must contain exactly {_EXPECTED_RUNS} runs")

    specs: list[FormalRunSpecV09] = []
    seen_ids: set[str] = set()
    for index, entry in enumerate(runs, start=1):
        entry = _require_mapping(entry, f"run {index}")
        if entry.get("position") != index:
            raise ValueError(f"run order position drift at slot {index}")
        seed = entry.get("seed")
        if seed not in seeds:
            raise ValueError(f"run order seed at position {index} is not in the frozen seed list")
        family = entry.get("family")
        if family not in families:
            raise ValueError(f"run order family at position {index} is not registered")
        run_id = entry.get("run_id")
        expected_id = f"{family}-S{seed}"
        if run_id != expected_id:
            raise ValueError(f"run order run identifier at position {index} disagrees with its family and seed")
        if run_id in seen_ids:
            raise ValueError(f"run order run identifier {run_id} is duplicated")
        seen_ids.add(run_id)
        specs.append(
            FormalRunSpecV09(
                position=index,
                seed=int(seed),
                family=family,
                run_id=run_id,
                variant=families[family]["variant"],
                trainable_parameters=families[family]["trainable_parameters"],
                results_root=families[family]["results_root"],
            ))

    family_counts: dict[str, int] = {}
    seed_counts: dict[int, int] = {}
    for spec in specs:
        family_counts[spec.family] = family_counts.get(spec.family, 0) + 1
        seed_counts[spec.seed] = seed_counts.get(spec.seed, 0) + 1
    if any(count != _RUNS_PER_FAMILY for count in family_counts.values()) or len(family_counts) != 3:
        raise ValueError(f"each model family must appear exactly {_RUNS_PER_FAMILY} times")
    if any(count != _RUNS_PER_SEED for count in seed_counts.values()) or len(seed_counts) != 8:
        raise ValueError(f"each seed must appear exactly {_RUNS_PER_SEED} times")

    _assert_matches_authorization_v09(specs)
    return tuple(specs)


def _assert_matches_authorization_v09(specs: Sequence[FormalRunSpecV09]) -> None:
    """Cross-check the data copy of the order against the code copy."""
    from stage_authorization_v09 import MAIN_ALLOWED_RUNS

    if tuple(spec.run_id for spec in specs) != tuple(MAIN_ALLOWED_RUNS):
        raise ValueError("run order disagrees with the authorized run identifiers")


def load_run_order_v09(path: str | Path) -> tuple[FormalRunSpecV09, ...]:
    """Load and validate the frozen order from disk."""
    path = Path(os.path.abspath(path))
    return validate_run_order_v09(json.loads(path.read_text(encoding="utf-8")))


def dropout_seed_v09(seed: int) -> int:
    """Derive the dropout stream seed; identical for all three families of one seed."""
    seed = int(seed)
    if seed <= 0:
        raise ValueError("training seed must be a positive integer")
    return seed * _DROPOUT_MULTIPLIER + _DROPOUT_OFFSET


def _state_sha256(state: torch.Tensor) -> str:
    return hashlib.sha256(state.cpu().numpy().tobytes()).hexdigest()


def reset_training_dropout_rng_v09(seed: int) -> dict:
    """Reset the CPU and every CUDA dropout stream, then report their state hashes.

    Called after the model and optimizer are constructed so that model initialisation never
    consumes the dropout stream; the three families of one seed then enter their first batch
    with byte-identical RNG state.
    """
    dropout_seed = dropout_seed_v09(seed)
    torch.manual_seed(dropout_seed)
    cuda_hash = None
    if torch.cuda.is_available():
        torch.cuda.manual_seed_all(dropout_seed)
        states = torch.cuda.get_rng_state_all()
        cuda_hash = hashlib.sha256(b"".join(s.cpu().numpy().tobytes() for s in states)).hexdigest()
    return {
        "dropout_seed": dropout_seed,
        "cpu_state_sha256": _state_sha256(torch.get_rng_state()),
        "cuda_state_sha256": cuda_hash,
    }


# --------------------------------------------------------------------------------------
# S2: single-run trainer
# --------------------------------------------------------------------------------------

_HISTORY_VARIANT = "continuous_multiscale_history"
_HISTORY_GATES = ("hidden_gate", "cell_gate")
# The history encoder is gradient-dead while both gates are exactly zero; Adam must lift it
# off zero within this many steps or the history path is wired wrong.
_HISTORY_WAKE_BY_STEP = 3


class FormalTrainingError(RuntimeError):
    """Raised when a formal main-training invariant fails."""


def _gradient_norm(parameters) -> float:
    total = 0.0
    for parameter in parameters:
        if parameter.grad is None:
            return float("nan")
        total += float(parameter.grad.detach().double().pow(2).sum().cpu())
    return float(total ** 0.5)


def _history_health_v09(model: torch.nn.Module, step_index: int) -> dict:
    """Read-only view of the gradients this backward already produced; no second forward."""
    gates = [getattr(model, name) for name in _HISTORY_GATES]
    encoder = list(model.history_encoder.parameters())
    with torch.no_grad():
        gate_absolute_maximum = max(float(g.detach().abs().max().cpu()) for g in gates)
    gate_grads_present = all(g.grad is not None for g in gates)
    encoder_grads_present = all(p.grad is not None for p in encoder)
    return {
        "step": int(step_index),
        "gate_absolute_maximum": gate_absolute_maximum,
        "gate_gradient_norm": _gradient_norm(gates) if gate_grads_present else float("nan"),
        "history_encoder_gradient_norm": _gradient_norm(encoder) if encoder_grads_present else float("nan"),
        "gate_gradients_present": gate_grads_present,
        "history_encoder_gradients_present": encoder_grads_present,
    }


def _assert_history_health_v09(health: dict) -> None:
    """Enforce the pre-registered wiring facts about the two history gates."""
    step = health["step"]
    if not health["gate_gradients_present"] or not health["history_encoder_gradients_present"]:
        raise FormalTrainingError(f"history gradients missing at step {step}")
    gate_norm = health["gate_gradient_norm"]
    encoder_norm = health["history_encoder_gradient_norm"]
    if not (np.isfinite(gate_norm) and np.isfinite(encoder_norm)):
        raise FormalTrainingError(f"history gradients are not finite at step {step}")
    if step == 1:
        if health["gate_absolute_maximum"] != 0.0:
            raise FormalTrainingError("history gates must be exactly zero before the first update")
        if encoder_norm != 0.0:
            raise FormalTrainingError(
                "history encoder gradient must be exactly zero while both gates are zero")
        if not gate_norm > 0.0:
            raise FormalTrainingError("history gate gradient must be strictly positive at the first update")


def single_train_step_v09(
    model: torch.nn.Module,
    optimizer: torch.optim.Optimizer,
    dynamic: Mapping[str, torch.Tensor],
    statics: torch.Tensor,
    target: torch.Tensor,
    loss_weights: torch.Tensor,
    *,
    dropout_context: tuple[int, int, int],
    gradient_clip: float,
    step_index: int,
    history_model: bool = False,
    record: bool = False,
) -> dict:
    """One Adam update for exactly one model, with pure-observation health checks."""
    parameters = active_named_parameters(model)
    if not parameters:
        raise FormalTrainingError("formal training requires active parameters")
    model.train()
    optimizer.zero_grad(set_to_none=True)
    prediction = model(dynamic, statics, dropout_context=dropout_context).prediction
    loss = (loss_weights * torch.square(prediction - target)).mean()
    if not torch.isfinite(loss):
        raise FormalTrainingError(f"non-finite training loss at step {step_index}")
    loss.backward()

    health = None
    if history_model:
        health = _history_health_v09(model, step_index)
        _assert_history_health_v09(health)

    norm = torch.nn.utils.clip_grad_norm_([parameter for _, parameter in parameters], float(gradient_clip))
    if not torch.isfinite(norm):
        raise FormalTrainingError(f"non-finite gradient norm at step {step_index}")
    optimizer.step()
    report = {
        "loss": float(loss.detach().cpu()),
        "gradient_norm": float(norm.detach().cpu()),
    }
    if record and health is not None:
        report["history_health"] = health
    return report


def _save_run_checkpoint_v09(path: Path, *, epoch: int, model, optimizer, permutation_sha256: str) -> None:
    if path.exists():
        raise FileExistsError(f"formal checkpoint already exists: {path}")
    torch.save(
        {
            "schema": "historical_multiscale_formal_v09_run_checkpoint_v1",
            "epoch": int(epoch),
            "model_state_dict": model.state_dict(),
            "optimizer_state_dict": optimizer.state_dict(),
            "permutation_sha256": permutation_sha256,
        },
        path,
    )


def run_training_v09(
    inputs: FormalTrainingInputsV09,
    *,
    variant: str,
    seed: int,
    output_dir: str | Path,
    device: str | torch.device,
    execution_spec: StrictExecutionSpecV09 | None = None,
    protocol: Mapping | None = None,
    model_builder=build_model_v09,
    record_health: bool = True,
    runtime=None,
) -> dict:
    """Train exactly one of the 24 formal runs into a fresh output directory."""
    if variant not in VARIANTS_FORMAL_V09 or variant == "nested_history_disabled":
        raise ValueError(f"unsupported formal main-training variant: {variant}")
    seed = int(seed)
    if execution_spec is None:
        if protocol is None:
            raise ValueError("formal training needs either an execution spec or the protocol")
        execution_spec = _frozen_execution_spec_v09(protocol)
    output_dir = Path(output_dir)
    if output_dir.exists():
        raise FileExistsError(f"formal training output already exists: {output_dir}")

    basin_keys, target_keys = ordered_training_keys_v09(inputs)
    if len(basin_keys) != execution_spec.expected_samples:
        raise FormalTrainingError("formal training sample count drift")

    torch_device = torch.device(device)
    model = model_builder(variant, seed).to(torch_device)
    parameters = active_named_parameters(model)
    trainable = sum(p.numel() for _, p in parameters)
    if trainable != _EXPECTED_TRAINABLE_COUNTS[variant]:
        raise FormalTrainingError(f"formal training parameter count drift for {variant}")
    optimizer = torch.optim.Adam([parameter for _, parameter in parameters], lr=0.001)
    # Reset the dropout stream only after the model and optimizer exist, so initialisation
    # never consumes it and all three families of one seed start byte-identical.
    rng_binding = reset_training_dropout_rng_v09(seed)

    history_model = variant == _HISTORY_VARIANT
    output_dir.mkdir(parents=True, exist_ok=False)
    epoch_trace = []
    health_trace = []
    checkpoint_names = []
    optimizer_steps_total = 0
    global_step = 0
    history_awake_step = None

    for epoch in range(1, execution_spec.epochs + 1):
        learning_rate = learning_rate_for_epoch_v09(epoch)
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
                variant=variant,
                device=torch_device,
            )
            weights = torch.reciprocal(torch.square(batch.raw_per_basin_std + 0.1))
            global_step += 1
            report = single_train_step_v09(
                model,
                optimizer,
                batch.dynamic,
                batch.statics,
                batch.target,
                weights,
                dropout_context=(seed, epoch, steps),
                gradient_clip=1.0,
                step_index=global_step,
                history_model=history_model,
                record=record_health,
            )
            if history_model:
                health = report.get("history_health")
                if health is not None and epoch == 1 and health["step"] <= _HISTORY_WAKE_BY_STEP:
                    health_trace.append(health)
                if (history_awake_step is None and global_step > 1 and history_model
                        and report.get("history_health", {}).get("history_encoder_gradient_norm", 0.0) > 0.0):
                    history_awake_step = global_step
            losses.append(report["loss"])
            steps += 1
            optimizer_steps_total += 1
            if runtime is not None and steps % 64 == 0:
                runtime.checkpoint()
        if steps != execution_spec.expected_steps_per_epoch:
            raise FormalTrainingError("formal training optimizer step count drift")
        if history_model and epoch == 1 and record_health:
            if history_awake_step is None or history_awake_step > _HISTORY_WAKE_BY_STEP:
                raise FormalTrainingError(
                    f"history encoder produced no nonzero gradient by step {_HISTORY_WAKE_BY_STEP}")
        epoch_trace.append({
            "epoch": epoch,
            "learning_rate": learning_rate,
            "permutation_sha256": order_sha256,
            "optimizer_steps": steps,
            "mean_training_loss": float(np.mean(np.asarray(losses, dtype=np.float64))),
        })
        if epoch in execution_spec.checkpoint_epochs:
            checkpoint_name = f"checkpoint_epoch{epoch:03d}.pt"
            _save_run_checkpoint_v09(
                output_dir / checkpoint_name,
                epoch=epoch,
                model=model,
                optimizer=optimizer,
                permutation_sha256=order_sha256,
            )
            checkpoint_names.append(checkpoint_name)
        if runtime is not None:
            runtime.checkpoint()

    manifest = {
        "schema": "historical_multiscale_formal_v09_main_run_v1",
        "status": "formal_training_complete",
        "formal_execution": execution_spec.formal,
        "variant": variant,
        "seed": seed,
        "epochs": execution_spec.epochs,
        "batch_size": execution_spec.batch_size,
        "training_samples": len(basin_keys),
        "trainable_parameters": trainable,
        "optimizer_steps_per_epoch": execution_spec.expected_steps_per_epoch,
        "optimizer_steps_total": optimizer_steps_total,
        "checkpoint_epochs": list(execution_spec.checkpoint_epochs),
        "checkpoint_files": checkpoint_names,
        "epoch_trace": epoch_trace,
        "dropout_rng_binding": rng_binding,
        "history_health_trace": health_trace,
        "history_encoder_first_nonzero_gradient_step": history_awake_step,
        "input_bindings": {
            "input_seal_sha256": inputs.input_seal_sha256,
            "input_external_audit_sha256": inputs.external_audit_sha256,
            "trusted_source_audit_sha256": inputs.trusted_source_audit_sha256,
        },
        "validation_metrics_computed": False,
        "formal_evaluation_observation_reads": 0,
        "formal_period_predictions_generated": False,
    }
    write_json_atomic(output_dir / "manifest.json", manifest)
    sealed_names = (*checkpoint_names, "manifest.json")
    sealed_files = exact_file_inventory(output_dir, sealed_names)
    seal = {
        "schema": "historical_multiscale_formal_v09_main_run_seal_v1",
        "status": "sealed",
        "sealed_files": sealed_files,
        "sealed_files_sha256": canonical_sha256(sealed_files),
        "manifest_sha256": sha256_file(output_dir / "manifest.json"),
    }
    write_json_atomic(output_dir / "seal.json", seal)
    return manifest

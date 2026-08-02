"""Directory-external independent replay of a sealed strict version-09 run."""
from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Callable

import numpy as np
import torch
from torch import nn

from artifact_v09 import (
    assert_no_embedded_seal_entries,
    assert_no_reparse_components,
    assert_no_reparse_tree,
    canonical_sha256,
    sha256_file,
    write_json_atomic,
)
from formal_training_data_v09 import FormalTrainingInputsV09
from formal_training_data_v09 import epoch_order_v09, permutation_sha256_v09
from models_formal_v09 import build_model_v09
from strict_nesting_formal_v09 import assert_reproduced_predictions_v09
from train_strict_formal_v09 import predict_strict_pair_v09
from train_strict_v06 import active_named_parameters, assert_parameter_sequence_equal

_FORMAL_GEOMETRY = {
    "seed": 100,
    "epochs": 30,
    "batch_size": 256,
    "training_samples": 1_745_928,
    "optimizer_steps_per_epoch": 6_821,
    "optimizer_steps_total": 204_630,
    "checkpoint_epochs": [10, 20, 30],
    "checkpoint_files": [
        "checkpoint_epoch010.pt",
        "checkpoint_epoch020.pt",
        "checkpoint_epoch030.pt",
    ],
}


def _verify_sealed_files(run_dir: Path, seal: dict) -> None:
    sealed_files = seal.get("sealed_files")
    if not isinstance(sealed_files, list):
        raise ValueError("strict run seal drift")
    assert_no_embedded_seal_entries(sealed_files)
    if (seal.get("status") != "sealed" or
            seal.get("sealed_files_sha256") != canonical_sha256(sealed_files)):
        raise ValueError("strict run seal drift")
    assert_no_reparse_tree(run_dir)
    expected = {item.get("relative_path") for item in sealed_files}
    actual = {
        path.relative_to(run_dir).as_posix()
        for path in run_dir.rglob("*")
        if path.is_file() and path != run_dir / "seal.json"
    }
    if None in expected or actual != expected:
        raise ValueError("strict run sealed inventory drift")
    for item in sealed_files:
        path = run_dir / item["relative_path"]
        if path.stat().st_size != item.get("size_bytes") or sha256_file(path) != item.get("sha256"):
            raise ValueError(f"strict sealed file drift: {item['relative_path']}")


def _require_sha256(value, label: str) -> None:
    if not isinstance(value, str) or len(value) != 64 or any(
            character not in "0123456789abcdef" for character in value):
        raise ValueError(f"strict {label} is not a SHA-256 digest")


def _validate_manifest_trajectory_v09(manifest: dict) -> list[dict]:
    if manifest.get("schema") != "historical_multiscale_formal_v09_strict_run_v1":
        raise ValueError("strict manifest schema drift")
    if manifest.get("status") != "strict_nesting_complete":
        raise ValueError("strict manifest status drift")
    if manifest.get("formal_evaluation_observation_reads") != 0:
        raise ValueError("strict formal evaluation observation read drift")
    for key in ("seed", "epochs", "batch_size", "training_samples", "optimizer_steps_per_epoch",
                "optimizer_steps_total"):
        if not isinstance(manifest.get(key), int) or isinstance(manifest.get(key), bool):
            raise ValueError(f"strict manifest {key} is invalid")
    if manifest.get("formal_execution") is True:
        for key, expected in _FORMAL_GEOMETRY.items():
            if manifest.get(key) != expected:
                raise ValueError(f"strict formal manifest {key} drift")
        _require_sha256(manifest.get("protocol_canonical_sha256"), "protocol binding")
        bindings = manifest.get("input_bindings")
        if not isinstance(bindings, dict):
            raise ValueError("strict formal input bindings are missing")
        for key in ("input_seal_sha256", "input_external_audit_sha256", "trusted_source_audit_sha256"):
            _require_sha256(bindings.get(key), f"input binding {key}")
    trace = manifest.get("epoch_trace")
    if not isinstance(trace, list) or len(trace) != manifest["epochs"]:
        raise ValueError("strict epoch trace length drift")
    expected_steps = manifest["optimizer_steps_per_epoch"]
    expected_total = manifest["epochs"] * expected_steps
    if manifest["optimizer_steps_total"] != expected_total:
        raise ValueError("strict total optimizer step drift")
    for epoch, row in enumerate(trace, start=1):
        if not isinstance(row, dict) or row.get("epoch") != epoch or row.get("optimizer_steps") != expected_steps:
            raise ValueError(f"strict epoch trace drift at epoch {epoch}")
        expected_hash = permutation_sha256_v09(
            epoch_order_v09(manifest["training_samples"], seed=manifest["seed"], epoch=epoch))
        if row.get("permutation_sha256") != expected_hash:
            raise ValueError(f"strict permutation drift at epoch {epoch}")
    checkpoint_epochs = manifest.get("checkpoint_epochs")
    checkpoint_files = manifest.get("checkpoint_files")
    if (not isinstance(checkpoint_epochs, list) or not isinstance(checkpoint_files, list) or
            len(checkpoint_epochs) != len(checkpoint_files) or not checkpoint_epochs or
            checkpoint_epochs[-1] != manifest["epochs"]):
        raise ValueError("strict checkpoint inventory is invalid")
    expected_files = [f"checkpoint_epoch{epoch:03d}.pt" for epoch in checkpoint_epochs]
    if checkpoint_files != expected_files:
        raise ValueError("strict checkpoint filename drift")
    return trace


def _assert_exact_tree(reference, candidate, label: str) -> None:
    if isinstance(reference, torch.Tensor):
        if not isinstance(candidate,
                          torch.Tensor) or reference.dtype != candidate.dtype or reference.shape != candidate.shape:
            raise ValueError(f"strict {label} tensor structure drift")
        if not torch.equal(reference, candidate):
            raise ValueError(f"strict {label} tensor value drift")
        return
    if isinstance(reference, dict):
        if not isinstance(candidate, dict) or list(reference) != list(candidate):
            raise ValueError(f"strict {label} mapping drift")
        for key in reference:
            _assert_exact_tree(reference[key], candidate[key], f"{label}.{key}")
        return
    if isinstance(reference, (list, tuple)):
        if not isinstance(candidate, type(reference)) or len(reference) != len(candidate):
            raise ValueError(f"strict {label} sequence drift")
        for index, (reference_item, candidate_item) in enumerate(zip(reference, candidate)):
            _assert_exact_tree(reference_item, candidate_item, f"{label}[{index}]")
        return
    if reference != candidate:
        raise ValueError(f"strict {label} value drift")


def _load_and_verify_checkpoints_v09(run_dir: Path, manifest: dict, trace: list[dict], *, device,
                                     model_builder: Callable[[str, int], nn.Module]) -> tuple[nn.Module, nn.Module]:
    final_pair = None
    trace_by_epoch = {row["epoch"]: row for row in trace}
    for epoch, relative_path in zip(manifest["checkpoint_epochs"], manifest["checkpoint_files"]):
        checkpoint = torch.load(run_dir / relative_path, map_location=device, weights_only=False)
        if checkpoint.get("schema") != "historical_multiscale_formal_v09_strict_checkpoint_v1":
            raise ValueError(f"strict checkpoint schema drift at epoch {epoch}")
        if checkpoint.get("epoch") != epoch:
            raise ValueError(f"strict checkpoint epoch drift at epoch {epoch}")
        if checkpoint.get("permutation_sha256") != trace_by_epoch[epoch]["permutation_sha256"]:
            raise ValueError(f"strict checkpoint permutation drift at epoch {epoch}")
        classic = model_builder("classic_lstm_256_clean", manifest["seed"]).to(device)
        nested = model_builder("nested_history_disabled", manifest["seed"]).to(device)
        classic.load_state_dict(checkpoint["classic_state_dict"], strict=True)
        nested.load_state_dict(checkpoint["nested_state_dict"], strict=True)
        assert_parameter_sequence_equal(active_named_parameters(classic), active_named_parameters(nested))
        _assert_exact_tree(
            checkpoint["classic_optimizer_state_dict"],
            checkpoint["nested_optimizer_state_dict"],
            f"optimizer epoch {epoch}",
        )
        final_pair = (classic, nested)
    if final_pair is None:
        raise ValueError("strict checkpoint inventory is missing")
    return final_pair


def audit_strict_run_v09(
    run_dir: str | Path,
    *,
    inputs: FormalTrainingInputsV09,
    device: str | torch.device,
    report_path: str | Path,
    model_builder: Callable[[str, int], nn.Module] = build_model_v09,
) -> dict:
    """Reload the final checkpoint and replay every training-key prediction."""
    raw_run_dir = Path(os.path.abspath(run_dir))
    raw_report_path = Path(os.path.abspath(report_path))
    common_root = Path(os.path.commonpath((raw_run_dir, raw_report_path)))
    assert_no_reparse_components(common_root, raw_run_dir)
    assert_no_reparse_components(common_root, raw_report_path)
    assert_no_reparse_tree(raw_run_dir)
    run_dir = raw_run_dir.resolve()
    report_path = raw_report_path.resolve()
    if report_path == run_dir or run_dir in report_path.parents:
        raise ValueError("strict external audit report must be outside the sealed run")
    seal_path = run_dir / "seal.json"
    manifest_path = run_dir / "manifest.json"
    seal = json.loads(seal_path.read_text(encoding="utf-8"))
    _verify_sealed_files(run_dir, seal)
    if seal.get("manifest_sha256") != sha256_file(manifest_path):
        raise ValueError("strict manifest seal binding drift")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    trace = _validate_manifest_trajectory_v09(manifest)
    classic, nested = _load_and_verify_checkpoints_v09(
        run_dir,
        manifest,
        trace,
        device=device,
        model_builder=model_builder,
    )
    replay_classic, replay_nested = predict_strict_pair_v09(
        classic,
        nested,
        inputs,
        batch_size=int(manifest["batch_size"]),
        device=device,
    )
    stored_classic = np.load(
        run_dir / "classic_training_predictions.float32.npy",
        mmap_mode="r",
        allow_pickle=False,
    )
    stored_nested = np.load(
        run_dir / "nested_training_predictions.float32.npy",
        mmap_mode="r",
        allow_pickle=False,
    )
    assert_reproduced_predictions_v09(
        torch.from_numpy(np.array(stored_classic, copy=True)),
        torch.from_numpy(replay_classic),
    )
    assert_reproduced_predictions_v09(
        torch.from_numpy(np.array(stored_nested, copy=True)),
        torch.from_numpy(replay_nested),
    )
    if replay_classic.tobytes() != replay_nested.tobytes():
        raise ValueError("strict independent replay pair is not byte-identical")
    reference_difference = max(
        float(np.max(np.abs(stored_classic.astype(np.float64) - replay_classic.astype(np.float64)))),
        float(np.max(np.abs(stored_nested.astype(np.float64) - replay_nested.astype(np.float64)))),
    )
    report = {
        "schema": "historical_multiscale_formal_v09_strict_external_audit_v1",
        "status": ("strict_nesting_checkpoint_prediction_replay_passed"
                   if manifest["formal_execution"] else "strict_nesting_synthetic_checkpoint_prediction_replay_passed"),
        "run_seal_sha256": sha256_file(seal_path),
        "run_manifest_sha256": sha256_file(manifest_path),
        "training_samples": int(manifest["training_samples"]),
        "checkpoints_verified": list(manifest["checkpoint_files"]),
        "permutation_hashes_recomputed": len(trace),
        "maximum_pair_difference": 0.0,
        "maximum_reference_difference": reference_difference,
        "formal_evaluation_observation_reads": 0,
    }
    write_json_atomic(report_path, report)
    return report

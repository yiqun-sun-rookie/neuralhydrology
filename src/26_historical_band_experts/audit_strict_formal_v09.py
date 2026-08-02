"""Directory-external independent replay of a sealed strict version-09 run."""
from __future__ import annotations

import json
from pathlib import Path
from typing import Callable

import numpy as np
import torch
from torch import nn

from artifact_v09 import canonical_sha256, sha256_file, write_json_atomic
from formal_training_data_v09 import FormalTrainingInputsV09
from models_formal_v09 import build_model_v09
from strict_nesting_formal_v09 import assert_reproduced_predictions_v09
from train_strict_formal_v09 import predict_strict_pair_v09


def _verify_sealed_files(run_dir: Path, seal: dict) -> None:
    sealed_files = seal.get("sealed_files")
    if (seal.get("status") != "sealed" or not isinstance(sealed_files, list) or
            seal.get("sealed_files_sha256") != canonical_sha256(sealed_files)):
        raise ValueError("strict run seal drift")
    expected = {item.get("relative_path") for item in sealed_files}
    actual = {
        path.relative_to(run_dir).as_posix()
        for path in run_dir.rglob("*")
        if path.is_file() and path.name != "seal.json"
    }
    if None in expected or actual != expected:
        raise ValueError("strict run sealed inventory drift")
    for item in sealed_files:
        path = run_dir / item["relative_path"]
        if path.stat().st_size != item.get("size_bytes") or sha256_file(path) != item.get("sha256"):
            raise ValueError(f"strict sealed file drift: {item['relative_path']}")


def audit_strict_run_v09(
    run_dir: str | Path,
    *,
    inputs: FormalTrainingInputsV09,
    device: str | torch.device,
    report_path: str | Path,
    model_builder: Callable[[str, int], nn.Module] = build_model_v09,
) -> dict:
    """Reload the final checkpoint and replay every training-key prediction."""
    run_dir = Path(run_dir).resolve()
    report_path = Path(report_path).resolve()
    if report_path == run_dir or run_dir in report_path.parents:
        raise ValueError("strict external audit report must be outside the sealed run")
    seal_path = run_dir / "seal.json"
    manifest_path = run_dir / "manifest.json"
    seal = json.loads(seal_path.read_text(encoding="utf-8"))
    _verify_sealed_files(run_dir, seal)
    if seal.get("manifest_sha256") != sha256_file(manifest_path):
        raise ValueError("strict manifest seal binding drift")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("status") != "strict_nesting_complete":
        raise ValueError("strict manifest status drift")
    checkpoints = manifest.get("checkpoint_files")
    if not isinstance(checkpoints, list) or not checkpoints:
        raise ValueError("strict checkpoint inventory is missing")
    checkpoint = torch.load(
        run_dir / checkpoints[-1],
        map_location=device,
        weights_only=False,
    )
    if checkpoint.get("epoch") != manifest.get("epochs"):
        raise ValueError("strict final checkpoint epoch drift")
    seed = int(manifest["seed"])
    classic = model_builder("classic_lstm_256_clean", seed).to(device)
    nested = model_builder("nested_history_disabled", seed).to(device)
    classic.load_state_dict(checkpoint["classic_state_dict"], strict=True)
    nested.load_state_dict(checkpoint["nested_state_dict"], strict=True)
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
        "status": "strict_nesting_external_audit_passed",
        "run_seal_sha256": sha256_file(seal_path),
        "run_manifest_sha256": sha256_file(manifest_path),
        "training_samples": int(manifest["training_samples"]),
        "final_checkpoint": checkpoints[-1],
        "maximum_pair_difference": 0.0,
        "maximum_reference_difference": reference_difference,
        "formal_evaluation_observation_reads": 0,
    }
    write_json_atomic(report_path, report)
    return report

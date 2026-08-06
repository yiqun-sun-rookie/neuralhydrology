"""Read-only bridge from frozen core checkpoints to version-09 model classes."""
from __future__ import annotations

import hashlib
import io
import json
import os
import platform
from pathlib import Path
import subprocess
import sys
from typing import Iterable, Mapping

import numpy as np
import torch
import yaml

from artifact_v09 import assert_no_reparse_components, canonical_sha256, sha256_file, write_json_atomic
from formal_input_contract_v09 import DYNAMIC_COLUMNS_V09
from formal_training_data_v09 import (
    FormalBridgeInputsV09,
    normalize_forcing_batch_v09,
    verify_sealed_bridge_inputs_unchanged_v09,
)
from formal_v09_protocol import validate_protocol_v09
from models_formal_v09 import build_model_v09
from verify_legacy_reference_v09 import verify_legacy_reference_v09

_ACTIVE_TENSORS = (
    "lstm.weight_ih_l0",
    "lstm.weight_hh_l0",
    "lstm.bias_ih_l0",
    "lstm.bias_hh_l0",
    "head.net.0.weight",
    "head.net.0.bias",
)


def _assert_report_outside_protected_paths(report_path: str | Path, protected_roots: Iterable[str | Path]) -> Path:
    raw_report_path = Path(os.path.abspath(report_path))
    for root in protected_roots:
        raw_protected = Path(os.path.abspath(root))
        common_root = Path(os.path.commonpath((raw_protected, raw_report_path)))
        assert_no_reparse_components(common_root, raw_protected)
        assert_no_reparse_components(common_root, raw_report_path)
        protected = raw_protected.resolve()
        report_path = raw_report_path.resolve()
        if report_path == protected or protected in report_path.parents:
            raise ValueError(f"legacy bridge report must be outside protected path: {protected}")
    return raw_report_path.resolve()


def _source_bindings_v09() -> dict[str, str]:
    repo_root = Path(__file__).resolve().parents[2]
    paths = {
        "audit_legacy_checkpoint_bridge_v09.py": Path(__file__).resolve(),
        "formal_training_data_v09.py": Path(__file__).resolve().with_name("formal_training_data_v09.py"),
        "models_formal_v09.py": Path(__file__).resolve().with_name("models_formal_v09.py"),
        "verify_legacy_reference_v09.py": Path(__file__).resolve().with_name("verify_legacy_reference_v09.py"),
        "neuralhydrology/modelzoo/cudalstm.py": repo_root / "neuralhydrology/modelzoo/cudalstm.py",
        "neuralhydrology/modelzoo/inputlayer.py": repo_root / "neuralhydrology/modelzoo/inputlayer.py",
        "neuralhydrology/modelzoo/head.py": repo_root / "neuralhydrology/modelzoo/head.py",
    }
    return {label: sha256_file(path) for label, path in paths.items()}


def _environment_binding_v09(device: str | torch.device) -> dict:
    repo_root = Path(__file__).resolve().parents[2]
    completed = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        cwd=repo_root,
        check=True,
        capture_output=True,
        text=True,
    )
    return {
        "python_version": platform.python_version(),
        "python_executable": str(Path(sys.executable).resolve()),
        "torch_version": torch.__version__,
        "torch_cuda_version": torch.version.cuda,
        "device": str(torch.device(device)),
        "git_head": completed.stdout.strip(),
    }


def _require_checkpoint_state(state: Mapping) -> None:
    if tuple(state) != _ACTIVE_TENSORS or any(not isinstance(state[name], torch.Tensor) for name in _ACTIVE_TENSORS):
        raise ValueError("legacy checkpoint must contain exactly six ordered active tensors")


def _legacy_dynamic_input_names_v09(config, *, expected_count: int) -> tuple[str, ...]:
    """Derive the exact ``x_d`` keys the bound legacy core model requires.

    The keys belong to the hash-bound legacy config, never to the formal protocol: the two
    name the same five Maurer variables in the same order but with different vocabularies
    (``PRCP(mm/day)`` versus ``prcp``). Reading them from the config keeps the bridge bound
    to the bytes whose SHA-256 the protocol already registers.
    """
    names = getattr(config, "dynamic_inputs", None)
    if isinstance(names, dict):
        raise ValueError("legacy bridge requires a single-frequency legacy config")
    if not isinstance(names, (list, tuple)) or not names:
        raise ValueError("legacy config dynamic inputs are invalid")
    if any(not isinstance(name, str) or not name for name in names):
        raise ValueError("legacy bridge requires flat legacy dynamic input names")
    if len(set(names)) != len(names):
        raise ValueError("legacy config dynamic input names are not unique")
    if len(names) != int(expected_count):
        raise ValueError("legacy config dynamic input count drift")
    return tuple(names)


def assert_legacy_checkpoint_bridge_v09(
    state: Mapping,
    *,
    seed: int,
    panels: Iterable[tuple[Mapping[str, torch.Tensor], torch.Tensor]],
) -> dict:
    """Load one six-tensor state into three equivalent formal models."""
    _require_checkpoint_state(state)
    models = (
        build_model_v09("classic_lstm_256_clean", seed),
        build_model_v09("classic_lstm_256_clean", seed),
        build_model_v09("nested_history_disabled", seed),
    )
    for model in models:
        missing, unexpected = model.load_state_dict(state, strict=False)
        if unexpected or any(name in _ACTIVE_TENSORS for name in missing):
            raise ValueError("legacy checkpoint active tensor bridge drift")
        model.eval()
    panel_count = 0
    with torch.no_grad():
        for dynamic, statics in panels:
            predictions = [model(dynamic, statics).prediction for model in models]
            for candidate in predictions[1:]:
                if not torch.equal(predictions[0], candidate):
                    raise ValueError("legacy checkpoint bridge prediction mismatch")
            panel_count += 1
    if panel_count == 0:
        raise ValueError("legacy checkpoint bridge requires a nonempty panel")
    return {
        "tensor_count": len(_ACTIVE_TENSORS),
        "panel_count": panel_count,
        "model_count": len(models),
        "maximum_prediction_difference": 0.0,
    }


def _real_panel_batches(inputs: FormalBridgeInputsV09, batch_size: int = 256):
    selected_target_dates = np.linspace(0, len(inputs.target_dates) - 1, 12, dtype=np.int64)
    forcing_indices = np.searchsorted(inputs.dates, inputs.target_dates[selected_target_dates])
    basin_indices = np.repeat(np.arange(len(inputs.basins), dtype=np.int64), 12)
    target_indices = np.tile(forcing_indices, len(inputs.basins))
    for start in range(0, len(basin_indices), batch_size):
        basins = basin_indices[start:start + batch_size]
        targets = target_indices[start:start + batch_size]
        recent = np.empty((len(basins), 270, 5), dtype=np.float32)
        for row, (basin, target) in enumerate(zip(basins, targets)):
            np.copyto(recent[row], inputs.forcing[basin, target - 269:target + 1], casting="no")
        normalized = normalize_forcing_batch_v09(recent, inputs.scaler)
        statics = np.ascontiguousarray(inputs.statics[basins], dtype=np.float32)
        yield torch.from_numpy(normalized), torch.from_numpy(statics)


def _read_registered_bytes_v09(
    legacy_results_root: Path,
    path: Path,
    expected_sha256: str,
    *,
    label: str,
) -> bytes:
    """Bind validation, hashing, and later parsing/loading to one byte payload."""
    assert_no_reparse_components(legacy_results_root, path)
    payload = path.read_bytes()
    assert_no_reparse_components(legacy_results_root, path)
    actual_sha256 = hashlib.sha256(payload).hexdigest()
    if actual_sha256 != expected_sha256:
        raise ValueError(f"legacy {label} SHA-256 drift")
    return payload


def audit_legacy_checkpoint_bridge_v09(
        protocol: Mapping,
        *,
        legacy_results_root: str | Path,
        inputs: FormalBridgeInputsV09,
        report_path: str | Path,
        device: str | torch.device,
        protected_run_roots: Iterable[str | Path] = (),
) -> dict:
    """Verify all frozen run hashes and exact core/formal predictions without targets."""
    from neuralhydrology.modelzoo.cudalstm import CudaLSTM
    from neuralhydrology.utils.config import Config

    validate_protocol_v09(protocol)
    raw_legacy_results_root = Path(os.path.abspath(legacy_results_root))
    assert_no_reparse_components(raw_legacy_results_root, raw_legacy_results_root)
    legacy_results_root = raw_legacy_results_root.resolve()
    protected_roots = [legacy_results_root, *protected_run_roots]
    if inputs.root is not None:
        protected_roots.append(inputs.root)
    report_path = _assert_report_outside_protected_paths(report_path, protected_roots)
    if report_path.exists():
        raise FileExistsError(f"legacy bridge report already exists: {report_path}")
    for run in protocol["legacy_reference"]["runs"]:
        run_dir = legacy_results_root / run["run_id"]
        assert_no_reparse_components(legacy_results_root, run_dir)
        assert_no_reparse_components(legacy_results_root, run_dir / "config.yml")
        assert_no_reparse_components(legacy_results_root, run_dir / "model_epoch030.pt")
    identity = verify_legacy_reference_v09(protocol, legacy_results_root)
    generator = torch.Generator().manual_seed(29_090)
    synthetic_recent = torch.randn(2, 270, 5, generator=generator)
    synthetic_statics = torch.randn(2, 27, generator=generator)
    maximum = 0.0
    total_real_rows = 0
    run_rows = []
    legacy_dynamic_input_names: tuple[str, ...] | None = None
    for run in protocol["legacy_reference"]["runs"]:
        run_dir = legacy_results_root / run["run_id"]
        assert_no_reparse_components(legacy_results_root, run_dir)
        config_path = run_dir / "config.yml"
        checkpoint_path = run_dir / "model_epoch030.pt"
        config_payload = _read_registered_bytes_v09(
            legacy_results_root,
            config_path,
            run["config_sha256"],
            label="config",
        )
        checkpoint_payload = _read_registered_bytes_v09(
            legacy_results_root,
            checkpoint_path,
            run["checkpoint_epoch030_sha256"],
            label="checkpoint",
        )
        state = torch.load(io.BytesIO(checkpoint_payload), map_location="cpu", weights_only=False)
        _require_checkpoint_state(state)
        config_mapping = yaml.safe_load(config_payload.decode("utf-8"))
        if not isinstance(config_mapping, dict):
            raise ValueError("legacy config must decode to a mapping")
        config = Config(config_mapping)
        dynamic_input_names = _legacy_dynamic_input_names_v09(
            config,
            expected_count=int(protocol["dynamic_input_count"]),
        )
        # The sealed forcing columns were built from exactly these names in exactly this order,
        # so equality here is what makes the positional x_d assignment below verifiable rather
        # than assumed.
        if dynamic_input_names != DYNAMIC_COLUMNS_V09:
            raise ValueError("legacy config dynamic inputs differ from the sealed forcing column contract")
        if legacy_dynamic_input_names is None:
            legacy_dynamic_input_names = dynamic_input_names
        elif dynamic_input_names != legacy_dynamic_input_names:
            raise ValueError("legacy config dynamic input name drift across registered runs")
        core = CudaLSTM(config).to(device)
        classic = build_model_v09("classic_lstm_256_clean", run["seed"]).to(device)
        nested = build_model_v09("nested_history_disabled", run["seed"]).to(device)
        for model in (core, classic, nested):
            missing, unexpected = model.load_state_dict(state, strict=False)
            if unexpected or any(name in _ACTIVE_TENSORS for name in missing):
                raise ValueError("legacy checkpoint load drift")
            model.eval()

        def compare(recent: torch.Tensor, statics: torch.Tensor) -> None:
            nonlocal maximum
            recent = recent.to(device)
            statics = statics.to(device)
            core_data = {
                "x_d": {
                    name: recent[:, :, index:index + 1] for index, name in enumerate(dynamic_input_names)
                },
                "x_s": statics,
            }
            with torch.no_grad():
                reference = core(core_data)["y_hat"][:, -1, 0]
                classic_prediction = classic({"recent": recent}, statics).prediction
                nested_prediction = nested({"recent": recent}, statics).prediction
            for candidate in (classic_prediction, nested_prediction):
                difference = float((reference - candidate).abs().max().cpu())
                maximum = max(maximum, difference)
                if difference != 0.0:
                    raise ValueError("legacy core/formal bridge prediction mismatch")

        compare(synthetic_recent, synthetic_statics)
        rows = 0
        for recent, statics in _real_panel_batches(inputs):
            compare(recent, statics)
            rows += len(recent)
        if rows != len(inputs.basins) * 12:
            raise ValueError("legacy real training-input panel coverage drift")
        total_real_rows += rows
        run_rows.append({
            "seed": run["seed"],
            "run_id": run["run_id"],
            "config_sha256": hashlib.sha256(config_payload).hexdigest(),
            "checkpoint_sha256": hashlib.sha256(checkpoint_payload).hexdigest(),
            "real_panel_rows": rows,
        })
    if legacy_dynamic_input_names is None:
        raise ValueError("legacy bridge verified no registered run")
    verify_sealed_bridge_inputs_unchanged_v09(inputs)
    report = {
        "schema": "historical_multiscale_formal_v09_legacy_checkpoint_bridge_audit_v1",
        "status": "legacy_checkpoint_bridge_external_audit_passed",
        "protocol_canonical_sha256": canonical_sha256(protocol),
        "source_bindings": _source_bindings_v09(),
        "environment_binding": _environment_binding_v09(device),
        "input_bindings": {
            "input_seal_sha256": inputs.input_seal_sha256,
            "complete_input_external_audit_sha256": inputs.external_audit_sha256,
            "trusted_source_external_audit_sha256": inputs.trusted_source_audit_sha256,
        },
        "legacy_dynamic_input_names": list(legacy_dynamic_input_names),
        "verified_identity": identity,
        "runs": run_rows,
        "run_count": len(run_rows),
        "synthetic_panel_rows_per_run": 2,
        "real_panel_rows_per_run": len(inputs.basins) * 12,
        "real_panel_rows_total": total_real_rows,
        "maximum_prediction_difference": maximum,
        "training_target_value_reads": 0,
        "formal_evaluation_observation_reads": 0,
    }
    write_json_atomic(report_path, report)
    return report

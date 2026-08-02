from pathlib import Path
import sys

import numpy as np
import pytest

IDEA_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(IDEA_ROOT))


def _inputs():
    from formal_training_data_v09 import FormalTrainingInputsV09

    generator = np.random.default_rng(2909)
    dates = np.arange("2000-01-01", "2000-10-27", dtype="datetime64[D]")
    return FormalTrainingInputsV09.synthetic(
        forcing=np.ascontiguousarray(generator.normal(size=(2, 300, 5)).astype(np.float32)),
        statics=np.ascontiguousarray(generator.normal(size=(2, 27)).astype(np.float32)),
        targets=np.ascontiguousarray(generator.normal(size=(2, 4)).astype(np.float32)),
        dates=dates,
        target_dates=dates[-4:],
        scaler={
            "dynamic_center_float64": [0.0] * 5,
            "dynamic_scale_float64": [1.0] * 5,
            "target_center_float64": 0.0,
            "target_scale_float64": 1.0,
            "per_basin_target_scale_float64": [1.0, 1.5],
        },
    )


def _tiny_builder(variant: str, seed: int):
    from models_formal_v09 import CoreCompatibleClassicLSTM, CoreCompatibleContinuousHistoryLSTM

    import torch

    torch.manual_seed(seed)
    if variant == "classic_lstm_256_clean":
        return CoreCompatibleClassicLSTM(hidden_size=4, dropout=0.2)
    if variant == "nested_history_disabled":
        return CoreCompatibleContinuousHistoryLSTM(
            history_enabled=False,
            hidden_size=4,
            dropout=0.2,
        )
    raise ValueError(variant)


def test_synthetic_strict_runner_seals_exact_pair_and_fixed_checkpoints(tmp_path):
    from train_strict_formal_v09 import StrictExecutionSpecV09, _run_strict_training_v09

    output = tmp_path / "strict"
    manifest = _run_strict_training_v09(
        _inputs(),
        protocol={"protocol_id": "synthetic"},
        output_dir=output,
        device="cpu",
        execution_spec=StrictExecutionSpecV09(
            epochs=2,
            batch_size=3,
            checkpoint_epochs=(1, 2),
            expected_samples=8,
            expected_steps_per_epoch=3,
        ),
        model_builder=_tiny_builder,
    )

    assert manifest["status"] == "strict_nesting_complete"
    assert manifest["optimizer_steps_total"] == 6
    assert manifest["maximum_prediction_difference"] == 0.0
    assert [row["epoch"] for row in manifest["epoch_trace"]] == [1, 2]
    assert (output / "checkpoint_epoch001.pt").is_file()
    assert (output / "checkpoint_epoch002.pt").is_file()
    assert (output / "seal.json").is_file()
    classic = np.load(output / "classic_training_predictions.float32.npy", allow_pickle=False)
    nested = np.load(output / "nested_training_predictions.float32.npy", allow_pickle=False)
    assert classic.tobytes() == nested.tobytes()

    with pytest.raises(FileExistsError):
        _run_strict_training_v09(
            _inputs(),
            protocol={"protocol_id": "synthetic"},
            output_dir=output,
            device="cpu",
            execution_spec=StrictExecutionSpecV09(1, 3, (1,), 8, 3),
            model_builder=_tiny_builder,
        )


def test_formal_strict_runner_requires_a_live_training_runtime(tmp_path):
    from formal_v09_protocol import load_protocol_v09
    from train_strict_formal_v09 import run_strict_training_v09

    protocol = load_protocol_v09(IDEA_ROOT / "configs/formal_v09_protocol.json")
    with pytest.raises(ValueError, match="runtime"):
        run_strict_training_v09(
            _inputs(),
            protocol=protocol,
            output_dir=tmp_path / "formal",
            device="cpu",
            runtime=None,
        )

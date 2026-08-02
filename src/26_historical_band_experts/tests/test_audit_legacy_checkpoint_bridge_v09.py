from pathlib import Path
import sys

import pytest
import torch

IDEA_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(IDEA_ROOT))


def test_checkpoint_bridge_requires_six_exact_active_tensors_and_three_equal_models():
    from audit_legacy_checkpoint_bridge_v09 import assert_legacy_checkpoint_bridge_v09
    from models_formal_v09 import build_model_v09

    source = build_model_v09("classic_lstm_256_clean", 100)
    state = source.state_dict()
    dynamic = {"recent": torch.zeros(2, 12, 5)}
    statics = torch.zeros(2, 27)

    report = assert_legacy_checkpoint_bridge_v09(
        state,
        seed=100,
        panels=((dynamic, statics),),
    )
    assert report["tensor_count"] == 6
    assert report["panel_count"] == 1
    assert report["maximum_prediction_difference"] == 0.0

    drift = dict(state)
    drift.pop("head.net.0.bias")
    with pytest.raises(ValueError, match="six|tensor"):
        assert_legacy_checkpoint_bridge_v09(
            drift,
            seed=100,
            panels=((dynamic, statics),),
        )

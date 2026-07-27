from pathlib import Path
import sys

import pytest
import torch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from diagnostics_v06 import (
    BRANCH_COMBINATIONS,
    DEFAULT_BRANCH_WIDTHS,
    capture_fused_features,
    masked_predictions_from_fused,
)
from models_v05 import build_model_v05


EXPECTED_COMBINATIONS = (
    ("recent",),
    ("medium",),
    ("old",),
    ("recent", "medium"),
    ("recent", "old"),
    ("medium", "old"),
    ("recent", "medium", "old"),
)


def _inputs(batch_size: int = 3) -> tuple[dict[str, torch.Tensor], torch.Tensor]:
    generator = torch.Generator().manual_seed(610)
    dynamic = {
        "recent": torch.randn(batch_size, 270, 5, generator=generator),
        "medium": torch.randn(batch_size, 60, 20, generator=generator),
        "old": torch.randn(batch_size, 5, 12, 20, generator=generator),
    }
    statics = torch.randn(batch_size, 27, generator=generator)
    return dynamic, statics


def test_v06_branch_combinations_are_exactly_the_seven_nonempty_subsets():
    assert BRANCH_COMBINATIONS == EXPECTED_COMBINATIONS
    assert DEFAULT_BRANCH_WIDTHS == {
        "recent": 256,
        "medium": 64,
        "old": 128,
    }


def test_v06_all_branch_mask_exactly_matches_original_v05_forward():
    dynamic, statics = _inputs()
    model = build_model_v05("hierarchical_rich_history", seed=100).eval()

    original, fused = capture_fused_features(model, dynamic, statics)
    masked = masked_predictions_from_fused(model, fused)

    torch.testing.assert_close(
        masked[("recent", "medium", "old")],
        original,
        rtol=0,
        atol=0,
    )


def test_v06_inactive_features_are_zeroed_after_encoding_and_bias_is_retained_once():
    model = build_model_v05("hierarchical_rich_history", seed=100).eval()
    with torch.no_grad():
        model.head.weight.fill_(1.0)
        model.head.bias.fill_(3.0)
    fused = torch.ones(2, 448)

    masked = masked_predictions_from_fused(model, fused)

    torch.testing.assert_close(masked[("recent",)], torch.full((2,), 259.0))
    torch.testing.assert_close(masked[("medium",)], torch.full((2,), 67.0))
    torch.testing.assert_close(masked[("old",)], torch.full((2,), 131.0))
    torch.testing.assert_close(masked[("recent", "medium")], torch.full((2,), 323.0))
    torch.testing.assert_close(masked[("recent", "old")], torch.full((2,), 387.0))
    torch.testing.assert_close(masked[("medium", "old")], torch.full((2,), 195.0))
    torch.testing.assert_close(masked[("recent", "medium", "old")], torch.full((2,), 451.0))


def test_v06_capture_rejects_training_mode_because_dropout_would_change_mask_semantics():
    dynamic, statics = _inputs()
    model = build_model_v05("hierarchical_rich_history", seed=100).train()

    with pytest.raises(ValueError, match="evaluation mode"):
        capture_fused_features(model, dynamic, statics)


def test_v06_masking_rejects_wrong_fused_width():
    model = build_model_v05("hierarchical_rich_history", seed=100).eval()

    with pytest.raises(ValueError, match="448"):
        masked_predictions_from_fused(model, torch.zeros(2, 447))

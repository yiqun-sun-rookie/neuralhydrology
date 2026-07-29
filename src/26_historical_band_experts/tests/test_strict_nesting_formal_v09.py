from pathlib import Path
import sys

import pytest
import torch


IDEA_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(IDEA_ROOT))


def test_v09_one_lockstep_update_is_bitwise_exact():
    from models_formal_v09 import build_model_v09
    from strict_nesting_formal_v09 import lockstep_train_step_v09
    from train_strict_v06 import active_named_parameters

    classic = build_model_v09("classic_lstm_256_clean", 100)
    nested = build_model_v09("nested_history_disabled", 100)
    classic_optimizer = torch.optim.Adam([parameter for _, parameter in active_named_parameters(classic)], lr=0.001)
    nested_optimizer = torch.optim.Adam([parameter for _, parameter in active_named_parameters(nested)], lr=0.001)
    generator = torch.Generator().manual_seed(2909)
    dynamic = {"recent": torch.randn(3, 6, 5, generator=generator)}
    statics = torch.randn(3, 27, generator=generator)
    target = torch.randn(3, generator=generator)
    weights = torch.rand(3, generator=generator)

    report = lockstep_train_step_v09(
        classic,
        nested,
        classic_optimizer,
        nested_optimizer,
        dynamic,
        statics,
        target,
        weights,
        basin_indices=(torch.tensor([0, 1, 2]), torch.tensor([0, 1, 2])),
        target_indices=(torch.tensor([10, 11, 12]), torch.tensor([10, 11, 12])),
        dropout_context=(100, 1, 0),
        gradient_clip=1.0,
    )

    assert report["lockstep_exact"] is True
    assert report["random_number_state_equal"] is True
    assert report["prediction_equal"] is True
    assert report["loss_equal"] is True
    assert report["gradients_equal"] is True
    assert report["optimizer_state_equal"] is True
    assert report["parameters_equal"] is True


def test_v09_independent_reproduction_tolerance_is_exactly_one_e_minus_six():
    from strict_nesting_formal_v09 import (
        IndependentReproductionMismatch,
        assert_reproduced_predictions_v09,
    )

    reference = torch.tensor([0.0, 1.0], dtype=torch.float64)
    assert_reproduced_predictions_v09(reference, reference + torch.tensor([1e-6, -1e-6]))
    with pytest.raises(IndependentReproductionMismatch, match="1e-06"):
        assert_reproduced_predictions_v09(reference, reference + torch.tensor([1.0001e-6, 0.0]))
    with pytest.raises(IndependentReproductionMismatch, match="nonempty"):
        assert_reproduced_predictions_v09(torch.tensor([]), torch.tensor([]))


def test_v09_lockstep_rejects_different_batch_keys_before_training():
    from models_formal_v09 import build_model_v09
    from strict_nesting_formal_v09 import lockstep_train_step_v09
    from train_strict_v06 import StrictNestingMismatch, active_named_parameters

    classic = build_model_v09("classic_lstm_256_clean", 100)
    nested = build_model_v09("nested_history_disabled", 100)
    classic_optimizer = torch.optim.Adam([parameter for _, parameter in active_named_parameters(classic)], lr=0.001)
    nested_optimizer = torch.optim.Adam([parameter for _, parameter in active_named_parameters(nested)], lr=0.001)
    dynamic = {"recent": torch.zeros(2, 2, 5)}
    statics = torch.zeros(2, 27)
    target = torch.zeros(2)
    weights = torch.ones(2)

    with pytest.raises(StrictNestingMismatch, match="basin batch indices"):
        lockstep_train_step_v09(
            classic,
            nested,
            classic_optimizer,
            nested_optimizer,
            dynamic,
            statics,
            target,
            weights,
            basin_indices=(torch.tensor([0, 1]), torch.tensor([0, 2])),
            target_indices=(torch.tensor([10, 11]), torch.tensor([10, 11])),
            dropout_context=(100, 1, 0),
            gradient_clip=1.0,
        )

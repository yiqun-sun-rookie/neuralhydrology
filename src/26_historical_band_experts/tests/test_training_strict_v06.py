from pathlib import Path
import sys

import pytest
import torch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from models_v06 import build_strict_pair_v06
from train_strict_v06 import (
    StrictNestingMismatch,
    active_named_parameters,
    assert_batch_indices_equal,
    assert_exact_tensor,
    assert_parameter_sequence_equal,
    exact_evaluation_predictions,
    lockstep_train_step,
)


def _batch(device: str = "cpu"):
    generator = torch.Generator().manual_seed(706)
    dynamic = {
        "recent": torch.randn(3, 12, 5, generator=generator).to(device),
    }
    statics = torch.randn(3, 27, generator=generator).to(device)
    target = torch.randn(3, generator=generator).to(device)
    weights = torch.tensor([0.5, 1.0, 1.5], device=device)
    basins = torch.tensor([0, 1, 2], device=device)
    times = torch.tensor([3649, 3650, 3651], device=device)
    return dynamic, statics, target, weights, basins, times


def _optimizers(classic, nested):
    return (
        torch.optim.Adam((parameter for _, parameter in active_named_parameters(classic)), lr=0.001),
        torch.optim.Adam((parameter for _, parameter in active_named_parameters(nested)), lr=0.001),
    )


def test_v06_lockstep_step_keeps_predictions_gradients_adam_and_parameters_exact():
    classic, nested = build_strict_pair_v06(seed=100)
    optimizers = _optimizers(classic, nested)
    dynamic, statics, target, weights, basins, times = _batch()

    report = lockstep_train_step(
        classic=classic,
        nested=nested,
        classic_optimizer=optimizers[0],
        nested_optimizer=optimizers[1],
        dynamic=dynamic,
        statics=statics,
        target=target,
        loss_weights=weights,
        basin_indices=(basins, basins.clone()),
        target_indices=(times, times.clone()),
        gradient_clip=1.0,
    )

    assert report["status"] == "exact"
    assert report["prediction_equal"] is True
    assert report["loss_equal"] is True
    assert report["gradients_equal"] is True
    assert report["optimizer_state_equal"] is True
    assert report["parameters_equal"] is True
    for (_, classic_parameter), (_, nested_parameter) in zip(
        active_named_parameters(classic),
        active_named_parameters(nested),
    ):
        assert torch.equal(classic_parameter, nested_parameter)


def test_v06_two_lockstep_steps_remain_exact():
    classic, nested = build_strict_pair_v06(seed=100)
    optimizers = _optimizers(classic, nested)
    dynamic, statics, target, weights, basins, times = _batch()

    for _ in range(2):
        report = lockstep_train_step(
            classic=classic,
            nested=nested,
            classic_optimizer=optimizers[0],
            nested_optimizer=optimizers[1],
            dynamic=dynamic,
            statics=statics,
            target=target,
            loss_weights=weights,
            basin_indices=(basins, basins.clone()),
            target_indices=(times, times.clone()),
            gradient_clip=1.0,
        )
        assert report["status"] == "exact"


def test_v06_two_synthetic_epochs_and_final_evaluation_predictions_remain_exact():
    classic, nested = build_strict_pair_v06(seed=100)
    optimizers = _optimizers(classic, nested)
    dynamic, statics, target, weights, basins, times = _batch()

    for _epoch in range(2):
        for _batch_index in range(2):
            lockstep_train_step(
                classic=classic,
                nested=nested,
                classic_optimizer=optimizers[0],
                nested_optimizer=optimizers[1],
                dynamic=dynamic,
                statics=statics,
                target=target,
                loss_weights=weights,
                basin_indices=(basins, basins.clone()),
                target_indices=(times, times.clone()),
                gradient_clip=1.0,
            )

    classic_predictions, nested_predictions = exact_evaluation_predictions(
        classic,
        nested,
        [(dynamic, statics), (dynamic, statics)],
    )
    assert torch.equal(classic_predictions, nested_predictions)


def test_v06_changed_batch_index_fails_before_forward():
    _dynamic, _statics, _target, _weights, basins, times = _batch()
    changed = times.clone()
    changed[0] += 1

    with pytest.raises(StrictNestingMismatch, match="target batch indices"):
        assert_batch_indices_equal(
            basin_indices=(basins, basins.clone()),
            target_indices=(times, changed),
        )


def test_v06_changed_parameter_order_fails_before_training():
    classic, nested = build_strict_pair_v06(seed=100)
    classic_parameters = active_named_parameters(classic)
    nested_parameters = list(reversed(active_named_parameters(nested)))

    with pytest.raises(StrictNestingMismatch, match="parameter order"):
        assert_parameter_sequence_equal(classic_parameters, nested_parameters)


def test_v06_changed_dropout_mask_reports_the_first_differing_component():
    reference = torch.tensor([[1.0, 0.0], [0.0, 1.0]])
    changed = reference.clone()
    changed[0, 0] = 0.0

    with pytest.raises(StrictNestingMismatch, match="dropout mask"):
        assert_exact_tensor("dropout mask", reference, changed)


@pytest.mark.skipif(not torch.cuda.is_available(), reason="CUDA is required")
def test_v06_cuda_lockstep_step_is_exact():
    classic, nested = build_strict_pair_v06(seed=100)
    classic = classic.cuda()
    nested = nested.cuda()
    optimizers = _optimizers(classic, nested)
    dynamic, statics, target, weights, basins, times = _batch(device="cuda")

    report = lockstep_train_step(
        classic=classic,
        nested=nested,
        classic_optimizer=optimizers[0],
        nested_optimizer=optimizers[1],
        dynamic=dynamic,
        statics=statics,
        target=target,
        loss_weights=weights,
        basin_indices=(basins, basins.clone()),
        target_indices=(times, times.clone()),
        gradient_clip=1.0,
    )

    assert report["status"] == "exact"

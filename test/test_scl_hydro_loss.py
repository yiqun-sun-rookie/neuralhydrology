import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

import pytest
import torch
from scl_hydro.loss import StateContinuityLoss


def test_scl_loss_identical_states():
    """Loss should be zero when overlap states are identical."""
    loss_fn = StateContinuityLoss(scl_weight=1.0)
    h_k = torch.randn(4, 30, 64)
    loss = loss_fn(h_k, h_k.clone())
    assert loss.item() == pytest.approx(0.0, abs=1e-6)


def test_scl_loss_different_states():
    """Loss should be positive when states differ."""
    loss_fn = StateContinuityLoss(scl_weight=1.0)
    h_k = torch.zeros(4, 30, 64)
    h_k1 = torch.ones(4, 30, 64)
    loss = loss_fn(h_k, h_k1)
    assert loss.item() > 0


def test_scl_loss_weight():
    """Loss should scale with scl_weight."""
    h_k = torch.zeros(2, 10, 32)
    h_k1 = torch.ones(2, 10, 32)
    loss_1 = StateContinuityLoss(scl_weight=1.0)(h_k, h_k1)
    loss_01 = StateContinuityLoss(scl_weight=0.1)(h_k, h_k1)
    assert loss_1.item() == pytest.approx(loss_01.item() * 10, rel=1e-5)


def test_scl_loss_gradient_flow():
    """Gradients should flow through both input tensors."""
    loss_fn = StateContinuityLoss(scl_weight=1.0)
    h_k = torch.randn(2, 5, 16, requires_grad=True)
    h_k1 = torch.randn(2, 5, 16, requires_grad=True)
    loss = loss_fn(h_k, h_k1)
    loss.backward()
    assert h_k.grad is not None
    assert h_k1.grad is not None

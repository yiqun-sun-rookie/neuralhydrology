import pytest
import torch
import torch.nn as nn


class FakeModel(nn.Module):
    def forward(self, x_d, x_s):
        return x_d.sum(dim=-1, keepdim=True)


@pytest.fixture
def setup():
    from src.adversarial.attacks.sparse_temporal import SparseTemporalAttack
    from src.adversarial.constraints.lp_norm import LpConstraint
    model = FakeModel()
    constraint = LpConstraint(epsilon=0.2, norm="linf")
    attack = SparseTemporalAttack(model=model, constraint=constraint,
                                   max_steps=18, n_iter=30)
    return attack, model


class TestSparseTemporalAttack:

    def test_output_shape(self, setup):
        attack, _ = setup
        x_d = torch.randn(1, 365, 5)
        x_s = torch.randn(1, 13)
        y_obs = torch.randn(1, 365, 1)
        x_adv = attack.attack(x_d, x_s, y_obs)
        assert x_adv.shape == x_d.shape

    def test_sparsity(self, setup):
        """Only max_steps timesteps should be perturbed."""
        attack, _ = setup
        x_d = torch.randn(1, 365, 5)
        x_s = torch.randn(1, 13)
        y_obs = torch.randn(1, 365, 1)
        x_adv = attack.attack(x_d, x_s, y_obs)
        delta = (x_adv - x_d).abs()
        # Count non-zero timesteps (any feature perturbed)
        perturbed_steps = (delta.sum(dim=-1) > 1e-6).sum(dim=-1)
        assert perturbed_steps.item() <= 18

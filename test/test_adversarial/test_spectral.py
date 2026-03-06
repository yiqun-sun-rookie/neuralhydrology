import pytest
import torch
import torch.nn as nn


class FakeModel(nn.Module):
    def forward(self, x_d, x_s):
        return x_d.sum(dim=-1, keepdim=True)


@pytest.fixture
def setup():
    from src.adversarial.attacks.spectral import SpectralAttack
    from src.adversarial.constraints.lp_norm import LpConstraint
    model = FakeModel()
    constraint = LpConstraint(epsilon=0.3, norm="linf")
    attack = SpectralAttack(model=model, constraint=constraint, n_iter=30)
    return attack, model


class TestSpectralAttack:

    def test_output_shape(self, setup):
        attack, _ = setup
        x_d = torch.randn(1, 128, 5)
        x_s = torch.randn(1, 13)
        y_obs = torch.randn(1, 128, 1)
        x_adv = attack.attack(x_d, x_s, y_obs)
        assert x_adv.shape == x_d.shape

    def test_mean_preserved(self, setup):
        """Spectral attack should approximately preserve time-domain mean."""
        attack, _ = setup
        torch.manual_seed(42)
        x_d = torch.randn(1, 128, 5)
        x_s = torch.randn(1, 13)
        y_obs = torch.randn(1, 128, 1)
        x_adv = attack.attack(x_d, x_s, y_obs)
        for f in range(5):
            orig_mean = x_d[0, :, f].mean()
            adv_mean = x_adv[0, :, f].mean()
            assert abs(orig_mean - adv_mean) < 0.15

    def test_perturbation_nonzero(self, setup):
        attack, _ = setup
        x_d = torch.randn(1, 128, 5)
        x_s = torch.randn(1, 13)
        y_obs = torch.randn(1, 128, 1)
        x_adv = attack.attack(x_d, x_s, y_obs)
        assert (x_adv - x_d).abs().max() > 1e-6

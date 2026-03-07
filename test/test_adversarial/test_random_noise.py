import pytest
import torch
import torch.nn as nn


class FakeModel(nn.Module):
    def forward(self, x_d, x_s):
        return x_d.sum(dim=-1, keepdim=True)


@pytest.fixture
def setup_gaussian():
    from src.adversarial.attacks.random_noise import GaussianNoise
    from src.adversarial.constraints.lp_norm import LpConstraint
    model = FakeModel()
    constraint = LpConstraint(epsilon=0.1, norm="linf")
    attack = GaussianNoise(model=model, constraint=constraint, n_samples=5)
    return attack, model


@pytest.fixture
def setup_multiplicative():
    from src.adversarial.attacks.random_noise import MultiplicativeBias
    from src.adversarial.constraints.lp_norm import LpConstraint
    model = FakeModel()
    constraint = LpConstraint(epsilon=0.1, norm="linf")
    attack = MultiplicativeBias(model=model, constraint=constraint, n_samples=5)
    return attack, model


@pytest.fixture
def setup_temporal():
    from src.adversarial.attacks.random_noise import TemporalCorrelatedNoise
    from src.adversarial.constraints.lp_norm import LpConstraint
    model = FakeModel()
    constraint = LpConstraint(epsilon=0.1, norm="linf")
    attack = TemporalCorrelatedNoise(model=model, constraint=constraint, n_samples=5)
    return attack, model


class TestGaussianNoise:

    def test_output_shape(self, setup_gaussian):
        attack, _ = setup_gaussian
        x_d = torch.randn(2, 50, 5)
        x_s = torch.randn(2, 13)
        y_obs = torch.randn(2, 50, 1)
        x_adv = attack.attack(x_d, x_s, y_obs)
        assert x_adv.shape == x_d.shape

    def test_perturbation_within_bounds(self, setup_gaussian):
        attack, _ = setup_gaussian
        x_d = torch.randn(2, 50, 5)
        x_s = torch.randn(2, 13)
        y_obs = torch.randn(2, 50, 1)
        x_adv = attack.attack(x_d, x_s, y_obs)
        delta = (x_adv - x_d).abs()
        assert delta.max() <= 0.1 + 1e-5

    def test_reproducible(self, setup_gaussian):
        attack, _ = setup_gaussian
        x_d = torch.randn(2, 50, 5)
        x_s = torch.randn(2, 13)
        y_obs = torch.randn(2, 50, 1)
        x_adv1 = attack.attack(x_d, x_s, y_obs)
        x_adv2 = attack.attack(x_d, x_s, y_obs)
        assert torch.allclose(x_adv1, x_adv2)


class TestMultiplicativeBias:

    def test_output_shape(self, setup_multiplicative):
        attack, _ = setup_multiplicative
        x_d = torch.randn(2, 50, 5)
        x_s = torch.randn(2, 13)
        y_obs = torch.randn(2, 50, 1)
        x_adv = attack.attack(x_d, x_s, y_obs)
        assert x_adv.shape == x_d.shape

    def test_only_prcp_channel_changed(self, setup_multiplicative):
        attack, _ = setup_multiplicative
        x_d = torch.randn(2, 50, 5)
        x_s = torch.randn(2, 13)
        y_obs = torch.randn(2, 50, 1)
        x_adv = attack.attack(x_d, x_s, y_obs)
        # Channels 1-4 should be unchanged (only after projection, so check within tolerance)
        for ch in range(1, 5):
            assert torch.allclose(x_adv[:, :, ch], x_d[:, :, ch], atol=1e-5)

    def test_perturbation_within_bounds(self, setup_multiplicative):
        attack, _ = setup_multiplicative
        x_d = torch.randn(2, 50, 5)
        x_s = torch.randn(2, 13)
        y_obs = torch.randn(2, 50, 1)
        x_adv = attack.attack(x_d, x_s, y_obs)
        delta = (x_adv - x_d).abs()
        assert delta.max() <= 0.1 + 1e-5


class TestTemporalCorrelatedNoise:

    def test_output_shape(self, setup_temporal):
        attack, _ = setup_temporal
        x_d = torch.randn(2, 50, 5)
        x_s = torch.randn(2, 13)
        y_obs = torch.randn(2, 50, 1)
        x_adv = attack.attack(x_d, x_s, y_obs)
        assert x_adv.shape == x_d.shape

    def test_perturbation_within_bounds(self, setup_temporal):
        attack, _ = setup_temporal
        x_d = torch.randn(2, 50, 5)
        x_s = torch.randn(2, 13)
        y_obs = torch.randn(2, 50, 1)
        x_adv = attack.attack(x_d, x_s, y_obs)
        delta = (x_adv - x_d).abs()
        assert delta.max() <= 0.1 + 1e-5

    def test_temporal_smoothness(self, setup_temporal):
        """Temporal noise should be smoother than i.i.d."""
        attack, _ = setup_temporal
        x_d = torch.zeros(1, 100, 5)
        x_s = torch.randn(1, 13)
        y_obs = torch.randn(1, 100, 1)
        x_adv = attack.attack(x_d, x_s, y_obs)
        delta = x_adv - x_d
        # Temporal difference should be small relative to amplitude
        diff = (delta[:, 1:, :] - delta[:, :-1, :]).abs().mean()
        amp = delta.abs().mean()
        assert diff < amp  # smoother than random

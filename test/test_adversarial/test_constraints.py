import pytest
import torch


class TestLpConstraint:

    def test_linf_clamp(self):
        from src.adversarial.constraints.lp_norm import LpConstraint
        c = LpConstraint(epsilon=0.1, norm="linf")
        x_clean = torch.zeros(2, 10, 5)
        x_adv = torch.ones(2, 10, 5)  # way out of bounds
        x_proj = c.project(x_clean, x_adv)
        delta = x_proj - x_clean
        assert delta.abs().max() <= 0.1 + 1e-6

    def test_l2_clamp(self):
        from src.adversarial.constraints.lp_norm import LpConstraint
        c = LpConstraint(epsilon=1.0, norm="l2")
        x_clean = torch.zeros(2, 10, 5)
        x_adv = torch.ones(2, 10, 5) * 10
        x_proj = c.project(x_clean, x_adv)
        delta = x_proj - x_clean
        # Per-sample L2 norm
        for i in range(2):
            assert delta[i].norm() <= 1.0 + 1e-5


class TestPhysicalConstraint:

    def test_precipitation_non_negative(self):
        from src.adversarial.constraints.physical import PhysicalConstraint
        c = PhysicalConstraint(
            epsilon=0.5,
            feature_names=["prcp(mm/day)", "srad(W/m2)", "tmax(C)", "tmin(C)", "vp(Pa)"],
            scaler_center=torch.zeros(5),
            scaler_scale=torch.ones(5),
        )
        x_clean = torch.zeros(2, 10, 5)
        x_adv = torch.full((2, 10, 5), -1.0)  # negative everywhere
        x_proj = c.project(x_clean, x_adv)

        # In real space: prcp, srad >= 0
        prcp_real = x_proj[:, :, 0] * 1.0 + 0.0  # scale=1, center=0
        assert (prcp_real >= -1e-6).all()

    def test_temperature_in_range(self):
        from src.adversarial.constraints.physical import PhysicalConstraint
        c = PhysicalConstraint(
            epsilon=10.0,
            feature_names=["prcp(mm/day)", "srad(W/m2)", "tmax(C)", "tmin(C)", "vp(Pa)"],
            scaler_center=torch.tensor([0.0, 0.0, 15.0, 5.0, 0.0]),
            scaler_scale=torch.tensor([1.0, 1.0, 10.0, 10.0, 1.0]),
        )
        x_clean = torch.zeros(2, 10, 5)
        x_adv = torch.full((2, 10, 5), 100.0)
        x_proj = c.project(x_clean, x_adv)

        # tmax real = x_proj[:,:,2] * 10 + 15, should be <= 60
        tmax_real = x_proj[:, :, 2] * 10.0 + 15.0
        assert (tmax_real <= 60.0 + 1e-4).all()


class TestStatisticalConstraint:

    def test_mean_preserved(self):
        from src.adversarial.constraints.statistical import StatisticalConstraint
        c = StatisticalConstraint(
            epsilon=0.5,
            feature_names=["prcp(mm/day)", "srad(W/m2)", "tmax(C)", "tmin(C)", "vp(Pa)"],
            scaler_center=torch.zeros(5),
            scaler_scale=torch.ones(5),
        )
        torch.manual_seed(42)
        x_clean = torch.randn(1, 365, 5)
        x_adv = x_clean + torch.randn_like(x_clean) * 0.3
        x_proj = c.project(x_clean, x_adv)

        # Mean should be close to original (per feature)
        for f in range(5):
            orig_mean = x_clean[0, :, f].mean()
            proj_mean = x_proj[0, :, f].mean()
            assert abs(orig_mean - proj_mean) < 0.05

    def test_std_preserved(self):
        from src.adversarial.constraints.statistical import StatisticalConstraint
        c = StatisticalConstraint(
            epsilon=0.5,
            feature_names=["prcp(mm/day)", "srad(W/m2)", "tmax(C)", "tmin(C)", "vp(Pa)"],
            scaler_center=torch.zeros(5),
            scaler_scale=torch.ones(5),
        )
        torch.manual_seed(42)
        x_clean = torch.randn(1, 365, 5)
        x_adv = x_clean + torch.randn_like(x_clean) * 0.3
        x_proj = c.project(x_clean, x_adv)

        for f in range(5):
            orig_std = x_clean[0, :, f].std()
            proj_std = x_proj[0, :, f].std()
            assert abs(orig_std - proj_std) / orig_std < 0.1  # within 10%

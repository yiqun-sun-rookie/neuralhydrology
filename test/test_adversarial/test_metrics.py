import pytest
import torch


class TestAttackMetrics:

    def test_delta_nse(self):
        from src.adversarial.evaluation.metrics import delta_nse
        y_obs = torch.tensor([1.0, 2.0, 3.0, 4.0, 5.0])
        y_clean = torch.tensor([1.1, 2.1, 2.9, 3.9, 5.1])  # good pred
        y_adv = torch.tensor([3.0, 1.0, 5.0, 2.0, 4.0])  # bad pred
        d = delta_nse(y_obs, y_clean, y_adv)
        assert d < 0  # NSE should drop

    def test_attack_success_rate(self):
        from src.adversarial.evaluation.metrics import attack_success_rate
        # 3 basins: NSE drops to -0.5, 0.3, -0.1
        nse_adv = torch.tensor([-0.5, 0.3, -0.1])
        asr = attack_success_rate(nse_adv, threshold=0.0)
        assert abs(asr - 2 / 3) < 1e-6

    def test_compute_nse_perfect(self):
        from src.adversarial.evaluation.metrics import compute_nse
        y_obs = torch.tensor([1.0, 2.0, 3.0, 4.0, 5.0])
        y_pred = y_obs.clone()
        nse = compute_nse(y_obs, y_pred)
        assert abs(nse - 1.0) < 1e-5

    def test_detectability_ks(self):
        from src.adversarial.evaluation.metrics import detectability_ks
        torch.manual_seed(0)
        x_clean = torch.randn(365)
        x_adv = x_clean + 0.001 * torch.randn(365)  # tiny perturbation
        p_val = detectability_ks(x_clean, x_adv)
        assert p_val > 0.05  # should not be detectable

    def test_peak_error(self):
        from src.adversarial.evaluation.metrics import peak_error
        y_obs = torch.tensor([1.0, 10.0, 2.0])  # peak at index 1
        y_pred = torch.tensor([1.0, 7.0, 2.0])  # underestimates peak
        rel_err = peak_error(y_obs, y_pred, quantile=0.9)
        assert abs(rel_err - 0.3) < 1e-5  # (10-7)/10 = 0.3

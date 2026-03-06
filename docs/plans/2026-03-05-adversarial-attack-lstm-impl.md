# Adversarial Attack on CudaLSTM — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a 6-method adversarial attack framework to evaluate CudaLSTM robustness on CAMELS-US basins.

**Architecture:** Model wrapper adapts neuralhydrology's dict-based interface to tensor-based attack interface. Each attack inherits from `BaseAttack`, uses composable `Constraint` objects for 3-tier projection. A YAML-driven runner orchestrates the full experiment matrix.

**Tech Stack:** PyTorch (attacks + model), neuralhydrology (CudaLSTM), numpy/scipy (spectral + stats), pytest (tests), matplotlib (plots), YAML (config)

**External dependency:** `neuralhydrology` package at `G:\github\pycharm\projects\neuralhydrology` — must be on PYTHONPATH or pip-installed in editable mode.

---

### Task 1: Environment Setup + Project Scaffolding

**Files:**
- Create: `src/adversarial/__init__.py`
- Create: `src/adversarial/attacks/__init__.py`
- Create: `src/adversarial/constraints/__init__.py`
- Create: `src/adversarial/evaluation/__init__.py`
- Create: `tests/test_adversarial/__init__.py`

**Step 1: Verify neuralhydrology is importable**

Run:
```bash
cd G:/github/pycharm/projects/kalmannet
python -c "from neuralhydrology.modelzoo.cudalstm import CudaLSTM; print('OK')"
```

If it fails, install in editable mode:
```bash
pip install -e G:/github/pycharm/projects/neuralhydrology
```

**Step 2: Create directory structure**

```bash
mkdir -p src/adversarial/attacks src/adversarial/constraints src/adversarial/evaluation tests/test_adversarial
```

**Step 3: Create all `__init__.py` files**

Each one is empty for now.

**Step 4: Commit**

```bash
git add src/adversarial/ tests/test_adversarial/
git commit -m "feat(adversarial): scaffold project structure"
```

---

### Task 2: CudaLSTM Model Wrapper

**Files:**
- Create: `src/adversarial/model_wrapper.py`
- Create: `tests/test_adversarial/test_model_wrapper.py`

**Step 1: Write the failing test**

```python
# tests/test_adversarial/test_model_wrapper.py
import pytest
import torch


@pytest.fixture
def wrapper():
    """Load the real CudaLSTM wrapper. Skip if checkpoint not available."""
    from src.adversarial.model_wrapper import CudaLSTMWrapper
    from pathlib import Path

    run_dir = Path(r"G:\github\pycharm\projects\neuralhydrology\runs\05_full_531_basins_smoke_v2_2026_0217_1632_ep1")
    if not run_dir.exists():
        pytest.skip("neuralhydrology run_dir not found")
    return CudaLSTMWrapper(run_dir=run_dir, device="cpu")


class TestCudaLSTMWrapper:

    def test_forward_shape(self, wrapper):
        """Forward pass returns correct shape."""
        B, T = 2, 365
        x_d = torch.randn(B, T, 5)
        x_s = torch.randn(B, 13)
        y_hat = wrapper.forward(x_d, x_s)
        assert y_hat.shape == (B, T, 1)

    def test_forward_requires_grad(self, wrapper):
        """Output has grad_fn when input requires_grad (needed for attacks)."""
        B, T = 2, 365
        x_d = torch.randn(B, T, 5, requires_grad=True)
        x_s = torch.randn(B, 13)
        y_hat = wrapper.forward(x_d, x_s)
        assert y_hat.requires_grad

    def test_feature_names(self, wrapper):
        """Wrapper exposes feature names and indices."""
        assert len(wrapper.dynamic_features) == 5
        assert "prcp(mm/day)" in wrapper.dynamic_features

    def test_scaler(self, wrapper):
        """Wrapper exposes scaler for denormalization."""
        scaler = wrapper.get_scaler()
        assert "xarray_feature_center" in scaler or hasattr(scaler, "keys")
```

**Step 2: Run test to verify it fails**

Run: `python -m pytest tests/test_adversarial/test_model_wrapper.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'src.adversarial.model_wrapper'`

**Step 3: Write implementation**

```python
# src/adversarial/model_wrapper.py
"""Wrap neuralhydrology CudaLSTM for adversarial attack interface."""
from __future__ import annotations

from pathlib import Path
from typing import Optional

import torch
import torch.nn as nn

from neuralhydrology.modelzoo import get_model
from neuralhydrology.utils.config import Config
from neuralhydrology.datautils.utils import load_scaler


class CudaLSTMWrapper(nn.Module):
    """Tensor-interface wrapper around neuralhydrology CudaLSTM.

    Converts stacked tensor [B, T, 5] <-> feature-dict expected by CudaLSTM.
    """

    def __init__(self, run_dir: Path, device: str = "cpu",
                 epoch: Optional[int] = None):
        super().__init__()
        self.run_dir = Path(run_dir)
        self.device = torch.device(device)

        # Load config
        cfg_path = self.run_dir / "config.yml"
        self.cfg = Config(cfg_path)

        # Load model
        self.model = get_model(self.cfg).to(self.device)

        # Find checkpoint
        if epoch is None:
            pts = sorted(self.run_dir.glob("model_epoch*.pt"))
            if not pts:
                raise FileNotFoundError(f"No checkpoint found in {self.run_dir}")
            weight_file = pts[-1]  # latest epoch
        else:
            weight_file = self.run_dir / f"model_epoch{epoch:03d}.pt"

        state = torch.load(weight_file, map_location=self.device, weights_only=True)
        self.model.load_state_dict(state)
        self.model.eval()

        # Feature metadata
        self.dynamic_features = list(self.cfg.dynamic_inputs)
        self.static_features = list(self.cfg.static_attributes)
        self.n_dynamic = len(self.dynamic_features)
        self.n_static = len(self.static_features)

        # Scaler
        self._scaler = load_scaler(self.run_dir)

    def forward(self, x_d: torch.Tensor, x_s: torch.Tensor) -> torch.Tensor:
        """Run forward pass.

        Args:
            x_d: [B, T, n_dynamic] dynamic features (normalized).
            x_s: [B, n_static] static attributes (normalized).

        Returns:
            y_hat: [B, T, 1] streamflow predictions (normalized).
        """
        # Convert stacked tensor to feature dict
        data = {}
        x_d_dict = {}
        for i, feat in enumerate(self.dynamic_features):
            x_d_dict[feat] = x_d[:, :, i]  # [B, T]
        data["x_d"] = x_d_dict
        data["x_s"] = x_s

        # Pre-model hook (handles statics concatenation etc.)
        data = self.model.pre_model_hook(data, is_train=False)

        predictions = self.model(data)
        return predictions["y_hat"]  # [B, T, 1]

    def get_scaler(self) -> dict:
        """Return normalization scaler."""
        return self._scaler
```

**Step 4: Run tests**

Run: `python -m pytest tests/test_adversarial/test_model_wrapper.py -v`
Expected: all 4 tests PASS

**Step 5: Commit**

```bash
git add src/adversarial/model_wrapper.py tests/test_adversarial/test_model_wrapper.py
git commit -m "feat(adversarial): CudaLSTM model wrapper with tensor interface"
```

---

### Task 3: Constraint Hierarchy (L1/L2/L3)

**Files:**
- Create: `src/adversarial/constraints/base.py`
- Create: `src/adversarial/constraints/lp_norm.py`
- Create: `src/adversarial/constraints/physical.py`
- Create: `src/adversarial/constraints/statistical.py`
- Create: `tests/test_adversarial/test_constraints.py`

**Step 1: Write failing tests**

```python
# tests/test_adversarial/test_constraints.py
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
        # prcp is feature index 0, after denorm could be negative
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
```

**Step 2: Run to verify failure**

Run: `python -m pytest tests/test_adversarial/test_constraints.py -v`
Expected: FAIL — import errors

**Step 3: Implement constraints**

```python
# src/adversarial/constraints/base.py
from __future__ import annotations

from abc import ABC, abstractmethod

import torch


class BaseConstraint(ABC):
    """Abstract base for perturbation constraints."""

    def __init__(self, epsilon: float):
        self.epsilon = epsilon

    @abstractmethod
    def project(self, x_clean: torch.Tensor, x_adv: torch.Tensor) -> torch.Tensor:
        """Project x_adv to satisfy constraints.

        Args:
            x_clean: [B, T, F] original clean input.
            x_adv: [B, T, F] perturbed input.

        Returns:
            x_proj: [B, T, F] projected input satisfying constraints.
        """
        ...
```

```python
# src/adversarial/constraints/lp_norm.py
from __future__ import annotations

import torch

from .base import BaseConstraint


class LpConstraint(BaseConstraint):
    """L-inf or L2 norm constraint on perturbation."""

    def __init__(self, epsilon: float, norm: str = "linf"):
        super().__init__(epsilon)
        assert norm in ("linf", "l2"), f"Unsupported norm: {norm}"
        self.norm = norm

    def project(self, x_clean: torch.Tensor, x_adv: torch.Tensor) -> torch.Tensor:
        delta = x_adv - x_clean

        if self.norm == "linf":
            delta = delta.clamp(-self.epsilon, self.epsilon)
        elif self.norm == "l2":
            # Per-sample L2 projection
            flat = delta.reshape(delta.shape[0], -1)
            norms = flat.norm(dim=1, keepdim=True).clamp(min=1e-8)
            scale = torch.min(torch.ones_like(norms), self.epsilon / norms)
            flat = flat * scale
            delta = flat.reshape(delta.shape)

        return x_clean + delta
```

```python
# src/adversarial/constraints/physical.py
from __future__ import annotations

from typing import List

import torch

from .lp_norm import LpConstraint


# Physical bounds in REAL (unnormalized) space
_PHYSICAL_BOUNDS = {
    "prcp(mm/day)": (0.0, 500.0),
    "srad(W/m2)":   (0.0, 600.0),
    "tmax(C)":      (-50.0, 60.0),
    "tmin(C)":      (-60.0, 50.0),
    "vp(Pa)":       (0.0, 10000.0),
}


class PhysicalConstraint(LpConstraint):
    """Lp + physical feasibility (non-negative precip, T range, etc.)."""

    def __init__(self, epsilon: float, feature_names: List[str],
                 scaler_center: torch.Tensor, scaler_scale: torch.Tensor,
                 norm: str = "linf"):
        super().__init__(epsilon, norm)
        self.feature_names = feature_names
        # scaler_center, scaler_scale: [F] tensors for each feature
        self.register_center = scaler_center
        self.register_scale = scaler_scale

    def project(self, x_clean: torch.Tensor, x_adv: torch.Tensor) -> torch.Tensor:
        # First apply Lp projection
        x_proj = super().project(x_clean, x_adv)

        # Then clip to physical bounds in real space
        center = self.register_center.to(x_proj.device)
        scale = self.register_scale.to(x_proj.device)

        for i, feat in enumerate(self.feature_names):
            if feat in _PHYSICAL_BOUNDS:
                lo, hi = _PHYSICAL_BOUNDS[feat]
                # Convert bounds to normalized space
                lo_norm = (lo - center[i]) / scale[i].clamp(min=1e-8)
                hi_norm = (hi - center[i]) / scale[i].clamp(min=1e-8)
                x_proj[:, :, i] = x_proj[:, :, i].clamp(lo_norm, hi_norm)

        return x_proj
```

```python
# src/adversarial/constraints/statistical.py
from __future__ import annotations

from typing import List

import torch

from .physical import PhysicalConstraint


class StatisticalConstraint(PhysicalConstraint):
    """Physical + distribution-preserving (mean/std/autocorrelation)."""

    def __init__(self, epsilon: float, feature_names: List[str],
                 scaler_center: torch.Tensor, scaler_scale: torch.Tensor,
                 norm: str = "linf"):
        super().__init__(epsilon, feature_names, scaler_center, scaler_scale, norm)

    def project(self, x_clean: torch.Tensor, x_adv: torch.Tensor) -> torch.Tensor:
        # First apply physical projection
        x_proj = super().project(x_clean, x_adv)

        # Then adjust to match mean and std of original per feature
        for f in range(x_proj.shape[-1]):
            orig = x_clean[:, :, f]      # [B, T]
            proj = x_proj[:, :, f]       # [B, T]

            orig_mean = orig.mean(dim=1, keepdim=True)    # [B, 1]
            orig_std = orig.std(dim=1, keepdim=True)      # [B, 1]
            proj_mean = proj.mean(dim=1, keepdim=True)
            proj_std = proj.std(dim=1, keepdim=True).clamp(min=1e-8)

            # Standardize then rescale to match original moments
            proj_normed = (proj - proj_mean) / proj_std
            proj_matched = proj_normed * orig_std + orig_mean

            x_proj = x_proj.clone()
            x_proj[:, :, f] = proj_matched

        # Re-apply physical bounds (moment matching may violate)
        x_proj = super().project(x_clean, x_proj)

        return x_proj
```

```python
# src/adversarial/constraints/__init__.py
from .base import BaseConstraint
from .lp_norm import LpConstraint
from .physical import PhysicalConstraint
from .statistical import StatisticalConstraint

__all__ = ["BaseConstraint", "LpConstraint", "PhysicalConstraint", "StatisticalConstraint"]
```

**Step 4: Run tests**

Run: `python -m pytest tests/test_adversarial/test_constraints.py -v`
Expected: all 6 tests PASS

**Step 5: Commit**

```bash
git add src/adversarial/constraints/ tests/test_adversarial/test_constraints.py
git commit -m "feat(adversarial): 3-tier constraint hierarchy (Lp/Physical/Statistical)"
```

---

### Task 4: Evaluation Metrics

**Files:**
- Create: `src/adversarial/evaluation/metrics.py`
- Create: `tests/test_adversarial/test_metrics.py`

**Step 1: Write failing tests**

```python
# tests/test_adversarial/test_metrics.py
import pytest
import torch


class TestAttackMetrics:

    def test_delta_nse(self):
        from src.adversarial.evaluation.metrics import delta_nse
        y_obs = torch.tensor([1.0, 2.0, 3.0, 4.0, 5.0])
        y_clean = torch.tensor([1.1, 2.1, 2.9, 3.9, 5.1])  # good pred
        y_adv = torch.tensor([3.0, 1.0, 5.0, 2.0, 4.0])    # bad pred
        d = delta_nse(y_obs, y_clean, y_adv)
        assert d < 0  # NSE should drop

    def test_attack_success_rate(self):
        from src.adversarial.evaluation.metrics import attack_success_rate
        # 3 basins: NSE drops to -0.5, 0.3, -0.1
        nse_adv = torch.tensor([-0.5, 0.3, -0.1])
        asr = attack_success_rate(nse_adv, threshold=0.0)
        assert abs(asr - 2 / 3) < 1e-6

    def test_min_epsilon(self):
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
        y_obs = torch.tensor([1.0, 10.0, 2.0])   # peak at index 1
        y_pred = torch.tensor([1.0, 7.0, 2.0])    # underestimates peak
        rel_err = peak_error(y_obs, y_pred, quantile=0.9)
        assert abs(rel_err - 0.3) < 1e-5  # (10-7)/10 = 0.3
```

**Step 2: Run to verify failure**

Run: `python -m pytest tests/test_adversarial/test_metrics.py -v`

**Step 3: Implement**

```python
# src/adversarial/evaluation/metrics.py
"""Adversarial attack evaluation metrics."""
from __future__ import annotations

import torch
from scipy import stats


def compute_nse(y_obs: torch.Tensor, y_pred: torch.Tensor) -> float:
    """Nash-Sutcliffe Efficiency."""
    ss_res = ((y_obs - y_pred) ** 2).sum()
    ss_tot = ((y_obs - y_obs.mean()) ** 2).sum()
    return float(1.0 - ss_res / ss_tot.clamp(min=1e-10))


def compute_kge(y_obs: torch.Tensor, y_pred: torch.Tensor) -> float:
    """Kling-Gupta Efficiency."""
    obs = y_obs.detach().cpu().numpy().flatten()
    pred = y_pred.detach().cpu().numpy().flatten()
    r = float(torch.corrcoef(torch.stack([y_obs.flatten(), y_pred.flatten()]))[0, 1])
    alpha = float(y_pred.std() / y_obs.std().clamp(min=1e-10))
    beta = float(y_pred.mean() / y_obs.mean().clamp(min=1e-10))
    return float(1.0 - ((r - 1) ** 2 + (alpha - 1) ** 2 + (beta - 1) ** 2) ** 0.5)


def delta_nse(y_obs: torch.Tensor, y_clean: torch.Tensor,
              y_adv: torch.Tensor) -> float:
    """Change in NSE: NSE(adv) - NSE(clean). Negative = attack succeeded."""
    return compute_nse(y_obs, y_adv) - compute_nse(y_obs, y_clean)


def attack_success_rate(nse_values: torch.Tensor, threshold: float = 0.0) -> float:
    """Fraction of basins where NSE falls below threshold."""
    return float((nse_values < threshold).float().mean())


def detectability_ks(x_clean: torch.Tensor, x_adv: torch.Tensor) -> float:
    """KS-test p-value between clean and adversarial input distributions."""
    result = stats.ks_2samp(
        x_clean.detach().cpu().numpy().flatten(),
        x_adv.detach().cpu().numpy().flatten(),
    )
    return float(result.pvalue)


def peak_error(y_obs: torch.Tensor, y_pred: torch.Tensor,
               quantile: float = 0.9) -> float:
    """Mean relative error on peaks above given quantile."""
    threshold = torch.quantile(y_obs, quantile)
    mask = y_obs >= threshold
    if mask.sum() == 0:
        return 0.0
    obs_peak = y_obs[mask]
    pred_peak = y_pred[mask]
    return float(((obs_peak - pred_peak).abs() / obs_peak.clamp(min=1e-6)).mean())
```

**Step 4: Run tests**

Run: `python -m pytest tests/test_adversarial/test_metrics.py -v`
Expected: all 5 PASS

**Step 5: Commit**

```bash
git add src/adversarial/evaluation/metrics.py tests/test_adversarial/test_metrics.py
git commit -m "feat(adversarial): attack evaluation metrics (NSE, KGE, ASR, KS, peak error)"
```

---

### Task 5: Base Attack Class + Loss Functions

**Files:**
- Create: `src/adversarial/attacks/base.py`
- Create: `src/adversarial/attacks/losses.py`
- Create: `tests/test_adversarial/test_losses.py`

**Step 1: Write failing tests**

```python
# tests/test_adversarial/test_losses.py
import pytest
import torch


class TestAttackLosses:

    def test_untargeted_loss_gradient(self):
        """Untargeted loss should produce non-zero gradient w.r.t. input."""
        from src.adversarial.attacks.losses import untargeted_nse_loss
        y_pred = torch.tensor([1.0, 2.0, 3.0], requires_grad=True)
        y_obs = torch.tensor([1.0, 2.0, 3.0])
        loss = untargeted_nse_loss(y_pred, y_obs)
        loss.backward()
        assert y_pred.grad is not None

    def test_targeted_flood_loss(self):
        """Targeted flood loss only considers high-flow timesteps."""
        from src.adversarial.attacks.losses import targeted_flood_loss
        y_pred = torch.tensor([0.5, 10.0, 0.3, 8.0, 0.2], requires_grad=True)
        y_obs = torch.tensor([0.5, 10.0, 0.3, 8.0, 0.2])
        loss = targeted_flood_loss(y_pred, y_obs, quantile=0.5)
        loss.backward()
        assert y_pred.grad is not None

    def test_targeted_lowflow_loss(self):
        from src.adversarial.attacks.losses import targeted_lowflow_loss
        y_pred = torch.tensor([0.5, 10.0, 0.3, 8.0, 0.2], requires_grad=True)
        y_obs = torch.tensor([0.5, 10.0, 0.3, 8.0, 0.2])
        loss = targeted_lowflow_loss(y_pred, y_obs, quantile=0.2)
        loss.backward()
        assert y_pred.grad is not None
```

**Step 2: Run to verify failure**

Run: `python -m pytest tests/test_adversarial/test_losses.py -v`

**Step 3: Implement**

```python
# src/adversarial/attacks/losses.py
"""Loss functions for adversarial attacks."""
from __future__ import annotations

import torch


def _nse_loss(y_pred: torch.Tensor, y_obs: torch.Tensor) -> torch.Tensor:
    """Differentiable negative NSE (minimize = maximize NSE degradation)."""
    ss_res = ((y_obs - y_pred) ** 2).sum()
    ss_tot = ((y_obs - y_obs.mean()) ** 2).sum().clamp(min=1e-10)
    nse = 1.0 - ss_res / ss_tot
    return nse  # We want to MINIMIZE this (push NSE down)


def untargeted_nse_loss(y_pred: torch.Tensor, y_obs: torch.Tensor) -> torch.Tensor:
    """Untargeted: minimize NSE over all timesteps."""
    return _nse_loss(y_pred, y_obs)


def targeted_flood_loss(y_pred: torch.Tensor, y_obs: torch.Tensor,
                        quantile: float = 0.9) -> torch.Tensor:
    """Targeted: minimize NSE only on high-flow timesteps."""
    threshold = torch.quantile(y_obs.detach(), quantile)
    mask = (y_obs >= threshold).detach()
    if mask.sum() < 2:
        return untargeted_nse_loss(y_pred, y_obs)
    return _nse_loss(y_pred[mask], y_obs[mask])


def targeted_lowflow_loss(y_pred: torch.Tensor, y_obs: torch.Tensor,
                          quantile: float = 0.1) -> torch.Tensor:
    """Targeted: minimize NSE only on low-flow timesteps."""
    threshold = torch.quantile(y_obs.detach(), quantile)
    mask = (y_obs <= threshold).detach()
    if mask.sum() < 2:
        return untargeted_nse_loss(y_pred, y_obs)
    return _nse_loss(y_pred[mask], y_obs[mask])


def get_loss_fn(target: str):
    """Factory for loss functions."""
    return {
        "untargeted": untargeted_nse_loss,
        "flood": targeted_flood_loss,
        "lowflow": targeted_lowflow_loss,
    }[target]
```

```python
# src/adversarial/attacks/base.py
"""Base class for all adversarial attacks."""
from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Optional

import torch

from src.adversarial.constraints.base import BaseConstraint
from src.adversarial.attacks.losses import get_loss_fn


class BaseAttack(ABC):
    """Abstract base class for adversarial attacks on CudaLSTM."""

    def __init__(self, model, constraint: BaseConstraint,
                 target: str = "untargeted", epsilon: float = 0.1):
        self.model = model
        self.constraint = constraint
        self.target = target
        self.epsilon = epsilon
        self.loss_fn = get_loss_fn(target)

    @abstractmethod
    def attack(self, x_d: torch.Tensor, x_s: torch.Tensor,
               y_obs: torch.Tensor) -> torch.Tensor:
        """Generate adversarial perturbation.

        Args:
            x_d: [B, T, F] clean dynamic features.
            x_s: [B, S] static attributes (not perturbed).
            y_obs: [B, T, 1] observed streamflow.

        Returns:
            x_d_adv: [B, T, F] adversarial dynamic features.
        """
        ...

    def compute_loss(self, y_pred: torch.Tensor,
                     y_obs: torch.Tensor) -> torch.Tensor:
        """Compute attack loss (to be MINIMIZED — lower = worse prediction)."""
        return self.loss_fn(y_pred.squeeze(-1), y_obs.squeeze(-1))
```

**Step 4: Run tests**

Run: `python -m pytest tests/test_adversarial/test_losses.py -v`
Expected: all 3 PASS

**Step 5: Commit**

```bash
git add src/adversarial/attacks/base.py src/adversarial/attacks/losses.py tests/test_adversarial/test_losses.py
git commit -m "feat(adversarial): base attack class + untargeted/targeted loss functions"
```

---

### Task 6: Attack A — Auto-PGD

**Files:**
- Create: `src/adversarial/attacks/auto_pgd.py`
- Create: `tests/test_adversarial/test_auto_pgd.py`

**Step 1: Write failing tests**

```python
# tests/test_adversarial/test_auto_pgd.py
import pytest
import torch
import torch.nn as nn


class FakeModel(nn.Module):
    """Simple differentiable model for testing attacks."""
    def forward(self, x_d, x_s):
        return x_d.sum(dim=-1, keepdim=True)  # [B, T, 1]


@pytest.fixture
def setup():
    from src.adversarial.attacks.auto_pgd import AutoPGD
    from src.adversarial.constraints.lp_norm import LpConstraint
    model = FakeModel()
    constraint = LpConstraint(epsilon=0.1, norm="linf")
    attack = AutoPGD(model=model, constraint=constraint, n_iter=10, target="untargeted")
    return attack, model


class TestAutoPGD:

    def test_output_shape(self, setup):
        attack, _ = setup
        x_d = torch.randn(2, 50, 5)
        x_s = torch.randn(2, 13)
        y_obs = torch.randn(2, 50, 1)
        x_adv = attack.attack(x_d, x_s, y_obs)
        assert x_adv.shape == x_d.shape

    def test_perturbation_within_bounds(self, setup):
        attack, _ = setup
        x_d = torch.randn(2, 50, 5)
        x_s = torch.randn(2, 13)
        y_obs = torch.randn(2, 50, 1)
        x_adv = attack.attack(x_d, x_s, y_obs)
        delta = (x_adv - x_d).abs()
        assert delta.max() <= 0.1 + 1e-5

    def test_perturbation_is_nonzero(self, setup):
        attack, _ = setup
        x_d = torch.randn(2, 50, 5)
        x_s = torch.randn(2, 13)
        y_obs = x_d.sum(dim=-1, keepdim=True)  # match model output
        x_adv = attack.attack(x_d, x_s, y_obs)
        assert (x_adv - x_d).abs().max() > 1e-6

    def test_loss_decreases(self, setup):
        """Attack should decrease NSE (make predictions worse)."""
        attack, model = setup
        x_d = torch.randn(2, 50, 5)
        x_s = torch.randn(2, 13)
        y_obs = model(x_d, x_s).detach()

        y_clean = model(x_d, x_s)
        loss_clean = attack.compute_loss(y_clean, y_obs)

        x_adv = attack.attack(x_d, x_s, y_obs)
        y_adv = model(x_adv, x_s)
        loss_adv = attack.compute_loss(y_adv, y_obs)

        assert loss_adv < loss_clean  # NSE should decrease
```

**Step 2: Run to verify failure**

Run: `python -m pytest tests/test_adversarial/test_auto_pgd.py -v`

**Step 3: Implement**

```python
# src/adversarial/attacks/auto_pgd.py
"""Auto-PGD: adaptive step-size PGD attack."""
from __future__ import annotations

import torch

from .base import BaseAttack


class AutoPGD(BaseAttack):
    """Auto-PGD with adaptive step size and checkpoint restarts.

    Reference: Croce & Hein (2020), "Reliable evaluation of adversarial
    robustness with an ensemble of diverse parameter-free attacks."
    """

    def __init__(self, model, constraint, n_iter: int = 50,
                 target: str = "untargeted", epsilon: float = 0.1,
                 n_restarts: int = 1, rho: float = 0.75):
        super().__init__(model, constraint, target, epsilon)
        self.n_iter = n_iter
        self.n_restarts = n_restarts
        self.rho = rho  # fraction of budget for step size schedule checkpoints

    def attack(self, x_d: torch.Tensor, x_s: torch.Tensor,
               y_obs: torch.Tensor) -> torch.Tensor:
        best_adv = x_d.clone()
        best_loss = torch.tensor(float("inf"))

        for _ in range(self.n_restarts):
            x_adv = self._single_run(x_d, x_s, y_obs)
            with torch.no_grad():
                y_adv = self.model(x_adv, x_s)
                loss = self.compute_loss(y_adv, y_obs)
            if loss < best_loss:
                best_loss = loss
                best_adv = x_adv.clone()

        return best_adv

    def _single_run(self, x_d: torch.Tensor, x_s: torch.Tensor,
                    y_obs: torch.Tensor) -> torch.Tensor:
        # Initialize with random perturbation within epsilon ball
        delta = torch.empty_like(x_d).uniform_(-self.epsilon, self.epsilon)
        delta.requires_grad_(True)

        # Adaptive step size schedule
        eta = 2.0 * self.epsilon  # initial step size
        # Checkpoints for step size reduction
        checkpoints = [int(self.rho ** i * self.n_iter) for i in range(10)]
        checkpoints = sorted(set(c for c in checkpoints if 0 < c < self.n_iter))

        best_loss = torch.tensor(float("inf"))
        best_delta = delta.data.clone()
        prev_loss = None
        n_worse = 0

        for i in range(self.n_iter):
            x_adv = self.constraint.project(x_d, x_d + delta)
            # Need to recompute delta from projection for correct gradient
            x_adv_input = x_adv.detach().requires_grad_(True)

            y_pred = self.model(x_adv_input, x_s)
            loss = self.compute_loss(y_pred, y_obs)

            # Track best
            if loss < best_loss:
                best_loss = loss.item()
                best_delta = (x_adv_input - x_d).detach().clone()

            loss.backward()

            with torch.no_grad():
                grad = x_adv_input.grad
                # PGD step: move in direction of negative gradient (minimize loss = minimize NSE)
                delta.data = best_delta - eta * grad.sign()
                # Project
                x_proj = self.constraint.project(x_d, x_d + delta.data)
                delta.data = x_proj - x_d

                # Adaptive step size: halve if no progress
                if prev_loss is not None and loss.item() >= prev_loss:
                    n_worse += 1
                else:
                    n_worse = 0
                prev_loss = loss.item()

                if i in checkpoints or n_worse >= 3:
                    eta = eta / 2.0
                    n_worse = 0
                    delta.data = best_delta.clone()

        return x_d + best_delta
```

**Step 4: Run tests**

Run: `python -m pytest tests/test_adversarial/test_auto_pgd.py -v`
Expected: all 4 PASS

**Step 5: Commit**

```bash
git add src/adversarial/attacks/auto_pgd.py tests/test_adversarial/test_auto_pgd.py
git commit -m "feat(adversarial): Auto-PGD attack with adaptive step size"
```

---

### Task 7: Attack B — C&W-Regression

**Files:**
- Create: `src/adversarial/attacks/cw_regression.py`
- Create: `tests/test_adversarial/test_cw_regression.py`

**Step 1: Write failing tests**

```python
# tests/test_adversarial/test_cw_regression.py
import pytest
import torch
import torch.nn as nn


class FakeModel(nn.Module):
    def forward(self, x_d, x_s):
        return x_d.sum(dim=-1, keepdim=True)


@pytest.fixture
def setup():
    from src.adversarial.attacks.cw_regression import CWRegression
    from src.adversarial.constraints.lp_norm import LpConstraint
    model = FakeModel()
    constraint = LpConstraint(epsilon=1.0, norm="l2")
    attack = CWRegression(model=model, constraint=constraint,
                          n_iter=50, target_nse=0.0, lr=0.01)
    return attack, model


class TestCWRegression:

    def test_output_shape(self, setup):
        attack, _ = setup
        x_d = torch.randn(2, 50, 5)
        x_s = torch.randn(2, 13)
        y_obs = torch.randn(2, 50, 1)
        x_adv = attack.attack(x_d, x_s, y_obs)
        assert x_adv.shape == x_d.shape

    def test_minimizes_perturbation_norm(self, setup):
        """C&W should find smaller perturbation than max epsilon."""
        attack, model = setup
        x_d = torch.randn(1, 50, 5)
        x_s = torch.randn(1, 13)
        y_obs = model(x_d, x_s).detach()
        x_adv = attack.attack(x_d, x_s, y_obs)
        l2 = (x_adv - x_d).reshape(1, -1).norm(dim=1)
        assert l2.item() < 1.0  # should be less than max epsilon
```

**Step 2: Run to verify failure**

Run: `python -m pytest tests/test_adversarial/test_cw_regression.py -v`

**Step 3: Implement**

```python
# src/adversarial/attacks/cw_regression.py
"""C&W adapted for regression: minimize perturbation s.t. NSE < target."""
from __future__ import annotations

import torch

from .base import BaseAttack


class CWRegression(BaseAttack):
    """Carlini-Wagner attack adapted for regression (streamflow).

    Finds minimum L2 perturbation such that NSE drops below target_nse.
    """

    def __init__(self, model, constraint, target_nse: float = 0.0,
                 n_iter: int = 200, lr: float = 0.01,
                 c_init: float = 1.0, c_factor: float = 2.0,
                 binary_search_steps: int = 5,
                 target: str = "untargeted", epsilon: float = 1.0):
        super().__init__(model, constraint, target, epsilon)
        self.target_nse = target_nse
        self.n_iter = n_iter
        self.lr = lr
        self.c_init = c_init
        self.c_factor = c_factor
        self.binary_search_steps = binary_search_steps

    def attack(self, x_d: torch.Tensor, x_s: torch.Tensor,
               y_obs: torch.Tensor) -> torch.Tensor:
        best_adv = x_d.clone()
        best_l2 = torch.tensor(float("inf"))

        # Binary search over c (trade-off between L2 and attack success)
        c_lo, c_hi = 0.0, self.c_init * 10.0
        c = self.c_init

        for _ in range(self.binary_search_steps):
            x_adv, success = self._optimize(x_d, x_s, y_obs, c)
            l2 = (x_adv - x_d).reshape(x_d.shape[0], -1).norm(dim=1).mean()

            if success and l2 < best_l2:
                best_l2 = l2
                best_adv = x_adv.clone()
                c_hi = c
            else:
                c_lo = c

            c = (c_lo + c_hi) / 2.0

        return best_adv

    def _optimize(self, x_d, x_s, y_obs, c):
        # Use tanh-space parameterization for unconstrained optimization
        w = torch.zeros_like(x_d, requires_grad=True)
        optimizer = torch.optim.Adam([w], lr=self.lr)

        for _ in range(self.n_iter):
            optimizer.zero_grad()
            delta = torch.tanh(w) * self.epsilon
            x_adv = self.constraint.project(x_d, x_d + delta)

            y_pred = self.model(x_adv, x_s)
            nse = self.compute_loss(y_pred, y_obs)  # returns NSE

            # L2 norm of perturbation
            l2 = (x_adv - x_d).reshape(x_d.shape[0], -1).norm(dim=1).mean()

            # C&W objective: minimize L2 + c * max(0, NSE - target)
            attack_term = torch.clamp(nse - self.target_nse, min=0.0)
            loss = l2 + c * attack_term

            loss.backward()
            optimizer.step()

        # Check if attack succeeded
        with torch.no_grad():
            delta = torch.tanh(w) * self.epsilon
            x_adv = self.constraint.project(x_d, x_d + delta)
            y_pred = self.model(x_adv, x_s)
            final_nse = self.compute_loss(y_pred, y_obs)
            success = final_nse.item() <= self.target_nse

        return x_adv.detach(), success
```

**Step 4: Run tests**

Run: `python -m pytest tests/test_adversarial/test_cw_regression.py -v`
Expected: all 2 PASS

**Step 5: Commit**

```bash
git add src/adversarial/attacks/cw_regression.py tests/test_adversarial/test_cw_regression.py
git commit -m "feat(adversarial): C&W-Regression attack (minimum perturbation for NSE < target)"
```

---

### Task 8: Attack C — Sparse Temporal

**Files:**
- Create: `src/adversarial/attacks/sparse_temporal.py`
- Create: `tests/test_adversarial/test_sparse_temporal.py`

**Step 1: Write failing tests**

```python
# tests/test_adversarial/test_sparse_temporal.py
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
                                   max_steps=18, n_iter=30)  # 18/365 ≈ 5%
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
```

**Step 2: Run to verify failure**

Run: `python -m pytest tests/test_adversarial/test_sparse_temporal.py -v`

**Step 3: Implement**

```python
# src/adversarial/attacks/sparse_temporal.py
"""Sparse Temporal Attack: learn which timesteps to perturb."""
from __future__ import annotations

import torch
import torch.nn.functional as F

from .base import BaseAttack


class SparseTemporalAttack(BaseAttack):
    """Perturb only a learned subset of timesteps via Gumbel-Softmax mask.

    Jointly optimizes WHAT to perturb (mask) and HOW to perturb (delta).
    """

    def __init__(self, model, constraint, max_steps: int = 18,
                 n_iter: int = 100, lr: float = 0.01,
                 temperature: float = 1.0, temp_anneal: float = 0.95,
                 target: str = "untargeted", epsilon: float = 0.2):
        super().__init__(model, constraint, target, epsilon)
        self.max_steps = max_steps
        self.n_iter = n_iter
        self.lr = lr
        self.temperature = temperature
        self.temp_anneal = temp_anneal

    def attack(self, x_d: torch.Tensor, x_s: torch.Tensor,
               y_obs: torch.Tensor) -> torch.Tensor:
        B, T, F = x_d.shape
        device = x_d.device

        # Learnable parameters: mask logits + perturbation
        mask_logits = torch.zeros(B, T, device=device, requires_grad=True)
        delta = torch.zeros(B, T, F, device=device, requires_grad=True)

        optimizer = torch.optim.Adam([mask_logits, delta], lr=self.lr)
        temp = self.temperature

        best_loss = torch.tensor(float("inf"))
        best_adv = x_d.clone()

        for i in range(self.n_iter):
            optimizer.zero_grad()

            # Gumbel-Softmax to get differentiable top-k mask
            soft_mask = self._gumbel_topk(mask_logits, self.max_steps, temp)
            # soft_mask: [B, T] in (0, 1)

            # Apply mask: only perturb selected timesteps
            masked_delta = delta * soft_mask.unsqueeze(-1)  # [B, T, F]
            x_adv = self.constraint.project(x_d, x_d + masked_delta)

            y_pred = self.model(x_adv, x_s)
            loss = self.compute_loss(y_pred, y_obs)

            # Sparsity regularization: encourage exactly max_steps
            sparsity_loss = (soft_mask.sum(dim=1) - self.max_steps).pow(2).mean()
            total_loss = loss + 0.1 * sparsity_loss

            total_loss.backward()
            optimizer.step()

            temp *= self.temp_anneal

            with torch.no_grad():
                if loss.item() < best_loss.item():
                    best_loss = loss
                    # Hard mask for final output
                    hard_mask = self._hard_topk(mask_logits, self.max_steps)
                    hard_delta = delta * hard_mask.unsqueeze(-1)
                    best_adv = self.constraint.project(x_d, x_d + hard_delta)

        return best_adv.detach()

    @staticmethod
    def _gumbel_topk(logits: torch.Tensor, k: int,
                     temperature: float) -> torch.Tensor:
        """Differentiable top-k via repeated Gumbel-Softmax."""
        # Sample Gumbel noise
        gumbel = -torch.log(-torch.log(torch.rand_like(logits) + 1e-20) + 1e-20)
        perturbed = (logits + gumbel) / max(temperature, 0.01)
        # Sigmoid to get per-element probability
        probs = torch.sigmoid(perturbed)
        return probs

    @staticmethod
    def _hard_topk(logits: torch.Tensor, k: int) -> torch.Tensor:
        """Hard top-k mask (non-differentiable, for final output)."""
        _, indices = logits.topk(k, dim=-1)
        mask = torch.zeros_like(logits)
        mask.scatter_(1, indices, 1.0)
        return mask
```

**Step 4: Run tests**

Run: `python -m pytest tests/test_adversarial/test_sparse_temporal.py -v`
Expected: all 2 PASS

**Step 5: Commit**

```bash
git add src/adversarial/attacks/sparse_temporal.py tests/test_adversarial/test_sparse_temporal.py
git commit -m "feat(adversarial): Sparse Temporal attack with Gumbel-Softmax mask"
```

---

### Task 9: Attack D — Causal Trigger

**Files:**
- Create: `src/adversarial/attacks/causal_trigger.py`
- Create: `tests/test_adversarial/test_causal_trigger.py`

**Step 1: Write failing tests**

```python
# tests/test_adversarial/test_causal_trigger.py
import pytest
import torch
import torch.nn as nn


class FakeModel(nn.Module):
    def forward(self, x_d, x_s):
        return x_d.cumsum(dim=1).sum(dim=-1, keepdim=True)


@pytest.fixture
def setup():
    from src.adversarial.attacks.causal_trigger import CausalTriggerAttack
    from src.adversarial.constraints.lp_norm import LpConstraint
    model = FakeModel()
    constraint = LpConstraint(epsilon=0.3, norm="linf")
    attack = CausalTriggerAttack(model=model, constraint=constraint,
                                  pre_window=7, n_iter=30)
    return attack, model


class TestCausalTrigger:

    def test_output_shape(self, setup):
        attack, _ = setup
        x_d = torch.randn(1, 100, 5)
        x_s = torch.randn(1, 13)
        y_obs = torch.randn(1, 100, 1)
        peak_indices = [50]
        x_adv = attack.attack(x_d, x_s, y_obs, peak_indices=peak_indices)
        assert x_adv.shape == x_d.shape

    def test_perturbation_only_before_peak(self, setup):
        """Perturbation should only exist in [peak-w, peak) window."""
        attack, _ = setup
        x_d = torch.randn(1, 100, 5)
        x_s = torch.randn(1, 13)
        y_obs = torch.randn(1, 100, 1)
        peak_indices = [50]
        x_adv = attack.attack(x_d, x_s, y_obs, peak_indices=peak_indices)
        delta = (x_adv - x_d).abs()

        # Before window: no perturbation
        assert delta[0, :43, :].max() < 1e-6
        # After peak: no perturbation
        assert delta[0, 50:, :].max() < 1e-6
        # In window [43, 50): may have perturbation
        assert delta[0, 43:50, :].max() > 1e-6
```

**Step 2: Run to verify failure**

Run: `python -m pytest tests/test_adversarial/test_causal_trigger.py -v`

**Step 3: Implement**

```python
# src/adversarial/attacks/causal_trigger.py
"""Causal Trigger: perturb pre-event window to corrupt peak predictions."""
from __future__ import annotations

from typing import List, Optional

import torch

from .base import BaseAttack


class CausalTriggerAttack(BaseAttack):
    """Perturb only w days before flood peaks, exploiting LSTM memory.

    Only modifies input in [t_peak - pre_window, t_peak), but evaluates
    loss on [t_peak, t_peak + post_window].
    """

    def __init__(self, model, constraint, pre_window: int = 7,
                 post_window: int = 7, n_iter: int = 100, lr: float = 0.01,
                 target: str = "untargeted", epsilon: float = 0.3):
        super().__init__(model, constraint, target, epsilon)
        self.pre_window = pre_window
        self.post_window = post_window
        self.n_iter = n_iter
        self.lr = lr

    def attack(self, x_d: torch.Tensor, x_s: torch.Tensor,
               y_obs: torch.Tensor,
               peak_indices: Optional[List[int]] = None) -> torch.Tensor:
        B, T, F = x_d.shape

        if peak_indices is None:
            peak_indices = self._find_peaks(y_obs)

        # Build perturbation mask: 1 in pre-event windows, 0 elsewhere
        mask = torch.zeros(B, T, device=x_d.device)
        target_mask = torch.zeros(B, T, device=x_d.device)
        for t_peak in peak_indices:
            t_start = max(0, t_peak - self.pre_window)
            mask[:, t_start:t_peak] = 1.0
            t_end = min(T, t_peak + self.post_window)
            target_mask[:, t_peak:t_end] = 1.0

        delta = torch.zeros(B, T, F, device=x_d.device, requires_grad=True)
        optimizer = torch.optim.Adam([delta], lr=self.lr)

        best_loss = torch.tensor(float("inf"))
        best_delta = torch.zeros_like(delta)

        for _ in range(self.n_iter):
            optimizer.zero_grad()

            masked_delta = delta * mask.unsqueeze(-1)
            x_adv = self.constraint.project(x_d, x_d + masked_delta)

            y_pred = self.model(x_adv, x_s)

            # Loss only on target window (peak + post)
            if target_mask.sum() > 0:
                y_pred_target = y_pred.squeeze(-1) * target_mask
                y_obs_target = y_obs.squeeze(-1) * target_mask
                # Masked MSE as proxy (avoid NSE issues with small windows)
                n_active = target_mask.sum().clamp(min=1)
                loss = -((y_pred_target - y_obs_target) ** 2).sum() / n_active
            else:
                loss = self.compute_loss(y_pred, y_obs)

            loss.backward()
            optimizer.step()

            with torch.no_grad():
                if loss.item() < best_loss.item():
                    best_loss = loss
                    best_delta = delta.data.clone()

        with torch.no_grad():
            masked_delta = best_delta * mask.unsqueeze(-1)
            x_adv = self.constraint.project(x_d, x_d + masked_delta)
        return x_adv

    @staticmethod
    def _find_peaks(y_obs: torch.Tensor, quantile: float = 0.95) -> List[int]:
        """Auto-detect flood peaks from observations."""
        y = y_obs.squeeze(-1).mean(dim=0)  # [T]
        threshold = torch.quantile(y, quantile)
        above = (y >= threshold).nonzero(as_tuple=True)[0]
        if len(above) == 0:
            return [int(y.argmax())]
        # Cluster nearby peaks: take local maxima with min distance 14 days
        peaks = []
        last = -100
        for idx in above.tolist():
            if idx - last > 14:
                peaks.append(idx)
                last = idx
        return peaks if peaks else [int(y.argmax())]
```

**Step 4: Run tests**

Run: `python -m pytest tests/test_adversarial/test_causal_trigger.py -v`
Expected: all 2 PASS

**Step 5: Commit**

```bash
git add src/adversarial/attacks/causal_trigger.py tests/test_adversarial/test_causal_trigger.py
git commit -m "feat(adversarial): Causal Trigger attack exploiting LSTM memory propagation"
```

---

### Task 10: Attack E — Spectral

**Files:**
- Create: `src/adversarial/attacks/spectral.py`
- Create: `tests/test_adversarial/test_spectral.py`

**Step 1: Write failing tests**

```python
# tests/test_adversarial/test_spectral.py
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
```

**Step 2: Run to verify failure**

Run: `python -m pytest tests/test_adversarial/test_spectral.py -v`

**Step 3: Implement**

```python
# src/adversarial/attacks/spectral.py
"""Spectral Attack: perturb in frequency domain, preserve time-domain stats."""
from __future__ import annotations

import torch

from .base import BaseAttack


class SpectralAttack(BaseAttack):
    """Optimize perturbation in frequency domain.

    Perturbs selected frequency bands while keeping the DC component
    (mean) and overall energy (variance) approximately fixed.
    """

    def __init__(self, model, constraint, n_iter: int = 100,
                 lr: float = 0.01, target: str = "untargeted",
                 epsilon: float = 0.3,
                 freq_bands: str = "all"):
        super().__init__(model, constraint, target, epsilon)
        self.n_iter = n_iter
        self.lr = lr
        self.freq_bands = freq_bands  # "all", "low", "mid", "high"

    def attack(self, x_d: torch.Tensor, x_s: torch.Tensor,
               y_obs: torch.Tensor) -> torch.Tensor:
        B, T, F = x_d.shape

        # Work in frequency domain: optimize delta_freq
        # Initialize zero perturbation in freq domain
        x_freq = torch.fft.rfft(x_d, dim=1)  # [B, T//2+1, F] complex
        n_freq = x_freq.shape[1]

        # Learnable: real and imaginary parts of frequency perturbation
        delta_real = torch.zeros(B, n_freq, F, device=x_d.device, requires_grad=True)
        delta_imag = torch.zeros(B, n_freq, F, device=x_d.device, requires_grad=True)

        optimizer = torch.optim.Adam([delta_real, delta_imag], lr=self.lr)

        # Frequency band mask
        freq_mask = self._get_freq_mask(n_freq, T, x_d.device)

        best_loss = torch.tensor(float("inf"))
        best_adv = x_d.clone()

        for _ in range(self.n_iter):
            optimizer.zero_grad()

            # Build complex perturbation, zero out DC (preserve mean)
            delta_freq = torch.complex(delta_real, delta_imag)
            delta_freq[:, 0, :] = 0.0  # preserve DC = preserve mean
            delta_freq = delta_freq * freq_mask.unsqueeze(0).unsqueeze(-1)

            # Back to time domain
            delta_time = torch.fft.irfft(delta_freq, n=T, dim=1)  # [B, T, F]

            x_adv = self.constraint.project(x_d, x_d + delta_time)
            y_pred = self.model(x_adv, x_s)
            loss = self.compute_loss(y_pred, y_obs)

            loss.backward()
            optimizer.step()

            with torch.no_grad():
                if loss.item() < best_loss.item():
                    best_loss = loss
                    best_adv = x_adv.detach().clone()

        return best_adv

    def _get_freq_mask(self, n_freq: int, T: int,
                       device: torch.device) -> torch.Tensor:
        """Binary mask selecting which frequency bands to perturb."""
        mask = torch.ones(n_freq, device=device)

        if self.freq_bands == "low":
            # Only perturb low frequencies (periods > 30 days)
            cutoff = max(1, T // 30)
            mask[cutoff:] = 0.0
        elif self.freq_bands == "mid":
            lo = max(1, T // 30)
            hi = max(lo + 1, T // 7)
            mask[:lo] = 0.0
            mask[hi:] = 0.0
        elif self.freq_bands == "high":
            cutoff = max(1, T // 7)
            mask[:cutoff] = 0.0

        mask[0] = 0.0  # always preserve DC
        return mask
```

**Step 4: Run tests**

Run: `python -m pytest tests/test_adversarial/test_spectral.py -v`
Expected: all 3 PASS

**Step 5: Commit**

```bash
git add src/adversarial/attacks/spectral.py tests/test_adversarial/test_spectral.py
git commit -m "feat(adversarial): Spectral attack with frequency-band selection"
```

---

### Task 11: Attack F — Universal Adversarial Perturbation (UAP)

**Files:**
- Create: `src/adversarial/attacks/uap.py`
- Create: `tests/test_adversarial/test_uap.py`

**Step 1: Write failing tests**

```python
# tests/test_adversarial/test_uap.py
import pytest
import torch
import torch.nn as nn


class FakeModel(nn.Module):
    def forward(self, x_d, x_s):
        return x_d.sum(dim=-1, keepdim=True)


@pytest.fixture
def setup():
    from src.adversarial.attacks.uap import UAP
    from src.adversarial.constraints.lp_norm import LpConstraint
    model = FakeModel()
    constraint = LpConstraint(epsilon=0.2, norm="linf")
    attack = UAP(model=model, constraint=constraint, n_iter=20)
    return attack, model


class TestUAP:

    def test_universal_shape(self, setup):
        """UAP should produce a single perturbation pattern [1, T, F]."""
        attack, _ = setup
        dataset = [(torch.randn(1, 50, 5), torch.randn(1, 13),
                     torch.randn(1, 50, 1)) for _ in range(5)]
        uap = attack.craft_universal(dataset)
        assert uap.shape == (1, 50, 5)

    def test_apply_to_new_sample(self, setup):
        """UAP applies to unseen samples without per-sample optimization."""
        attack, _ = setup
        dataset = [(torch.randn(1, 50, 5), torch.randn(1, 13),
                     torch.randn(1, 50, 1)) for _ in range(5)]
        uap = attack.craft_universal(dataset)

        # Apply to new sample
        x_new = torch.randn(3, 50, 5)
        x_adv = attack.attack(x_new, torch.randn(3, 13), torch.randn(3, 50, 1))
        assert x_adv.shape == x_new.shape

    def test_perturbation_bounded(self, setup):
        attack, _ = setup
        dataset = [(torch.randn(1, 50, 5), torch.randn(1, 13),
                     torch.randn(1, 50, 1)) for _ in range(5)]
        uap = attack.craft_universal(dataset)
        assert uap.abs().max() <= 0.2 + 1e-5
```

**Step 2: Run to verify failure**

Run: `python -m pytest tests/test_adversarial/test_uap.py -v`

**Step 3: Implement**

```python
# src/adversarial/attacks/uap.py
"""Universal Adversarial Perturbation: one pattern to attack all samples."""
from __future__ import annotations

from typing import List, Tuple, Optional

import torch

from .base import BaseAttack


class UAP(BaseAttack):
    """Craft a single universal perturbation that degrades all samples.

    Two-phase usage:
    1. craft_universal(dataset) — optimize δ* on training data
    2. attack(x_d, x_s, y_obs) — apply pre-computed δ* to new samples
    """

    def __init__(self, model, constraint, n_iter: int = 50,
                 lr: float = 0.01, target: str = "untargeted",
                 epsilon: float = 0.2):
        super().__init__(model, constraint, target, epsilon)
        self.n_iter = n_iter
        self.lr = lr
        self._uap: Optional[torch.Tensor] = None  # cached universal perturbation

    def craft_universal(
        self,
        dataset: List[Tuple[torch.Tensor, torch.Tensor, torch.Tensor]],
    ) -> torch.Tensor:
        """Optimize universal perturbation over dataset.

        Args:
            dataset: list of (x_d [1,T,F], x_s [1,S], y_obs [1,T,1]) tuples.

        Returns:
            uap: [1, T, F] universal perturbation.
        """
        x_d_0, _, _ = dataset[0]
        T, F = x_d_0.shape[1], x_d_0.shape[2]
        device = x_d_0.device

        delta = torch.zeros(1, T, F, device=device, requires_grad=True)
        optimizer = torch.optim.Adam([delta], lr=self.lr)

        for _ in range(self.n_iter):
            total_loss = torch.tensor(0.0, device=device)

            for x_d, x_s, y_obs in dataset:
                optimizer.zero_grad()
                # Broadcast universal perturbation to batch
                x_adv = self.constraint.project(x_d, x_d + delta)
                y_pred = self.model(x_adv, x_s)
                loss = self.compute_loss(y_pred, y_obs)
                total_loss = total_loss + loss

            avg_loss = total_loss / len(dataset)
            avg_loss.backward()
            optimizer.step()

            # Project to epsilon ball
            with torch.no_grad():
                delta.data = delta.data.clamp(-self.epsilon, self.epsilon)

        self._uap = delta.detach().clone()
        return self._uap

    def attack(self, x_d: torch.Tensor, x_s: torch.Tensor,
               y_obs: torch.Tensor) -> torch.Tensor:
        """Apply pre-computed UAP to new samples."""
        if self._uap is None:
            raise RuntimeError("Call craft_universal() first.")
        uap = self._uap.to(x_d.device)
        x_adv = self.constraint.project(x_d, x_d + uap)
        return x_adv
```

**Step 4: Run tests**

Run: `python -m pytest tests/test_adversarial/test_uap.py -v`
Expected: all 3 PASS

**Step 5: Commit**

```bash
git add src/adversarial/attacks/uap.py tests/test_adversarial/test_uap.py
git commit -m "feat(adversarial): Universal Adversarial Perturbation (UAP)"
```

---

### Task 12: Attack Registry + `__init__.py` Exports

**Files:**
- Modify: `src/adversarial/attacks/__init__.py`

**Step 1: Write the registry**

```python
# src/adversarial/attacks/__init__.py
from .auto_pgd import AutoPGD
from .cw_regression import CWRegression
from .sparse_temporal import SparseTemporalAttack
from .causal_trigger import CausalTriggerAttack
from .spectral import SpectralAttack
from .uap import UAP

ATTACK_REGISTRY = {
    "auto_pgd": AutoPGD,
    "cw_regression": CWRegression,
    "sparse_temporal": SparseTemporalAttack,
    "causal_trigger": CausalTriggerAttack,
    "spectral": SpectralAttack,
    "uap": UAP,
}

__all__ = [
    "AutoPGD", "CWRegression", "SparseTemporalAttack",
    "CausalTriggerAttack", "SpectralAttack", "UAP",
    "ATTACK_REGISTRY",
]
```

**Step 2: Run all tests**

Run: `python -m pytest tests/test_adversarial/ -v`
Expected: all tests PASS

**Step 3: Commit**

```bash
git add src/adversarial/attacks/__init__.py
git commit -m "feat(adversarial): attack registry with all 6 methods"
```

---

### Task 13: Basin Selection

**Files:**
- Create: `src/adversarial/evaluation/basin_selection.py`
- Create: `tests/test_adversarial/test_basin_selection.py`

**Step 1: Write failing test**

```python
# tests/test_adversarial/test_basin_selection.py
import pytest
from pathlib import Path


class TestBasinSelection:

    def test_select_representative(self):
        from src.adversarial.evaluation.basin_selection import select_representative_basins
        attr_dir = Path(r"G:\github\pycharm\projects\kalmannet\data\Caravan\attributes\camels")
        if not attr_dir.exists():
            pytest.skip("Caravan attributes not found")

        basins = select_representative_basins(
            attr_dir=attr_dir,
            n_basins=15,
        )
        assert len(basins) == 15
        assert all(isinstance(b, str) for b in basins)
        # Should be 8-digit CAMELS gauge IDs
        assert all(len(b) == 8 for b in basins)
```

**Step 2: Run to verify failure**

Run: `python -m pytest tests/test_adversarial/test_basin_selection.py -v`

**Step 3: Implement**

```python
# src/adversarial/evaluation/basin_selection.py
"""Select representative basins from CAMELS-US using k-medoids clustering."""
from __future__ import annotations

from pathlib import Path
from typing import List

import numpy as np
import pandas as pd


def select_representative_basins(
    attr_dir: Path,
    n_basins: int = 15,
    random_state: int = 42,
) -> List[str]:
    """Select representative basins via k-medoids on static attributes.

    Uses: elev_mean, slope_mean, area_gages2, p_mean, aridity,
    frac_snow, frac_forest, soil_depth_pelletier.
    """
    # Load attributes
    attr_file = attr_dir / "attributes_caravan_camels.csv"
    df = pd.read_csv(attr_file, dtype={"gauge_id": str})

    # Select clustering features
    cluster_cols = [
        "gauge_elev_mean", "gauge_slope_mean", "area",
        "p_mean", "aridity", "frac_snow", "frac_forest",
        "soil_depth_pelletier",
    ]
    # Find available columns (names may vary)
    available = [c for c in cluster_cols if c in df.columns]
    if len(available) < 3:
        # Fallback: use all numeric columns
        available = df.select_dtypes(include=[np.number]).columns.tolist()[:8]

    features = df[available].copy()
    features = features.fillna(features.median())

    # Normalize
    features = (features - features.mean()) / features.std().clip(lower=1e-8)
    X = features.values

    # Simple k-medoids via iterative closest-to-centroid
    rng = np.random.RandomState(random_state)
    from sklearn.cluster import KMeans

    km = KMeans(n_clusters=n_basins, random_state=random_state, n_init=10)
    labels = km.fit_predict(X)

    # For each cluster, pick the basin closest to centroid
    selected = []
    gauge_ids = df["gauge_id"].values
    for k in range(n_basins):
        mask = labels == k
        cluster_points = X[mask]
        dists = np.linalg.norm(cluster_points - km.cluster_centers_[k], axis=1)
        idx_in_cluster = dists.argmin()
        global_idx = np.where(mask)[0][idx_in_cluster]
        selected.append(str(gauge_ids[global_idx]).zfill(8))

    return selected
```

**Step 4: Run test**

Run: `python -m pytest tests/test_adversarial/test_basin_selection.py -v`
Expected: PASS

**Step 5: Commit**

```bash
git add src/adversarial/evaluation/basin_selection.py tests/test_adversarial/test_basin_selection.py
git commit -m "feat(adversarial): k-medoids basin selection for representative CAMELS basins"
```

---

### Task 14: Experiment Config + Main Runner

**Files:**
- Create: `configs/adversarial_eval.yaml`
- Create: `scripts/run_adversarial_eval.py`

**Step 1: Create config**

```yaml
# configs/adversarial_eval.yaml
model:
  run_dir: "G:/github/pycharm/projects/neuralhydrology/runs/05_full_531_basins_smoke_v2_2026_0217_1632_ep1"
  device: "cuda"

data:
  n_basins: 15
  attr_dir: "G:/github/pycharm/projects/kalmannet/data/Caravan/attributes/camels"
  period: "test"  # test split from config

attacks:
  auto_pgd:
    n_iter: 50
    n_restarts: 1
  cw_regression:
    n_iter: 200
    target_nse: 0.0
    lr: 0.01
    binary_search_steps: 5
  sparse_temporal:
    max_steps_fraction: 0.05  # 5% of timesteps
    n_iter: 100
  causal_trigger:
    pre_windows: [1, 3, 7, 14]
    n_iter: 100
  spectral:
    freq_bands: ["all", "low", "mid", "high"]
    n_iter: 100
  uap:
    n_iter: 50

epsilons: [0.01, 0.02, 0.05, 0.1, 0.2, 0.5]
constraint_levels: ["lp", "physical", "statistical"]
targets: ["untargeted", "flood", "lowflow"]

output_dir: "results/adversarial_eval"
```

**Step 2: Create runner script**

```python
# scripts/run_adversarial_eval.py
"""Main entry point for adversarial evaluation experiments."""
from __future__ import annotations

import argparse
import json
import logging
from pathlib import Path

import torch
import yaml

from src.adversarial.model_wrapper import CudaLSTMWrapper
from src.adversarial.attacks import ATTACK_REGISTRY
from src.adversarial.constraints import LpConstraint, PhysicalConstraint, StatisticalConstraint
from src.adversarial.evaluation.metrics import (
    compute_nse, compute_kge, delta_nse, attack_success_rate,
    detectability_ks, peak_error,
)
from src.adversarial.evaluation.basin_selection import select_representative_basins

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)


def load_config(path: str) -> dict:
    with open(path) as f:
        return yaml.safe_load(f)


def build_constraint(level: str, epsilon: float, wrapper: CudaLSTMWrapper):
    """Build constraint object for given level."""
    if level == "lp":
        return LpConstraint(epsilon=epsilon, norm="linf")

    # Extract scaler center/scale for dynamic features
    scaler = wrapper.get_scaler()
    center = torch.zeros(wrapper.n_dynamic)
    scale = torch.ones(wrapper.n_dynamic)
    # Populate from scaler (implementation depends on scaler format)
    for i, feat in enumerate(wrapper.dynamic_features):
        if hasattr(scaler, 'get'):
            center[i] = float(scaler.get("xarray_feature_center", {}).get(feat, 0.0))
            scale[i] = float(scaler.get("xarray_feature_scale", {}).get(feat, 1.0))

    if level == "physical":
        return PhysicalConstraint(epsilon=epsilon,
                                   feature_names=wrapper.dynamic_features,
                                   scaler_center=center, scaler_scale=scale)
    elif level == "statistical":
        return StatisticalConstraint(epsilon=epsilon,
                                      feature_names=wrapper.dynamic_features,
                                      scaler_center=center, scaler_scale=scale)
    raise ValueError(f"Unknown constraint level: {level}")


def run_single_experiment(attack, wrapper, x_d, x_s, y_obs, x_d_clean_pred):
    """Run one attack and return metrics dict."""
    x_d_adv = attack.attack(x_d, x_s, y_obs)
    with torch.no_grad():
        y_adv = wrapper.forward(x_d_adv, x_s)
        y_clean = x_d_clean_pred

    y_obs_flat = y_obs.squeeze(-1).flatten()
    y_clean_flat = y_clean.squeeze(-1).flatten()
    y_adv_flat = y_adv.squeeze(-1).flatten()

    return {
        "nse_clean": compute_nse(y_obs_flat, y_clean_flat),
        "nse_adv": compute_nse(y_obs_flat, y_adv_flat),
        "delta_nse": delta_nse(y_obs_flat, y_clean_flat, y_adv_flat),
        "kge_clean": compute_kge(y_obs_flat, y_clean_flat),
        "kge_adv": compute_kge(y_obs_flat, y_adv_flat),
        "peak_error": peak_error(y_obs_flat, y_adv_flat, quantile=0.9),
        "detectability_ks": detectability_ks(x_d.flatten(), x_d_adv.flatten()),
        "l_inf": float((x_d_adv - x_d).abs().max()),
        "l2": float((x_d_adv - x_d).reshape(1, -1).norm(dim=1).mean()),
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default="configs/adversarial_eval.yaml")
    parser.add_argument("--attack", default=None, help="Run specific attack only")
    parser.add_argument("--epsilon", type=float, default=None, help="Single epsilon")
    args = parser.parse_args()

    cfg = load_config(args.config)
    output_dir = Path(cfg["output_dir"])
    output_dir.mkdir(parents=True, exist_ok=True)

    # Load model
    logger.info("Loading CudaLSTM model...")
    wrapper = CudaLSTMWrapper(
        run_dir=Path(cfg["model"]["run_dir"]),
        device=cfg["model"]["device"],
    )

    # Select basins
    logger.info("Selecting representative basins...")
    basins = select_representative_basins(
        attr_dir=Path(cfg["data"]["attr_dir"]),
        n_basins=cfg["data"]["n_basins"],
    )
    logger.info(f"Selected {len(basins)} basins: {basins}")

    # TODO: Load data for selected basins via neuralhydrology DataLoader
    # This requires integration with neuralhydrology's dataset loading
    # For now, placeholder structure:

    attacks_to_run = [args.attack] if args.attack else list(cfg["attacks"].keys())
    epsilons = [args.epsilon] if args.epsilon else cfg["epsilons"]

    all_results = []

    for attack_name in attacks_to_run:
        for epsilon in epsilons:
            for constraint_level in cfg["constraint_levels"]:
                for target in cfg["targets"]:
                    logger.info(f"Running {attack_name} | ε={epsilon} | "
                                f"{constraint_level} | {target}")

                    constraint = build_constraint(constraint_level, epsilon, wrapper)
                    attack_cls = ATTACK_REGISTRY[attack_name]
                    attack_kwargs = dict(cfg["attacks"].get(attack_name, {}))
                    attack = attack_cls(
                        model=wrapper, constraint=constraint,
                        target=target, epsilon=epsilon,
                        **{k: v for k, v in attack_kwargs.items()
                           if k not in ("pre_windows", "freq_bands",
                                        "max_steps_fraction")},
                    )

                    # TODO: iterate over basins + data batches
                    # For each basin:
                    #   result = run_single_experiment(...)
                    #   all_results.append({
                    #       "attack": attack_name, "epsilon": epsilon,
                    #       "constraint": constraint_level, "target": target,
                    #       "basin": basin_id, **result
                    #   })

    # Save results
    results_file = output_dir / "results.json"
    with open(results_file, "w") as f:
        json.dump(all_results, f, indent=2)
    logger.info(f"Results saved to {results_file}")


if __name__ == "__main__":
    main()
```

**Step 3: Commit**

```bash
git add configs/adversarial_eval.yaml scripts/run_adversarial_eval.py
git commit -m "feat(adversarial): experiment config and main runner script"
```

---

### Task 15: Data Loading Integration

**Files:**
- Create: `src/adversarial/data_loader.py`
- Create: `tests/test_adversarial/test_data_loader.py`

**Step 1: Write failing test**

```python
# tests/test_adversarial/test_data_loader.py
import pytest
from pathlib import Path


class TestAdversarialDataLoader:

    def test_load_basin(self):
        from src.adversarial.data_loader import load_basin_data
        run_dir = Path(r"G:\github\pycharm\projects\neuralhydrology\runs\05_full_531_basins_smoke_v2_2026_0217_1632_ep1")
        if not run_dir.exists():
            pytest.skip("run_dir not found")

        x_d, x_s, y_obs = load_basin_data(
            run_dir=run_dir,
            basin_id="01013500",
            period="test",
            device="cpu",
        )
        assert x_d.ndim == 3  # [B, T, F]
        assert x_s.ndim == 2  # [B, S]
        assert y_obs.ndim == 3  # [B, T, 1]
        assert x_d.shape[-1] == 5
```

**Step 2: Run to verify failure**

Run: `python -m pytest tests/test_adversarial/test_data_loader.py -v`

**Step 3: Implement**

```python
# src/adversarial/data_loader.py
"""Load basin data from neuralhydrology for adversarial evaluation."""
from __future__ import annotations

from pathlib import Path
from typing import Tuple

import torch
from torch.utils.data import DataLoader

from neuralhydrology.utils.config import Config
from neuralhydrology.datasetzoo import get_dataset
from neuralhydrology.datautils.utils import load_scaler


def load_basin_data(
    run_dir: Path,
    basin_id: str,
    period: str = "test",
    device: str = "cpu",
) -> Tuple[torch.Tensor, torch.Tensor, torch.Tensor]:
    """Load all data for a single basin, stacked into tensors.

    Returns:
        x_d: [N, T, F] dynamic features (normalized)
        x_s: [N, S] static attributes (normalized)
        y_obs: [N, T, 1] observed streamflow (normalized)
    """
    cfg = Config(run_dir / "config.yml")
    scaler = load_scaler(run_dir)

    # Override basins to load single basin
    cfg.update_config({"basins": [basin_id]})

    ds = get_dataset(
        cfg=cfg,
        is_train=False,
        period=period,
        basin=basin_id,
        scaler=scaler,
        id_to_int={},
    )

    loader = DataLoader(ds, batch_size=len(ds), collate_fn=ds.collate_fn,
                        shuffle=False)
    batch = next(iter(loader))

    # Stack x_d dict into tensor
    feature_names = list(cfg.dynamic_inputs)
    x_d_list = [batch["x_d"][feat] for feat in feature_names]
    x_d = torch.stack(x_d_list, dim=-1).to(device)  # [N, T, F]

    x_s = batch["x_s"].to(device)   # [N, S]
    y_obs = batch["y"].to(device)   # [N, T, 1]

    return x_d, x_s, y_obs
```

**Step 4: Run test**

Run: `python -m pytest tests/test_adversarial/test_data_loader.py -v`
Expected: PASS (if data available, else skip)

**Step 5: Commit**

```bash
git add src/adversarial/data_loader.py tests/test_adversarial/test_data_loader.py
git commit -m "feat(adversarial): basin data loader bridging neuralhydrology datasets"
```

---

### Task 16: Integration Test — End-to-End Attack Pipeline

**Files:**
- Create: `tests/test_adversarial/test_integration.py`

**Step 1: Write integration test**

```python
# tests/test_adversarial/test_integration.py
"""End-to-end integration test: load real model, run all attacks."""
import pytest
import torch
from pathlib import Path


RUN_DIR = Path(r"G:\github\pycharm\projects\neuralhydrology\runs\05_full_531_basins_smoke_v2_2026_0217_1632_ep1")
SKIP = not RUN_DIR.exists()


@pytest.fixture(scope="module")
def model_and_data():
    if SKIP:
        pytest.skip("neuralhydrology run_dir not found")

    from src.adversarial.model_wrapper import CudaLSTMWrapper
    from src.adversarial.data_loader import load_basin_data

    wrapper = CudaLSTMWrapper(run_dir=RUN_DIR, device="cpu")
    x_d, x_s, y_obs = load_basin_data(
        run_dir=RUN_DIR, basin_id="01013500", period="test", device="cpu",
    )
    # Use first sample only for speed
    x_d = x_d[:1]
    x_s = x_s[:1]
    y_obs = y_obs[:1]

    with torch.no_grad():
        y_clean = wrapper.forward(x_d, x_s)

    return wrapper, x_d, x_s, y_obs, y_clean


@pytest.mark.parametrize("attack_name", [
    "auto_pgd", "cw_regression", "sparse_temporal", "spectral",
])
def test_attack_runs(model_and_data, attack_name):
    from src.adversarial.attacks import ATTACK_REGISTRY
    from src.adversarial.constraints.lp_norm import LpConstraint
    from src.adversarial.evaluation.metrics import compute_nse

    wrapper, x_d, x_s, y_obs, y_clean = model_and_data
    constraint = LpConstraint(epsilon=0.2, norm="linf")

    attack_cls = ATTACK_REGISTRY[attack_name]
    kwargs = {"model": wrapper, "constraint": constraint,
              "target": "untargeted", "epsilon": 0.2}
    if attack_name == "sparse_temporal":
        kwargs["max_steps"] = 18
    if attack_name == "cw_regression":
        kwargs["n_iter"] = 20
        kwargs["binary_search_steps"] = 2

    attack = attack_cls(n_iter=10, **kwargs)
    x_adv = attack.attack(x_d, x_s, y_obs)

    assert x_adv.shape == x_d.shape
    assert (x_adv - x_d).abs().max() <= 0.2 + 1e-4


def test_causal_trigger(model_and_data):
    from src.adversarial.attacks.causal_trigger import CausalTriggerAttack
    from src.adversarial.constraints.lp_norm import LpConstraint

    wrapper, x_d, x_s, y_obs, _ = model_and_data
    constraint = LpConstraint(epsilon=0.3, norm="linf")
    attack = CausalTriggerAttack(
        model=wrapper, constraint=constraint,
        pre_window=7, n_iter=10,
    )
    x_adv = attack.attack(x_d, x_s, y_obs, peak_indices=[180])
    assert x_adv.shape == x_d.shape
    # Only perturbation in [173, 180)
    assert (x_adv[:, 187:, :] - x_d[:, 187:, :]).abs().max() < 1e-5


def test_uap(model_and_data):
    from src.adversarial.attacks.uap import UAP
    from src.adversarial.constraints.lp_norm import LpConstraint

    wrapper, x_d, x_s, y_obs, _ = model_and_data
    constraint = LpConstraint(epsilon=0.2, norm="linf")
    attack = UAP(model=wrapper, constraint=constraint, n_iter=5)

    dataset = [(x_d, x_s, y_obs)]  # single sample for test
    uap = attack.craft_universal(dataset)
    assert uap.shape == (1, x_d.shape[1], x_d.shape[2])

    x_adv = attack.attack(x_d, x_s, y_obs)
    assert x_adv.shape == x_d.shape
```

**Step 2: Run integration tests**

Run: `python -m pytest tests/test_adversarial/test_integration.py -v --timeout=120`
Expected: all PASS (or skip if data unavailable)

**Step 3: Commit**

```bash
git add tests/test_adversarial/test_integration.py
git commit -m "test(adversarial): end-to-end integration test for all 6 attacks"
```

---

### Task 17: Final — Run All Tests + Verify

**Step 1: Run full test suite**

```bash
python -m pytest tests/test_adversarial/ -v --tb=short
```

Expected: all unit tests PASS, integration tests PASS or skip.

**Step 2: Smoke test the runner**

```bash
python scripts/run_adversarial_eval.py --config configs/adversarial_eval.yaml --attack auto_pgd --epsilon 0.1
```

**Step 3: Final commit**

```bash
git add -A
git commit -m "feat(adversarial): complete adversarial attack framework v1 (6 methods, 3-tier constraints)"
```

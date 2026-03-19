# SCL-LSTM Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement State Continuity Loss LSTM (SCL-LSTM) for hydrological modeling — a training framework using overlapping segment pairs, an observation encoder, and a state continuity loss to learn consistent hydrological states.

**Architecture:** Independent workspace at `src/scl_hydro/` that imports from neuralhydrology but does not modify it. Core components: `ObsEncoder` (small LSTM encoding observations to initial states), `SCLCudaLSTM` (wraps encoder + LSTM + head), `SCLDataset` (overlapping pair sampling), `SCLTrainer` (pair forward + SCL loss), `StateContinuityLoss` (L2 on hidden states at overlap points).

**Tech Stack:** Python 3.10, PyTorch >=2.0, neuralhydrology 1.12.0, CAMELS-US dataset, pytest

**Spec:** `docs/superpowers/specs/2026-03-17-scl-lstm-design.md`

---

## Phase Scope

**This plan covers Phase 1: Core algorithm validation on synthetic data.** Tasks 1–8 implement the SCL-LSTM training framework with simplified components (raw features, MSELoss) to validate the core algorithm works end-to-end. Task 9 defines Phase 2: CAMELS integration, which adds NH-compatible components (InputLayer, NSE loss, static attributes, evaluation) needed for actual experiments.

| Phase 1 simplification | Phase 2 upgrade |
|------------------------|-----------------|
| Raw tensor inputs to LSTM | NH `InputLayer` embedding |
| MSELoss | Masked NSE loss with `per_basin_target_stds` |
| No static attributes | Static attributes in encoder + main model |
| Synthetic data | CAMELS-US 531 basins |
| No evaluation | Full evaluation with `RegressionTester` |

---

## File Structure

| File | Responsibility |
|------|----------------|
| `src/scl_hydro/__init__.py` | Package marker |
| `src/scl_hydro/config.py` | `SCLConfig` — wraps NH Config with SCL-specific params |
| `src/scl_hydro/model.py` | `ObsEncoder` + `SCLCudaLSTM` — encoder and main model |
| `src/scl_hydro/dataset.py` | `SCLDataset` — overlapping segment pair sampling |
| `src/scl_hydro/loss.py` | `StateContinuityLoss` — L2 hidden state penalty |
| `src/scl_hydro/trainer.py` | `SCLTrainer` — training loop with pair forward + SCL |
| `src/scl_hydro/scripts/run_experiment.py` | CLI entry point for training |
| `src/scl_hydro/scripts/evaluate.py` | Evaluation script |
| `test/test_scl_hydro_config.py` | Config tests |
| `test/test_scl_hydro_model.py` | ObsEncoder + SCLCudaLSTM tests |
| `test/test_scl_hydro_loss.py` | StateContinuityLoss tests |
| `test/test_scl_hydro_dataset.py` | SCLDataset tests |
| `test/test_scl_hydro_trainer.py` | SCLTrainer integration tests |

---

### Task 1: SCLConfig

**Files:**
- Create: `src/scl_hydro/__init__.py`
- Create: `src/scl_hydro/config.py`
- Create: `test/test_scl_hydro_config.py`

- [ ] **Step 1: Write failing test**

```python
# test/test_scl_hydro_config.py
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

import pytest
from scl_hydro.config import SCLConfig


def test_scl_config_defaults():
    """SCLConfig should provide sensible defaults for all SCL params."""
    cfg = SCLConfig({
        "dynamic_inputs": ["prcp(mm/day)", "tmax(C)"],
        "target_variables": ["QObs(mm/d)"],
        "hidden_size": 256,
    })
    assert cfg.seg_length == 180
    assert cfg.context_length == 30
    assert cfg.overlap_length == 30
    assert cfg.scl_weight == 0.1
    assert cfg.enc_hidden_size == 64
    assert cfg.encoder_inputs == []  # defaults to empty, filled from dynamic_inputs + Q


def test_scl_config_custom():
    """SCLConfig should accept custom SCL params."""
    cfg = SCLConfig({
        "dynamic_inputs": ["prcp(mm/day)"],
        "target_variables": ["QObs(mm/d)"],
        "hidden_size": 128,
        "seg_length": 90,
        "context_length": 14,
        "overlap_length": 14,
        "scl_weight": 0.5,
        "enc_hidden_size": 32,
    })
    assert cfg.seg_length == 90
    assert cfg.context_length == 14
    assert cfg.overlap_length == 14
    assert cfg.scl_weight == 0.5
    assert cfg.enc_hidden_size == 32


def test_scl_config_validation_overlap_gt_seg():
    """overlap_length must be less than seg_length."""
    with pytest.raises(ValueError, match="overlap_length.*seg_length"):
        SCLConfig({
            "dynamic_inputs": ["prcp(mm/day)"],
            "target_variables": ["QObs(mm/d)"],
            "hidden_size": 128,
            "seg_length": 30,
            "overlap_length": 30,
        })
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd G:/github/pycharm/projects/neuralhydrology && python -m pytest test/test_scl_hydro_config.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'scl_hydro'`

- [ ] **Step 3: Implement SCLConfig**

```python
# src/scl_hydro/__init__.py
# SCL-LSTM: State Continuity Loss for hydrological models

# src/scl_hydro/config.py
from typing import Dict, List, Union
from pathlib import Path

from neuralhydrology.utils.config import Config


class SCLConfig:
    """Wraps neuralhydrology Config with SCL-specific parameters.

    Does NOT subclass Config because Config validates all keys and rejects unknowns.
    Instead, we extract SCL keys, store them, and pass the rest to Config.
    """

    # SCL-specific keys with defaults
    _SCL_DEFAULTS = {
        "seg_length": 180,
        "context_length": 30,
        "overlap_length": 30,
        "scl_weight": 0.1,
        "enc_hidden_size": 64,
        "encoder_inputs": [],
    }

    def __init__(self, yml_path_or_dict: Union[Path, dict]):
        if isinstance(yml_path_or_dict, (str, Path)):
            import yaml
            with open(yml_path_or_dict, "r") as f:
                raw = yaml.safe_load(f)
        else:
            raw = dict(yml_path_or_dict)

        # Extract SCL keys before passing to NH Config
        self._scl_cfg = {}
        for key, default in self._SCL_DEFAULTS.items():
            self._scl_cfg[key] = raw.pop(key, default)

        # Validate constraints
        if self._scl_cfg["overlap_length"] >= self._scl_cfg["seg_length"]:
            raise ValueError(
                f"overlap_length ({self._scl_cfg['overlap_length']}) must be "
                f"less than seg_length ({self._scl_cfg['seg_length']})"
            )

        # Create NH Config with remaining keys in dev_mode (skip key validation)
        self._nh_cfg = Config(raw, dev_mode=True)

    # SCL properties
    @property
    def seg_length(self) -> int:
        return self._scl_cfg["seg_length"]

    @property
    def context_length(self) -> int:
        return self._scl_cfg["context_length"]

    @property
    def overlap_length(self) -> int:
        return self._scl_cfg["overlap_length"]

    @property
    def scl_weight(self) -> float:
        return self._scl_cfg["scl_weight"]

    @property
    def enc_hidden_size(self) -> int:
        return self._scl_cfg["enc_hidden_size"]

    @property
    def encoder_inputs(self) -> List[str]:
        return self._scl_cfg["encoder_inputs"]

    @property
    def overlap_start(self) -> int:
        """Index in prediction window where overlap starts."""
        return self.seg_length - self.overlap_length

    # Delegate all other attribute access to NH Config
    def __getattr__(self, name):
        if name.startswith("_"):
            raise AttributeError(name)
        return getattr(self._nh_cfg, name)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd G:/github/pycharm/projects/neuralhydrology && python -m pytest test/test_scl_hydro_config.py -v`
Expected: 3 PASSED

- [ ] **Step 5: Commit**

```bash
git add src/scl_hydro/__init__.py src/scl_hydro/config.py test/test_scl_hydro_config.py
git commit -m "feat(scl_hydro): add SCLConfig with SCL-specific parameters"
```

---

### Task 2: ObsEncoder

**Files:**
- Create: `src/scl_hydro/model.py`
- Create: `test/test_scl_hydro_model.py`

- [ ] **Step 1: Write failing test for ObsEncoder**

```python
# test/test_scl_hydro_model.py
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

import pytest
import torch
from scl_hydro.model import ObsEncoder


def test_obs_encoder_output_shapes():
    """ObsEncoder should produce (h_0, c_0) with correct shapes."""
    batch_size = 4
    context_len = 30
    n_enc_features = 5  # P, T, humidity, radiation, Q_obs
    enc_hidden = 64
    main_hidden = 256

    encoder = ObsEncoder(
        input_size=n_enc_features,
        enc_hidden_size=enc_hidden,
        main_hidden_size=main_hidden,
    )

    x = torch.randn(batch_size, context_len, n_enc_features)
    h0, c0 = encoder(x)

    # PyTorch LSTM format: (num_layers, batch, hidden)
    assert h0.shape == (1, batch_size, main_hidden)
    assert c0.shape == (1, batch_size, main_hidden)


def test_obs_encoder_gradient_flow():
    """Gradients should flow back through the encoder."""
    encoder = ObsEncoder(input_size=3, enc_hidden_size=16, main_hidden_size=32)
    x = torch.randn(2, 10, 3)
    h0, c0 = encoder(x)
    loss = h0.sum() + c0.sum()
    loss.backward()

    # Check that encoder LSTM weights have gradients
    assert encoder.lstm.weight_ih_l0.grad is not None
    assert encoder.proj_h.weight.grad is not None
    assert encoder.proj_c.weight.grad is not None
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd G:/github/pycharm/projects/neuralhydrology && python -m pytest test/test_scl_hydro_model.py::test_obs_encoder_output_shapes -v`
Expected: FAIL with `ImportError`

- [ ] **Step 3: Implement ObsEncoder**

```python
# src/scl_hydro/model.py
from typing import Dict, Tuple
import torch
import torch.nn as nn


class ObsEncoder(nn.Module):
    """Encodes observation context [P, T, Q_obs, ...] into LSTM initial states (h_0, c_0).

    Uses a small LSTM to process the context window, then projects the final hidden/cell
    states to the main model's hidden size via separate linear layers.
    """

    def __init__(self, input_size: int, enc_hidden_size: int, main_hidden_size: int,
                 dropout: float = 0.0):
        super().__init__()
        self.lstm = nn.LSTM(input_size=input_size, hidden_size=enc_hidden_size, batch_first=True)
        self.proj_h = nn.Linear(enc_hidden_size, main_hidden_size)
        self.proj_c = nn.Linear(enc_hidden_size, main_hidden_size)
        self.dropout = nn.Dropout(p=dropout)

    def forward(self, x: torch.Tensor) -> Tuple[torch.Tensor, torch.Tensor]:
        """Encode context observations into initial LSTM states.

        Args:
            x: [batch, context_len, input_size] — context window features including Q_obs.

        Returns:
            h_0: [1, batch, main_hidden_size] — initial hidden state for main LSTM.
            c_0: [1, batch, main_hidden_size] — initial cell state for main LSTM.
        """
        _, (h_n, c_n) = self.lstm(x)
        # h_n, c_n: [1, batch, enc_hidden_size]
        h_0 = self.proj_h(self.dropout(h_n.squeeze(0))).unsqueeze(0)  # [1, batch, main_hidden]
        c_0 = self.proj_c(self.dropout(c_n.squeeze(0))).unsqueeze(0)
        return h_0, c_0
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd G:/github/pycharm/projects/neuralhydrology && python -m pytest test/test_scl_hydro_model.py -v`
Expected: 2 PASSED

- [ ] **Step 5: Commit**

```bash
git add src/scl_hydro/model.py test/test_scl_hydro_model.py
git commit -m "feat(scl_hydro): add ObsEncoder with projection layers"
```

---

### Task 3: SCLCudaLSTM

**Files:**
- Modify: `src/scl_hydro/model.py`
- Modify: `test/test_scl_hydro_model.py`

- [ ] **Step 1: Write failing test for SCLCudaLSTM**

Add to `test/test_scl_hydro_model.py`:

```python
from scl_hydro.model import SCLCudaLSTM


def test_scl_cudalstm_forward_shapes():
    """SCLCudaLSTM should output predictions and hidden states."""
    batch = 4
    seg_len = 30
    context_len = 10
    n_main_feat = 3
    n_enc_feat = 4  # main features + Q_obs
    hidden = 32

    model = SCLCudaLSTM(
        n_main_features=n_main_feat,
        n_enc_features=n_enc_feat,
        hidden_size=hidden,
        enc_hidden_size=16,
        n_targets=1,
    )

    predict_x = torch.randn(batch, seg_len, n_main_feat)
    context_x = torch.randn(batch, context_len, n_enc_feat)
    result = model(predict_x, context_x)

    assert result["y_hat"].shape == (batch, seg_len, 1)
    assert result["lstm_output"].shape == (batch, seg_len, hidden)


def test_scl_cudalstm_no_encoder():
    """When context_data is None, should use zero initial state."""
    model = SCLCudaLSTM(
        n_main_features=3,
        n_enc_features=4,
        hidden_size=32,
        enc_hidden_size=16,
        n_targets=1,
    )
    predict_x = torch.randn(2, 20, 3)
    result = model(predict_x, context_data=None)
    assert result["y_hat"].shape == (2, 20, 1)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd G:/github/pycharm/projects/neuralhydrology && python -m pytest test/test_scl_hydro_model.py::test_scl_cudalstm_forward_shapes -v`
Expected: FAIL with `ImportError`

- [ ] **Step 3: Implement SCLCudaLSTM**

Add to `src/scl_hydro/model.py`:

```python
class SCLCudaLSTM(nn.Module):
    """LSTM model with observation encoder for initial state injection.

    Mirrors CudaLSTM architecture (embedding → LSTM → dropout → head) but:
    1. Accepts initial states (h_0, c_0) from ObsEncoder instead of zeros.
    2. Uses raw tensor inputs rather than NH data dicts for flexibility.
    """

    def __init__(self, n_main_features: int, n_enc_features: int, hidden_size: int,
                 enc_hidden_size: int, n_targets: int, output_dropout: float = 0.0,
                 encoder_dropout: float = 0.0):
        super().__init__()
        self.encoder = ObsEncoder(
            input_size=n_enc_features,
            enc_hidden_size=enc_hidden_size,
            main_hidden_size=hidden_size,
            dropout=encoder_dropout,
        )
        self.lstm = nn.LSTM(input_size=n_main_features, hidden_size=hidden_size, batch_first=True)
        self.dropout = nn.Dropout(p=output_dropout)
        self.head = nn.Linear(hidden_size, n_targets)

    def forward(self, predict_data: torch.Tensor,
                context_data: torch.Tensor = None) -> Dict[str, torch.Tensor]:
        """Forward pass with optional encoder-based initialization.

        Args:
            predict_data: [batch, seg_len, n_main_features] — forcing inputs.
            context_data: [batch, context_len, n_enc_features] — encoder context (or None).

        Returns:
            Dict with 'y_hat', 'lstm_output', 'h_n', 'c_n'.
        """
        if context_data is not None:
            h0, c0 = self.encoder(context_data)
            lstm_out, (h_n, c_n) = self.lstm(predict_data, (h0, c0))
        else:
            lstm_out, (h_n, c_n) = self.lstm(predict_data)

        y_hat = self.head(self.dropout(lstm_out))

        return {
            "y_hat": y_hat,
            "lstm_output": lstm_out,
            "h_n": h_n.transpose(0, 1),
            "c_n": c_n.transpose(0, 1),
        }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd G:/github/pycharm/projects/neuralhydrology && python -m pytest test/test_scl_hydro_model.py -v`
Expected: 4 PASSED

- [ ] **Step 5: Commit**

```bash
git add src/scl_hydro/model.py test/test_scl_hydro_model.py
git commit -m "feat(scl_hydro): add SCLCudaLSTM with encoder integration"
```

---

### Task 4: StateContinuityLoss

**Files:**
- Create: `src/scl_hydro/loss.py`
- Create: `test/test_scl_hydro_loss.py`

- [ ] **Step 1: Write failing test**

```python
# test/test_scl_hydro_loss.py
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd G:/github/pycharm/projects/neuralhydrology && python -m pytest test/test_scl_hydro_loss.py -v`
Expected: FAIL with `ModuleNotFoundError`

- [ ] **Step 3: Implement StateContinuityLoss**

```python
# src/scl_hydro/loss.py
import torch
import torch.nn as nn


class StateContinuityLoss(nn.Module):
    """L2 penalty on hidden state differences at temporal overlap points.

    Computes mean squared difference between hidden states from two overlapping segments
    at corresponding timesteps, weighted by scl_weight.
    """

    def __init__(self, scl_weight: float = 0.1):
        super().__init__()
        self.scl_weight = scl_weight

    def forward(self, h_k_overlap: torch.Tensor, h_k1_overlap: torch.Tensor) -> torch.Tensor:
        """Compute state continuity loss.

        Args:
            h_k_overlap: [batch, overlap_len, hidden] — seg_k hidden states at overlap.
            h_k1_overlap: [batch, overlap_len, hidden] — seg_k+1 hidden states at overlap.

        Returns:
            Scalar loss: scl_weight * mean((h_k - h_k1)^2).
        """
        return self.scl_weight * torch.mean((h_k_overlap - h_k1_overlap) ** 2)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd G:/github/pycharm/projects/neuralhydrology && python -m pytest test/test_scl_hydro_loss.py -v`
Expected: 4 PASSED

- [ ] **Step 5: Commit**

```bash
git add src/scl_hydro/loss.py test/test_scl_hydro_loss.py
git commit -m "feat(scl_hydro): add StateContinuityLoss"
```

---

### Task 5: SCLDataset

**Files:**
- Create: `src/scl_hydro/dataset.py`
- Create: `test/test_scl_hydro_dataset.py`

- [ ] **Step 1: Write failing test**

```python
# test/test_scl_hydro_dataset.py
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

import pytest
import numpy as np
import pandas as pd
import torch
from scl_hydro.dataset import SCLDataset


@pytest.fixture
def synthetic_data(tmp_path):
    """Create synthetic basin data for testing."""
    n_days = 400
    dates = pd.date_range("2000-01-01", periods=n_days, freq="D")
    df = pd.DataFrame({
        "prcp": np.random.rand(n_days),
        "tmax": np.random.rand(n_days) * 30,
        "QObs": np.abs(np.random.randn(n_days)) + 0.1,
    }, index=dates)
    return {"basin_01": df}


def test_scl_dataset_getitem_keys(synthetic_data):
    """__getitem__ should return all required keys."""
    ds = SCLDataset(
        data=synthetic_data,
        seg_length=30,
        context_length=10,
        overlap_length=10,
        main_features=["prcp", "tmax"],
        enc_features=["prcp", "tmax", "QObs"],
        target="QObs",
    )
    assert len(ds) > 0
    sample = ds[0]
    required_keys = {"context_k", "predict_k", "context_k1", "predict_k1",
                     "y_k", "y_k1"}
    assert required_keys.issubset(sample.keys())


def test_scl_dataset_shapes(synthetic_data):
    """All tensors should have correct shapes."""
    seg_len = 30
    ctx_len = 10
    overlap = 10
    n_main = 2
    n_enc = 3
    ds = SCLDataset(
        data=synthetic_data,
        seg_length=seg_len,
        context_length=ctx_len,
        overlap_length=overlap,
        main_features=["prcp", "tmax"],
        enc_features=["prcp", "tmax", "QObs"],
        target="QObs",
    )
    sample = ds[0]
    assert sample["context_k"].shape == (ctx_len, n_enc)
    assert sample["predict_k"].shape == (seg_len, n_main)
    assert sample["context_k1"].shape == (ctx_len, n_enc)
    assert sample["predict_k1"].shape == (seg_len, n_main)
    assert sample["y_k"].shape == (seg_len, 1)
    assert sample["y_k1"].shape == (seg_len, 1)


def test_scl_dataset_temporal_overlap(synthetic_data):
    """The overlap region of seg_k and seg_k+1 should cover the same dates."""
    seg_len = 30
    overlap = 10
    ds = SCLDataset(
        data=synthetic_data,
        seg_length=seg_len,
        context_length=10,
        overlap_length=overlap,
        main_features=["prcp", "tmax"],
        enc_features=["prcp", "tmax", "QObs"],
        target="QObs",
    )
    sample = ds[0]
    # Last overlap_length of y_k should equal first overlap_length of y_k1
    y_k_overlap = sample["y_k"][-overlap:]
    y_k1_overlap = sample["y_k1"][:overlap]
    torch.testing.assert_close(y_k_overlap, y_k1_overlap)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd G:/github/pycharm/projects/neuralhydrology && python -m pytest test/test_scl_hydro_dataset.py -v`
Expected: FAIL with `ModuleNotFoundError`

- [ ] **Step 3: Implement SCLDataset**

```python
# src/scl_hydro/dataset.py
from typing import Dict, List, Optional
import numpy as np
import pandas as pd
import torch
from torch.utils.data import Dataset


class SCLDataset(Dataset):
    """Dataset that returns overlapping segment pairs for SCL training.

    Each sample consists of two temporally overlapping segments (seg_k, seg_k+1) from
    the same basin. Both include a context window (for the encoder) and a prediction
    window (for the main model).

    Temporal layout:
        seg_k:   [--context_k--][--------predict_k--------]
        seg_k+1:                       [--context_k+1--][--------predict_k+1--------]
        overlap:                                        |overlap_len|
    """

    def __init__(self, data: Dict[str, pd.DataFrame], seg_length: int,
                 context_length: int, overlap_length: int,
                 main_features: List[str], enc_features: List[str],
                 target: str, scaler: Optional[dict] = None):
        super().__init__()
        self.seg_length = seg_length
        self.context_length = context_length
        self.overlap_length = overlap_length
        self.main_features = main_features
        self.enc_features = enc_features
        self.target = target
        self.overlap_start = seg_length - overlap_length

        # Step between consecutive segment pairs
        self._step = seg_length - overlap_length

        # Store data as numpy arrays for fast indexing
        self._basin_data = {}
        for basin_id, df in data.items():
            self._basin_data[basin_id] = {
                "main": df[main_features].values.astype(np.float32),
                "enc": df[enc_features].values.astype(np.float32),
                "target": df[[target]].values.astype(np.float32),
            }

        # Build lookup table: list of (basin_id, seg_k_predict_start_idx)
        self._lookup = []
        for basin_id, arrays in self._basin_data.items():
            n_timesteps = len(arrays["target"])
            # seg_k needs: context_k starts at (i - context_length)
            # seg_k+1 needs: predict_k+1 ends at (i + 2*seg_length - overlap_length)
            min_start = context_length
            max_start = n_timesteps - (2 * seg_length - overlap_length)
            for i in range(min_start, max_start):
                # Check no NaN in targets for both segments
                y_k = arrays["target"][i:i + seg_length]
                y_k1_start = i + self._step
                y_k1 = arrays["target"][y_k1_start:y_k1_start + seg_length]
                if not (np.any(np.isnan(y_k)) or np.any(np.isnan(y_k1))):
                    self._lookup.append((basin_id, i))

    def __len__(self) -> int:
        return len(self._lookup)

    def __getitem__(self, idx: int) -> Dict[str, torch.Tensor]:
        basin_id, pred_k_start = self._lookup[idx]
        arrays = self._basin_data[basin_id]

        # Seg k indices
        ctx_k_start = pred_k_start - self.context_length
        ctx_k_end = pred_k_start
        pred_k_end = pred_k_start + self.seg_length

        # Seg k+1 indices
        pred_k1_start = pred_k_start + self._step
        ctx_k1_start = pred_k1_start - self.context_length
        ctx_k1_end = pred_k1_start
        pred_k1_end = pred_k1_start + self.seg_length

        return {
            "context_k": torch.from_numpy(arrays["enc"][ctx_k_start:ctx_k_end]),
            "predict_k": torch.from_numpy(arrays["main"][pred_k_start:pred_k_end]),
            "context_k1": torch.from_numpy(arrays["enc"][ctx_k1_start:ctx_k1_end]),
            "predict_k1": torch.from_numpy(arrays["main"][pred_k1_start:pred_k1_end]),
            "y_k": torch.from_numpy(arrays["target"][pred_k_start:pred_k_end]),
            "y_k1": torch.from_numpy(arrays["target"][pred_k1_start:pred_k1_end]),
        }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd G:/github/pycharm/projects/neuralhydrology && python -m pytest test/test_scl_hydro_dataset.py -v`
Expected: 3 PASSED

- [ ] **Step 5: Commit**

```bash
git add src/scl_hydro/dataset.py test/test_scl_hydro_dataset.py
git commit -m "feat(scl_hydro): add SCLDataset with overlapping pair sampling"
```

---

### Task 6: SCLTrainer

**Files:**
- Create: `src/scl_hydro/trainer.py`
- Create: `test/test_scl_hydro_trainer.py`

- [ ] **Step 1: Write failing test**

```python
# test/test_scl_hydro_trainer.py
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

import pytest
import numpy as np
import pandas as pd
import torch
from scl_hydro.trainer import SCLTrainer
from scl_hydro.model import SCLCudaLSTM
from scl_hydro.dataset import SCLDataset
from scl_hydro.loss import StateContinuityLoss


@pytest.fixture
def synthetic_data():
    n_days = 500
    dates = pd.date_range("2000-01-01", periods=n_days, freq="D")
    df = pd.DataFrame({
        "prcp": np.random.rand(n_days).astype(np.float32),
        "tmax": np.random.rand(n_days).astype(np.float32) * 30,
        "QObs": (np.abs(np.random.randn(n_days)) + 0.1).astype(np.float32),
    }, index=dates)
    return {"basin_01": df}


def test_scl_trainer_one_step(synthetic_data):
    """SCLTrainer should complete one training step without error."""
    model = SCLCudaLSTM(
        n_main_features=2, n_enc_features=3,
        hidden_size=32, enc_hidden_size=16, n_targets=1,
    )
    dataset = SCLDataset(
        data=synthetic_data, seg_length=30, context_length=10, overlap_length=10,
        main_features=["prcp", "tmax"], enc_features=["prcp", "tmax", "QObs"],
        target="QObs",
    )
    trainer = SCLTrainer(
        model=model, dataset=dataset,
        scl_weight=0.1, overlap_start=20, overlap_length=10,
        lr=0.001, batch_size=4,
    )
    loss_before = trainer.train_step()
    assert isinstance(loss_before, dict)
    assert "pred_loss" in loss_before
    assert "scl_loss" in loss_before
    assert "total_loss" in loss_before


def test_scl_trainer_loss_decreases(synthetic_data):
    """Loss should decrease after multiple training steps."""
    torch.manual_seed(42)
    model = SCLCudaLSTM(
        n_main_features=2, n_enc_features=3,
        hidden_size=32, enc_hidden_size=16, n_targets=1,
    )
    dataset = SCLDataset(
        data=synthetic_data, seg_length=30, context_length=10, overlap_length=10,
        main_features=["prcp", "tmax"], enc_features=["prcp", "tmax", "QObs"],
        target="QObs",
    )
    trainer = SCLTrainer(
        model=model, dataset=dataset,
        scl_weight=0.1, overlap_start=20, overlap_length=10,
        lr=0.001, batch_size=8,
    )
    losses = [trainer.train_step()["total_loss"] for _ in range(20)]
    # Loss should generally decrease (compare first 5 avg vs last 5 avg)
    assert np.mean(losses[-5:]) < np.mean(losses[:5])
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd G:/github/pycharm/projects/neuralhydrology && python -m pytest test/test_scl_hydro_trainer.py::test_scl_trainer_one_step -v`
Expected: FAIL with `ModuleNotFoundError`

- [ ] **Step 3: Implement SCLTrainer**

```python
# src/scl_hydro/trainer.py
from typing import Dict, Optional
import torch
import torch.nn as nn
from torch.utils.data import DataLoader

from scl_hydro.model import SCLCudaLSTM
from scl_hydro.dataset import SCLDataset
from scl_hydro.loss import StateContinuityLoss


class SCLTrainer:
    """Trainer for SCL-LSTM with overlapping segment pairs.

    Handles: paired forward pass, prediction loss, state continuity loss,
    gradient computation, and optimizer step.
    """

    def __init__(self, model: SCLCudaLSTM, dataset: SCLDataset,
                 scl_weight: float, overlap_start: int, overlap_length: int,
                 lr: float = 0.001, batch_size: int = 128,
                 device: str = "cpu", clip_grad_norm: Optional[float] = 1.0):
        self.model = model.to(device)
        self.device = device
        self.overlap_start = overlap_start
        self.overlap_length = overlap_length

        self.loader = DataLoader(dataset, batch_size=batch_size, shuffle=True,
                                 drop_last=True)
        self._loader_iter = iter(self.loader)

        self.optimizer = torch.optim.Adam(model.parameters(), lr=lr)
        self.pred_loss_fn = nn.MSELoss()
        self.scl_loss_fn = StateContinuityLoss(scl_weight=scl_weight)
        self.clip_grad_norm = clip_grad_norm

    def _get_batch(self) -> Dict[str, torch.Tensor]:
        try:
            batch = next(self._loader_iter)
        except StopIteration:
            self._loader_iter = iter(self.loader)
            batch = next(self._loader_iter)
        return {k: v.to(self.device) for k, v in batch.items()}

    def train_step(self) -> Dict[str, float]:
        """Execute one training step on a batch of segment pairs.

        Returns:
            Dict with 'pred_loss', 'scl_loss', 'total_loss' (all float).
        """
        self.model.train()
        batch = self._get_batch()

        # Concatenate both segments for batched forward pass
        B = batch["predict_k"].shape[0]
        predict_2b = torch.cat([batch["predict_k"], batch["predict_k1"]], dim=0)
        context_2b = torch.cat([batch["context_k"], batch["context_k1"]], dim=0)

        output = self.model(predict_2b, context_2b)
        y_hat_k, y_hat_k1 = output["y_hat"].chunk(2, dim=0)
        lstm_out_k, lstm_out_k1 = output["lstm_output"].chunk(2, dim=0)

        # Prediction loss on both segments
        pred_loss = (self.pred_loss_fn(y_hat_k, batch["y_k"])
                     + self.pred_loss_fn(y_hat_k1, batch["y_k1"]))

        # State continuity loss at overlap region
        h_k_ov = lstm_out_k[:, self.overlap_start:, :]
        h_k1_ov = lstm_out_k1[:, :self.overlap_length, :]
        scl_loss = self.scl_loss_fn(h_k_ov, h_k1_ov)

        total_loss = pred_loss + scl_loss

        # Backward + step
        self.optimizer.zero_grad()
        total_loss.backward()
        if self.clip_grad_norm is not None:
            nn.utils.clip_grad_norm_(self.model.parameters(), self.clip_grad_norm)
        self.optimizer.step()

        return {
            "pred_loss": pred_loss.item(),
            "scl_loss": scl_loss.item(),
            "total_loss": total_loss.item(),
        }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd G:/github/pycharm/projects/neuralhydrology && python -m pytest test/test_scl_hydro_trainer.py -v`
Expected: 2 PASSED

- [ ] **Step 5: Commit**

```bash
git add src/scl_hydro/trainer.py test/test_scl_hydro_trainer.py
git commit -m "feat(scl_hydro): add SCLTrainer with paired forward + SCL loss"
```

---

### Task 7: Training Script

**Files:**
- Create: `src/scl_hydro/scripts/__init__.py`
- Create: `src/scl_hydro/scripts/run_experiment.py`
- Create: `src/scl_hydro/configs/scl_default.yml`

- [ ] **Step 1: Create default config YAML**

```yaml
# src/scl_hydro/configs/scl_default.yml
# SCL-LSTM default experiment config for CAMELS-US

# --- SCL-specific ---
seg_length: 180
context_length: 30
overlap_length: 30
scl_weight: 0.1
enc_hidden_size: 64

# --- Standard NH-compatible ---
experiment_name: scl_lstm_default
hidden_size: 256
batch_size: 128
epochs: 30
learning_rate:
  0: 0.001
optimizer: adam
loss: nse
output_dropout: 0.4
clip_gradient_norm: 1.0

# Data
data_dir: /data/camels_us
train_basin_file: basins.txt
dynamic_inputs:
  - prcp(mm/day)
  - srad(W/m2)
  - tmax(C)
  - tmin(C)
  - vp(Pa)
target_variables:
  - QObs(mm/d)
static_attributes:
  - elev_mean
  - slope_mean
  - area_gages2
  - frac_forest
  - lai_max
  - lai_diff
  - gvf_max
  - gvf_diff
  - soil_depth_pelletier
  - soil_depth_statsgo
  - soil_porosity
  - soil_conductivity
  - max_water_content
  - sand_frac
  - silt_frac
  - clay_frac
  - carbonate_rocks_frac
  - geol_permeability
  - p_mean
  - pet_mean
  - aridity
  - frac_snow
  - high_prec_freq
  - high_prec_dur
  - low_prec_freq
  - low_prec_dur

# Periods
train_start_date: 01/10/1999
train_end_date: 30/09/2008
validation_start_date: 01/10/1980
validation_end_date: 30/09/1989
test_start_date: 01/10/1989
test_end_date: 30/09/1999
```

- [ ] **Step 2: Create training script**

```python
# src/scl_hydro/scripts/__init__.py

# src/scl_hydro/scripts/run_experiment.py
"""SCL-LSTM training entry point.

Usage:
    cd src && python -m scl_hydro.scripts.run_experiment --config <path_to_yml>
"""
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from scl_hydro.config import SCLConfig


def main():
    parser = argparse.ArgumentParser(description="Train SCL-LSTM model")
    parser.add_argument("--config", type=str, required=True, help="Path to YAML config file")
    parser.add_argument("--gpu", type=int, default=-1, help="GPU id (-1 for CPU)")
    args = parser.parse_args()

    cfg = SCLConfig(args.config)
    device = f"cuda:{args.gpu}" if args.gpu >= 0 else "cpu"

    print(f"SCL-LSTM Training")
    print(f"  seg_length={cfg.seg_length}, context_length={cfg.context_length}")
    print(f"  overlap_length={cfg.overlap_length}, scl_weight={cfg.scl_weight}")
    print(f"  device={device}")

    # TODO: Full training loop integration with CAMELS data loading
    # This will be implemented when connecting to the actual CAMELS dataset
    print("Config loaded successfully. Full training loop TBD.")


if __name__ == "__main__":
    main()
```

- [ ] **Step 3: Verify script runs**

Run: `cd G:/github/pycharm/projects/neuralhydrology/src && python -m scl_hydro.scripts.run_experiment --config scl_hydro/configs/scl_default.yml`
Expected: Prints config info and "Config loaded successfully"

- [ ] **Step 4: Commit**

```bash
git add src/scl_hydro/scripts/ src/scl_hydro/configs/scl_default.yml
git commit -m "feat(scl_hydro): add training script and default config"
```

---

### Task 8: End-to-End Smoke Test

**Files:**
- Create: `test/test_scl_hydro_e2e.py`

- [ ] **Step 1: Write end-to-end smoke test**

```python
# test/test_scl_hydro_e2e.py
"""End-to-end smoke test: synthetic data → SCLDataset → SCLCudaLSTM → SCLTrainer → loss decreases."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

import numpy as np
import pandas as pd
import torch
from scl_hydro.model import SCLCudaLSTM
from scl_hydro.dataset import SCLDataset
from scl_hydro.trainer import SCLTrainer


def test_e2e_scl_training():
    """Full pipeline: data → dataset → model → trainer → loss decreases."""
    torch.manual_seed(42)
    np.random.seed(42)

    # Synthetic data: 2 basins, 3 years daily
    n_days = 1095
    data = {}
    for basin in ["basin_01", "basin_02"]:
        dates = pd.date_range("2000-01-01", periods=n_days, freq="D")
        data[basin] = pd.DataFrame({
            "prcp": np.random.rand(n_days).astype(np.float32),
            "tmax": (np.random.rand(n_days) * 30).astype(np.float32),
            "QObs": (np.abs(np.random.randn(n_days)) + 0.1).astype(np.float32),
        }, index=dates)

    seg_len = 60
    ctx_len = 15
    overlap = 15

    dataset = SCLDataset(
        data=data, seg_length=seg_len, context_length=ctx_len,
        overlap_length=overlap,
        main_features=["prcp", "tmax"],
        enc_features=["prcp", "tmax", "QObs"],
        target="QObs",
    )
    assert len(dataset) > 0, "Dataset should have samples"

    model = SCLCudaLSTM(
        n_main_features=2, n_enc_features=3,
        hidden_size=32, enc_hidden_size=16, n_targets=1,
    )

    trainer = SCLTrainer(
        model=model, dataset=dataset,
        scl_weight=0.1,
        overlap_start=seg_len - overlap,
        overlap_length=overlap,
        lr=0.001, batch_size=8,
    )

    # Train for 30 steps
    losses = []
    for _ in range(30):
        step_loss = trainer.train_step()
        losses.append(step_loss["total_loss"])

    # Verify loss decreases (first 10 avg > last 10 avg)
    first_avg = np.mean(losses[:10])
    last_avg = np.mean(losses[-10:])
    assert last_avg < first_avg, f"Loss should decrease: {first_avg:.4f} -> {last_avg:.4f}"

    # Verify SCL loss is non-trivial (not zero)
    scl_losses = [trainer.train_step()["scl_loss"] for _ in range(5)]
    assert any(l > 0 for l in scl_losses), "SCL loss should be non-zero"
```

- [ ] **Step 2: Run the test**

Run: `cd G:/github/pycharm/projects/neuralhydrology && python -m pytest test/test_scl_hydro_e2e.py -v`
Expected: 1 PASSED

- [ ] **Step 3: Commit**

```bash
git add test/test_scl_hydro_e2e.py
git commit -m "test(scl_hydro): add end-to-end smoke test"
```

---

## Execution Summary

| Task | Description | Files | Tests |
|------|-------------|-------|-------|
| 1 | SCLConfig | 3 created | 3 tests |
| 2 | ObsEncoder | 1 created, 1 created | 2 tests |
| 3 | SCLCudaLSTM | 1 modified, 1 modified | 2 tests |
| 4 | StateContinuityLoss | 1 created, 1 created | 4 tests |
| 5 | SCLDataset | 1 created, 1 created | 3 tests |
| 6 | SCLTrainer | 1 created, 1 created | 2 tests |
| 7 | Training script + config | 3 created | manual |
| 8 | End-to-end smoke test | 1 created | 1 test |
| **Total** | | **13 files** | **17 tests** |

After Task 8, you will have a fully testable SCL-LSTM core that trains on synthetic data.

---

### Task 9: Phase 2 Checklist — CAMELS Integration

**Not implemented in this plan.** This task lists everything needed to connect SCL-LSTM to real CAMELS-US data and run experiments E1–E7. Each item should become its own task in a follow-up plan.

- [ ] **9.1** Upgrade `SCLCudaLSTM` to use NH `InputLayer` for feature embedding (match CudaLSTM baseline architecture)
- [ ] **9.2** Add static attributes to encoder input (concatenate to each context timestep, per spec Section 2.2)
- [ ] **9.3** Replace `MSELoss` with `MaskedNSELoss` in `SCLTrainer`, add `per_basin_target_stds` to `SCLDataset` output
- [ ] **9.4** Connect `SCLDataset` to CAMELS-US data loading (via NH `get_dataset` or direct xarray loading)
- [ ] **9.5** Implement `scripts/evaluate.py` using NH `RegressionTester` for NSE/KGE evaluation
- [ ] **9.6** Create experiment configs for E1–E7 (baseline_standard, baseline_no_warmup, ablation_no_encoder, ablation_no_scl, baseline_ar, encoder_only_single)
- [ ] **9.7** Implement `scripts/analyze_states.py` for hidden state vs soil moisture/SWE correlation (Fig 5)
- [ ] **9.8** Create HPC SLURM submission scripts
- [ ] **9.9** Run E1–E7 on CAMELS-US 531 basins, generate paper figures

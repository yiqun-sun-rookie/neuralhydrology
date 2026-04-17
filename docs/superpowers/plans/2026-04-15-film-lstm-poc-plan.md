# FiLM-LSTM POC Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a FiLM-LSTM model (pre-activation gate FiLM on LSTM), set up a 24-run 2×2 ablation (EA-LSTM vs FiLM-LSTM × real vs shuffled static × 2 PUB folds × 3 seeds) on CAMELS-US, and run the analysis pipeline to apply pre-registered threshold B for go/no-go decision.

**Architecture:** A new `FiLMLSTM` class under `neuralhydrology/modelzoo/` mirrors `EALSTM`'s structure. Its 4-gate LSTM cell computes `pre_act = x @ W_ih + h @ W_hh + b`, then modulates with `γ(s), β(s)` from a small MLP generator. Identity initialization (γ ≡ 1, β ≡ 0 at init) keeps early training stable. The experiment reuses `src/static_falsification/`'s existing 5-fold PUB splits and `shuffled_dataset.py`.

**Tech Stack:** PyTorch 2.x, neuralhydrology 1.12, pytest, YAPF (Google style, 120 char), SLURM on hpcbh.hhu.edu.cn.

**Reference spec:** `docs/superpowers/specs/2026-04-15-film-lstm-poc-design.md`

---

## File Structure

### New files

| Path | Responsibility |
|---|---|
| `neuralhydrology/modelzoo/filmlstm.py` | `FiLMLSTM` model class and `_FiLMGenerator` helper |
| `test/test_filmlstm.py` | Unit tests: identity init, forward shape, gradient flow, registry |
| `src/static_falsification/configs/base_filmlstm.yml` | Base config for FiLM-LSTM training |
| `src/static_falsification/scripts/generate_film_poc_configs.py` | Generates 24 per-fold/seed/condition YAMLs |
| `src/static_falsification/configs/film_poc/` | Directory for generated POC configs (24 files) |
| `src/static_falsification/hpc/submit_film_poc.slurm` | SLURM job array script for 24 runs |
| `src/static_falsification/scripts/analyze_film_poc.py` | Aggregates per-basin NSE, computes ΔArch/ΔPhys, prints verdict |
| `src/static_falsification/docs/poc_memo_template.md` | Template for POC result memo |

### Modified files

| Path | Change |
|---|---|
| `neuralhydrology/modelzoo/__init__.py` | Import and register `FiLMLSTM` (3 lines: import, list entry, factory branch) |

### Reused (unchanged)

- `src/static_falsification/data/fold{0,1}_{train,validation,test}.txt` — PUB splits
- `src/static_falsification/data/shuffle_maps.json` — fixed shuffle mapping
- `src/static_falsification/shuffled_dataset.py` — shuffle dataset wrapper
- `src/static_falsification/configs/base_ealstm.yml` — reference for EA-LSTM baseline configs

---

## Task 1: FiLM Generator with identity initialization (TDD)

**Files:**
- Create: `neuralhydrology/modelzoo/filmlstm.py` (generator only, model class in Task 2)
- Create: `test/test_filmlstm.py`

- [ ] **Step 1.1: Create test file skeleton and write failing test for identity init**

Create `test/test_filmlstm.py`:

```python
"""Unit tests for FiLM-LSTM model."""
import torch
import pytest

from neuralhydrology.modelzoo.filmlstm import _FiLMGenerator


class _FakeCfg:
    """Minimal stand-in for neuralhydrology Config in unit tests."""
    def __init__(self, hidden_size=16, film_generator_hidden_size=8):
        self.hidden_size = hidden_size
        self.film_generator_hidden_size = film_generator_hidden_size


def test_film_generator_identity_init():
    """At initialization, generator must output gamma=1 and beta=0 for any input."""
    cfg = _FakeCfg(hidden_size=16)
    S = 24  # static dim
    gen = _FiLMGenerator(cfg, static_size=S)

    # Two different random static inputs
    s1 = torch.randn(4, S)
    s2 = torch.randn(4, S)

    gamma1, beta1 = gen(s1)
    gamma2, beta2 = gen(s2)

    # gamma and beta must not depend on s at init (final-layer weights=0, bias encodes identity)
    assert torch.allclose(gamma1, gamma2, atol=1e-7), "Gamma must be s-independent at init"
    assert torch.allclose(beta1, beta2, atol=1e-7), "Beta must be s-independent at init"

    # gamma ≡ 1, beta ≡ 0
    assert torch.allclose(gamma1, torch.ones_like(gamma1), atol=1e-7), f"Gamma must be ones, got min={gamma1.min()}, max={gamma1.max()}"
    assert torch.allclose(beta1, torch.zeros_like(beta1), atol=1e-7), f"Beta must be zeros, got min={beta1.min()}, max={beta1.max()}"

    # Shape: [batch, 4 * hidden_size]
    assert gamma1.shape == (4, 4 * cfg.hidden_size)
    assert beta1.shape == (4, 4 * cfg.hidden_size)
```

- [ ] **Step 1.2: Run test to confirm it fails with ImportError**

```bash
cd G:\github\pycharm\projects\neuralhydrology
pytest test/test_filmlstm.py::test_film_generator_identity_init -v
```

Expected: `ImportError: cannot import name '_FiLMGenerator' from 'neuralhydrology.modelzoo.filmlstm'` (or ModuleNotFoundError if `filmlstm.py` doesn't exist yet).

- [ ] **Step 1.3: Create `filmlstm.py` with `_FiLMGenerator` only**

Create `neuralhydrology/modelzoo/filmlstm.py`:

```python
"""FiLM-LSTM: LSTM with Feature-wise Linear Modulation of gate pre-activations by static attributes.

Reference: Perez et al. 2018, "FiLM: Visual Reasoning with a General Conditioning Layer" (AAAI).
This is a hydrology-specific adaptation: static catchment attributes modulate all 4 LSTM gate
pre-activations via affine (gamma, beta) parameters generated by a small MLP.
"""
from typing import Dict, Tuple

import torch
import torch.nn as nn

from neuralhydrology.modelzoo.basemodel import BaseModel
from neuralhydrology.modelzoo.inputlayer import InputLayer
from neuralhydrology.modelzoo.head import get_head
from neuralhydrology.utils.config import Config


class _FiLMGenerator(nn.Module):
    """MLP that maps static attributes to per-gate (gamma, beta) FiLM parameters.

    Output: (gamma, beta) each of shape [B, 4 * hidden_size], one pair per LSTM gate (i, f, g, o).
    Identity initialization: final-layer weights are zero, biases encode gamma=1, beta=0, so at init
    the FiLM modulation is a no-op (the LSTM behaves as a vanilla LSTM regardless of static input).
    """

    def __init__(self, cfg, static_size: int):
        super().__init__()
        H = cfg.hidden_size
        mid = getattr(cfg, 'film_generator_hidden_size', 64)

        self.mlp_gamma = nn.Sequential(
            nn.Linear(static_size, mid),
            nn.ReLU(),
            nn.Linear(mid, 4 * H),
        )
        self.mlp_beta = nn.Sequential(
            nn.Linear(static_size, mid),
            nn.ReLU(),
            nn.Linear(mid, 4 * H),
        )
        self._identity_init()

    def _identity_init(self):
        # gamma: final weight=0, bias=1 -> gamma ≡ 1 at init (any input yields ones)
        nn.init.zeros_(self.mlp_gamma[-1].weight)
        nn.init.ones_(self.mlp_gamma[-1].bias)
        # beta: final weight=0, bias=0 -> beta ≡ 0 at init
        nn.init.zeros_(self.mlp_beta[-1].weight)
        nn.init.zeros_(self.mlp_beta[-1].bias)

    def forward(self, s: torch.Tensor) -> Tuple[torch.Tensor, torch.Tensor]:
        return self.mlp_gamma(s), self.mlp_beta(s)
```

- [ ] **Step 1.4: Run test to confirm it passes**

```bash
pytest test/test_filmlstm.py::test_film_generator_identity_init -v
```

Expected: PASS.

- [ ] **Step 1.5: Commit**

```bash
git add neuralhydrology/modelzoo/filmlstm.py test/test_filmlstm.py
git commit -m "feat(filmlstm): add _FiLMGenerator with identity initialization

Generator MLP maps static attributes to per-gate (gamma, beta) FiLM
parameters. Identity init (final weight=0, bias encodes gamma=1 / beta=0)
makes the FiLM layer a no-op at init, so the model starts as a vanilla
LSTM and learns conditioning gradually.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 2: FiLMLSTM model class (TDD)

**Files:**
- Modify: `neuralhydrology/modelzoo/filmlstm.py` (add `FiLMLSTM` class)
- Modify: `test/test_filmlstm.py` (add forward shape and s-invariance tests)

- [ ] **Step 2.1: Add failing forward-shape + s-invariance test**

Append to `test/test_filmlstm.py`:

```python
from typing import Callable
from test import Fixture
from neuralhydrology.modelzoo.filmlstm import FiLMLSTM


def test_filmlstm_forward_shape_and_identity(get_config: Fixture[Callable[[str], dict]]):
    """At init, FiLMLSTM output must not depend on static input (FiLM is identity at init)."""
    config = get_config('daily_regression')
    config.update_config({
        'dataset': 'camels_us',
        'data_dir': config.data_dir / 'camels_us',
        'target_variables': 'QObs(mm/d)',
        'forcings': 'daymet',
        'dynamic_inputs': ['prcp(mm/day)', 'tmax(C)'],
        'static_attributes': ['elev_mean', 'slope_mean', 'area_gages2'],
        'model': 'filmlstm',
    })

    model = FiLMLSTM(config)
    model.eval()

    # Two different static inputs, same dynamic
    x_d = {k: torch.rand((config.batch_size, 50, 1)) for k in config.dynamic_inputs}
    x_s_1 = torch.rand((config.batch_size, len(config.static_attributes)))
    x_s_2 = torch.rand((config.batch_size, len(config.static_attributes)))

    with torch.no_grad():
        out_1 = model({'x_d': x_d, 'x_s': x_s_1})
        out_2 = model({'x_d': x_d, 'x_s': x_s_2})

    # Shape check
    assert out_1['y_hat'].shape == (config.batch_size, 50, 1)
    assert out_1['h_n'].shape == (config.batch_size, 50, config.hidden_size)
    assert out_1['c_n'].shape == (config.batch_size, 50, config.hidden_size)

    # Identity init: outputs must be identical across different static inputs
    assert torch.allclose(out_1['y_hat'], out_2['y_hat'], atol=1e-6), \
        "At init, FiLMLSTM output must not depend on static input (gamma=1, beta=0)"


def test_filmlstm_gradient_flow(get_config: Fixture[Callable[[str], dict]]):
    """All parameters (film generator + LSTM core + head) must receive non-None gradients."""
    config = get_config('daily_regression')
    config.update_config({
        'dataset': 'camels_us',
        'data_dir': config.data_dir / 'camels_us',
        'target_variables': 'QObs(mm/d)',
        'forcings': 'daymet',
        'dynamic_inputs': ['prcp(mm/day)', 'tmax(C)'],
        'static_attributes': ['elev_mean', 'slope_mean', 'area_gages2'],
        'model': 'filmlstm',
    })

    model = FiLMLSTM(config)

    x_d = {k: torch.rand((config.batch_size, 50, 1)) for k in config.dynamic_inputs}
    x_s = torch.rand((config.batch_size, len(config.static_attributes)))

    out = model({'x_d': x_d, 'x_s': x_s})
    loss = out['y_hat'].sum()
    loss.backward()

    missing_grads = [n for n, p in model.named_parameters() if p.requires_grad and p.grad is None]
    assert not missing_grads, f"Parameters without gradients: {missing_grads}"
```

- [ ] **Step 2.2: Run test to confirm it fails with ImportError/AttributeError**

```bash
pytest test/test_filmlstm.py::test_filmlstm_forward_shape_and_identity -v
```

Expected: `ImportError: cannot import name 'FiLMLSTM'` or similar.

- [ ] **Step 2.3: Add `FiLMLSTM` class to `filmlstm.py`**

Append to `neuralhydrology/modelzoo/filmlstm.py`:

```python
class FiLMLSTM(BaseModel):
    """LSTM with FiLM-modulated gate pre-activations by static attributes.

    Differences vs. EA-LSTM:
      - EA-LSTM: input gate uses static-only path `sigma(W_s * s + b_s)`, kept constant over time.
        Other 3 gates (f, o, g) are dynamic.
      - FiLMLSTM: all 4 gates (i, f, g, o) are dynamic. Static attributes generate per-gate
        (gamma, beta) vectors that affinely modulate pre-activations before sigmoid/tanh.

    Identity initialization (gamma=1, beta=0) makes the model behave as a vanilla LSTM at init.
    """
    module_parts = ['embedding_net', 'film_generator', 'cell', 'head']

    def __init__(self, cfg: Config):
        super().__init__(cfg=cfg)
        self._hidden_size = cfg.hidden_size
        self.embedding_net = InputLayer(cfg)

        if self.embedding_net.statics_output_size == 0:
            raise ValueError('FiLMLSTM requires static inputs.')

        self.film_generator = _FiLMGenerator(cfg, static_size=self.embedding_net.statics_output_size)

        # 4-gate LSTM parameters: order is (i, f, g, o) along the 4H axis
        input_size = self.embedding_net.dynamics_output_size
        H = cfg.hidden_size
        self.weight_ih = nn.Parameter(torch.empty(input_size, 4 * H))
        self.weight_hh = nn.Parameter(torch.empty(H, 4 * H))
        self.bias = nn.Parameter(torch.empty(4 * H))
        self._reset_parameters()

        self.dropout = nn.Dropout(p=cfg.output_dropout)
        self.head = get_head(cfg=cfg, n_in=H, n_out=self.output_size)

    def _reset_parameters(self):
        nn.init.orthogonal_(self.weight_ih)
        # hh: identity-block repeated 4 times (standard LSTM initialization)
        eye = torch.eye(self._hidden_size)
        self.weight_hh.data = eye.repeat(1, 4)
        nn.init.zeros_(self.bias)
        if self.cfg.initial_forget_bias is not None:
            # f gate is the 2nd chunk (index H:2H) under (i, f, g, o) ordering
            self.bias.data[self._hidden_size:2 * self._hidden_size] = self.cfg.initial_forget_bias

    def forward(self, data: dict) -> Dict[str, torch.Tensor]:
        x_d, x_s = self.embedding_net(data, concatenate_output=False)
        if x_s is None:
            raise ValueError('FiLMLSTM requires static inputs (x_s or x_one_hot).')

        # Compute gamma, beta ONCE per sample (time-constant modulation)
        gamma, beta = self.film_generator(x_s)  # each [B, 4H]

        B = x_d.shape[1]
        h_t = x_d.new_zeros(B, self._hidden_size)
        c_t = x_d.new_zeros(B, self._hidden_size)
        h_n, c_n = [], []

        for x_dt in x_d:
            pre_act = x_dt @ self.weight_ih + h_t @ self.weight_hh + self.bias  # [B, 4H]
            pre_act = gamma * pre_act + beta  # FiLM modulation
            i, f, g, o = pre_act.chunk(4, dim=-1)
            i = torch.sigmoid(i)
            f = torch.sigmoid(f)
            g = torch.tanh(g)
            o = torch.sigmoid(o)
            c_t = f * c_t + i * g
            h_t = o * torch.tanh(c_t)
            h_n.append(h_t)
            c_n.append(c_t)

        h_n = torch.stack(h_n, 0).transpose(0, 1)
        c_n = torch.stack(c_n, 0).transpose(0, 1)

        pred = {'h_n': h_n, 'c_n': c_n}
        pred.update(self.head(self.dropout(h_n)))
        return pred
```

- [ ] **Step 2.4: Register `filmlstm` in the modelzoo factory (needed for `get_model` used implicitly by `FiLMLSTM` test path)**

Edit `neuralhydrology/modelzoo/__init__.py`:

After line 10 (`from neuralhydrology.modelzoo.ealstm import EALSTM`), add:

```python
from neuralhydrology.modelzoo.filmlstm import FiLMLSTM
```

In the `SINGLE_FREQ_MODELS` list (line 24-38), add `"filmlstm"` right after `"ealstm"`:

```python
SINGLE_FREQ_MODELS = [
    "cudalstm",
    "ealstm",
    "filmlstm",
    "customlstm",
    ...
]
```

In `get_model`, after the `ealstm` branch (line 68-69), add:

```python
    elif cfg.model.lower() == "filmlstm":
        model = FiLMLSTM(cfg=cfg)
```

- [ ] **Step 2.5: Run all FiLM tests**

```bash
pytest test/test_filmlstm.py -v
```

Expected: all 3 tests PASS.

- [ ] **Step 2.6: Run the broader test suite to catch regressions in modelzoo registration**

```bash
pytest test/ --smoke-test -x
```

Expected: no new failures (smoke-test runs a subset; full unregressed).

- [ ] **Step 2.7: Commit**

```bash
git add neuralhydrology/modelzoo/filmlstm.py neuralhydrology/modelzoo/__init__.py test/test_filmlstm.py
git commit -m "feat(filmlstm): add FiLMLSTM model and register in modelzoo

Pre-activation gate FiLM on LSTM: static attributes generate (gamma, beta)
that affinely modulate all 4 gate pre-activations before sigmoid/tanh.
Identity init makes the model behave as vanilla LSTM at init.

Includes unit tests: identity init produces s-independent output, shape
check, and gradient flow across film_generator + LSTM core + head.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 3: Base FiLM config and local 3-epoch sanity run

**Files:**
- Create: `src/static_falsification/configs/base_filmlstm.yml`

- [ ] **Step 3.1: Create the base FiLM config by copying and adjusting `base_ealstm.yml`**

Create `src/static_falsification/configs/base_filmlstm.yml`:

```yaml
# Static Falsification Experiment — Base FiLMLSTM Config
# FiLM-LSTM: pre-activation gate FiLM on LSTM, static attributes modulate all 4 gates.
experiment_name: film_poc_{condition}_fold{fold_idx}_seed{seed}

dataset: camels_us
data_dir: data/CAMELS_US

model: filmlstm
head: regression
hidden_size: 256
film_generator_hidden_size: 64
initial_forget_bias: 3
output_dropout: 0.0
output_activation: linear

epochs: 30
batch_size: 128
optimizer: Adam
loss: NSE
learning_rate:
  0: 0.001

# Basin files — will be overridden per fold by generator script
train_basin_file: src/static_falsification/data/fold0_train.txt
validation_basin_file: src/static_falsification/data/fold0_validation.txt
test_basin_file: src/static_falsification/data/fold0_test.txt

train_start_date: "01/10/1999"
train_end_date: "30/09/2008"
validation_start_date: "01/10/1980"
validation_end_date: "30/09/1989"
test_start_date: "01/10/1989"
test_end_date: "30/09/1999"

forcings:
  - daymet
dynamic_inputs:
  - prcp(mm/day)
  - srad(W/m2)
  - tmax(C)
  - tmin(C)
  - vp(Pa)

static_attributes:
  - elev_mean
  - slope_mean
  - area_gages2
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
  - frac_forest
  - lai_max
  - lai_diff
  - gvf_max
  - gvf_diff
  - dom_land_cover_frac
  - p_mean
  - pet_mean
  - aridity
  - frac_snow
  - high_prec_freq

target_variables:
  - QObs(mm/d)
clip_targets_to_zero:
  - QObs(mm/d)

seq_length: 365
predict_last_n: 1

num_workers: 0
validate_every: 2
validate_n_random_basins: 50
clip_gradient_norm: 1.0

log_interval: 10
log_tensorboard: False
log_n_figures: 0
save_weights_every: 10
metrics:
  - NSE
  - KGE
```

- [ ] **Step 3.2: Run a 3-epoch local smoke training to verify config + model + CAMELS data pipeline**

This requires a temp config with `epochs: 3` and the first 10 basins of `fold0_train.txt`. Create `src/static_falsification/configs/_smoke_filmlstm.yml` with those overrides (copy base_filmlstm.yml, change experiment_name to `film_smoke`, epochs to 3, and create a 10-basin subset file manually — or just set `train_basin_file` to an existing small list if one exists).

Run:
```bash
python -m neuralhydrology.nh_run train --config-file src/static_falsification/configs/_smoke_filmlstm.yml --gpu -1
```

Expected: training starts, runs 3 epochs without NaN, produces `runs/film_smoke_*/model_epoch003.pt`. Do not worry about NSE quality at 3 epochs.

- [ ] **Step 3.3: Delete smoke config and smoke run directory (keep repo clean)**

```bash
rm src/static_falsification/configs/_smoke_filmlstm.yml
rm -rf runs/film_smoke_*
```

- [ ] **Step 3.4: Commit the base config**

```bash
git add src/static_falsification/configs/base_filmlstm.yml
git commit -m "data(static_falsification): add base FiLMLSTM config

Mirrors base_ealstm.yml with model=filmlstm and film_generator_hidden_size=64.
Same 24 static attributes, 5 daymet dynamic inputs, 30 epochs, seq_length=365.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 4: POC config generator and 24 generated configs

**Files:**
- Create: `src/static_falsification/scripts/generate_film_poc_configs.py`
- Create: `src/static_falsification/configs/film_poc/` (24 generated YAMLs)

The POC matrix has 4 conditions × 2 folds × 3 seeds = 24 runs:

| Config family | Model | Static | Fold | Seeds |
|---|---|---|---|---|
| `ealstm_poc_real` | ealstm | real | 0, 1 | 0, 1, 2 |
| `ealstm_poc_shuffle` | ealstm | shuffled | 0, 1 | 0, 1, 2 |
| `filmlstm_poc_real` | filmlstm | real | 0, 1 | 0, 1, 2 |
| `filmlstm_poc_shuffle` | filmlstm | shuffled | 0, 1 | 0, 1, 2 |

- [ ] **Step 4.1: Inspect `shuffled_dataset.py` to learn how to enable shuffle in a config**

```bash
cat src/static_falsification/shuffled_dataset.py | head -60
```

Note the config key(s) it looks for (e.g., `dataset: shuffled_camels_us` or a flag like `shuffle_static: True`). Record the exact key name for the generator script.

- [ ] **Step 4.2: Write the generator script**

Create `src/static_falsification/scripts/generate_film_poc_configs.py`:

```python
"""Generate 24 POC configs for FiLM-LSTM 2x2 ablation.

Matrix: 2 models × 2 static conditions × 2 folds × 3 seeds = 24 configs.
"""
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parents[3]
BASE_EALSTM = REPO_ROOT / 'src/static_falsification/configs/base_ealstm.yml'
BASE_FILM = REPO_ROOT / 'src/static_falsification/configs/base_filmlstm.yml'
OUT_DIR = REPO_ROOT / 'src/static_falsification/configs/film_poc'
DATA_DIR = REPO_ROOT / 'src/static_falsification/data'

# TODO in Step 4.1: replace with actual key(s) used by shuffled_dataset.py
SHUFFLE_CONFIG_KEYS = {
    # Example — replace based on Step 4.1 finding:
    # 'dataset': 'shuffled_camels_us',
    # 'shuffle_map_file': 'src/static_falsification/data/shuffle_maps.json',
}


def build_config(model: str, fold: int, seed: int, shuffle: bool) -> dict:
    base_path = BASE_FILM if model == 'filmlstm' else BASE_EALSTM
    with open(base_path, 'r', encoding='utf-8') as f:
        cfg = yaml.safe_load(f)

    condition = 'shuffle' if shuffle else 'real'
    cfg['experiment_name'] = f'{model}_poc_{condition}_fold{fold}_seed{seed}'
    cfg['seed'] = seed
    cfg['train_basin_file'] = f'src/static_falsification/data/fold{fold}_train.txt'
    cfg['validation_basin_file'] = f'src/static_falsification/data/fold{fold}_validation.txt'
    cfg['test_basin_file'] = f'src/static_falsification/data/fold{fold}_test.txt'

    if shuffle:
        cfg.update(SHUFFLE_CONFIG_KEYS)  # applied from Step 4.1 finding
        cfg['experiment_name'] += '_shuffle'

    return cfg


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    models = ['ealstm', 'filmlstm']
    folds = [0, 1]
    seeds = [0, 1, 2]
    conditions = [False, True]  # False=real, True=shuffle

    n = 0
    for model in models:
        for fold in folds:
            for seed in seeds:
                for shuffle in conditions:
                    cfg = build_config(model, fold, seed, shuffle)
                    cond = 'shuffle' if shuffle else 'real'
                    out = OUT_DIR / f'{model}_poc_{cond}_fold{fold}_seed{seed}.yml'
                    with open(out, 'w', encoding='utf-8') as f:
                        yaml.safe_dump(cfg, f, default_flow_style=False, sort_keys=False)
                    n += 1
                    print(f'  wrote {out.relative_to(REPO_ROOT)}')

    print(f'\nGenerated {n} configs in {OUT_DIR.relative_to(REPO_ROOT)}')
    assert n == 24, f'Expected 24 configs, got {n}'


if __name__ == '__main__':
    main()
```

- [ ] **Step 4.3: Run the generator**

```bash
python src/static_falsification/scripts/generate_film_poc_configs.py
```

Expected: `Generated 24 configs in src/static_falsification/configs/film_poc`.

- [ ] **Step 4.4: Manually spot-check one FiLM-shuffle config and one EA-real config**

```bash
cat src/static_falsification/configs/film_poc/filmlstm_poc_shuffle_fold0_seed0.yml
cat src/static_falsification/configs/film_poc/ealstm_poc_real_fold1_seed2.yml
```

Verify: `model`, `seed`, `train_basin_file`, shuffle-related keys look right.

- [ ] **Step 4.5: Verify one generated config actually trains for 1 epoch**

Pick `filmlstm_poc_real_fold0_seed0.yml`, override `epochs: 1` inline via a temp copy, run local CPU training for 1 epoch, confirm no crash. Example:

```bash
cp src/static_falsification/configs/film_poc/filmlstm_poc_real_fold0_seed0.yml /tmp/_film_1ep.yml
sed -i 's/^epochs:.*/epochs: 1/' /tmp/_film_1ep.yml
python -m neuralhydrology.nh_run train --config-file /tmp/_film_1ep.yml --gpu -1
```

Expected: finishes 1 epoch without error. Delete `/tmp/_film_1ep.yml` and the resulting `runs/` directory.

- [ ] **Step 4.6: Commit generator + configs**

```bash
git add src/static_falsification/scripts/generate_film_poc_configs.py src/static_falsification/configs/film_poc/
git commit -m "data(static_falsification): generate 24 FiLM-LSTM POC configs

2x2x2x3 matrix: {ealstm, filmlstm} x {real, shuffle} x {fold0, fold1} x {seed0-2}.
Uses base_ealstm.yml and base_filmlstm.yml as starting points.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 5: HPC SLURM submission script

**Files:**
- Create: `src/static_falsification/hpc/submit_film_poc.slurm`

- [ ] **Step 5.1: Inspect existing SLURM scripts to match the HPC template**

```bash
cat src/static_falsification/hpc/submit_exp1_core.slurm
```

Note: partition name, account, module loads, conda env activation, paths.

- [ ] **Step 5.2: Write the job-array SLURM script**

Create `src/static_falsification/hpc/submit_film_poc.slurm`:

```bash
#!/bin/bash
#SBATCH --job-name=film_poc
#SBATCH --output=logs/static_falsification/film_poc_%A_%a.out
#SBATCH --error=logs/static_falsification/film_poc_%A_%a.err
#SBATCH --array=0-23%8
#SBATCH --partition=hgpu8
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=4
#SBATCH --mem=32G
#SBATCH --time=12:00:00

# --array=0-23%8 → 24 jobs, at most 8 running at once (adjust %N to queue capacity)

set -euo pipefail

# --- Environment (MATCH submit_exp1_core.slurm; adjust if stale) ---
source ~/miniconda3/etc/profile.d/conda.sh
conda activate neuralhydrology
cd ~/projects/neuralhydrology

# --- Config list (24 entries, index must match --array range) ---
CONFIGS=(
    src/static_falsification/configs/film_poc/ealstm_poc_real_fold0_seed0.yml
    src/static_falsification/configs/film_poc/ealstm_poc_real_fold0_seed1.yml
    src/static_falsification/configs/film_poc/ealstm_poc_real_fold0_seed2.yml
    src/static_falsification/configs/film_poc/ealstm_poc_real_fold1_seed0.yml
    src/static_falsification/configs/film_poc/ealstm_poc_real_fold1_seed1.yml
    src/static_falsification/configs/film_poc/ealstm_poc_real_fold1_seed2.yml
    src/static_falsification/configs/film_poc/ealstm_poc_shuffle_fold0_seed0.yml
    src/static_falsification/configs/film_poc/ealstm_poc_shuffle_fold0_seed1.yml
    src/static_falsification/configs/film_poc/ealstm_poc_shuffle_fold0_seed2.yml
    src/static_falsification/configs/film_poc/ealstm_poc_shuffle_fold1_seed0.yml
    src/static_falsification/configs/film_poc/ealstm_poc_shuffle_fold1_seed1.yml
    src/static_falsification/configs/film_poc/ealstm_poc_shuffle_fold1_seed2.yml
    src/static_falsification/configs/film_poc/filmlstm_poc_real_fold0_seed0.yml
    src/static_falsification/configs/film_poc/filmlstm_poc_real_fold0_seed1.yml
    src/static_falsification/configs/film_poc/filmlstm_poc_real_fold0_seed2.yml
    src/static_falsification/configs/film_poc/filmlstm_poc_real_fold1_seed0.yml
    src/static_falsification/configs/film_poc/filmlstm_poc_real_fold1_seed1.yml
    src/static_falsification/configs/film_poc/filmlstm_poc_real_fold1_seed2.yml
    src/static_falsification/configs/film_poc/filmlstm_poc_shuffle_fold0_seed0.yml
    src/static_falsification/configs/film_poc/filmlstm_poc_shuffle_fold0_seed1.yml
    src/static_falsification/configs/film_poc/filmlstm_poc_shuffle_fold0_seed2.yml
    src/static_falsification/configs/film_poc/filmlstm_poc_shuffle_fold1_seed0.yml
    src/static_falsification/configs/film_poc/filmlstm_poc_shuffle_fold1_seed1.yml
    src/static_falsification/configs/film_poc/filmlstm_poc_shuffle_fold1_seed2.yml
)

CFG="${CONFIGS[$SLURM_ARRAY_TASK_ID]}"
echo "[$(date)] Task $SLURM_ARRAY_TASK_ID  config=$CFG"

mkdir -p logs/static_falsification
python -m neuralhydrology.nh_run train --config-file "$CFG" --gpu 0

echo "[$(date)] Task $SLURM_ARRAY_TASK_ID done"
```

- [ ] **Step 5.3: Validate script syntax (syntax-only, no submission)**

```bash
bash -n src/static_falsification/hpc/submit_film_poc.slurm
```

Expected: no output (syntax OK).

- [ ] **Step 5.4: Commit the SLURM script**

```bash
git add src/static_falsification/hpc/submit_film_poc.slurm
git commit -m "feat(static_falsification): add HPC SLURM script for FiLM POC

24-job array with --array=0-23%8 (max 8 parallel). Covers the full
2x2x2x3 POC matrix on hgpu8 partition.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 6: Analysis script (unit-tested with synthetic data)

**Files:**
- Create: `src/static_falsification/scripts/analyze_film_poc.py`
- Modify: `test/test_filmlstm.py` (add analysis script unit test)

- [ ] **Step 6.1: Write failing test for analysis script on synthetic data**

Append to `test/test_filmlstm.py`:

```python
def test_analyze_film_poc_verdict_on_synthetic_data(tmp_path: Fixture):
    """Analysis script must apply threshold B correctly on synthetic NSE tables."""
    import sys
    from pathlib import Path
    sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'src' / 'static_falsification' / 'scripts'))
    from analyze_film_poc import compute_verdict

    # Simulate a clear PASS: FiLM real = 0.72, EA real = 0.68, shuffle cases much lower
    per_run_nse = {
        ('ealstm',   'real',    0): 0.68, ('ealstm',   'real',    1): 0.68,
        ('filmlstm', 'real',    0): 0.72, ('filmlstm', 'real',    1): 0.72,
        ('ealstm',   'shuffle', 0): 0.60, ('ealstm',   'shuffle', 1): 0.60,
        ('filmlstm', 'shuffle', 0): 0.62, ('filmlstm', 'shuffle', 1): 0.62,
    }
    verdict = compute_verdict(per_run_nse, threshold='B')
    assert verdict['go'] is True
    assert verdict['delta_arch'] == pytest.approx(0.04, abs=1e-6)
    assert verdict['delta_phys_film'] == pytest.approx(0.10, abs=1e-6)
    assert verdict['delta_phys_ea'] == pytest.approx(0.08, abs=1e-6)

    # Simulate a clear FAIL: FiLM slightly worse than EA
    per_run_nse_fail = {
        ('ealstm',   'real',    0): 0.68, ('ealstm',   'real',    1): 0.68,
        ('filmlstm', 'real',    0): 0.67, ('filmlstm', 'real',    1): 0.67,
        ('ealstm',   'shuffle', 0): 0.60, ('ealstm',   'shuffle', 1): 0.60,
        ('filmlstm', 'shuffle', 0): 0.60, ('filmlstm', 'shuffle', 1): 0.60,
    }
    verdict_fail = compute_verdict(per_run_nse_fail, threshold='B')
    assert verdict_fail['go'] is False
```

- [ ] **Step 6.2: Run test to confirm ImportError**

```bash
pytest test/test_filmlstm.py::test_analyze_film_poc_verdict_on_synthetic_data -v
```

Expected: ImportError (script doesn't exist yet).

- [ ] **Step 6.3: Write `analyze_film_poc.py` with `compute_verdict` + full analysis pipeline**

Create `src/static_falsification/scripts/analyze_film_poc.py`:

```python
"""Analyze FiLM-LSTM POC results and apply pre-registered threshold B.

Aggregates per-run test NSE from runs/film_poc_*/test/, computes:
    ΔArch         = NSE(filmlstm, real) - NSE(ealstm, real)
    ΔPhys_FiLM    = NSE(filmlstm, real) - NSE(filmlstm, shuffle)
    ΔPhys_EA      = NSE(ealstm, real)   - NSE(ealstm, shuffle)
Prints verdict: go / no-go / reconsider.
"""
import pickle
from collections import defaultdict
from pathlib import Path
from typing import Dict, Tuple

import numpy as np

# Key: (model, condition, fold) -> median test NSE across basins × seeds
PerRunKey = Tuple[str, str, int]


def collect_nse_from_runs(runs_root: Path) -> Dict[PerRunKey, float]:
    """Walk runs/ and extract median test NSE per (model, condition, fold), averaged over seeds."""
    grouped = defaultdict(list)

    for run_dir in runs_root.glob('*_poc_*_fold*_seed*'):
        name = run_dir.name
        parts = name.split('_')
        # Expected: {model}_poc_{condition}_fold{F}_seed{S}_{date}_{time}
        try:
            model = parts[0]
            condition = parts[2]
            fold = int(parts[3].replace('fold', ''))
        except (ValueError, IndexError):
            print(f'[WARN] skipping unparseable run dir: {name}')
            continue

        test_results = list(run_dir.glob('test/model_epoch*/test_results.p'))
        if not test_results:
            print(f'[WARN] no test_results.p in {name}')
            continue
        # Pick the last epoch
        with open(sorted(test_results)[-1], 'rb') as f:
            results = pickle.load(f)

        # results schema: {basin_id: {target_var: {'NSE': value, ...}}}
        nses = []
        for basin_id, target_dict in results.items():
            for target_var, metrics in target_dict.items():
                if 'NSE' in metrics:
                    nses.append(metrics['NSE'])
        if not nses:
            print(f'[WARN] no NSE values extracted from {name}')
            continue
        grouped[(model, condition, fold)].append(np.median(nses))

    # Average across seeds
    return {k: float(np.mean(v)) for k, v in grouped.items()}


def compute_verdict(per_run_nse: Dict[PerRunKey, float], threshold: str = 'B') -> dict:
    """Compute verdict under the given threshold."""
    # Aggregate across folds (mean)
    def _mean(model, condition):
        vals = [v for (m, c, f), v in per_run_nse.items() if m == model and c == condition]
        if not vals:
            raise ValueError(f'Missing data for ({model}, {condition})')
        return float(np.mean(vals))

    ea_real = _mean('ealstm', 'real')
    ea_shuffle = _mean('ealstm', 'shuffle')
    film_real = _mean('filmlstm', 'real')
    film_shuffle = _mean('filmlstm', 'shuffle')

    delta_arch = film_real - ea_real
    delta_phys_film = film_real - film_shuffle
    delta_phys_ea = ea_real - ea_shuffle

    # Per-fold consistency
    folds = sorted(set(f for _, _, f in per_run_nse.keys()))
    per_fold_deltas = []
    for fold in folds:
        try:
            ea_r = per_run_nse[('ealstm', 'real', fold)]
            film_r = per_run_nse[('filmlstm', 'real', fold)]
            per_fold_deltas.append(film_r - ea_r)
        except KeyError:
            continue
    fold_sign_conflict = (
        len(per_fold_deltas) >= 2
        and max(per_fold_deltas) > 0.05
        and min(per_fold_deltas) < -0.03
    )

    if threshold == 'B':
        pass_arch = delta_arch >= 0.02
        pass_phys = delta_phys_film > delta_phys_ea
        go = pass_arch and pass_phys and not fold_sign_conflict
    else:
        raise ValueError(f'Unknown threshold: {threshold}')

    return {
        'go': go,
        'delta_arch': delta_arch,
        'delta_phys_film': delta_phys_film,
        'delta_phys_ea': delta_phys_ea,
        'per_fold_deltas': per_fold_deltas,
        'fold_sign_conflict': fold_sign_conflict,
        'raw': {
            'ea_real': ea_real, 'ea_shuffle': ea_shuffle,
            'film_real': film_real, 'film_shuffle': film_shuffle,
        },
    }


def main():
    runs_root = Path('runs')
    per_run_nse = collect_nse_from_runs(runs_root)

    print('\n--- Per-(model, condition, fold) median NSE (averaged over seeds) ---')
    for key in sorted(per_run_nse.keys()):
        print(f'  {key}: {per_run_nse[key]:.4f}')

    verdict = compute_verdict(per_run_nse, threshold='B')

    print('\n--- Deltas ---')
    print(f'  ΔArch        = {verdict["delta_arch"]:+.4f}   (need >= +0.02)')
    print(f'  ΔPhys_FiLM   = {verdict["delta_phys_film"]:+.4f}')
    print(f'  ΔPhys_EA     = {verdict["delta_phys_ea"]:+.4f}')
    print(f'  Per-fold deltas: {[f"{d:+.4f}" for d in verdict["per_fold_deltas"]]}')
    print(f'  Fold sign conflict: {verdict["fold_sign_conflict"]}')

    print('\n--- Verdict under threshold B ---')
    print('  GO ✓ — upgrade to full 5-fold experiment' if verdict['go']
          else '  NO-GO ✗ — reconsider per decision branches in spec §10')


if __name__ == '__main__':
    main()
```

- [ ] **Step 6.4: Run test to confirm it passes**

```bash
pytest test/test_filmlstm.py::test_analyze_film_poc_verdict_on_synthetic_data -v
```

Expected: PASS.

- [ ] **Step 6.5: Commit**

```bash
git add src/static_falsification/scripts/analyze_film_poc.py test/test_filmlstm.py
git commit -m "feat(static_falsification): add FiLM POC analysis with threshold B

Aggregates per-run test NSE, computes ΔArch, ΔPhys_FiLM, ΔPhys_EA, applies
pre-registered threshold B (ΔArch >= +0.02, ΔPhys_FiLM > ΔPhys_EA, no fold
sign conflict). Unit-tested with synthetic pass and fail cases.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 7: POC result memo template

**Files:**
- Create: `src/static_falsification/docs/poc_memo_template.md`

- [ ] **Step 7.1: Create memo template**

Create `src/static_falsification/docs/poc_memo_template.md`:

```markdown
# FiLM-LSTM POC — Result Memo

**Date:** YYYY-MM-DD
**Runs:** 24 (2 models × 2 static conditions × 2 folds × 3 seeds)
**Reference spec:** `docs/superpowers/specs/2026-04-15-film-lstm-poc-design.md`
**Reference plan:** `docs/superpowers/plans/2026-04-15-film-lstm-poc-plan.md`

## Per-run median test NSE (averaged over seeds per fold)

|  | EA-LSTM real | EA-LSTM shuffle | FiLM-LSTM real | FiLM-LSTM shuffle |
|---|---|---|---|---|
| Fold 0 | _fill_ | _fill_ | _fill_ | _fill_ |
| Fold 1 | _fill_ | _fill_ | _fill_ | _fill_ |
| Fold-avg | _fill_ | _fill_ | _fill_ | _fill_ |

## Deltas

- ΔArch         = NSE(FiLM, real) − NSE(EA, real)   = _fill_
- ΔPhys_FiLM    = NSE(FiLM, real) − NSE(FiLM, shuf) = _fill_
- ΔPhys_EA      = NSE(EA, real)   − NSE(EA, shuf)   = _fill_

## Threshold B check

- [ ] ΔArch ≥ +0.02 — _pass/fail_
- [ ] ΔPhys_FiLM > ΔPhys_EA — _pass/fail_
- [ ] No fold sign conflict — _pass/fail_

## Verdict

_GO: upgrade to full 5-fold × 5 seeds on HPC._
_or_
_NO-GO: pivot per decision branch X in spec §10._

## Next action

_(Link to next plan / commit next piece of work here.)_
```

- [ ] **Step 7.2: Commit**

```bash
git add src/static_falsification/docs/poc_memo_template.md
git commit -m "docs(static_falsification): add FiLM POC memo template

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 8: Run POC on HPC (user-driven, not automated)

This task is **not executable by the coding agent**. It requires the user to SSH to HPC, sync data/code, and submit jobs. Document the exact steps so the user can run them in a terminal session.

- [ ] **Step 8.1: Sync repo to HPC**

From local:
```bash
# User runs this in WSL (not Windows):
rsync -avz --exclude='.git' --exclude='runs/' --exclude='data/' \
    ~/path/to/neuralhydrology/ \
    sunyiq@hpcbh.hhu.edu.cn:~/projects/neuralhydrology/
```

(Reference: `memory/wsl_hpc_setup.md` for ControlMaster details.)

- [ ] **Step 8.2: SSH to HPC and submit job array**

```bash
ssh sunyiq@hpcbh.hhu.edu.cn
cd ~/projects/neuralhydrology
sbatch src/static_falsification/hpc/submit_film_poc.slurm
```

Expected: `Submitted batch job <JOB_ID>`.

- [ ] **Step 8.3: Monitor (not blocking — just a check-in)**

```bash
squeue -u sunyiq
# Or:
sacct -j <JOB_ID> --format=JobID,State,Elapsed,ExitCode
```

Wait for all 24 tasks to finish (expected: 4–8 h per task × up to 3 rounds of 8 parallel = up to ~24 h wall time).

- [ ] **Step 8.4: Download results back to local**

From local WSL:
```bash
rsync -avz sunyiq@hpcbh.hhu.edu.cn:~/projects/neuralhydrology/runs/*_poc_* \
    ~/path/to/neuralhydrology/runs/
```

---

## Task 9: Run analysis and write memo

- [ ] **Step 9.1: Run the analysis script**

```bash
cd G:\github\pycharm\projects\neuralhydrology
python src/static_falsification/scripts/analyze_film_poc.py | tee src/static_falsification/docs/poc_analysis_output.txt
```

Expected: table of per-(model, condition, fold) NSEs, deltas, and a printed verdict.

- [ ] **Step 9.2: Copy the memo template and fill it in**

```bash
cp src/static_falsification/docs/poc_memo_template.md \
   src/static_falsification/docs/poc_memo_$(date +%Y-%m-%d).md
```

Manually fill the table with values from Step 9.1 output. Set the verdict. Identify next action (per decision branch in spec §10).

- [ ] **Step 9.3: Commit memo + analysis output**

```bash
git add src/static_falsification/docs/poc_memo_*.md src/static_falsification/docs/poc_analysis_output.txt
git commit -m "docs(static_falsification): record FiLM POC results and verdict

<One-line verdict summary here, e.g. 'GO: ΔArch=+0.04, ΔPhys_FiLM=+0.10, upgrade to full 5-fold.'>

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

- [ ] **Step 9.4: Update memory with POC outcome**

Edit `memory/static_falsification_project.md` and `memory/method_hypernet_for_hydrology.md` (the latter should be renamed or supplemented with FiLM findings). Update `memory/MEMORY.md` index entries accordingly.

---

## Self-Review (inline, done before handing plan to execution)

**Spec coverage check** (against `2026-04-15-film-lstm-poc-design.md`):

| Spec section | Covered by |
|---|---|
| §3.1 FiLM-LSTM cell | Task 2 (steps 2.1–2.3) |
| §3.2 FiLM generator | Task 1 (steps 1.1–1.5) |
| §3.3 Relation to EA-LSTM | Task 2 step 2.3 (docstring + identity test in 2.1) |
| §4 Components | Task 3 (base config), Task 4 (per-fold configs), Task 5 (SLURM), Task 6 (analysis) |
| §5 Data flow | Task 4 (configs with shuffle), Task 6 (collect + aggregate) |
| §6 Success criteria (threshold B) | Task 6 step 6.3 (`compute_verdict`) + 6.1 tests |
| §7 Error handling | Task 1 step 1.3 (identity init), Task 2 step 2.3 (ValueError on missing static) |
| §8.1 Unit tests | Task 1 step 1.1, Task 2 step 2.1, Task 6 step 6.1 |
| §8.2 Smoke test | Task 3 step 3.2 (local 3-epoch), Task 4 step 4.5 (1 epoch via CPU) |
| §9 Timeline | Aligned: Tasks 1–7 = D1–D3 coding; Task 8 = D4 HPC; Task 9 = D5–D7 analysis+memo |
| §10 Decision branches | Task 9 step 9.2 (memo links to branch), Task 9 step 9.4 (memory update) |

**Placeholder scan:**
- Task 4 step 4.2 has `TODO in Step 4.1: replace SHUFFLE_CONFIG_KEYS` — this is a **deliberate, contextual placeholder** because the actual shuffled-dataset config keys must be read from `shuffled_dataset.py` first. The step instructs the engineer how to resolve it in 4.1. This is acceptable per the writing-plans rules (the engineer is not asked to "figure it out" — they're told exactly where to find it and paste the result).
- Task 5 step 5.2 has an inline "adjust if stale" on conda env activation — this is a **standard HPC script hygiene reminder**, not a missing implementation.
- Task 8 step 8.1 has `~/path/to/neuralhydrology/` as a placeholder path — acceptable because the exact local path varies per machine and the user knows their own layout.
- Task 9 step 9.3 commit message has `<One-line verdict summary here>` — acceptable because the summary depends on runtime results that cannot be known in advance.

No "TBD", no "add appropriate error handling", no "similar to Task N".

**Type consistency:**
- `FiLMLSTM.__init__` signature matches `EALSTM.__init__`: `(cfg: Config)` ✓
- `_FiLMGenerator.__init__(cfg, static_size: int)` — `static_size` positional is consistent between Task 1 test and Task 2 usage ✓
- Config key `film_generator_hidden_size` referenced in Task 1 (`_FiLMGenerator.__init__`), Task 3 (`base_filmlstm.yml`), read via `getattr(cfg, 'film_generator_hidden_size', 64)` so absent key defaults to 64 — ✓
- Run-dir name pattern `{model}_poc_{condition}_fold{F}_seed{S}` — generator (Task 4), SLURM (Task 5), and parsing in `collect_nse_from_runs` (Task 6) all agree on this pattern ✓
- Analysis keys `('ealstm'|'filmlstm', 'real'|'shuffle', 0|1)` — test (Task 6.1) and collector (Task 6.3) agree ✓

No type / naming mismatches found.

# Static Attribute Falsification — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Determine whether EALSTM actually uses static catchment attributes' physical content, via permutation experiments on CAMELS-US 531 basins with 5-fold PUB cross-validation.

**Architecture:** Generate 5-fold PUB splits and per-fold shuffle mappings, then batch-generate configs for 3 conditions (E1/E3/E4). Training uses standard `nh_run train`. E2 evaluation reuses E1 models with a custom dataset subclass that remaps static attributes. Analysis script aggregates results and runs statistical tests.

**Tech Stack:** neuralhydrology (EALSTM), CAMELS-US, Python 3.10, PyTorch, scipy (Wilcoxon), matplotlib

**Spec:** `docs/superpowers/specs/2026-03-29-static-falsification-design.md`

---

## File Structure

```
src/static_falsification/
    __init__.py                       # empty
    shuffled_dataset.py               # ShuffledCamelsUS subclass (shuffle + constant modes)
    configs/
        base_ealstm.yml               # shared hyperparameters template
        (generated at runtime by generate_configs.py)
    scripts/
        generate_splits.py            # 5-fold basin split + derangement pi
        generate_configs.py           # batch-generate 15 YAML configs from template
        run_training.py               # batch-train all 15 models via nh_run
        run_eval_e2.py                # E2: load E1 model, evaluate with shuffled static
        analyze_results.py            # aggregate metrics, Wilcoxon tests, figures
    hpc/
        submit_all.slurm              # master HPC submission script
    data/
        (generated at runtime by generate_splits.py)
test/
    test_static_falsification.py      # unit tests for splits, shuffle, dataset subclass
```

---

### Task 1: Generate 5-Fold PUB Splits + Derangement Mappings

**Files:**
- Create: `src/static_falsification/scripts/generate_splits.py`
- Create: `src/static_falsification/data/` (output directory)
- Test: `test/test_static_falsification.py`

- [ ] **Step 1: Write the test for split generation**

Create `test/test_static_falsification.py`:

```python
"""Tests for static falsification experiment utilities."""
import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "src"))


def test_generate_fold_splits():
    """5-fold split covers all 531 basins with no overlap."""
    from static_falsification.scripts.generate_splits import generate_fold_splits

    basins = [f"{i:08d}" for i in range(531)]
    folds = generate_fold_splits(basins, n_folds=5, seed=42)

    assert len(folds) == 5
    all_basins = []
    for fold in folds:
        assert len(fold) > 0
        all_basins.extend(fold)
    assert sorted(all_basins) == sorted(basins), "Folds must cover all basins exactly once"


def test_generate_derangement():
    """Derangement has no fixed points."""
    from static_falsification.scripts.generate_splits import generate_derangement

    items = [f"{i:08d}" for i in range(100)]
    mapping = generate_derangement(items, seed=42)

    assert len(mapping) == len(items)
    for k, v in mapping.items():
        assert k != v, f"Fixed point found: {k} -> {v}"
    assert set(mapping.values()) == set(items), "Derangement must be a permutation"


def test_generate_derangement_deterministic():
    """Same seed produces same derangement."""
    from static_falsification.scripts.generate_splits import generate_derangement

    items = [f"{i:08d}" for i in range(50)]
    m1 = generate_derangement(items, seed=99)
    m2 = generate_derangement(items, seed=99)
    assert m1 == m2
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest test/test_static_falsification.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'static_falsification'`

- [ ] **Step 3: Create package and implement split generation**

Create `src/static_falsification/__init__.py` (empty file).

Create `src/static_falsification/scripts/generate_splits.py`:

```python
"""Generate 5-fold PUB splits and per-fold derangement mappings."""
import json
import random
from pathlib import Path
from typing import Dict, List


def generate_fold_splits(basins: List[str], n_folds: int = 5, seed: int = 42) -> List[List[str]]:
    """Partition basins into n_folds non-overlapping groups."""
    rng = random.Random(seed)
    shuffled = list(basins)
    rng.shuffle(shuffled)
    fold_size = len(shuffled) // n_folds
    folds = []
    for i in range(n_folds):
        start = i * fold_size
        end = start + fold_size if i < n_folds - 1 else len(shuffled)
        folds.append(sorted(shuffled[start:end]))
    return folds


def generate_derangement(items: List[str], seed: int = 42) -> Dict[str, str]:
    """Generate a fixed-point-free permutation (derangement) of items."""
    rng = random.Random(seed)
    n = len(items)
    if n < 2:
        raise ValueError("Need at least 2 items for a derangement")
    shuffled = list(items)
    for _ in range(1000):
        rng.shuffle(shuffled)
        if all(shuffled[i] != items[i] for i in range(n)):
            return dict(zip(items, shuffled))
    # Fallback: Sattolo's algorithm (always produces a derangement for n >= 2)
    shuffled = list(items)
    for i in range(n - 1, 0, -1):
        j = rng.randint(0, i - 1)
        shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
    return dict(zip(items, shuffled))


def main():
    """Generate and save splits + derangements for the experiment."""
    # Load the 531 basin list
    basin_file = Path("src/full_531_basins/data/531_basin_list.txt")
    if not basin_file.exists():
        basin_file = Path("data/CAMELS_US/basin_list.txt")
    basins = [line.strip() for line in basin_file.read_text().splitlines() if line.strip()]

    out_dir = Path("src/static_falsification/data")
    out_dir.mkdir(parents=True, exist_ok=True)

    # Generate 5-fold splits
    folds = generate_fold_splits(basins, n_folds=5, seed=42)

    # Generate per-fold derangements (different seed per fold)
    derangements = {}
    for fold_idx in range(5):
        # Derangement applies to ALL basins, not just train basins
        derangements[str(fold_idx)] = generate_derangement(basins, seed=100 + fold_idx)

    # Save fold splits
    fold_data = {}
    for fold_idx, test_basins in enumerate(folds):
        train_basins = sorted([b for i, f in enumerate(folds) for b in f if i != fold_idx])
        # 10% of train basins for validation
        rng = random.Random(42 + fold_idx)
        val_size = max(1, len(train_basins) // 10)
        val_basins = sorted(rng.sample(train_basins, val_size))
        actual_train = sorted([b for b in train_basins if b not in val_basins])
        fold_data[str(fold_idx)] = {
            "train": actual_train,
            "validation": val_basins,
            "test": test_basins,
        }

    with open(out_dir / "fold_splits.json", "w") as f:
        json.dump(fold_data, f, indent=2)

    with open(out_dir / "shuffle_maps.json", "w") as f:
        json.dump(derangements, f, indent=2)

    # Write per-fold basin list files (needed by neuralhydrology configs)
    for fold_idx, splits in fold_data.items():
        for split_name, basin_list in splits.items():
            fname = out_dir / f"fold{fold_idx}_{split_name}.txt"
            fname.write_text("\n".join(basin_list) + "\n")

    print(f"Generated 5-fold splits: {[len(f) for f in folds]} basins per fold")
    print(f"Generated {len(derangements)} derangement mappings")
    print(f"Output: {out_dir}")


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pytest test/test_static_falsification.py -v`
Expected: 3 passed

- [ ] **Step 5: Commit**

```bash
git add src/static_falsification/__init__.py src/static_falsification/scripts/generate_splits.py test/test_static_falsification.py
git commit -m "feat(static_falsification): add 5-fold PUB split + derangement generation"
```

---

### Task 2: ShuffledCamelsUS Dataset Subclass

**Files:**
- Create: `src/static_falsification/shuffled_dataset.py`
- Modify: `test/test_static_falsification.py` (add tests)

- [ ] **Step 1: Write the test for shuffled dataset**

Append to `test/test_static_falsification.py`:

```python
def test_shuffled_dataset_remaps_attributes():
    """ShuffledCamelsUS replaces basin attributes according to shuffle_map."""
    from static_falsification.shuffled_dataset import apply_shuffle, apply_constant

    import torch

    # Simulate _attributes dict
    attrs = {
        "basin_a": torch.tensor([1.0, 2.0]),
        "basin_b": torch.tensor([3.0, 4.0]),
        "basin_c": torch.tensor([5.0, 6.0]),
    }
    shuffle_map = {"basin_a": "basin_b", "basin_b": "basin_c", "basin_c": "basin_a"}

    result = apply_shuffle(dict(attrs), shuffle_map)

    assert torch.equal(result["basin_a"], attrs["basin_b"])
    assert torch.equal(result["basin_b"], attrs["basin_c"])
    assert torch.equal(result["basin_c"], attrs["basin_a"])


def test_apply_constant_zeros_all_attributes():
    """apply_constant replaces all attributes with zeros."""
    from static_falsification.shuffled_dataset import apply_constant

    import torch

    attrs = {
        "basin_a": torch.tensor([1.0, 2.0, 3.0]),
        "basin_b": torch.tensor([4.0, 5.0, 6.0]),
    }

    result = apply_constant(dict(attrs))

    for basin, tensor in result.items():
        assert torch.equal(tensor, torch.zeros(3))
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest test/test_static_falsification.py::test_shuffled_dataset_remaps_attributes -v`
Expected: FAIL — `ModuleNotFoundError`

- [ ] **Step 3: Implement shuffled_dataset.py**

Create `src/static_falsification/shuffled_dataset.py`:

```python
"""Dataset subclass that shuffles or zeroes static catchment attributes."""
from typing import Dict

import torch


def apply_shuffle(attributes: Dict[str, torch.Tensor],
                  shuffle_map: Dict[str, str]) -> Dict[str, torch.Tensor]:
    """Remap basin->attributes according to shuffle_map.

    Parameters
    ----------
    attributes : dict
        Original mapping of basin_id -> attribute tensor.
    shuffle_map : dict
        Mapping of basin_id -> source_basin_id (the basin whose attributes to use).

    Returns
    -------
    dict
        New mapping with remapped attributes.
    """
    original = dict(attributes)
    result = {}
    for basin, source in shuffle_map.items():
        if basin in original and source in original:
            result[basin] = original[source]
    # Keep any basins not in the shuffle_map unchanged
    for basin in original:
        if basin not in result:
            result[basin] = original[basin]
    return result


def apply_constant(attributes: Dict[str, torch.Tensor]) -> Dict[str, torch.Tensor]:
    """Replace all basin attributes with zero vectors (global mean after z-score).

    Parameters
    ----------
    attributes : dict
        Original mapping of basin_id -> attribute tensor.

    Returns
    -------
    dict
        New mapping with all-zeros tensors.
    """
    return {basin: torch.zeros_like(tensor) for basin, tensor in attributes.items()}


class ModifiedCamelsUS(CamelsUS):
    """CamelsUS variant that applies shuffle or constant to static attributes after loading.

    Set class-level variables before instantiation:
        ModifiedCamelsUS._shuffle_map = {...}  # for shuffle mode
        ModifiedCamelsUS._constant_mode = True  # for constant (zero) mode
    """

    _shuffle_map = None
    _constant_mode = False

    def _load_data(self):
        super()._load_data()
        if self._attributes:
            if self.__class__._constant_mode:
                self._attributes = apply_constant(self._attributes)
            elif self.__class__._shuffle_map:
                self._attributes = apply_shuffle(self._attributes, self.__class__._shuffle_map)
```

Note: This class imports `CamelsUS` from neuralhydrology. The full import at the top of `shuffled_dataset.py`:

```python
from neuralhydrology.datasetzoo.camelsus import CamelsUS
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pytest test/test_static_falsification.py -v`
Expected: 5 passed

- [ ] **Step 5: Commit**

```bash
git add src/static_falsification/shuffled_dataset.py test/test_static_falsification.py
git commit -m "feat(static_falsification): add shuffle/constant attribute manipulation functions"
```

---

### Task 3: Base EALSTM Config Template

**Files:**
- Create: `src/static_falsification/configs/base_ealstm.yml`

- [ ] **Step 1: Create the base config template**

Create `src/static_falsification/configs/base_ealstm.yml`:

```yaml
# Static Falsification Experiment — Base EALSTM Config
# Hyperparameters aligned with Kratzert et al. 2019 HESS
experiment_name: sf_{condition}_fold{fold_idx}

dataset: camels_us
data_dir: data/CAMELS_US

model: ealstm
head: regression
hidden_size: 256
initial_forget_bias: 3
output_dropout: 0.0
output_activation: linear

epochs: 30
batch_size: 256
optimizer: Adam
loss: NSE
learning_rate:
  0: 0.001

# Basin files — will be overridden per fold by generate_configs.py
train_basin_file: src/static_falsification/data/fold0_train.txt
validation_basin_file: src/static_falsification/data/fold0_validation.txt
test_basin_file: src/static_falsification/data/fold0_test.txt

# Time periods (Kratzert 2019 HESS alignment)
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
  - dom_land_cover
  - root_depth_50
  - root_depth_99
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

- [ ] **Step 2: Verify YAML is valid**

Run: `python -c "import yaml; yaml.safe_load(open('src/static_falsification/configs/base_ealstm.yml'))"`
Expected: No error

- [ ] **Step 3: Commit**

```bash
git add src/static_falsification/configs/base_ealstm.yml
git commit -m "feat(static_falsification): add base EALSTM config template"
```

---

### Task 4: Config Generator Script

**Files:**
- Create: `src/static_falsification/scripts/generate_configs.py`
- Modify: `test/test_static_falsification.py` (add test)

- [ ] **Step 1: Write the test**

Append to `test/test_static_falsification.py`:

```python
def test_generate_configs_creates_15_files(tmp_path):
    """generate_configs produces 15 YAML files (3 conditions x 5 folds)."""
    import yaml
    from static_falsification.scripts.generate_configs import generate_all_configs

    # Create minimal base config
    base_config = {
        "experiment_name": "sf_{condition}_fold{fold_idx}",
        "train_basin_file": "PLACEHOLDER",
        "validation_basin_file": "PLACEHOLDER",
        "test_basin_file": "PLACEHOLDER",
        "static_attributes": ["elev_mean", "slope_mean"],
    }
    base_yml = tmp_path / "base.yml"
    with open(base_yml, "w") as f:
        yaml.dump(base_config, f)

    # Create fake data dir with fold files
    data_dir = tmp_path / "data"
    data_dir.mkdir()
    for fold_idx in range(5):
        for split in ["train", "validation", "test"]:
            (data_dir / f"fold{fold_idx}_{split}.txt").write_text("01234567\n")

    out_dir = tmp_path / "configs"
    generate_all_configs(base_yml, data_dir, out_dir, n_folds=5)

    configs = list(out_dir.glob("*.yml"))
    assert len(configs) == 15

    # E4 configs keep static_attributes (EALSTM requires x_s);
    # zeroing happens at dataset level, not config level.
    e4_configs = [c for c in configs if "e4" in c.name]
    assert len(e4_configs) == 5
    for cfg_path in e4_configs:
        with open(cfg_path) as f:
            cfg = yaml.safe_load(f)
        assert len(cfg.get("static_attributes", [])) > 0, "E4 must keep static_attributes for EALSTM"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest test/test_static_falsification.py::test_generate_configs_creates_15_files -v`
Expected: FAIL

- [ ] **Step 3: Implement generate_configs.py**

Create `src/static_falsification/scripts/generate_configs.py`:

```python
"""Batch-generate 15 YAML configs (3 conditions x 5 folds) from base template."""
import copy
from pathlib import Path

import yaml


def generate_all_configs(base_yml: Path, data_dir: Path, out_dir: Path, n_folds: int = 5):
    """Generate E1, E3, E4 configs for each fold.

    E1: correct static attributes (baseline)
    E3: shuffled static (shuffle injection happens at dataset level, not config)
    E4: no static attributes (constant zero = remove from config)
    """
    with open(base_yml) as f:
        base = yaml.safe_load(f)

    out_dir.mkdir(parents=True, exist_ok=True)

    for fold_idx in range(n_folds):
        for condition in ["e1", "e3", "e4"]:
            cfg = copy.deepcopy(base)

            # Set experiment name
            cfg["experiment_name"] = f"sf_{condition}_fold{fold_idx}"

            # Set basin files
            cfg["train_basin_file"] = str(data_dir / f"fold{fold_idx}_train.txt")
            cfg["validation_basin_file"] = str(data_dir / f"fold{fold_idx}_validation.txt")
            cfg["test_basin_file"] = str(data_dir / f"fold{fold_idx}_test.txt")

            # E3 and E4: configs are identical to E1. The shuffle (E3) and
            # constant-zero (E4) transformations are applied at dataset level
            # by run_training.py, NOT in the config.
            # EALSTM requires x_s in forward pass, so static_attributes must stay.

            fname = out_dir / f"ealstm_{condition}_fold{fold_idx}.yml"
            with open(fname, "w") as f:
                yaml.dump(cfg, f, default_flow_style=False, sort_keys=False)


def main():
    base_yml = Path("src/static_falsification/configs/base_ealstm.yml")
    data_dir = Path("src/static_falsification/data")
    out_dir = Path("src/static_falsification/configs")
    generate_all_configs(base_yml, data_dir, out_dir)
    print(f"Generated 15 configs in {out_dir}")


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pytest test/test_static_falsification.py -v`
Expected: 6 passed

- [ ] **Step 5: Commit**

```bash
git add src/static_falsification/scripts/generate_configs.py test/test_static_falsification.py
git commit -m "feat(static_falsification): add config generator for 3 conditions x 5 folds"
```

---

### Task 5: Training Script (E1, E3, E4)

**Files:**
- Create: `src/static_falsification/scripts/run_training.py`

- [ ] **Step 1: Implement training script**

Create `src/static_falsification/scripts/run_training.py`:

```python
"""Batch training for static falsification experiments.

Usage:
    # Train all 15 models sequentially (local):
    python -m static_falsification.scripts.run_training --gpu 0

    # Train a specific condition+fold:
    python -m static_falsification.scripts.run_training --condition e1 --fold 0 --gpu 0

    # E3 requires shuffle injection:
    python -m static_falsification.scripts.run_training --condition e3 --fold 2 --gpu 0
"""
import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent))

from neuralhydrology.nh_run import start_run
from neuralhydrology.datasetzoo import register_dataset
from neuralhydrology.datasetzoo.camelsus import CamelsUS
from static_falsification.shuffled_dataset import ModifiedCamelsUS


def run_single(condition: str, fold_idx: int, gpu: int = 0):
    """Train one model for a given condition and fold."""
    config_path = Path(f"src/static_falsification/configs/ealstm_{condition}_fold{fold_idx}.yml")
    if not config_path.exists():
        raise FileNotFoundError(f"Config not found: {config_path}. Run generate_configs.py first.")

    if condition in ("e3", "e4"):
        ModifiedCamelsUS._shuffle_map = None
        ModifiedCamelsUS._constant_mode = False

        if condition == "e3":
            shuffle_maps_path = Path("src/static_falsification/data/shuffle_maps.json")
            with open(shuffle_maps_path) as f:
                all_maps = json.load(f)
            ModifiedCamelsUS._shuffle_map = all_maps[str(fold_idx)]
            print(f"[E3] Shuffle mode for fold {fold_idx}")
        elif condition == "e4":
            ModifiedCamelsUS._constant_mode = True
            print(f"[E4] Constant (zero) mode for fold {fold_idx}")

        register_dataset("camels_us", ModifiedCamelsUS)

    print(f"Training {condition} fold {fold_idx} with config: {config_path}")
    start_run(config_file=config_path, gpu=gpu)

    if condition in ("e3", "e4"):
        ModifiedCamelsUS._shuffle_map = None
        ModifiedCamelsUS._constant_mode = False
        register_dataset("camels_us", CamelsUS)


def main():
    parser = argparse.ArgumentParser(description="Train static falsification models")
    parser.add_argument("--condition", type=str, choices=["e1", "e3", "e4", "all"], default="all")
    parser.add_argument("--fold", type=int, default=-1, help="Fold index (0-4), -1 for all")
    parser.add_argument("--gpu", type=int, default=0, help="GPU id (-1 for CPU)")
    args = parser.parse_args()

    conditions = ["e1", "e3", "e4"] if args.condition == "all" else [args.condition]
    folds = list(range(5)) if args.fold < 0 else [args.fold]

    for condition in conditions:
        for fold_idx in folds:
            run_single(condition, fold_idx, args.gpu)


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Verify script loads without error**

Run: `python -c "import sys; sys.path.insert(0, 'src'); from static_falsification.scripts.run_training import main; print('OK')"`
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add src/static_falsification/scripts/run_training.py
git commit -m "feat(static_falsification): add batch training script with E3 shuffle injection"
```

---

### Task 6: E2 Evaluation Script (Test-Time Shuffle)

**Files:**
- Create: `src/static_falsification/scripts/run_eval_e2.py`

- [ ] **Step 1: Implement E2 evaluation script**

Create `src/static_falsification/scripts/run_eval_e2.py`:

```python
"""E2 evaluation: load E1 models and evaluate with shuffled static attributes.

Usage:
    python -m static_falsification.scripts.run_eval_e2 --results-dir results/11_static_falsification --gpu 0
    python -m static_falsification.scripts.run_eval_e2 --results-dir results/11_static_falsification --fold 0 --gpu 0
"""
import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent))

from neuralhydrology.datasetzoo import register_dataset
from neuralhydrology.datasetzoo.camelsus import CamelsUS
from neuralhydrology.evaluation.evaluate import start_evaluation
from neuralhydrology.utils.config import Config
from static_falsification.shuffled_dataset import ModifiedCamelsUS


def eval_e2_single(results_dir: Path, fold_idx: int, gpu: int = 0):
    """Evaluate E1 model from a fold with shuffled static attributes."""
    # Find the E1 run directory
    e1_pattern = f"sf_e1_fold{fold_idx}_*"
    e1_dirs = sorted(results_dir.glob(e1_pattern))
    if not e1_dirs:
        raise FileNotFoundError(f"No E1 run directory found matching {e1_pattern} in {results_dir}")
    run_dir = e1_dirs[-1]  # Use the latest if multiple exist

    # Load shuffle map and register modified dataset
    shuffle_maps_path = Path("src/static_falsification/data/shuffle_maps.json")
    with open(shuffle_maps_path) as f:
        all_maps = json.load(f)
    ModifiedCamelsUS._shuffle_map = all_maps[str(fold_idx)]
    ModifiedCamelsUS._constant_mode = False
    register_dataset("camels_us", ModifiedCamelsUS)

    print(f"[E2] Evaluating E1 model from {run_dir} with shuffled static (fold {fold_idx})")

    config = Config(run_dir / "config.yml")
    if gpu >= 0:
        config.device = f"cuda:{gpu}"
    else:
        config.device = "cpu"

    # Override experiment name so results are saved separately
    config.experiment_name = f"sf_e2_fold{fold_idx}"

    start_evaluation(cfg=config, run_dir=run_dir, period="test")

    # Restore
    ModifiedCamelsUS._shuffle_map = None
    ModifiedCamelsUS._constant_mode = False
    register_dataset("camels_us", CamelsUS)


def main():
    parser = argparse.ArgumentParser(description="E2: evaluate E1 models with shuffled static")
    parser.add_argument("--results-dir", type=str, required=True)
    parser.add_argument("--fold", type=int, default=-1, help="Fold index (0-4), -1 for all")
    parser.add_argument("--gpu", type=int, default=0)
    args = parser.parse_args()

    results_dir = Path(args.results_dir)
    folds = list(range(5)) if args.fold < 0 else [args.fold]

    for fold_idx in folds:
        eval_e2_single(results_dir, fold_idx, args.gpu)


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Verify script loads without error**

Run: `python -c "import sys; sys.path.insert(0, 'src'); from static_falsification.scripts.run_eval_e2 import main; print('OK')"`
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add src/static_falsification/scripts/run_eval_e2.py
git commit -m "feat(static_falsification): add E2 test-time shuffle evaluation script"
```

---

### Task 7: Results Analysis Script

**Files:**
- Create: `src/static_falsification/scripts/analyze_results.py`

- [ ] **Step 1: Implement analysis script**

Create `src/static_falsification/scripts/analyze_results.py`:

```python
"""Aggregate results across folds, compute statistics, and generate figures.

Usage:
    python -m static_falsification.scripts.analyze_results --results-dir results/11_static_falsification
"""
import argparse
import json
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from scipy import stats


CONDITIONS = ["e1", "e2", "e3", "e4"]
CONDITION_LABELS = {
    "e1": "E1: Correct Static",
    "e2": "E2: Train Correct, Test Shuffle",
    "e3": "E3: Train+Test Shuffle",
    "e4": "E4: Constant (Zero) Static",
}


def load_results(results_dir: Path) -> pd.DataFrame:
    """Load per-basin NSE/KGE from all experiment run directories."""
    rows = []
    for condition in CONDITIONS:
        for fold_idx in range(5):
            pattern = f"sf_{condition}_fold{fold_idx}_*"
            run_dirs = sorted(results_dir.glob(pattern))
            if not run_dirs:
                print(f"WARNING: No run directory for {condition} fold {fold_idx}")
                continue
            run_dir = run_dirs[-1]

            # Find the test results CSV
            test_results = list(run_dir.glob("test/model_epoch*/test_results.csv"))
            if not test_results:
                # Try pickle format
                test_results = list(run_dir.glob("test/model_epoch*/test_results.p"))
            if not test_results:
                print(f"WARNING: No test results in {run_dir}")
                continue

            results_file = test_results[-1]
            if results_file.suffix == ".csv":
                df = pd.read_csv(results_file, index_col=0)
            else:
                df = pd.read_pickle(results_file)

            for basin in df.index:
                row = {
                    "condition": condition,
                    "fold": fold_idx,
                    "basin": basin,
                }
                if "NSE" in df.columns:
                    row["NSE"] = df.loc[basin, "NSE"]
                if "KGE" in df.columns:
                    row["KGE"] = df.loc[basin, "KGE"]
                rows.append(row)

    return pd.DataFrame(rows)


def compute_table1(df: pd.DataFrame) -> pd.DataFrame:
    """Table 1: median NSE/KGE per condition, with Wilcoxon p-values vs E1."""
    summary = []
    for condition in CONDITIONS:
        cond_df = df[df["condition"] == condition]
        row = {
            "Condition": CONDITION_LABELS[condition],
            "Median NSE": cond_df["NSE"].median(),
            "Mean NSE": cond_df["NSE"].mean(),
            "Median KGE": cond_df.get("KGE", pd.Series(dtype=float)).median(),
        }
        if condition != "e1":
            e1_nse = df[df["condition"] == "e1"].set_index(["fold", "basin"])["NSE"]
            cx_nse = cond_df.set_index(["fold", "basin"])["NSE"]
            common = e1_nse.index.intersection(cx_nse.index)
            if len(common) > 0:
                stat, pval = stats.wilcoxon(e1_nse.loc[common], cx_nse.loc[common])
                row["p-value vs E1"] = pval
            else:
                row["p-value vs E1"] = float("nan")
        else:
            row["p-value vs E1"] = float("nan")
        summary.append(row)
    return pd.DataFrame(summary)


def plot_fig1_boxplots(df: pd.DataFrame, out_dir: Path):
    """Fig 1: E1-E4 PUB NSE box plots."""
    fig, ax = plt.subplots(figsize=(8, 5))
    data = [df[df["condition"] == c]["NSE"].dropna().values for c in CONDITIONS]
    labels = [CONDITION_LABELS[c] for c in CONDITIONS]
    bp = ax.boxplot(data, labels=labels, patch_artist=True)
    colors = ["#2196F3", "#FF9800", "#9C27B0", "#607D8B"]
    for patch, color in zip(bp["boxes"], colors):
        patch.set_facecolor(color)
        patch.set_alpha(0.7)
    ax.set_ylabel("NSE")
    ax.set_title("PUB Performance: Static Attribute Permutation Experiment")
    ax.axhline(y=0, color="gray", linestyle="--", alpha=0.5)
    plt.xticks(rotation=15, ha="right")
    plt.tight_layout()
    fig.savefig(out_dir / "fig1_boxplots.png", dpi=150)
    plt.close(fig)
    print(f"Saved {out_dir / 'fig1_boxplots.png'}")


def plot_fig2_scatter(df: pd.DataFrame, out_dir: Path):
    """Fig 2: E1 vs E2 per-basin NSE scatter."""
    e1 = df[df["condition"] == "e1"].set_index(["fold", "basin"])["NSE"]
    e2 = df[df["condition"] == "e2"].set_index(["fold", "basin"])["NSE"]
    common = e1.index.intersection(e2.index)

    fig, ax = plt.subplots(figsize=(6, 6))
    ax.scatter(e1.loc[common], e2.loc[common], alpha=0.4, s=10, color="#2196F3")
    lims = [min(ax.get_xlim()[0], ax.get_ylim()[0]), max(ax.get_xlim()[1], ax.get_ylim()[1])]
    ax.plot(lims, lims, "k--", alpha=0.5, label="y = x (no difference)")
    ax.set_xlabel("E1 NSE (Correct Static)")
    ax.set_ylabel("E2 NSE (Shuffled Static at Test)")
    ax.set_title("E1 vs E2: Does Shuffling Static Attributes Hurt?")
    ax.legend()
    ax.set_aspect("equal")
    plt.tight_layout()
    fig.savefig(out_dir / "fig2_scatter_e1_vs_e2.png", dpi=150)
    plt.close(fig)
    print(f"Saved {out_dir / 'fig2_scatter_e1_vs_e2.png'}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--results-dir", type=str, required=True)
    args = parser.parse_args()

    results_dir = Path(args.results_dir)
    out_dir = results_dir / "analysis"
    out_dir.mkdir(parents=True, exist_ok=True)

    print("Loading results...")
    df = load_results(results_dir)
    if df.empty:
        print("ERROR: No results found. Check results-dir and run directories.")
        return

    print(f"Loaded {len(df)} basin-level results across {df['condition'].nunique()} conditions")

    # Table 1
    table1 = compute_table1(df)
    print("\n=== Table 1: Summary ===")
    print(table1.to_string(index=False))
    table1.to_csv(out_dir / "table1_summary.csv", index=False)

    # Figures
    plot_fig1_boxplots(df, out_dir)
    plot_fig2_scatter(df, out_dir)

    # Interpretation
    e1_median = df[df["condition"] == "e1"]["NSE"].median()
    e2_median = df[df["condition"] == "e2"]["NSE"].median()
    diff = e1_median - e2_median
    print(f"\n=== Key Result ===")
    print(f"E1 median NSE: {e1_median:.4f}")
    print(f"E2 median NSE: {e2_median:.4f}")
    print(f"Difference (E1 - E2): {diff:.4f}")
    if abs(diff) < 0.02:
        print("INTERPRETATION: Static attributes appear to have minimal impact (< 0.02 NSE)")
    else:
        print(f"INTERPRETATION: Static attributes have measurable impact ({diff:.4f} NSE)")


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Verify script loads without error**

Run: `python -c "import sys; sys.path.insert(0, 'src'); from static_falsification.scripts.analyze_results import main; print('OK')"`
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add src/static_falsification/scripts/analyze_results.py
git commit -m "feat(static_falsification): add results analysis with Wilcoxon tests and figures"
```

---

### Task 8: HPC Submission Script

**Files:**
- Create: `src/static_falsification/hpc/submit_all.slurm`

- [ ] **Step 1: Create HPC submission script**

Create `src/static_falsification/hpc/submit_all.slurm`:

```bash
#!/bin/bash
#SBATCH --job-name=sf_train
#SBATCH --partition=hgpu8
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=4
#SBATCH --mem=32G
#SBATCH --time=06:00:00
#SBATCH --array=0-14
#SBATCH --output=logs/11_static_falsification/slurm_%A_%a.out
#SBATCH --error=logs/11_static_falsification/slurm_%A_%a.err

# Map array index to condition + fold
# 0-4: E1 fold 0-4, 5-9: E3 fold 0-4, 10-14: E4 fold 0-4
CONDITIONS=(e1 e1 e1 e1 e1 e3 e3 e3 e3 e3 e4 e4 e4 e4 e4)
FOLDS=(0 1 2 3 4 0 1 2 3 4 0 1 2 3 4)

CONDITION=${CONDITIONS[$SLURM_ARRAY_TASK_ID]}
FOLD=${FOLDS[$SLURM_ARRAY_TASK_ID]}

echo "=== Task $SLURM_ARRAY_TASK_ID: ${CONDITION} fold ${FOLD} ==="
echo "Start: $(date)"

cd $HOME/neuralhydrology

# Activate conda environment
source activate nh

python -m static_falsification.scripts.run_training \
    --condition ${CONDITION} \
    --fold ${FOLD} \
    --gpu 0

echo "End: $(date)"
```

- [ ] **Step 2: Create log directory placeholder**

Run: `mkdir -p logs/11_static_falsification`

- [ ] **Step 3: Commit**

```bash
git add src/static_falsification/hpc/submit_all.slurm
git commit -m "feat(static_falsification): add HPC SLURM submission for 15 training jobs"
```

---

### Task 9: End-to-End Smoke Test

**Files:**
- Modify: `test/test_static_falsification.py` (add smoke test)

- [ ] **Step 1: Write smoke test**

Append to `test/test_static_falsification.py`:

```python
@pytest.mark.skipif(
    not Path("data/CAMELS_US").exists(),
    reason="CAMELS_US data not available"
)
def test_smoke_e1_single_basin(tmp_path):
    """Smoke test: train EALSTM on 1 basin for 1 epoch with correct static."""
    import yaml

    base_yml = Path("src/static_falsification/configs/base_ealstm.yml")
    if not base_yml.exists():
        pytest.skip("Base config not found")

    with open(base_yml) as f:
        cfg = yaml.safe_load(f)

    # Override for smoke test
    cfg["experiment_name"] = "smoke_e1"
    cfg["epochs"] = 1
    cfg["batch_size"] = 16
    cfg["validate_every"] = 1
    cfg["validate_n_random_basins"] = 1
    cfg["run_dir"] = str(tmp_path / "runs")
    cfg["seq_length"] = 30

    # Write a single-basin file
    basin_file = tmp_path / "basins.txt"
    basin_file.write_text("01013500\n")
    cfg["train_basin_file"] = str(basin_file)
    cfg["validation_basin_file"] = str(basin_file)
    cfg["test_basin_file"] = str(basin_file)

    smoke_cfg = tmp_path / "smoke.yml"
    with open(smoke_cfg, "w") as f:
        yaml.dump(cfg, f)

    from neuralhydrology.nh_run import start_run
    start_run(config_file=smoke_cfg, gpu=-1)

    # Check that a model checkpoint was saved
    run_dirs = list((tmp_path / "runs").iterdir())
    assert len(run_dirs) == 1
    assert any((run_dirs[0]).glob("model_epoch*.pt"))
```

- [ ] **Step 2: Run smoke test (if data available)**

Run: `pytest test/test_static_falsification.py::test_smoke_e1_single_basin -v --timeout=120`
Expected: PASS (or SKIP if CAMELS_US data not present)

- [ ] **Step 3: Commit**

```bash
git add test/test_static_falsification.py
git commit -m "test(static_falsification): add end-to-end smoke test for single-basin EALSTM"
```

---

### Task 10: Run the Full Pipeline (Data Generation)

This task generates the actual experiment data files. It must be run interactively, not in tests.

- [ ] **Step 1: Generate splits and derangements**

Run: `cd src && python -m static_falsification.scripts.generate_splits`
Expected output:
```
Generated 5-fold splits: [106, 106, 106, 106, 107] basins per fold
Generated 5 derangement mappings
Output: src/static_falsification/data
```

- [ ] **Step 2: Generate 15 config files**

Run: `cd src && python -m static_falsification.scripts.generate_configs`
Expected output: `Generated 15 configs in src/static_falsification/configs`

- [ ] **Step 3: Verify generated files**

Run: `ls src/static_falsification/configs/ealstm_*.yml | wc -l`
Expected: `15`

Run: `ls src/static_falsification/data/fold*_*.txt | wc -l`
Expected: `15` (5 folds × 3 splits)

- [ ] **Step 4: Commit generated data**

```bash
git add src/static_falsification/data/ src/static_falsification/configs/ealstm_*.yml
git commit -m "data(static_falsification): generate 5-fold splits, derangements, and 15 configs"
```

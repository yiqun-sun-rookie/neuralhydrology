# MTS-Mamba vs MTS-LSTM 双频率对比实验 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 分阶段验证 MTS-Mamba Context Prepend 状态传递方案（方案 A）是否达到 MTS-LSTM baseline 95% 的小时 NSE，并逐步扩展到更多流域。

**Architecture:** 三阶段递进：(1) 4 basin test data 快速验证，(2) CAMELS-H 10 basin 扩展验证，(3) HPC 全量规模实验。

**Tech Stack:** NeuralHydrology (PyTorch), hourly_camels_us dataset, Mamba (transformers backend), xarray

**路径规范（项目约定）：**
- 配置: `src/mts_mamba_global_transfer/configs/`
- 脚本: `src/mts_mamba_global_transfer/scripts/`
- 数据列表: `src/mts_mamba_global_transfer/data/`
- 结果: `results/41_mts_mamba_global_transfer/`
- 日志: `logs/41_mts_mamba_global_transfer/`
- 文档: `draft/ideas/41_mts_mamba_global_transfer.md`

---

## 约束条件

- **可用小时数据**：`test/test_data/camels_us/hourly/usgs-streamflow-nldas_hourly.nc`
- **可用 basins**：4 个（01022500, 01547700, 02064000, 03015500）
- **时间范围**：2000-01-01 ~ 2002-12-31（3 年小时数据）
- **Basin list file**：`test/test_data/4_basins_test_set.txt`（纯 8 位 USGS ID，无 camels_ 前缀）
- **参考配置**：`test/test_configs/multi_timescale_regression.test.yml`

## 实验设计

| 参数 | 值 | 说明 |
|------|-----|------|
| basins | 4 | 受限于 test data |
| epochs | 3 | 足够观察收敛趋势 |
| hidden_size | 32 | CPU 友好，快速验证 |
| seq_length (1D) | 30 | 30 天日序列 |
| seq_length (1h) | 336 | 14 天小时序列（336/24=14，与日频率对齐） |
| predict_last_n (1D) | 1 | 预测最后 1 天 |
| predict_last_n (1h) | 24 | 预测最后 24 小时 |
| batch_size | 32 | CPU 友好 |
| train | 01/01/2000 – 31/12/2000 | 1 年训练 |
| val | 01/01/2001 – 31/12/2001 | 1 年验证 |
| test | 01/01/2002 – 31/12/2002 | 1 年测试 |

---

### Task 1: 创建 MTS-LSTM baseline 配置

**Files:**
- Create: `src/mts_mamba_global_transfer/configs/mtslstm_camels_hourly_4basins_ep3.yml`

**Step 1: 创建配置文件**

```yaml
# Baseline: MTS-LSTM with CAMELS-US hourly data (4 basins, 3 epochs)
# 阶段 0 对比实验 — MTS-LSTM baseline
experiment_name: 41_mtslstm_camels_hourly_4basins_ep3

# --- Data ---
dataset: hourly_camels_us
data_dir: ./test/test_data/camels_us
forcings: nldas_hourly

train_basin_file: ./test/test_data/4_basins_test_set.txt
validation_basin_file: ./test/test_data/4_basins_test_set.txt
test_basin_file: ./test/test_data/4_basins_test_set.txt

train_start_date: "01/01/2000"
train_end_date: "31/12/2000"
validation_start_date: "01/01/2001"
validation_end_date: "31/12/2001"
test_start_date: "01/01/2002"
test_end_date: "31/12/2002"

dynamic_inputs:
  - total_precipitation
  - temperature
target_variables:
  - qobs_mm_per_hour
static_attributes:
  - elev_mean
  - slope_mean

# --- Multi-timescale ---
use_frequencies:
  - 1D
  - 1h
seq_length:
  1D: 30
  1h: 336
predict_last_n:
  1D: 1
  1h: 24

# --- Model: MTS-LSTM ---
model: mtslstm
head: regression
output_activation: linear
hidden_size: 32
initial_forget_bias: 3
output_dropout: 0.4
transfer_mtslstm_states:
  h: linear
  c: linear
shared_mtslstm: false

# --- Training ---
epochs: 3
batch_size: 32
optimizer: Adam
loss: MSE
learning_rate:
  0: 1e-3
clip_gradient_norm: 1

# --- Logging & Validation ---
validate_every: 1
validate_n_random_basins: 4
save_weights_every: 1
log_interval: 5
log_tensorboard: true
log_n_figures: 2
metrics:
  - NSE
  - KGE
  - Alpha-NSE
  - Beta-NSE

num_workers: 0
seed: 111
device: cpu
run_dir: results/41_mts_mamba_global_transfer
```

**Step 2: 验证配置加载**

Run: `python -c "from neuralhydrology.utils.config import Config; c = Config('src/mts_mamba_global_transfer/configs/mtslstm_camels_hourly_4basins_ep3.yml'); print('OK:', c.model, c.use_frequencies)"`
Expected: `OK: mtslstm ['1D', '1h']`

**Step 3: Commit**

```bash
git add src/mts_mamba_global_transfer/configs/mtslstm_camels_hourly_4basins_ep3.yml
git commit -m "feat(41): add MTS-LSTM baseline config for Phase 0 comparison"
```

---

### Task 2: 创建 MTS-Mamba 实验配置

**Files:**
- Create: `src/mts_mamba_global_transfer/configs/mtsmamba_camels_hourly_4basins_ep3.yml`

**Step 1: 创建配置文件**

```yaml
# Experimental: MTS-Mamba (Context Prepend) with CAMELS-US hourly data (4 basins, 3 epochs)
# 阶段 0 对比实验 — MTS-Mamba 方案 A
experiment_name: 41_mtsmamba_camels_hourly_4basins_ep3

# --- Data --- (与 MTS-LSTM baseline 完全相同)
dataset: hourly_camels_us
data_dir: ./test/test_data/camels_us
forcings: nldas_hourly

train_basin_file: ./test/test_data/4_basins_test_set.txt
validation_basin_file: ./test/test_data/4_basins_test_set.txt
test_basin_file: ./test/test_data/4_basins_test_set.txt

train_start_date: "01/01/2000"
train_end_date: "31/12/2000"
validation_start_date: "01/01/2001"
validation_end_date: "31/12/2001"
test_start_date: "01/01/2002"
test_end_date: "31/12/2002"

dynamic_inputs:
  - total_precipitation
  - temperature
target_variables:
  - qobs_mm_per_hour
static_attributes:
  - elev_mean
  - slope_mean

# --- Multi-timescale ---
use_frequencies:
  - 1D
  - 1h
seq_length:
  1D: 30
  1h: 336
predict_last_n:
  1D: 1
  1h: 24

# --- Model: MTS-Mamba ---
model: mtsmamba
head: regression
output_activation: linear
hidden_size: 32
initial_forget_bias: 3
output_dropout: 0.4
transfer_mtsmamba_states: linear
mamba_d_state: 16
mamba_d_conv: 4
mamba_expand: 2
mamba_n_layers: 2

# --- Training --- (与 baseline 完全相同)
epochs: 3
batch_size: 32
optimizer: Adam
loss: MSE
learning_rate:
  0: 1e-3
clip_gradient_norm: 1

# --- Logging & Validation ---
validate_every: 1
validate_n_random_basins: 4
save_weights_every: 1
log_interval: 5
log_tensorboard: true
log_n_figures: 2
metrics:
  - NSE
  - KGE
  - Alpha-NSE
  - Beta-NSE

num_workers: 0
seed: 111
device: cpu
run_dir: results/41_mts_mamba_global_transfer
```

**Step 2: 验证配置加载**

Run: `python -c "from neuralhydrology.utils.config import Config; c = Config('src/mts_mamba_global_transfer/configs/mtsmamba_camels_hourly_4basins_ep3.yml'); print('OK:', c.model, c.use_frequencies, c.transfer_mtsmamba_states)"`
Expected: `OK: mtsmamba ['1D', '1h'] linear`

**Step 3: Commit**

```bash
git add src/mts_mamba_global_transfer/configs/mtsmamba_camels_hourly_4basins_ep3.yml
git commit -m "feat(41): add MTS-Mamba experimental config for Phase 0 comparison"
```

---

### Task 3: 编写对比结果提取脚本

**Files:**
- Create: `src/mts_mamba_global_transfer/scripts/compare_phase0.py`

**Step 1: 编写脚本**

```python
"""Phase 0 结果提取与对比脚本.

Usage:
    python -m src.mts_mamba_global_transfer.scripts.compare_phase0 \
        --lstm-dir results/41_mts_mamba_global_transfer/<lstm_run_dir> \
        --mamba-dir results/41_mts_mamba_global_transfer/<mamba_run_dir>
"""
import argparse
import pickle
import sys
from pathlib import Path


def load_test_results(run_dir: Path) -> dict:
    """Load test_results.p from the latest epoch directory."""
    test_dir = run_dir / "test"
    if not test_dir.exists():
        raise FileNotFoundError(f"No test/ directory in {run_dir}")
    epoch_dirs = sorted(test_dir.glob("model_epoch*"))
    if not epoch_dirs:
        raise FileNotFoundError(f"No model_epoch* directories in {test_dir}")
    results_file = epoch_dirs[-1] / "test_results.p"
    with open(results_file, "rb") as f:
        return pickle.load(f)


def extract_metrics(results: dict, freq: str = "1h") -> dict:
    """Extract per-basin metrics for a given frequency, return {basin: {metric: value}}."""
    metrics = {}
    for basin, freq_data in results.items():
        if freq in freq_data:
            xr_ds = freq_data[freq]["xr"]
            basin_metrics = {}
            for attr in ["NSE", "KGE", "Alpha-NSE", "Beta-NSE"]:
                val = xr_ds.attrs.get(attr)
                if val is not None:
                    basin_metrics[attr] = float(val)
            metrics[basin] = basin_metrics
    return metrics


def mean_metric(per_basin: dict, metric: str) -> float:
    """Compute mean of a metric across basins."""
    vals = [b[metric] for b in per_basin.values() if metric in b]
    return sum(vals) / len(vals) if vals else float("nan")


def main():
    parser = argparse.ArgumentParser(description="Phase 0: MTS-Mamba vs MTS-LSTM comparison")
    parser.add_argument("--lstm-dir", type=Path, required=True, help="MTS-LSTM run directory")
    parser.add_argument("--mamba-dir", type=Path, required=True, help="MTS-Mamba run directory")
    parser.add_argument("--threshold", type=float, default=0.95, help="Pass threshold (default: 0.95)")
    args = parser.parse_args()

    print("=" * 60)
    print("Phase 0: MTS-Mamba vs MTS-LSTM Comparison")
    print("=" * 60)

    lstm_results = load_test_results(args.lstm_dir)
    mamba_results = load_test_results(args.mamba_dir)

    lstm_hourly = extract_metrics(lstm_results, "1h")
    mamba_hourly = extract_metrics(mamba_results, "1h")

    print(f"\n{'Basin':<12} {'LSTM NSE':>10} {'Mamba NSE':>10} {'Ratio':>8}")
    print("-" * 44)
    for basin in sorted(lstm_hourly.keys()):
        lstm_nse = lstm_hourly[basin].get("NSE", float("nan"))
        mamba_nse = mamba_hourly.get(basin, {}).get("NSE", float("nan"))
        ratio = mamba_nse / lstm_nse if lstm_nse != 0 else float("nan")
        print(f"{basin:<12} {lstm_nse:>10.4f} {mamba_nse:>10.4f} {ratio:>8.4f}")

    lstm_mean = mean_metric(lstm_hourly, "NSE")
    mamba_mean = mean_metric(mamba_hourly, "NSE")
    ratio = mamba_mean / lstm_mean if lstm_mean != 0 else float("nan")

    print("-" * 44)
    print(f"{'Mean':<12} {lstm_mean:>10.4f} {mamba_mean:>10.4f} {ratio:>8.4f}")

    print(f"\nThreshold: {args.threshold}")
    passed = ratio >= args.threshold
    status = "PASSED" if passed else "FAILED"
    print(f"Result: {status} (ratio={ratio:.4f}, target>={args.threshold})")

    # KGE summary
    lstm_kge = mean_metric(lstm_hourly, "KGE")
    mamba_kge = mean_metric(mamba_hourly, "KGE")
    print(f"\nKGE: LSTM={lstm_kge:.4f}, Mamba={mamba_kge:.4f}")

    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
```

**Step 2: Commit**

```bash
git add src/mts_mamba_global_transfer/scripts/compare_phase0.py
git commit -m "feat(41): add Phase 0 comparison script"
```

---

### Task 4: 运行 MTS-LSTM baseline 训练

**Step 1: 运行训练**

Run:
```bash
python -m neuralhydrology.nh_run train \
  --config-file src/mts_mamba_global_transfer/configs/mtslstm_camels_hourly_4basins_ep3.yml \
  --gpu -1
```

Expected:
- 训练正常启动，无报错
- 3 个 epoch 完成
- 结果写入 `results/41_mts_mamba_global_transfer/41_mtslstm_camels_hourly_4basins_ep3_<timestamp>/`
- 预计耗时：CPU 上 20-60 分钟

**Step 2: 运行测试评估**

Run:
```bash
python -m neuralhydrology.nh_run evaluate \
  --run-dir results/41_mts_mamba_global_transfer/41_mtslstm_camels_hourly_4basins_ep3_<timestamp> \
  --period test --epoch 3
```

Expected: 生成 `test/model_epoch003/test_results.p`

**Step 3: 记录 run directory 路径**

记录完整路径，供 Task 6 使用。

---

### Task 5: 运行 MTS-Mamba 实验训练

**Step 1: 运行训练**

Run:
```bash
python -m neuralhydrology.nh_run train \
  --config-file src/mts_mamba_global_transfer/configs/mtsmamba_camels_hourly_4basins_ep3.yml \
  --gpu -1
```

Expected:
- 训练正常启动，无报错
- 日志显示 `[MTS-Mamba] backend=transformers, frequencies=['1D', '1h'], transfer=linear`
- 3 个 epoch 完成
- 结果写入 `results/41_mts_mamba_global_transfer/41_mtsmamba_camels_hourly_4basins_ep3_<timestamp>/`

**Step 2: 运行测试评估**

Run:
```bash
python -m neuralhydrology.nh_run evaluate \
  --run-dir results/41_mts_mamba_global_transfer/41_mtsmamba_camels_hourly_4basins_ep3_<timestamp> \
  --period test --epoch 3
```

Expected: 生成 `test/model_epoch003/test_results.p`

---

### Task 6: 提取指标并对比

**Step 1: 运行对比脚本**

Run:
```bash
python src/mts_mamba_global_transfer/scripts/compare_phase0.py \
  --lstm-dir results/41_mts_mamba_global_transfer/41_mtslstm_camels_hourly_4basins_ep3_<timestamp> \
  --mamba-dir results/41_mts_mamba_global_transfer/41_mtsmamba_camels_hourly_4basins_ep3_<timestamp>
```

Expected output 示例:
```
============================================================
Phase 0: MTS-Mamba vs MTS-LSTM Comparison
============================================================

Basin        LSTM NSE  Mamba NSE    Ratio
--------------------------------------------
01022500       0.5234     0.5012   0.9576
01547700       0.4891     0.4723   0.9657
02064000       0.6012     0.5801   0.9649
03015500       0.5567     0.5389   0.9680
--------------------------------------------
Mean           0.5426     0.5231   0.9640

Threshold: 0.95
Result: PASSED (ratio=0.9640, target>=0.95)
```

**Step 2: 判断结果**

- **PASSED (ratio >= 0.95)**：方案 A 验证通过，进入阶段 1（规模实验）
- **FAILED (ratio < 0.95)**：分析原因，考虑调整超参或尝试方案 B

---

### Task 7: 更新文档与 Results Index

**Files:**
- Modify: `draft/ideas/41_mts_mamba_global_transfer.md`

**Step 1: 在 Results Index 中添加两条记录**

在 `## Results Index` 表格末尾添加：

```markdown
| 41_mtslstm_camels_hourly_4basins_ep3_<timestamp> | 2026-02-24 | `results/41_mts_mamba_global_transfer/...` | Phase 0 baseline: hourly NSE=X.XXXX, KGE=X.XXXX |
| 41_mtsmamba_camels_hourly_4basins_ep3_<timestamp> | 2026-02-24 | `results/41_mts_mamba_global_transfer/...` | Phase 0 experimental: hourly NSE=X.XXXX, KGE=X.XXXX, ratio=X.XXXX |
```

**Step 2: 在 Progress Log 中添加记录**

```markdown
| 2026-02-24 | Phase 0 对比实验完成 | MTS-Mamba vs MTS-LSTM (4 basins, 3 ep, 1D+1h): hourly NSE ratio=X.XXXX, 结果: PASSED/FAILED |
```

**Step 3: 更新 阶段 0 checklist**

将以下项标记为 `[x]`：
```markdown
- [x] 配置 CAMELS-US mini 双频率对比实验（4 basins, 3 epochs, 1D+1H），MTS-Mamba vs MTS-LSTM。
```

**Step 4: Commit**

```bash
git add draft/ideas/41_mts_mamba_global_transfer.md \
      src/mts_mamba_global_transfer/configs/*.yml \
      src/mts_mamba_global_transfer/scripts/compare_phase0.py
git commit -m "feat(41): complete Phase 0 comparison experiment (MTS-Mamba vs MTS-LSTM)"
```

---

## Phase 2: CAMELS-H 扩展验证（10 basin）

> **前提条件：** Phase 1 通过（MTS-Mamba NSE ratio >= 0.95）。
>
> **数据说明（实测）：**
> - `data/camelsh/timeseries/Data/CAMELSH/timeseries/{basin}.nc`：3166 个流域，含 `Tair`（℃）/ `Rainf`（mm/hr）/ `Streamflow`（m³/s）等，`DateTime` 维，1980-2024 hourly
> - `data/camelsh/attributes/attributes.csv`：777 个流域，含 `elev_mean`、`slope_mean`、`area`（km²）等
> - `data/camelsh/filtered/filtered_basins_2010_2020_95pct_good.txt`：113 个优质流域，全部同时有 timeseries NC 和 attributes
> - **无需额外下载**；需实现 `HourlyCamelsH` dataset class

### Task 8: 实现 HourlyCamelsH dataset class

**Files:**
- Create: `neuralhydrology/datasetzoo/hourlycamelsh.py`
- Modify: `neuralhydrology/datasetzoo/__init__.py`

**Step 1: 实现 HourlyCamelsH**

```python
"""CAMELS-H hourly dataset class for NeuralHydrology.

Data layout expected at data_dir (= data/camelsh/):
  timeseries/Data/CAMELSH/timeseries/{basin}.nc  # Tair, Rainf, Streamflow, DateTime dim
  attributes/attributes.csv                       # basin_id (int), elev_mean, slope_mean, area(km²)...
"""
import logging
from pathlib import Path
from typing import Dict, List, Optional, Union

import numpy as np
import pandas as pd
import xarray as xr

from neuralhydrology.datasetzoo.basedataset import BaseDataset
from neuralhydrology.utils.config import Config

LOGGER = logging.getLogger(__name__)

_TIMESERIES_SUBPATH = Path("timeseries/Data/CAMELSH/timeseries")
_ATTRIBUTES_FILE = Path("attributes/attributes.csv")


class HourlyCamelsH(BaseDataset):
    """Hourly CAMELS-H dataset class.

    Reads per-basin hourly NetCDF files containing NLDAS-2 forcings and USGS streamflow.
    Streamflow is converted from m³/s to mm/hr using the basin area from the attributes file.

    Parameters
    ----------
    cfg : Config
        Run configuration. Key fields:
        - ``data_dir``: path to ``data/camelsh/``
        - ``dynamic_inputs``: subset of ``['Rainf', 'Tair', 'PSurf', 'SWdown', ...]``
        - ``target_variables``: should include ``'qobs_mm_per_hour'``
        - ``static_attributes``: subset of columns in ``attributes/attributes.csv``
    """

    def __init__(self, cfg: Config, is_train: bool, period: str, basin: str = None,
                 additional_features: list = [], id_to_int: dict = {}, scaler: dict = {}):
        self._attrs_cache: Optional[pd.DataFrame] = None
        super().__init__(cfg=cfg, is_train=is_train, period=period, basin=basin,
                         additional_features=additional_features, id_to_int=id_to_int, scaler=scaler)

    def _load_basin_data(self, basin: str) -> pd.DataFrame:
        """Load hourly timeseries for one basin."""
        nc_path = self.cfg.data_dir / _TIMESERIES_SUBPATH / f"{basin}.nc"
        if not nc_path.is_file():
            raise FileNotFoundError(f"No CAMELS-H timeseries NC for basin {basin} at {nc_path}")

        ds = xr.open_dataset(nc_path)
        df = ds.to_dataframe()
        df.index.name = "date"

        # Convert Streamflow m³/s → qobs_mm_per_hour
        if "Streamflow" in df.columns:
            area_km2 = self._get_basin_area(basin)
            area_m2 = area_km2 * 1e6
            df["qobs_mm_per_hour"] = df["Streamflow"] * 3600.0 * 1000.0 / area_m2
            df.loc[df["qobs_mm_per_hour"] < 0, "qobs_mm_per_hour"] = np.nan

        return df

    def _get_basin_area(self, basin: str) -> float:
        """Return basin area in km² from attributes file."""
        attrs = self._get_attrs()
        return float(attrs.loc[basin, "area"])

    def _get_attrs(self) -> pd.DataFrame:
        if self._attrs_cache is None:
            self._attrs_cache = _load_camelsh_attributes(self.cfg.data_dir)
        return self._attrs_cache

    def _load_attributes(self) -> pd.DataFrame:
        """Return attributes DataFrame indexed by basin id (zero-padded 8-digit string)."""
        attrs = _load_camelsh_attributes(self.cfg.data_dir)
        return attrs


def _load_camelsh_attributes(data_dir: Path) -> pd.DataFrame:
    """Load CAMELS-H attributes CSV, return DataFrame indexed by 8-digit basin id strings."""
    attrs_path = data_dir / _ATTRIBUTES_FILE
    if not attrs_path.is_file():
        raise FileNotFoundError(f"CAMELS-H attributes not found at {attrs_path}")
    attrs = pd.read_csv(attrs_path, index_col="basin_id")
    attrs.index = attrs.index.astype(str).str.zfill(8)
    return attrs
```

**Step 2: 注册到 datasetzoo factory**

在 `neuralhydrology/datasetzoo/__init__.py` 中，找到 `get_dataset` 函数，添加 `hourly_camelsh` 分支（参考其他 dataset 的注册方式）：

```python
from neuralhydrology.datasetzoo.hourlycamelsh import HourlyCamelsH

# 在 get_dataset() 的 if/elif 链中添加：
elif cfg.dataset == "hourly_camelsh":
    ds = HourlyCamelsH(cfg=cfg, is_train=is_train, period=period, basin=basin,
                       additional_features=additional_features, id_to_int=id_to_int, scaler=scaler)
```

**Step 3: 验证注册**

```bash
python -c "
from neuralhydrology.datasetzoo import get_dataset
print('OK: hourly_camelsh registered')
"
```

Expected: 无 ImportError

**Step 4: Commit**

```bash
git add neuralhydrology/datasetzoo/hourlycamelsh.py neuralhydrology/datasetzoo/__init__.py
git commit -m "feat: add HourlyCamelsH dataset class for Phase 2 comparison"
```

---

### Task 9: 创建 Phase 2 basin 列表与配置

**Files:**
- Create: `src/mts_mamba_global_transfer/data/phase2_camelsh_10basins.txt`
- Create: `src/mts_mamba_global_transfer/configs/phase2_mtslstm_camelsh_10b_ep3.yml`
- Create: `src/mts_mamba_global_transfer/configs/phase2_mtsmamba_camelsh_10b_ep3.yml`

**Step 1: 创建 basin 列表**

取 `data/camelsh/filtered/filtered_basins_2010_2020_95pct_good.txt` 前 10 个（已验证这 113 个流域全部有 timeseries NC + attributes）：

```
01081000
01098530
01108000
01109403
01110000
01118300
01119500
01121000
01123000
01125500
```

**Step 2: 创建 MTS-LSTM Phase 2 配置**

```yaml
# Phase 2 baseline: MTS-LSTM, CAMELS-H 10 basins (1980-2024 hourly, NLDAS-2 forcings)
experiment_name: 41_phase2_mtslstm_camelsh_10b_ep3

dataset: hourly_camelsh
data_dir: ./data/camelsh

train_basin_file: src/mts_mamba_global_transfer/data/phase2_camelsh_10basins.txt
validation_basin_file: src/mts_mamba_global_transfer/data/phase2_camelsh_10basins.txt
test_basin_file: src/mts_mamba_global_transfer/data/phase2_camelsh_10basins.txt

train_start_date: "01/01/2000"
train_end_date: "31/12/2015"
validation_start_date: "01/01/2016"
validation_end_date: "31/12/2018"
test_start_date: "01/01/2019"
test_end_date: "31/12/2020"

dynamic_inputs:
  - Rainf
  - Tair
target_variables:
  - qobs_mm_per_hour
static_attributes:
  - elev_mean
  - slope_mean

use_frequencies:
  - 1D
  - 1h
seq_length:
  1D: 30
  1h: 336
predict_last_n:
  1D: 1
  1h: 24

model: mtslstm
head: regression
output_activation: linear
hidden_size: 32
initial_forget_bias: 3
output_dropout: 0.4
transfer_mtslstm_states:
  h: linear
  c: linear
shared_mtslstm: false

epochs: 3
batch_size: 32
optimizer: Adam
loss: MSE
learning_rate:
  0: 1e-3
clip_gradient_norm: 1

validate_every: 1
validate_n_random_basins: 10
save_weights_every: 1
log_interval: 5
log_tensorboard: true
log_n_figures: 2
metrics:
  - NSE
  - KGE
  - Alpha-NSE
  - Beta-NSE

num_workers: 0
seed: 111
device: cpu
run_dir: results/41_mts_mamba_global_transfer
```

**Step 3: 创建 MTS-Mamba Phase 2 配置**（仅 model 字段不同）

```yaml
# Phase 2 experimental: MTS-Mamba, CAMELS-H 10 basins
experiment_name: 41_phase2_mtsmamba_camelsh_10b_ep3
# --- 所有 Data / Multi-timescale / Training / Logging 字段与 MTS-LSTM Phase 2 config 相同 ---
dataset: hourly_camelsh
data_dir: ./data/camelsh
train_basin_file: src/mts_mamba_global_transfer/data/phase2_camelsh_10basins.txt
validation_basin_file: src/mts_mamba_global_transfer/data/phase2_camelsh_10basins.txt
test_basin_file: src/mts_mamba_global_transfer/data/phase2_camelsh_10basins.txt
train_start_date: "01/01/2000"
train_end_date: "31/12/2015"
validation_start_date: "01/01/2016"
validation_end_date: "31/12/2018"
test_start_date: "01/01/2019"
test_end_date: "31/12/2020"
dynamic_inputs: [Rainf, Tair]
target_variables: [qobs_mm_per_hour]
static_attributes: [elev_mean, slope_mean]
use_frequencies: [1D, 1h]
seq_length: {1D: 30, 1h: 336}
predict_last_n: {1D: 1, 1h: 24}
epochs: 3
batch_size: 32
optimizer: Adam
loss: MSE
learning_rate: {0: 1e-3}
clip_gradient_norm: 1
validate_every: 1
validate_n_random_basins: 10
save_weights_every: 1
log_interval: 5
log_tensorboard: true
metrics: [NSE, KGE, Alpha-NSE, Beta-NSE]
num_workers: 0
seed: 111
device: cpu
run_dir: results/41_mts_mamba_global_transfer
# --- Model: MTS-Mamba ---
model: mtsmamba
head: regression
output_activation: linear
hidden_size: 32
output_dropout: 0.4
transfer_mtsmamba_states: linear
mamba_d_state: 16
mamba_d_conv: 4
mamba_expand: 2
mamba_n_layers: 2
```

**Step 4: 验证配置与 dataset 联动**

```bash
python -c "
from neuralhydrology.utils.config import Config
c = Config('src/mts_mamba_global_transfer/configs/phase2_mtslstm_camelsh_10b_ep3.yml')
print('dataset:', c.dataset, '| model:', c.model)
c2 = Config('src/mts_mamba_global_transfer/configs/phase2_mtsmamba_camelsh_10b_ep3.yml')
print('dataset:', c2.dataset, '| model:', c2.model)
"
```

Expected: `dataset: hourly_camelsh | model: mtslstm` 和 `dataset: hourly_camelsh | model: mtsmamba`

**Step 5: Commit**

```bash
git add src/mts_mamba_global_transfer/data/phase2_camelsh_10basins.txt \
        src/mts_mamba_global_transfer/configs/phase2_mtslstm_camelsh_10b_ep3.yml \
        src/mts_mamba_global_transfer/configs/phase2_mtsmamba_camelsh_10b_ep3.yml
git commit -m "feat(41): add Phase 2 basin list and configs for CAMELS-H comparison"
```

---

### Task 10: 运行 Phase 2 训练与评估

**Step 1: 运行 MTS-LSTM Phase 2**

```bash
python -m neuralhydrology.nh_run train \
    --config-file src/mts_mamba_global_transfer/configs/phase2_mtslstm_camelsh_10b_ep3.yml \
    --gpu -1

python -m neuralhydrology.nh_run evaluate \
    --run-dir results/41_mts_mamba_global_transfer/41_phase2_mtslstm_camelsh_10b_ep3_<timestamp> \
    --period test --epoch 3
```

**Step 2: 运行 MTS-Mamba Phase 2**

```bash
python -m neuralhydrology.nh_run train \
    --config-file src/mts_mamba_global_transfer/configs/phase2_mtsmamba_camelsh_10b_ep3.yml \
    --gpu -1

python -m neuralhydrology.nh_run evaluate \
    --run-dir results/41_mts_mamba_global_transfer/41_phase2_mtsmamba_camelsh_10b_ep3_<timestamp> \
    --period test --epoch 3
```

---

### Task 11: Phase 2 结果提取与文档更新

**Step 1: 运行对比脚本**

```bash
python src/mts_mamba_global_transfer/scripts/compare_phase0.py \
    --lstm-dir results/41_mts_mamba_global_transfer/41_phase2_mtslstm_camelsh_10b_ep3_<timestamp> \
    --mamba-dir results/41_mts_mamba_global_transfer/41_phase2_mtsmamba_camelsh_10b_ep3_<timestamp>
```

**Step 2: 更新 `draft/ideas/41_mts_mamba_global_transfer.md`**

Results Index 添加两条 Phase 2 记录；Progress Log 添加 Phase 2 条目；更新 Phase 1 checklist。

**Step 3: Commit**

```bash
git add draft/ideas/41_mts_mamba_global_transfer.md
git commit -m "feat(41): complete Phase 2 CAMELS-H 10-basin comparison"
```

---

## Phase 3: HPC 全量规模实验

> **前提条件：** Phase 2 通过（NSE ratio >= 0.95，指标稳定）。

**不需要新建配置**——复用 / 更新现有 HPC 配置：
- `src/mts_mamba_global_transfer/configs/caravan_daily_basemodel_hpc.yml`（全局日尺度预训练）
- `src/mts_mamba_global_transfer/hpc/submit_caravan_global.slurm`

**操作步骤（参考 `draft/ideas/41_mts_mamba_global_transfer.md` 当前执行入口）：**
```bash
sed -i 's/\r$//' src/mts_mamba_global_transfer/hpc/*.slurm
sbatch src/mts_mamba_global_transfer/hpc/submit_caravan_global.slurm
```

---

## 故障排除

### 训练 OOM

将 `batch_size` 从 32 降到 16，或将 `seq_length.1h` 从 336 降到 168。

### Mamba 后端缺失

```bash
pip install transformers
```

### NaN predictions

检查 hourly NetCDF 数据完整性：
```python
import xarray as xr
ds = xr.open_dataset("test/test_data/camels_us/hourly/usgs-streamflow-nldas_hourly.nc")
print(ds["qobs_mm_per_hour"].isnull().sum().values)
```

### MTS-Mamba 大幅落后 baseline

1. 检查 context token 是否正确传递（加断点 `mtsmamba.py:246`）
2. 尝试 `hidden_size: 64` 增加模型容量
3. 尝试 `transfer_mtsmamba_states: identity` 排除投影层问题

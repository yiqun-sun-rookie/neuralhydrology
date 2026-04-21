# Nam Ou 库尾站 DL 干净重训练 L15 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用最新 SSOT 数据在单流域库尾站上训一个 DL 模型（CudaLSTM），test 集 NSE 超过 XAJ 基线 0.562，且全面避开 `DL_RETRAIN_PITFALLS.md` 列出的 14 条坑。

**Architecture:** 以 `laos_forecast/data/03_final/namou_kuwei/` SSOT 为唯一数据源，通过参数化的 `build_hybrid_dataset.py` 生成含累积降雨/API/mask 的 nc，用降容量 CudaLSTM + MSE loss 训练，以 smoke gate 防止 loss 崩溃，以 2023 分段评估（全站齐 vs 缺 mengwu）反映真实鲁棒性。

**Tech Stack:** neuralhydrology 1.12 + pandas/xarray + PyTorch 2.x (CPU)，复用 laos `dl_models` 推理栈。

---

## Split 决策（已敲定，不在任务内再讨论）

| 阶段 | 时段 | 小时数 | 说明 |
|---|---|---|---|
| train | 2020-01-01 → 2021-12-31 | 17544 | 2 年，xls 数据，4 站完整，避开 2018/2021 接缝和 2022 低估 |
| val | 2023-01-01 → 2023-06-30 | 4344 | 半年，含 mengwu 缺测 → 早停选对缺测鲁棒的 checkpoint |
| test | 2023-07-01 → 2023-12-31 | 4416 | 半年，含 mengwu 缺测 + 2023 汛期 |
| 明确排除 | 2022 全年、2024 全年 | — | 2022 P/Q 比异常；2024 流量录入错误 |

**Caveat（必须承认）**：训练集无丰水年（P1#7 部分未避开 —— 数据质量硬约束）。如果 test NSE 显著低于 XAJ，Stage 7 会尝试引入 2022 with rain ×2（启发式修正）或切换到 P+Q 自回归。

## 架构决策（已敲定）

- **不改 nh 核心**（`neuralhydrology/` 包不动）
- **数据构建脚本住在 `laos_forecast/basins/namou_kuwei/dl/scripts/`**（承接 L14 位置）
- **Configs 住在 `laos_forecast/basins/namou_kuwei/dl/configs/no_leak/15_clean_retrain/`**
- **nc 输出到 `laos_forecast/data/nh_datasets/namou_kuwei/hourly_clean_v15/`**（独立于 L14 避免串）
- **Run dir 留在 `laos_forecast/basins/namou_kuwei/dl/results/L15_*`**（L14 相同约定）
- **路径策略**：config 里 `data_dir` / `train_basin_file` 等**全部用绝对路径**（L14 的相对路径在 2026-04-17 data migration 后已错位 — _data_migration_backup_20260417 为证），避免 CWD 歧义。运行 nh 从任意 CWD 都应能工作。

## File Structure

### 新建文件

| 路径 | 职责 |
|---|---|
| `laos_forecast/basins/namou_kuwei/dl/scripts/build_hybrid_dataset_v15.py` | L15 数据构建，CLI 参数化 + 累积特征 + API + 数据源标记 |
| `laos_forecast/basins/namou_kuwei/dl/scripts/verify_nc_v15.py` | 6 项 sanity check，失败直接 exit 1 |
| `laos_forecast/basins/namou_kuwei/dl/configs/no_leak/15_clean_retrain/_common.yml` | 参考块（不直接加载） |
| `laos_forecast/basins/namou_kuwei/dl/configs/no_leak/15_clean_retrain/L15_smoke_CudaLSTM_LT1h.yml` | 10 epoch smoke |
| `laos_forecast/basins/namou_kuwei/dl/configs/no_leak/15_clean_retrain/L15_CudaLSTM_LT1h.yml` | 50 epoch 正式训练 |
| `laos_forecast/basins/namou_kuwei/dl/scripts/report_segmented_test.py` | 按 mengwu 可用性分段出报告 |
| `laos_forecast/basins/namou_kuwei/dl/docs/L15_TRAIN_REPORT.md` | 结果归档 |

### 修改文件

- 无（L14 保留为参照）

---

## Task 1: 核实 SSOT 数据修正状态（避坑 P1#5）

**目标**：写进 `DL_RETRAIN_PITFALLS.md` 之外的单独核查记录，避免后续 stage 因"不知 rain 修不修正"反复纠结。

**Files:**
- Create: `laos_forecast/basins/namou_kuwei/dl/docs/SSOT_VERIFICATION_2026_04_19.md`
- Read-only reference: `laos_forecast/data/03_final/namou_kuwei/rain.csv`, `grid_hybrid.csv`
- Read-only reference: `forecast_system_lite/basins/namou_kuwei/scripts/generate_hybrid_inputs.py`

- [ ] **Step 1: 抽样核对 rain.csv 数值是否已修正**

运行：

```bash
python -c "
import pandas as pd
r = pd.read_csv('G:/github/pycharm/projects/laos_forecast/data/03_final/namou_kuwei/rain.csv', parse_dates=['time'])
print('Rain max per station (mm/h):')
print(r[['mengwu','banteng','aka','kuwei_rain']].max())
print('Annual totals (mm):')
for y in [2020, 2021, 2022, 2023]:
    row = r[r['time'].dt.year == y][['mengwu','banteng','aka','kuwei_rain','upstream_mean']].sum()
    print(f'  {y}: mengwu={row[\"mengwu\"]:.0f} banteng={row[\"banteng\"]:.0f} aka={row[\"aka\"]:.0f} kuwei={row[\"kuwei_rain\"]:.0f} upstream_mean={row[\"upstream_mean\"]:.0f}')
"
```

预期（基于先前抽查）：各站 max 在 51~71 mm/h 之间（raw gauge 量级）；2022 年降雨总量与 2021 相近但 2022 年流量 2× 2021。

- [ ] **Step 2: 查 SSOT 生成脚本是否隐式修正**

Grep `laos_forecast/data/03_final/` 的构造来源。在 `forecast_system_lite/src/data/rain_qc.py` 和相关 generator 里找 `* 1.39` / `* 1.26` / `correction_factor`：

```bash
grep -rn "correction\|1\.39\|1\.26\|\\*\s*10\\b" G:/github/pycharm/projects/forecast_system_lite/src/data/ G:/github/pycharm/projects/laos_forecast/src/ 2>&1 | grep -v pycache
```

预期：`rain_qc.py:149` 只有一个 `pct = n_unreliable / n_total * 100`（不是修正），所以 **rain 未在 SSOT 层修正**。

- [ ] **Step 3: 核对 pet_g0 是否已 × 10**

```bash
python -c "
import pandas as pd
g = pd.read_csv('G:/github/pycharm/projects/laos_forecast/data/03_final/namou_kuwei/grid_hybrid.csv', parse_dates=['time'])
print('pet_g0 stats:')
print(g['pet_g0'].describe())
print('pet_g0 max per year:')
for y in [2020, 2021, 2022, 2023]:
    print(f'  {y}: max={g[g[\"time\"].dt.year == y][\"pet_g0\"].max():.3f}')
"
```

预期：max ≈ 0.8 mm/h，说明 ×10 已应用（不是 0.08 或 8）。

- [ ] **Step 4: 写核查报告**

Create `laos_forecast/basins/namou_kuwei/dl/docs/SSOT_VERIFICATION_2026_04_19.md` 内容：

```markdown
# SSOT 数据修正状态核查

核查日期: 2026-04-19
核查范围: laos_forecast/data/03_final/namou_kuwei/

## 结论

| 字段 | 来源 | 当前修正状态 | L15 决策 |
|---|---|---|---|
| rain.csv 4 站 | gauge (xls) | 未修正（raw） | L15 按 raw 训练，不加 ×1.39 |
| grid_hybrid.csv rain_g0 | gauge 面平均 | 同 rain.csv | 不在 L15 dynamic_inputs |
| grid_hybrid.csv pet_g0 | ERA5 × 10 | 已修正 | L15 直接使用 |
| grid_hybrid.csv temp_g0 | ERA5 | 无修正需求 | L15 直接使用 |
| discharge.csv | xls/xlsm 处理 | 时间对齐修正 | 2024 整年不用 |

## 年际 P/Q 比异常（L15 排除 2022 的理由）

| 年 | upstream_mean 总降雨 | 年均流量 | P/Q 比 |
|---|---|---|---|
| 2020 | [填实测] | 21.5 | - |
| 2021 | [填实测] | 23.3 | - |
| 2022 | [填实测] | 52.1 | **异常低**（降雨与 2021 相近但流量 2×） |
| 2023 | [填实测] | 14.8 | - |

2022 数据 **L15 全部排除**：既不训练也不评估。

## L15 不做的事

- 不在 DL 训练层做 rain/PET 修正
- 不改 SSOT CSV
- 不混用 fsl/grid_meteo_pet_hourly_gauge_corrected.csv（那是 XAJ 训练用的，含 ×1.39）
```

把实测数据填进去。

- [ ] **Step 5: Commit**

```bash
cd G:/github/pycharm/projects/laos_forecast
git add basins/namou_kuwei/dl/docs/SSOT_VERIFICATION_2026_04_19.md
git commit -m "docs(kuwei-l15): verify SSOT correction status before retrain"
```

---

## Task 2: 写 L15 数据构建脚本（避坑 P0#1, P1#6, P2#9, P2#14）

**Files:**
- Create: `laos_forecast/basins/namou_kuwei/dl/scripts/build_hybrid_dataset_v15.py`

**设计要点**：
- CLI 参数化（`--src`, `--dst`, `--period-start`, `--period-end`）
- 明确 NaN → 0 + mask 的处理（继承 L14 方案 B）
- 新增累积降雨、API、qobs_prev（自回归）
- 加 `data_source` 列标记（即使本次 2020-2023 都是 xls，也留接口）
- stdout 打印完整 diagnostic（行数、NaN、累积特征统计）

- [ ] **Step 1: 写脚本骨架**

```python
"""L15 clean retrain 数据构建器。

Source: laos_forecast/data/03_final/namou_kuwei/ SSOT
Produces: 单-basin nc, 含 4 站 p_ + m_ + 累积 rain + API + qobs_prev。

避开坑:
- P0#1 silent imputation: NaN 显式保留 + mask
- P1#6 信号弱: sum6/12/24/48h + api_k95
- P2#9 路径硬编码: 全部 CLI 参数
- P2#14 数据接缝: data_source 列
"""
import argparse
from pathlib import Path

import numpy as np
import pandas as pd
import xarray as xr

RAIN_COLS = ['aka', 'banteng', 'mengwu', 'kuwei_rain']
ACCUM_WINDOWS = [6, 12, 24, 48]


def parse_args():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--src', type=Path, required=True,
                   help='SSOT dir, e.g. laos_forecast/data/03_final/namou_kuwei')
    p.add_argument('--dst', type=Path, required=True,
                   help='nc output dir, e.g. laos_forecast/data/nh_datasets/namou_kuwei/hourly_clean_v15')
    p.add_argument('--period-start', default='2020-01-01 00:00:00')
    p.add_argument('--period-end',   default='2023-12-31 23:00:00')
    p.add_argument('--api-k', type=float, default=0.95, help='API decay factor k')
    return p.parse_args()


def build_api_k95(rain_series, k=0.95):
    """API[t] = k * API[t-1] + rain[t]. Init API[0] = rain[0]."""
    api = np.zeros(len(rain_series), dtype=np.float32)
    r = rain_series.fillna(0).to_numpy(dtype=np.float32)
    api[0] = r[0]
    for i in range(1, len(r)):
        api[i] = k * api[i - 1] + r[i]
    return pd.Series(api, index=rain_series.index, dtype=np.float32)


def main():
    args = parse_args()
    q = pd.read_csv(args.src / 'discharge.csv', parse_dates=['time']).set_index('time')
    r = pd.read_csv(args.src / 'rain.csv', parse_dates=['time']).set_index('time')
    g = pd.read_csv(args.src / 'grid_hybrid.csv', parse_dates=['time']).set_index('time')

    idx = pd.date_range(args.period_start, args.period_end, freq='h')
    r = r.reindex(idx)
    q = q.reindex(idx)
    g = g.reindex(idx)

    df = pd.DataFrame(index=idx)
    df.index.name = 'date'

    # 4 站 per-station rain + mask (避坑 P0#1)
    for s in RAIN_COLS:
        mask = r[s].notna().astype(np.int8)
        df[f'p_{s}'] = r[s].fillna(0.0).astype(np.float32)
        df[f'm_{s}'] = mask

    n_avail = sum(df[f'm_{s}'] for s in RAIN_COLS)
    df['n_avail_norm'] = (n_avail / 4.0).astype(np.float32)

    # 累积降雨 (避坑 P1#6), 基于 upstream_mean
    u = r['upstream_mean'].fillna(0.0).astype(np.float32)
    for w in ACCUM_WINDOWS:
        df[f'rain_sum{w}h'] = u.rolling(w, min_periods=1).sum().astype(np.float32)

    # API (避坑 P1#6)
    df['api_k95'] = build_api_k95(u, k=args.api_k).astype(np.float32)

    # 气象
    df['rain_g0'] = g['rain_g0'].astype(np.float32)
    df['temp_g0'] = g['temp_g0'].astype(np.float32)
    df['pet_g0'] = g['pet_g0'].astype(np.float32)

    # 流量 + 自回归项
    df['qobs'] = q['q_obs'].astype(np.float32)
    df['qobs_prev'] = df['qobs'].shift(1).astype(np.float32)  # t-1 的流量

    # Lead-time 预留
    for lt in (6, 12, 24):
        df[f'qobs_lead{lt}'] = df['qobs'].shift(-lt).astype(np.float32)

    # 数据源标记 (避坑 P2#14)
    yr = pd.Series(idx.year, index=idx)
    df['data_source'] = np.where(yr <= 2019, 0, 1).astype(np.int8)  # 0=xlsx 1=xls

    # 打印诊断
    print(f'=' * 60)
    print(f'L15 hybrid_clean dataset: {args.period_start} → {args.period_end}')
    print(f'=' * 60)
    print(f'Total rows: {len(df)}')
    print(f'qobs NaN   : {df["qobs"].isna().sum()}')
    print(f'rain_g0 NaN: {df["rain_g0"].isna().sum()}')
    print(f'pet_g0 NaN : {df["pet_g0"].isna().sum()}')
    print()
    print('Per-station availability:')
    for s in RAIN_COLS:
        m = df[f'm_{s}']
        print(f'  m_{s:11s} = 1 : {int(m.sum()):6d}h  ({m.mean() * 100:.2f}%)')
    print()
    print('n_avail_norm distribution:')
    vc = df['n_avail_norm'].round(2).value_counts().sort_index()
    for k, v in vc.items():
        print(f'  n_avail={k:.2f}: {v:6d}h')
    print()
    print('Rain cumulative stats (upstream_mean based):')
    for w in ACCUM_WINDOWS:
        col = f'rain_sum{w}h'
        print(f'  {col}: mean={df[col].mean():.3f}  max={df[col].max():.2f}')
    print(f'  api_k95       : mean={df["api_k95"].mean():.3f}  max={df["api_k95"].max():.2f}')

    # 保存
    ts_dir = args.dst / 'time_series'
    ts_dir.mkdir(parents=True, exist_ok=True)
    ds = df.to_xarray()
    out_nc = ts_dir / 'namou_kuwei.nc'
    ds.to_netcdf(out_nc)
    print(f'\nWrote: {out_nc}')

    # basin files
    args.dst.joinpath('basins.txt').write_text('namou_kuwei\n')
    args.dst.joinpath('train_basins.txt').write_text('namou_kuwei\n')
    args.dst.joinpath('validation_basins.txt').write_text('namou_kuwei\n')
    args.dst.joinpath('test_basins.txt').write_text('namou_kuwei\n')

    # attributes (空占位)
    attr_dir = args.dst / 'attributes'
    attr_dir.mkdir(exist_ok=True)
    pd.DataFrame({'gauge_id': ['namou_kuwei'], 'area_km2': [1796.46]}).to_csv(
        attr_dir / 'attributes.csv', index=False)

    print('Done.')


if __name__ == '__main__':
    main()
```

- [ ] **Step 2: 跑脚本，观察 stdout**

```bash
cd G:/github/pycharm/projects/laos_forecast
python basins/namou_kuwei/dl/scripts/build_hybrid_dataset_v15.py \
    --src data/03_final/namou_kuwei \
    --dst data/nh_datasets/namou_kuwei/hourly_clean_v15 \
    --period-start "2020-01-01 00:00:00" \
    --period-end   "2023-12-31 23:00:00"
```

预期 stdout（关键行）：

```
Total rows: 35064
qobs NaN   : 0 (或小量)
m_mengwu = 1 : 约 26304h 左右（缺 2023）
m_aka, m_banteng, m_kuwei_rain = 1 : ≈ 35000h
n_avail=1.00: ≈ 26000h
n_avail=0.75: ≈ 8000h
rain_sum24h mean: 3.5~5 max: 100+
api_k95 mean: 3~5 max: 100+
```

- [ ] **Step 3: Commit**

```bash
cd G:/github/pycharm/projects/laos_forecast
git add basins/namou_kuwei/dl/scripts/build_hybrid_dataset_v15.py
git commit -m "feat(kuwei-l15): add clean dataset builder with accumulated rain + API"
```

---

## Task 3: 写数据 sanity check 脚本（避坑 P0#1 验证）

**Files:**
- Create: `laos_forecast/basins/namou_kuwei/dl/scripts/verify_nc_v15.py`

**设计要点**：6 项检查，任一失败 `sys.exit(1)`。防止"silent 错误数据进入训练"复现 L13 翻车。

- [ ] **Step 1: 写检查脚本**

```python
"""L15 nc 数据 6 项 sanity check。任一失败退出非零。"""
import sys
from pathlib import Path

import numpy as np
import pandas as pd
import xarray as xr

NC_PATH = Path('G:/github/pycharm/projects/laos_forecast/data/nh_datasets/namou_kuwei/hourly_clean_v15/time_series/namou_kuwei.nc')
SSOT_RAIN = Path('G:/github/pycharm/projects/laos_forecast/data/03_final/namou_kuwei/rain.csv')


def main():
    assert NC_PATH.exists(), f'nc not found: {NC_PATH}'
    ds = xr.open_dataset(NC_PATH)
    df = ds.to_dataframe()
    ssot_r = pd.read_csv(SSOT_RAIN, parse_dates=['time']).set_index('time')
    failed = []

    # Check 1: 总行数 = 35064 ± 允许 ±24
    n = len(df)
    if not (35000 <= n <= 35100):
        failed.append(f'Row count {n} out of [35000, 35100]')

    # Check 2: 没有 silent imputation — p_mengwu 2023 应该全部 NaN / 或 m_mengwu=0
    df_2023 = df.loc['2023']
    mengwu_2023_avail = df_2023['m_mengwu'].sum()
    if mengwu_2023_avail > 100:  # 允许极少部分可用
        failed.append(f'p_mengwu 2023 has {mengwu_2023_avail}h availability — expected ~0 per DATA_AUDIT')

    # Check 3: p_mengwu != mean(p_aka, p_banteng, p_kuwei_rain) — 防止旧 CSV 污染再现
    non_nan = (df['m_mengwu'] == 1) & (df['m_aka'] == 1) & (df['m_banteng'] == 1) & (df['m_kuwei_rain'] == 1)
    if non_nan.sum() > 100:
        sub = df.loc[non_nan, ['p_mengwu', 'p_aka', 'p_banteng', 'p_kuwei_rain']]
        mean3 = sub[['p_aka', 'p_banteng', 'p_kuwei_rain']].mean(axis=1)
        match_rate = np.isclose(sub['p_mengwu'], mean3, atol=0.01).mean()
        if match_rate > 0.5:
            failed.append(f'p_mengwu ~= mean(others) in {match_rate * 100:.1f}% rows — silent imputation suspected!')

    # Check 4: SSOT rain 值与 nc 严格对齐（随机抽 100 行）
    sample_idx = df.index[::350][:100]
    for t in sample_idx:
        for s in ['aka', 'banteng', 'mengwu', 'kuwei_rain']:
            ssot_val = ssot_r.loc[t, s] if t in ssot_r.index else np.nan
            nc_val_raw = df.loc[t, f'p_{s}']
            nc_mask = df.loc[t, f'm_{s}']
            if pd.isna(ssot_val):
                if nc_mask != 0 or nc_val_raw != 0:
                    failed.append(f'SSOT NaN at {t} {s} but nc has p={nc_val_raw}, mask={nc_mask}')
                    break
            else:
                if not np.isclose(nc_val_raw, ssot_val, atol=0.01):
                    failed.append(f'SSOT {ssot_val} != nc {nc_val_raw} at {t} {s}')
                    break

    # Check 5: 累积特征单调性 —— sum48h >= sum24h >= sum12h >= sum6h 对每一行
    bad = ((df['rain_sum48h'] < df['rain_sum24h'] - 1e-3) |
           (df['rain_sum24h'] < df['rain_sum12h'] - 1e-3) |
           (df['rain_sum12h'] < df['rain_sum6h'] - 1e-3))
    if bad.sum() > 0:
        failed.append(f'Cumulative rain monotonicity violated in {bad.sum()} rows')

    # Check 6: qobs 排除 2024（应该 0 行 2024）
    if (df.index.year == 2024).sum() > 0:
        failed.append(f'Found {(df.index.year == 2024).sum()} rows in 2024 — expected 0')

    if failed:
        print('SANITY CHECK FAILED:')
        for f in failed:
            print(f'  ❌ {f}')
        sys.exit(1)

    print('✅ All 6 sanity checks passed')
    print(f'   rows={n}, mengwu_2023_avail={mengwu_2023_avail}h, ssot_samples=100 OK')


if __name__ == '__main__':
    main()
```

- [ ] **Step 2: 运行验证**

```bash
cd G:/github/pycharm/projects/laos_forecast
python basins/namou_kuwei/dl/scripts/verify_nc_v15.py
```

预期：打印 `✅ All 6 sanity checks passed`，exit 0。

- [ ] **Step 3: Commit**

```bash
cd G:/github/pycharm/projects/laos_forecast
git add basins/namou_kuwei/dl/scripts/verify_nc_v15.py
git commit -m "feat(kuwei-l15): add 6-check sanity verifier for clean nc"
```

---

## Task 4: 写 L15 smoke config（避坑 P0#4, P2#10）

**Files:**
- Create: `laos_forecast/basins/namou_kuwei/dl/configs/no_leak/15_clean_retrain/_common.yml`
- Create: `laos_forecast/basins/namou_kuwei/dl/configs/no_leak/15_clean_retrain/L15_smoke_CudaLSTM_LT1h.yml`

**关键设计**：
- `hidden_size: 64`（L14 是 128 — 避坑 P0#4）
- `seq_length: 96`（L14 是 168 — 避坑 P0#4）
- `loss: MSE`（L14 是 NSE — 单 basin NSE 容易崩，避坑 P0#4）
- `output_dropout: 0.4`（L14 无 dropout — 避坑 P0#4）
- `log_tensorboard: false, log_n_figures: 0`（避坑 P2#10）
- `epochs: 10`（smoke）
- dynamic_inputs 含累积特征和 API（避坑 P1#6），**不含 qobs_prev**（smoke 只验通路）

- [ ] **Step 1: 写 _common.yml 参考块**

```yaml
# L15 Clean Retrain — 参考配置块（不直接加载）
#
# 数据: laos_forecast/data/nh_datasets/namou_kuwei/hourly_clean_v15
# Split (2026-04-19 敲定):
#   Train 2020-01-01 .. 2021-12-31   (2 yr, clean xls, 4 stations)
#   Valid 2023-01-01 .. 2023-06-30   (6 mo, mengwu NaN stress)
#   Test  2023-07-01 .. 2023-12-31   (6 mo, mengwu NaN stress + wet season)
#   Excluded: 2022 (P/Q 异常), 2024 (录入错误)
#
# 避坑清单:
#   P0#1 silent imputation → 用 v15 nc（已校验）
#   P0#2 2024 录入错误    → split 不含 2024
#   P0#3 2022 放 val 是反的 → 2022 不在任何集
#   P0#4 CudaLSTM 崩溃    → h=64, seq=96, loss=MSE, dropout=0.4
#   P1#6 信号太弱         → 加 rain_sum{6,12,24,48}h + api_k95
#   P1#7 无丰水年训练     → 已知 caveat，Stage 7 决定是否引入 2022
#   P1#8 2023 mengwu     → Stage 6 分段报告
#   P2#9 路径硬编码       → builder CLI 参数化
#   P2#10 CPU segfault   → log_tensorboard=false, log_n_figures=0
#
# Caveat: train 无丰水年，若 test NSE 过低 → Stage 7 扩展训练
```

- [ ] **Step 2: 写 smoke config**

```yaml
# L15 Smoke — 10 ep CudaLSTM LT1h 通路验证
experiment_name: L15_smoke_CudaLSTM_LT1h

run_dir: G:/github/pycharm/projects/laos_forecast/basins/namou_kuwei/dl/results/L15_smoke_CudaLSTM_LT1h

# data (全部绝对路径, 避免 CWD 问题)
dataset: generic
data_dir: G:/github/pycharm/projects/laos_forecast/data/nh_datasets/namou_kuwei/hourly_clean_v15
train_basin_file: G:/github/pycharm/projects/laos_forecast/data/nh_datasets/namou_kuwei/hourly_clean_v15/train_basins.txt
validation_basin_file: G:/github/pycharm/projects/laos_forecast/data/nh_datasets/namou_kuwei/hourly_clean_v15/validation_basins.txt
test_basin_file: G:/github/pycharm/projects/laos_forecast/data/nh_datasets/namou_kuwei/hourly_clean_v15/test_basins.txt
forcings:
  - generic

train_start_date: '01/01/2020'
train_end_date:   '31/12/2021'
validation_start_date: '01/01/2023'
validation_end_date:   '30/06/2023'
test_start_date: '01/07/2023'
test_end_date:   '31/12/2023'

# target
target_variables:
  - qobs

dynamic_inputs:
  - p_aka
  - p_banteng
  - p_mengwu
  - p_kuwei_rain
  - m_aka
  - m_banteng
  - m_mengwu
  - m_kuwei_rain
  - n_avail_norm
  - rain_sum6h
  - rain_sum12h
  - rain_sum24h
  - rain_sum48h
  - api_k95
  - temp_g0
  - pet_g0

# custom normalization — rain/mask keep zeros meaningful
custom_normalization:
  p_aka:         {centering: none, scaling: std}
  p_banteng:     {centering: none, scaling: std}
  p_mengwu:      {centering: none, scaling: std}
  p_kuwei_rain:  {centering: none, scaling: std}
  m_aka:         {centering: none, scaling: none}
  m_banteng:     {centering: none, scaling: none}
  m_mengwu:      {centering: none, scaling: none}
  m_kuwei_rain:  {centering: none, scaling: none}
  n_avail_norm:  {centering: none, scaling: none}
  rain_sum6h:    {centering: none, scaling: std}
  rain_sum12h:   {centering: none, scaling: std}
  rain_sum24h:   {centering: none, scaling: std}
  rain_sum48h:   {centering: none, scaling: std}
  api_k95:       {centering: none, scaling: std}
  temp_g0:       {centering: mean, scaling: std}
  pet_g0:        {centering: none, scaling: std}
  qobs:          {centering: none, scaling: std}

# model
model: cudalstm
head: regression
hidden_size: 64
seq_length: 96
initial_forget_bias: 3
output_dropout: 0.4

# training
epochs: 10
batch_size: 256
optimizer: Adam
loss: MSE
learning_rate:
  0: 0.001
  5: 0.0005
clip_gradient_norm: 1.0
predict_last_n: 1

validate_every: 2
save_weights_every: 5

metrics:
  - NSE
  - KGE
  - RMSE
  - Peak-MAPE

# device & logging
device: cpu
log_tensorboard: false
log_n_figures: 0
seed: 2025
```

- [ ] **Step 3: Commit**

```bash
cd G:/github/pycharm/projects/laos_forecast
git add basins/namou_kuwei/dl/configs/no_leak/15_clean_retrain/
git commit -m "feat(kuwei-l15): add smoke config with reduced capacity + MSE + dropout"
```

---

## Task 5: 跑 smoke（Gate: train loss 不崩、val NSE > 0.3）

**设计要点**：这是 L14 踩坑 P0#4 的复现关键判据。smoke 不过，不继续。

- [ ] **Step 1: 跑 smoke**

```bash
python -m neuralhydrology.nh_run train \
    --config-file G:/github/pycharm/projects/laos_forecast/basins/namou_kuwei/dl/configs/no_leak/15_clean_retrain/L15_smoke_CudaLSTM_LT1h.yml \
    --gpu -1
```

预计耗时：~5 分钟。

- [ ] **Step 2: 检查 output.log 的 loss 曲线**

```bash
RUN_DIR=$(ls -td G:/github/pycharm/projects/laos_forecast/basins/namou_kuwei/dl/results/L15_smoke_CudaLSTM_LT1h_* | head -1)
echo "Run dir: $RUN_DIR"
grep "Epoch.*average loss\|validation loss" "$RUN_DIR/output.log" | head -30
```

**Gate 条件（必须全部满足）**：

1. `avg_loss` 在 ep1 > 0.05（不是 0.000）
2. `avg_loss` 到 ep10 仍 > 0.001（没有指数崩塌）
3. 最好一次 `validation NSE > 0.3`

**如果 gate 失败**：

- loss 崩 0 → 试 batch_size=128, 或加 weight_decay 1e-4
- val NSE 长期 < 0 → 检查 Task 3 sanity 是否真通过；检查 dynamic_inputs 拼写
- val NSE 只在 ~0.1 → 降 `hidden_size=32` 再试

**不满足 gate 禁止进 Task 6**。

- [ ] **Step 3: 记录 smoke 结果到 L15_TRAIN_REPORT.md（新建）**

Create `laos_forecast/basins/namou_kuwei/dl/docs/L15_TRAIN_REPORT.md`：

```markdown
# L15 Clean Retrain 训练报告

## Smoke Run

- 日期: 2026-04-XX
- Run dir: results/04_namou_kuwei/L15_smoke_CudaLSTM_LT1h_<timestamp>
- 配置: h=64, seq=96, MSE loss, dropout=0.4, 10 ep
- Gate 状态: [✅ / ❌]
  - ep1 loss = X.XXX
  - ep10 loss = X.XXX  
  - best val NSE = X.XXX
- 结论: [通过 → 进 Task 6 / 未过 → 调整 Y 重试]
```

- [ ] **Step 4: Commit（仅 commit 报告，不 commit run_dir）**

```bash
cd G:/github/pycharm/projects/laos_forecast
git add basins/namou_kuwei/dl/docs/L15_TRAIN_REPORT.md
git commit -m "docs(kuwei-l15): smoke run report"
```

---

## Task 6: 写 L15 正式训练 config 并训练（避坑 P0#4 验证）

**前置条件**：Task 5 gate 通过。

**Files:**
- Create: `laos_forecast/basins/namou_kuwei/dl/configs/no_leak/15_clean_retrain/L15_CudaLSTM_LT1h.yml`

**与 smoke 差异**：
- `epochs: 50`
- LR schedule 三档：`{0: 1e-3, 20: 5e-4, 40: 1e-4}`
- `validate_every: 5`

- [ ] **Step 1: 写正式 config（复制 smoke 后改三项）**

```yaml
# L15 正式训练 — 50 ep CudaLSTM LT1h
experiment_name: L15_CudaLSTM_LT1h

run_dir: G:/github/pycharm/projects/laos_forecast/basins/namou_kuwei/dl/results/L15_CudaLSTM_LT1h

# === 数据/模型 section 完全同 smoke, 只改 epochs/LR schedule/validate_every ===

dataset: generic
data_dir: G:/github/pycharm/projects/laos_forecast/data/nh_datasets/namou_kuwei/hourly_clean_v15
train_basin_file: G:/github/pycharm/projects/laos_forecast/data/nh_datasets/namou_kuwei/hourly_clean_v15/train_basins.txt
validation_basin_file: G:/github/pycharm/projects/laos_forecast/data/nh_datasets/namou_kuwei/hourly_clean_v15/validation_basins.txt
test_basin_file: G:/github/pycharm/projects/laos_forecast/data/nh_datasets/namou_kuwei/hourly_clean_v15/test_basins.txt
forcings:
  - generic

train_start_date: '01/01/2020'
train_end_date:   '31/12/2021'
validation_start_date: '01/01/2023'
validation_end_date:   '30/06/2023'
test_start_date: '01/07/2023'
test_end_date:   '31/12/2023'

target_variables:
  - qobs

dynamic_inputs:
  - p_aka
  - p_banteng
  - p_mengwu
  - p_kuwei_rain
  - m_aka
  - m_banteng
  - m_mengwu
  - m_kuwei_rain
  - n_avail_norm
  - rain_sum6h
  - rain_sum12h
  - rain_sum24h
  - rain_sum48h
  - api_k95
  - temp_g0
  - pet_g0

custom_normalization:
  p_aka:         {centering: none, scaling: std}
  p_banteng:     {centering: none, scaling: std}
  p_mengwu:      {centering: none, scaling: std}
  p_kuwei_rain:  {centering: none, scaling: std}
  m_aka:         {centering: none, scaling: none}
  m_banteng:     {centering: none, scaling: none}
  m_mengwu:      {centering: none, scaling: none}
  m_kuwei_rain:  {centering: none, scaling: none}
  n_avail_norm:  {centering: none, scaling: none}
  rain_sum6h:    {centering: none, scaling: std}
  rain_sum12h:   {centering: none, scaling: std}
  rain_sum24h:   {centering: none, scaling: std}
  rain_sum48h:   {centering: none, scaling: std}
  api_k95:       {centering: none, scaling: std}
  temp_g0:       {centering: mean, scaling: std}
  pet_g0:        {centering: none, scaling: std}
  qobs:          {centering: none, scaling: std}

model: cudalstm
head: regression
hidden_size: 64
seq_length: 96
initial_forget_bias: 3
output_dropout: 0.4

# === 以下为正式训练差异 ===
epochs: 50
batch_size: 256
optimizer: Adam
loss: MSE
learning_rate:
  0: 0.001
  20: 0.0005
  40: 0.0001
clip_gradient_norm: 1.0
predict_last_n: 1

validate_every: 5
save_weights_every: 10

metrics:
  - NSE
  - KGE
  - RMSE
  - Peak-MAPE

device: cpu
log_tensorboard: false
log_n_figures: 0
seed: 2025
```

- [ ] **Step 2: 跑正式训练**

```bash
python -m neuralhydrology.nh_run train \
    --config-file G:/github/pycharm/projects/laos_forecast/basins/namou_kuwei/dl/configs/no_leak/15_clean_retrain/L15_CudaLSTM_LT1h.yml \
    --gpu -1
```

预计耗时：~25 分钟。

- [ ] **Step 3: 中途检查（训到 ep20 时 kill 进程不是目的，只是人工看曲线决定是否异常）**

```bash
RUN_DIR=$(ls -td G:/github/pycharm/projects/laos_forecast/basins/namou_kuwei/dl/results/L15_CudaLSTM_LT1h_* | head -1)
grep "Epoch.*average loss\|validation loss\|Setting learning rate" "$RUN_DIR/output.log"
```

**异常信号**（任一出现就 kill + 调整）：
- train loss 在 ep5~10 内已经 ≤ 1e-5 → 崩塌；降 hidden_size=32 或回到 seq_length=48
- val NSE 在 ep25 后连续 3 次 < 前次 → 过拟合；提前停

- [ ] **Step 4: 更新训练报告**

在 `L15_TRAIN_REPORT.md` 追加：

```markdown
## Full Training

- 日期: 2026-04-XX
- Run dir: results/04_namou_kuwei/L15_CudaLSTM_LT1h_<timestamp>
- 配置: h=64, seq=96, MSE, dropout=0.4, 50 ep
- 训练曲线（每 5 ep）:
  | Epoch | train_loss | val_NSE | val_KGE | val_RMSE |
  |-------|-----------|---------|---------|----------|
  | 5     | X.XXX     | X.XXX   | X.XXX   | X.XX     |
  | ...   |           |         |         |          |
- 最佳 val NSE: X.XXX (epoch Y)
- 结论: [达标 / 未达 → Stage 7 迭代]
```

- [ ] **Step 5: Commit**

```bash
cd G:/github/pycharm/projects/laos_forecast
git add basins/namou_kuwei/dl/configs/no_leak/15_clean_retrain/L15_CudaLSTM_LT1h.yml
git add basins/namou_kuwei/dl/docs/L15_TRAIN_REPORT.md
git commit -m "feat(kuwei-l15): 50ep training config + run report"
```

---

## Task 7: 评估 + 分段报告（避坑 P1#8）

**Files:**
- Create: `laos_forecast/basins/namou_kuwei/dl/scripts/report_segmented_test.py`

**设计要点**：2023 test 集里 mengwu 全年缺。把 test 结果按 `n_avail_norm` 分段：full(=1.0) vs partial(<1.0)。常规报告不该把二者混一起。

- [ ] **Step 1: 跑 nh evaluate（拿 best checkpoint）**

```bash
RUN_DIR=$(ls -td G:/github/pycharm/projects/laos_forecast/basins/namou_kuwei/dl/results/L15_CudaLSTM_LT1h_* | head -1)
python -m neuralhydrology.nh_run evaluate \
    --run-dir "$RUN_DIR" \
    --period test \
    --epoch 50 \
    --gpu -1
```

产物：`$RUN_DIR/test/model_epoch050/test_metrics.csv` + `test_results.p`

- [ ] **Step 2: 写分段报告脚本**

```python
"""按 mengwu 可用性分段报 test 指标。"""
import pickle
import sys
from pathlib import Path

import numpy as np
import pandas as pd
import xarray as xr


def nse(obs, sim):
    mask = ~(np.isnan(obs) | np.isnan(sim))
    o = obs[mask]; s = sim[mask]
    denom = np.sum((o - o.mean()) ** 2)
    return 1 - np.sum((o - s) ** 2) / denom if denom > 0 else np.nan


def kge(obs, sim):
    mask = ~(np.isnan(obs) | np.isnan(sim))
    o = obs[mask]; s = sim[mask]
    if len(o) < 2: return np.nan
    r = np.corrcoef(o, s)[0, 1]
    alpha = s.std() / o.std()
    beta = s.mean() / o.mean() if o.mean() != 0 else np.nan
    return 1 - np.sqrt((r - 1) ** 2 + (alpha - 1) ** 2 + (beta - 1) ** 2)


def rmse(obs, sim):
    mask = ~(np.isnan(obs) | np.isnan(sim))
    return np.sqrt(np.mean((obs[mask] - sim[mask]) ** 2))


def main(run_dir: Path, epoch: int = 50):
    results_p = run_dir / 'test' / f'model_epoch{epoch:03d}' / 'test_results.p'
    assert results_p.exists(), f'Missing: {results_p}'
    with open(results_p, 'rb') as f:
        res = pickle.load(f)

    basin_key = list(res.keys())[0]
    ds = res[basin_key]['1H']['xr']
    obs = ds['qobs_obs'].squeeze().to_numpy()
    sim = ds['qobs_sim'].squeeze().to_numpy()
    times = ds['date'].to_numpy()

    # 读 nc 拿 n_avail_norm
    nc = Path('G:/github/pycharm/projects/laos_forecast/data/nh_datasets/namou_kuwei/hourly_clean_v15/time_series/namou_kuwei.nc')
    src = xr.open_dataset(nc).to_dataframe()
    n_avail = src.loc[times, 'n_avail_norm'].to_numpy()

    full_mask = n_avail >= 0.99
    partial_mask = n_avail < 0.99

    rows = []
    for name, m in [('全部 test 集', np.ones_like(full_mask, dtype=bool)),
                    ('4 站齐全', full_mask),
                    ('至少缺 1 站', partial_mask)]:
        if m.sum() == 0:
            rows.append({'segment': name, 'n_hours': 0, 'NSE': np.nan,
                         'KGE': np.nan, 'RMSE': np.nan})
            continue
        o, s = obs[m], sim[m]
        rows.append({
            'segment': name,
            'n_hours': int(m.sum()),
            'NSE': round(nse(o, s), 4),
            'KGE': round(kge(o, s), 4),
            'RMSE': round(rmse(o, s), 3),
        })

    df = pd.DataFrame(rows)
    print(df.to_string(index=False))

    out = run_dir / 'test' / f'model_epoch{epoch:03d}' / 'segmented_metrics.csv'
    df.to_csv(out, index=False)
    print(f'\nSaved: {out}')


if __name__ == '__main__':
    run_dir = Path(sys.argv[1])
    epoch = int(sys.argv[2]) if len(sys.argv) > 2 else 50
    main(run_dir, epoch)
```

- [ ] **Step 3: 跑分段脚本**

```bash
RUN_DIR=$(ls -td G:/github/pycharm/projects/laos_forecast/basins/namou_kuwei/dl/results/L15_CudaLSTM_LT1h_* | head -1)
python G:/github/pycharm/projects/laos_forecast/basins/namou_kuwei/dl/scripts/report_segmented_test.py "$RUN_DIR" 50
```

预期输出：

```
      segment  n_hours     NSE     KGE   RMSE
 全部 test 集     4416  0.XXXX  0.XXXX  XX.XX
    4 站齐全        0  (缺 2023 mengwu 全年 NaN → 此行 NaN 可接受)
 至少缺 1 站     4416  0.XXXX  0.XXXX  XX.XX
```

（注：2023 全年 mengwu NaN → "4 站齐全"可能 0 行；这意味着 L15 test 整段都是"缺 mengwu"场景。这恰好暴露 P1#8 的设计意图。）

- [ ] **Step 4: 追加到 L15_TRAIN_REPORT.md**

```markdown
## Test 分段评估

| Segment | Hours | NSE | KGE | RMSE |
|---------|-------|-----|-----|------|
| 全部 test 集 | 4416 | X.XXX | X.XXX | XX.XX |
| 4 站齐全 | 0 | — | — | — |
| 至少缺 1 站 | 4416 | X.XXX | X.XXX | XX.XX |

**与 XAJ 基线对比**：
- XAJ smoke NSE = 0.562（同 basin 同架构验证）
- L15 NSE = X.XXX → [超过 / 持平 / 低于]

**结论**：[达标 → L15 冻结 / 低于 → Stage 8 迭代]
```

- [ ] **Step 5: Commit**

```bash
cd G:/github/pycharm/projects/laos_forecast
git add basins/namou_kuwei/dl/scripts/report_segmented_test.py
git add basins/namou_kuwei/dl/docs/L15_TRAIN_REPORT.md
git commit -m "feat(kuwei-l15): segmented test evaluation + final report"
```

---

## Task 8: 如 NSE 未达 XAJ 基线 → 迭代方案

**触发条件**：Task 7 test NSE < 0.562。

**迭代选项**（按代价从低到高尝试）：

- [ ] **方案 A: 引入 qobs_prev 自回归**
  - 在 config `dynamic_inputs` 加 `qobs_prev`
  - 注意：这会让模型变成"预测下一步"而非"预测"，NSE 会虚高，但对预报任务是合理的
  - 运行方式：复制 L15_CudaLSTM_LT1h.yml → L15_AR_CudaLSTM_LT1h.yml，加一行 `- qobs_prev`，重训
  - Gate: 测试 AR 基线 NSE > 0.9（如果 < 0.9 说明基本通路有问题）

- [ ] **方案 B: 应用 2022 rain ×2 启发式修正后再训**
  - 在 `build_hybrid_dataset_v15.py` 加 `--fix-2022-rain` flag
  - flag 开启时：`df.loc['2022', p_*列] *= 2.0`
  - 重跑 Task 2 → Task 3 → 新 config train 含 2022，val 放 2023 H1，test 放 2023 H2
  - 注意：这是启发式，需在报告里明示

- [ ] **方案 C: 换 EA-LSTM 或 GRU**
  - 复制 config，`model: ealstm` / `model: gru`
  - 其余保持一致，单纯模型架构对比
  - 通常 NSE 差 < 5% —— 不解决根本信号问题，只是备选

**禁止的事**：
- 不要瞎调 hidden_size / seq_length / LR —— 这些已按 pitfall 规则定好
- 不要在 DL 训练侧做 rain 修正 —— 在 SSOT 或 builder 里做

每个方案都要写成独立的训练报告子节（`## Iteration A`, `## Iteration B` 等），不替换原始 L15 记录。

---

## Task 9: 更新 MEMORY 和 Pitfalls 文档

**Files:**
- Modify: `laos_forecast/basins/namou_kuwei/dl/docs/DL_RETRAIN_PITFALLS.md`（加 L15 结果状态列）
- Modify: `C:\Users\yiqun\.claude\projects\G--github-pycharm-projects-neuralhydrology\memory\kuwei_dl_pitfalls.md`（加 L15 实际验证情况）

- [ ] **Step 1: 在 DL_RETRAIN_PITFALLS.md 加一列 "L15 实测"**

逐条把 L14_B 的状态列后面加一列，填"L15 验证通过/实测 NSE 贡献/caveat 确认"。

- [ ] **Step 2: 更新 memory**

在 `kuwei_dl_pitfalls.md` 的"14 条状态"表加 "L15 验证" 列。

- [ ] **Step 3: Commit**

```bash
cd G:/github/pycharm/projects/laos_forecast
git add basins/namou_kuwei/dl/docs/DL_RETRAIN_PITFALLS.md
git commit -m "docs(kuwei-l15): update pitfalls table with L15 verification results"
```

---

## Success Criteria

**硬指标（必须满足）**：
- [ ] Task 3 sanity check 6/6 通过
- [ ] Task 5 smoke gate 通过（loss 不崩, val NSE > 0.3）
- [ ] Task 6 正式训练完成 50 epochs 无异常
- [ ] Task 7 test NSE ≥ 0.3（低 bar，至少比 L14_B 的 0.006 高两个数量级）

**软指标（理想目标）**：
- [ ] Task 7 test NSE ≥ 0.562（超过 XAJ 基线）
- [ ] 14 条 pitfall 全部在 DL_RETRAIN_PITFALLS.md 标记 "L15 avoided"

**失败退出条件**：
- Task 5 gate 反复失败（3 次调参后仍崩）→ 不是调参问题，是建模假设错了，需停下重评估
- Task 7 NSE < 0 → 数据通路错，回 Task 3 重查

---

## 14 条 Pitfall × L15 映射

| # | Pitfall | Task |
|---|---|---|
| P0#1 | Silent imputation | Task 3 Check 2+3+4 显式验证 |
| P0#2 | 2024 录入错误 | Task 2 period_end=2023-12-31 |
| P0#3 | 2022 放 val 反 | 2022 完全排除 |
| P0#4 | CudaLSTM 崩溃 | Task 4 h=64/seq=96/MSE/dropout; Task 5 gate |
| P1#5 | PET 修正混乱 | Task 1 核查报告 |
| P1#6 | 信号太弱 | Task 2 加 sum6/12/24/48h + api_k95 |
| P1#7 | 年际偏移 | **Caveat** — 训练无丰水；Task 8 方案 B 兜底 |
| P1#8 | 2023 mengwu | Task 7 分段报告 |
| P2#9 | 路径硬编码 | Task 2 CLI 参数化 |
| P2#10 | CPU segfault | Task 4 log_tensorboard/figures=false |
| P2#11 | 11 站 xlsx 只 4 站 | 不在 L15 范围 |
| P2#12 | 站点坐标未文档化 | 不在 L15 范围 |
| P2#13 | Hargreaves PET | Task 1 确认用 ERA5×10 不走 Hargreaves |
| P2#14 | 数据接缝 | Task 2 data_source 列；本次全 xls 接缝问题天然规避 |

---

## 估时

- Task 1：~20 min（脚本 + 核查 + 报告）
- Task 2：~45 min（builder 写 + 跑 + 检查 stdout）
- Task 3：~30 min（sanity 脚本 + 跑）
- Task 4：~20 min（config 写）
- Task 5：~30 min（smoke 跑 ~5min + 分析 + 报告）
- Task 6：~45 min（train ~25min + 监控 + 报告）
- Task 7：~30 min（eval + 分段脚本 + 报告）
- Task 8：按需（A 方案 +30min, B +60min, C +30min）
- Task 9：~15 min

**总计**（无迭代）：~4.5 小时。单次迭代 +1 小时。

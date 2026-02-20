# 标准化工作流（流量预报）

> 目标：零泄露、可复现、可移植。适用�?Nam Ou Kuwei 以及后续站点�?

## 快速开始（新流域）

```bash
# 1. 扫描数据目录，自动创建站点模�?
python src/namou_kuwei/scripts/new_site.py --name my_basin --data-dir data/my_basin_hourly

# 2. 一条命令完成：生成配置 �?校验 �?训练 �?评估
python src/namou_kuwei/scripts/run_experiment.py quick --site my_basin --type ar --lead 1

# 3. 对比所有实验结�?
python src/namou_kuwei/scripts/run_experiment.py compare --results-dir results/04_namou_kuwei
```

---

## 详细步骤

### 1. 数据准备与检�?

- 输入格式：`time_series/<station>.csv`，包含时间戳、降�?p_xxx)、流�?qobs)
- 时间拆分示例：Train 2020.1-2021.6，Val 2021.7-2021.12，Test 2022全年（互斥）
- 归一化：降雨/流量�?`custom_normalization: {centering: none, scaling: std}` 保留零点
- 快速自检�?
  - 缺测/全零站点：排除或修复
  - 时间段重叠：禁止
  - 路径可用：data_dir、basin 文件存在

### 2. 配置文件

关键字段�?
- `dynamic_inputs`: 降雨站列表（绝不直接�?qobs�?
- `lagged_features`: `qobs: [N]` 生成 `qobs_shiftN`
- `autoregressive_inputs`: `[qobs_shiftN]`，N = 预报提前�?
- `target_variables`: `[qobs]`
- `predict_last_n`: 1 (Seq-to-One) �?24 (Seq-to-Seq)

### 3. 模型选择

| 场景 | model | 说明 |
|------|-------|------|
| AR 预报 | `arlstm` | 支持 autoregressive_inputs |
| 纯降�?| `cudalstm` | �?AR 输入 |
| Seq2Seq+AR | `arlstm` | AR滞后 >= predict_last_n |

### 4. 训练配置

统一超参：hidden_size=64, seq_length=168, batch_size=256, epochs=60, seed=2025

### 5. 工具命令

```bash
# 新建站点模板（自动扫描数据目录）
python src/namou_kuwei/scripts/new_site.py --name my_basin --data-dir data/my_basin_hourly

# 生成配置（可选，quick 命令会自动调用）
python src/namou_kuwei/scripts/gen_config.py --site my_basin --type ar --lead 1 --dry-run

# 校验配置（防泄露�?
python src/namou_kuwei/scripts/validate_config.py src/namou_kuwei/configs/generated/

# 一键训�?评估
python src/namou_kuwei/scripts/run_experiment.py quick --site my_basin --type ar --lead 1

# 单独训练
python src/namou_kuwei/scripts/run_experiment.py train --config <config.yml>

# 单独评估
python src/namou_kuwei/scripts/run_experiment.py evaluate --run-dir results/04_namou_kuwei/<run_dir>

# 对比结果
python src/namou_kuwei/scripts/run_experiment.py compare --results-dir results/04_namou_kuwei
```

### 6. 可复现性要�?

- 固定种子：`seed=2025`
- 保存：`model_epoch*.pt` + `config.yml` + `train_data_scaler.yml`
- 使用相同数据拆分�?`custom_normalization`
- 换机器需更新 `data_dir` 等路�?

---

## 已验证成功结果（对齐参考）

| 实验 | 类型 | NSE | 关键配置 |
|------|------|-----|----------|
| L3_Rain_AR_LT1h | Seq-to-One 1h | 0.975 | qobs_shift1, arlstm |
| L5_Rain_AR_LT24h | Seq-to-One 24h | 0.735 | qobs_shift24, arlstm |
| L6_Seq2Seq_AR24lag_24h | Seq-to-Seq 24h | 0.730 | qobs_shift24, predict_last_n=24 |

配置路径：`src/namou_kuwei/configs/no_leak/`


# 配置文件对比分析

## 📊 两个配置文件的区别

### `full_674_basins.yml` vs `full_training.yml`

| 配置项 | full_674_basins.yml | full_training.yml | 说明 |
|--------|---------------------|-------------------|------|
| **实验名称** | `full_674_basins` | `full_training_nse` | 不同的实验标识 |
| **生成时间** | 2025-09-28 18:32:30 | 2025-09-25 18:17:00 | full_674_basins更新 |

## 🏗️ 模型配置差异

| 配置项 | full_674_basins.yml | full_training.yml | 影响 |
|--------|---------------------|-------------------|------|
| **隐藏层大小** | `256` | `128` | full_674_basins模型更大 |
| **输出dropout** | `0.3` | `0.3` | 相同 |
| **初始遗忘偏置** | `3` | `3` | 相同 |

## 🎯 训练配置差异

| 配置项 | full_674_basins.yml | full_training.yml | 影响 |
|--------|---------------------|-------------------|------|
| **训练轮数** | `100` | `10` | full_674_basins训练更久 |
| **批次大小** | `128` | `256` | full_training批次更大 |
| **优化器** | `Adam` | `AdamW` | 不同优化器 |
| **损失函数** | `MSE` | `NSE` | 不同损失函数 |

## 📈 学习率调度差异

### full_674_basins.yml
```yaml
learning_rate:
  0: 0.0005    # 更保守的初始学习率
  15: 0.0003
  30: 0.0002
  40: 0.0001
```

### full_training.yml
```yaml
learning_rate:
  0: 0.003     # 更高的初始学习率
  10: 0.002
  25: 0.001
  40: 0.0005
```

## 📅 时间分割差异

### full_674_basins.yml
```yaml
# 较短的时间范围
train_start_date: 01/10/1999
train_end_date: 30/09/2008
validation_start_date: 01/10/2008
validation_end_date: 30/09/2011
test_start_date: 01/10/2011
test_end_date: 30/09/2014
```

### full_training.yml
```yaml
# 更长的时间范围，避免数据泄露
train_start_date: 01/10/1980    # 1980-1999 (20年)
train_end_date: 30/09/1999
validation_start_date: 01/10/2000  # 2000-2007 (8年)
validation_end_date: 30/09/2007
test_start_date: 01/10/2008     # 2008-2014 (7年)
test_end_date: 30/09/2014
```

## 🔧 训练参数差异

| 配置项 | full_674_basins.yml | full_training.yml | 说明 |
|--------|---------------------|-------------------|------|
| **验证频率** | `5` | `5` | 相同 |
| **验证流域数** | `10` | `50` | full_training验证更全面 |
| **梯度裁剪** | `0.5` | `1.0` | full_training更宽松 |
| **工作进程** | `8` | `0` | full_training适配Windows |

## 📊 输入特征差异

| 配置项 | full_674_basins.yml | full_training.yml | 说明 |
|--------|---------------------|-------------------|------|
| **数据源** | 仅 `daymet` | 仅 `daymet` | 相同 |
| **动态输入** | 5个特征 | 5个特征 | 相同特征 |

## 📝 日志和保存差异

| 配置项 | full_674_basins.yml | full_training.yml | 说明 |
|--------|---------------------|-------------------|------|
| **日志间隔** | `5` | `5` | 相同 |
| **保存频率** | `5` | `10` | full_training保存更少 |
| **可视化数量** | `1` | `5` | full_training可视化更多 |
| **详细程度** | 无 | `verbose: 1` | full_training更详细 |

## 🎯 评估指标差异

| 配置项 | full_674_basins.yml | full_training.yml | 说明 |
|--------|---------------------|-------------------|------|
| **评估指标** | NSE, KGE, Alpha-NSE | 仅 NSE | full_674_basins更全面 |

## 📁 数据文件路径差异

| 配置项 | full_674_basins.yml | full_training.yml | 说明 |
|--------|---------------------|-------------------|------|
| **数据文件路径** | `examples\01-Introduction\splits\` | `configs/data_splits/` | full_training路径已更新 |

## 🎯 使用建议

### 选择 `full_674_basins.yml` 当：
- ✅ 需要更全面的评估指标（NSE, KGE, Alpha-NSE）
- ✅ 想要更长的训练时间（100 epochs）
- ✅ 需要更大的模型容量（256 hidden units）
- ✅ 追求更稳定的训练（更保守的学习率）

### 选择 `full_training.yml` 当：
- ✅ 需要快速训练和验证（10 epochs）
- ✅ 使用NSE损失函数进行训练
- ✅ 需要更详细的控制台输出
- ✅ 在Windows环境下运行（num_workers=0）
- ✅ 需要避免数据泄露的时间分割
- ✅ 需要更全面的验证（50个随机流域）

## 🔄 主要差异总结

1. **训练策略**：
   - `full_674_basins.yml`: 长期训练，大模型，保守学习率
   - `full_training.yml`: 快速训练，适中模型，激进学习率

2. **时间分割**：
   - `full_674_basins.yml`: 较短时间范围，可能有数据泄露
   - `full_training.yml`: 长时间范围，避免数据泄露

3. **损失函数**：
   - `full_674_basins.yml`: MSE损失
   - `full_training.yml`: NSE损失

4. **系统兼容性**：
   - `full_674_basins.yml`: 通用配置
   - `full_training.yml`: Windows优化配置

## 💡 推荐使用

**推荐使用 `full_training.yml`**，因为：
1. ✅ 时间分割更合理，避免数据泄露
2. ✅ 使用NSE损失函数，更适合水文预测
3. ✅ Windows兼容性更好
4. ✅ 控制台输出更详细
5. ✅ 数据文件路径已更新
6. ✅ 验证更全面（50个随机流域）

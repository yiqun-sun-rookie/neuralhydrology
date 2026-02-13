# NeuralHydrology 训练文件命名规则详解

## 概述

NeuralHydrology使用特定的命名规则来组织训练运行和文件，了解这些规则有助于更好地管理训练过程。

## 训练运行目录命名规则

### 基本格式 (新版本)
```
{experiment_name}_{YYYY}_{MMDD}_{HHMM}_ep{epochs}/
```

### 示例分析
以 `test_run_mse_nse_optimized_2024_0924_1805_ep10` 为例：

- **experiment_name**: `test_run_mse_nse_optimized`
  - 来自配置文件中的 `experiment_name` 字段
  - 可以自定义，建议包含训练类型和参数信息
  
- **year**: `2024`
  - 格式：`YYYY` (4位年份)
  - 便于跨年管理训练
  
- **date**: `0924` 
  - 格式：`MMDD` (月日)
  - `09` = 9月
  - `24` = 24日
  
- **time**: `1805`
  - 格式：`HHMM` (时分，已去掉秒数)
  - `18` = 18时
  - `05` = 05分
  
- **epochs**: `ep10`
  - 格式：`ep{epochs}` (总epoch数)
  - 便于快速识别训练规模

### 完整示例 (新格式)
```
runs/
├── test_run_mse_nse_optimized_2024_0924_1805_ep10/     # 单流域MSE+NSE优化训练
├── full_training_674_basins_gpu_2024_0924_1517_ep50/   # 674流域GPU完整训练
├── test_run_3_basins_nse_2024_0918_2223_ep5/           # 3流域NSE测试训练
└── proper_split_demo_2024_0919_1308_ep20/              # 数据分割演示训练
```

### 旧格式对比
```
# 旧格式 (已弃用)
test_run_mse_nse_optimized_2409_180532

# 新格式 (推荐)
test_run_mse_nse_optimized_2024_0924_1805_ep10
```

## 文件命名规则

### 1. 模型检查点文件
```
model_epoch{epoch_number:03d}.pt
```

**示例：**
- `model_epoch001.pt` - 第1个epoch的模型
- `model_epoch010.pt` - 第10个epoch的模型
- `model_epoch100.pt` - 第100个epoch的模型

### 2. 优化器状态文件
```
optimizer_state_epoch{epoch_number:03d}.pt
```

**示例：**
- `optimizer_state_epoch001.pt` - 第1个epoch的优化器状态
- `optimizer_state_epoch010.pt` - 第10个epoch的优化器状态

### 3. 配置文件
```
config.yml
```
- 包含完整的训练配置参数
- 用于续跑和复现训练

### 4. 日志文件
```
output.log
```
- 训练过程的详细日志
- 包含损失、指标、学习率等信息

### 5. TensorBoard事件文件
```
events.out.tfevents.{timestamp}.{hostname}.{pid}.{suffix}
```

**示例：**
- `events.out.tfevents.1758708339.ys-9000k.32188.0`

### 6. 图像日志文件
```
img_log/
├── QObsmmd_freq1D_epoch1_1.png
├── QObsmmd_freq1D_epoch2_1.png
└── ...
```

**命名格式：**
```
{target_variable}_{frequency}_{epoch}_{basin_id}.png
```

## 训练状态判断

### 完成状态检查
通过比较模型文件数量和配置的epoch数来判断：

```python
# 检查训练是否完成
latest_epoch = max([int(f.stem.split('_')[-1].replace('epoch', '')) 
                   for f in model_files])
total_epochs = config.get('epochs', 0)
is_completed = latest_epoch >= total_epochs
```

### 续跑条件
满足以下条件的训练可以续跑：
1. ✅ 存在 `config.yml` 配置文件
2. ✅ 存在模型检查点文件 (`model_epoch*.pt`)
3. ✅ 当前epoch数 < 配置的总epoch数
4. ✅ 训练目录结构完整

## 配置文件命名建议

### 推荐的experiment_name格式
```
{task_type}_{dataset}_{model}_{optimization}_{date}
```

**示例：**
- `single_basin_camels_lstm_mse_nse_2409`
- `multi_basin_camels_gru_adam_2409`
- `full_training_camels_cudalstm_optimized_2409`

### 任务类型标识
- `single_basin` - 单流域训练
- `multi_basin` - 多流域训练  
- `full_training` - 完整训练
- `test_run` - 测试运行
- `demo` - 演示运行

### 优化标识
- `mse` - 使用MSE损失
- `nse` - 使用NSE指标
- `optimized` - 优化参数
- `gpu` - GPU训练
- `baseline` - 基线模型

## 实际案例分析

### 案例1: 完成的训练
```
test_run_mse_nse_optimized_2409_180532/
├── config.yml                    # epochs: 10
├── model_epoch001.pt            # 第1个epoch
├── model_epoch002.pt            # 第2个epoch
├── ...
├── model_epoch010.pt            # 第10个epoch ✅ 完成
├── optimizer_state_epoch001.pt
├── ...
├── optimizer_state_epoch010.pt
└── output.log                   # 显示训练正常结束
```
**状态**: ✅ 已完成 (10/10 epochs)

### 案例2: 中断的训练
```
full_training_674_basins_gpu_2409_151758/
├── config.yml                    # epochs: 50
├── model_epoch001.pt            # 第1个epoch
├── model_epoch002.pt            # 第2个epoch
├── ...
├── model_epoch005.pt            # 第5个epoch ❌ 中断
├── optimizer_state_epoch001.pt
├── ...
├── optimizer_state_epoch005.pt
└── output.log                   # 显示训练中断
```
**状态**: ❌ 可续跑 (5/50 epochs)

## 最佳实践

### 1. 命名规范
- 使用有意义的experiment_name
- 包含关键参数信息
- 避免特殊字符和空格

### 2. 目录管理
- 定期清理完成的训练
- 保留重要的训练结果
- 使用版本控制管理配置

### 3. 续跑管理
- 定期检查可续跑的训练
- 及时续跑中断的训练
- 记录续跑原因和结果

## 新命名规则的优势

### 🆕 改进点
1. **年份信息**: 增加4位年份，便于跨年管理
2. **简化时间**: 去掉秒数，只保留时分，减少冗余
3. **Epoch信息**: 在目录名中直接显示总epoch数
4. **更清晰**: 日期格式更直观 (0924 vs 2409)

### 📊 对比分析
| 特性 | 旧格式 | 新格式 | 优势 |
|------|--------|--------|------|
| 年份 | ❌ 无 | ✅ 2024 | 跨年管理 |
| 时间精度 | 秒级 | 分钟级 | 减少冲突 |
| Epoch信息 | ❌ 无 | ✅ ep10 | 快速识别 |
| 可读性 | 一般 | 更好 | 更直观 |

## 总结

NeuralHydrology的文件命名规则设计得很有逻辑性：
- 📁 **目录名**: 包含实验名、年份、日期、时间、epoch数，便于识别和管理
- 🔢 **模型文件**: 使用epoch编号，便于续跑和版本管理
- 📊 **日志文件**: 统一的命名格式，便于监控和分析
- ⚙️ **配置文件**: 标准YAML格式，便于修改和复现

理解这些命名规则有助于：
- ✅ 快速识别训练状态和规模
- ✅ 有效管理训练资源
- ✅ 正确使用续跑功能
- ✅ 组织训练实验
- ✅ 跨年管理训练历史

# NeuralHydrology 续跑训练指南

## 概述

当NeuralHydrology训练意外中断时，可以使用续跑功能从中断点继续训练，而不需要重新开始。

## 文件说明

- `quick_gpu_train_with_resume.py` - 支持续跑功能的训练脚本
- `resume_training.bat` - Windows批处理文件，一键续跑
- `RESUME_TRAINING_GUIDE.md` - 本使用指南

## 使用方法

### 方法1: 使用批处理文件 (推荐)

```bash
# 双击运行或在命令行执行
resume_training.bat
```

### 方法2: 使用Python脚本

```bash
# 自动续跑最新的中断训练
python quick_gpu_train_with_resume.py --resume

# 交互式续跑 (会显示所有可续跑的训练供选择)
python quick_gpu_train_with_resume.py

# 自动模式 (使用默认配置开始新训练)
python quick_gpu_train_with_resume.py --auto
```

### 方法3: 直接使用NeuralHydrology命令

```bash
# 续跑指定目录的训练
python neuralhydrology/nh_run.py continue_training --run-dir runs/your_run_directory --gpu 0
```

## 续跑条件

脚本会自动检测满足以下条件的训练：

1. ✅ 存在 `config.yml` 配置文件
2. ✅ 存在模型检查点文件 (`model_epoch*.pt`)
3. ✅ 当前epoch数 < 配置的总epoch数
4. ✅ 训练目录结构完整

## 检测到的可续跑训练

根据当前检测结果，发现以下可续跑的训练：

1. **full_training_674_basins_mse_nse** (Epoch 5/50)
   - 目录: `runs/full_training_674_basins_mse_nse_2409_170953`
   - 进度: 10% 完成

2. **full_training_674_basins_gpu** (Epoch 5/50)
   - 目录: `runs/full_training_674_basins_gpu_2409_151758`
   - 进度: 10% 完成

3. **test_run_3_basins_nse** (Epoch 2/5)
   - 目录: `runs/test_run_3_basins_nse_1809_222351`
   - 进度: 40% 完成

4. **test_run_nse_long** (Epoch 3/10)
   - 目录: `runs/test_run_nse_long_1809_221821`
   - 进度: 30% 完成

5. **test_run_full** (Epoch 3/50)
   - 目录: `runs/test_run_full_1309_212323`
   - 进度: 6% 完成

## 注意事项

1. **GPU内存**: 续跑时会使用与原训练相同的GPU设置
2. **学习率**: 会从检查点恢复优化器状态，包括学习率调度
3. **随机种子**: 续跑会保持训练的随机性一致性
4. **数据**: 确保训练数据仍然可用且路径正确

## 故障排除

### 问题1: 找不到可续跑的训练
- 检查 `runs/` 目录是否存在
- 确认训练确实中断了（未完成所有epoch）
- 检查模型检查点文件是否存在

### 问题2: 续跑失败
- 检查GPU是否可用
- 确认PyTorch版本兼容性
- 检查配置文件格式是否正确

### 问题3: 内存不足
- 尝试使用更小的batch_size
- 检查GPU内存使用情况
- 考虑使用CPU训练

## 高级用法

### 修改续跑参数

可以创建新的配置文件来覆盖原训练的参数：

```bash
# 创建新的配置文件
cp runs/your_run/config.yml new_config.yml

# 编辑新配置文件，修改参数
# 例如: 修改学习率、batch_size等

# 使用新配置续跑
python neuralhydrology/nh_run.py continue_training --run-dir runs/your_run --config-file new_config.yml --gpu 0
```

### 指定特定GPU

```bash
python quick_gpu_train_with_resume.py --resume --gpu 1
```

## 监控训练进度

续跑后可以通过以下方式监控进度：

1. **日志文件**: `runs/your_run/output.log`
2. **TensorBoard**: `tensorboard --logdir runs/`
3. **模型检查点**: `runs/your_run/model_epoch*.pt`

## 总结

续跑功能让您可以：
- ✅ 从中断点继续训练，节省时间
- ✅ 保持训练状态和优化器状态
- ✅ 自动检测可续跑的训练
- ✅ 灵活选择GPU和配置参数

现在您可以安全地续跑任何中断的训练了！

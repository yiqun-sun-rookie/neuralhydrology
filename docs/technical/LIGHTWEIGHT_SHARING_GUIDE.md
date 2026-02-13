# NeuralHydrology 轻量级分享指南

## 🎯 解决方案概述

为了解决完整数据集过大（~10GB）的问题，我们创建了一个轻量级的测试数据集（~50MB），让接收者可以快速验证neuralhydrology库的安装和运行。

## 📊 数据规模对比

| 数据集类型 | 流域数量 | 数据大小 | 训练时间 | 用途 |
|-----------|----------|----------|----------|------|
| **测试数据集** | 3个流域 | ~50MB | 2-10分钟 | 快速验证 |
| 演示数据集 | 4个流域 | ~500MB | 5-15分钟 | 功能演示 |
| 完整数据集 | 674个流域 | ~10GB | 数小时 | 正式训练 |

## 🚀 快速分享方案

### 方案一：轻量级分享包（推荐）

```bash
# 创建包含测试数据的轻量级分享包
zip -r neuralhydrology_light.zip \
    simple_train.py \
    neuralhydrology/ \
    configs/ \
    data/test_data/ \
    scripts/ \
    requirements*.txt \
    environments/ \
    *.md \
    --exclude="*.pyc" \
    --exclude="__pycache__" \
    --exclude="runs/" \
    --exclude="data/CAMELS_US/" \
    --exclude="data/raw/"
```

**特点：**
- 包含完整的测试数据集
- 大小约100MB（相比完整版本减少99%）
- 接收者可以直接运行测试

### 方案二：代码分享包

```bash
# 创建不包含数据的代码分享包
zip -r neuralhydrology_code.zip \
    simple_train.py \
    neuralhydrology/ \
    configs/ \
    scripts/ \
    requirements*.txt \
    environments/ \
    *.md \
    --exclude="*.pyc" \
    --exclude="__pycache__" \
    --exclude="runs/" \
    --exclude="data/"
```

**特点：**
- 仅包含代码和配置
- 大小约10MB
- 接收者需要自己准备数据

## 📁 分享包内容

### 核心文件
- `simple_train.py` - 主训练脚本
- `neuralhydrology/` - 核心库代码
- `configs/` - 配置文件目录
- `data/test_data/` - 轻量级测试数据集（仅方案一）
- `scripts/` - 数据准备和设置脚本

### 依赖管理
- `requirements.txt` - 通用依赖包列表
- `requirements-gpu.txt` - GPU版本依赖包
- `requirements-cpu.txt` - CPU版本依赖包
- `environments/` - Conda环境配置文件

### 文档
- `QUICK_START.md` - 5分钟快速上手指南
- `TEST_DATA_GUIDE.md` - 测试数据集使用指南
- `INSTALLATION_GUIDE.md` - 详细安装指南
- `PACKAGE_LIST.md` - 依赖包清单
- `SHARING_CHECKLIST.md` - 分享清单

## 🎯 接收者使用流程

### 第一步：环境准备
```bash
# 创建虚拟环境
conda create -n neuralhydrology python=3.10
conda activate neuralhydrology

# 安装依赖
pip install -r requirements-gpu.txt  # GPU版本
# 或
pip install -r requirements-cpu.txt  # CPU版本
```

### 第二步：验证安装
```python
import torch
print(f"PyTorch: {torch.__version__}")
print(f"CUDA可用: {torch.cuda.is_available()}")
```

### 第三步：运行测试

**方案一用户（有测试数据）：**
```bash
# 超快速验证（2-3分钟）
python simple_train.py --config configs/test_data/quick_test.yml

# 标准测试（5-10分钟）
python simple_train.py --config configs/test_data/test_config.yml
```

**方案二用户（无测试数据）：**
```bash
# 创建测试数据
python scripts/create_test_data.py

# 运行测试
python simple_train.py --config configs/test_data/quick_test.yml
```

### 第四步：查看结果
- 训练日志: `runs/最新目录/output.log`
- TensorBoard: `tensorboard --logdir runs/`
- 模型文件: `runs/最新目录/model_epoch_*.pt`

## 📋 测试配置说明

### quick_test.yml - 超快速验证
- **训练时间**: 2-3分钟
- **模型参数**: 最小化（hidden_size=16, epochs=3）
- **序列长度**: 10天
- **用途**: 验证安装和基本功能

### test_config.yml - 标准测试
- **训练时间**: 5-10分钟
- **模型参数**: 简化（hidden_size=32, epochs=10）
- **序列长度**: 30天
- **用途**: 验证完整训练流程

## 🎉 预期结果

### 成功标志
- 训练正常开始和结束
- 生成模型文件（.pt格式）
- 产生训练日志和图表
- NSE指标在合理范围内（0.1-0.7）

### 输出文件
```
runs/quick_test_YYYYMMDD_HHMMSS/
├── model_epoch_1.pt
├── model_epoch_2.pt
├── model_epoch_3.pt
├── output.log
├── config.yml
└── img_log/
    ├── QObsmmd_freq1D_epoch1_1.png
    ├── QObsmmd_freq1D_epoch2_1.png
    └── QObsmmd_freq1D_epoch3_1.png
```

## ⚠️ 注意事项

### 数据限制
- 测试数据集仅用于验证功能
- 模型性能不代表完整数据集表现
- 时间范围较短（1-5年）
- 流域数量有限（3个）

### 性能说明
- 测试结果仅供参考
- 完整训练需要更多数据和更长时间
- 实际应用需要调整超参数

## 🔧 故障排除

### 常见问题
1. **依赖包缺失**: 运行 `pip install -r requirements.txt`
2. **CUDA错误**: 使用 `--gpu -1` 切换到CPU
3. **数据路径错误**: 检查配置文件中的数据路径
4. **内存不足**: 减少batch_size或使用更少数据

### 获取帮助
- 查看详细文档
- 检查训练日志
- 参考故障排除指南

## 📈 下一步

### 测试成功后
1. **查看训练结果**: 分析模型性能
2. **使用TensorBoard**: 可视化训练过程
3. **尝试更大数据集**: 使用完整数据集
4. **调整参数**: 优化模型性能

### 正式使用
- 准备完整数据集
- 使用正式配置文件
- 进行长期训练
- 评估模型性能

## 🎯 总结

通过轻量级测试数据集，我们成功解决了分享大数据集的问题：

✅ **大幅减少数据大小**：从10GB减少到50MB（减少99.5%）  
✅ **保持完整功能**：验证所有核心功能  
✅ **快速验证**：2-10分钟完成测试  
✅ **易于分享**：适合网络传输  
✅ **用户友好**：提供详细文档和脚本  

这个方案让接收者可以快速验证neuralhydrology库的安装和运行，同时为后续的完整训练做好准备。

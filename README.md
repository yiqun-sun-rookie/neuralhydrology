# NeuralHydrology 深度学习水文建模库

## 🚀 快速开始

### 1. 环境要求
- Python 3.8 或更高版本
- 推荐使用 Anaconda 或 Miniconda
- 可选：NVIDIA GPU + CUDA 11.8（用于加速训练）

### 2. 安装依赖

#### 方法一：使用Conda（推荐）
```bash
# 创建虚拟环境
conda create -n neuralhydrology python=3.10
conda activate neuralhydrology

# 安装依赖（选择GPU或CPU版本）
pip install -r requirements-gpu.txt    # GPU版本
# 或
pip install -r requirements-cpu.txt    # CPU版本
```

#### 方法二：使用pip
```bash
# 创建虚拟环境
python -m venv neuralhydrology_env
# Windows:
neuralhydrology_env\Scripts\activate
# macOS/Linux:
source neuralhydrology_env/bin/activate

# 安装依赖
pip install -r requirements-gpu.txt    # GPU版本
# 或
pip install -r requirements-cpu.txt    # CPU版本
```

### 3. 验证安装
```python
import torch
print(f"PyTorch版本: {torch.__version__}")
print(f"CUDA可用: {torch.cuda.is_available()}")
```

### 4. 运行训练

> **提示**：从当前版本开始，官方入口统一为 `neuralhydrology/nh_run.py`（命令行工具 `nh-run`）。所有原先的 `simple_train.py` 示例请改用 `nh-run` 或 `python -m neuralhydrology.nh_run`。

#### 超快速验证（2-3 分钟）
```bash
python -m neuralhydrology.nh_run train --config-file configs/test_data/quick_test.yml --gpu 0
```

#### 标准测试（5-10 分钟）
```bash
python -m neuralhydrology.nh_run train --config-file configs/test_data/test_config.yml --gpu 0
```

#### 演示训练（10-20 分钟）
```bash
python -m neuralhydrology.nh_run train --config-file configs/quick_demo.yml --gpu 0
```

#### 完整训练（需要完整数据集）
```bash
python -m neuralhydrology.nh_run train --config-file configs/full_training/full_training.yml --gpu 0
```

#### 断点续训（训练意外中断后恢复）
```bash
# 自动选择最新的训练运行
python -m neuralhydrology.nh_run continue_training --run-dir runs/<latest_run>

# 从指定运行目录恢复
python -m neuralhydrology.nh_run continue_training --run-dir runs/quick_test_2025_1024_1631_ep3

# 从指定epoch恢复
python -m neuralhydrology.nh_run continue_training --run-dir runs/quick_test_2025_1024_1631_ep3 --epoch 2
```

**断点续训功能特点：**
- 🔄 自动检测可恢复的训练运行
- 📋 交互式选择界面
- 🎯 支持从指定epoch恢复
- ⚡ 智能GPU/CPU检测
- 🛡️ 完善的错误处理

### 5. 查看结果
- 训练日志：`runs/最新目录/output.log`
- TensorBoard：`tensorboard --logdir runs/`
- 模型文件：`runs/最新目录/model_epoch_*.pt`

## 📁 项目结构

```
neuralhydrology/
├── neuralhydrology/nh_run.py    # 官方训练/评估入口（可执行为 nh-run）
├── neuralhydrology/             # 核心库代码
├── configs/                     # 配置文件
│   ├── test_data/              # 测试配置
│   ├── quick_demo.yml          # 快速演示
│   └── full_training/          # 完整训练
├── data/                       # 数据目录
│   ├── test_data/             # 测试数据（~4MB）
│   ├── camels_us_demo/        # 演示数据（~14MB）
│   └── new_region/            # 新区域示例
├── scripts/                    # 工具脚本
├── requirements-gpu.txt        # GPU版本依赖
├── requirements-cpu.txt        # CPU版本依赖
└── *.md                       # 详细文档
```

## 🎯 配置文件选择

| 配置文件 | 用途 | 训练时间 | 数据大小 | 推荐场景 |
|---------|------|----------|----------|----------|
| `configs/test_data/quick_test.yml` | 超快速验证 | 2-3分钟 | ~4MB | 首次使用 |
| `configs/test_data/test_config.yml` | 标准测试 | 5-10分钟 | ~4MB | 功能验证 |
| `configs/quick_demo.yml` | 演示训练 | 10-20分钟 | ~14MB | 功能演示 |
| `configs/full_training/full_training.yml` | 完整训练 | 数小时 | ~47GB | 正式训练 |

## ⚙️ 常用参数

```bash
# 指定 GPU
python -m neuralhydrology.nh_run train --config-file configs/test_data/quick_test.yml --gpu 0

# 使用 CPU
python -m neuralhydrology.nh_run train --config-file configs/test_data/quick_test.yml --gpu -1

# 断点续训
python -m neuralhydrology.nh_run continue_training --run-dir runs/your_run_directory --gpu 0
```

## 🔧 故障排除

### 常见问题

1. **CUDA错误**
   ```
   RuntimeError: CUDA out of memory
   ```
   **解决**: 使用 `--gpu -1` 切换到CPU训练

2. **依赖包缺失**
   ```
   ImportError: No module named 'xxx'
   ```
   **解决**: 重新安装依赖 `pip install -r requirements-gpu.txt`

3. **数据路径错误**
   ```
   FileNotFoundError: [Errno 2] No such file or directory
   ```
   **解决**: 检查配置文件中的数据路径

4. **训练意外中断**
   ```
   KeyboardInterrupt 或系统崩溃
   ```
   **解决**: 使用断点续训功能恢复训练
   ```bash
   python simple_train.py --resume
   ```

### 获取帮助
- 查看详细文档：`QUICK_START.md`、`TEST_DATA_GUIDE.md`
- 检查训练日志：`runs/*/output.log`
- 使用TensorBoard：`tensorboard --logdir runs/`

## 📚 更多文档

- [快速开始指南](QUICK_START.md) - 5分钟快速上手
- [测试数据指南](TEST_DATA_GUIDE.md) - 测试数据集使用说明
- [安装指南](INSTALLATION_GUIDE.md) - 详细安装说明
- [依赖包清单](PACKAGE_LIST.md) - 完整的依赖包信息
- [分享清单](SHARING_CHECKLIST.md) - 项目分享指南

## 🎉 开始使用

1. 安装依赖包
2. 运行快速测试：`python simple_train.py --config configs/test_data/quick_test.yml`
3. 查看结果：`runs/quick_test_*/output.log`
4. 开始您的深度学习水文建模之旅！

---

**注意**: 这是一个轻量级版本，包含测试数据集。如需完整训练，请准备完整的数据集。
# NeuralHydrology 学生入门指南

## 项目概述（面向新手）

NeuralHydrology 是一个用于水文建模的深度学习库，核心目标是用神经网络预测径流（流量）。项目包含：
- 训练和评估入口：统一使用 `neuralhydrology/nh_run.py`（命令行 `python -m neuralhydrology.nh_run`）。
- 配置驱动：训练流程由 YAML 配置文件控制，存放在 `src/<idea>/configs/`。
- 数据和结果：原始数据放在 `data/`，训练输出建议按 idea 归档到 `results/<ID>_<idea>/`。
- 文档体系：主要在 `docs/`，其中 `guides/` 是面向用户的使用指南。

如果你是新手，建议先理解“配置驱动训练 + 小数据集验证”的流程，再进入 531 流域的大规模基准测试。

## 新手推荐入门的部分（以 531 流域为主线）

**推荐主线：531 Basins（CAMELS-US）基准测试**

原因：
- 训练目标清晰，能直接进入项目的核心实验线。
- 结果可与历史基线对比，便于评估进展。

需要满足：
- 完整 CAMELS-US 数据集已放在 `data/CAMELS_US`。
- 531 流域列表文件存在：`src/mamba_camels_us/data/531_basin_list.txt`。

对应配置：
- `src/mamba_camels_us/configs/mamba_daily.yml`（完整 531 流域）
- 可选快速验证：`src/mamba_camels_us/configs/mamba_daily_quick.yml`（100 流域）或 `mamba_daily_mini.yml`（50 流域）

参考资料：
- 安装与运行：`guides/INSTALLATION_GUIDE.md`
- 快速开始：`guides/QUICK_START.md`

注意：项目中旧的 `simple_train.py` 说明属于历史文档，当前推荐入口是 `nh_run`（见根目录 README 的说明）。

## 入门部分的具体步骤（可直接给学生）

### 1. 安装与环境

按照 [guides/INSTALLATION_GUIDE.md](guides/INSTALLATION_GUIDE.md) 完成环境安装。
建议优先使用 Conda + GPU 版本（如果没有 GPU 则使用 CPU 版本）。

### 2. 确认可用（先跑最小验证）

```bash
python src/test_data/scripts/create_test_data.py
```

如果想一键完成环境检查 + 数据生成 + 快速验证，可以使用：

```bash
python src/test_data/scripts/setup_test_environment.py
```

### 3. 运行 531 Basins 主线训练

确保 CAMELS-US 数据已准备好，并检查配置中的 `data_dir: data/CAMELS_US`。
在 Windows 上大小写不敏感，但在 Linux/macOS 上需要目录名与配置一致。

```bash
python -m neuralhydrology.nh_run train --config-file src/mamba_camels_us/configs/mamba_daily.yml --gpu 0
```

如果需要先做轻量验证（推荐用于确认环境/数据路径）：

```bash
python -m neuralhydrology.nh_run train --config-file src/mamba_camels_us/configs/mamba_daily_quick.yml --gpu 0
```

如果没有 GPU，可在配置文件中把 `device` 改为 `cpu`。

```bash
python -m neuralhydrology.nh_run train --config-file src/test_data/configs/quick_test.yml --gpu 0
```

如果没有 GPU：

```bash
python -m neuralhydrology.nh_run train --config-file src/test_data/configs/quick_test.yml --gpu -1
```

### 4. 查看结果

训练完成后，结果通常会归档到 `results/<ID>_<idea>/`（或配置中的 `run_dir`）：
- 日志：`logs/<ID>_<idea>/` 或 `results/<ID>_<idea>/.../output.log`
- 模型权重：`results/<ID>_<idea>/.../model_epoch_*.pt`
- TensorBoard：`tensorboard --logdir results/`

### 5. 下一步扩展

完成 531 Basins 后，可以尝试调整模型或训练设置（epochs、batch_size、hidden_size），并对比不同运行的结果表现。

## 建议的阅读顺序

1. [guides/INSTALLATION_GUIDE.md](guides/INSTALLATION_GUIDE.md)
2. [guides/QUICK_START.md](guides/QUICK_START.md)
3. 根目录 [README.md](../README.md) 了解整体结构与入口

## 常见问题（新手版）

- **GPU 报错/显存不足**：将配置中的 `device` 改为 `cpu`，或使用更小的 quick/mini 配置先验证。
- **找不到数据**：确认 `data/CAMELS_US` 路径存在且数据完整；在 Linux/macOS 上要注意目录大小写。
- **命令不生效**：确认使用 `python -m neuralhydrology.nh_run` 作为入口。

---
## 推荐阅读论文（理解库的背景）

为了更好地理解 NeuralHydrology 库的设计和方法,推荐阅读以下论文:

### 1. NeuralHydrology 库本身
- **Kratzert, F., Gauch, M., Nearing, G., & Klotz, D. (2022).** NeuralHydrology — A Python library for Deep Learning research in hydrology. *Journal of Open Source Software, 7*(71), 4050. https://doi.org/10.21105/joss.04050
  - 📌 介绍 NeuralHydrology 库的设计理念和功能

### 2. LSTM 在水文建模中的应用（核心方法）
- **Kratzert, F., et al. (2018).** Rainfall–runoff modelling using Long Short-Term Memory (LSTM) networks. *Water Resources Research, 54*(11), 8868-8884. https://doi.org/10.1029/2018WR024087
  - 📌 首次将 LSTM 应用于降雨径流建模

- **Kratzert, F., et al. (2019).** Towards learning universal, regional, and local hydrological behaviors via machine learning applied to large-sample datasets. *Hydrology and Earth System Sciences, 23*(12), 5089-5110. https://doi.org/10.5194/hess-23-5089-2019
  - 📌 基于 CAMELS-US 531 流域的大样本研究

### 3. 多时间尺度建模
- **Gauch, M., et al. (2021).** Rainfall–runoff prediction at multiple timescales with a single Long Short-Term Memory network. *Hydrology and Earth System Sciences, 25*(4), 2045-2062. https://doi.org/10.5194/hess-25-2045-2021
  - 📌 小时级和日尺度的多时间尺度建模

### 4. 数据集
- **Kratzert, F., et al. (2023).** Caravan - A global community dataset for large-sample hydrology. *Scientific Data, 10*(1), 61. https://doi.org/10.1038/s41597-023-01975-w
  - 📌 全球大样本数据集 Caravan 的介绍

建议阅读顺序:
1. 先读 **NeuralHydrology 库论文** 了解整体框架
2. 再读 **2018/2019 LSTM 论文** 理解核心方法
3. 如果做小时级研究,阅读 **Gauch 2021**

---
如果你需要进一步加入项目实验或研究任务，建议阅读 `draft/RESEARCH_INDEX.md` 了解各 idea 的最新状态与入口。


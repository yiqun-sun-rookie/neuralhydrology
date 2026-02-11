# 🚀 NeuralHydrology 项目总览 (Projects Overview)

**最后更新**: 2026-01-09
**文档结构**: 本项目分为四个独立任务，点击下方链接进入各任务详情页。

---

## 🏗️ 任务导航

| 任务板块 | 核心目标 | 当前状态 | 进度文档 |
|:---:|---|---|:---:|
| **Project A** | **Nam Ou Kuwei 流量预报**<br>高精度、多时效(1h/24h) | ✅ **已完成**<br>(Phase 1 Success) | [查看详情](./projects/project_a_namou/PROGRESS.md) |
| **Project B** | **Full 531 Basins Benchmark**<br>基于 CAMELS-US 的大规模基准测试 | ✅ **阶段完成**<br>(GRU 对比已完成) | [查看详情](./projects/project_b_full531/PROGRESS.md) |
| **Project C** | **Camelsh Hourly**<br>小时级分辨率的大样本模拟<br>🐍 **Mamba 模型研究** | 🚀 **活跃中**<br>(Mamba 研究进行中) | [总体进展](./projects/project_c_camelsh/PROGRESS.md)<br>[Mamba 研究](./projects/project_c_camelsh/MAMBA_RESEARCH.md) |
| **Project D** | **Haihe River**<br>海河流域数据健康检查 | 🛡️ **维护中**<br>(数据验证) | [查看详情](./projects/project_d_haihe/PROGRESS.md) |

---

## 🛠️ 公共资源

*   **[数据使用指南 (Data Usage Guide)](./DATA_USAGE_GUIDE.md)**: CAMELS 数据配置总结，含变量映射表，便于跨项目复用。
*   **[代码工具箱 (Code Index)](./CODE_INDEX.md)**: 所有绘图、分析脚本的说明与用法。
*   **[存储规则 (Storage Policy)](./PROJECT_STORAGE_POLICY.md)**: `configs/`/`experiments/` 与 `runs/`/`results/`/`outputs/` 的分工约定。
*   **[运行环境](./environments/)**: Conda 环境配置 (`cpu`, `cuda11_8` 等)。

---

## 📅 近期关键里程碑

*   **2026-01-09**: 🐍 启动 Project C 的 **Mamba 小时级水文模型研究**，创建完整研究文档 ([MAMBA_RESEARCH.md](./projects/project_c_camelsh/MAMBA_RESEARCH.md))
*   **2026-01-09**: 修复 Windows tqdm 兼容性问题，解决验证阶段崩溃
*   **2026-01-05**: 完成 Mamba 模型集成到 NeuralHydrology，使用 Hugging Face transformers 后端
*   **2025-12-21**: 创建 [数据使用指南](./DATA_USAGE_GUIDE.md)，完成 CAMELS 数据配置总结。
*   **2025-12-21**: 完成 Project B 的 Multihead 模型测试评估 (NSE=0.679)。
*   **2025-12-16**: 修复 MTS-LSTM 和 Multihead 配置问题。
*   **2025-12-11**: 完成项目文档重构，实现四大任务分离管理。
*   **2025-12-10**: 完成 Project B 的基线模型 (CUDA-LSTM) 评估，NSE=0.725。
*   **2025-12-09**: 启动 Project B 的 GRU 模型训练。


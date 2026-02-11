# 📦 项目存储规则（Storage Policy）

**目的**：让四大任务（Project A/B/C/D）的代码、配置、运行输出、最终成果彼此清晰分离，并且有统一的"入口文档"可追溯。

**最后更新**: 2025-12-13

---

## 1. `experiments/` vs `configs/`

- **`experiments/`（任务/项目专用，优先使用）**
  - 存放：项目自定义、可复现实验配置、实验说明、分层实验设计等。
  - 例：`experiments/namou_kuwei/configs/no_leak/...`（Nam Ou 最佳配置）
  - 例：`experiments/camelsh/configs/...`（Camelsh 小时级配置）
  - 原则：**四大任务的"活跃配置"都放这里**。

- **`configs/`（通用/模板/参考配置）**
  - 存放：通用示例、模板配置、数据切分文件、官方/通用训练配置。
  - 例：`configs/camels_us/`（531流域数据划分）、`configs/full_training/`（Full 531 模型配置）
  - 原则：作为"参考与模板"，**不承诺与四大任务一一对应**。

- **`configs/archive/`（已归档的旧版配置）**
  - 内容：历史配置、已被 `experiments/` 取代的旧版本。
  - 例：`configs/archive/namou_kuwei/`（Nam Ou 旧版 hierarchy/leadtime 配置）
  - 原则：**仅供参考，不再用于训练**。

---

## 2. `runs/` vs `results/` vs `outputs/`

- **`runs/`（训练运行目录：自动生成）**
  - 内容：每次训练/评估产生的 `config.yml`、`output.log`、`events...`、`model_epoch*.pt`、`test/...` 等。
  - 原则：**原始记录**，可回溯；不手动修改结构。

- **`docs/projects/<project>/results/`（可视化与报告的统一成果目录）**
  - 内容：用于报告/论文的最终图表（PNG/PDF）、关键摘要图等。
  - 原则：**“一处生成、多处引用”**——报告只引用这里的图。

- **`results/`（精选/发布归档，可选）**
  - 内容：你确认过的“最优模型权重/配置备份/对外分享包”。
  - 原则：只放“最终版/里程碑版”，避免与 `runs/` 重复堆积。

- **`outputs/`（临时分析产物，可选）**
  - 内容：探索性脚本的临时输出、健康检查导出、一次性 csv/png/html。
  - 原则：**不作为最终报告引用来源**；若确认为成果，应搬运/复制到对应 `docs/projects/.../results/`。

---

## 3. `scripts/` vs `tools/`

- **`scripts/`（一次性脚本、分析、绘图）**
  - 存放：绘图脚本、数据分析、训练监控、一次性处理脚本。
  - 例：`plot_531_baseline.py`、`analyze_training.py`、`check_data_leakage.py`
  - 原则：**执行后即得到结果**，不需要作为模块导入。
  - 归档：`scripts/archive/` 存放已弃用的旧版脚本。

- **`tools/`（可复用工具库）**
  - 存放：站点管理工具、配置生成器、GEE 数据提取器、流域处理工具。
  - 例：`new_site.py`（创建新站点）、`gen_config.py`、`gee/`（GEE 工具包）
  - 原则：**可被其他脚本导入或多次复用**。

---

## 4. 文档入口规则

- **总入口**：`docs/PROJECTS_OVERVIEW.md`
- **分任务进度**：`docs/projects/project_*/PROGRESS.md`
- **历史归档**：`docs/projects/project_*/archive/`



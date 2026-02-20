# 01 - Caravan Global Daily Model

**状态**: 🔄 进行中  
**创建日期**: 2026-01-21  
**最后更新**: 2026-02-18

---

## 研究目标

在 Caravan 全球数据集上预训练一个 CUDA-LSTM 日尺度基础模型，作为后续迁移学习和区域微调的 baseline，并保证任务资产与其他实验隔离。

---

## 任务隔离边界

本任务只使用以下目录（与其他任务隔离）：

- 代码与配置：`src/caravan_global/`
- 结果输出：`results/01_caravan_global/`
- 运行日志：`logs/01_caravan_global/`
- 任务文档：`draft/ideas/01_caravan_global.md`
- 索引入口：`draft/RESEARCH_INDEX.md`

约束：

- 训练使用的 basin 列表固定为 `src/caravan_global/data/valid_basins.txt`
- 不再依赖 `data/Caravan/` 下的临时分析文件

---

## 核心配置（当前）

| 参数 | 值 |
|------|-----|
| 数据集 | Caravan (全球) |
| 模型 | CUDA-LSTM (`cudalstm`) |
| Epochs | 30 |
| Batch Size | 128 |
| Seq Length | 365 |
| Hidden Size | 128 |
| Basin Count | 5281 |

---

## Code Index

| Component | Path | Description |
| :--- | :--- | :--- |
| Config | `src/caravan_global/configs/caravan_hpc.yml` | HPC 训练配置（隔离 basin 路径） |
| Smoke Config | `src/caravan_global/configs/caravan_daily_smoke_2basins_ep1.yml` | 本地最小训练验证（2 basins, 1 epoch） |
| Smoke Basins | `src/caravan_global/data/smoke_2_basins.txt` | smoke 配置用 basin 列表 |
| Smoke Config (10x3) | `src/caravan_global/configs/caravan_daily_smoke_10basins_ep3.yml` | 本地增强 smoke 验证（10 basins, 3 epochs） |
| Smoke Basins (10) | `src/caravan_global/data/smoke_10_basins.txt` | 10-basin smoke 配置用 basin 列表 |
| SLURM | `src/caravan_global/hpc/submit_caravan.slurm` | 作业提交脚本（预检与节点排除） |
| Basin List | `src/caravan_global/data/valid_basins.txt` | 训练使用的纯 basin 列表（5281） |
| Analysis | `src/caravan_global/scripts/run_local_analysis.py` | 本地数据对齐分析 |
| Verifier | `src/caravan_global/scripts/verify_basins.py` | 严格三期一致性验证 |
| Docs | `src/caravan_global/docs/data_requirements.md` | 样本定义和筛选标准 |

---

## Results Index

| Run ID | Date | Output Path | Notes |
| :--- | :--- | :--- | :--- |
| caravan_daily_smoke_10basins_ep3_2026_0218_1802_ep3 | 2026-02-18 | `results/01_caravan_global/caravan_daily_smoke_10basins_ep3_2026_0218_1802_ep3/` | 本地 CPU smoke 完成（10 basins, 3 epochs）: NSE=0.57383, KGE=0.52536 |
| caravan_daily_smoke_2basins_ep1_2026_0218_1255_ep1 | 2026-02-18 | `results/01_caravan_global/caravan_daily_smoke_2basins_ep1_2026_0218_1255_ep1/` | 本地 CPU smoke 训练完成（2 basins, 1 epoch） |
| 155573 | 2026-01-29 | 历史作业 ID | 失败：basin 文件注释行被解析为 basin ID |
| 155808 | 2026-01-31 | 历史作业 ID | 失败：xarray NetCDF backend 缺失 (`netcdf4`) |
| caravan_global_pretrain_hpc_2026_0131_2305_ep30 | 2026-01-31 | `results/01_caravan_global/` | 已创建 run 目录，训练中断待续跑 |

---

## Progress Log

| Date | Event | Details |
| :--- | :--- | :--- |
| 2026-02-18 | 本地增强 smoke 验证通过 | 使用 `src/caravan_global/configs/caravan_daily_smoke_10basins_ep3.yml` 在 CPU 上完成 10 basins/3 epochs，验证指标 NSE=0.57383, KGE=0.52536 |
| 2026-02-18 | 本地 smoke 验证通过 | 使用 `src/caravan_global/configs/caravan_daily_smoke_2basins_ep1.yml` 在 CPU 上完成 2 basins/1 epoch，验证指标 NSE=0.44622, KGE=0.50352 |
| 2026-01-21 | 项目结构创建 | 按 rules 初始化 `src/caravan_global` 与 `results/01_caravan_global` |
| 2026-01-27 | 流域筛选完成 | 基于输入-目标对齐与样本阈值筛出 5281 个有效流域 |
| 2026-01-29 | 任务失败复盘 | 发现 `valid_basins.txt` 含注释行触发 dataset 解析错误 |
| 2026-01-31 | 环境问题定位 | 发现 HPC `nh_final` 缺失 `netcdf4` 导致 xarray 读 `.nc` 失败 |
| 2026-01-31 | 隔离收口 | 训练入口改为 `src/caravan_global/data/valid_basins.txt`，同步脚本改为仅同步本任务 |

---

## 运行命令（隔离版）

```bash
# 1) 同步本任务
# 使用 src/caravan_global/hpc/winscp_sync.txt（仅同步 src/caravan_global + 本任务 idea 文档）

# 2) 提交训练
sbatch src/caravan_global/hpc/submit_caravan.slurm

# 3) 监控日志
tail -f logs/01_caravan_global/<job_id>.out
```

### 本地最小 smoke（可复现）

```bash
python -m neuralhydrology.nh_run train --config-file src/caravan_global/configs/caravan_daily_smoke_2basins_ep1.yml --gpu -1
python -m neuralhydrology.nh_run train --config-file src/caravan_global/configs/caravan_daily_smoke_10basins_ep3.yml --gpu -1
```

---

## 已知坑位（HPC）

- 节点不稳定：`ngu001, ngu201, ngu202`（已在 slurm 排除）
- `valid_basins.txt` 必须是纯列表（无注释行）
- `nh_final` 环境需有 `netcdf4`（或 `h5netcdf`）以支持 xarray 读取 NetCDF

---

## 对话交接摘要（可直接开启新对话）

### 1) 本对话的目的

本轮工作的核心目标是让 Caravan 全球训练在 HPC 上稳定跑起来，并把资产按项目规则隔离，避免与其他任务混用。

具体包括：

- 定位并修复 HPC 训练中断原因（节点、依赖、文件格式）
- 基于深度学习样本定义筛选可用流域，并确定最终时间区间
- 形成可复用的提交/同步流程
- 将代码、结果、文档收口到 `01_caravan_global` 任务边界

### 2) 最新进度（截至本次对话）

已完成：

1. **时间区间与流域筛选**
   - 时间区间固定为：
     - Train: `1981-01-01` ~ `2005-12-31`
     - Val: `2006-01-01` ~ `2010-12-31`
     - Test: `2011-01-01` ~ `2020-12-31`
   - 严格“三期一致”筛选后有效流域数：**5281**
   - 训练使用列表：`src/caravan_global/data/valid_basins.txt`（纯列表，无注释）

2. **关键故障修复**
   - 修复 `valid_basins.txt` 注释行导致的 basin 解析错误
   - 修复训练入口路径，避免读取 `data/Caravan` 的临时文件
   - 更新节点排除：`ngu001, ngu201, ngu202`
   - 定位最新报错为 xarray 缺少 NetCDF backend（`netcdf4/h5netcdf`）

3. **任务隔离**
   - 建立/更新任务索引：`draft/RESEARCH_INDEX.md`
   - 统一任务边界：
     - Code: `src/caravan_global/`
     - Results: `results/01_caravan_global/`
     - Logs: `logs/01_caravan_global/`
     - Docs: `draft/ideas/01_caravan_global.md`
   - WinSCP 同步脚本改为仅同步本任务：`src/caravan_global/hpc/winscp_sync.txt`

4. **脚本与文档更新**
   - `src/caravan_global/configs/caravan_hpc.yml`
   - `src/caravan_global/hpc/submit_caravan.slurm`
   - `src/caravan_global/scripts/verify_basins.py`
   - `src/caravan_global/scripts/run_local_analysis.py`
   - `src/caravan_global/scripts/check_basin_availability.py`
   - `src/caravan_global/README.md`
   - `results/01_caravan_global/README.md`

### 3) 当前阻塞点

最新作业日志（`155808`）显示：训练可启动、GPU 可见，但在读取 `.nc` 时崩溃：

- 报错：`xarray ... backends ['netcdf4', 'h5netcdf'] ... dependencies may not be installed`
- 结论：HPC 的 `nh_final` 环境缺 `netcdf4`（或等效后端）### 4) 下一步计划（执行顺序）

1. 在 HPC 安装依赖（一次性）：
   - `conda activate nh_final`
   - `conda install -c conda-forge netcdf4`
   - 验证：`python -c "import xarray, netcdf4; print('OK')"`

2. 同步本任务代码：
   - 执行 `src/caravan_global/hpc/winscp_sync.txt`（仅同步 `src/caravan_global` + 任务文档）

3. 重新提交训练：
   - `sbatch src/caravan_global/hpc/submit_caravan.slurm`
   - 监控：`tail -f logs/01_caravan_global/<job_id>.out`

4. 成功跑通后：
   - 记录首个完整 epoch 用时与资源占用
   - 若显存/耗时异常，再调 `batch_size`、`num_workers`、`validate_n_random_basins`

### 5) 最终目标（Definition of Done）

满足以下条件视为任务完成：

- Caravan 全球 `cudalstm` 在 5281 流域上完成 30 epoch 训练（或可稳定续跑）
- 输出目录 `results/01_caravan_global/...` 中包含完整 checkpoint 与日志
- `draft/ideas/01_caravan_global.md` 的 Results Index 与 Progress Log 完整更新
- 关键坑位与修复流程可被他人按文档复现

### 6) 新对话启动提示（可直接粘贴）> 我在做 `01_caravan_global` 任务。当前代码已隔离到 `src/caravan_global`，训练入口是 `src/caravan_global/hpc/submit_caravan.slurm`，流域列表是 `src/caravan_global/data/valid_basins.txt`（5281 行纯列表）。  
> 最新失败是 HPC 环境缺 `netcdf4`，请先帮我检查 `nh_final` 依赖并给出最短路径把训练跑起来，然后继续监控并更新 `draft/ideas/01_caravan_global.md` 的 Results Index/Progress Log。

---

## 2026-02-19 本地 Smoke 复验

- 已执行真实训练命令：  
  `python -m neuralhydrology.nh_run train --config-file src/caravan_global/configs/caravan_daily_smoke_2basins_ep1.yml`
- 训练结果：2 basins / 1 epoch / CPU 跑通。
- 输出目录：  
  `results/01_caravan_global/caravan_daily_smoke_2basins_ep1_2026_0219_1642_ep1/`
- 验证指标（epoch 1）：NSE=0.44622，KGE=0.50352。

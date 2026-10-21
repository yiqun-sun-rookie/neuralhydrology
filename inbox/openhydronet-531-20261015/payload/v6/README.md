# OpenHydroNet（Google flood-forecasting）使用说明

给其他项目用的入口页。评估结论见 `docs/technical/openhydronet_vs_nh_lstm_simulation_20261020.md`。

## 它是什么、适合什么

- Google 防洪预报团队从 NeuralHydrology 分叉出来的业务预报版（Apache-2.0，PyTorch，包名 `googlehydrology` 1.13.0，固定提交 `011265446e11`）。
- 模型：Mean-Embedding-Forecast-LSTM（现役）和 Handoff-Forecast-LSTM。核心特点：每个数据来源有自己的嵌入网络，再对各来源取**忽略缺失的平均**，所以多来源、有缺失的真实业务数据能直接喂；可以接真实天气预报（带预见期）；自带数据同化接口。
- 已验证（本仓实测）：做**模拟**时精度略低于调好的 nh LSTM（单模型约 −0.02，5 成员集成约 −0.006 NSE）；超参筛选没有补回差距。
- **没有验证**：多来源 + 缺失数据场景（它的设计目的）；用长期、大样本训练的真实预报精度。
- 适合：需要吃真实天气预报；多降水产品融合且有缺失；想用它自带的数据同化。不适合：只做单来源的模拟，nh 的 CudaLSTM 更省事、精度不输。
- 官方预训练权重**不能**拿来做 CAMELS 531 对比（530/531 个流域在它的训练集里，训练期 1982–2023 没留出段）。

## 在哪里

| 位置 | 内容 |
|---|---|
| `G:\github\pycharm\projects\flood-forecasting` | 本地克隆（conda 环境 `googlehydrology`，Python 3.12，用清华镜像 pip 装） |
| 超算 `/data1/home/sunyiq/openhydronet_shared`（只读） | 共享安装：`pysite/`、`flood-forecasting/`、`env.sh`、`run_template.slurm` |
| 超算 `/data1/home/sunyiq/openhydronet_531_20261015` | 本次实验的落点（数据、运行目录、日志）；别的项目不要写这里 |
| 本目录 `src/openhydronet_eval/` | 数据构建、评估、对拍脚本，配置，信箱命令 |

## 超算上怎么用（别的项目）

1. 在**自己的**落点目录里放配置、数据、日志；**不要**在共享目录里写东西。
2. 复制 `/data1/home/sunyiq/openhydronet_shared/run_template.slurm` 到自己的目录，改里面标 `CHANGEME` 的几处（项目目录、配置路径、分区、时长）。脚本里已 `source env.sh`，之后用 `ohn train --config-file ...`、`ohn infer --run-dir ...`。
3. 日志目录要先存在；`sbatch` 的参数写在脚本的 `#SBATCH` 行里；不要写 `--mem`（平台规则，见 `docs/hpc/HPC_PLAYBOOK.md`）。
4. 配置里必须有 `compile: False`（集群没有编译器）。

## 本地怎么用

- 激活环境 `conda activate googlehydrology`，在 `flood-forecasting` 目录下用 `run train --config-file ...`。
- Windows 上三个坑：`conda-forge` 不稳 → conda 只装 Python，其余 pip；从 Google 云盘直读数据会无限卡住 → 先用稀疏镜像脚本把需要的流域下载到本地；`torch.compile` 需要编译器 → 配置里 `compile: False`。

## 数据格式（自己造数据时）

- `attributes.zarr`：每个流域一行的属性表，每个属性一个 float32 变量。
- `streamflow.zarr`：`streamflow(basin, date)`，单位 mm/d。
- `dynamics/<产品名大写>/timeseries.zarr`：变量 `(basin, date)` 或带预见期 `(basin, date, lead_time)`；`lead_time` 是 1..N 天的时间差，第 1 个预见期在发起日当天生效。配置里 `hindcast_inputs: {产品名: [变量...]}`，变量名建议 `<产品名>_<量>`。
- 自定义产品（例如 Maurer）直接可用：产品名不在它的别名表里时，目录名取产品名的大写。样例：`scripts/build_id18_data.py`。

## 必须知道的行为

- **模型不支持纯历史输入。** 前向计算要求预报分支存在；想做模拟，就把未来几天的实测强迫当“完美预报”。输出里 `time_step τ` 对应实测日 = 发起日 d − 1 + τ；τ = 0 是严格模拟，τ = 1 的输入含当天，τ ≥ 2 才用到未来强迫（已用斜坡数据实测，见 `verification/align_probe.py`）。
- 检验时的发起日范围由数据决定；用预报产品时，GraphCast 只到 2023-12，HRES 只到 2024-09。
- 取样品均值：CMAL 头的 `streamflow_sim` 是 7500 个样本的均值。比点预测精度要用回归头 + NSE 损失，CMAL 会让 NSE 低约 0.037。
- 判断“与某模型打平”至少看 3–5 个种子的平均；单种子波动约 ±0.01。

## 文件清单

`scripts/`：`build_data.py`（官方 CAMELS-531 的数据：稀疏镜像 + USGS 流量 + 属性）、`build_id18_data.py`（ID18 协议数据）、`ohn_eval.py` / `ohn_ens_eval.py`（逐流域 NSE、集成）、`manifest_camels.py`（数据清单对拍）。`configs/`：`native531`（官方配置）、`id18_nse`、`id18_cmal`、`tune_v*`。`hpc/`：作业脚本和信箱工具。`verification/`：对拍与日期对齐测试。结果表在 `results/openhydronet_eval/`。

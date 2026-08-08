# ID26 历史连续多尺度气象 v09 主训练阶段 — 任务交接摘要

**交接时间：** 2026-08-08 21:37 (+0800)

**状态：** 严格嵌套阶段已完成并通过独立审核；主训练阶段代码已实现（S1–S5a）；
种子 100 的三个臂正在 HPC 上跑，前两个已完成，第三个进行中。

---

## 1. 最终目标与当前阶段定位

### 最终目标

在**完全相同的预测信息和评价规则**下比较三组模型，各 8 个固定随机数，共 24 次训练：

| 运行族 | 结构 | 可训练参数 | 能看到的信息 |
|---|---|---:|---|
| `B09-CLASSIC` | 隐藏宽度 256 | 297,217 | 目标日 + 此前 269 天 Maurer 气象 |
| `B09-CAPACITY` | 隐藏宽度 369 | 595,198 | **与 CLASSIC 完全相同** |
| `E09-CONTINUOUS` | 近期 256 + 历史编码器 256 | 596,737 | 近期 270 天 **+ 滞后 270–3,561 天**（池化为 120 个对数间隔 bin，每 bin 7 特征） |

`B09-CAPACITY` 的唯一作用是把"历史有用"与"参数多有用"分开：它与
`E09-CONTINUOUS` 参数量仅差 0.26%，但看不到历史。**科学上有意义的比较是
CONTINUOUS vs CAPACITY。**

24 次训练与三组集合预测全部封存后，才允许由唯一评分进程抽取一次操作系统加密随机的
256 位值，据此派生**新的** 107 流域秘密留出集与 424 流域公开集，进行一次预注册评分。

### 当前阶段及其定位

当前处于**主训练阶段**。严格嵌套（证明清洁训练实现能逐更新复现经典 256 模型）已完成
并通过，它是主训练的前置门槛，现已解除。当前正在做的是"放 24 次之前先跑种子 100 的
三个臂做链路验证"。

---

## 2. 必须遵守的限制、成功标准与停止条件

### 硬限制

- 不生成正式预测、不评分、不读取正式评价期观测（1989-10-01 至 1999-09-30）。
- 不修改冻结协议、封存输入、严格嵌套已封存产物。
- 不移动 `~/v09_strict/neuralhydrology` 的 Git HEAD（见第 5 节）。
- 不向 HPC 的 conda 环境 `nh_final` 安装任何包（其他会话的实验正在使用）。
- 24 次训练必须串行（协议规定），`_MAIN_ORDER` 是固定顺序，不得并行或改序。

### 已被推翻的旧限制（重要）

原设计要求主训练消费一次性授权收据 `A09-TRAIN-01`（`maximum_attempts=1`）。
**该机制已于 2026-08-08 经用户批准废弃**，理由：24 次训练约数十小时、跨多个调度作业，
一次中断即烧毁收据并困住所有已完成运行（严格嵌套阶段在本地已实际发生：一次 2 MB
内存抖动烧掉整个授权，56 分钟白跑）。

科学保证不依赖该锁，而依赖：冻结协议、封存并哈希的输入、冻结的运行顺序、
以及"全部预测封存后才抽取"的秘密留出集——这些一条未动。

**新对话不要重新引入授权收据机制。** 编排器源码中已有测试断言不含任何授权字样。

### 单次训练的成功判据

- 参数量分别为 297,217 / 595,198 / 596,737；
- 30 轮、每轮 6,821 步、共 204,630 次优化更新；训练样本 1,745,928；
- 检查点固定在第 10、20、30 轮；
- `E09-CONTINUOUS` 专有：第 1 步两个历史门严格为 0、历史编码器梯度严格为 0、
  两门合并梯度范数严格大于 0；第 3 步结束前历史编码器出现非零有限梯度；
- 训练损失有限且下降；
- `formal_evaluation_observation_reads = 0`。

### 停止条件

任一运行子进程非零退出、封存失败、哈希漂移、出现 `.building` 或 `.failed` 目录时，
编排器**停止后续运行、保留已完成运行、不自动重试、不自动清理**，写
`training_attempt_01.failure.json`。半写目录必须由人判断后处理。

---

## 3. 已完成的有效方案与关键结果

### 3.1 严格嵌套阶段（已完成，通过）

在 HPC 执行，全部判据满足且优于判据：

| 判据 | 要求 | 实测 |
|---|---|---|
| 同进程 classic vs nested 差值 | 全 0 | **0.0** |
| 独立重放最大差 | ≤ 1e-6 | **0.0**（严格相等） |
| 优化更新数 | 204,630 | 204,630 |
| 训练样本 | 1,745,928 | 1,745,928 |
| 30 轮排列哈希重算 | 全部一致 | 30/30 |
| 正式评价观测读取 | 0 | 0 |

- 训练作业 `201718` @ ngu008，耗时 **01:56:07**，`strict_nesting_complete`
- 审核作业 `201740` @ ngu010，耗时 00:02:24，
  `strict_nesting_checkpoint_prediction_replay_passed`
- 旧模型桥接：8 个随机数、50,976 行真实面板、`maximum_prediction_difference = 0.0`

### 3.2 跨环境 bit-exact 成立（重要，消除了一个风险）

本地 torch 2.2.2 / numpy 1.26.4 / RTX 4070 Ti → HPC torch **2.4.0** / numpy **2.3.3** /
RTX 3090，桥接 50,976 行仍严格 0.0。**跨 torch 版本、跨 GPU 型号不是风险点。**

### 3.3 资源预检（S3，已完成，GPU 实测通过）

四种工作负载 × 两个一次性 GPU 子进程，除峰值显存外全部数组哈希相同：

| 负载 | 一致 | peak allocated | peak reserved |
|---|---|---:|---:|
| strict_nesting_pair | 是 | 984 MiB | 1142 MiB |
| classic_lstm_256_clean | 是 | 979 MiB | 1120 MiB |
| classic_lstm_369_capacity | 是 | 1363 MiB | 1610 MiB |
| continuous_multiscale_history | 是 | 1165 MiB | 1402 MiB |

环境：RTX 3090 / torch 2.4.0 / cuDNN 9.1.0。冻结开关
`cudnn_deterministic=true`、`cudnn_benchmark=false`、
`deterministic_algorithms_requested=true`、`CUBLAS_WORKSPACE_CONFIG=:4096:8`。

**结论：cuDNN LSTM 反向在独立进程间确定。显存不构成约束**（协议要求启动前可用显存
≥ `max(2×峰值, 峰值+2 GiB)`，最严一档 3,450 MiB，3090 空闲 24 GB）。

### 3.4 主训练阶段代码（S1–S5a 已实现并提交）

| 阶段 | 内容 | 状态 |
|---|---|---|
| S1 | 冻结 24 项运行顺序 + dropout 随机数流 | 完成 |
| S2 | 单运行训练器（含历史门机制级门禁） | 完成 |
| S3 | 资源预检（结构性隔离，无法接收路径参数） | 完成，GPU 实测通过 |
| S4 | 可断点续跑的串行编排器（无一次性锁） | 完成 |
| S5a | 预注册状态诊断（面板/五列/汇总） | 完成 |
| S5b | 24 次总审核 + 总封存 | **未做** |

本地测试：685 通过。另有 **2 个既有失败**（见第 6 节），与本工作无关。

### 3.5 当前进行中的种子 100 三臂验证

作业 `201861` @ ngu011，2026-08-08 约 15:40 启动，`--max-runs 3`：

| 臂 | 状态 | 参数量 | 步数 | 训练损失 ep1 → ep30 |
|---|---|---:|---:|---|
| classic/seed_100 | 完成 | 297,217 | 204,630 | 0.04088 → 0.01017 |
| capacity/seed_100 | 完成 | 595,198 | 204,630 | 0.03614 → 0.00855 |
| continuous/seed_100 | **进行中** | — | — | — |

注：以上是**训练损失**，不是验证指标，不能据此判断泛化能力。capacity 损失更低
仅反映参数量翻倍后对训练数据拟合更好。

---

## 4. 影响后续判断的科学事实与失败实验

### 效应量（决定这个实验值不值得）

v08 在冻结的 60 流域内部筛选（三随机数集合）：

- 相对 `B09-CLASSIC`：中位差 **+0.015203**
- 相对 `B09-CAPACITY`（参数拉平）：中位差 **+0.003593**
- 胜率 42/60；95% 自助区间 `[+0.006702, +0.022880]`
  （**该区间对应的是相对 CLASSIC 那一条，参数拉平那条没有区间证据**）

**参数拉平后只有 +0.0036，且无置信区间。** 531 流域正式评价的泛化性由项目自身审核判为
`HOLD`。建议按**负结果实验**准备叙事，不要按 +0.015 设定预期。

### 已失败的结构（不要重试）

- **v05 分层高信息量历史**：60 流域随机数 100 下，相对经典 −0.039934，
  相对参数量控制 −0.036840，胜率 20/60，四门槛全败。
- **v07 由远到近状态传递**：相对经典 +0.001398，相对参数量控制 **−0.007735**，
  胜率 32/60，四门槛全败。

三次结构尝试中仅 v08 勉强过线。

### 其他已确认事实

- 旧八随机数经典集合中位 NSE `0.759225`，仅作历史评分参考，不能当作清洁同信息训练基线。
- Maurer 最低温与最高温在全部 5,576,031 个流域日完全相同。已确认，按冻结协议原样保留，
  **禁止事后修补**。
- 原 107 流域留出集已被同一 424/107 划分评分 7 次并进入研究反馈，**不能再当秘密留出集**。

---

## 5. 准确路径与环境

### 本地

- 工作区：`G:\github\pycharm\projects\neuralhydrology\.worktrees\historical-band-experts-pilot`
- 分支：`codex/historical-band-experts-pilot`
- 当前 HEAD：`bb519b8b9980725ac1d5f4e298d76ae80ea2c58d`（已推送到远端同名分支）
- 提交链（新→旧）：
  `bb519b8b` S5a 状态诊断 → `2e87f4a5` S4 编排器 → `ccb01978` S3 结果文档 →
  `c9bcfb4e` CUDA 初始化修复 → `abdeb4bd` S3 资源预检 → `4ab591db` S2 单运行训练器 →
  `002ed231` S1 冻结顺序 → `f9418320` 严格嵌套修复

### 主要源码文件（均在 `src/26_historical_band_experts/`）

| 文件 | 作用 |
|---|---|
| `configs/formal_v09_protocol.json` | 冻结协议，文件 SHA-256 `2a018755422eb102259eba11558bc190ba11034d3390f64df7bbc54e8756a0f7` |
| `configs/formal_v09_run_order.json` | 冻结的 24 项运行顺序 |
| `train_formal_v09.py` | 运行顺序验证器、dropout 流、单运行训练器 |
| `run_formal_training_v09.py` | 可断点续跑的串行编排器（含 worker CLI） |
| `resource_preflight_formal_v09.py` | 四负载 × 双子进程资源预检 |
| `state_diagnostics_formal_v09.py` | 预注册状态诊断 |
| `train_strict_formal_v09.py` / `audit_strict_formal_v09.py` | 严格嵌套阶段（已完成，勿改） |
| `prepare_formal_strict_stage_v09.py` / `create_formal_strict_authorization_v09.py` / `audit_formal_strict_stage_v09.py` | 严格嵌套三入口（已用完） |

规格文档：
- `docs/superpowers/plans/2026-07-31-historical-multiscale-formal-v09-training-stage.md`
  （Task 5/6 是主训练与总审核的原始规格）
- `docs/technical/historical_multiscale_formal_v09_state_diagnostics_preregistration.md`
  （状态诊断预注册，面板/五列定义的唯一权威）
- `docs/plans/2026-08-07-id26-v09-main-training-implementation.md`（S1–S5 实现计划与状态）

### HPC

- 主机 `hpcbh.hhu.edu.cn`，用户 `sunyiq`，登录节点 `login4`，SLURM，CentOS 7，**有偿计费**
- conda 环境 `nh_final` = Python 3.11.13 + torch 2.4.0 + numpy 2.3.3
- GPU 分区主力 `hgpu2p`（9 节点 × 2 × RTX 3090 24 GB）；**坏节点 `ngu002` 必须
  `--exclude=ngu002`**
- 存储 `/data1` 余 364 TB

HPC 目录：

| 路径 | 内容 | 注意 |
|---|---|---|
| `~/v09_strict/neuralhydrology` | 严格嵌套已封存证据 | **HEAD 必须保持 `f9418320`**，其消费回执记录了该提交，移动会造成审核漂移 |
| `~/v09_strict/codetest/neuralhydrology` | 主训练代码与结果 | 当前 HEAD `bb519b8b`，训练结果落在此树 |
| `~/v09_strict/gitenv` | 独立 git 2.55.0 | **计算节点没有 git**，slurm 中必须 `export PATH=$GITENV/bin:$PATH` |
| `~/v09_strict/jobs` / `~/v09_strict/logs` | slurm 脚本与日志 | |
| `~/v09_strict/upload_archive/v09_sealed_input.tar.gz` | 封存输入归档，SHA-256 `feee746c7bda7970c8bac470969bf4247118f8f35d6cf543a44a8a6b4bd1bed7` | 79 MB，解开后 19 个文件 |
| `~/v09_strict/suite_jobid.txt` | 当前套件作业号（`201861`） | |

训练结果落点（在 codetest 树内）：

```
results/26_historical_band_experts/formal_v09/classic/seed_<seed>/
results/26_historical_band_experts/formal_v09/capacity/seed_<seed>/
results/26_historical_band_experts/formal_v09/continuous/seed_<seed>/
```

临时目录 `seed_<seed>.building`，失败目录 `seed_<seed>.failed`。

### HPC 通信方式（重要）

**堡垒机挡死一切直连自动化；登录需要静态密码 + 手机动态码，无法自动化。**
唯一可用通道是 Git 信箱：HPC 上的守护进程每 20 秒从 GitHub 分支 `hpc-mailbox` 拉命令。

- 本地信箱工作区：`G:\github\pycharm\projects\neuralhydrology\.worktrees\hpc-mailbox`
- 本任务专用 channel：**`id26-v09-strict`**，当前 seq **20** 已发出（下一条用 **21**）
- 用法：改 `inbox/id26-v09-strict/cmd.sh`，`printf '<N>' > inbox/id26-v09-strict/seq`，
  提交时加 `-c core.autocrlf=false`，`git pull --rebase` 后 push；
  结果出现在 `outbox/id26-v09-strict/result_<N>.txt`
- 规则见分支内 `CHANNELS.md`：只改自己 channel，不碰别人的

**信箱三条必须遵守的操作教训：**

1. **命令必须"提交即返回"，绝不写长等待循环。** 单条命令超过 2 小时会被 `timeout` 杀掉
   且结果推不出来；更严重的是守护进程只在**没有任何 worker 运行时**才 `git reset --hard`
   更新工作区，长等待会让整个信箱（含其他会话）看不到新命令。
2. `cmd.sh` 里**禁止跑计算**（平台明令），重活一律 `sbatch`。
3. slurm 脚本禁止写 `--mem`；用 `set -eo pipefail` 但**不要加 `-u`**；
   必须 `export MKL_THREADING_LAYER=GNU`；日志目录必须先 `mkdir -p`；
   注意 CRLF（用 `sed -i 's/\r$//'`）。

---

## 6. 已确认与已排除的问题

### 已确认

1. **本地工作站不适合跑这个实验。** 本地严格嵌套跑到第 11 轮被自己的内存安全门拦停：
   `available physical memory below task reserve: 2145243136 < 2147483648`。
   根因是**其他会话在同一台机器起了 28 进程的作业**（当时 42 个 python 进程占 19.5 GB）。
   协议假设独占，工作站保证不了。HPC 的价值是**隔离**不是速度（消费回执记录 ngu008
   可用内存 257 GB）。
2. **计算节点没有 git**，而 v09 三处门禁都调 git。已建独立环境 `~/v09_strict/gitenv`。
3. `nh_final` **没有装 pytest**，且不应安装（其他会话在用）。
4. **2 个既有测试失败与本工作无关**：
   `tests/test_build_formal_inputs_v09.py::test_public_formal_entry_has_no_path_or_resource_injection_and_fails_without_authorization`
   与 `::test_public_formal_entry_checks_each_exact_sensitive_path`。
   原因是它们断言正式输入入口因"缺授权"报错，但实际更早就因消费回执
   `formal_input_seal_authorization_consumed.json` 已存在（写于 2026-08-01 11:15）而报
   `FileExistsError`。这是测试耦合了生产状态的设计缺陷，与主训练代码无关。

### 已排除

- 跨 torch 2.2.2→2.4.0、numpy 1.26→2.3、4070 Ti→3090 的 bit-exact 不成立 —— 已实测排除。
- cuDNN LSTM 反向非确定性 —— 已实测排除（四负载双进程全部一致）。
- 显存不足 —— 已实测排除（最大 1610 MiB reserved，3090 有 24 GB）。
- 主机内存不足（在 HPC 上）—— ngu008 实测可用 257 GB。

### 未验证 / 仍不确定

- **`E09-CONTINUOUS` 的历史门在真实 531 流域数据上是否按预期唤醒**（合成数据上成立：
  第 1 步门梯度 > 0、编码器梯度 = 0，3 步内唤醒）。**这是当前最关键的未验证项。**
- **24 次训练的真实总时长。** 早前"约 34 小时"的估计**已知偏乐观**：该估计基于严格嵌套
  配对（两个模型共用一次数据加载），而独立运行要各自付一遍取窗口开销。实测 classic 与
  capacity 各约 1.3–1.5 小时（未精确计时）。continuous 因需取整个 3,562 天窗口（数据搬运
  量约为近期臂的 13 倍）明显更慢：约 19:10 开始，截至 **21:40 已跑约 2.5 小时仍未完成**
  （作业总 elapsed 06:00:06）。**新的总时长必须用实测重算，早前的 34 小时估计已作废。**
  若 continuous 单臂约 3 小时，则 8×classic + 8×capacity + 8×continuous 粗估 **45–50 小时**，
  须按实测修正。
- 连续历史候选能否在 531 流域正式评价中超过两个清洁对照。
- 冻结赛道规范文件存在换行/字节哈希三态不一致（清单
  `1beb31af1e7d1131370ffe6c3f829b897869599cb75dbd42917265da0e1a9c00`、Windows 字节
  `8fb707cb5e2ec0f8edbf3f191f9ce836d259e8a31286466da63e6e62791388fb`、换行标准化
  `0439eb55cd059300eca9c90c20aaed1901cd8be5e9b556bd4ae2e4609a2f5d5e`）。
  必须在评分授权前解决，但不得修改冻结文件。**不阻塞主训练。**

---

## 7. 未完成事项、阻塞原因与最优先下一步

### 未完成

1. `E09-CONTINUOUS-S100` 训练进行中（作业 201861）。
2. 剩余 21 次训练未启动。
3. **S5b 未实现**：24 次总审核（`audit_formal_training_v09.py`）与总封存
   （`seal_training_suite_v09`）。规格见
   `docs/superpowers/plans/2026-07-31-historical-multiscale-formal-v09-training-stage.md`
   Task 6。当时的判断是：其价值低于前几段，且部分拒绝条件依赖尚未编写的评分环节，
   等 24 次跑完再补更靠谱。
4. 正式预测、评分、状态诊断的实际执行均未开始（且未获授权）。

### 阻塞原因

无技术阻塞。当前等待 `E09-CONTINUOUS-S100` 完成。

### 最优先的下一步

1. 查询作业 `201861` 状态，取 `continuous/seed_100/manifest.json`。
2. **验四项**：参数量 = 596,737；步数 = 204,630；
   `history_encoder_first_nonzero_gradient_step` ∈ {2, 3}；
   `history_health_trace[0]` 满足 `gate_absolute_maximum == 0.0`、
   `history_encoder_gradient_norm == 0.0`、`gate_gradient_norm > 0`。
3. 四项全过 → 用三个臂的实测耗时重算 24 次总时长，报告给用户，再启动剩余 21 次
   （编排器不带 `--max-runs` 即可，会自动跳过已完成的 3 个）。
4. 任一项不过 → **停止，不启动剩余 21 次**，报告差异并排查合成测试为何未暴露该问题。

---

## 8. 新对话应首先检查的文件与执行的命令

### 先读

1. 本文件
2. `docs/plans/2026-08-07-id26-v09-main-training-implementation.md`（S1–S5 状态）
3. `docs/technical/historical_multiscale_formal_v09_state_diagnostics_preregistration.md`
4. `src/26_historical_band_experts/run_formal_training_v09.py`（编排器语义）
5. 信箱分支内的 `CHANNELS.md`

### 本地只读核验

```bash
cd "G:/github/pycharm/projects/neuralhydrology/.worktrees/historical-band-experts-pilot"
git rev-parse --abbrev-ref HEAD          # 期望 codex/historical-band-experts-pilot
git rev-parse HEAD                       # 期望 bb519b8b9980725ac1d5f4e298d76ae80ea2c58d
git status --short                       # 期望空
python -m pytest src/26_historical_band_experts/tests -q
# 期望 685 passed, 2 failed（那 2 个见第 6 节，与本工作无关）
```

### 查询 HPC 上的运行状态（走信箱，seq 用 21；seq=20 已于 21:39 发出，先看它的结果）

```bash
cd "G:/github/pycharm/projects/neuralhydrology/.worktrees/hpc-mailbox"
git fetch origin hpc-mailbox && git reset --hard origin/hpc-mailbox
cat inbox/id26-v09-strict/seq            # 确认当前 seq，下一条用 +1
```

写 `inbox/id26-v09-strict/cmd.sh`（**必须提交即返回，不要写长等待循环**）：

```bash
#!/bin/bash
export LC_ALL=C
ROOT=/data1/home/sunyiq/v09_strict
CODE=$ROOT/codetest/neuralhydrology
PY=$HOME/miniconda3/envs/nh_final/bin/python
JID=$(cat "$ROOT/suite_jobid.txt" 2>/dev/null || echo 201861)
echo "=== JOB ==="
sacct -j "$JID" -X --format=JobID%10,State%12,ExitCode%8,Elapsed%12 2>&1 | head -4
echo "=== DIRS ==="
find "$CODE/results/26_historical_band_experts/formal_v09" -maxdepth 2 -name 'seed_*' 2>/dev/null | sed 's|.*formal_v09/||' | sort
echo "=== ARMS ==="
cd "$CODE"
$PY - <<'PY' 2>&1 | tail -20
import json, pathlib
base = pathlib.Path.cwd()/"results/26_historical_band_experts/formal_v09"
for family in ("classic", "capacity", "continuous"):
    m = base/family/"seed_100"/"manifest.json"
    if not m.is_file():
        print(f"{family:11s}: not finished"); continue
    d = json.loads(m.read_text(encoding="utf-8"))
    print(f"{family:11s}: {d['status']} params={d['trainable_parameters']} steps={d['optimizer_steps_total']} "
          f"wake={d.get('history_encoder_first_nonzero_gradient_step')} "
          f"loss {d['epoch_trace'][0]['mean_training_loss']:.5f} -> {d['epoch_trace'][-1]['mean_training_loss']:.5f}")
    if d.get("history_health_trace"):
        h = d["history_health_trace"][0]
        print(f"             step1 gate_abs_max={h['gate_absolute_maximum']} enc_grad={h['history_encoder_gradient_norm']} "
              f"gate_grad={h['gate_gradient_norm']:.6g}")
PY
echo "=== END ==="
```

推送：

```bash
printf '21' > inbox/id26-v09-strict/seq
git add -A
git -c core.autocrlf=false commit -q -m "mailbox[id26-v09-strict]: seq=21 status query"
git fetch origin hpc-mailbox -q && git rebase -q origin/hpc-mailbox
git push origin HEAD:hpc-mailbox
```

取结果（可能需要等其他 channel 的 worker 结束）：

```bash
git fetch origin hpc-mailbox -q
git show origin/hpc-mailbox:outbox/id26-v09-strict/result_20.txt   # 或 result_21.txt
```

### 启动剩余 21 次的命令（**四项验证通过后才可执行**）

在 HPC 上通过 sbatch 提交，slurm 脚本核心内容：

```bash
export PATH=/data1/home/sunyiq/v09_strict/gitenv/bin:$PATH
export MKL_THREADING_LAYER=GNU
export CUBLAS_WORKSPACE_CONFIG=:4096:8
cd /data1/home/sunyiq/v09_strict/codetest/neuralhydrology
export PYTHONPATH=$(pwd):$(pwd)/src/26_historical_band_experts:$PYTHONPATH
python -u src/26_historical_band_experts/run_formal_training_v09.py \
  --worktree-root . --device cuda:0
```

（不带 `--max-runs` 即跑完全部剩余；已完成的 3 个会被自动跳过。
SBATCH 需含 `-p hgpu2p --gres=gpu:1 --exclude=ngu002`，时限按重算后的总时长设置，
不得写 `--mem`。断线后重新提交同一脚本即可续跑。）

---

## 附：给用户汇报时的口径提醒

- 用户明确要求：**回答末尾必须有独立的"结论"段；去掉过程性叙述；不要让技术细节淹没结论；
  尽量精简。** 崩溃/失败报告尤其要把结论放最前面。
- 用户对协议黑话（授权、一次性消费、封印）不熟且明确表达过困惑，**不要直接使用这些术语，
  必须先用大白话解释**。
- 汇报效应量时必须用 **+0.0036（参数拉平）**，不要用 +0.015。
